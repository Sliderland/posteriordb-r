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
#' @param data The exact named Stan input list. `list()` explicitly declares
#'   an empty input; `NULL` is currently unavailable and errors.
#' @param data_info Named data metadata. `name` and `title` are required;
#'   supported descriptive fields are `description`, `references`, `urls`,
#'   and `keywords`.
#' @param model_info Named model metadata. `name` and `title` are required;
#'   supported descriptive fields are `description`, `references`, `urls`,
#'   `keywords`, `prior`, and `licence`.
#' @param posterior_info Named posterior metadata. `added_by` and `added_date`
#'   provide defaults for the constructed objects. Structural fields are
#'   derived from the supplied data/model; only `added_by` and `added_date`
#'   may be supplied as posterior metadata.
#' @param reference_info Named human annotations for the reference draws,
#'   such as `comments`, `added_by`, and `added_date`. The inference method
#'   and version provenance are derived from the fit. Diagnostics and
#'   `checks_made` are calculated internally.
#' @param include Optional character vector of base variable names to retain.
#' @param exclude Optional character vector of base variable names to omit.
#' @param check Whether to evaluate the package's reference-draw acceptance
#'   checks. `FALSE` leaves the candidate explicitly unchecked.
#' @param pdb Optional PosteriorDB connection to attach for later use. This
#'   constructor never reads from or writes to it.
#' @param ... Reserved; unknown or duplicate arguments are rejected.
#'
#' @return A `pdb_reference_bundle` list containing `data`, `model_code`,
#'   `posterior`, `reference_draws`, `diagnostics`, and `provenance`.
#' @details
#' The bundle embeds its content in memory and remains usable before database
#' persistence. Supplied data is recorded as caller-supplied; this function
#' cannot establish that it produced the fit. For example:
#'
#' ```r
#' bundle <- create_pdb_reference_draws(
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
create_pdb_reference_draws <- function(
  fit, data = NULL, data_info = list(), model_info = list(),
  posterior_info = list(), reference_info = list(), include = NULL,
  exclude = NULL, check = TRUE, pdb = NULL, ...
) {
  UseMethod("create_pdb_reference_draws", fit)
}

#' @rdname create_pdb_reference_draws
#' @export
create_pdb_reference_draws.stanfit <- function(
  fit, data = NULL, data_info = list(), model_info = list(),
  posterior_info = list(), reference_info = list(), include = NULL,
  exclude = NULL, check = TRUE, pdb = NULL, ...
) {
  dots <- list(...)
  if (length(dots)) stop("Unused or unknown arguments in `...`: ",
                         paste(names(dots) %||% rep("<unnamed>", length(dots)), collapse = ", "),
                         call. = FALSE)
  checkmate::assert_flag(check)
  if (!is.null(pdb)) checkmate::assert_class(pdb, "pdb")
  resolved_data <- resolve_standalone_fit_data(fit, data)
  data <- resolved_data$data
  data_info <- validate_bundle_metadata(data_info, "data_info",
    required = character(), allowed = c("name", "title", "data_file", "added_by", "added_date", "description", "references", "urls", "keywords"))
  model_info <- validate_bundle_metadata(model_info, "model_info",
    required = character(), allowed = c("name", "title", "framework", "model_implementations", "added_by", "added_date", "description", "references", "urls", "keywords", "prior", "licence"))
  posterior_info <- validate_bundle_metadata(posterior_info, "posterior_info",
    required = character(), allowed = c("name", "model_name", "data_name", "reference_posterior_name", "dimensions", "added_by", "added_date"))
  reference_info <- validate_bundle_metadata(reference_info, "reference_info",
    required = character(), allowed = c("comments", "added_by", "added_date"))
  if (any(c("diagnostics", "checks_made", "passed", "accepted") %in% names(reference_info)))
    stop("`reference_info` cannot supply diagnostics or acceptance evidence.", call. = FALSE)
  assert_bundle_required_metadata(data_info, model_info)
  expected_data_file <- paste0("data/data/", data_info$name, ".json")
  if (!is.null(data_info$data_file) && !identical(data_info$data_file, expected_data_file))
    stop("`data_info$data_file` conflicts with the inferred data path.", call. = FALSE)
  if (!is.null(model_info$framework) && !identical(model_info$framework, "stan"))
    stop("`model_info$framework` conflicts with the inferred Stan framework.", call. = FALSE)
  expected_impl <- list(stan = list(model_code = paste0("models/stan/", model_info$name, ".stan")))
  if (!is.null(model_info$model_implementations) && !identical(model_info$model_implementations, expected_impl))
    stop("`model_info$model_implementations` conflicts with the inferred Stan model path.", call. = FALSE)

  extracted <- extract_external_stan_fit(fit)
  all_vars <- posterior::variables(extracted$draws)
  all_vars <- setdiff(all_vars, "lp__")
  bases <- unique(sub("\\[.*$", "", all_vars))
  include <- validate_variable_selection(include, "include")
  exclude <- validate_variable_selection(exclude, "exclude")
  if (!is.null(include) && length(setdiff(include, bases)))
    stop("Unknown saved variable(s) in `include`: ", paste(setdiff(include, bases), collapse = ", "), call. = FALSE)
  if (!is.null(exclude) && length(setdiff(exclude, bases)))
    stop("Unknown saved variable(s) in `exclude`: ", paste(setdiff(exclude, bases), collapse = ", "), call. = FALSE)
  chosen_bases <- setdiff(if (is.null(include)) bases else include, exclude %||% character())
  chosen <- all_vars[vapply(all_vars, function(v) sub("\\[.*$", "", v) %in% chosen_bases, logical(1))]
  if (!length(chosen)) stop("Variable selection leaves no saved draws.", call. = FALSE)
  dimensions <- infer_saved_dimensions(chosen)
  draws_array <- posterior::subset_draws(extracted$draws, variable = chosen, regex = FALSE)
  draws <- posterior::as_draws_list(draws_array)
  diagnostics <- compute_stan_sampling_diagnostics(
    draws_array, keep_dimensions = chosen,
    sampler_diagnostics = extracted$sampler_diagnostics,
    expected_fraction_of_missing_information = extracted$metadata$expected_fraction_of_missing_information,
    max_treedepth = extracted$metadata$max_treedepth
  )

  added_by <- posterior_info$added_by %||% unname(Sys.info()[["user"]])
  added_date <- posterior_info$added_date %||% Sys.Date()
  checkmate::assert_string(added_by)
  checkmate::assert_class(added_date, "Date")
  data_info <- make_bundle_info(data_info, added_by, added_date)
  data_info$data_file <- expected_data_file
  model_info <- make_bundle_info(model_info, added_by, added_date)
  model_info$framework <- NULL
  model_info$model_implementations <- NULL
  dat <- as.pdb_data(data, info = as.pdb_data_info(data_info))
  mi <- as.pdb_model_info(c(model_info, list(framework = "stan")))
  code <- tryCatch(as.character(fit@stanmodel@model_code), error = function(e) NULL)
  if (is.null(code) || length(code) != 1L || is.na(code) || !nzchar(code))
    stop("The `stanfit` does not expose its saved Stan source code.", call. = FALSE)
  mc <- as.pdb_model_code(code, info = mi, framework = "stan")
  if (!is.null(pdb)) {
    pdb(dat) <- pdb
    pdb(mc) <- pdb
  }

  structural <- list(name = paste(data_info$name, model_info$name, sep = "-"),
    model_name = model_info$name, data_name = data_info$name,
    reference_posterior_name = paste(data_info$name, model_info$name, sep = "-"),
    dimensions = dimensions)
  for (key in intersect(names(posterior_info), names(structural))) {
    expected <- structural[[key]]
    if (!identical(posterior_info[[key]], expected)) stop("`posterior_info$", key,
      "` conflicts with the inferred value.", call. = FALSE)
  }
  po_fields <- posterior_info[setdiff(names(posterior_info), c("added_by", "added_date", names(structural)))]
  rinfo <- new_bundle_reference_info(reference_info, extracted$metadata, diagnostics,
                                     structural$reference_posterior_name, added_by, added_date)
  rpd <- as.pdb_reference_posterior_draws(draws, info = rinfo)
  if (!is.null(pdb)) pdb(rpd) <- pdb
  attr(rpd, "sampler_diagnostics") <- extracted$sampler_diagnostics
  attr(rpd, "sampling_metadata") <- extracted$metadata
  diagnostic_report <- list(
    metrics = list(ndraws = diagnostics$ndraws, nchains = diagnostics$nchains,
      mean_lag1_ac = diagnostics$mean_lag1_ac, r_hat = diagnostics$r_hat,
      efmi = diagnostics$expected_fraction_of_missing_information,
      divergent_transitions = diagnostics$divergent_transitions),
    thresholds = reference_draw_policy()$thresholds,
    status = NULL, failures = NULL, checked = FALSE
  )
  if (check) {
    diagnostic_report <- reference_draw_diagnostics_from_extracted(
      extracted, checks = "all", include = chosen_bases
    )
    diagnostic_report$checked <- TRUE
    rpd <- tryCatch(check_reference_posterior_draws(rpd), error = function(e) {
      ri <- info(rpd)
      ri$checks_made <- c(ri$checks_made %||% list(), list(
        check_failed = conditionMessage(e), diagnostic_report = diagnostic_report
      ))
      info(rpd) <- ri
      rpd
    })
  }
  po <- as.pdb_posterior(c(structural, list(pdb_data = dat, pdb_model_code = mc), po_fields,
    list(added_by = added_by, added_date = added_date,
         embedded_data = dat, embedded_model_code = mc,
         embedded_reference_draws = rpd)), pdb = pdb)
  if (!is.null(pdb)) pdb(po) <- pdb
  bundle <- list(data = dat, model_code = mc, posterior = po,
    reference_draws = rpd, diagnostics = diagnostic_report %||% diagnostics,
    provenance = list(data_source = resolved_data$source, fit_class = class(fit)[1],
      selected_variables = chosen, sampling_metadata = extracted$metadata,
      imported_at = Sys.time(), import_versions = list(
        posteriordb = as.character(utils::packageVersion("posteriordb")),
        R = R.version$version.string,
        rstan = as.character(utils::packageVersion("rstan")),
        posterior = as.character(utils::packageVersion("posterior")))))
  class(bundle) <- c("pdb_reference_bundle", "list")
  bundle
}

#' @exportS3Method
create_pdb_reference_draws.default <- function(fit, ...) {
  stop("Unsupported fit class. `create_pdb_reference_draws()` currently accepts only `rstan::stanfit`.", call. = FALSE)
}

#' Print a standalone reference-draw bundle
#' @param x A `pdb_reference_bundle` returned by [create_pdb_reference_draws()].
#' @param ... Unused.
#' @export
print.pdb_reference_bundle <- function(x, ...) {
  cat("PosteriorDB reference bundle: ", x$data_info$name %||% info(x$data)$name,
      "-", info(x$model_code)$name, "\n", sep = "")
  cat("Variables: ", paste(x$provenance$selected_variables, collapse = ", "), "\n", sep = "")
  metrics <- x$diagnostics$metrics %||% x$diagnostics
  cat("Draws: ", metrics$ndraws, " across ", metrics$nchains, " chains\n", sep = "")
  checks <- info(x$reference_draws)$checks_made
  status <- if (!isTRUE(x$diagnostics$checked)) "unchecked" else if (!is.null(checks$check_failed)) "failed" else "passed"
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
    if (is.null(data)) stop("`data` is required. Pass the actual named Stan input list; automatic fit-data recovery is unavailable for this fit.", call. = FALSE)
  }
  if (!is.list(data)) stop("", if (source == "fit-recovered") "Recovered" else "Supplied",
    " `data` must be a list.", call. = FALSE)
  if (length(data) && (is.null(names(data)) || anyNA(names(data)) || any(!nzchar(names(data))) || anyDuplicated(names(data))))
    stop(if (source == "fit-recovered") "Recovered" else "Supplied",
      " `data` must be a named list with unique, non-empty input names (or `list()` for no inputs).", call. = FALSE)
  list(data = data, source = source)
}

# Future recovery belongs at this narrow boundary. NULL means unavailable;
# malformed recovered values are returned and rejected by the common validator.
recover_stanfit_data <- function(fit) NULL

validate_bundle_metadata <- function(x, arg, required, allowed) {
  checkmate::assert_list(x, .var.name = arg)
  if (!length(x)) return(x)
  if (is.null(names(x)) || anyNA(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x)))
    stop("`", arg, "` must have unique, non-empty field names.", call. = FALSE)
  unknown <- setdiff(names(x), allowed)
  if (length(unknown)) stop("Unknown field(s) in `", arg, "`: ", paste(unknown, collapse = ", "), call. = FALSE)
  missing <- setdiff(required, names(x))
  if (length(missing)) stop("`", arg, "` is missing required field(s): ", paste(missing, collapse = ", "), call. = FALSE)
  x
}

assert_metadata_pair <- function(x, arg, fields) {
  missing <- setdiff(fields, names(x))
  if (length(missing)) return(missing)
  checkmate::assert_string(x$name); checkmate::assert_string(x$title)
  character()
}

assert_bundle_required_metadata <- function(data_info, model_info) {
  missing_data <- assert_metadata_pair(data_info, "data_info", c("name", "title"))
  missing_model <- assert_metadata_pair(model_info, "model_info", c("name", "title"))
  missing_required <- c(if (length(missing_data)) paste0("data_info$", missing_data),
                        if (length(missing_model)) paste0("model_info$", missing_model))
  if (length(missing_required)) stop("Missing required metadata fields: ",
    paste(missing_required, collapse = ", "), ".", call. = FALSE)
  invisible(TRUE)
}

make_bundle_info <- function(x, added_by, added_date) {
  x$added_by <- x$added_by %||% added_by
  x$added_date <- x$added_date %||% added_date
  x
}

validate_variable_selection <- function(x, arg) {
  if (is.null(x)) return(NULL)
  checkmate::assert_character(x, any.missing = FALSE, min.len = 1L)
  if (any(!nzchar(x)) || anyDuplicated(x)) stop("`", arg, "` must contain unique, non-empty base names.", call. = FALSE)
  x
}

infer_saved_dimensions <- function(variables) {
  bases <- unique(sub("\\[.*$", "", variables))
  out <- lapply(bases, function(base) {
    vals <- variables[startsWith(variables, paste0(base, "["))]
    if (!length(vals)) return(integer())
    idx <- lapply(sub("^.*\\[([^]]+)\\]$", "\\1", vals), function(s) as.integer(strsplit(s, ",", fixed = TRUE)[[1]]))
    if (anyNA(unlist(idx)) || !all(lengths(idx) == lengths(idx)[1])) stop("Saved array indices are malformed for `", base, "`.", call. = FALSE)
    matrix <- do.call(rbind, idx); dims <- apply(matrix, 2L, max)
    expected <- do.call(expand.grid, c(lapply(dims, seq_len), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE))
    observed <- unique(as.data.frame(matrix))
    if (nrow(observed) != prod(dims) || !all(apply(expected, 1L, paste, collapse = ",") %in% apply(observed, 1L, paste, collapse = ",")))
      stop("Saved array `", base, "` is partial; all scalar elements are required.", call. = FALSE)
    as.integer(dims)
  })
  names(out) <- bases
  out
}

new_bundle_reference_info <- function(x, metadata, diagnostics, name, added_by, added_date) {
  allowed <- c("comments", "added_by", "added_date", "inference", "versions")
  x <- x[intersect(names(x), allowed)]
  args <- metadata$method_arguments %||% list()
  info <- list(name = name,
    inference = x$inference %||% list(method = "stan_sampling", method_arguments = args),
    diagnostics = diagnostics, checks_made = NULL,
    comments = x$comments %||% paste0("Imported from an externally sampled rstan::stanfit."),
    added_by = x$added_by %||% added_by, added_date = x$added_date %||% added_date,
    # Only retain a Stan version reported by the fit's own stored metadata.
    # Installed package versions below describe this import operation instead.
    versions = if (!is.null(metadata$stan_version)) list(stan_version = metadata$stan_version) else NULL)
  as.pdb_reference_posterior_info(info)
}
