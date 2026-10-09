#' Build a PosteriorDB reference-draw bundle from a Stan fit
#'
#' Builds linked data, model, posterior and reference-draw objects from an
#' already sampled `rstan::stanfit`, and checks the draws. Nothing is sampled
#' and nothing is written; write the result with [write_pdb()].
#'
#' Describe new data and a new model with `data_info` and `model_info`, or
#' reuse objects that are already in a database by passing them, or their
#' saved names, as `data`, `model_code` or `posterior`.
#'
#' @param fit A completed `rstan::stanfit` object.
#' @param data The exact named list of data passed to Stan, a `pdb_data`
#'   object, or the name of data saved in `pdb`. Use `list()` for a model
#'   without data. May be omitted only when `posterior` supplies its linked
#'   data. Data cannot be recovered from the fit.
#' @param model_code Optional `pdb_model_code` object or saved model name.
#'   Its Stan code must match the code in `fit`.
#' @param posterior Optional `pdb_posterior` object or saved posterior name.
#'   Its data, model and `dimensions` must match the bundle. If `data` and
#'   `model_code` are omitted, the posterior's linked data and model are used.
#' @param added_by Contributor name recorded for the new objects. Defaults to
#'   the current system user. A value in one of the `*_info` lists overrides
#'   it for that object.
#' @param added_date Contribution date recorded for the new objects. Defaults
#'   to today. A value in one of the `*_info` lists overrides it for that
#'   object.
#' @param data_info Named list describing new data. `name` and `title` are
#'   required; `description`, `references`, `urls` and `keywords` are
#'   optional. Names become file names, so they cannot contain slashes. Use
#'   underscores rather than hyphens, because posteriors are named
#'   `data_name-model_name`.
#' @param model_info Named list describing a new model. `name` and `title`
#'   are required; `description`, `references`, `urls`, `keywords`, `prior`
#'   and `licence` are optional. Names follow the same rules as in
#'   `data_info`. Set `framework = "stan"` to store the model code as
#'   `models/stan/<name>.stan` with the Stan version requirement
#'   `">=2.26.0"`, or supply `model_implementations` yourself to record a
#'   different `stan_version`. Priors are not inferred from the Stan code.
#' @param posterior_info Named list of optional posterior metadata:
#'   `references`, `urls`, `keywords`, `added_by` and `added_date`. The
#'   posterior's name, its links to the data and model, and its `dimensions`
#'   are worked out from the fit; if you supply them, they must match.
#' @param reference_info Named list of optional notes for the reference
#'   draws: `comments`, `added_by` and `added_date`.
#' @param include Base names of saved variables to keep. The default `NULL`
#'   (or `"all"`) keeps every saved output except `lp__`. `"none"` (or
#'   `character(0)`) keeps only the model's parameters, which are always
#'   kept. A base name selects all of that variable's elements. Note that
#'   `c()` is `NULL` and therefore keeps everything.
#' @param exclude Base names of saved variables to drop. The default `NULL`
#'   (or `"none"`) drops nothing; `"all"` drops everything except the
#'   model's parameters. Excluding a parameter, naming a variable in both
#'   `include` and `exclude`, or using an unknown name is an error.
#' @param check Whether to run the reference-draw checks now. With `FALSE`
#'   the draws are left unchecked; check them later with
#'   [check_reference_posterior_draws()].
#' @param pdb Optional PosteriorDB connection. It is used to look up objects
#'   passed by name and is attached to the new objects. Nothing is written
#'   to it.
#' @param ... The arguments listed above, passed by name. Only `fit`, `data`,
#'   `added_by` and `added_date` can be passed by position. Unknown or
#'   misspelled arguments are an error.
#'
#' @return A `pdb_reference_bundle` list with `data`, `model_code`,
#'   `posterior`, `reference_draws`, `summary_statistics`, `diagnostics` and
#'   `provenance`. `summary_statistics` holds `mean_value` and
#'   `mean_squared_value` when the checks pass and is `NULL` otherwise.
#'   `diagnostics` is `NULL` when `check = FALSE`.
#' @details
#' The posterior's `dimensions` hold the number of unconstrained parameters
#' for each model parameter, not the shape of the saved variable. Transformed
#' parameters and generated quantities are saved as draws but have no entry.
#'
#' A failed check does not raise an error. The bundle is returned with the
#' failures recorded in `diagnostics`, and its draws cannot be written.
#'
#' Reused objects are compared with the fit. If you pass both an existing
#' object and its `*_info` list, the list is ignored with a warning. See
#' [write_pdb()] for how reused objects are treated when the bundle is
#' written.
#'
#' The package cannot confirm that `data` is the data the fit was sampled
#' with. If a `stanfit` was saved and reloaded in a new R session, the model
#' may be recompiled to work out the parameter counts; the fit is not
#' resampled.
#'
#' ```r
#' bundle <- create_pdb_bundle(
#'   fit, data = stan_data,
#'   data_info = list(name = "study", title = "Study inputs"),
#'   model_info = list(name = "normal", title = "Normal model",
#'                     framework = "stan"),
#'   include = c("mu", "sigma")
#' )
#' bundle$diagnostics$status
#' bundle$reference_draws
#' ```
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
  if (
    is.character(model_code) &&
      length(model_code) == 1L &&
      !inherits(model_code, "pdb_model_code")
  ) {
    model_code <- if (is.null(pdb)) {
      pdb_model_code(model_code, framework = "stan")
    } else {
      pdb_model_code(model_code, framework = "stan", pdb = pdb)
    }
  }
  if (is.character(posterior) && length(posterior) == 1L) {
    posterior <- if (is.null(pdb)) {
      pdb_posterior(posterior)
    } else {
      pdb_posterior(posterior, pdb = pdb)
    }
  }
  if (!is.null(model_code)) {
    checkmate::assert_class(model_code, "pdb_model_code")
  }
  if (!is.null(posterior)) {
    checkmate::assert_class(posterior, "pdb_posterior")
  }
  if (!is.null(posterior)) {
    # A supplied posterior can fill in its linked data and Stan source.
    if (is.null(data)) {
      data <- get_data(posterior)
    }
    if (is.null(model_code)) {
      model_code <- model_code(posterior, framework = "stan")
    }
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
    if (!identical(framework(model_code), "stan")) {
      stop("`model_code` must contain Stan source.", call. = FALSE)
    }
    model_info <- unclass(info(model_code))
  }
  if (!is.null(posterior)) {
    if (length(posterior_info)) {
      warning(
        "Both an existing PosteriorDB posterior object and `posterior_info` were supplied; using the object's metadata and ignoring `posterior_info`.",
        call. = FALSE
      )
    }
    posterior_fields <- c(
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
    posterior_info <- unclass(posterior)[intersect(
      names(unclass(posterior)),
      posterior_fields
    )]
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
    # A reused model keeps its other implementations; new models are Stan-only.
    if (is.null(model_code)) {
      checkmate::assert_subset(names(implementations), "stan")
    }
    stan_implementation <- implementations$stan
    checkmate::assert_list(stan_implementation)
    checkmate::assert_names(
      names(stan_implementation),
      must.include = "model_code",
      subset.of = c("model_code", "stan_version")
    )
    if (
      !identical(
        stan_implementation$model_code,
        expected_impl$stan$model_code
      )
    ) {
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
  # Extraction already selected complete saved outputs using the model schema.
  chosen <- all_vars
  if (!length(chosen)) {
    stop("Variable selection leaves no saved draws.", call. = FALSE)
  }
  dimensions <- extracted$dimensions
  if (!length(dimensions)) {
    stop(
      "The selected draws contain no unconstrained model parameters; posterior dimensions cannot be inferred from derived quantities alone.",
      call. = FALSE
    )
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
  dat <- existing_data %||%
    as.pdb_data(data, info = as.pdb_data_info(data_info))
  mi <- as.pdb_model_info(c(model_info, list(framework = "stan")))
  mi$model_implementations$stan["stan_version"] <- list(stan_version)
  code <- extracted$source
  if (
    !is.null(existing_model_code) &&
      !identical(
        normalize_stan_model_code(existing_model_code),
        normalize_stan_model_code(code)
      )
  ) {
    stop(
      "The supplied model code does not match the source embedded in `fit`.",
      call. = FALSE
    )
  }
  mc <- existing_model_code %||%
    as.pdb_model_code(code, info = mi, framework = "stan")
  if (!identical(info(mc)$name, model_info$name)) {
    stop(
      "The supplied model-code name conflicts with the resolved model metadata.",
      call. = FALSE
    )
  }
  if (!is.null(pdb)) {
    if (is.null(existing_data)) {
      pdb(dat) <- pdb
    }
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
    same <- if (key == "dimensions") same_dimension_counts else identical
    if (
      !is.null(posterior_info[[key]]) &&
        !same(posterior_info[[key]], expected)
    ) {
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
      name = "name",
      model_name = "model_name",
      data_name = "data_name",
      reference_posterior_name = "reference_posterior_name"
    )
    conflicts <- expected_fields[vapply(
      names(expected_fields),
      function(key) {
        !is.null(existing_posterior[[key]]) &&
          !identical(existing_posterior[[key]], structural[[key]])
      },
      logical(1)
    )]
    if (length(conflicts)) {
      stop(
        "The supplied posterior does not link to the resolved data and model objects.",
        call. = FALSE
      )
    }
    if (!same_dimension_counts(existing_posterior$dimensions, dimensions)) {
      stop(
        "The supplied posterior's unconstrained dimensions do not match the fitted model and selected variables.",
        call. = FALSE
      )
    }
  }
  po_fields <- posterior_info[setdiff(
    names(posterior_info),
    c("added_by", "added_date", names(structural))
  )]
  if (check) {
    # Diagnostics must be attached before summaries can be accepted or built.
    diagnostic_report <- bundle_full_diagnostic_report(extracted)
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
  po <- existing_posterior %||%
    as.pdb_posterior(
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
    stop(
      "`check_reference_posterior_draws()` does not accept extra arguments for a bundle.",
      call. = FALSE
    )
  }
  draws <- x$reference_draws
  extracted <- list(
    draws = posterior::as_draws_array(draws),
    sampler_diagnostics = attr(draws, "sampler_diagnostics"),
    metadata = attr(draws, "sampling_metadata"),
    fit_class = x$provenance$fit_class
  )
  if (is.null(extracted$metadata)) {
    stop(
      "The bundle has no saved sampling metadata needed for diagnostics.",
      call. = FALSE
    )
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
  required_draw_checks <- required_reference_draw_checks(
    info(draws)$inference$method
  )
  if (
    !all(vapply(
      required_draw_checks,
      function(key) {
        isTRUE(draw_checks[[key]])
      },
      logical(1)
    ))
  ) {
    return(NULL)
  }
  summary_statistics_from_checked_reference_draws(draws)
}

bundle_full_diagnostic_report <- function(extracted) {
  draws <- extracted$draws
  report <- reference_draw_diagnostics_from_extracted(
    extracted,
    checks = "all"
  )
  report$metrics$effective_sample_size_bulk <- reference_variable_diagnostic(
    draws,
    posterior::ess_bulk
  )
  report$metrics$effective_sample_size_tail <- reference_variable_diagnostic(
    draws,
    posterior::ess_tail
  )
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
    ri$checks_made <- c(
      bundle_acceptance_flags(),
      list(ess_within_bounds = ess_within_bounds(draws, ri))
    )
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
  metrics <- x$diagnostics$metrics %||%
    list(
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
    stop(
      "`data` is required. Pass the actual named Stan input list; fit-data recovery is not supported.",
      call. = FALSE
    )
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

bundle_acceptance_flags <- function() {
  checks <- required_reference_draw_checks("stan_sampling")
  stats::setNames(rep(list(TRUE), length(checks)), checks)
}

normalize_stan_model_code <- function(x) {
  code <- paste(as.character(x), collapse = "\n")
  code <- gsub("\r\n?", "\n", code)
  sub("\n+$", "", code)
}
