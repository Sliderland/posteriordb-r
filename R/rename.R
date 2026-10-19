#' Rename data, a model or a posterior in a local database
#'
#' Renames the object's files and updates everything that refers to it:
#' posteriors that use renamed data or a renamed model (a posterior called
#' `"<data>-<model>"` is renamed to match), reference posteriors named after
#' a renamed posterior, the links to them, and aliases.
#'
#' All new files are written before any old file is removed. The old files
#' are only removed once every new file has been written.
#'
#' @param x A posterior, data, model code or info object, or a name.
#' @param new_name The new name.
#' @param type For a name: `"data"`, `"model"` or `"posterior"`. Needed only
#'   when the name is used by more than one type.
#' @param pdb A local [pdb][pdb_local] connection; defaults to the object's.
#' @param ... Not used.
#' @return The renamed object, read back from the database (for a name, the
#'   object it names).
#' @export
rename_pdb <- function(x, new_name, ...) UseMethod("rename_pdb")

#' @rdname rename_pdb
#' @export
rename_pdb.character <- function(x, new_name, type = NULL, pdb = pdb_default(), ...) {
  if (is.null(type)) {
    found <- c(data = x %in% data_names(pdb), model = x %in% model_names(pdb),
               posterior = x %in% posterior_names(pdb))
    if (sum(found) != 1L) stop2("Give `type`: '", x, "' is used by ", sum(found), " object types.")
    type <- names(found)[found]
  }
  checkmate::assert_choice(type, c("data", "model", "posterior"))
  rename_in_pdb(x, new_name, type, pdb)
  switch(type, data = data_info(new_name, pdb = pdb), model = model_info(new_name, pdb = pdb),
         posterior = posterior(new_name, pdb = pdb))
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_posterior <- function(x, new_name, pdb = posteriordb::pdb(x), ...) {
  rename_in_pdb(x$name, new_name, "posterior", pdb)
  posterior(new_name, pdb = pdb)
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_data <- function(x, new_name, pdb = posteriordb::pdb(x), ...) {
  rename_in_pdb(info(x)$name, new_name, "data", pdb)
  get_data(new_name, pdb = pdb)
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_data_info <- function(x, new_name, pdb = pdb_default(), ...) {
  rename_in_pdb(x$name, new_name, "data", pdb)
  data_info(new_name, pdb = pdb)
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_model_code <- function(x, new_name, pdb = posteriordb::pdb(x), ...) {
  rename_in_pdb(info(x)$name, new_name, "model", pdb)
  model_code(new_name, framework = framework(x), pdb = pdb)
}

#' @rdname rename_pdb
#' @export
rename_pdb.pdb_model_info <- function(x, new_name, pdb = pdb_default(), ...) {
  rename_in_pdb(x$name, new_name, "model", pdb)
  model_info(new_name, pdb = pdb)
}

rename_in_pdb <- function(old, new, type, pdb) {
  checkmate::assert_class(pdb, "pdb_local")
  assert_name(new, "new_name")
  if (identical(old, new)) return(invisible(new))
  existing <- switch(type, data = data_names(pdb), model = model_names(pdb),
                     posterior = posterior_names(pdb))
  if (new %in% existing) stop2("A ", type, " named '", new, "' already exists.")
  ops <- list()
  move <- function(from, to, text = NULL, zip = FALSE) {
    ops[[length(ops) + 1L]] <<- list(from = from, to = to, text = text, zip = zip)
  }
  read <- function(path) read_json_file(file.path(pdb$path, path), simplify = FALSE)

  if (type == "data") {
    di <- read(file.path("data", "info", paste0(old, ".info.json")))
    di$name <- new
    di$data_file <- default_data_path(new)
    move(file.path("data", "info", paste0(old, ".info.json")),
         file.path("data", "info", paste0(new, ".info.json")), json_text(di))
    move(paste0(default_data_path(old), ".zip"), paste0(default_data_path(new), ".zip"), zip = TRUE)
  }
  if (type == "model") {
    mi <- read(file.path("models", "info", paste0(old, ".info.json")))
    mi$name <- new
    for (fw in names(mi$model_implementations)) {
      from <- mi$model_implementations[[fw]]$model_code %||% default_model_path(old, fw)
      to <- file.path(dirname(from), sub(paste0("^", old, "\\."), paste0(new, "."), basename(from)))
      mi$model_implementations[[fw]]$model_code <- to
      move(from, to)
    }
    move(file.path("models", "info", paste0(old, ".info.json")),
         file.path("models", "info", paste0(new, ".info.json")), json_text(mi))
  }

  # Posteriors: update the affected ones and follow their reference posteriors.
  pns <- posterior_names(pdb)
  records <- stats::setNames(lapply(pns, function(n) read(file.path("posteriors", paste0(n, ".json")))), pns)
  renamed <- list()
  changed <- character()
  for (pn in pns) {
    r <- records[[pn]]
    new_pn <- pn
    if (type == "posterior" && identical(pn, old)) new_pn <- new
    if (type == "data" && identical(r$data_name, old)) {
      r$data_name <- new
      changed <- c(changed, pn)
      if (identical(pn, paste0(old, "-", r$model_name))) new_pn <- paste0(new, "-", r$model_name)
    }
    if (type == "model" && identical(r$model_name, old)) {
      r$model_name <- new
      changed <- c(changed, pn)
      if (identical(pn, paste0(r$data_name, "-", old))) new_pn <- paste0(r$data_name, "-", new)
    }
    if (!identical(new_pn, pn)) {
      renamed[[pn]] <- new_pn
      r$name <- new_pn
    }
    records[[pn]] <- r
  }
  if (type == "posterior" && !length(renamed)) stop2("No posterior named '", old, "'.")
  reference_renames <- renamed[names(renamed) %in% reference_posterior_names(pdb)]
  for (ref in names(reference_renames)) {
    for (path in reference_files(pdb, ref)) {
      new_path <- file.path(dirname(path), sub(ref, reference_renames[[ref]], basename(path), fixed = TRUE))
      if (endsWith(path, ".info.json")) {
        ri <- read(path)
        ri$name <- reference_renames[[ref]]
        move(path, new_path, json_text(ri))
      } else {
        move(path, new_path, zip = endsWith(path, ".zip"))
      }
    }
  }
  for (pn in pns) {
    r <- records[[pn]]
    ref <- r$reference_posterior_name
    if (!is.null(ref) && ref %in% names(reference_renames)) {
      r$reference_posterior_name <- reference_renames[[ref]]
      changed <- c(changed, pn)
    }
    if (pn %in% c(changed, names(renamed))) {
      move(file.path("posteriors", paste0(pn, ".json")),
           file.path("posteriors", paste0(r$name, ".json")), json_text(r))
    }
  }
  aliases <- pdb_aliases(pdb)
  if (any(unlist(aliases) %in% names(renamed))) {
    aliases <- lapply(aliases, function(a) renamed[[a]] %||% a)
    move("alias/posteriors.json", "alias/posteriors.json", json_text(aliases))
  }
  execute_moves(ops, pdb)
  invisible(new)
}

reference_files <- function(pdb, name) {
  dirs <- file.path("reference_posteriors",
                    vapply(reference_posterior_types(), reference_type_dir, ""))
  candidates <- c(file.path(dirs, "info", paste0(name, ".info.json")),
                  file.path("reference_posteriors", "draws", "draws", paste0(name, ".json.zip")),
                  file.path("reference_posteriors", "summary_statistics", summary_statistic_types(),
                            summary_statistic_types(), paste0(name, ".json")))
  candidates[file.exists(file.path(pdb$path, candidates))]
}

# Write every target, then remove sources that are not targets.
execute_moves <- function(ops, pdb) {
  from <- vapply(ops, `[[`, "", "from")
  to <- vapply(ops, `[[`, "", "to")
  taken <- c(to[to != from & file.exists(file.path(pdb$path, to)) & !to %in% from],
             to[duplicated(to)])
  if (length(taken)) stop2("Nothing was renamed; these files already exist: ", paste(taken, collapse = ", "))
  missing <- from[!file.exists(file.path(pdb$path, from))]
  if (length(missing)) stop2("Nothing was renamed; these files are missing: ", paste(missing, collapse = ", "))
  # Read zipped and copied sources before anything is overwritten.
  for (i in seq_along(ops)) {
    if (is.null(ops[[i]]$text)) {
      src <- file.path(pdb$path, from[i])
      if (ops[[i]]$zip) {
        tmp <- tempfile(fileext = ".json")
        unzip_json(src, tmp)
        ops[[i]]$text <- paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        unlink(tmp)
      } else {
        ops[[i]]$text <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      }
    }
  }
  for (op in ops) {
    target <- file.path(pdb$path, op$to)
    if (op$zip) write_zip_json(op$text, target) else write_text_file(op$text, target)
  }
  old <- setdiff(from, to)
  file.remove(file.path(pdb$path, old))
  invisible(TRUE)
}
