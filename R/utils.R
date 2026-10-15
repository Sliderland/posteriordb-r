#' @keywords internal
"_PACKAGE"

`%||%` <- function(x, y) if (is.null(x)) y else x

stop2 <- function(...) stop(..., call. = FALSE)

cat0 <- function(...) cat(..., sep = "")

# Resource names become file names, so they must be one path component.
assert_name <- function(x, what = "name") {
  checkmate::assert_string(x, min.chars = 1, .var.name = what)
  if (x %in% c(".", "..") || grepl("[/\\\\[:cntrl:]]", x)) {
    stop2("`", what, "` must be a single path component: '", x, "'.")
  }
  invisible(x)
}

supported_frameworks <- function() c("stan", "pymc", "pymc3", "tfp", "pyro")

framework_extension <- function(framework) {
  if (identical(framework, "stan")) "stan" else "py"
}

summary_statistic_types <- function() c("mean_value", "mean_squared_value")

reference_posterior_types <- function() c("draws", summary_statistic_types())

# Relative directory (inside reference_posteriors/) for one reference type.
reference_type_dir <- function(type) {
  checkmate::assert_choice(type, reference_posterior_types())
  if (type == "draws") "draws" else file.path("summary_statistics", type)
}

# "theta[1,2]" -> "theta"
base_variable <- function(x) sub("\\[.*$", "", x)

# JSON -------------------------------------------------------------------------

json_text <- function(x, auto_unbox = TRUE) {
  out <- jsonlite::toJSON(x, pretty = TRUE, auto_unbox = auto_unbox,
                          null = "null", na = "null", digits = NA)
  enc2utf8(as.character(out))
}

read_json_file <- function(path, simplify = TRUE) {
  jsonlite::read_json(path, simplifyVector = simplify)
}

write_text_file <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  # Write the UTF-8 bytes as they are, whatever the session's locale.
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(enc2utf8(text), con, useBytes = TRUE)
  invisible(path)
}

# Write `text` as the single member `member` of the ZIP archive `zipfile`.
write_zip_json <- function(text, zipfile, member = sub("[.]zip$", "", basename(zipfile))) {
  staging <- tempfile("pdbzip")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE))
  write_text_file(text, file.path(staging, member))
  dir.create(dirname(zipfile), recursive = TRUE, showWarnings = FALSE)
  target <- normalizePath(zipfile, mustWork = FALSE)
  if (file.exists(target)) file.remove(target)
  status <- utils::zip(target, file.path(staging, member), flags = "-jq9X")
  if (!identical(as.integer(status), 0L) || !file.exists(target)) {
    stop2("Could not create ZIP archive '", zipfile, "'. Is a `zip` program available?")
  }
  invisible(zipfile)
}

# Extract the single JSON member of `zipfile` to `destination`.
unzip_json <- function(zipfile, destination) {
  members <- utils::unzip(zipfile, list = TRUE)$Name
  members <- members[!endsWith(members, "/")]
  if (length(members) != 1L) {
    stop2("Expected one file in the ZIP archive '", zipfile, "'.")
  }
  staging <- tempfile("pdbunzip")
  on.exit(unlink(staging, recursive = TRUE))
  utils::unzip(zipfile, files = members, exdir = staging, junkpaths = TRUE)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(file.path(staging, basename(members)), destination, overwrite = TRUE)) {
    stop2("Could not extract '", zipfile, "' to '", destination, "'.")
  }
  invisible(destination)
}

# Strip classes and attributes that should never be serialized.
plain_list <- function(x, drop = character()) {
  x <- unclass(x)
  attr(x, "pdb") <- NULL
  attr(x, "info") <- NULL
  if (length(drop)) x <- x[setdiff(names(x), drop)]
  x
}

# Empty JSON arrays are read as list(); the info schema uses character vectors.
normalize_info <- function(x) {
  for (field in c("keywords", "references", "urls")) {
    if (is.list(x[[field]]) && length(x[[field]]) == 0L) x[[field]] <- character()
  }
  if (!is.null(x$added_date)) x$added_date <- as.Date(x$added_date)
  x
}

require_package <- function(pkg, why) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop2("The `", pkg, "` package is required ", why, ".")
  }
}
