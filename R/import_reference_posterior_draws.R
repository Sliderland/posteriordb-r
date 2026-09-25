#' Convert an externally sampled Stan fit to reference-posterior draws
#'
#' Sampling is deliberately kept outside this package. This function accepts a
#' completed post-warmup `rstan::stanfit` or `cmdstanr::CmdStanMCMC` object,
#' keeps only the variables declared by the PosteriorDB posterior, computes the
#' usual reference-posterior diagnostics, and returns the in-memory object
#' without writing to a database. For CmdStanR, calling this function reads the
#' draws and sampler diagnostics from the fit's CSV output files.
#' The fit's retained scalar variable names and shapes must match the posterior
#' specification. The importer does not verify that the fit used the posterior's
#' model source code or data.
#'
#' @param fit a completed `rstan::stanfit` or `cmdstanr::CmdStanMCMC` object.
#' @param posterior a PosteriorDB posterior name or a `pdb_posterior` object.
#' @param pdb a local or remote PosteriorDB connection used to resolve a name.
#' @param dimensions optional named PosteriorDB dimension list. When omitted,
#'   `posterior$dimensions` is authoritative.
#' @param policy reserved for a future diagnostic policy; must currently be
#'   `NULL` so the package's acceptance checks cannot be mistaken for a
#'   caller-supplied policy.
#' @param ... optional metadata fields such as `comments`, `added_by`,
#'   `added_date`, and `sampling_timestamp`.
#' @return A `pdb_reference_posterior_draws` object. If a required check fails,
#'   the object is returned with the failure recorded in its `checks_made`
#'   metadata; it is not eligible for writing.
#' @export
as_reference_posterior_draws <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
) {
  UseMethod("as_reference_posterior_draws", fit)
}

#' @rdname as_reference_posterior_draws
#' @export
as_reference_posterior_draws.stanfit <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
) {
  as_reference_posterior_draws_external(
    fit, posterior, pdb, dimensions, policy, ...
  )
}

#' @rdname as_reference_posterior_draws
#' @export
as_reference_posterior_draws.CmdStanMCMC <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
) {
  as_reference_posterior_draws_external(
    fit, posterior, pdb, dimensions, policy, ...
  )
}

as_reference_posterior_draws_external <- function(
  fit,
  posterior,
  pdb,
  dimensions,
  policy,
  ...
) {
  checkmate::assert_class(pdb, "pdb")
  if (!is.null(policy)) {
    stop("Custom diagnostic policies are not implemented; `policy` must be NULL.", call. = FALSE)
  }
  dots <- list(...)
  if (length(dots) &&
      (is.null(names(dots)) || anyNA(names(dots)) ||
       any(!nzchar(names(dots))) || anyDuplicated(names(dots)) ||
       !all(names(dots) %in% c("comments", "added_by", "added_date", "sampling_timestamp")))) {
    stop("`...` accepts only named `comments`, `added_by`, `added_date`, and `sampling_timestamp` fields.", call. = FALSE)
  }
  if (!is.null(dots$sampling_timestamp)) {
    checkmate::assert_string(dots$sampling_timestamp)
  }
  if (!is.null(dots$comments)) checkmate::assert_string(dots$comments)
  extracted <- extract_external_stan_fit(fit)
  if (!is.null(dots$sampling_timestamp)) {
    extracted$metadata$sampling_timestamp <- as.character(dots$sampling_timestamp)
  }
  po <- resolve_import_posterior(posterior, pdb)
  posterior_dimensions <- dimensions %||% po$dimensions
  if (is.null(posterior_dimensions) || length(posterior_dimensions) == 0L) {
    stop(
      "Posterior dimensions are unavailable; supply `dimensions` explicitly.",
      call. = FALSE
    )
  }
  posterior_dimensions <- validate_import_dimensions(posterior_dimensions)
  keep_dimensions <- posterior_dimension_names(posterior_dimensions)
  if (!is.null(dimensions) && length(po$dimensions) &&
      !setequal(keep_dimensions, posterior_dimension_names(validate_import_dimensions(po$dimensions)))) {
    stop("Supplied `dimensions` disagree with the posterior's declared dimensions.", call. = FALSE)
  }

  draws <- filter_external_posterior_draws(
    extracted$draws,
    keep_dimensions = keep_dimensions
  )
  validate_external_posterior_draws(draws, keep_dimensions)

  diagnostics <- compute_stan_sampling_diagnostics(
    x = draws,
    keep_dimensions = keep_dimensions,
    sampler_diagnostics = extracted$sampler_diagnostics,
    expected_fraction_of_missing_information =
      extracted$metadata$expected_fraction_of_missing_information,
    max_treedepth = extracted$metadata$max_treedepth
  )
  rpi <- new_import_reference_posterior_info(
    posterior = po,
    diagnostics = diagnostics,
    metadata = extracted$metadata,
    policy = policy,
    dots = dots
  )

  rpd <- as.reference_posterior_draws(
    posterior::as_draws_list(draws),
    info = rpi,
    pdb = pdb
  )
  attr(rpd, "sampler_diagnostics") <- extracted$sampler_diagnostics
  attr(rpd, "sampling_metadata") <- extracted$metadata

  checked <- tryCatch(
    check_reference_posterior_draws(rpd),
    error = function(error) {
      failed_info <- info(rpd)
      failed_info$checks_made <- c(
        failed_info$checks_made %||% list(),
        list(check_failed = conditionMessage(error))
      )
      info(rpd) <- failed_info
      rpd
    }
  )
  checked
}

#' @exportS3Method
as_reference_posterior_draws.default <- function(fit, ...) {
  stop(
    "Unsupported Stan fit object; expected a completed rstan::stanfit or cmdstanr::CmdStanMCMC object.",
    call. = FALSE
  )
}

#' @rdname as_reference_posterior_draws
#' @export
as_reference_posterior_draws_from_stanfit <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
) {
  as_reference_posterior_draws(
    fit = fit,
    posterior = posterior,
    pdb = pdb,
    dimensions = dimensions,
    policy = policy,
    ...
  )
}

#' @rdname as_reference_posterior_draws
#' @export
as_reference_posterior_draws_from_cmdstanr <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
) {
  as_reference_posterior_draws(
    fit = fit,
    posterior = posterior,
    pdb = pdb,
    dimensions = dimensions,
    policy = policy,
    ...
  )
}

#' Import externally sampled Stan draws into a local PosteriorDB
#'
#' This is the writing wrapper around
#' [as_reference_posterior_draws()]. Sampling is never performed
#' by this function. Conversion runs the complete reference-draw checks
#' regardless of the `write` setting. With `write = FALSE` (the default), the
#' checked object is returned in memory, including any failed checks. With
#' `write = TRUE`, all required checks must pass before writing. The
#' reference-draw files, summary-statistic files (by default), and any new
#' posterior link are staged and round-trip verified together. The target
#' posterior must already exist in the local database. Existing data and model
#' files are not rewritten.
#'
#' The importer verifies that the fit contains the scalar variables and shapes
#' declared by the posterior, but it does not compare the fit's Stan source code
#' or sampling data with the source and data linked to that posterior.
#'
#' @param fit a completed `rstan::stanfit` or `cmdstanr::CmdStanMCMC` object.
#' @param posterior a PosteriorDB posterior name or a `pdb_posterior` object.
#' @param pdb a local PosteriorDB object. Required when `write = TRUE`; when
#'   `write = FALSE`, it is used to resolve a posterior name.
#' @param dimensions optional named PosteriorDB dimension list.
#' @param policy reserved for a future diagnostic policy; must currently be
#'   `NULL`.
#' @param write whether to write the validated result to `pdb`.
#' @param overwrite whether existing reference-posterior files may be replaced.
#' @param write_summary_statistics whether to also write the supported summary
#'   statistics (`mean_value` and `mean_squared_value`) when `write = TRUE`.
#'   Defaults to `TRUE`.
#' @param ... optional metadata fields forwarded to the conversion function.
#' @return A `pdb_reference_posterior_draws` object.
#' @examples
#' \dontrun{
#' imported <- import_reference_posterior_draws(
#'   fit,
#'   posterior = "existing-data-existing-model",
#'   pdb = pdb_local("/path/to/posterior_database"),
#'   write = TRUE
#' )
#' }
#' @seealso [as_reference_posterior_draws()], [write_pdb()]
#' @export
import_reference_posterior_draws <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  write = FALSE,
  overwrite = FALSE,
  write_summary_statistics = TRUE,
  ...
) {
  checkmate::assert_flag(write)
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(write_summary_statistics)
  checkmate::assert_class(pdb, "pdb")
  if (write) checkmate::assert_class(pdb, "pdb_local")

  rpd <- as_reference_posterior_draws(
    fit = fit,
    posterior = posterior,
    pdb = pdb,
    dimensions = dimensions,
    policy = policy,
    ...
  )

  if (!write) return(rpd)
  failure <- info(rpd)$checks_made$check_failed
  if (!is.null(failure)) {
    stop("Reference-posterior checks failed; nothing was written: ", failure,
         call. = FALSE)
  }
  assert_checked_reference_posterior_draws(rpd)
  posterior_name <- if (is.character(posterior)) posterior else posterior$name
  checkmate::assert_string(posterior_name)
  target_posterior <- pdb_posterior(posterior_name, pdb = pdb)
  if (!setequal(
    posterior::variables(rpd),
    posterior_dimension_names(validate_import_dimensions(target_posterior$dimensions))
  )) {
    stop("Imported variables disagree with the target database's posterior dimensions.",
         call. = FALSE)
  }
  write_imported_reference_posterior_draws(
    rpd, pdb = pdb, overwrite = overwrite, linked_posterior = target_posterior,
    write_summary_statistics = write_summary_statistics
  )
  rpd
}

# Internal extraction boundary for future fit implementations.
extract_external_stan_fit <- function(fit, checks = "all", strict = TRUE, ...) {
  UseMethod("extract_external_stan_fit", fit)
}

#' @exportS3Method
extract_external_stan_fit.stanfit <- function(fit, checks = "all", strict = TRUE, ...) {
  extract_rstan_fit(fit, checks = checks, strict = strict, ...)
}

#' @exportS3Method
extract_external_stan_fit.CmdStanMCMC <- function(fit, checks = "all", strict = TRUE, ...) {
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
        conditionMessage(error), call. = FALSE
      )
    }
  )
  draws <- tryCatch(posterior::as_draws_array(draws), error = function(error) {
    stop("Could not convert cmdstanr draws to a posterior draws_array: ",
         conditionMessage(error), call. = FALSE)
  })
  need_sampler <- "all" %in% checks || any(checks %in% c("divergent_transitions", "efmi"))
  sampler_diagnostics <- if (need_sampler) tryCatch(
    fit$sampler_diagnostics(inc_warmup = FALSE, format = "draws_array"),
    error = function(error) {
      if (strict) stop(
        "Could not read sampler diagnostics from the cmdstanr fit's CSV files: ",
        conditionMessage(error), call. = FALSE
      )
      NULL
    }
  ) else NULL
  sampler_diagnostics <- if (!is.null(sampler_diagnostics)) tryCatch(
    posterior::as_draws_array(sampler_diagnostics),
    error = function(error) {
      if (strict) stop("Could not convert cmdstanr sampler diagnostics: ",
                       conditionMessage(error), call. = FALSE)
      NULL
    }
  ) else NULL
  if (!is.null(sampler_diagnostics) &&
      !identical(dim(sampler_diagnostics)[1:2], dim(draws)[1:2]))
    stop("The cmdstanr fit has inconsistent post-warmup sampler diagnostics dimensions.", call. = FALSE)
  sampler_invalid <- need_sampler && (is.null(sampler_diagnostics) ||
    !"divergent__" %in% posterior::variables(sampler_diagnostics))
  if (sampler_invalid) {
    if (strict) stop("The cmdstanr fit has incomplete or inconsistent post-warmup sampler diagnostics.", call. = FALSE)
  }
  metadata <- tryCatch(fit$metadata(), error = function(error) {
    stop("Could not read metadata from the cmdstanr fit's CSV files: ",
         conditionMessage(error), call. = FALSE)
  })
  if (!is.list(metadata)) {
    stop("The cmdstanr fit returned invalid CSV metadata.", call. = FALSE)
  }
  nchains <- posterior::nchains(draws)
  retained_iterations <- dim(draws)[1L]
  retained_draws <- posterior::ndraws(draws)
  iter_sampling <- cmdstanr_metadata_value(
    metadata, c("iter_sampling", "iterations_sampling"), retained_iterations
  )
  warmup <- cmdstanr_metadata_value(
    metadata, c("iter_warmup", "warmup", "num_warmup"), 0L
  )
  thin <- cmdstanr_metadata_value(metadata, "thin", 1L)
  max_treedepth <- cmdstanr_metadata_value(
    metadata, c("max_depth", "max_treedepth"), 10
  )
  bfmi <- if ("all" %in% checks || "efmi" %in% checks) tryCatch(
    cmdstanr_bfmi(sampler_diagnostics, nchains, strict = strict),
    error = function(error) {
      if (strict) stop(conditionMessage(error), call. = FALSE)
      NULL
    }
  ) else NULL
  metadata <- list(
    nchains = as.integer(nchains),
    chains = as.integer(nchains),
    total_iterations = as_integer_or_null(as.numeric(iter_sampling) + as.numeric(warmup)),
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
    cmdstan_version = cmdstanr_metadata_value(metadata, "cmdstan_version", NULL),
    posterior_version = paste("posterior", utils::packageVersion("posterior")),
    r_version = R.version$version.string,
    sampling_timestamp = cmdstanr_metadata_value(
      metadata, c("start_datetime", "start_time"), NULL
    ),
    max_treedepth = as.numeric(max_treedepth),
    expected_fraction_of_missing_information = bfmi
  )
  metadata <- drop_null_list_elements(metadata)
  metadata$method_arguments <- cmdstanr_method_arguments(metadata)
  list(draws = draws, sampler_diagnostics = sampler_diagnostics, metadata = metadata)
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
  parts <- vapply(c("stan_version_major", "stan_version_minor", "stan_version_patch"),
                  function(name) as.character(cmdstanr_metadata_value(metadata, name, NA_character_)),
                  character(1))
  if (anyNA(parts)) return(cmdstanr_metadata_value(metadata, "stan_version", NULL))
  paste("Stan", paste(parts, collapse = "."))
}

sampler_diagnostics_bfmi <- function(sampler_diagnostics, nchains,
                                     strict = TRUE) {
  if (!"energy__" %in% posterior::variables(sampler_diagnostics)) {
    if (strict) {
      stop("Sampler diagnostics have no `energy__` variable for E-FMI.",
           call. = FALSE)
    }
    return(NULL)
  }
  bfmi <- vapply(seq_len(nchains), function(chain) {
    energy <- sampler_diagnostics[, chain, "energy__"]
    denominator <- stats::var(energy)
    if (length(energy) < 2L || !is.finite(denominator) || denominator <= 0) return(NA_real_)
    mean(diff(energy)^2) / denominator
  }, numeric(1))
  if (strict && (anyNA(bfmi) || any(!is.finite(bfmi)))) {
    stop("Sampler diagnostics have missing or invalid per-chain E-FMI values.",
         call. = FALSE)
  }
  bfmi
}

rstan_sampler_bfmi <- function(sampler_diagnostics, nchains,
                                strict = FALSE) {
  if (!"energy__" %in% posterior::variables(sampler_diagnostics)) {
    if (strict) {
      stop("RStan sampler diagnostics have no `energy__` variable for E-FMI.",
           call. = FALSE)
    }
    return(NULL)
  }
  bfmi <- vapply(seq_len(nchains), function(chain) {
    energy <- sampler_diagnostics[, chain, "energy__"]
    denominator <- stats::var(energy)
    if (length(energy) < 2L || !is.finite(denominator) || denominator <= 0) {
      return(NA_real_)
    }
    # Match rstan::get_bfmi(): divide the squared energy differences by the
    # number of retained energy draws, not the number of differences.
    sum(diff(energy)^2) / length(energy) / denominator
  }, numeric(1))
  if (strict && any(!is.finite(bfmi))) {
    stop("RStan sampler diagnostics have missing or invalid per-chain E-FMI values.",
         call. = FALSE)
  }
  bfmi
}

cmdstanr_bfmi <- function(sampler_diagnostics, nchains, strict = TRUE) {
  sampler_diagnostics_bfmi(sampler_diagnostics, nchains, strict)
}

cmdstanr_sampler_arguments <- function(metadata) {
  args <- metadata[intersect(names(metadata), c(
    "num_chains", "iter_sampling", "iter_warmup", "thin", "save_warmup",
    "seed", "algorithm", "method", "max_depth", "refresh", "parallel_chains"
  ))]
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
  tryCatch({
    sampler_params <- rstan::get_sampler_params(fit, inc_warmup = FALSE)
    sampler_params_to_draws_array(sampler_params)
  }, error = function(error) {
    if (strict) stop("Could not extract post-warmup sampler diagnostics: ",
                     conditionMessage(error), call. = FALSE)
    NULL
  })
}

extract_rstan_fit <- function(fit, checks = "all", strict = TRUE,
                              for_bundle = FALSE, compute_diagnostics = TRUE,
                              include = NULL,
                              exclude = NULL, ...) {
  if (isTRUE(for_bundle)) {
    return(extract_rstan_fit_for_bundle(fit, strict = strict,
      compute_diagnostics = compute_diagnostics,
      include = include, exclude = exclude))
  }
  draws <- tryCatch(
    posterior::as_draws_array(fit),
    error = function(error) {
      stop("Could not convert the rstan::stanfit to posterior draws: ",
           conditionMessage(error), call. = FALSE)
    }
  )
  need_sampler <- "all" %in% checks || any(checks %in% c("divergent_transitions", "efmi"))
  sampler_diagnostics <- if (need_sampler) {
    extract_rstan_sampler_diagnostics(fit, strict = strict)
  } else NULL
  if (!is.null(sampler_diagnostics) &&
      !identical(dim(sampler_diagnostics)[1:2], dim(draws)[1:2]))
    stop("The Stan fit has inconsistent post-warmup sampler diagnostics dimensions.", call. = FALSE)
  sampler_invalid <- need_sampler && (is.null(sampler_diagnostics) ||
    !"divergent__" %in% posterior::variables(sampler_diagnostics))
  if (sampler_invalid) {
    if (strict) stop("The Stan fit has incomplete or inconsistent post-warmup sampler diagnostics.", call. = FALSE)
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
  bfmi <- if ("all" %in% checks || "efmi" %in% checks) tryCatch(
    rstan::get_bfmi(fit),
    error = function(error) {
      if (strict) stop("Could not extract the Stan fit's BFMI: ", conditionMessage(error), call. = FALSE)
      NULL
    }
  ) else NULL
  if (!is.null(bfmi) && (!is.numeric(bfmi) || length(bfmi) != nchains ||
      (strict && (anyNA(bfmi) || any(!is.finite(bfmi)))))) {
    if (strict) stop("The Stan fit has missing or invalid per-chain BFMI values.", call. = FALSE)
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

# Bundle extraction contract: draws is an ordered post-warmup draws_array;
# dimensions contains selected base-variable axes (integer(), scalar); metadata
# is sampling provenance only. Import-time package versions live separately.
extract_rstan_fit_for_bundle <- function(fit, strict = TRUE,
                                         compute_diagnostics = TRUE,
                                         include = NULL, exclude = NULL) {
  if (!inherits(fit, "stanfit"))
    stop("Bundle extraction requires an `rstan::stanfit`.", call. = FALSE)
  checkmate::assert_flag(strict)
  checkmate::assert_flag(compute_diagnostics)
  include <- validate_variable_selection(include, "include")
  exclude <- validate_variable_selection(exclude, "exclude")

  stan_args <- rstan_fit_stan_args(fit)
  if (!length(stan_args))
    stop("The `stanfit` has no saved per-chain sampling arguments; its inference method cannot be verified.", call. = FALSE)
  chain_is_hmc <- vapply(stan_args, function(x) {
    method <- x$method
    algorithm <- x$algorithm
    if (is.list(method)) {
      algorithm <- algorithm %||% method$algorithm
      method <- method$method %||% method$name
    }
    method <- if (is.null(method) || !length(method)) NULL else tolower(as.character(method[[1L]]))
    algorithm <- if (is.null(algorithm) || !length(algorithm)) NULL else tolower(as.character(algorithm[[1L]]))
    !is.null(algorithm) && algorithm %in% c("nuts", "hmc") &&
      (is.null(method) || method %in% c("sampling", "stan_sampling"))
  }, logical(1))
  if (!length(chain_is_hmc) || anyNA(chain_is_hmc) || !all(chain_is_hmc))
    stop("Bundle extraction supports completed HMC sampling fits only; the `stanfit` records a non-sampling or unknown inference method.", call. = FALSE)
  sim <- rstan_fit_slot(fit, "sim")
  if (!is.null(sim$chains) && length(sim$chains) == 1L &&
      sim$chains != length(stan_args))
    stop("Merged or inconsistent `stanfit` objects are not supported for bundle extraction.", call. = FALSE)
  chain_ids <- vapply(stan_args, function(x) as.character(x$chain_id %||% NA_character_), character(1))
  if (length(chain_ids) > 1L && !anyNA(chain_ids) && anyDuplicated(chain_ids))
    stop("Merged `stanfit` objects with repeated chain IDs are not supported for bundle extraction.", call. = FALSE)

  code <- rstan_fit_slot(rstan_fit_slot(fit, "stanmodel"), "model_code")
  if (is.null(code) || length(code) != 1L || is.na(code) || !nzchar(code))
    stop("The `stanfit` does not expose its saved Stan source code.", call. = FALSE)
  if (grepl("#\\s*include\\b", code, perl = TRUE))
    stop("The saved Stan source contains `#include`; bundle extraction requires self-contained source code.", call. = FALSE)

  # Reuse the established extractor once so draws and sampling metadata all
  # describe the same fit snapshot. Unchecked bundles retain raw sampler
  # diagnostics for a later explicit check, but do not calculate BFMI yet.
  result <- extract_rstan_fit(
    fit,
    checks = if (compute_diagnostics) "all" else character(),
    strict = strict
  )
  if (!compute_diagnostics) {
    result$sampler_diagnostics <- extract_rstan_sampler_diagnostics(
      fit,
      strict = FALSE
    )
  }
  if (!is.null(result$sampler_diagnostics) &&
      !identical(dim(result$sampler_diagnostics)[1:2], dim(result$draws)[1:2])) {
    stop("The Stan fit has inconsistent post-warmup sampler diagnostics dimensions.", call. = FALSE)
  }
  draws <- result$draws
  if (posterior::nchains(draws) != length(stan_args))
    stop("The saved per-chain inference settings do not match the number of draw chains.", call. = FALSE)
  scalar_names <- setdiff(posterior::variables(draws), "lp__")
  declared <- rstan_fit_slot(fit, "par_dims")
  if (is.null(declared) || is.null(names(declared)) || anyDuplicated(names(declared)))
    stop("The `stanfit` does not contain usable declared parameter dimensions.", call. = FALSE)
  bases <- unique(sub("\\[.*$", "", scalar_names))
  missing_decl <- setdiff(bases, names(declared))
  if (length(missing_decl))
    stop("Saved variables lack declared dimensions: ", paste(missing_decl, collapse = ", "), call. = FALSE)
  declared_bases <- setdiff(names(declared), "lp__")
  if (!is.null(include) && length(setdiff(include, declared_bases)))
    stop("Unknown Stan variable(s) in `include`: ", paste(setdiff(include, declared_bases), collapse = ", "), call. = FALSE)
  if (!is.null(exclude) && length(setdiff(exclude, declared_bases)))
    stop("Unknown Stan variable(s) in `exclude`: ", paste(setdiff(exclude, declared_bases), collapse = ", "), call. = FALSE)
  selected_bases <- setdiff(if (is.null(include)) declared_bases else include,
                            exclude %||% character())
  if (!length(selected_bases)) stop("Variable selection leaves no saved draws.", call. = FALSE)
  invalid_axes <- selected_bases[vapply(selected_bases, function(base) {
    axes <- declared[[base]]
    !is.numeric(axes) || anyNA(axes) || any(!is.finite(axes)) ||
      any(axes < 0L) || any(axes != floor(axes))
  }, logical(1))]
  if (length(invalid_axes))
    stop("Stan variable(s) have invalid declared dimensions: ",
         paste(invalid_axes, collapse = ", "), call. = FALSE)
  zero_sized <- selected_bases[vapply(selected_bases, function(base) {
    axes <- declared[[base]]
    length(axes) > 0L && any(axes == 0L)
  }, logical(1))]
  if (length(zero_sized))
    stop("Stan variable(s) have zero-sized declared dimensions; exclude them explicitly to continue: ",
         paste(zero_sized, collapse = ", "), call. = FALSE)
  unsaved <- setdiff(selected_bases, bases)
  if (length(unsaved))
    stop("Requested Stan variable(s) were not saved in the fit: ", paste(unsaved, collapse = ", "), call. = FALSE)

  dimensions <- stats::setNames(lapply(selected_bases, function(base) {
    raw_axes <- declared[[base]]
    if (!is.numeric(raw_axes) || anyNA(raw_axes) || any(!is.finite(raw_axes)) ||
        any(raw_axes < 0L) || any(raw_axes != floor(raw_axes)))
      stop("Stan variable `", base, "` has invalid declared dimensions.", call. = FALSE)
    axes <- as.integer(raw_axes)
    if (any(axes <= 0L))
      stop("Stan variable `", base, "` has zero-sized or invalid declared dimensions; exclude it explicitly to continue.", call. = FALSE)
    saved <- scalar_names[sub("\\[.*$", "", scalar_names) == base]
    validate_rstan_saved_coverage(base, saved, axes)
    axes
  }), selected_bases)
  selected <- scalar_names[sub("\\[.*$", "", scalar_names) %in% selected_bases]
  draws <- posterior::subset_draws(draws, variable = selected, regex = FALSE)

  sampler_diagnostics <- result$sampler_diagnostics
  metadata <- result$metadata
  # rstan_stan_version() is based on the installed package's Stan version,
  # which is not proof of the version used when this fit was sampled.
  metadata[c("rstan_version", "posterior_version", "r_version", "stan_version")] <- NULL
  # `stanfit@date` can be the merge time for sflist2stanfit(), so do not
  # describe this available clock value as the original sampling timestamp.
  metadata$fit_timestamp <- metadata$sampling_timestamp
  metadata$sampling_timestamp <- NULL
  metadata$method_arguments$sampling_timestamp <- NULL
  # Keep chain-specific values intact; derive a scalar max depth only when common.
  controls <- lapply(stan_args, function(x) x$control %||% list())
  depths <- vapply(controls, function(x) as.numeric(x$max_treedepth %||% 10), numeric(1))
  metadata$max_treedepth <- if (all(depths == depths[[1L]])) depths[[1L]] else depths
  import_versions <- list(R = R.version$version.string,
    rstan = as.character(utils::packageVersion("rstan")),
    posterior = as.character(utils::packageVersion("posterior")))
  list(draws = draws, sampler_diagnostics = sampler_diagnostics,
    metadata = metadata, source = as.character(code), dimensions = dimensions,
    fit_class = "stanfit", import_versions = import_versions)
}

validate_rstan_saved_coverage <- function(base, saved_names, axes) {
  if (!length(axes)) {
    if (!identical(saved_names, base))
      stop("Saved scalar coverage for `", base, "` does not match its declared scalar shape.", call. = FALSE)
    return(invisible(TRUE))
  }
  indices <- lapply(saved_names, function(nm) {
    m <- regmatches(nm, regexpr("\\[[0-9,]+\\]$", nm))
    if (!length(m) || !nzchar(m)) return(NULL)
    as.integer(strsplit(substr(m, 2L, nchar(m) - 1L), ",", fixed = TRUE)[[1L]])
  })
  expected <- prod(axes)
  valid <- length(indices) == expected && all(vapply(indices, function(i)
    !is.null(i) && length(i) == length(axes) && all(i >= 1L) &&
      all(i <= axes), logical(1)))
  if (valid) {
    key <- vapply(indices, paste, collapse = ",", character(1))
    valid <- !anyDuplicated(key) && length(key) == expected
  }
  if (!valid)
    stop("Saved scalar coverage for `", base, "` is partial or does not match declared axes ",
         paste(axes, collapse = " x "), ".", call. = FALSE)
  invisible(TRUE)
}

# Expand base dimensions to the canonical scalar draw names, preserving every
# axis (including an axis of length one). This is intentionally private to the
# fit import path and does not invoke dimension inference or sampling.
bundle_dimension_names <- function(dimensions, variables = NULL) {
  unlist(lapply(names(dimensions), function(base) {
    axes <- dimensions[[base]]
    if (!length(axes)) return(base)
    # The PosteriorDB dimension format uses 1 for scalars, but a one-element
    # vector also has dimensions 1. Its indexed draw name disambiguates it
    # while the full in-memory bundle is available.
    if (length(axes) == 1L && axes == 1L &&
        !is.null(variables) && base %in% variables) return(base)
    indices <- expand.grid(lapply(axes, seq_len), KEEP.OUT.ATTRS = FALSE,
                           stringsAsFactors = FALSE)
    ordered <- do.call(cbind, indices)
    apply(ordered, 1L, function(i) paste0(base, "[", paste(i, collapse = ","), "]"))
  }), use.names = FALSE)
}

resolve_import_posterior <- function(posterior, pdb) {
  if (is.character(posterior)) return(pdb_posterior(posterior, pdb = pdb))
  checkmate::assert_class(posterior, "pdb_posterior")
  posterior
}

validate_import_dimensions <- function(dimensions) {
  if (is.atomic(dimensions) && !is.null(names(dimensions))) {
    dimensions <- as.list(dimensions)
  }
  checkmate::assert_list(dimensions, min.len = 1L)
  checkmate::assert_named(dimensions)
  checkmate::assert_true(!anyDuplicated(names(dimensions)))
  dimensions
}

filter_external_posterior_draws <- function(draws, keep_dimensions) {
  available <- posterior::variables(draws)
  missing_variables <- setdiff(keep_dimensions, available)
  if (length(missing_variables)) {
    stop(
      "The external Stan fit is missing declared posterior variables: ",
      paste(missing_variables, collapse = ", "),
      call. = FALSE
    )
  }
  posterior::subset_draws(
    draws,
    variable = keep_dimensions,
    regex = FALSE
  )
}

validate_external_posterior_draws <- function(draws, keep_dimensions) {
  checkmate::assert_class(draws, "draws_array")
  if (!identical(posterior::variables(draws), keep_dimensions)) {
    stop("The retained posterior variable names do not match the declared dimensions.", call. = FALSE)
  }
  if (posterior::nchains(draws) < 1L || posterior::ndraws(draws) < 1L) {
    stop("The external Stan fit has no complete post-warmup chains.", call. = FALSE)
  }
  values <- as.numeric(draws)
  if (anyNA(values) || any(!is.finite(values))) {
    stop("Retained posterior draws contain missing or non-finite values.", call. = FALSE)
  }
  draw_dimensions <- dim(draws)
  if (length(dim(draws)) != 3L ||
      draw_dimensions[[1L]] * draw_dimensions[[2L]] != posterior::ndraws(draws) ||
      draw_dimensions[[2L]] != posterior::nchains(draws) ||
      draw_dimensions[[3L]] != length(keep_dimensions)) {
    stop("The external Stan fit does not contain complete, consistently shaped chains.", call. = FALSE)
  }
  invisible(draws)
}

new_import_reference_posterior_info <- function(
  posterior,
  diagnostics,
  metadata,
  policy,
  dots
) {
  added_by <- dots$added_by %||% unname(Sys.info()[["user"]])
  added_date <- dots$added_date %||% Sys.Date()
  checkmate::assert_string(added_by)
  checkmate::assert_class(added_date, "Date")
  method_arguments <- metadata$method_arguments %||% list()
  info <- list(
    name = posterior$reference_posterior_name %||% posterior$name,
    inference = list(
      method = "stan_sampling",
      method_arguments = method_arguments
    ),
    diagnostics = diagnostics,
    checks_made = NULL,
    comments = dots$comments %||% paste0(
      "Imported from an externally sampled ",
      if (!is.null(metadata$cmdstanr_version)) "cmdstanr::CmdStanMCMC." else "rstan::stanfit."
    ),
    added_by = added_by,
    added_date = added_date,
    versions = imported_reference_posterior_versions(metadata)
  )
  as.pdb_reference_posterior_info(info)
}

imported_reference_posterior_versions <- function(metadata) {
  versions <- pdb_stan_sampling_versions()
  versions$posterior_version <- metadata$posterior_version
  versions$stan_version <- metadata$stan_version
  if (!is.null(metadata$rstan_version)) versions$rstan_version <- metadata$rstan_version
  if (!is.null(metadata$cmdstanr_version)) versions$cmdstanr_version <- metadata$cmdstanr_version
  if (!is.null(metadata$cmdstan_version)) versions$cmdstan_version <- metadata$cmdstan_version
  versions
}

write_imported_reference_posterior_draws <- function(x, pdb, overwrite,
                                                     linked_posterior = NULL,
                                                     write_summary_statistics = TRUE) {
  checkmate::assert_class(pdb, "pdb_local")
  checkmate::assert_flag(write_summary_statistics)
  if (is.null(linked_posterior)) {
    stop("A linked posterior is required before reference draws can be written.",
         call. = FALSE)
  }
  failure <- info(x)$checks_made$check_failed
  if (!is.null(failure)) {
    stop("Reference-posterior checks failed; nothing was written: ", failure, call. = FALSE)
  }
  assert_checked_reference_posterior_draws(x)
  name <- info(x)$name
  checkmate::assert_string(name)
  if (name %in% c(".", "..") || grepl("[/\\\\]", name)) {
    stop("Reference-posterior names must be file names without path separators.", call. = FALSE)
  }
  final_info <- pdb_file_path(pdb, "reference_posteriors", "draws", "info", paste0(name, ".info.json"))
  final_draws <- pdb_file_path(pdb, "reference_posteriors", "draws", "draws", paste0(name, ".json.zip"))
  checkmate::assert_class(linked_posterior, "pdb_posterior")
  current_reference <- linked_posterior$reference_posterior_name
  if (!is.null(current_reference) && !identical(current_reference, name)) {
    stop("The posterior already points to a different reference posterior.", call. = FALSE)
  }
  update_posterior <- is.null(current_reference)
  summary_types <- if (write_summary_statistics) {
    supported_summary_statistic_types()
  } else {
    character()
  }
  summary_files <- unlist(lapply(summary_types, function(type) {
    c(
      pdb_file_path(pdb, "reference_posteriors", "summary_statistics", type,
                    "info", paste0(name, ".info.json")),
      pdb_file_path(pdb, "reference_posteriors", "summary_statistics", type,
                    type, paste0(name, ".json"))
    )
  }), use.names = FALSE)
  final_files <- c(final_info, final_draws, summary_files)
  if (update_posterior) {
    final_files <- c(final_files, pdb_file_path(
      pdb, "posteriors", paste0(linked_posterior$name, ".json")
    ))
  }
  existing <- file.exists(final_files)
  if (any(existing) && !overwrite) {
    stop(
      "Reference-posterior files already exist; use `overwrite = TRUE` to replace them.",
      call. = FALSE
    )
  }
  endpoint <- pdb$pdb_local_endpoint %||% pdb_endpoint(pdb)
  staging <- tempfile("reference-posterior-import-", tmpdir = endpoint)
  dir.create(staging, recursive = TRUE)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
  staged_pdb <- pdb
  staged_pdb$pdb_id <- staging
  staged_pdb$pdb_local_endpoint <- staging
  staged_pdb$cache_path <- file.path(staging, "cache")
  dir.create(staged_pdb$cache_path, recursive = TRUE)

  staged_posterior <- linked_posterior
  staged_posterior$reference_posterior_name <- name
  write_pdb(staged_posterior, staged_pdb, overwrite = TRUE)
  write_pdb(
    x,
    staged_pdb,
    overwrite = FALSE,
    write_summary_statistics = write_summary_statistics
  )
  verify_imported_reference_posterior(staged_pdb, x)
  if (update_posterior) {
    link_reference_posterior_object(
      linked_posterior,
      reference_posterior = name,
      pdb = staged_pdb,
      verify = TRUE
    )
  }
  for (path in final_files) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  }

  staged_info <- pdb_file_path(staged_pdb, "reference_posteriors", "draws", "info", paste0(name, ".info.json"))
  staged_draws <- pdb_file_path(staged_pdb, "reference_posteriors", "draws", "draws", paste0(name, ".json.zip"))
  staged_summary_files <- unlist(lapply(summary_types, function(type) {
    c(
      pdb_file_path(staged_pdb, "reference_posteriors", "summary_statistics", type,
                    "info", paste0(name, ".info.json")),
      pdb_file_path(staged_pdb, "reference_posteriors", "summary_statistics", type,
                    type, paste0(name, ".json"))
    )
  }), use.names = FALSE)
  staged_files <- c(staged_info, staged_draws, staged_summary_files)
  if (update_posterior) {
    staged_files <- c(staged_files, pdb_file_path(
      staged_pdb, "posteriors", paste0(linked_posterior$name, ".json")
    ))
  }
  if (!all(file.exists(staged_files))) {
    stop("Staging did not produce all reference-draw and summary-statistic files.", call. = FALSE)
  }
  backups <- character()
  installed <- character()
  committed <- FALSE
  on.exit({
    if (!committed) {
      for (path in installed) {
        if (file.exists(path)) unlink(path)
      }
      for (original in names(backups)) {
        backup <- backups[[original]]
        if (file.exists(backup)) {
          if (!file.rename(backup, original)) {
            warning("Could not restore original reference-posterior file: ", original,
                    call. = FALSE)
          }
        }
      }
    }
  }, add = TRUE)
  for (path in final_files[file.exists(final_files)]) {
    backup <- tempfile(paste0(basename(path), ".import-backup-"), tmpdir = dirname(path))
    if (!file.rename(path, backup)) stop("Could not stage the existing reference-posterior file.", call. = FALSE)
    backups[path] <- backup
  }
  for (i in seq_along(final_files)) {
    if (!file.rename(staged_files[[i]], final_files[[i]])) {
      stop("Could not commit the imported reference-posterior files.", call. = FALSE)
    }
    installed <- c(installed, final_files[[i]])
  }
  verify_imported_reference_posterior(pdb, x, fresh_cache = TRUE)
  if (!is.null(linked_posterior)) {
    linked_file <- pdb_file_path(
      pdb, "posteriors", paste0(linked_posterior$name, ".json")
    )
    if (!identical(jsonlite::read_json(linked_file)$reference_posterior_name, name)) {
      stop("Round-trip verification of the posterior reference link failed.",
           call. = FALSE)
    }
  }
  cached_files <- file.path(
    pdb$cache_path,
    c(file.path("reference_posteriors", "draws", "info", paste0(name, ".info.json")),
      file.path("reference_posteriors", "draws", "draws", paste0(name, ".json")),
      unlist(lapply(summary_types, function(type) {
        c(
          file.path("reference_posteriors", "summary_statistics", type,
                    "info", paste0(name, ".info.json")),
          file.path("reference_posteriors", "summary_statistics", type,
                    type, paste0(name, ".json"))
        )
      }), use.names = FALSE),
      if (update_posterior) file.path("posteriors", paste0(linked_posterior$name, ".json")))
  )
  unlink(cached_files[file.exists(cached_files)])
  for (backup in backups) if (file.exists(backup)) unlink(backup)
  committed <- TRUE
  invisible(x)
}

verify_imported_reference_posterior <- function(pdb, expected, fresh_cache = FALSE) {
  if (fresh_cache) {
    pdb$cache_path <- tempfile("reference-posterior-verify-cache-")
    dir.create(pdb$cache_path, recursive = TRUE)
    on.exit(unlink(pdb$cache_path, recursive = TRUE, force = TRUE), add = TRUE)
  }
  actual_info <- read_reference_posterior_info(info(expected)$name, type = "draws", pdb = pdb)
  actual_draws <- read_reference_posterior_draws(info(expected)$name, pdb = pdb)
  if (!identical(actual_info$name, info(expected)$name) ||
      !isTRUE(all.equal(actual_info$diagnostics$ndraws, info(expected)$diagnostics$ndraws, check.attributes = FALSE)) ||
      !isTRUE(all.equal(actual_info$diagnostics$nchains, info(expected)$diagnostics$nchains, check.attributes = FALSE)) ||
      !identical(posterior::variables(actual_draws), posterior::variables(expected)) ||
      !isTRUE(all.equal(
        as.numeric(posterior::as_draws_array(actual_draws)),
        as.numeric(posterior::as_draws_array(expected)),
        tolerance = 1e-12
      ))) {
    stop("Round-trip verification of the imported reference posterior failed.", call. = FALSE)
  }
  check_reference_posterior_draws(actual_draws)
  invisible(TRUE)
}

rstan_fit_slot <- function(fit, slot_name) {
  if (!isS4(fit) || !slot_name %in% methods::slotNames(fit)) return(NULL)
  methods::slot(fit, slot_name)
}

rstan_fit_stan_args <- function(fit) {
  args <- rstan_fit_slot(fit, "stan_args")
  if (is.null(args) || !is.list(args)) list() else args
}

rstan_public_value <- function(fun, fit) {
  if (!exists(fun, envir = asNamespace("rstan"), inherits = FALSE)) return(NULL)
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
  if (!length(values)) return(NULL)
  first <- values[[1L]]
  if (all(vapply(values, identical, logical(1), y = first))) first else values
}

rstan_sampler_arguments <- function(stan_args) {
  if (!length(stan_args)) return(NULL)
  per_chain <- lapply(stan_args, function(args) {
    # `chain_id` identifies the chain; it is not a sampling setting. Chain
    # position is preserved by the names when settings differ by chain.
    keep <- intersect(names(args), c(
      "iter", "warmup", "thin", "save_warmup", "seed",
      "algorithm", "method", "control", "refresh"
    ))
    drop_null_list_elements(lapply(args[keep], sanitize_metadata_value))
  })
  if (!any(lengths(per_chain))) return(NULL)
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
  if (is.null(value) || !length(value) || is.na(value[[1L]])) NULL else as.character(value[[1L]])
}

rstan_stan_version <- function(fit) {
  value <- tryCatch(rstan::stan_version(), error = function(error) NULL)
  if (is.null(value)) return(NULL)
  paste("Stan", as.character(value))
}

rstan_sampling_timestamp <- function(fit) {
  candidates <- list(
    rstan_fit_slot(fit, "date"),
    rstan_list_value(rstan_fit_slot(fit, "sim"), "start_datetime"),
    rstan_list_value(rstan_fit_slot(fit, "sim"), "start_time")
  )
  value <- do.call(first_rstan_value, candidates)
  if (is.null(value)) return(NULL)
  as.character(value[[1L]])
}

as_integer_or_null <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x)) NULL else as.integer(x)
}

sanitize_metadata_value <- function(x) {
  if (is.function(x) || is.environment(x) || inherits(x, "externalptr")) return(NULL)
  if (is.atomic(x)) return(unname(x))
  if (is.list(x)) return(drop_null_list_elements(lapply(x, sanitize_metadata_value)))
  as.character(x)
}

drop_null_list_elements <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}

`%||%` <- function(x, y) if (is.null(x)) y else x
