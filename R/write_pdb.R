#' Write objects to pdb
#'
#' @description a function to simplify writing to a local pdb.
#'
#' @details Writing reference draws requires all applicable reference acceptance
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
#'   checked. It preflights every destination before writing. Existing files
#'   for new components cause an error when `overwrite = FALSE`; with
#'   `overwrite = TRUE`, the complete set is detected before any replacement
#'   begins. Components reused from the target database are skipped and are
#'   never overwritten by the bundle writer. Reused objects retain their
#'   source connections; same-name files in another database are rejected.
#'   A reused posterior must already have the matching persisted reference
#'   link before accepted bundle draws can be written. To fill an empty link,
#'   use [import_reference_posterior_draws()] with `write = TRUE`.
#'   When checks fail, newly written posteriors omit the candidate reference
#'   link unless its files already exist. Existing links to stored reference
#'   files are preserved. The in-memory bundle still contains the candidate.
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

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_bundle <- function(
  x,
  pdb,
  overwrite = FALSE,
  write_summary_statistics = TRUE,
  ...
) {
  if (length(list(...))) {
    stop(
      "`write_pdb()` does not accept extra arguments for a bundle.",
      call. = FALSE
    )
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

  draws_accepted <- FALSE
  draw_skip_reason <- diagnostic_error
  if (is.null(draw_skip_reason)) {
    acceptance <- tryCatch(
      {
        assert_checked_reference_posterior_draws(bundle$reference_draws)
        NULL
      },
      error = identity
    )
    if (is.null(acceptance)) {
      draws_accepted <- TRUE
    } else {
      draw_skip_reason <- conditionMessage(acceptance)
    }
  }

  # Preflight includes the draw and summary files when acceptance passes.
  write_plan <- preflight_pdb_bundle_write(
    bundle,
    pdb,
    include_reference_draws = draws_accepted,
    write_summary_statistics = write_summary_statistics,
    overwrite = overwrite
  )
  if (overwrite && length(write_plan$collision_paths)) {
    message(
      "Bundle write preflight found existing destination file(s) that will be replaced: ",
      paste(write_plan$collision_paths, collapse = ", ")
    )
  }

  written <- character()
  write_complete <- FALSE
  on.exit(
    {
      if (!write_complete) {
        message(
          "Bundle write did not complete. Completed components: ",
          if (length(written)) paste(written, collapse = ", ") else "none",
          ". Files already written are retained; the failing component may have partial files. ",
          "Inspect local changes before retrying."
        )
      }
    },
    add = TRUE
  )
  for (component in c("data", "model_code", "posterior")) {
    if (component %in% write_plan$write) {
      object <- bundle[[component]]
      if (component == "posterior" && !draws_accepted) {
        posterior_path <- pdb_file_path(
          pdb,
          "posteriors",
          paste0(object$name, ".json")
        )
        reference <- if (file.exists(posterior_path)) {
          jsonlite::read_json(posterior_path)$reference_posterior_name
        } else {
          object$reference_posterior_name
        }
        reference_exists <- !is.null(reference) &&
          all(file.exists(c(
            pdb_file_path(
              pdb,
              "reference_posteriors",
              "draws",
              "info",
              paste0(reference, ".info.json")
            ),
            pdb_file_path(
              pdb,
              "reference_posteriors",
              "draws",
              "draws",
              paste0(reference, ".json.zip")
            )
          )))
        object["reference_posterior_name"] <- list(
          if (reference_exists) reference else NULL
        )
        object$embedded_reference_draws <- NULL
      }
      component_overwrite <- if (component %in% write_plan$reused_to_copy) {
        FALSE
      } else {
        overwrite
      }
      write_pdb(
        object,
        pdb = pdb,
        overwrite = component_overwrite
      )
      written <- c(written, component)
    }
  }

  if (draws_accepted) {
    write_pdb(
      bundle$reference_draws,
      pdb = pdb,
      overwrite = overwrite,
      write_summary_statistics = write_summary_statistics
    )
    written <- c(written, "reference_draws")
    if (write_summary_statistics) written <- c(written, "summary_statistics")
  } else {
    message(paste0(
      "The data, model, and posterior components are available. Reference draws and ",
      "summary statistics were skipped because the reference-draw checks ",
      "did not pass.",
      if (!is.null(draw_skip_reason)) paste0(" Reason: ", draw_skip_reason)
    ))
  }

  write_complete <- TRUE
  result <- list(
    bundle = bundle,
    written = written,
    reused = write_plan$reused_in_target,
    overwritten = write_plan$overwritten,
    collisions = write_plan$collision_paths,
    reference_draws_written = draws_accepted,
    summary_statistics_written = draws_accepted && write_summary_statistics,
    diagnostic_error = diagnostic_error,
    skipped_reason = if (draws_accepted) NULL else draw_skip_reason
  )
  class(result) <- c("pdb_bundle_write_result", "list")
  invisible(result)
}

preflight_pdb_bundle_write <- function(
  bundle,
  pdb,
  include_reference_draws,
  write_summary_statistics,
  overwrite
) {
  checkmate::assert_flag(include_reference_draws)
  checkmate::assert_flag(write_summary_statistics)
  checkmate::assert_flag(overwrite)

  reused <- bundle$provenance$reused_components %||% logical()
  data_name <- info(bundle$data)$name
  model_name <- info(bundle$model_code)$name
  specs <- list(
    data = list(
      object = bundle$data,
      reused = isTRUE(reused["data"]),
      paths = c(
        pdb_write_output_path(pdb, "data/info", "json", data_name),
        pdb_write_output_path(
          pdb,
          "data/data",
          "json",
          data_name,
          zip = TRUE,
          info = FALSE
        )
      )
    ),
    model_code = list(
      object = bundle$model_code,
      reused = isTRUE(reused["model_code"]),
      paths = c(
        pdb_write_output_path(pdb, "models/info", "json", model_name),
        pdb_write_output_path(
          pdb,
          "models/stan",
          "stan",
          model_name,
          info = FALSE
        )
      )
    ),
    posterior = list(
      object = bundle$posterior,
      reused = isTRUE(reused["posterior"]),
      paths = pdb_write_output_path(
        pdb,
        "posteriors",
        "json",
        bundle$posterior$name,
        info = FALSE
      )
    )
  )

  if (include_reference_draws) {
    draw_name <- info(bundle$reference_draws)$name
    draw_paths <- pdb_reference_output_paths(
      pdb,
      draw_name,
      if (write_summary_statistics) {
        supported_summary_statistic_types()
      } else {
        character()
      }
    )
    specs$reference_draws <- list(
      object = bundle$reference_draws,
      reused = FALSE,
      paths = draw_paths
    )
  }

  all_paths <- unlist(lapply(specs, `[[`, "paths"), use.names = FALSE)
  duplicate_paths <- unique(all_paths[duplicated(all_paths)])
  if (length(duplicate_paths)) {
    stop(
      "Bundle components map to duplicate destination file(s): ",
      paste(duplicate_paths, collapse = ", "),
      ". No files were written.",
      call. = FALSE
    )
  }

  write_components <- character()
  reused_in_target <- character()
  reused_to_copy <- character()
  overwritten <- character()
  collision_paths <- character()
  blocking_issues <- character()
  for (component in names(specs)) {
    spec <- specs[[component]]
    existing <- file.exists(spec$paths)

    if (spec$reused && all(existing)) {
      source_pdb <- tryCatch(pdb(spec$object), error = function(error) NULL)
      if (is.null(source_pdb) || !same_local_pdb(source_pdb, pdb)) {
        blocking_issues <- c(
          blocking_issues,
          paste0(
            "The reused ",
            component,
            " object has files with the same destination name, but it is not ",
            "confirmed to come from this database: ",
            paste(spec$paths, collapse = ", "),
            ". The bundle writer will not replace or silently reuse them."
          )
        )
        next
      }
      if (
        component == "posterior" &&
          include_reference_draws &&
          !identical(
            jsonlite::read_json(spec$paths)$reference_posterior_name,
            info(bundle$reference_draws)$name
          )
      ) {
        blocking_issues <- c(
          blocking_issues,
          paste0(
            "The reused posterior does not have the matching persisted reference link: ",
            spec$paths,
            ". Use import_reference_posterior_draws(..., write = TRUE) to fill an empty link; ",
            "a different existing link cannot be replaced."
          )
        )
        next
      }
      reused_in_target <- c(reused_in_target, component)
      next
    }

    if (spec$reused && any(existing)) {
      blocking_issues <- c(
        blocking_issues,
        paste0(
          "The reused ",
          component,
          " object has only some of its expected files in the destination: ",
          paste(spec$paths[existing], collapse = ", "),
          ". Reused objects are never overwritten."
        )
      )
      next
    }

    if (any(existing)) {
      collision_paths <- c(collision_paths, spec$paths[existing])
      if (!overwrite) {
        next
      }
      overwritten <- c(overwritten, component)
    } else if (spec$reused) {
      reused_to_copy <- c(reused_to_copy, component)
    }
    write_components <- c(write_components, component)
  }

  if (length(blocking_issues)) {
    if (length(collision_paths)) {
      blocking_issues <- c(
        blocking_issues,
        paste0(
          "Other existing destination file(s): ",
          paste(collision_paths, collapse = ", ")
        )
      )
    }
    stop(
      "Bundle write preflight found unsafe reused-object collision(s):\n- ",
      paste(blocking_issues, collapse = "\n- "),
      "\nNo files were written.",
      call. = FALSE
    )
  }

  if (length(collision_paths) && !overwrite) {
    stop(
      "Bundle write preflight found existing destination file(s): ",
      paste(collision_paths, collapse = ", "),
      ". No files were written. Set `overwrite = TRUE` to replace files for newly constructed components.",
      call. = FALSE
    )
  }

  list(
    write = write_components,
    reused_in_target = reused_in_target,
    reused_to_copy = reused_to_copy,
    overwritten = unique(overwritten),
    collision_paths = collision_paths
  )
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
  ...
) {
  checkmate::assert_flag(write_summary_statistics)
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
  assert_reference_posterior_exists(pdb, reference_posterior_name)
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
  linked <- vapply(
    posterior_files,
    function(path) {
      tryCatch(
        {
          posterior_info <- jsonlite::read_json(path, simplifyVector = TRUE)
          identical(
            posterior_info$reference_posterior_name,
            reference_posterior_name
          )
        },
        error = function(error) FALSE
      )
    },
    logical(1)
  )
  if (!any(linked)) {
    stop(
      "Cannot write reference-posterior draws: no posterior in this database ",
      "points to reference posterior '",
      reference_posterior_name,
      "'. Write or link the associated posterior first.",
      call. = FALSE
    )
  }
  invisible(TRUE)
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
