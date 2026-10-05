#' Construct a standalone PosteriorDB reference-draw bundle from a Stan fit
#'
#' Build linked data, model, posterior, and reference-draw objects around an
#' already sampled `rstan::stanfit`. The default workflow accepts the actual
#' Stan input list and human labels. Existing database objects can also be
#' reused, either as objects or names. This function does not resample the fit
#' or write files; it reads named records through the package getters and may
#' recompile the model only to recover dimensions when compiled parameter-name
#' methods are absent. Errors from available methods propagate without recovery.
#'
#' The default variable selection includes saved parameters, transformed
#' parameters, and generated quantities, except `lp__`. `include` and
#' `exclude` select base variable names, so `include = "theta"` retains all
#' saved scalar elements of an array parameter. All inferred parameter-block
#' variables are always retained, diagnosed, and summarized, even when omitted
#' from `include`. Excluding them is an error. Derived outputs do not change
#' the inferred posterior dimensions.
#'
#' @param fit A completed `rstan::stanfit` object.
#' @param data The exact named Stan input list, a `pdb_data` object, or the
#'   name of saved data in `pdb`. `list()` explicitly declares an empty input;
#'   `NULL` errors unless linked data can be retrieved from a supplied
#'   posterior object. Fit-data recovery is not supported.
#' @param model_code Optional `pdb_model_code` object or saved model name.
#'   Its Stan source must match the source embedded in `fit`.
#' @param posterior Optional `pdb_posterior` object or saved posterior name.
#'   Its linked data/model and unconstrained dimensions must match the bundle.
#' @param added_by Shared default contributor name for the constructed data,
#'   model, posterior, and reference-draw metadata. Defaults to the current R
#'   user. Values supplied in the corresponding metadata lists take precedence.
#' @param added_date Shared default contribution date for the constructed
#'   objects. Defaults to the current date when the function is called.
#'   Values supplied in the corresponding metadata lists take precedence.
#' @param data_info Named data metadata. `name` and `title` are required;
#'   names must be nonempty single path components without separators,
#'   control characters, or the special names `.` and `..`. Dots within names
#'   and hyphens are allowed; the same rules apply to model names.
#'   supported descriptive fields are `description`, `references`, `urls`,
#'   and `keywords`.
#' @param model_info Named model metadata. `name` and `title` are required;
#'   supported descriptive fields are `description`, `references`, `urls`,
#'   `keywords`, `prior`, and `licence`. Supply `prior` only when you have
#'   prior metadata to record (for example, `list(keywords = "prior-key")`);
#'   the constructor does not infer priors from Stan code. When written, an
#'   unspecified prior is omitted, no `likelihood_code` entry is emitted, and
#'   omitted model `keywords` are written as `null`.
#'   Set `framework = "stan"` to have the constructor build
#'   `model_implementations$stan` using the conventional
#'   `models/stan/<name>.stan` path and `stan_version = ">=2.26.0"` default.
#'   You can instead supply `model_implementations` yourself; an explicit
#'   Stan implementation must use the inferred model-code path, and its
#'   `stan_version` overrides the default when provided.
#' @param posterior_info Named posterior metadata. Optional `added_by` and
#'   `added_date` values override the shared defaults for the posterior.
#'   The generated `dimensions` map contains unconstrained parameter counts,
#'   not constrained output shapes. Draw selection still retains every saved
#'   scalar output column for each selected base variable.
#'   Optional descriptive fields `urls`, `references`, and `keywords` are
#'   retained in the posterior info JSON when supplied.
#'   Optional structural fields
#'   (`name`, `model_name`, `data_name`, `reference_posterior_name`, and
#'   `dimensions`) are accepted only when they match inferred values.
#' @param reference_info Named human annotations for the reference draws,
#'   such as `comments`, `added_by`, and `added_date`. The inference method
#'   and version provenance are derived from the current R environment.
#'   Diagnostics and `checks_made` are calculated internally.
#' @param include Optional character vector of saved base variable names to
#'   retain in addition to all inferred parameter-block variables. `NULL`
#'   retains all saved model outputs except `lp__`; `"all"` (or `c("all")`)
#'   is an alias for NULL. `"none"` (or `c("none")`) is an alias for
#'   `character(0)`: retain only parameter-block variables, with no additional
#'   outputs. `"all"` and `"none"` are reserved when used alone.
#'   `c()` is NULL and therefore selects all.
#' @param exclude Optional character vector of base variable names to omit.
#'   Exclusion takes precedence over inclusion for derived outputs; excluding
#'   an inferred parameter-block variable is an error.
#' @param check Whether to evaluate the package's reference-draw acceptance
#'   checks. `FALSE` leaves the candidate explicitly unchecked and skips
#'   draw-diagnostic and acceptance-metric calculations.
#' @param pdb Optional PosteriorDB connection used to retrieve named objects
#'   and attach newly constructed objects. Reused objects retain their source
#'   connections. This constructor never writes to it.
#' @param ... Named method options: `model_code`, `posterior`, `data_info`, `model_info`, `posterior_info`,
#'   `reference_info`, `include`, `exclude`, `check`, and
#'   `pdb`. Unnamed, duplicate, misspelled, or other arguments are rejected.
#'
#' @return A `pdb_reference_bundle` list containing `data`, `model_code`,
#'   `posterior`, `reference_draws`, `summary_statistics`, `diagnostics`, and
#'   `provenance`. When checks pass, `summary_statistics` is a named list with
#'   `mean_value` and `mean_squared_value` objects; otherwise it is `NULL`. `diagnostics` is
#'   `NULL` when `check = FALSE`; call [check_reference_posterior_draws()] on
#'   that bundle to check it later.
#' @details
#' The first four positional arguments are `fit`, `data`, `added_by`, and
#' `added_date`. Supply all other options by name through the generic.
#' The default workflow uses a Stan input list and data/model metadata.
#' Alternatively, `data` can be a `pdb_data` object or saved data name, and
#' `model_code` and `posterior` can each be supplied as existing objects or
#' saved names. A supplied posterior can provide linked data and model code
#' when `data` and `model_code` are omitted. Database names are resolved with
#' the package's normal getters. Supplied objects are checked against the fit
#' source, links, and inferred unconstrained dimensions. If an existing object
#' and its corresponding `*_info` list are both supplied, a warning is issued
#' and the existing object's metadata takes precedence.
#' Reused objects keep their source database connections. The bundle writer
#' rejects same-name files in another destination database, even with
#' `overwrite = TRUE`. A reused posterior must have the matching reference
#' link on disk before accepted bundle draws can be written; use
#' [import_reference_posterior_draws()] with `write = TRUE` to fill an empty
#' link together with the accepted reference files.
#'
#' The bundle embeds its content in memory and remains usable before database
#' persistence. Supplied data is recorded as caller-supplied; this function
#' cannot establish that it produced the fit. If a serialized RStan fit no longer
#' exposes compiled parameter-name methods, the model source is recompiled with
#' the supplied data to recover unconstrained parameter counts, bypassing RStan's
#' lookup of same-source archived models. Errors from available methods, including
#' inconsistent counts or invalid names, are not retried; the saved fit is
#' not resampled. With `check = FALSE`, raw
#' sampler diagnostics are retained so [check_reference_posterior_draws()]
#' can check the bundle later without rerunning sampling. For example:
#'
#' ```r
#' bundle <- create_pdb_bundle(
#'   fit, data = stan_data,
#'   data_info = list(name = "study", title = "Study inputs"),
#'   model_info = list(name = "normal", title = "Normal model"),
#'   include = c("mu", "sigma")
#' )
#' bundle$reference_draws
#' bundle$summary_statistics$mean_value
#' bundle$summary_statistics$mean_squared_value
#' ```
#'
#' Missing names/titles, conflicting structural metadata, unknown fields,
#' unsupported fit classes, unavailable data, and incomplete saved arrays
#' produce actionable errors. Failed diagnostic candidates are returned with
#' their failures recorded.
#' @export
create_pdb_bundle <- function(
  fit,
  data = NULL,
  added_by = unname(Sys.info()[["user"]]),
  added_date = Sys.Date(),
  ...
) {
  validate_bundle_call_dots(list(...))
  UseMethod("create_pdb_bundle", fit)
}

#' @rdname create_pdb_bundle
#' @export
create_pdb_bundle.stanfit <- function(
  fit,
  data = NULL,
  added_by = unname(Sys.info()[["user"]]),
  added_date = Sys.Date(),
  model_code = NULL,
  posterior = NULL,
  data_info = list(),
  model_info = list(),
  posterior_info = list(),
  reference_info = list(),
  include = NULL,
  exclude = NULL,
  check = TRUE,
  pdb = NULL,
  ...
) {
  if (length(list(...))) {
    stop("Internal dispatch passed unexpected extra arguments.", call. = FALSE)
  }
  checkmate::assert_flag(check)
  checkmate::assert_string(added_by)
  checkmate::assert_class(added_date, "Date")
  if (!is.null(pdb)) {
    checkmate::assert_class(pdb, "pdb")
  }
  if (is.character(data) && length(data) == 1L) {
    # Resolve saved names before validating and assembling the standalone bundle.
    data <- if (is.null(pdb)) pdb_data(data) else pdb_data(data, pdb = pdb)
  }
  if (is.character(model_code) && length(model_code) == 1L &&
      !inherits(model_code, "pdb_model_code")) {
    model_code <- if (is.null(pdb)) {
      pdb_model_code(model_code, framework = "stan")
    } else {
      pdb_model_code(model_code, framework = "stan", pdb = pdb)
    }
  }
  if (is.character(posterior) && length(posterior) == 1L) {
    posterior <- if (is.null(pdb)) pdb_posterior(posterior) else pdb_posterior(posterior, pdb = pdb)
  }
  if (!is.null(model_code)) checkmate::assert_class(model_code, "pdb_model_code")
  if (!is.null(posterior)) checkmate::assert_class(posterior, "pdb_posterior")
  if (!is.null(posterior)) {
    # A supplied posterior can fill in its linked data and Stan source.
    if (is.null(data)) data <- get_data(posterior)
    if (is.null(model_code)) model_code <- model_code(posterior, framework = "stan")
  }
  resolved_data <- resolve_standalone_fit_data(data)
  data <- resolved_data$data
  existing_data <- resolved_data$object
  if (!is.null(existing_data)) {
    if (length(data_info)) {
      warning(
        "Both an existing PosteriorDB data object and `data_info` were supplied; using the object's metadata and ignoring `data_info`.",
        call. = FALSE
      )
    }
    data_info <- unclass(info(existing_data))
  }
  if (!is.null(model_code)) {
    if (length(model_info)) {
      warning(
        "Both an existing PosteriorDB model-code object and `model_info` were supplied; using the object's metadata and ignoring `model_info`.",
        call. = FALSE
      )
    }
    if (!identical(framework(model_code), "stan")) stop("`model_code` must contain Stan source.", call. = FALSE)
    model_info <- unclass(info(model_code))
  }
  if (!is.null(posterior)) {
    if (length(posterior_info)) {
      warning(
        "Both an existing PosteriorDB posterior object and `posterior_info` were supplied; using the object's metadata and ignoring `posterior_info`.",
        call. = FALSE
      )
    }
    posterior_fields <- c("name", "model_name", "data_name", "reference_posterior_name",
      "dimensions", "added_by", "added_date", "urls", "references", "keywords")
    posterior_info <- unclass(posterior)[intersect(names(unclass(posterior)), posterior_fields)]
  }
  validate_stan_input_data(data, "data")
  data_info <- validate_bundle_metadata(
    data_info,
    "data_info",
    allowed = c(
      "name",
      "title",
      "data_file",
      "added_by",
      "added_date",
      "description",
      "references",
      "urls",
      "keywords"
    )
  )
  model_info <- validate_bundle_metadata(
    model_info,
    "model_info",
    allowed = c(
      "name",
      "title",
      "framework",
      "model_implementations",
      "added_by",
      "added_date",
      "description",
      "references",
      "urls",
      "keywords",
      "prior",
      "licence"
    )
  )
  posterior_info <- validate_bundle_metadata(
    posterior_info,
    "posterior_info",
    allowed = c(
      "name",
      "model_name",
      "data_name",
      "reference_posterior_name",
      "dimensions",
      "added_by",
      "added_date",
      "urls",
      "references",
      "keywords"
    )
  )
  reference_info <- validate_bundle_metadata(
    reference_info,
    "reference_info",
    allowed = c("comments", "added_by", "added_date")
  )
  assert_bundle_required_metadata(data_info, model_info)
  expected_data_file <- paste0("data/data/", data_info$name, ".json")
  if (
    !is.null(data_info$data_file) &&
      !identical(data_info$data_file, expected_data_file)
  ) {
    stop(
      "`data_info$data_file` conflicts with the inferred data path.",
      call. = FALSE
    )
  }
  if (
    !is.null(model_info$framework) && !identical(model_info$framework, "stan")
  ) {
    stop(
      "`model_info$framework` conflicts with the inferred Stan framework.",
      call. = FALSE
    )
  }
  expected_impl <- list(
    stan = list(model_code = paste0("models/stan/", model_info$name, ".stan"))
  )
  if (!is.null(model_info$model_implementations)) {
    implementations <- model_info$model_implementations
    checkmate::assert_names(names(implementations), must.include = "stan")
    checkmate::assert_subset(names(implementations), "stan")
    stan_implementation <- implementations$stan
    checkmate::assert_list(stan_implementation)
    checkmate::assert_names(
      names(stan_implementation),
      must.include = "model_code",
      subset.of = c("model_code", "stan_version")
    )
    if (!identical(
      stan_implementation$model_code,
      expected_impl$stan$model_code
    )) {
      stop(
        "`model_info$model_implementations$stan$model_code` conflicts with the inferred Stan model path.",
        call. = FALSE
      )
    }
  }

  # Convert the fit into backend-neutral draws, dimensions, and provenance.
  extracted <- extract_external_stan_fit(
    fit,
    checks = "all",
    strict = FALSE,
    for_bundle = TRUE,
    compute_diagnostics = check,
    include = include,
    exclude = exclude,
    data = data
  )
  assemble_standalone_fit_bundle(
    extracted = extracted,
    resolved_data = resolved_data,
    data_info = data_info,
    model_info = model_info,
    posterior_info = posterior_info,
    reference_info = reference_info,
    added_by = added_by,
    added_date = added_date,
    include = include,
    exclude = exclude,
    check = check,
    pdb = pdb,
    expected_data_file = expected_data_file,
    existing_data = existing_data,
    existing_model_code = model_code,
    existing_posterior = posterior
  )
}

# Construct bundle objects from resolved values and the backend-neutral
# extraction record. This helper must not inspect a backend fit object.
assemble_standalone_fit_bundle <- function(
  extracted,
  resolved_data,
  data_info,
  model_info,
  posterior_info,
  reference_info,
  added_by,
  added_date,
  include = NULL,
  exclude = NULL,
  check = TRUE,
  pdb = NULL,
  expected_data_file,
  existing_data = NULL,
  existing_model_code = NULL,
  existing_posterior = NULL
) {
  data <- resolved_data$data
  draws_array <- extracted$draws
  all_vars <- setdiff(posterior::variables(draws_array), "lp__")
  bases <- unique(sub("\\[.*$", "", all_vars))
  # Extraction already selected complete saved outputs using the model schema.
  chosen_bases <- bases
  chosen <- all_vars
  if (!length(chosen)) {
    stop("Variable selection leaves no saved draws.", call. = FALSE)
  }
  dimensions <- extracted$dimensions
  if (!length(dimensions)) {
    stop("The selected draws contain no unconstrained model parameters; posterior dimensions cannot be inferred from derived quantities alone.", call. = FALSE)
  }
  draws <- posterior::as_draws_list(draws_array)

  added_by <- added_by %||% unname(Sys.info()[["user"]])
  added_date <- added_date %||% Sys.Date()
  checkmate::assert_string(added_by)
  checkmate::assert_class(added_date, "Date")
  data_info <- make_bundle_info(data_info, added_by, added_date)
  data_info$data_file <- expected_data_file
  model_info <- make_bundle_info(model_info, added_by, added_date)
  stan_version <- if (
    !is.null(model_info$model_implementations) &&
      "stan_version" %in% names(model_info$model_implementations$stan)
  ) {
    model_info$model_implementations$stan$stan_version
  } else {
    ">=2.26.0"
  }
  model_info$framework <- NULL
  model_info$model_implementations <- NULL
  # Keep supplied data as a normal pdb_data object for both memory and writing.
  dat <- existing_data %||% as.pdb_data(data, info = as.pdb_data_info(data_info))
  mi <- as.pdb_model_info(c(model_info, list(framework = "stan")))
  mi$model_implementations$stan["stan_version"] <- list(stan_version)
  code <- extracted$source
  if (!is.null(existing_model_code) &&
      !identical(
        normalize_stan_model_code(existing_model_code),
        normalize_stan_model_code(code)
      )) {
    stop("The supplied model code does not match the source embedded in `fit`.", call. = FALSE)
  }
  mc <- existing_model_code %||% as.pdb_model_code(code, info = mi, framework = "stan")
  if (!identical(info(mc)$name, model_info$name)) stop("The supplied model-code name conflicts with the resolved model metadata.", call. = FALSE)
  if (!is.null(pdb)) {
    if (is.null(existing_data)) pdb(dat) <- pdb
    if (is.null(existing_model_code)) pdb(mc) <- pdb
  }

  structural <- list(
    name = paste(data_info$name, model_info$name, sep = "-"),
    model_name = model_info$name,
    data_name = data_info$name,
    reference_posterior_name = paste(
      data_info$name,
      model_info$name,
      sep = "-"
    ),
    dimensions = dimensions
  )
  for (key in intersect(names(posterior_info), names(structural))) {
    expected <- structural[[key]]
    if (!is.null(posterior_info[[key]]) &&
        !identical(posterior_info[[key]], expected)) {
      stop(
        "`posterior_info$",
        key,
        "` conflicts with the inferred value.",
        call. = FALSE
      )
    }
  }
  if (!is.null(existing_posterior)) {
    expected_fields <- c(
      name = "name", model_name = "model_name", data_name = "data_name",
      reference_posterior_name = "reference_posterior_name"
    )
    conflicts <- expected_fields[vapply(names(expected_fields), function(key) {
      !is.null(existing_posterior[[key]]) &&
        !identical(existing_posterior[[key]], structural[[key]])
    }, logical(1))]
    if (length(conflicts)) stop("The supplied posterior does not link to the resolved data and model objects.", call. = FALSE)
    if (!identical(existing_posterior$dimensions, dimensions)) stop("The supplied posterior's unconstrained dimensions do not match the fitted model and selected variables.", call. = FALSE)
  }
  po_fields <- posterior_info[setdiff(
    names(posterior_info),
    c("added_by", "added_date", names(structural))
  )]
  if (check) {
    # Diagnostics must be attached before summaries can be accepted or built.
    diagnostic_report <- bundle_full_diagnostic_report(
      extracted,
      include = chosen_bases
    )
  } else {
    # Keep only structural counts needed to print and serialize the unchecked
    # object. Do not calculate acceptance or informational draw metrics.
    diagnostic_report <- list(
      checks = character(),
      metrics = list(
        ndraws = posterior::ndraws(draws_array),
        nchains = posterior::nchains(draws_array)
      ),
      thresholds = list(),
      status = NULL,
      failures = NULL
    )
  }
  diagnostic_report$checked <- check
  diagnostic_info <- bundle_reference_diagnostic_info(
    diagnostic_report$metrics,
    posterior::ndraws(draws_array),
    posterior::nchains(draws_array),
    posterior::variables(draws_array)
  )
  rinfo <- new_bundle_reference_info(
    reference_info,
    extracted$metadata,
    diagnostic_info,
    structural$reference_posterior_name,
    added_by,
    added_date
  )
  rpd <- as.pdb_reference_posterior_draws(draws, info = rinfo)
  if (!is.null(pdb)) {
    pdb(rpd) <- pdb
  }
  attr(rpd, "sampler_diagnostics") <- extracted$sampler_diagnostics
  attr(rpd, "sampling_metadata") <- extracted$metadata
  if (check) {
    rpd <- attach_bundle_check_result(rpd, diagnostic_report)
  } else {
    diagnostic_report$status <- NULL
    diagnostic_report$failures <- NULL
  }
  summary_statistics <- bundle_summary_statistics(rpd)
  reused_components <- c(
    data = bundle_component_is_database_backed(existing_data),
    model_code = bundle_component_is_database_backed(existing_model_code),
    posterior = bundle_component_is_database_backed(existing_posterior)
  )
  if (!is.null(existing_posterior)) {
    # Embed components so the returned bundle remains usable before persistence.
    existing_posterior$reference_posterior_name <- structural$reference_posterior_name
    existing_posterior$embedded_data <- dat
    existing_posterior$embedded_model_code <- mc
    existing_posterior$embedded_reference_draws <- rpd
    assert_pdb_posterior(existing_posterior)
  }
  po <- existing_posterior %||% as.pdb_posterior(
    c(
      structural,
      list(pdb_data = dat, pdb_model_code = mc),
      po_fields,
      list(
        added_by = posterior_info$added_by %||% added_by,
        added_date = posterior_info$added_date %||% added_date,
        embedded_data = dat,
        embedded_model_code = mc,
        embedded_reference_draws = rpd
      )
    ),
    pdb = pdb
  )
  if (!is.null(pdb) && is.null(existing_posterior)) {
    pdb(po) <- pdb
  }
  bundle <- list(
    data = dat,
    model_code = mc,
    posterior = po,
    reference_draws = rpd,
    summary_statistics = summary_statistics,
    diagnostics = if (check) diagnostic_report else NULL,
    provenance = list(
      data_source = resolved_data$source,
      fit_class = extracted$fit_class,
      selected_variables = chosen,
      reused_components = reused_components,
      sampling_metadata = extracted$metadata,
      imported_at = Sys.time(),
      import_versions = c(
        extracted$import_versions,
        list(posteriordb = as.character(utils::packageVersion("posteriordb")))
      )
    )
  )
  class(bundle) <- c("pdb_reference_bundle", "list")
  bundle
}

bundle_component_is_database_backed <- function(x) {
  !is.null(x) && !is.null(tryCatch(pdb(x), error = function(error) NULL))
}

#' @rdname check_reference_posterior_draws
#' @exportS3Method
check_reference_posterior_draws.pdb_reference_bundle <- function(x, ...) {
  if (length(list(...))) {
    stop("`check_reference_posterior_draws()` does not accept extra arguments for a bundle.",
         call. = FALSE)
  }
  draws <- x$reference_draws
  extracted <- list(
    draws = posterior::as_draws_array(draws),
    sampler_diagnostics = attr(draws, "sampler_diagnostics"),
    metadata = attr(draws, "sampling_metadata"),
    fit_class = x$provenance$fit_class
  )
  if (is.null(extracted$metadata)) {
    stop("The bundle has no saved sampling metadata needed for diagnostics.",
         call. = FALSE)
  }
  report <- bundle_full_diagnostic_report(
    extracted
  )
  report$checked <- TRUE
  draws <- attach_bundle_check_result(draws, report)
  x$reference_draws <- draws
  x$posterior$embedded_reference_draws <- draws
  x$summary_statistics <- bundle_summary_statistics(draws)
  x$diagnostics <- report
  x
}

# Compute the persisted summary statistics only after the bundle's reference
# draw checks pass. The summary statistic writer has its own acceptance
# assertion, which uses `ndraws_is_gte_10k` instead of the bundle's stricter
# exact-draw-count flag. Preserve separate info objects for the draws and the
# summaries, and use the existing summary-statistic constructors and writers.
bundle_summary_statistics <- function(draws) {
  draw_checks <- info(draws)$checks_made
  required_draw_checks <- required_reference_draw_checks(info(draws)$inference$method)
  if (!all(vapply(required_draw_checks, function(key) {
    isTRUE(draw_checks[[key]])
  }, logical(1)))) {
    return(NULL)
  }
  summary_statistics_from_checked_reference_draws(draws)
}

bundle_full_diagnostic_report <- function(extracted, include = NULL) {
  draws <- extracted$draws
  report <- reference_draw_diagnostics_from_extracted(
    extracted,
    checks = "all",
    include = include
  )
  report$metrics$effective_sample_size_bulk <- reference_variable_diagnostic(draws, posterior::ess_bulk)
  report$metrics$effective_sample_size_tail <- reference_variable_diagnostic(draws, posterior::ess_tail)
  sampler_vars <- if (is.null(extracted$sampler_diagnostics)) {
    character()
  } else {
    posterior::variables(extracted$sampler_diagnostics)
  }
  if ("treedepth__" %in% sampler_vars) {
    sampler_depth <- matrix(
      extracted$sampler_diagnostics[,, "treedepth__"],
      nrow = dim(draws)[1L],
      ncol = dim(draws)[2L]
    )
    report$metrics$max_treedepth_observed_by_chain <- stats::setNames(
      apply(sampler_depth, 2L, max, na.rm = TRUE),
      paste0("chain", seq_len(posterior::nchains(draws)))
    )
  }
  report$metrics$max_treedepth <- extracted$metadata$max_treedepth %||% NULL
  report
}

attach_bundle_check_result <- function(draws, report) {
  passed <- all(unlist(report$status, use.names = FALSE))
  ri <- info(draws)
  ri$diagnostics <- bundle_reference_diagnostic_info(
    report$metrics,
    posterior::ndraws(draws),
    posterior::nchains(draws),
    posterior::variables(draws)
  )
  if (passed) {
    ri$checks_made <- bundle_acceptance_flags()
  } else {
    ri$checks_made <- list(
      check_failed = paste(names(report$failures), collapse = ", "),
      diagnostic_report = report
    )
  }
  info(draws) <- ri
  attr(draws, "diagnostic_report") <- report
  if (passed) {
    assert_reference_posterior_draws(draws)
    assert_checked_reference_posterior_draws(draws)
  }
  draws
}

#' @exportS3Method
create_pdb_bundle.default <- function(fit, ...) {
  stop(
    "Unsupported fit class. `create_pdb_bundle()` currently accepts only `rstan::stanfit`.",
    call. = FALSE
  )
}

validate_bundle_call_dots <- function(dots) {
  allowed <- c(
    "data_info",
    "model_code",
    "posterior",
    "model_info",
    "posterior_info",
    "reference_info",
    "include",
    "exclude",
    "check",
    "pdb"
  )
  supplied <- names(dots)
  if (
    length(dots) &&
      (is.null(supplied) || anyNA(supplied) || any(!nzchar(supplied)))
  ) {
    stop(
      "Arguments after `added_date` must be named exactly; use `data_info`, `model_code`, `model_info`, `posterior`, `posterior_info`, `reference_info`, `include`, `exclude`, `check`, or `pdb`.",
      call. = FALSE
    )
  }
  if (anyDuplicated(supplied)) {
    stop(
      "Duplicate argument(s) in `...`: ",
      paste(unique(supplied[duplicated(supplied)]), collapse = ", "),
      call. = FALSE
    )
  }
  unknown <- setdiff(supplied, allowed)
  if (length(unknown)) {
    stop(
      "Unknown argument(s) in `...`: ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Print a standalone reference-draw bundle
#' @param x A `pdb_reference_bundle` returned by [create_pdb_bundle()].
#' @param ... Unused.
#' @export
print.pdb_reference_bundle <- function(x, ...) {
  cat(
    "PosteriorDB reference bundle: ",
    x$data_info$name %||% info(x$data)$name,
    "-",
    info(x$model_code)$name,
    "\n",
    sep = ""
  )
  cat(
    "Variables: ",
    paste(x$provenance$selected_variables, collapse = ", "),
    "\n",
    sep = ""
  )
  metrics <- x$diagnostics$metrics %||% list(
    ndraws = x$provenance$sampling_metadata$ndraws,
    nchains = x$provenance$sampling_metadata$nchains
  )
  cat(
    "Draws: ",
    metrics$ndraws,
    " across ",
    metrics$nchains,
    " chains\n",
    sep = ""
  )
  checks <- info(x$reference_draws)$checks_made
  status <- if (!isTRUE(x$diagnostics$checked)) {
    "unchecked"
  } else if (!is.null(checks$check_failed)) {
    "failed"
  } else {
    "passed"
  }
  cat("Checks: ", status, "\n", sep = "")
  invisible(x)
}

# Contract: extraction returns draws as a posterior draws_array (iteration,
# chain, scalar-variable), matching sampler_diagnostics dimensions and a
# metadata list. Saved array variables are scalar names like theta[1,2].
resolve_standalone_fit_data <- function(data) {
  if (is.null(data)) {
    stop("`data` is required. Pass the actual named Stan input list; fit-data recovery is not supported.",
         call. = FALSE)
  }
  object <- NULL
  if (inherits(data, "pdb_data")) {
    object <- data
    data <- lapply(seq_along(object), function(i) object[[i]])
    names(data) <- names(object)
  }
  if (!is.list(data)) {
    stop(
      "Supplied `data` must be a list.",
      call. = FALSE
    )
  }
  if (
    length(data) &&
      (is.null(names(data)) ||
        anyNA(names(data)) ||
        any(!nzchar(names(data))) ||
        anyDuplicated(names(data)))
  ) {
    stop(
      "Supplied `data` must be a named list with unique, non-empty input names (or `list()` for no inputs).",
      call. = FALSE
    )
  }
  list(data = data, source = "caller-supplied", object = object)
}

# Each named input is one ordinary finite numeric, integer, or logical
# vector/array. Standard names and dimension attributes are preserved.
validate_stan_input_data <- function(x, path) {
  if (
    !is.list(x) ||
      is.object(x) ||
      isS4(x) ||
      length(setdiff(names(attributes(x)), "names"))
  ) {
    stop(
      "`data` must be a named list of ordinary numeric, integer, or logical vectors and arrays.",
      call. = FALSE
    )
  }
  if (
    length(x) &&
      (is.null(names(x)) ||
        anyNA(names(x)) ||
        any(!nzchar(names(x))) ||
        anyDuplicated(names(x)))
  ) {
    stop(
      "`data` must have unique, non-empty input names (or be `list()`).",
      call. = FALSE
    )
  }
  for (i in seq_along(x)) {
    value <- x[[i]]
    name <- names(x)[[i]]
    attrs <- attributes(value)
    if (
      !is.atomic(value) ||
        is.object(value) ||
        isS4(value) ||
        !typeof(value) %in% c("double", "integer", "logical") ||
        any(!is.finite(value)) ||
        length(setdiff(names(attrs), c("names", "dim", "dimnames")))
    ) {
      stop(
        "`data$",
        name,
        "` must be an ordinary numeric, integer, or logical vector or array.",
        call. = FALSE
      )
    }
  }
  invisible(x)
}

validate_bundle_metadata <- function(x, arg, allowed) {
  checkmate::assert_list(x, .var.name = arg)
  if (!length(x)) {
    return(x)
  }
  if (
    is.null(names(x)) ||
      anyNA(names(x)) ||
      any(!nzchar(names(x))) ||
      anyDuplicated(names(x))
  ) {
    stop("`", arg, "` must have unique, non-empty field names.", call. = FALSE)
  }
  unknown <- setdiff(names(x), allowed)
  if (length(unknown)) {
    stop(
      "Unknown field(s) in `",
      arg,
      "`: ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  x
}

assert_metadata_pair <- function(x, arg, fields) {
  missing <- fields[
    !fields %in% names(x) |
      vapply(
        fields,
        function(field) {
          is.null(x[[field]])
        },
        logical(1)
      )
  ]
  if (length(missing)) {
    return(missing)
  }
  assert_pdb_resource_name(x$name)
  checkmate::assert_string(x$title)
  character()
}

assert_bundle_required_metadata <- function(data_info, model_info) {
  missing_data <- assert_metadata_pair(
    data_info,
    "data_info",
    c("name", "title")
  )
  missing_model <- assert_metadata_pair(
    model_info,
    "model_info",
    c("name", "title")
  )
  missing_required <- c(
    if (length(missing_data)) paste0("data_info$", missing_data),
    if (length(missing_model)) paste0("model_info$", missing_model)
  )
  if (length(missing_required)) {
    stop(
      "Missing required metadata fields: ",
      paste(missing_required, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

make_bundle_info <- function(x, added_by, added_date) {
  x$added_by <- x$added_by %||% added_by
  x$added_date <- x$added_date %||% added_date
  x
}

validate_variable_selection <- function(x, arg) {
  if (is.null(x)) {
    return(NULL)
  }
  checkmate::assert_character(x, any.missing = FALSE,
                              min.len = if (arg == "include") 0L else 1L)
  if (any(!nzchar(x)) || anyDuplicated(x)) {
    stop(
      "`",
      arg,
      "` must contain unique, non-empty base names.",
      call. = FALSE
    )
  }
  x
}

new_bundle_reference_info <- function(
  x,
  metadata,
  diagnostics,
  name,
  added_by,
  added_date
) {
  args <- metadata$method_arguments %||% list()
  info <- list(
    name = name,
    inference = list(method = "stan_sampling", method_arguments = args),
    diagnostics = diagnostics,
    checks_made = NULL,
    comments = x$comments %||%
      paste0("Imported from an externally sampled rstan::stanfit."),
    added_by = x$added_by %||% added_by,
    added_date = x$added_date %||% added_date,
    # These describe the R environment used to assemble the bundle; a fit
    # object does not reliably preserve its original package/session versions.
    versions = pdb_stan_sampling_versions()
  )
  as.pdb_reference_posterior_info(info)
}

bundle_reference_diagnostic_info <- function(metrics, ndraws, nchains, variables) {
  get_metric <- function(key, default) {
    value <- metrics[[key]]
    if (is.null(value) || identical(value, "unavailable")) default else value
  }
  list(
    diagnostic_information = list(names = variables),
    ndraws = as.integer(ndraws),
    nchains = as.integer(nchains),
    effective_sample_size_bulk = get_metric(
      "effective_sample_size_bulk",
      rep(NA_real_, 0L)
    ),
    effective_sample_size_tail = get_metric(
      "effective_sample_size_tail",
      rep(NA_real_, 0L)
    ),
    mean_lag1_ac = get_metric("mean_lag1_ac", rep(NA_real_, 0L)),
    r_hat = get_metric("r_hat", rep(NA_real_, 0L)),
    divergent_transitions = get_metric(
      "divergent_transitions",
      rep(NA_real_, nchains)
    ),
    expected_fraction_of_missing_information = get_metric(
      "efmi",
      rep(NA_real_, nchains)
    )
  )
}

bundle_acceptance_flags <- function() {
  checks <- required_reference_draw_checks("stan_sampling")
  stats::setNames(rep(list(TRUE), length(checks)), checks)
}

normalize_stan_model_code <- function(x) {
  code <- paste(as.character(x), collapse = "\n")
  code <- gsub("\r\n?", "\n", code)
  sub("\n+$", "", code)
}
