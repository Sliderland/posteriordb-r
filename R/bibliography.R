#' Get the bibliography of a posterior database
#'
#' @param pdb a posterior database connection
#' @param ... further arguments passed to [bibtex::read.bib]
#'
#' @export
bibliography <- function(pdb, ...) {
  checkmate::assert_class(pdb, "pdb")
  fp <- file.path("bibliography/references.bib")
  pfn <- pdb_cached_local_file_path(pdb, path = fp)
  bibtex::read.bib(pfn, ...)
}

#' Append references to a posterior database bibliography
#'
#' Add a BibTeX reference supplied either as a character string or as a
#' `bibentry` object. A character string must contain exactly one keyed entry;
#' a `bibentry` object may contain one or more entries. Before writing, the
#' complete bibliography is checked for duplicate citation keys (ignoring
#' case) and duplicate entries. If validation fails, the bibliography is left
#' unchanged. Only local posterior database connections can be modified.
#'
#' @param ref a character string containing one BibTeX entry, or a `bibentry`
#'   object containing one or more entries
#' @param pdb a local posterior database connection
#' @param ... further arguments passed to methods
#'
#' @return Invisibly, `TRUE`.
#' @export
append_reference <- function(ref, pdb, ...) {
  UseMethod("append_reference")
}

#' @rdname append_reference
#' @export
append_reference.character <- function(ref, pdb, ...) {
  checkmate::assert_string(ref, min.chars = 1L)
  parsed <- parse_bibtex_text(ref)
  if (length(parsed) != 1L) {
    stop("`ref` must contain exactly one keyed BibTeX entry.", call. = FALSE)
  }
  append_reference.bibentry(parsed, pdb, ...)
}

#' @rdname append_reference
#' @export
append_reference.bibentry <- function(ref, pdb, ...) {
  checkmate::assert_class(pdb, "pdb_local")
  if (length(ref) < 1L) {
    stop("`ref` must contain at least one BibTeX entry.", call. = FALSE)
  }

  reference_path <- pdb_file_path(pdb, "bibliography", "references.bib")
  checkmate::assert_file_exists(reference_path)
  existing <- if (file.info(reference_path)$size == 0L) {
    structure(list(), class = "bibentry")
  } else {
    bibtex::read.bib(reference_path)
  }
  combined <- c(existing, ref)
  assert_unique_bibliography(combined)

  separator <- if (file.info(reference_path)$size > 0L) "\n\n" else ""
  cat(separator, paste(as.character(utils::toBibtex(ref)), collapse = "\n"), "\n",
    file = reference_path, append = TRUE, sep = ""
  )

  cache_path <- file.path(pdb$cache_path, "bibliography", "references.bib")
  if (file.exists(cache_path)) {
    file.remove(cache_path)
  }
  invisible(TRUE)
}

parse_bibtex_text <- function(x) {
  keys <- bibtex_keys(x)
  if (length(keys) == 0L) {
    stop("`ref` does not contain a keyed BibTeX entry.", call. = FALSE)
  }
  if (anyDuplicated(tolower(keys))) {
    stop("`ref` contains duplicate citation keys.", call. = FALSE)
  }

  path <- tempfile(fileext = ".bib")
  on.exit(unlink(path), add = TRUE)
  writeLines(x, path, useBytes = TRUE)
  parsed <- suppressWarnings(bibtex::read.bib(path))
  if (length(parsed) != length(keys)) {
    stop("`ref` contains an invalid or unsupported BibTeX entry.",
      call. = FALSE
    )
  }
  parsed
}

bibtex_keys <- function(x) {
  pattern <- paste0(
    "@([[:alpha:]]+)\\s*[\\{(]\\s*",
    "([^,[:space:]]+)\\s*,"
  )
  matches <- regmatches(
    x,
    gregexpr(pattern, x, perl = TRUE, ignore.case = TRUE)
  )[[1L]]
  if (identical(matches, character(0))) {
    return(character())
  }
  types <- sub(pattern, "\\1", matches, perl = TRUE, ignore.case = TRUE)
  keys <- sub(pattern, "\\2", matches, perl = TRUE, ignore.case = TRUE)
  keys[!tolower(types) %in% c("comment", "preamble", "string")]
}

assert_unique_bibliography <- function(x) {
  entries <- unclass(x)
  keys <- vapply(entries, function(entry) attr(entry, "key"), character(1L))
  duplicate_keys <- unique(keys[duplicated(tolower(keys))])
  if (length(duplicate_keys) > 0L) {
    stop(
      "Duplicate BibTeX citation key(s): ",
      paste(duplicate_keys, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  fingerprints <- vapply(entries, bibentry_fingerprint, character(1L))
  duplicate_entries <- unique(keys[duplicated(fingerprints)])
  if (length(duplicate_entries) > 0L) {
    stop(
      "Duplicate BibTeX entry or entries found at key(s): ",
      paste(duplicate_entries, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

bibentry_fingerprint <- function(entry) {
  fields <- entry[sort(names(entry))]
  paste(
    c(tolower(attr(entry, "bibtype")), utils::capture.output(dput(fields))),
    collapse = "\n"
  )
}

#' @rdname bibliography
#' @export
pdb_bibliography <- bibliography
