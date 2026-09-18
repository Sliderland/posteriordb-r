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
#' Add BibTeX references supplied as a character string, a path to a `.bib`
#' file, or a `bibentry` object. A character string of BibTeX text must contain
#' exactly one keyed entry; a `.bib` file or `bibentry` object may contain
#' multiple entries. Before writing, the complete bibliography is checked for
#' duplicate citation keys (ignoring case) and duplicate entries. If validation
#' fails, the bibliography is left unchanged. Only local posterior database
#' connections can be modified.
#'
#' @param ref a character string containing one BibTeX entry, a path to a
#'   `.bib` file, or a `bibentry` object containing one or more entries
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
  is_file <- file.exists(ref)
  if (is_file) {
    checkmate::assert_file_exists(ref, access = "r")
    parsed <- parse_bibtex_text(
      paste(readLines(ref, warn = FALSE), collapse = "\n"), path = ref
    )
  } else {
    if (grepl("\\.bib$", ref, ignore.case = TRUE) &&
        !grepl("@", ref, fixed = TRUE)) {
      stop("BibTeX file does not exist: ", ref, call. = FALSE)
    }
    parsed <- parse_bibtex_text(ref)
  }
  if (!is_file && length(parsed) != 1L) {
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
  serialized <- paste(as.character(utils::toBibtex(ref)), collapse = "\n")
  parsed <- parse_bibtex_text(serialized)
  if (length(parsed) != length(ref)) {
    stop("`ref` contains an invalid BibTeX entry.", call. = FALSE)
  }

  reference_path <- pdb_file_path(pdb, "bibliography", "references.bib")
  checkmate::assert_file_exists(reference_path)
  existing <- if (file.info(reference_path)$size == 0L) {
    structure(list(), class = "bibentry")
  } else {
    parse_bibtex_text(
      paste(readLines(reference_path, warn = FALSE), collapse = "\n"),
      path = reference_path, allow_empty = TRUE,
      label = "The existing bibliography"
    )
  }
  combined <- c(existing, parsed)
  assert_unique_bibliography(combined)

  separator <- if (file.info(reference_path)$size > 0L) "\n\n" else ""
  append_bibliography_atomically(
    reference_path,
    paste0(separator, serialized, "\n")
  )

  cache_path <- file.path(pdb$cache_path, "bibliography", "references.bib")
  if (file.exists(cache_path) && !file.remove(cache_path)) {
    stop("Reference was appended, but the cached bibliography could not be ",
      "invalidated at ", cache_path,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

append_bibliography_atomically <- function(path, suffix) {
  size <- file.info(path)$size
  original <- if (isTRUE(size > 0L)) {
    rawToChar(readBin(path, what = "raw", n = size))
  } else {
    ""
  }
  replacement <- tempfile("references-bib-", tmpdir = dirname(path))
  backup <- tempfile("references-bib-backup-", tmpdir = dirname(path))
  committed <- FALSE
  on.exit({
    if (file.exists(replacement)) unlink(replacement)
    if (!committed && file.exists(backup) && !file.exists(path)) {
      file.rename(backup, path)
    }
    if (file.exists(backup)) unlink(backup)
  }, add = TRUE)

  con <- file(replacement, open = "wb")
  on.exit(if (!is.null(con)) try(close(con), silent = TRUE), add = TRUE)
  writeChar(paste0(original, suffix), con, eos = NULL, useBytes = TRUE)
  close(con)
  con <- NULL

  if (!file.rename(path, backup)) {
    stop("Could not stage the existing bibliography for replacement.", call. = FALSE)
  }
  if (!file.rename(replacement, path)) {
    file.rename(backup, path)
    stop("Could not commit the updated bibliography.", call. = FALSE)
  }
  committed <- TRUE
  invisible(TRUE)
}

parse_bibtex_text <- function(x, path = NULL, allow_empty = FALSE,
                              label = "`ref`") {
  keys <- bibtex_keys(x)
  if (length(keys) == 0L && !allow_empty) {
    stop(label, " does not contain a keyed BibTeX entry.", call. = FALSE)
  }
  if (anyDuplicated(tolower(keys))) {
    stop(
      label, " contains duplicate citation key(s): ",
      paste(duplicate_pairs(tolower(keys), keys), collapse = ", "),
      ".", call. = FALSE
    )
  }

  if (is.null(path)) {
    path <- tempfile(fileext = ".bib")
    on.exit(unlink(path), add = TRUE)
    writeLines(x, path, useBytes = TRUE)
  }
  parsed <- tryCatch(
    suppressWarnings(bibtex::read.bib(path)),
    error = function(e) {
      stop(label, " contains an invalid or unsupported BibTeX entry.",
        call. = FALSE
      )
    }
  )
  parsed_keys <- unname(vapply(unclass(parsed), function(entry) {
    key <- attr(entry, "key")
    if (length(key) != 1L || is.na(key) || !nzchar(key)) {
      return(NA_character_)
    }
    key
  }, character(1L)))
  if (length(parsed) != length(keys) || anyNA(parsed_keys) ||
      !identical(parsed_keys, keys)) {
    stop(label, " contains an invalid or unsupported BibTeX entry.",
      call. = FALSE
    )
  }
  parsed
}

bibtex_keys <- function(x) {
  chars <- strsplit(x, "", fixed = TRUE, useBytes = TRUE)[[1L]]
  n <- length(chars)
  keys <- character()
  i <- 1L
  whitespace <- c(" ", "\t", "\r", "\n")

  while (i <= n) {
    if (chars[i] == "%") {
      while (i <= n && chars[i] != "\n") i <- i + 1L
    }
    if (i > n || chars[i] != "@") {
      i <- i + 1L
      next
    }

    j <- i + 1L
    while (j <= n && chars[j] %in% whitespace) j <- j + 1L
    type_start <- j
    while (j <= n && grepl("^[A-Za-z]$", chars[j])) j <- j + 1L
    if (j == type_start) {
      i <- i + 1L
      next
    }
    type <- tolower(paste(chars[type_start:(j - 1L)], collapse = ""))
    while (j <= n && chars[j] %in% whitespace) j <- j + 1L
    if (j > n || !chars[j] %in% c("{", "(")) {
      i <- i + 1L
      next
    }

    opening <- chars[j]
    closing <- if (opening == "{") "}" else ")"
    j <- j + 1L
    if (!type %in% c("comment", "preamble", "string")) {
      while (j <= n && chars[j] %in% whitespace) j <- j + 1L
      key_start <- j
      while (j <= n && !chars[j] %in% c(",", closing)) j <- j + 1L
      key <- if (j == key_start) "" else
        trimws(paste(chars[key_start:(j - 1L)], collapse = ""))
      keys <- c(keys, key)
    }

    depth <- 1L
    braces <- 0L
    quoted <- FALSE
    while (j <= n && depth > 0L) {
      char <- chars[j]
      if (char == "\\") {
        j <- j + 2L
        next
      }
      if (type != "comment" && char == '"' &&
          (opening == "(" && braces == 0L ||
           opening == "{" && depth == 1L)) {
        quoted <- !quoted
      } else if (!quoted && opening == "{") {
        if (char == "{") depth <- depth + 1L
        if (char == "}") depth <- depth - 1L
      } else if (!quoted && opening == "(") {
        if (char == "{") braces <- braces + 1L
        if (char == "}" && braces > 0L) braces <- braces - 1L
        if (char == ")" && braces == 0L) depth <- depth - 1L
      }
      j <- j + 1L
    }
    i <- j
  }
  keys
}

assert_unique_bibliography <- function(x) {
  entries <- unclass(x)
  keys <- vapply(entries, function(entry) attr(entry, "key"), character(1L))
  duplicate_keys <- duplicate_pairs(tolower(keys), keys)
  if (length(duplicate_keys)) {
    stop(
      "Duplicate BibTeX citation key(s): ",
      paste(duplicate_keys, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  fingerprints <- vapply(entries, bibentry_fingerprint, character(1L))
  duplicate_entries <- duplicate_pairs(fingerprints, keys)
  if (length(duplicate_entries)) {
    stop(
      "Duplicate BibTeX entry or entries found at key(s): ",
      paste(duplicate_entries, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

duplicate_pairs <- function(values, keys) {
  later <- which(duplicated(values))
  if (!length(later)) {
    return(character())
  }
  vapply(later, function(i) {
    first <- match(values[i], values)
    paste0("`", keys[first], "` and `", keys[i], "`")
  }, character(1L))
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
