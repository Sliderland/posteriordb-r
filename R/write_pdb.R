#' Write objects to pdb
#'
#' @description a function to simplify writing to a local pdb.
#'
#' @details
#' **Reference draws.** Draws can be written only after they have passed
#' [check_reference_posterior_draws()], and only when their posterior is
#' already saved in `pdb`. That posterior must either link to the draws
#' already, or have no reference link and the same name as the draws (or be
#' named in `posterior_name`), in which case the link is filled in. Both
#' summary statistics are computed and written too unless
#' `write_summary_statistics = FALSE`. Writing does not run the checks again.
#'
#' **Bundles.** For a `pdb_reference_bundle` from [create_pdb_bundle()], the
#' draws are checked first if they have not been. New data, model and
#' posterior objects are written. Reference draws and summary statistics are
#' written only if every check passed; otherwise the other objects are still
#' written and the result says what was skipped. Objects reused from `pdb`
#' are left as they are, except that a reused posterior with no reference
#' link is linked to the new draws. A reused posterior linked to different
#' draws is an error. Objects reused from another database are copied if
#' `pdb` has no files with that name, and are an error otherwise. Summary
#' statistics already in the bundle are written as they are; after changing a
#' bundle's draws, call [check_reference_posterior_draws()] to recompute them.
#'
#' **Existing files.** Every destination file for a bundle is checked before
#' anything is written. With `overwrite = FALSE` an existing file is an error
#' and nothing is written. With `overwrite = TRUE` existing files for new
#' objects are replaced.
#'
#' **Names and paths.** Names must be a single path component: no slashes,
#' and not `.` or `..`. Use underscores rather than hyphens in data and model
#' names, because posteriors are named `data_name-model_name`. Destinations
#' that resolve outside the database through symbolic links are rejected.
#'
#' **If a write fails.** Objects are written one after another. A disk or
#' serialization error stops the write and leaves the files already written
#' in place. The error names the file and, for a bundle, lists the completed
#' objects. Check the changes in your database checkout, fix the cause, and
#' write again, using `overwrite = TRUE` for files left by the first attempt.
#'
#' @param x an object to write to the pdb.
#' @param pdb the pdb to write to. Currently only a local pdb.
#' @param overwrite overwrite existing file?
#' @param write_summary_statistics When writing reference draws or a bundle,
#'   also write the summary statistics (`mean_value` and
#'   `mean_squared_value`).
#' @param posterior_name When writing reference draws, the saved posterior to
#'   link them to. Only needed when that posterior has no reference link yet
#'   and a different name from the draws.
#' @param type supported reference posterior types.
#' @param ... further arguments supplied to methods.
#' @return Invisibly `TRUE`. For a `pdb_reference_bundle`, invisibly a list
#'   with the checked `bundle`; the names of the `written`, `reused` and
#'   `overwritten` objects; `collisions`, the destination files that already
#'   existed; `reference_draws_written` and `summary_statistics_written`; and
#'   `skipped_reason` or `diagnostic_error` when the draws were not written.
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
  if (!is.null(posterior_name)) {
    assert_pdb_resource_name(posterior_name)
  }
  assert_reference_posterior_draws(x)
  assert_checked_reference_posterior_draws(x)
  reference_posterior_name <- info(x)$name
  assert_no_existing_outputs(
    pdb_reference_output_paths(
      pdb,
      reference_posterior_name,
      if (write_summary_statistics) {
        supported_summary_statistic_types()
      } else {
        character()
      }
    ),
    overwrite = overwrite
  )
  posterior_paths <- reference_draw_posterior_paths(
    pdb,
    reference_posterior_name,
    posterior_name
  )
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
      write_json_to_path(
        posterior_info,
        "posteriors",
        pdb,
        name = posterior_info$name,
        info = FALSE,
        overwrite = TRUE
      )
    }
  }
  pdb_clear_cache(pdb)
  for (summary_statistic in summary_statistics) {
    write_pdb(summary_statistic, pdb = pdb, overwrite = overwrite)
  }
  invisible(TRUE)
}

reference_draw_posterior_paths <- function(
  pdb,
  reference_posterior_name,
  posterior_name = NULL
) {
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
          if (
            !is.null(posterior_name) &&
              !identical(posterior_info$name, posterior_name)
          ) {
            return(FALSE)
          }
          matches <- identical(
            posterior_info$reference_posterior_name,
            reference_posterior_name
          ) ||
            (is.null(posterior_info$reference_posterior_name) &&
              identical(
                posterior_info$name,
                posterior_name %||% reference_posterior_name
              ))
          if (matches && is.null(posterior_info$reference_posterior_name)) {
            pdb_write_output_path(
              pdb,
              "posteriors",
              "json",
              posterior_info$name,
              info = FALSE
            )
          }
          matches
        },
        error = function(error) stop(paste("Error while linking:", error))
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
  assert_no_existing_outputs(
    pdb_write_output_path(
      pdb,
      paste0("reference_posteriors/summary_statistics/", sstype, "/", sstype),
      "json",
      info(x)$name,
      info = FALSE
    ),
    overwrite = overwrite
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
  assert_no_existing_outputs(
    pdb_write_output_path(
      pdb,
      "data/data",
      "json",
      info(x)$name,
      zip = TRUE,
      info = FALSE
    ),
    overwrite = overwrite
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
  assert_no_existing_outputs(
    pdb_write_output_path(
      pdb,
      paste0("models/", framework(x)),
      framework(x),
      info(x)$name,
      info = FALSE
    ),
    overwrite = overwrite
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
  if (
    !is.null(reference) &&
      !all(file.exists(pdb_reference_output_paths(pdb, reference)))
  ) {
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
rename_pdb <- function(x, new_name, ...) {
  checkmate::assert_string(new_name)
  UseMethod("rename_pdb")
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_data <- function(x, new_name, ...) {
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
rename_pdb.pdb_posterior <- function(x, new_name, ...) {
  old_x <- x
  x$name <- new_name
  write_pdb(x, pdb(x))
  remove_pdb(old_x, pdb(x))
}
