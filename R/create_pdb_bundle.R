#' Construct a standalone PosteriorDB reference-draw bundle from a Stan fit
#'
#' Build linked data, model, posterior, and reference-draw objects around an
#' already sampled `rstan::stanfit`. This function does not compile, sample,
#' access a database, or write files. Supply the actual Stan input list and
#' human labels; data recovery is reserved for a future backend.
#'
#' The default variable selection includes saved parameters, transformed
#' parameters, and generated quantities, except `lp__`. `include` and
#' `exclude` select base variable names, so `include = "theta"` retains all
#' saved scalar elements of an array parameter.
#'
#' @param fit A completed `rstan::stanfit` object.
#' @param data The exact named Stan input list, with ordinary numeric,
#'   integer, or logical vectors/arrays as values. `list()` explicitly declares
#'   an empty input; `NULL` is currently unavailable and errors.
#' @param added_by Shared default contributor name for the constructed data,
#'   model, posterior, and reference-draw metadata. Defaults to the current R
#'   user. Values supplied in the corresponding metadata lists take precedence.
#' @param added_date Shared default contribution date for the constructed
#'   objects. Defaults to the current date when the function is called.
#'   Values supplied in the corresponding metadata lists take precedence.
#' @param data_info Named data metadata. `name` and `title` are required;
#'   supported descriptive fields are `description`, `references`, `urls`,
#'   and `keywords`.
#' @param model_info Named model metadata. `name` and `title` are required;
#'   supported descriptive fields are `description`, `references`, `urls`,
#'   `keywords`, `prior`, and `licence`.
#' @param posterior_info Named posterior metadata. Optional `added_by` and
#'   `added_date` values override the shared defaults for the posterior.
#'   Optional structural fields
#'   (`name`, `model_name`, `data_name`, `reference_posterior_name`, and
#'   `dimensions`) are accepted only when they match inferred values.
#' @param reference_info Named human annotations for the reference draws,
#'   such as `comments`, `added_by`, and `added_date`. The inference method
#'   and version provenance are derived from the fit. Diagnostics and
#'   `checks_made` are calculated internally.
#' @param include Optional character vector of base variable names to retain.
#' @param exclude Optional character vector of base variable names to omit.
#' @param check Whether to evaluate the package's reference-draw acceptance
#'   checks. `FALSE` leaves the candidate explicitly unchecked and skips
#'   draw-diagnostic and acceptance-metric calculations.
#' @param pdb Optional PosteriorDB connection to attach for later use. This
#'   constructor never reads from or writes to it.
#' @param ... Named method options: `data_info`, `model_info`, `posterior_info`,
#'   `reference_info`, `include`, `exclude`, `check`, and
#'   `pdb`. Unnamed, duplicate, misspelled, or other arguments are rejected.
#'
#' @return A `pdb_reference_bundle` list containing `data`, `model_code`,
#'   `posterior`, `reference_draws`, `diagnostics`, and `provenance`.
#'   `diagnostics` is `NULL` when `check = FALSE`; call
#'   [check_reference_posterior_draws()] on that bundle to check it later.
#' @details
#' The bundle embeds its content in memory and remains usable before database
#' persistence. Supplied data is recorded as caller-supplied; this function
#' cannot establish that it produced the fit. With `check = FALSE`, raw
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
  resolved_data <- resolve_standalone_fit_data(fit, data)
  data <- resolved_data$data
  validate_stan_input_data(data, "data")
  data_info <- validate_bundle_metadata(
    data_info,
    "data_info",
    required = character(),
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
    required = character(),
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
    required = character(),
    allowed = c(
      "name",
      "model_name",
      "data_name",
      "reference_posterior_name",
      "dimensions",
      "added_by",
      "added_date"
    )
  )
  reference_info <- validate_bundle_metadata(
    reference_info,
    "reference_info",
    required = character(),
    allowed = c("comments", "added_by", "added_date")
  )
  if (
    any(
      c("diagnostics", "checks_made", "passed", "accepted") %in%
        names(reference_info)
    )
  ) {
    stop(
      "`reference_info` cannot supply diagnostics or acceptance evidence.",
      call. = FALSE
    )
  }
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
  if (
    !is.null(model_info$model_implementations) &&
      !identical(model_info$model_implementations, expected_impl)
  ) {
    stop(
      "`model_info$model_implementations` conflicts with the inferred Stan model path.",
      call. = FALSE
    )
  }

  extracted <- extract_rstan_fit(
    fit,
    checks = "all",
    strict = FALSE,
    for_bundle = TRUE,
    compute_diagnostics = check,
    include = include,
    exclude = exclude
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
    expected_data_file = expected_data_file
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
  expected_data_file
) {
  data <- resolved_data$data
  draws_array <- extracted$draws
  all_vars <- setdiff(posterior::variables(draws_array), "lp__")
  bases <- unique(sub("\\[.*$", "", all_vars))
  include <- validate_variable_selection(include, "include")
  exclude <- validate_variable_selection(exclude, "exclude")
  chosen_bases <- setdiff(
    if (is.null(include)) bases else include,
    exclude %||% character()
  )
  chosen <- all_vars
  if (!length(chosen)) {
    stop("Variable selection leaves no saved draws.", call. = FALSE)
  }
  dimensions <- extracted$dimensions[chosen_bases]
  # PosteriorDB represents scalar parameters with a dimension of 1. Fit
  # extractors represent them as integer(0), so normalize at the bundle
  # boundary where PosteriorDB metadata is assembled.
  dimensions <- lapply(dimensions, function(axes) {
    if (!length(axes)) 1L else axes
  })
  draws <- posterior::as_draws_list(draws_array)

  added_by <- added_by %||% unname(Sys.info()[["user"]])
  added_date <- added_date %||% Sys.Date()
  checkmate::assert_string(added_by)
  checkmate::assert_class(added_date, "Date")
  data_info <- make_bundle_info(data_info, added_by, added_date)
  data_info$data_file <- expected_data_file
  model_info <- make_bundle_info(model_info, added_by, added_date)
  model_info$framework <- NULL
  model_info$model_implementations <- NULL
  dat <- as.pdb_data(data, info = as.pdb_data_info(data_info))
  mi <- as.pdb_model_info(c(model_info, list(framework = "stan")))
  code <- extracted$source
  mc <- as.pdb_model_code(code, info = mi, framework = "stan")
  if (!is.null(pdb)) {
    pdb(dat) <- pdb
    pdb(mc) <- pdb
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
    if (!identical(posterior_info[[key]], expected)) {
      stop(
        "`posterior_info$",
        key,
        "` conflicts with the inferred value.",
        call. = FALSE
      )
    }
  }
  po_fields <- posterior_info[setdiff(
    names(posterior_info),
    c("added_by", "added_date", names(structural))
  )]
  if (check) {
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
    posterior::nchains(draws_array)
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
  po <- as.pdb_posterior(
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
  if (!is.null(pdb)) {
    pdb(po) <- pdb
  }
  bundle <- list(
    data = dat,
    model_code = mc,
    posterior = po,
    reference_draws = rpd,
    diagnostics = if (check) diagnostic_report else NULL,
    provenance = list(
      data_source = resolved_data$source,
      fit_class = extracted$fit_class,
      selected_variables = chosen,
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
    metadata = attr(draws, "sampling_metadata")
  )
  if (is.null(extracted$metadata)) {
    stop("The bundle has no saved sampling metadata needed for diagnostics.",
         call. = FALSE)
  }
  if (is.null(extracted$metadata$expected_fraction_of_missing_information) &&
      !is.null(extracted$sampler_diagnostics)) {
    extracted$metadata$expected_fraction_of_missing_information <-
      rstan_sampler_bfmi(
        extracted$sampler_diagnostics,
        posterior::nchains(extracted$draws),
        strict = FALSE
      )
  }
  report <- bundle_full_diagnostic_report(
    extracted
  )
  report$checked <- TRUE
  draws <- attach_bundle_check_result(draws, report)
  x$reference_draws <- draws
  x$posterior$embedded_reference_draws <- draws
  x$diagnostics <- report
  x
}

bundle_full_diagnostic_report <- function(extracted, include = NULL) {
  draws <- extracted$draws
  report <- reference_draw_diagnostics_from_extracted(
    extracted,
    checks = "all",
    include = include
  )
  scalar_vars <- posterior::variables(draws)
  scalar_ess <- function(fun) {
    stats::setNames(
      vapply(
        seq_along(scalar_vars),
        function(j) {
          z <- matrix(
            draws[,, j],
            nrow = dim(draws)[1L],
            ncol = dim(draws)[2L]
          )
          tryCatch(as.numeric(fun(z))[1L], error = function(e) NA_real_)
        },
        numeric(1)
      ),
      scalar_vars
    )
  }
  report$metrics$effective_sample_size_bulk <- scalar_ess(posterior::ess_bulk)
  report$metrics$effective_sample_size_tail <- scalar_ess(posterior::ess_tail)
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
    posterior::nchains(draws)
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
      "Arguments after `added_date` must be named exactly; use `data_info`, `model_info`, `posterior_info`, `reference_info`, `include`, `exclude`, `check`, or `pdb`.",
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
resolve_standalone_fit_data <- function(fit, data) {
  source <- "caller-supplied"
  if (is.null(data)) {
    data <- recover_stanfit_data(fit)
    source <- "fit-recovered"
    if (is.null(data)) {
      stop(
        "`data` is required. Pass the actual named Stan input list; automatic fit-data recovery is unavailable for this fit.",
        call. = FALSE
      )
    }
  }
  if (!is.list(data)) {
    stop(
      "",
      if (source == "fit-recovered") "Recovered" else "Supplied",
      " `data` must be a list.",
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
      if (source == "fit-recovered") "Recovered" else "Supplied",
      " `data` must be a named list with unique, non-empty input names (or `list()` for no inputs).",
      call. = FALSE
    )
  }
  list(data = data, source = source)
}

# Future recovery belongs at this narrow boundary. NULL means unavailable;
# malformed recovered values are returned and rejected by the common validator.
recover_stanfit_data <- function(fit) NULL

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

validate_bundle_metadata <- function(x, arg, required, allowed) {
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
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(
      "`",
      arg,
      "` is missing required field(s): ",
      paste(missing, collapse = ", "),
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
  checkmate::assert_string(x$name)
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
  checkmate::assert_character(x, any.missing = FALSE, min.len = 1L)
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
  allowed <- c("comments", "added_by", "added_date", "inference", "versions")
  x <- x[intersect(names(x), allowed)]
  args <- metadata$method_arguments %||% list()
  info <- list(
    name = name,
    inference = x$inference %||%
      list(method = "stan_sampling", method_arguments = args),
    diagnostics = diagnostics,
    checks_made = NULL,
    comments = x$comments %||%
      paste0("Imported from an externally sampled rstan::stanfit."),
    added_by = x$added_by %||% added_by,
    added_date = x$added_date %||% added_date,
    # Only retain a Stan version reported by the fit's own stored metadata.
    # Installed package versions below describe this import operation instead.
    versions = if (!is.null(metadata$stan_version)) {
      list(stan_version = metadata$stan_version)
    } else {
      NULL
    }
  )
  as.pdb_reference_posterior_info(info)
}

bundle_reference_diagnostic_info <- function(metrics, ndraws, nchains) {
  get_metric <- function(key, default) {
    value <- metrics[[key]]
    if (is.null(value) || identical(value, "unavailable")) default else value
  }
  list(
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
  list(
    ndraws_is_10k = TRUE,
    nchains_is_gte_4 = TRUE,
    abs_mean_lag1_ac_below_0_05 = TRUE,
    r_hat_below_1_01 = TRUE,
    efmi_above_0_2 = TRUE,
    no_divergent_transitions = TRUE
  )
}
