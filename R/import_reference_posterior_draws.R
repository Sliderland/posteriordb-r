#' Convert an externally sampled rstan fit to reference-posterior draws
#'
#' `rstan` sampling is deliberately kept outside this package.  This function
#' accepts a completed post-warmup [rstan::stanfit] object, keeps only the
#' variables declared by the PosteriorDB posterior, computes the usual
#' reference-posterior diagnostics, and returns the in-memory object without
#' writing to a database.
#'
#' @param fit a completed `rstan::stanfit` object.
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

as_reference_posterior_draws.default <- function(fit, ...) {
  stop(
    "Unsupported Stan fit object; expected a completed rstan::stanfit object.",
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

#' Import externally sampled Stan draws into a local PosteriorDB
#'
#' This is the writing wrapper around
#' [as_reference_posterior_draws_from_stanfit()]. Sampling is never performed
#' by this function. With `write = FALSE` (the default), the validated or
#' diagnostically failed in-memory object is returned. With `write = TRUE`,
#' required checks must pass and the metadata JSON and draw ZIP are written
#' transactionally after a round-trip verification.
#'
#' @param fit a completed `rstan::stanfit` object.
#' @param posterior a PosteriorDB posterior name or a `pdb_posterior` object.
#' @param pdb a local PosteriorDB object.
#' @param dimensions optional named PosteriorDB dimension list.
#' @param policy reserved for a future diagnostic policy; must currently be
#'   `NULL`.
#' @param write whether to write the validated result to `pdb`.
#' @param overwrite whether existing reference-posterior files may be replaced.
#' @param ... optional metadata fields forwarded to the conversion function.
#' @return A `pdb_reference_posterior_draws` object.
#' @export
import_reference_posterior_draws <- function(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  write = FALSE,
  overwrite = FALSE,
  ...
) {
  checkmate::assert_flag(write)
  checkmate::assert_flag(overwrite)
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
    rpd, pdb = pdb, overwrite = overwrite, linked_posterior = target_posterior
  )
  rpd
}

# Internal extraction boundary for future fit implementations.
extract_external_stan_fit <- function(fit, ...) {
  UseMethod("extract_external_stan_fit", fit)
}

extract_external_stan_fit.stanfit <- function(fit, ...) {
  extract_rstan_fit(fit, ...)
}

extract_external_stan_fit.default <- function(fit, ...) {
  stop(
    "Unsupported Stan fit object; expected a completed rstan::stanfit object.",
    call. = FALSE
  )
}

extract_rstan_fit <- function(fit, ...) {
  draws <- tryCatch(
    posterior::as_draws_array(fit),
    error = function(error) {
      stop("Could not convert the rstan::stanfit to posterior draws: ",
           conditionMessage(error), call. = FALSE)
    }
  )
  sampler_params <- tryCatch(
    rstan::get_sampler_params(fit, inc_warmup = FALSE),
    error = function(error) {
      stop("Could not extract post-warmup sampler diagnostics: ",
           conditionMessage(error), call. = FALSE)
    }
  )
  sampler_diagnostics <- sampler_params_to_draws_array(sampler_params)
  if (is.null(sampler_diagnostics) ||
      posterior::nchains(sampler_diagnostics) != posterior::nchains(draws) ||
      dim(sampler_diagnostics)[1L] != dim(draws)[1L] ||
      !"divergent__" %in% posterior::variables(sampler_diagnostics)) {
    stop("The Stan fit has incomplete or inconsistent post-warmup sampler diagnostics.", call. = FALSE)
  }
  stan_args <- rstan_fit_stan_args(fit)
  sim <- rstan_fit_slot(fit, "sim")
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
  bfmi <- tryCatch(
    rstan::get_bfmi(fit),
    error = function(error) {
      stop("Could not extract the Stan fit's BFMI: ", conditionMessage(error), call. = FALSE)
    }
  )
  if (!is.numeric(bfmi) || length(bfmi) != nchains ||
      anyNA(bfmi) || any(!is.finite(bfmi))) {
    stop("The Stan fit has missing or invalid per-chain BFMI values.", call. = FALSE)
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
    comments = dots$comments %||% "Imported from an externally sampled rstan::stanfit.",
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
  versions
}

write_imported_reference_posterior_draws <- function(x, pdb, overwrite,
                                                     linked_posterior = NULL) {
  checkmate::assert_class(pdb, "pdb_local")
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
  final_files <- c(final_info, final_draws)
  update_posterior <- FALSE
  if (!is.null(linked_posterior)) {
    checkmate::assert_class(linked_posterior, "pdb_posterior")
    current_reference <- linked_posterior$reference_posterior_name
    if (!is.null(current_reference) && !identical(current_reference, name)) {
      stop("The posterior already points to a different reference posterior.", call. = FALSE)
    }
    update_posterior <- is.null(current_reference)
    if (update_posterior) {
      linked_posterior$reference_posterior_name <- name
      final_files <- c(final_files, pdb_file_path(
        pdb, "posteriors", paste0(linked_posterior$name, ".json")
      ))
    }
  }
  existing <- file.exists(c(final_info, final_draws))
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

  write_pdb(x, staged_pdb, overwrite = FALSE)
  verify_imported_reference_posterior(staged_pdb, x)
  if (update_posterior) write_pdb(linked_posterior, staged_pdb, overwrite = FALSE)
  dir.create(dirname(final_info), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(final_draws), recursive = TRUE, showWarnings = FALSE)

  staged_info <- pdb_file_path(staged_pdb, "reference_posteriors", "draws", "info", paste0(name, ".info.json"))
  staged_draws <- pdb_file_path(staged_pdb, "reference_posteriors", "draws", "draws", paste0(name, ".json.zip"))
  staged_files <- c(staged_info, staged_draws)
  if (update_posterior) {
    staged_files <- c(staged_files, pdb_file_path(
      staged_pdb, "posteriors", paste0(linked_posterior$name, ".json")
    ))
  }
  if (!all(file.exists(staged_files))) {
    stop("Staging did not produce both reference-posterior files.", call. = FALSE)
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
  lapply(stan_args, function(args) {
    keep <- intersect(names(args), c(
      "chain_id", "iter", "warmup", "thin", "save_warmup", "seed",
      "algorithm", "method", "control", "refresh"
    ))
    drop_null_list_elements(lapply(args[keep], sanitize_metadata_value))
  })
}

rstan_method_arguments <- function(metadata) {
  keep <- c("chains", "iter", "warmup", "thin", "seed", "sampling_timestamp")
  args <- metadata[intersect(keep, names(metadata))]
  if (!is.null(metadata$sampler_arguments)) args$sampler_arguments <- metadata$sampler_arguments
  args
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
