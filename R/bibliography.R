#' Bibliography of a posterior database
#'
#' Data, models and posteriors cite their sources with BibTeX keys from
#' `bibliography/references.bib`. `bibliography()` reads that file,
#' `bibliography_keys()` lists its keys and `bibliography_entry()` returns
#' one entry. `append_reference()` adds entries to a local database; keys
#' already in the bibliography (ignoring case) are rejected and nothing is
#' written.
#'
#' @param pdb A [pdb][pdb_local] connection (local for `append_reference()`).
#' @param key A BibTeX key.
#' @param ref A `bibentry` object, BibTeX text with one entry, or a path to
#'   a `.bib` file.
#' @param ... Passed to [bibtex::read.bib()].
#' @return A `bibentry` object; `bibliography_keys()` returns a character
#'   vector and `append_reference()` returns `TRUE` invisibly.
#' @export
bibliography <- function(pdb = pdb_default(), ...) {
  bibtex::read.bib(pdb_file(pdb, "bibliography/references.bib"), ...)
}

#' @rdname bibliography
#' @export
pdb_bibliography <- bibliography

#' @rdname bibliography
#' @export
bibliography_keys <- function(pdb = pdb_default(), ...) names(bibliography(pdb, ...))

#' @rdname bibliography
#' @export
bibliography_entry <- function(key, pdb = pdb_default(), ...) {
  bib <- bibliography(pdb, ...)
  checkmate::assert_choice(key, names(bib))
  bib[key]
}

#' @rdname bibliography
#' @export
append_reference <- function(ref, pdb) {
  checkmate::assert_class(pdb, "pdb_local")
  if (is.character(ref)) ref <- parse_bibtex(ref)
  checkmate::assert_class(ref, "bibentry")
  if (!length(ref)) stop2("`ref` has no BibTeX entries.")
  keys <- names(ref)
  path <- file.path(pdb$path, "bibliography", "references.bib")
  existing <- if (file.exists(path) && file.size(path) > 0) names(bibtex::read.bib(path)) else character()
  clash <- keys[tolower(keys) %in% tolower(existing) | duplicated(tolower(keys))]
  if (length(clash)) stop2("Key(s) already in the bibliography: ", paste(clash, collapse = ", "))
  text <- paste(format(ref, style = "Bibtex"), collapse = "\n\n")
  old <- if (file.exists(path)) readLines(path, warn = FALSE, encoding = "UTF-8") else character()
  write_text_file(c(old, if (length(old)) "", text), path)
  invisible(TRUE)
}

parse_bibtex <- function(x) {
  checkmate::assert_string(x)
  path <- x
  if (!file.exists(x)) {
    path <- tempfile(fileext = ".bib")
    on.exit(unlink(path))
    writeLines(x, path)
  }
  n_entries <- sum(grepl("^\\s*@", readLines(path, warn = FALSE)))
  bib <- withCallingHandlers(bibtex::read.bib(path),
                             warning = function(w) stop2("Invalid BibTeX: ", conditionMessage(w)))
  if (length(bib) != n_entries) stop2("Some BibTeX entries could not be read.")
  if (!file.exists(x) && length(bib) != 1L) stop2("BibTeX text must contain exactly one entry.")
  bib
}
