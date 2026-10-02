#' Rename a data, model, or posterior in a local PosteriorDB
#'
#' Renaming a data set or model is a database migration, rather than a simple
#' file rename. The migration updates the object's metadata, affected
#' posterior records, canonical reference-posterior files, and posterior alias
#' targets. Data values, draws, summaries, and model-code contents are
#' preserved; JSON ZIP archives are rebuilt only to change their single member
#' filename to match the new database name. All validation and staging happen
#' before source files are moved.
#' If reserving or installing a file fails, the migration restores the
#' original files and removes installed targets. If rollback is incomplete,
#' the error identifies unrestored originals and retained backup paths.
#' Backups are deleted only after a successful migration or rollback.
#'
#' @param x an object to rename, or a character name.
#' @param new_name the new name.
#' @param type for a character `x`, one of `"data"`, `"model"`, or
#'   `"posterior"`. It is inferred when the name belongs to exactly one
#'   resource type.
#' @param pdb a local PosteriorDB connection when it cannot be obtained from
#'   `x` (required for a bare character name).
#' @param ... currently unused.
#' @return The renamed in-memory object.
#' @export
rename_pdb <- function(x, new_name, ...){
  assert_pdb_resource_name(new_name)
  UseMethod("rename_pdb")
}

#' @rdname rename_pdb
#' @export
rename_pdb.character <- function(x, new_name, type = NULL,
                                 pdb = pdb_default(), ...){
  assert_pdb_resource_name(x)
  checkmate::assert_class(pdb, "pdb_local")
  type <- rename_pdb_infer_type(x, type, pdb)
  object <- switch(
    type,
    data = data_info(x, pdb = pdb),
    model = model_info(x, pdb = pdb),
    posterior = posterior(x, pdb = pdb)
  )
  rename_pdb(object, new_name, pdb = pdb, ...)
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_data <- function(x, new_name, pdb = posteriordb::pdb(x), ...){
  checkmate::assert_class(info(x), "pdb_data_info")
  rename_pdb_entity(info(x)$name, new_name, type = "data", pdb = pdb, ...)
  new_info <- info(x)
  new_info$name <- new_name
  new_info$data_file <- paste0("data/data/", new_name, ".json")
  info(x) <- new_info
  x
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_data_info <- function(x, new_name, pdb = NULL, ...){
  rename_pdb_entity(x$name, new_name, type = "data", pdb = pdb, ...)
  x$name <- new_name
  x$data_file <- paste0("data/data/", new_name, ".json")
  x
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_model_info <- function(x, new_name, pdb = NULL, ...){
  old_name <- x$name
  rename_pdb_entity(old_name, new_name, type = "model", pdb = pdb, ...)
  x$name <- new_name
  for (implementation in seq_along(x$model_implementations)) {
    fields <- names(x$model_implementations[[implementation]])
    for (field in fields) {
      value <- x$model_implementations[[implementation]][[field]]
      x$model_implementations[[implementation]][[field]] <-
        rename_pdb_model_path(value, old_name, new_name)
    }
  }
  x
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_model_code <- function(x, new_name, pdb = posteriordb::pdb(x), ...){
  checkmate::assert_class(info(x), "pdb_model_info")
  info(x) <- rename_pdb.pdb_model_info(info(x), new_name, pdb = pdb, ...)
  x
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_posterior <- function(x, new_name, pdb = posteriordb::pdb(x), ...){
  old_name <- x$name
  rename_pdb_entity(old_name, new_name, type = "posterior", pdb = pdb, ...)
  x$name <- new_name
  if (identical(x$reference_posterior_name, old_name)) {
    x$reference_posterior_name <- new_name
  }
  x
}

rename_pdb_infer_type <- function(x, type, pdb) {
  if (!is.null(type)) {
    checkmate::assert_choice(type, c("data", "model", "posterior"))
    return(type)
  }
  exists <- c(
    data = x %in% data_names(pdb),
    model = x %in% model_names(pdb),
    posterior = x %in% posterior_names(pdb)
  )
  if (sum(exists) != 1L) {
    stop(
      "`type` is required unless `x` identifies exactly one data, model, or posterior.",
      call. = FALSE
    )
  }
  names(exists)[exists]
}

rename_pdb_connection <- function(pdb) {
  checkmate::assert_class(pdb, "pdb_local")
  pdb
}

rename_pdb_read_json <- function(path) {
  tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(error) {
      stop("Cannot parse JSON file '", path, "': ", conditionMessage(error), call. = FALSE)
    }
  )
}

rename_pdb_json_text <- function(object) {
  out <- jsonlite::toJSON(
    object,
    pretty = TRUE,
    auto_unbox = TRUE,
    null = "null",
    digits = NA,
    encoding = "UTF-8"
  )
  Encoding(out) <- "UTF-8"
  as.character(out)
}

rename_pdb_model_path <- function(value, old_name, new_name) {
  if (!is.character(value) || length(value) != 1L ||
      !grepl("^models/", value)) return(value)
  filename <- basename(value)
  if (!startsWith(filename, paste0(old_name, "."))) return(value)
  paste(dirname(value), paste0(new_name, substring(filename, nchar(old_name) + 1L)), sep = "/")
}

rename_pdb_basename <- function(relative, old_name, new_name) {
  filename <- basename(relative)
  prefix <- paste0(old_name, ".")
  if (!startsWith(filename, prefix)) {
    stop("File '", relative, "' does not have the expected name prefix.", call. = FALSE)
  }
  file.path(dirname(relative), paste0(new_name, substring(filename, nchar(old_name) + 1L)))
}

rename_pdb_add_action <- function(actions, source, target, content = NULL,
                                  zip_member = NULL) {
  source <- gsub("\\\\", "/", source)
  target <- gsub("\\\\", "/", target)
  previous <- actions[[source]]
  if (!is.null(previous)) {
    same_content <- (is.null(previous$content) && is.null(content)) ||
      identical(previous$content, content)
    if (!identical(previous$target, target) || !same_content ||
        !identical(previous$zip_member, zip_member)) {
      stop("The rename plan contains conflicting actions for '", source, "'.", call. = FALSE)
    }
    return(actions)
  }
  actions[[source]] <- list(
    source = source,
    target = target,
    content = content,
    zip_member = zip_member
  )
  actions
}

rename_pdb_posterior_files <- function(pdb) {
  root <- pdb_local_resource_path(pdb, "posteriors")
  files <- list.files(root, pattern = "[.]json$", full.names = TRUE, recursive = FALSE)
  lapply(files, function(path) {
    object <- rename_pdb_read_json(path)
    if (is.null(object$name)) {
      stop("Posterior file '", path, "' has no `name` field.", call. = FALSE)
    }
    object$.rename_path <- path
    object
  })
}

rename_pdb_reference_files <- function(pdb, old_name) {
  root <- pdb_local_resource_path(pdb, "reference_posteriors")
  if (!dir.exists(root)) return(character())
  files <- list.files(root, full.names = TRUE, recursive = TRUE)
  files[basename(files) %in% c(
    paste0(old_name, ".info.json"),
    paste0(old_name, ".json"),
    paste0(old_name, ".json.zip")
  )]
}

rename_pdb_add_reference_actions <- function(actions, pdb, old_name, new_name) {
  files <- rename_pdb_reference_files(pdb, old_name)
  if (!length(files)) {
    stop("Reference posterior '", old_name, "' is linked but no reference files were found.",
         call. = FALSE)
  }
  endpoint <- pdb$pdb_local_endpoint
  for (source in files) {
    relative <- substring(source, nchar(endpoint) + 2L)
    target <- rename_pdb_basename(relative, old_name, new_name)
    content <- NULL
    if (grepl("[.]info[.]json$", relative)) {
      info <- rename_pdb_read_json(source)
      info$name <- new_name
      content <- rename_pdb_json_text(info)
    }
    zip_member <- if (grepl("[.]json[.]zip$", relative)) paste0(new_name, ".json") else NULL
    actions <- rename_pdb_add_action(actions, relative, target, content, zip_member)
  }
  actions
}

rename_pdb_stage_zip <- function(source, destination, member_name) {
  member <- pdb_json_archive_member(source)
  extraction <- tempfile(".pdb-rename-unzip-")
  dir.create(extraction, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(extraction, recursive = TRUE, force = TRUE), add = TRUE)
  pdb_extract_json_archive(source, member, extraction)
  old_member <- file.path(extraction, member)
  new_member <- file.path(extraction, member_name)
  dir.create(dirname(new_member), recursive = TRUE, showWarnings = FALSE)
  if (!file.rename(old_member, new_member)) {
    stop("Could not rename ZIP member '", member, "'.", call. = FALSE)
  }
  oldwd <- setwd(extraction)
  on.exit(setwd(oldwd), add = TRUE)
  zip_destination <- paste0(destination, ".zip")
  utils::zip(zip_destination, files = member_name, flags = "-jq")
  if (!file.rename(zip_destination, destination)) {
    stop("Could not finalize staged ZIP archive.", call. = FALSE)
  }
  setwd(oldwd)
  invisible(TRUE)
}

rename_pdb_commit <- function(actions, pdb) {
  if (!length(actions)) return(invisible(TRUE))
  endpoint <- pdb$pdb_local_endpoint
  action_list <- unname(actions)
  sources <- vapply(action_list, `[[`, character(1), "source")
  targets <- vapply(action_list, `[[`, character(1), "target")
  if (anyDuplicated(targets)) stop("The rename plan has duplicate target paths.", call. = FALSE)
  source_abs <- vapply(sources, function(path) pdb_local_resource_path(pdb, path), character(1))
  target_abs <- vapply(targets, function(path) pdb_local_resource_path(pdb, path), character(1))
  if (any(!file.exists(source_abs))) stop("The rename plan refers to a missing source file.", call. = FALSE)
  source_set <- unique(source_abs)
  unexpected_targets <- target_abs[file.exists(target_abs) & !(target_abs %in% source_set)]
  if (length(unexpected_targets)) {
    stop("Refusing to overwrite existing file '", unexpected_targets[[1]], "'.", call. = FALSE)
  }
  if (any(target_abs %in% source_abs & target_abs != source_abs)) {
    stop("The rename plan contains a target that is another source file.", call. = FALSE)
  }

  stage <- tempfile(".pdb-rename-stage-", tmpdir = dirname(endpoint))
  backup <- tempfile(".pdb-rename-backup-", tmpdir = dirname(endpoint))
  dir.create(stage, recursive = TRUE, showWarnings = FALSE)
  dir.create(backup, recursive = TRUE, showWarnings = FALSE)
  keep_backup <- FALSE
  cleanup <- function() {
    unlink(stage, recursive = TRUE, force = TRUE)
    if (!keep_backup) unlink(backup, recursive = TRUE, force = TRUE)
  }
  on.exit(cleanup(), add = TRUE)

  staged <- character(length(action_list))
  backups <- character(length(action_list))
  for (i in seq_along(action_list)) {
    staged[[i]] <- file.path(stage, sprintf("%06d", i))
    backups[[i]] <- file.path(backup, sprintf("%06d", i))
    if (!is.null(action_list[[i]]$zip_member)) {
      rename_pdb_stage_zip(source_abs[[i]], staged[[i]], action_list[[i]]$zip_member)
    } else if (!is.null(action_list[[i]]$content)) {
      writeLines(action_list[[i]]$content, staged[[i]], useBytes = TRUE)
    } else if (!file.copy(source_abs[[i]], staged[[i]], overwrite = FALSE)) {
      stop("Could not stage '", sources[[i]], "'.", call. = FALSE)
    }
  }

  backed_up <- 0L
  committed <- 0L
  rollback <- function() {
    keep_backup <<- TRUE
    failures <- character()
    if (committed > 0L) {
      for (i in seq.int(committed, 1L)) unlink(target_abs[[i]], force = TRUE)
    }
    if (backed_up > 0L) {
      for (i in seq.int(backed_up, 1L)) {
        restored <- tryCatch({
          dir.create(dirname(source_abs[[i]]), recursive = TRUE, showWarnings = FALSE)
          file.rename(backups[[i]], source_abs[[i]])
        }, error = function(error) FALSE)
        if (!restored) {
          failures <- c(failures, paste0("Could not restore '", source_abs[[i]],
            "' from '", backups[[i]], "'."))
        }
      }
    }
    remaining_targets <- setdiff(target_abs[seq_len(committed)], source_abs)
    remaining_targets <- remaining_targets[file.exists(remaining_targets)]
    if (length(remaining_targets)) {
      failures <- c(failures, paste0("Could not remove installed target '", remaining_targets, "'."))
    }
    if (length(failures)) {
      return(paste("Rollback incomplete.", paste(failures, collapse = " "),
        "Remaining backups retained at", backup))
    }
    keep_backup <<- FALSE
    "The migration was rolled back."
  }
  keep_backup <- TRUE
  tryCatch({
    for (i in seq_along(action_list)) {
      if (!file.rename(source_abs[[i]], backups[[i]])) {
        stop("Could not reserve source file '", sources[[i]], "'.", call. = FALSE)
      }
      backed_up <- i
    }
    for (i in seq_along(action_list)) {
      dir.create(dirname(target_abs[[i]]), recursive = TRUE, showWarnings = FALSE)
      if (!file.rename(staged[[i]], target_abs[[i]])) {
        stop("Could not install target file '", targets[[i]], "'.", call. = FALSE)
      }
      committed <- i
    }
  }, error = function(error) {
    stop(conditionMessage(error), " ", rollback(), call. = FALSE)
  })
  keep_backup <- FALSE
  invisible(TRUE)
}

rename_pdb_entity <- function(old_name, new_name, type, pdb, ...) {
  assert_pdb_resource_name(old_name)
  assert_pdb_resource_name(new_name)
  checkmate::assert_choice(type, c("data", "model", "posterior"))
  pdb <- rename_pdb_connection(pdb)
  if (identical(old_name, new_name)) return(invisible(TRUE))

  endpoint <- pdb$pdb_local_endpoint
  actions <- list()
  add <- function(source, target, content = NULL) {
    actions <<- rename_pdb_add_action(actions, source, target, content)
  }

  if (type == "data") {
    info_rel <- file.path("data", "info", paste0(old_name, ".info.json"))
    data_candidates <- file.path("data", "data", paste0(old_name, c(".json.zip", ".json")))
    data_files <- data_candidates[vapply(
      data_candidates,
      function(path) file.exists(pdb_local_resource_path(pdb, path)),
      logical(1)
    )]
    if (!length(data_files)) stop("No data file was found for '", old_name, "'.", call. = FALSE)
    info_path <- pdb_local_resource_path(pdb, info_rel)
    if (!file.exists(info_path)) stop("No data metadata was found for '", old_name, "'.", call. = FALSE)
    data_info <- rename_pdb_read_json(info_path)
    if (!identical(data_info$name, old_name)) stop("Data metadata name does not match its filename.", call. = FALSE)
    data_info$name <- new_name
    data_info$data_file <- paste0("data/data/", new_name, ".json")
    add(info_rel, file.path("data", "info", paste0(new_name, ".info.json")), rename_pdb_json_text(data_info))
    for (data_rel in data_files) {
      data_target <- file.path("data", "data", paste0(new_name, substring(basename(data_rel), nchar(old_name) + 1L)))
      data_zip_member <- if (grepl("[.]json[.]zip$", data_rel)) paste0(new_name, ".json") else NULL
      actions <- rename_pdb_add_action(actions, data_rel, data_target, zip_member = data_zip_member)
    }
    entity_field <- "data_name"
  } else if (type == "model") {
    info_rel <- file.path("models", "info", paste0(old_name, ".info.json"))
    info_path <- pdb_local_resource_path(pdb, info_rel)
    if (!file.exists(info_path)) stop("No model metadata was found for '", old_name, "'.", call. = FALSE)
    model_info <- rename_pdb_read_json(info_path)
    if (!identical(model_info$name, old_name)) stop("Model metadata name does not match its filename.", call. = FALSE)
    model_info$name <- new_name
    implementations <- model_info$model_implementations
    if (is.null(implementations)) stop("Model '", old_name, "' has no implementations.", call. = FALSE)
    for (implementation in seq_along(implementations)) {
      for (field in names(implementations[[implementation]])) {
        value <- implementations[[implementation]][[field]]
        new_value <- rename_pdb_model_path(value, old_name, new_name)
        if (!identical(value, new_value)) {
          add(value, new_value)
          model_info$model_implementations[[implementation]][[field]] <- new_value
        }
      }
    }
    add(info_rel, file.path("models", "info", paste0(new_name, ".info.json")), rename_pdb_json_text(model_info))
    entity_field <- "model_name"
  } else {
    info_rel <- file.path("posteriors", paste0(old_name, ".json"))
    if (!file.exists(pdb_local_resource_path(pdb, info_rel))) stop("No posterior was found for '", old_name, "'.", call. = FALSE)
    entity_field <- NULL
  }

  posterior_files <- rename_pdb_posterior_files(pdb)
  affected <- list()
  for (posterior_info in posterior_files) {
    if (!is.null(entity_field) && !identical(posterior_info[[entity_field]], old_name)) next
    if (is.null(entity_field) && !identical(posterior_info$name, old_name)) next
    old_posterior_name <- posterior_info$name
    other_name <- if (type == "data") posterior_info$model_name else posterior_info$data_name
    expected_old <- if (is.null(entity_field)) old_name else if (type == "data") {
      paste(old_name, other_name, sep = "-")
    } else {
      paste(other_name, old_name, sep = "-")
    }
    new_posterior_name <- old_posterior_name
    if (identical(old_posterior_name, expected_old)) {
      new_posterior_name <- if (type == "data") paste(new_name, other_name, sep = "-") else
        if (type == "model") paste(other_name, new_name, sep = "-") else new_name
    }
    if (type == "data") posterior_info$data_name <- new_name
    if (type == "model") posterior_info$model_name <- new_name
    if (identical(posterior_info$reference_posterior_name, old_posterior_name) &&
        !identical(new_posterior_name, old_posterior_name)) {
      posterior_info$reference_posterior_name <- new_posterior_name
    }
    posterior_info$name <- new_posterior_name
    actual_relative <- substring(posterior_info$.rename_path, nchar(endpoint) + 2L)
    old_path <- paste0("posteriors/", old_posterior_name, ".json")
    if (!identical(actual_relative, old_path)) {
      stop("Posterior file '", actual_relative, "' disagrees with its `name` field.", call. = FALSE)
    }
    new_path <- paste0("posteriors/", new_posterior_name, ".json")
    serializable <- posterior_info[setdiff(names(posterior_info), ".rename_path")]
    add(old_path, new_path, rename_pdb_json_text(serializable))
    affected[[length(affected) + 1L]] <- list(
      old = old_posterior_name,
      new = new_posterior_name,
      reference = posterior_info$reference_posterior_name
    )
  }

  all_refs <- vapply(posterior_files, function(object) {
    reference <- object$reference_posterior_name
    if (is.null(reference) || length(reference) == 0L) "" else as.character(reference[[1]])
  }, character(1))
  affected_old <- vapply(affected, `[[`, character(1), "old")
  for (item in affected) {
    if (identical(item$old, item$new) || is.null(item$reference) || length(item$reference) == 0L ||
        !identical(item$reference, item$new)) next
    users <- which(all_refs == item$old)
    if (length(users) && any(!vapply(posterior_files[users], function(object) {
      object$name %in% affected_old
    }, logical(1)))) {
      stop("Reference posterior '", item$old, "' is shared with an unaffected posterior.", call. = FALSE)
    }
    actions <- rename_pdb_add_reference_actions(actions, pdb, item$old, item$new)
  }

  alias_path <- pdb_local_resource_path(pdb, file.path("alias", "posteriors.json"))
  if (file.exists(alias_path) && length(affected)) {
    aliases <- rename_pdb_read_json(alias_path)
    changed <- FALSE
    for (item in affected) {
      for (i in seq_along(aliases)) {
        if (identical(aliases[[i]], item$old)) {
          aliases[[i]] <- item$new
          changed <- TRUE
        }
      }
    }
    if (changed) {
      add(file.path("alias", "posteriors.json"), file.path("alias", "posteriors.json"),
          rename_pdb_json_text(aliases))
    }
  }

  rename_pdb_commit(actions, pdb)
  try(pdb_clear_cache(pdb), silent = TRUE)
  invisible(TRUE)
}
