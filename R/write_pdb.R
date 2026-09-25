#' Write objects to pdb
#'
#' @description a function to simplify writing to a local pdb.
#'
#' @details Writing reference draws requires all recorded reference acceptance
#'   flags to be `TRUE` and the associated posterior JSON to exist in `pdb`.
#'   Unchecked or failed reference draws, or draws without a saved posterior,
#'   are rejected before files are written. A successful reference-draw write
#'   also computes and writes each supported summary statistic by default;
#'   set `write_summary_statistics = FALSE` to write those objects separately.
#'   When `x` is a `pdb_reference_bundle`, `write_pdb()` checks unchecked
#'   draws, writes the data, model, and posterior, and writes reference draws
#'   only if all acceptance checks pass. The returned write report includes
#'   the checked bundle and any skipped components. Posterior JSON includes a
#'   `keywords` field set to `null` when no keywords were supplied.
#'   The individual reference-draw writer does not rerun diagnostic checks;
#'   ESS and treedepth are informational, not acceptance gates. The bundle
#'   writer runs the full checks first when the bundle has not already been
#'   checked.
#'
#' @param x an object to write to the pdb.
#' @param pdb the pdb to write to. Currently only a local pdb.
#' @param overwrite overwrite existing file?
#' @param write_summary_statistics When writing reference draws, also compute
#'   and write all supported summary statistics. Defaults to `TRUE`; set to
#'   `FALSE` to write summary-statistic objects separately.
#' @param type supported reference posterior types.
#' @param ... further arguments supplied to methods.
#' @return Existing object writers invisibly return `TRUE`. Writing a
#'   `pdb_reference_bundle` invisibly returns a `pdb_bundle_write_result` list
#'   with the checked `bundle`, names of successfully `written` components,
#'   whether reference draws and summary statistics were written, and any
#'   diagnostic error or skip reason.
#' @export
write_pdb <- function(x, pdb, overwrite = FALSE, ...){
  checkmate::assert_class(pdb, "pdb_local")
  UseMethod("write_pdb")
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_bundle <- function(
  x, pdb, overwrite = FALSE, write_summary_statistics = TRUE, ...
) {
  if (length(list(...))) {
    stop("`write_pdb()` does not accept extra arguments for a bundle.",
         call. = FALSE)
  }
  checkmate::assert_class(x, "pdb_reference_bundle")
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(write_summary_statistics)
  checkmate::assert_class(x$data, "pdb_data")
  checkmate::assert_class(x$model_code, "pdb_model_code")
  checkmate::assert_class(x$posterior, "pdb_posterior")
  checkmate::assert_class(x$reference_draws, "pdb_reference_posterior_draws")

  bundle <- x
  diagnostic_error <- NULL
  if (is.null(bundle$diagnostics) || !isTRUE(bundle$diagnostics$checked)) {
    diagnostic_result <- tryCatch(
      list(bundle = check_reference_posterior_draws(bundle), error = NULL),
      error = function(error) {
        list(bundle = NULL, error = conditionMessage(error))
      }
    )
    bundle <- diagnostic_result$bundle %||% bundle
    diagnostic_error <- diagnostic_result$error
  }

  write_pdb(bundle$data, pdb = pdb, overwrite = overwrite)
  write_pdb(bundle$model_code, pdb = pdb, overwrite = overwrite)
  write_pdb(bundle$posterior, pdb = pdb, overwrite = overwrite)
  written <- c("data", "model_code", "posterior")

  draws_accepted <- FALSE
  draw_skip_reason <- diagnostic_error
  if (is.null(draw_skip_reason)) {
    acceptance <- tryCatch({
      assert_checked_reference_posterior_draws(bundle$reference_draws)
      NULL
    }, error = identity)
    if (is.null(acceptance)) {
      draws_accepted <- TRUE
    } else {
      draw_skip_reason <- conditionMessage(acceptance)
    }
  }

  if (draws_accepted) {
    write_pdb(
      bundle$reference_draws,
      pdb = pdb,
      overwrite = overwrite,
      write_summary_statistics = write_summary_statistics
    )
    written <- c("data", "model_code", "posterior", "reference_draws")
    if (write_summary_statistics) written <- c(written, "summary_statistics")
  } else {
    message(paste0(
      "The data, model, and posterior were written. Reference draws and ",
      "summary statistics were skipped because the reference-draw checks ",
      "did not pass.",
      if (!is.null(draw_skip_reason)) paste0(" Reason: ", draw_skip_reason)
    ))
  }

  result <- list(
    bundle = bundle,
    written = written,
    reference_draws_written = draws_accepted,
    summary_statistics_written = draws_accepted && write_summary_statistics,
    diagnostic_error = diagnostic_error,
    skipped_reason = if (draws_accepted) NULL else draw_skip_reason
  )
  class(result) <- c("pdb_bundle_write_result", "list")
  invisible(result)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_info <- function(x, pdb, overwrite = FALSE, type, ...){
  checkmate::assert_choice(type, choices = supported_reference_posterior_types())
  assert_reference_posterior_info(x)
  class(x) <- c(class(x), "list")
  type_path <- type
  if(type %in% supported_summary_statistic_types()) type_path <- paste("summary_statistics", type, sep = "/")
  write_json_to_path(x, paste("reference_posteriors", type_path, "info", sep = "/"), pdb, zip = FALSE, info = TRUE, overwrite = overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_draws <- function(
  x, pdb, overwrite = FALSE, write_summary_statistics = TRUE, ...
){
  checkmate::assert_flag(write_summary_statistics)
  assert_reference_posterior_draws(x)
  assert_checked_reference_posterior_draws(x)
  reference_posterior_name <- info(x)$name
  assert_reference_posterior_exists(pdb, reference_posterior_name)
  summary_statistics <- if (write_summary_statistics) {
    summary_statistics_from_checked_reference_draws(x)
  } else {
    list()
  }
  write_pdb(info(x), pdb = pdb, overwrite = overwrite, type = "draws")
  write_json_to_path(x, "reference_posteriors/draws/draws", pdb, zip = TRUE, info = FALSE, overwrite = overwrite)
  for (summary_statistic in summary_statistics) {
    write_pdb(summary_statistic, pdb = pdb, overwrite = overwrite)
  }
}

assert_reference_posterior_exists <- function(pdb, reference_posterior_name) {
  posterior_dir <- pdb_file_path(pdb, "posteriors")
  posterior_files <- if (dir.exists(posterior_dir)) {
    list.files(posterior_dir, pattern = "\\.json$", full.names = TRUE)
  } else {
    character()
  }
  linked <- vapply(posterior_files, function(path) {
    tryCatch({
      posterior_info <- jsonlite::read_json(path, simplifyVector = TRUE)
      identical(posterior_info$reference_posterior_name,
                reference_posterior_name)
    }, error = function(error) FALSE)
  }, logical(1))
  if (!any(linked)) {
    stop(
      "Cannot write reference-posterior draws: no posterior in this database ",
      "points to reference posterior '", reference_posterior_name,
      "'. Write or link the associated posterior first.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_summary_statistic <- function(x, pdb, overwrite = FALSE, ...){
  assert_reference_posterior_summary_statistic(x)
  assert_checked_summary_statistics_draws(x)
  sstype <- summary_statistic_type(x)
  write_pdb(info(x), pdb = pdb, overwrite = overwrite, type = sstype)
  write_json_to_path(x, path = paste0("reference_posteriors/summary_statistics/", sstype, "/", sstype), pdb, zip = FALSE, info = FALSE, overwrite = overwrite, name = info(x)$name)
}


#' @rdname write_pdb
#' @export
write_pdb.pdb_data <- function(x, pdb, overwrite = FALSE, ...){
  assert_data(x)
  write_pdb(info(x), pdb = pdb, overwrite = overwrite)
  write_json_to_path(x, "data/data", pdb, name = info(x)$name, zip = TRUE, info = FALSE, overwrite = overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_data_info <- function(x, pdb,  overwrite = FALSE, ...){
  assert_data_info(x)
  x <- complete_info_fields(x, c(
    "name", "data_file", "title", "added_by", "added_date",
    "references", "description", "urls", "keywords"
  ))
  class(x) <- c(class(x), "list")
  write_json_to_path(x, "data/info", pdb, zip = FALSE, info = TRUE, overwrite = overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.stanmodel <- function(x, pdb, overwrite = FALSE, ...){
  write_stan_to_path(x = x@model_code, "models/stan", pdb, name = x@model_name, zip = FALSE, info = FALSE, overwrite = overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_model_code <- function(x, pdb,  overwrite = FALSE, ...){
  assert_model_code(x)
  write_pdb(info(x), pdb, overwrite = overwrite)
  write_model_code_to_path(x, path = "models/", pdb = pdb, name = info(x)$name, framework = framework(x), zip = FALSE, info = FALSE, overwrite = overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_model_info <- function(x, pdb,  overwrite = FALSE, ...){
  assert_model_info(x)
  if (!"keywords" %in% names(x)) x["keywords"] <- list(NULL)
  implementations <- x$model_implementations
  # Keep caller-supplied implementation metadata as-is. In particular, do not
  # manufacture null version/framework fields or discard optional values.
  x$model_implementations <- implementations
  class(x) <- c(class(x), "list")
  write_json_to_path(x, "models/info", pdb, zip = FALSE, info = TRUE, overwrite = overwrite)
}

complete_info_fields <- function(x, fields) {
  original_class <- class(x)
  missing <- setdiff(fields, names(x))
  if (length(missing)) x[missing] <- rep(list(NULL), length(missing))
  out <- x[fields]
  class(out) <- original_class
  out
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_posterior <- function(x, pdb,  overwrite = FALSE, ...){
  assert_pdb_posterior(x)
  if (!"keywords" %in% names(x)) x["keywords"] <- list(NULL)
  pdb(x) <- NULL
  x$model_info <- NULL
  x$data_info <- NULL
  # In-memory constructors may embed large content objects for standalone
  # getters. These payloads belong in their own database files, never in the
  # posterior metadata JSON.
  x$embedded_data <- NULL
  x$embedded_model_code <- NULL
  x$embedded_reference_draws <- NULL
  class(x) <- c(class(x), "list")
  write_json_to_path(x, "posteriors", pdb, zip = FALSE, info = FALSE, overwrite = overwrite)
}
