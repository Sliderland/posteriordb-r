#' Write objects to a local posterior database
#'
#' Writes data, models, posteriors, reference posteriors and bundles from
#' [create_pdb_bundle()] in the database's file layout. Writing data or model
#' code also writes their info.
#'
#' Every call works out all files it will write first. If one of them
#' already exists with different content and `overwrite = FALSE`, nothing is
#' written. Files that already exist with the same content are left alone,
#' so writing a bundle that reuses data or a model from the database is fine.
#' If writing fails part way, the files this call created are removed again.
#'
#' Reference draws must pass [check_reference_posterior_draws()]; the check
#' is run before writing. They are linked to the posterior named
#' `posterior_name`, which must already be in the database and must not
#' link to a different reference posterior. Summary statistics are computed
#' and written with them unless `write_summary_statistics = FALSE`.
#'
#' A bundle is written as its data, model, posterior and, if the draws pass
#' the checks, its reference draws and summary statistics. If they fail, the
#' rest is still written, with an empty reference link, and a message says
#' why.
#'
#' @param x The object to write.
#' @param pdb A local [pdb][pdb_local] connection.
#' @param overwrite Replace existing files with different content?
#' @param posterior_name Posterior to link reference draws to. Defaults to
#'   the reference posterior name.
#' @param write_summary_statistics Write summary statistics with reference
#'   draws?
#' @param type For a reference posterior info: `"draws"`, `"mean_value"` or
#'   `"mean_squared_value"`.
#' @param ... Not used.
#' @return The relative paths of the files written, invisibly. For a bundle,
#'   a list that also says whether the reference draws were written.
#' @export
write_pdb <- function(x, pdb, overwrite = FALSE, ...) {
  checkmate::assert_class(pdb, "pdb_local")
  checkmate::assert_flag(overwrite)
  UseMethod("write_pdb")
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_data <- function(x, pdb, overwrite = FALSE, ...) {
  execute_plan(plan_data(x), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_data_info <- function(x, pdb, overwrite = FALSE, ...) {
  execute_plan(plan_info(x), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_model_info <- function(x, pdb, overwrite = FALSE, ...) {
  execute_plan(plan_info(x), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_model_code <- function(x, pdb, overwrite = FALSE, ...) {
  execute_plan(plan_model_code(x), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_posterior <- function(x, pdb, overwrite = FALSE, ...) {
  ref <- x$reference_posterior_name
  if (!is.null(ref) && !reference_exists(pdb, ref)) {
    stop2("Posterior '", x$name, "' links to reference posterior '", ref,
          "', which is not in the database. Write the reference draws first, ",
          "or set `reference_posterior_name` to NULL.")
  }
  execute_plan(plan_posterior(x), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_info <- function(x, pdb, overwrite = FALSE, type = "draws", ...) {
  execute_plan(plan_reference_info(x, type), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_summary_statistic <- function(x, pdb, overwrite = FALSE, ...) {
  execute_plan(plan_summary_statistic(x), pdb, overwrite)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_posterior_draws <- function(x, pdb, overwrite = FALSE,
                                                    posterior_name = info(x)$name,
                                                    write_summary_statistics = TRUE, ...) {
  x <- check_reference_posterior_draws(x)
  name <- info(x)$name
  record_path <- file.path(pdb$path, "posteriors", paste0(posterior_name, ".json"))
  if (!file.exists(record_path)) {
    stop2("Posterior '", posterior_name, "' is not in the database. ",
          "Write it first, or set `posterior_name`.")
  }
  record <- read_json_file(record_path, simplify = FALSE)
  linked <- record$reference_posterior_name
  if (!is.null(linked) && !identical(linked, name)) {
    stop2("Posterior '", posterior_name, "' already links to reference posterior '", linked, "'.")
  }
  plan <- plan_reference_draws(x)
  if (write_summary_statistics) {
    for (s in compute_all_summary_statistics(x)) plan <- c(plan, plan_summary_statistic(s))
  }
  if (is.null(linked)) {
    record$reference_posterior_name <- name
    plan <- c(plan, list(plan_file(file.path("posteriors", paste0(posterior_name, ".json")),
                                   json_text(record))))
  }
  execute_plan(plan, pdb, overwrite, replace = file.path("posteriors", paste0(posterior_name, ".json")))
}

# Write plans ---------------------------------------------------------------
# A plan is a list of files (relative path, text, zipped?) to write.

plan_file <- function(path, text, zip = FALSE) list(path = path, text = text, zip = zip)

info_json <- function(x) json_text(plain_list(x))

# Optional fields that are written as null when missing, as in the database.
with_null_fields <- function(x, fields) {
  missing <- setdiff(fields, names(x))
  x[missing] <- rep(list(NULL), length(missing))
  x
}

plan_info <- function(x) {
  if (inherits(x, "pdb_model_info")) {
    assert_model_info(x)
    x <- with_null_fields(x, "keywords")
    return(list(plan_file(file.path("models", "info", paste0(x$name, ".info.json")), info_json(x))))
  }
  assert_data_info(x)
  x <- with_null_fields(x, c("references", "description", "urls", "keywords"))
  list(plan_file(file.path("data", "info", paste0(x$name, ".info.json")), info_json(x)))
}

plan_data <- function(x) {
  c(plan_info(info(x)),
    list(plan_file(info(x)$data_file, json_text(plain_list(x)), zip = TRUE)))
}

plan_model_code <- function(x) {
  c(plan_info(info(x)),
    list(plan_file(model_code_path(info(x), framework(x)), as.character(x))))
}

plan_posterior <- function(x, link = TRUE) {
  assert_posterior(x)
  record <- with_null_fields(plain_list(x, drop = c("model_info", "data_info", "embedded")),
                             "keywords")
  if (!link) record["reference_posterior_name"] <- list(NULL)
  list(plan_file(file.path("posteriors", paste0(x$name, ".json")), json_text(record)))
}

plan_reference_info <- function(x, type) {
  path <- file.path("reference_posteriors", reference_type_dir(type), "info",
                    paste0(x$name, ".info.json"))
  list(plan_file(path, info_json(x)))
}

plan_reference_draws <- function(x) {
  chains <- lapply(plain_list(x), function(chain) lapply(chain, unname))
  names(chains) <- NULL
  path <- file.path("reference_posteriors", "draws", "draws", paste0(info(x)$name, ".json"))
  c(plan_reference_info(info(x), "draws"),
    list(plan_file(path, json_text(chains, auto_unbox = FALSE), zip = TRUE)))
}

plan_summary_statistic <- function(x) {
  type <- attr(x, "type")
  path <- file.path("reference_posteriors", "summary_statistics", type, type,
                    paste0(info(x)$name, ".json"))
  c(plan_reference_info(info(x), type),
    list(plan_file(path, json_text(plain_list(x), auto_unbox = FALSE))))
}

reference_exists <- function(pdb, name) {
  all(file.exists(file.path(pdb$path, "reference_posteriors", "draws",
                            c(file.path("info", paste0(name, ".info.json")),
                              file.path("draws", paste0(name, ".json.zip"))))))
}

# Write a plan. Existing files with the same content are skipped; files with
# different content are an error unless `overwrite` (or listed in `replace`,
# for files the operation is meant to update). Files created by a failed
# write are removed.
execute_plan <- function(plan, pdb, overwrite = FALSE, replace = character()) {
  paths <- vapply(plan, function(f) if (f$zip) paste0(f$path, ".zip") else f$path, "")
  if (anyDuplicated(paths)) stop2("Two objects would be written to the same file.")
  full <- file.path(pdb$path, paths)
  exists <- file.exists(full)
  same <- vapply(seq_along(plan), function(i) exists[i] && same_file_content(plan[[i]], full[i]),
                 logical(1))
  conflicts <- paths[exists & !same & !paths %in% replace]
  if (length(conflicts) && !overwrite) {
    stop2("Nothing was written. These files already exist with different content ",
          "(use `overwrite = TRUE` to replace them):\n", paste0("  ", conflicts, collapse = "\n"))
  }
  created <- character()
  current <- NA_character_
  tryCatch({
    for (i in which(!same)) {
      current <- full[i]
      if (!exists[i]) created <- c(created, full[i])
      if (plan[[i]]$zip) write_zip_json(plan[[i]]$text, full[i]) else write_text_file(plan[[i]]$text, full[i])
    }
  }, error = function(e) {
    unlink(created)
    stop2("Writing failed at '", current, "': ", conditionMessage(e),
          "\nFiles created by this call were removed; replaced files were not restored.")
  })
  invisible(paths[!same])
}

same_file_content <- function(file, path) {
  existing <- if (file$zip) {
    tmp <- tempfile(fileext = ".json")
    on.exit(unlink(tmp))
    unzip_json(path, tmp)
    paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  } else {
    paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  }
  if (grepl("[.]json$", file$path)) {
    parsed <- tryCatch(list(jsonlite::fromJSON(existing), jsonlite::fromJSON(file$text)),
                       error = function(e) NULL)
    if (!is.null(parsed)) return(isTRUE(all.equal(canonical(parsed[[1]]), canonical(parsed[[2]]), tolerance = 1e-12)))
  }
  identical(trimws(existing), trimws(file$text))
}

# Sort named lists so that field order does not matter when comparing JSON.
canonical <- function(x) {
  if (is.list(x) && !is.data.frame(x)) {
    if (!is.null(names(x))) x <- x[order(names(x))]
    return(lapply(x, canonical))
  }
  x
}

#' Remove objects from a local posterior database
#'
#' Deletes the files of an object. For data, model code and reference
#' posteriors the info file is removed too unless `remove_info = FALSE`.
#' Posteriors that link to removed content are not changed.
#'
#' @param x The object to remove.
#' @param pdb A local [pdb][pdb_local] connection.
#' @param remove_info Also remove the info file?
#' @param type For a reference posterior info: `"draws"`, `"mean_value"` or
#'   `"mean_squared_value"`.
#' @param ... Not used.
#' @return The removed paths, invisibly.
#' @export
remove_pdb <- function(x, pdb, ...) {
  checkmate::assert_class(pdb, "pdb_local")
  UseMethod("remove_pdb")
}

remove_files <- function(pdb, paths) {
  full <- file.path(pdb$path, paths)
  missing <- paths[!file.exists(full)]
  if (length(missing)) stop2("Not in the database: ", paste(missing, collapse = ", "))
  ok <- file.remove(full)
  if (!all(ok)) stop2("Could not remove: ", paste(paths[!ok], collapse = ", "))
  invisible(paths)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_data <- function(x, pdb, remove_info = TRUE, ...) {
  paths <- paste0(info(x)$data_file, ".zip")
  if (remove_info) paths <- c(paths, file.path("data", "info", paste0(info(x)$name, ".info.json")))
  remove_files(pdb, paths)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_data_info <- function(x, pdb, ...) {
  remove_files(pdb, file.path("data", "info", paste0(x$name, ".info.json")))
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_model_code <- function(x, pdb, remove_info = TRUE, ...) {
  paths <- model_code_path(info(x), framework(x))
  if (remove_info) paths <- c(paths, file.path("models", "info", paste0(info(x)$name, ".info.json")))
  remove_files(pdb, paths)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_model_info <- function(x, pdb, ...) {
  remove_files(pdb, file.path("models", "info", paste0(x$name, ".info.json")))
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_posterior <- function(x, pdb, ...) {
  remove_files(pdb, file.path("posteriors", paste0(x$name, ".json")))
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_reference_posterior_info <- function(x, pdb, type = "draws", ...) {
  remove_files(pdb, file.path("reference_posteriors", reference_type_dir(type), "info",
                              paste0(x$name, ".info.json")))
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_reference_posterior_draws <- function(x, pdb, remove_info = TRUE, ...) {
  name <- info(x)$name
  paths <- file.path("reference_posteriors", "draws", "draws", paste0(name, ".json.zip"))
  if (remove_info) paths <- c(paths, file.path("reference_posteriors", "draws", "info",
                                               paste0(name, ".info.json")))
  remove_files(pdb, paths)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_reference_posterior_summary_statistic <- function(x, pdb, remove_info = TRUE, ...) {
  type <- attr(x, "type")
  name <- info(x)$name
  paths <- file.path("reference_posteriors", "summary_statistics", type, type, paste0(name, ".json"))
  if (remove_info) paths <- c(paths, file.path("reference_posteriors", "summary_statistics", type,
                                               "info", paste0(name, ".info.json")))
  remove_files(pdb, paths)
}

#' Link a posterior to a stored reference posterior
#'
#' Sets the `reference_posterior_name` of a posterior in a local database.
#' The reference draws and their info must already be in the database, and
#' the posterior must not link to a different reference posterior.
#'
#' @param posterior A posterior name or object.
#' @param reference_posterior Reference posterior name; defaults to the
#'   posterior's name.
#' @param pdb A local [pdb][pdb_local] connection.
#' @return The updated posterior, invisibly.
#' @export
link_reference_posterior <- function(posterior, reference_posterior = NULL, pdb = NULL) {
  name <- if (inherits(posterior, "pdb_posterior")) posterior$name else posterior
  pdb <- pdb %||% pdb(posterior) %||% pdb_default()
  checkmate::assert_class(pdb, "pdb_local")
  po <- posteriordb::posterior(name, pdb = pdb)
  reference_posterior <- reference_posterior %||% po$name
  assert_name(reference_posterior, "reference_posterior")
  if (!reference_exists(pdb, reference_posterior)) {
    stop2("Reference posterior '", reference_posterior, "' is not in the database.")
  }
  if (identical(po$reference_posterior_name, reference_posterior)) return(invisible(po))
  if (!is.null(po$reference_posterior_name)) {
    stop2("Posterior '", po$name, "' already links to '", po$reference_posterior_name, "'.")
  }
  po$reference_posterior_name <- reference_posterior
  execute_plan(plan_posterior(po), pdb, replace = file.path("posteriors", paste0(po$name, ".json")))
  invisible(po)
}
