# Internal extraction boundary for future fit implementations.
extract_external_stan_fit <- function(fit, checks = "all", strict = TRUE, ...) {
  UseMethod("extract_external_stan_fit", fit)
}

#' @exportS3Method
extract_external_stan_fit.stanfit <- function(
  fit,
  checks = "all",
  strict = TRUE,
  ...
) {
  extract_rstan_fit(fit, checks = checks, strict = strict, ...)
}

#' @exportS3Method
extract_external_stan_fit.CmdStanMCMC <- function(
  fit,
  checks = "all",
  strict = TRUE,
  ...
) {
  extract_cmdstanr_fit(fit, checks = checks, strict = strict, ...)
}

#' @exportS3Method
extract_external_stan_fit.default <- function(fit, ...) {
  stop(
    "Unsupported Stan fit object; expected a completed rstan::stanfit or cmdstanr::CmdStanMCMC object.",
    call. = FALSE
  )
}

extract_cmdstanr_fit <- function(fit, checks = "all", strict = TRUE, ...) {
  draws <- tryCatch(
    fit$draws(inc_warmup = FALSE, format = "draws_array"),
    error = function(error) {
      stop(
        "Could not read posterior draws from the cmdstanr fit's CSV files: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
  draws <- tryCatch(posterior::as_draws_array(draws), error = function(error) {
    stop(
      "Could not convert cmdstanr draws to a posterior draws_array: ",
      conditionMessage(error),
      call. = FALSE
    )
  })
  need_sampler <- "all" %in%
    checks ||
    any(checks %in% c("divergent_transitions", "efmi"))
  sampler_diagnostics <- if (need_sampler) {
    tryCatch(
      fit$sampler_diagnostics(inc_warmup = FALSE, format = "draws_array"),
      error = function(error) {
        if (strict) {
          stop(
            "Could not read sampler diagnostics from the cmdstanr fit's CSV files: ",
            conditionMessage(error),
            call. = FALSE
          )
        }
        NULL
      }
    )
  } else {
    NULL
  }
  sampler_diagnostics <- if (!is.null(sampler_diagnostics)) {
    tryCatch(
      posterior::as_draws_array(sampler_diagnostics),
      error = function(error) {
        if (strict) {
          stop(
            "Could not convert cmdstanr sampler diagnostics: ",
            conditionMessage(error),
            call. = FALSE
          )
        }
        NULL
      }
    )
  } else {
    NULL
  }
  if (
    !is.null(sampler_diagnostics) &&
      !identical(dim(sampler_diagnostics)[1:2], dim(draws)[1:2])
  ) {
    stop(
      "The cmdstanr fit has inconsistent post-warmup sampler diagnostics dimensions.",
      call. = FALSE
    )
  }
  sampler_invalid <- need_sampler &&
    (is.null(sampler_diagnostics) ||
      !"divergent__" %in% posterior::variables(sampler_diagnostics))
  if (sampler_invalid) {
    if (strict) {
      stop(
        "The cmdstanr fit has incomplete or inconsistent post-warmup sampler diagnostics.",
        call. = FALSE
      )
    }
  }
  metadata <- tryCatch(fit$metadata(), error = function(error) {
    stop(
      "Could not read metadata from the cmdstanr fit's CSV files: ",
      conditionMessage(error),
      call. = FALSE
    )
  })
  if (!is.list(metadata)) {
    stop("The cmdstanr fit returned invalid CSV metadata.", call. = FALSE)
  }
  nchains <- posterior::nchains(draws)
  retained_iterations <- dim(draws)[1L]
  retained_draws <- posterior::ndraws(draws)
  iter_sampling <- cmdstanr_metadata_value(
    metadata,
    c("iter_sampling", "iterations_sampling"),
    retained_iterations
  )
  warmup <- cmdstanr_metadata_value(
    metadata,
    c("iter_warmup", "warmup", "num_warmup"),
    0L
  )
  thin <- cmdstanr_metadata_value(metadata, "thin", 1L)
  max_treedepth <- cmdstanr_metadata_value(
    metadata,
    c("max_depth", "max_treedepth"),
    10
  )
  bfmi <- if ("all" %in% checks || "efmi" %in% checks) {
    tryCatch(
      cmdstanr_bfmi(sampler_diagnostics, nchains, strict = strict),
      error = function(error) {
        if (strict) {
          stop(conditionMessage(error), call. = FALSE)
        }
        NULL
      }
    )
  } else {
    NULL
  }
  metadata <- list(
    nchains = as.integer(nchains),
    chains = as.integer(nchains),
    total_iterations = as_integer_or_null(
      as.numeric(iter_sampling) + as.numeric(warmup)
    ),
    iter = as_integer_or_null(as.numeric(iter_sampling) + as.numeric(warmup)),
    warmup_iterations = as_integer_or_null(warmup),
    warmup = as_integer_or_null(warmup),
    retained_iterations = as.integer(retained_iterations),
    retained_draws = as.integer(retained_draws),
    ndraws = as.integer(retained_draws),
    thin = as_integer_or_null(thin),
    sampler_arguments = cmdstanr_sampler_arguments(metadata),
    model_name = cmdstanr_metadata_value(metadata, "model_name", NULL),
    stan_version = cmdstanr_stan_version(metadata),
    cmdstanr_version = paste("cmdstanr", utils::packageVersion("cmdstanr")),
    # CmdStan writes its own release version as stan_version_* in the CSV header.
    cmdstan_version = if (
      !is.null(stan_version <- cmdstanr_stan_version(metadata))
    ) {
      sub("^Stan ", "CmdStan ", stan_version)
    },
    posterior_version = paste("posterior", utils::packageVersion("posterior")),
    r_version = R.version$version.string,
    sampling_timestamp = cmdstanr_metadata_value(
      metadata,
      c("start_datetime", "start_time"),
      NULL
    ),
    max_treedepth = as.numeric(max_treedepth),
    expected_fraction_of_missing_information = bfmi
  )
  metadata <- drop_null_list_elements(metadata)
  metadata$method_arguments <- cmdstanr_method_arguments(metadata)
  list(
    draws = draws,
    sampler_diagnostics = sampler_diagnostics,
    metadata = metadata
  )
}

cmdstanr_metadata_value <- function(metadata, names, default = NULL) {
  names <- as.character(names)
  for (name in names) {
    value <- metadata[[name]]
    if (!is.null(value) && length(value) > 0L && !all(is.na(value))) {
      return(value[[1L]])
    }
  }
  default
}

cmdstanr_stan_version <- function(metadata) {
  parts <- vapply(
    c("stan_version_major", "stan_version_minor", "stan_version_patch"),
    function(name) {
      as.character(cmdstanr_metadata_value(metadata, name, NA_character_))
    },
    character(1)
  )
  if (anyNA(parts)) {
    return(cmdstanr_metadata_value(metadata, "stan_version", NULL))
  }
  paste("Stan", paste(parts, collapse = "."))
}

sampler_diagnostics_bfmi <- function(
  sampler_diagnostics,
  nchains,
  strict = TRUE,
  normalization = c("differences", "draws")
) {
  normalization <- match.arg(normalization)
  if (!"energy__" %in% posterior::variables(sampler_diagnostics)) {
    if (strict) {
      stop(
        "Sampler diagnostics have no `energy__` variable for E-FMI.",
        call. = FALSE
      )
    }
    return(NULL)
  }
  bfmi <- vapply(
    seq_len(nchains),
    function(chain) {
      energy <- sampler_diagnostics[, chain, "energy__"]
      denominator <- stats::var(energy)
      if (length(energy) < 2L || !is.finite(denominator) || denominator <= 0) {
        return(NA_real_)
      }
      # CmdStan uses n-1 differences; RStan divides by n retained draws.
      numerator <- if (normalization == "draws") {
        sum(diff(energy)^2) / length(energy)
      } else {
        mean(diff(energy)^2)
      }
      numerator / denominator
    },
    numeric(1)
  )
  if (strict && (anyNA(bfmi) || any(!is.finite(bfmi)))) {
    stop(
      "Sampler diagnostics have missing or invalid per-chain E-FMI values.",
      call. = FALSE
    )
  }
  bfmi
}

rstan_sampler_bfmi <- function(sampler_diagnostics, nchains, strict = FALSE) {
  sampler_diagnostics_bfmi(
    sampler_diagnostics,
    nchains,
    strict,
    normalization = "draws"
  )
}

cmdstanr_bfmi <- function(sampler_diagnostics, nchains, strict = TRUE) {
  sampler_diagnostics_bfmi(sampler_diagnostics, nchains, strict)
}

cmdstanr_sampler_arguments <- function(metadata) {
  args <- metadata[intersect(
    names(metadata),
    c(
      "num_chains",
      "iter_sampling",
      "iter_warmup",
      "thin",
      "save_warmup",
      "seed",
      "algorithm",
      "method",
      "max_depth",
      "refresh",
      "parallel_chains"
    )
  )]
  args <- lapply(args, sanitize_metadata_value)
  args <- drop_null_list_elements(args)
  if (!length(args)) NULL else args
}

cmdstanr_method_arguments <- function(metadata) {
  keep <- c("chains", "iter", "warmup", "thin", "sampling_timestamp")
  metadata[intersect(keep, names(metadata))]
}

# Sampler access and conversion are one optional diagnostics boundary. In
# tolerant report mode either failure yields unavailable metrics; legacy imports
# retain the strict error behavior.
extract_rstan_sampler_diagnostics <- function(fit, strict = TRUE) {
  tryCatch(
    {
      sampler_params <- rstan::get_sampler_params(fit, inc_warmup = FALSE)
      sampler_params_to_draws_array(sampler_params)
    },
    error = function(error) {
      if (strict) {
        stop(
          "Could not extract post-warmup sampler diagnostics: ",
          conditionMessage(error),
          call. = FALSE
        )
      }
      NULL
    }
  )
}

extract_rstan_fit <- function(fit, checks = "all", strict = TRUE, ...) {
  draws <- tryCatch(
    posterior::as_draws_array(fit),
    error = function(error) {
      stop(
        "Could not convert the rstan::stanfit to posterior draws: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
  need_sampler <- "all" %in%
    checks ||
    any(checks %in% c("divergent_transitions", "efmi"))
  sampler_diagnostics <- if (need_sampler) {
    extract_rstan_sampler_diagnostics(fit, strict = strict)
  } else {
    NULL
  }
  if (
    !is.null(sampler_diagnostics) &&
      !identical(dim(sampler_diagnostics)[1:2], dim(draws)[1:2])
  ) {
    stop(
      "The Stan fit has inconsistent post-warmup sampler diagnostics dimensions.",
      call. = FALSE
    )
  }
  sampler_invalid <- need_sampler &&
    (is.null(sampler_diagnostics) ||
      !"divergent__" %in% posterior::variables(sampler_diagnostics))
  if (sampler_invalid) {
    if (strict) {
      stop(
        "The Stan fit has incomplete or inconsistent post-warmup sampler diagnostics.",
        call. = FALSE
      )
    }
  }
  stan_args <- rstan_fit_stan_args(fit)
  sim <- rstan_fit_slot(fit, "sim")
  # Consistent merged fits are accepted only when their saved chain count and
  # unique chain IDs agree with the extracted draws, and all saved shapes and
  # source metadata below validate against the merged object.
  nchains <- posterior::nchains(draws)
  retained_iterations <- dim(draws)[1L]
  retained_draws <- posterior::ndraws(draws)
  total_iterations <- first_rstan_value(
    rstan_public_value("get_num_iterations", fit),
    rstan_list_value(sim, "iter"),
    if (length(stan_args)) rstan_list_value(stan_args[[1L]], "iter")
  )
  warmup <- first_rstan_value(
    rstan_public_value("get_num_warmup", fit),
    rstan_list_value(sim, "warmup"),
    if (length(stan_args)) rstan_list_value(stan_args[[1L]], "warmup")
  )
  thin <- first_rstan_value(
    rstan_public_value("get_thin", fit),
    rstan_list_value(sim, "thin"),
    if (length(stan_args)) rstan_list_value(stan_args[[1L]], "thin"),
    1L
  )
  seed <- rstan_common_arg(stan_args, "seed")
  control <- rstan_common_arg(stan_args, "control")
  max_treedepth <- if (!is.null(control) && !is.null(control$max_treedepth)) {
    as.numeric(control$max_treedepth)
  } else {
    10
  }
  bfmi <- if ("all" %in% checks || "efmi" %in% checks) {
    tryCatch(
      rstan::get_bfmi(fit),
      error = function(error) {
        if (strict) {
          stop(
            "Could not extract the Stan fit's BFMI: ",
            conditionMessage(error),
            call. = FALSE
          )
        }
        NULL
      }
    )
  } else {
    NULL
  }
  if (
    !is.null(bfmi) &&
      (!is.numeric(bfmi) ||
        length(bfmi) != nchains ||
        (strict && (anyNA(bfmi) || any(!is.finite(bfmi)))))
  ) {
    if (strict) {
      stop(
        "The Stan fit has missing or invalid per-chain BFMI values.",
        call. = FALSE
      )
    }
    bfmi <- NULL
  }

  metadata <- list(
    nchains = as.integer(nchains),
    chains = as.integer(nchains),
    total_iterations = as_integer_or_null(total_iterations),
    iter = as_integer_or_null(total_iterations),
    warmup_iterations = as_integer_or_null(warmup),
    warmup = as_integer_or_null(warmup),
    retained_iterations = as.integer(retained_iterations),
    retained_draws = as.integer(retained_draws),
    ndraws = as.integer(retained_draws),
    thin = as_integer_or_null(thin),
    seed = seed,
    sampler_arguments = rstan_sampler_arguments(stan_args),
    model_name = rstan_model_name(fit),
    stan_version = rstan_stan_version(fit),
    rstan_version = paste("rstan", utils::packageVersion("rstan")),
    posterior_version = paste("posterior", utils::packageVersion("posterior")),
    r_version = R.version$version.string,
    sampling_timestamp = rstan_sampling_timestamp(fit),
    control = control,
    max_treedepth = max_treedepth,
    expected_fraction_of_missing_information = bfmi
  )
  metadata <- drop_null_list_elements(metadata)
  metadata$method_arguments <- rstan_method_arguments(metadata)

  list(
    draws = draws,
    sampler_diagnostics = sampler_diagnostics,
    metadata = metadata
  )
}

validate_rstan_saved_coverage <- function(base, saved_names, axes) {
  if (!length(axes)) {
    if (!identical(saved_names, base)) {
      stop(
        "Saved scalar coverage for `",
        base,
        "` does not match its declared scalar shape.",
        call. = FALSE
      )
    }
    return(invisible(TRUE))
  }
  indices <- lapply(saved_names, function(nm) {
    m <- regmatches(nm, regexpr("\\[[0-9,]+\\]$", nm))
    if (!length(m) || !nzchar(m)) {
      return(NULL)
    }
    as.integer(strsplit(substr(m, 2L, nchar(m) - 1L), ",", fixed = TRUE)[[1L]])
  })
  expected <- prod(axes)
  valid <- length(indices) == expected &&
    all(vapply(
      indices,
      function(i) {
        !is.null(i) &&
          length(i) == length(axes) &&
          all(i >= 1L) &&
          all(i <= axes)
      },
      logical(1)
    ))
  if (valid) {
    key <- vapply(indices, paste, collapse = ",", character(1))
    valid <- !anyDuplicated(key) && length(key) == expected
  }
  if (!valid) {
    stop(
      "Saved scalar coverage for `",
      base,
      "` is partial or does not match declared axes ",
      paste(axes, collapse = " x "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Selection is shared by both fit backends. Dimensions remain mandatory;
# additional saved outputs need not contribute unconstrained coordinates.
resolve_import_variable_selection <- function(
  draws,
  required,
  include = NULL,
  exclude = NULL
) {
  available <- unique(sub("\\[.*$", "", posterior::variables(draws)))
  resolve_variable_selection(available, required, include, exclude)
}

filter_external_posterior_draws <- function(draws, keep_dimensions) {
  available <- posterior::variables(draws)
  available_bases <- unique(sub("\\[.*$", "", available))
  missing_variables <- setdiff(keep_dimensions, available_bases)
  if (length(missing_variables)) {
    stop(
      "The external Stan fit is missing declared posterior variables: ",
      paste(missing_variables, collapse = ", "),
      call. = FALSE
    )
  }
  selected <- available[sub("\\[.*$", "", available) %in% keep_dimensions]
  posterior::subset_draws(draws, variable = selected, regex = FALSE)
}

rstan_fit_stan_args <- function(fit) {
  args <- rstan_fit_slot(fit, "stan_args")
  if (is.null(args) || !is.list(args)) list() else args
}

rstan_public_value <- function(fun, fit) {
  if (!exists(fun, envir = asNamespace("rstan"), inherits = FALSE)) {
    return(NULL)
  }
  fn <- get(fun, envir = asNamespace("rstan"))
  tryCatch(fn(fit), error = function(error) NULL)
}

rstan_list_value <- function(x, name) {
  if (is.null(x) || is.null(x[[name]])) NULL else x[[name]]
}

first_rstan_value <- function(...) {
  values <- list(...)
  values <- values[!vapply(values, is.null, logical(1))]
  if (length(values)) values[[1L]] else NULL
}

rstan_common_arg <- function(stan_args, name) {
  values <- lapply(stan_args, rstan_list_value, name = name)
  values <- values[!vapply(values, is.null, logical(1))]
  if (!length(values)) {
    return(NULL)
  }
  first <- values[[1L]]
  if (all(vapply(values, identical, logical(1), y = first))) first else values
}

rstan_sampler_arguments <- function(stan_args) {
  if (!length(stan_args)) {
    return(NULL)
  }
  per_chain <- lapply(stan_args, function(args) {
    # `chain_id` identifies the chain; it is not a sampling setting. Chain
    # position is preserved by the names when settings differ by chain.
    keep <- intersect(
      names(args),
      c(
        "iter",
        "warmup",
        "thin",
        "save_warmup",
        "seed",
        "algorithm",
        "method",
        "control",
        "refresh"
      )
    )
    drop_null_list_elements(lapply(args[keep], sanitize_metadata_value))
  })
  if (!any(lengths(per_chain))) {
    return(NULL)
  }
  if (all(vapply(per_chain, identical, logical(1), y = per_chain[[1L]]))) {
    return(per_chain[[1L]])
  }
  names(per_chain) <- paste0("chain", seq_along(per_chain))
  per_chain
}

rstan_method_arguments <- function(metadata) {
  keep <- c("chains", "iter", "warmup", "thin", "seed", "control")
  metadata[intersect(keep, names(metadata))]
}

rstan_model_name <- function(fit) {
  value <- rstan_fit_slot(fit, "model_name")
  if (is.null(value) || !length(value) || is.na(value[[1L]])) {
    NULL
  } else {
    as.character(value[[1L]])
  }
}

rstan_stan_version <- function(fit) {
  value <- tryCatch(rstan::stan_version(), error = function(error) NULL)
  if (is.null(value)) {
    return(NULL)
  }
  paste("Stan", as.character(value))
}

rstan_sampling_timestamp <- function(fit) {
  candidates <- list(
    rstan_fit_slot(fit, "date"),
    rstan_list_value(rstan_fit_slot(fit, "sim"), "start_datetime"),
    rstan_list_value(rstan_fit_slot(fit, "sim"), "start_time")
  )
  value <- do.call(first_rstan_value, candidates)
  if (is.null(value)) {
    return(NULL)
  }
  as.character(value[[1L]])
}

as_integer_or_null <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x)) NULL else as.integer(x)
}

sanitize_metadata_value <- function(x) {
  if (is.function(x) || is.environment(x) || inherits(x, "externalptr")) {
    return(NULL)
  }
  if (is.atomic(x)) {
    return(unname(x))
  }
  if (is.list(x)) {
    return(drop_null_list_elements(lapply(x, sanitize_metadata_value)))
  }
  as.character(x)
}

drop_null_list_elements <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}
