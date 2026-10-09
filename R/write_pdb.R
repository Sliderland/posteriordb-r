#' Write objects to pdb
#'
#' @description a function to simplify writing to a local pdb.
#'
#' @details Writing reference draws requires all applicable reference acceptance
#'   flags to be `TRUE` and the associated posterior JSON to exist in `pdb`.
#'   The saved posterior must already link to the reference name, or have an
#'   empty reference link and the same name as the draws (or `posterior_name`).
#'   Unchecked or failed
#'   reference draws, or draws without a saved posterior, are rejected before
#'   files are written. Saving the draws fills an empty matching posterior
#'   link before writing any requested summaries, then clears
#'   the database cache. A successful reference-draw write
#'   also computes and writes each supported summary statistic by default;
#'   set `write_summary_statistics = FALSE` to write those objects separately.
#'   When `x` is a `pdb_reference_bundle`, `write_pdb()` checks unchecked
#'   draws, writes the data, model, and posterior, and writes reference draws
#'   only if all acceptance checks pass. The returned write report includes
#'   the checked bundle and any skipped components. Bundle writes reuse attached
#'   summaries, computing them only when \code{summary_statistics} is \code{NULL}.
#'   Attached summaries are validated before writing. After editing a bundle's
#'   draws, call \code{\link{check_reference_posterior_draws}()} to refresh its summaries.
#'   Posterior JSON includes a
#'   `keywords` field set to `null` when no keywords were supplied.
#'   The individual reference-draw writer does not rerun diagnostic checks;
#'   ESS and treedepth are informational, not acceptance gates. The bundle
#'   writer runs the full checks first when the bundle has not already been
#'   checked. It preflights every destination before writing. Existing files
#'   for new components cause an error when `overwrite = FALSE`; with
#'   `overwrite = TRUE`, the complete set is detected before any replacement
#'   begins. Components reused from the target database are skipped and are
#'   never replaced by the bundle writer; an empty posterior reference link
#'   is filled after a successful draw write. Reused objects retain their
#'   source connections; same-name files in another database are rejected.
#'   A reused posterior must have an empty or matching persisted reference
#'   link before accepted bundle draws can be written.
#'   Posterior writes save a `null` reference link unless both the reference
#'   info and draw archive already exist. When bundle checks fail, existing
#'   links to stored reference files are preserved. The in-memory bundle still
#'   contains the candidate.
#'   Resource names must be nonempty single path components: separators,
#'   `.` and `..`, and control characters are rejected. Dots within names
#'   and hyphens are allowed. Local destinations are checked before writing,
#'   including temporary JSON files used for ZIP archives. Paths that resolve
#'   through symlinks outside the database, or through dangling symlinks,
#'   are rejected. Individual multi-file writers check their payload paths
#'   before saving metadata. These checks do not lock the filesystem or make
#'   ordinary writes transactional.
#'   Bundle and component writes are sequential. An I/O or serialization
#'   error stops the operation and retains earlier writes and replacements.
#'   The failure message identifies the destination; bundle failures also
#'   list completed components. The failing component may contain partial
#'   files, and no success report is returned. Inspect the local Git changes,
#'   fix the cause, and retry; use `overwrite = TRUE` only after reviewing the
#'   files that will be replaced. ZIP failures retain the uncompressed JSON.
#'
#' @param x an object to write to the pdb.
#' @param pdb the pdb to write to. Currently only a local pdb.
#' @param overwrite overwrite existing file?
#' @param write_summary_statistics When writing reference draws, also compute
#'   and write all supported summary statistics. Defaults to `TRUE`; set to
#'   `FALSE` to write summary-statistic objects separately.
#' @param posterior_name When writing reference draws, the saved posterior to
#'   link. Supply this when an unlinked posterior has a different name from the
#'   draws. Defaults to finding existing links or an unlinked same-name posterior.
#' @param type supported reference posterior types.
#' @param ... further arguments supplied to methods.
#' @return Existing object writers invisibly return `TRUE`. Writing a
#'   `pdb_reference_bundle` invisibly returns a `pdb_bundle_write_result` list
#'   with the checked `bundle`, names of successfully `written` components,
#'   names of reused and overwritten components, the preflight `collisions`
#'   (destination paths found to exist before writes), whether reference draws
#'   and summary statistics were written, and any diagnostic error or skip
#'   reason.
#' @export
write_pdb <- function(x, pdb, overwrite = FALSE, ...) {
  checkmate::assert_class(pdb, "pdb_local")
  UseMethod("write_pdb")
}

# Shared destination preflight for bundle, individual, and staged import writes.
pdb_reference_output_paths <- function(pdb, name, summary_types = character()) {
  paths <- c(
    pdb_write_output_path(pdb, "reference_posteriors/draws/info", "json", name),
    pdb_write_output_path(
      pdb,
      "reference_posteriors/draws/draws",
      "json",
      name,
      zip = TRUE,
      info = FALSE
    )
  )
  summaries <- unlist(
    lapply(summary_types, function(type) {
      c(
        pdb_write_output_path(
          pdb,
          paste0("reference_posteriors/summary_statistics/", type, "/info"),
          "json",
          name
        ),
        pdb_write_output_path(
          pdb,
          paste0("reference_posteriors/summary_statistics/", type, "/", type),
          "json",
          name,
          info = FALSE
        )
      )
    }),
    use.names = FALSE
  )
  c(paths, summaries)
}

same_local_pdb <- function(left, right) {
  endpoint <- function(x) {
    value <- tryCatch(pdb_endpoint(x), error = function(error) NULL)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      return(NULL)
    }
    normalizePath(value, winslash = "/", mustWork = FALSE)
  }
  left_endpoint <- endpoint(left)
  right_endpoint <- endpoint(right)
  !is.null(left_endpoint) &&
    !is.null(right_endpoint) &&
    identical(left_endpoint, right_endpoint)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_info <- function(
  x,
  pdb,
  overwrite = FALSE,
  type,
  ...
) {
  checkmate::assert_choice(
    type,
    choices = supported_reference_posterior_types()
  )
  assert_reference_posterior_info(x)
  class(x) <- c(class(x), "list")
  type_path <- reference_posterior_type_path(type)
  write_json_to_path(
    x,
    paste("reference_posteriors", type_path, "info", sep = "/"),
    pdb,
    zip = FALSE,
    info = TRUE,
    overwrite = overwrite
  )
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_draws <- function(
  x,
  pdb,
  overwrite = FALSE,
  write_summary_statistics = TRUE,
  posterior_name = NULL,
  ...
) {
  checkmate::assert_flag(write_summary_statistics)
  if (!is.null(posterior_name)) assert_pdb_resource_name(posterior_name)
  assert_reference_posterior_draws(x)
  assert_checked_reference_posterior_draws(x)
  reference_posterior_name <- info(x)$name
  pdb_reference_output_paths(
    pdb,
    reference_posterior_name,
    if (write_summary_statistics) {
      supported_summary_statistic_types()
    } else {
      character()
    }
  )
  posterior_paths <- reference_draw_posterior_paths(pdb, reference_posterior_name,
    posterior_name)
  summary_statistics <- if (write_summary_statistics) {
    summary_statistics_from_checked_reference_draws(x)
  } else {
    list()
  }
  write_pdb(info(x), pdb = pdb, overwrite = overwrite, type = "draws")
  write_json_to_path(
    x,
    "reference_posteriors/draws/draws",
    pdb,
    zip = TRUE,
    info = FALSE,
    overwrite = overwrite
  )
  for (path in posterior_paths) {
    posterior_info <- jsonlite::read_json(path, simplifyVector = FALSE)
    if (is.null(posterior_info$reference_posterior_name)) {
      posterior_info$reference_posterior_name <- reference_posterior_name
      class(posterior_info) <- c("pdb_posterior", "list")
      write_json_to_path(posterior_info, "posteriors", pdb,
        name = posterior_info$name, info = FALSE, overwrite = TRUE)
    }
  }
  pdb_clear_cache(pdb)
  for (summary_statistic in summary_statistics) {
    write_pdb(summary_statistic, pdb = pdb, overwrite = overwrite)
  }
  invisible(TRUE)
}

reference_draw_posterior_paths <- function(pdb, reference_posterior_name,
                                         posterior_name = NULL) {
  posterior_dir <- pdb_file_path(pdb, "posteriors")
  posterior_files <- if (dir.exists(posterior_dir)) {
    list.files(posterior_dir, pattern = "\\.json$", full.names = TRUE)
  } else {
    character()
  }
  linked <- vapply(
    posterior_files,
    function(path) {
      tryCatch(
        {
          posterior_info <- jsonlite::read_json(path, simplifyVector = TRUE)
          if (!is.null(posterior_name) && !identical(posterior_info$name, posterior_name)) {
            return(FALSE)
          }
          matches <- identical(
            posterior_info$reference_posterior_name,
            reference_posterior_name
          ) || (
            is.null(posterior_info$reference_posterior_name) &&
              identical(posterior_info$name, posterior_name %||% reference_posterior_name)
          )
          if (matches && is.null(posterior_info$reference_posterior_name)) {
            pdb_write_output_path(pdb, "posteriors", "json",
              posterior_info$name, info = FALSE)
          }
          matches
        },
        error = function(error) FALSE
      )
    },
    logical(1)
  )
  if (!any(linked)) {
    stop(
      "Cannot write reference-posterior draws: no posterior in this database ",
      "is linked to or can be linked to reference posterior '",
      reference_posterior_name,
      "'. Write the associated posterior first and supply `posterior_name` if its name differs; ",
      "a different existing link cannot be replaced.",
      call. = FALSE
    )
  }
  posterior_files[linked]
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_summary_statistic <- function(
  x,
  pdb,
  overwrite = FALSE,
  ...
) {
  assert_reference_posterior_summary_statistic(x)
  assert_checked_summary_statistics_draws(x)
  sstype <- summary_statistic_type(x)
  pdb_write_output_path(
    pdb,
    paste0("reference_posteriors/summary_statistics/", sstype, "/", sstype),
    "json",
    info(x)$name,
    info = FALSE
  )
  write_pdb(info(x), pdb = pdb, overwrite = overwrite, type = sstype)
  write_json_to_path(
    x,
    path = paste0(
      "reference_posteriors/summary_statistics/",
      sstype,
      "/",
      sstype
    ),
    pdb,
    zip = FALSE,
    info = FALSE,
    overwrite = overwrite,
    name = info(x)$name
  )
}


#' @rdname write_pdb
#' @export
write_pdb.pdb_data <- function(x, pdb, overwrite = FALSE, ...) {
  assert_data(x)
  pdb_write_output_path(
    pdb,
    "data/data",
    "json",
    info(x)$name,
    zip = TRUE,
    info = FALSE
  )
  write_pdb(info(x), pdb = pdb, overwrite = overwrite)
  write_json_to_path(
    x,
    "data/data",
    pdb,
    name = info(x)$name,
    zip = TRUE,
    info = FALSE,
    overwrite = overwrite
  )
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_data_info <- function(x, pdb, overwrite = FALSE, ...) {
  assert_data_info(x)
  x <- complete_info_fields(
    x,
    c(
      "name",
      "data_file",
      "title",
      "added_by",
      "added_date",
      "references",
      "description",
      "urls",
      "keywords"
    )
  )
  class(x) <- c(class(x), "list")
  write_json_to_path(
    x,
    "data/info",
    pdb,
    zip = FALSE,
    info = TRUE,
    overwrite = overwrite
  )
}

#' @rdname write_pdb
#' @export
write_pdb.stanmodel <- function(x, pdb, overwrite = FALSE, ...) {
  write_stan_to_path(
    x = x@model_code,
    "models/stan",
    pdb,
    name = x@model_name,
    zip = FALSE,
    info = FALSE,
    overwrite = overwrite
  )
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_model_code <- function(x, pdb, overwrite = FALSE, ...) {
  assert_model_code(x)
  pdb_write_output_path(
    pdb,
    paste0("models/", framework(x)),
    framework(x),
    info(x)$name,
    info = FALSE
  )
  write_pdb(info(x), pdb, overwrite = overwrite)
  write_model_code_to_path(
    x,
    path = "models/",
    pdb = pdb,
    name = info(x)$name,
    framework = framework(x),
    zip = FALSE,
    info = FALSE,
    overwrite = overwrite
  )
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_model_info <- function(x, pdb, overwrite = FALSE, ...) {
  assert_model_info(x)
  if (!"keywords" %in% names(x)) {
    x["keywords"] <- list(NULL)
  }
  class(x) <- c(class(x), "list")
  write_json_to_path(
    x,
    "models/info",
    pdb,
    zip = FALSE,
    info = TRUE,
    overwrite = overwrite
  )
}

complete_info_fields <- function(x, fields) {
  original_class <- class(x)
  missing <- setdiff(fields, names(x))
  if (length(missing)) {
    x[missing] <- rep(list(NULL), length(missing))
  }
  out <- x[fields]
  class(out) <- original_class
  out
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_posterior <- function(x, pdb, overwrite = FALSE, ...) {
  assert_pdb_posterior(x)
  if (!"keywords" %in% names(x)) {
    x["keywords"] <- list(NULL)
  }
  pdb(x) <- NULL
  x$model_info <- NULL
  x$data_info <- NULL
  # In-memory constructors may embed large content objects for standalone
  # getters. These payloads belong in their own database files, never in the
  # posterior metadata JSON.
  x$embedded_data <- NULL
  x$embedded_model_code <- NULL
  x$embedded_reference_draws <- NULL
  reference <- x$reference_posterior_name
  if (!is.null(reference) &&
      !all(file.exists(pdb_reference_output_paths(pdb, reference)))) {
    x["reference_posterior_name"] <- list(NULL)
  }
  class(x) <- c(class(x), "list")
  write_json_to_path(
    x,
    "posteriors",
    pdb,
    zip = FALSE,
    info = FALSE,
    overwrite = overwrite
  )
}


#' Rename a pdb object
#'
#' @param x an object to rename
#' @param new_name the new name of the object
#' @param ... further arguments (not in use)
#'
#' @export
rename_pdb <- function(x, new_name, ...){
  checkmate::assert_string(new_name)
  UseMethod("rename_pdb")
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_data <- function(x, new_name, ...){
  old_x <- x
  di <- info(x)
  di$name <- new_name
  di$data_file <- paste0("data/data/", new_name, ".json")
  info(x) <- di
  write_pdb(x, pdb(x))
  remove_pdb(old_x, pdb(x))
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_posterior <- function(x, new_name, ...){
  old_x <- x
  x$name <- new_name
  write_pdb(x, pdb(x))
  remove_pdb(old_x, pdb(x))
}

