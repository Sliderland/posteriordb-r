#' Model and data information
#'
#' `model_info()` and `data_info()` return the metadata record of a model or
#' data set: its name, title, description, references, keywords and so on.
#' `as.model_info()` and `as.data_info()` build such a record from a named
#' list, for example before writing a new model or data set.
#'
#' For `as.model_info()`, `framework = "stan"` is shorthand for a Stan
#' implementation stored at the conventional `models/stan/<name>.stan` path.
#' `as.data_info()` sets `data_file` to `data/data/<name>.json` when missing.
#' `added_by` and `added_date` default to the current user and date.
#'
#' @param x A posterior, a name, or (for the `as.` functions) a named list.
#' @param pdb A [pdb][pdb_local] connection, used when `x` is a name.
#' @param ... Not used.
#' @return A `pdb_model_info` or `pdb_data_info` object.
#' @export
model_info <- function(x, ...) UseMethod("model_info")

#' @rdname model_info
#' @export
model_info.pdb_posterior <- function(x, ...) x$model_info

#' @rdname model_info
#' @export
model_info.pdb_model_code <- function(x, ...) info(x)

#' @rdname model_info
#' @export
model_info.character <- function(x, pdb = pdb_default(), ...) {
  assert_name(x, "model name")
  mi <- as.model_info(pdb_read_json(pdb, file.path("models", "info", paste0(x, ".info.json"))))
  pdb(mi) <- pdb
  mi
}

#' @rdname model_info
#' @export
pdb_model_info <- model_info

#' @rdname model_info
#' @export
as.model_info <- function(x, ...) UseMethod("as.model_info")

#' @rdname model_info
#' @export
as.pdb_model_info <- as.model_info

#' @export
as.model_info.pdb_model_info <- function(x, ...) x

#' @rdname model_info
#' @export
as.model_info.list <- function(x, ...) {
  x <- normalize_info(x)
  if (!is.null(x$framework)) {
    checkmate::assert_choice(x$framework, supported_frameworks())
    if (is.null(x$model_implementations[[x$framework]])) {
      impl <- list(model_code = default_model_path(x$name, x$framework))
      if (x$framework == "stan") impl$stan_version <- ">=2.26.0"
      x$model_implementations[[x$framework]] <- impl
    }
    x$framework <- NULL
  }
  x$added_by <- x$added_by %||% unname(Sys.info()[["user"]])
  x$added_date <- x$added_date %||% Sys.Date()
  x <- structure(x, class = "pdb_model_info")
  assert_model_info(x)
  x
}

default_model_path <- function(name, framework) {
  paste0("models/", framework, "/", name, ".", framework_extension(framework))
}

assert_model_info <- function(x) {
  assert_name(x$name, "model name")
  checkmate::assert_string(x$title, .var.name = "title")
  checkmate::assert_list(x$model_implementations, min.len = 1, names = "unique",
                         .var.name = "model_implementations")
  checkmate::assert_subset(names(x$model_implementations), supported_frameworks(),
                           .var.name = "model_implementations")
  assert_known_fields(x, c("name", "model_implementations", "title", "prior", "licence"), "model info")
  for (framework in names(x$model_implementations)) {
    impl <- x$model_implementations[[framework]]
    checkmate::assert_string(impl$model_code, .var.name = paste0(framework, " model_code"))
    assert_known_fields(impl, c("model_code", "likelihood_code", "stan_version", "pymc_version"),
                        paste(framework, "model implementation"), common = FALSE)
  }
  assert_common_info(x)
}

# The info schema is closed, so a misspelled field is an error rather than
# silently stored.
assert_known_fields <- function(x, allowed, what, common = TRUE) {
  if (common) allowed <- c(allowed, "added_by", "added_date", "description", "keywords", "references", "urls")
  unknown <- setdiff(names(x), allowed)
  if (length(unknown)) stop2("Unknown field(s) in ", what, ": ", paste(unknown, collapse = ", "))
}

assert_common_info <- function(x) {
  checkmate::assert_string(x$added_by, .var.name = "added_by")
  checkmate::assert_date(x$added_date, len = 1, .var.name = "added_date")
  checkmate::assert_string(x$description, null.ok = TRUE, .var.name = "description")
  for (field in c("keywords", "references", "urls")) {
    checkmate::assert_character(x[[field]], null.ok = TRUE, .var.name = field)
  }
  invisible(x)
}

#' @export
print.pdb_model_info <- function(x, ...) {
  cat0("Model: ", x$name, "\n", x$title, "\n")
  cat0("Frameworks: '", paste(names(x$model_implementations), collapse = "', '"), "'\n")
  invisible(x)
}

#' Model code
#'
#' `model_code()` returns the code of a model in one framework, and
#' `stan_code()` is the Stan shortcut. `model_code_file_path()` returns a
#' local path to the code file. `as.model_code()` wraps a code string (or an
#' rstan `stanmodel`) together with its model info.
#'
#' @param x A posterior, a model name, a `pdb_model_info` object, or (for
#'   `as.model_code()`) a code string or `stanmodel`.
#' @param framework A modelling framework, such as `"stan"` or `"pymc"`.
#' @param pdb A [pdb][pdb_local] connection, used when `x` is a name or info.
#' @param info A `pdb_model_info` object (or a list for [as.model_info()]).
#' @param ... Not used.
#' @return A `pdb_model_code` object: the code as a string, with `info`,
#'   `framework` and `pdb` attributes. File-path functions return a string.
#' @export
model_code <- function(x, ...) UseMethod("model_code")

#' @rdname model_code
#' @export
model_code.pdb_posterior <- function(x, framework, ...) {
  embedded <- x$embedded$model_code
  if (!is.null(embedded) && identical(framework(embedded), framework)) return(embedded)
  model_code(x$model_info, framework, pdb = posterior_pdb(x))
}

#' @rdname model_code
#' @export
model_code.character <- function(x, framework, pdb = pdb_default(), ...) {
  model_code(model_info(x, pdb = pdb), framework, pdb = pdb)
}

#' @rdname model_code
#' @export
model_code.pdb_model_info <- function(x, framework, pdb = pdb_default(), ...) {
  code <- paste(readLines(model_code_file_path(x, framework, pdb = pdb), warn = FALSE),
                collapse = "\n")
  out <- as.model_code(code, info = x, framework = framework)
  pdb(out) <- pdb
  out
}

#' @rdname model_code
#' @export
pdb_model_code <- model_code

#' @rdname model_code
#' @export
stan_code <- function(x, ...) model_code(x, framework = "stan", ...)

#' @rdname model_code
#' @export
pdb_stan_code <- stan_code

#' @rdname model_code
#' @export
model_code_file_path <- function(x, ...) UseMethod("model_code_file_path")

#' @rdname model_code
#' @export
model_code_file_path.pdb_posterior <- function(x, framework, ...) {
  model_code_file_path(x$model_info, framework, pdb = posterior_pdb(x))
}

#' @rdname model_code
#' @export
model_code_file_path.character <- function(x, framework, pdb = pdb_default(), ...) {
  model_code_file_path(model_info(x, pdb = pdb), framework, pdb = pdb)
}

#' @rdname model_code
#' @export
model_code_file_path.pdb_model_info <- function(x, framework, pdb = pdb_default(), ...) {
  pdb_file(pdb, model_code_path(x, framework))
}

#' @rdname model_code
#' @export
stan_code_file_path <- function(x, ...) model_code_file_path(x, framework = "stan", ...)

# Relative database path of a model's code in one framework.
model_code_path <- function(info, framework) {
  checkmate::assert_choice(framework, supported_frameworks())
  impl <- info$model_implementations[[framework]]
  if (is.null(impl)) stop2("Model '", info$name, "' has no ", framework, " implementation.")
  impl$model_code %||% default_model_path(info$name, framework)
}

#' @rdname model_code
#' @export
as.model_code <- function(x, ...) UseMethod("as.model_code")

#' @rdname model_code
#' @export
as.pdb_model_code <- as.model_code

#' @rdname model_code
#' @export
as.model_code.character <- function(x, info, framework = "stan", ...) {
  checkmate::assert_string(x)
  checkmate::assert_choice(framework, supported_frameworks())
  info <- as.model_info(info)
  if (is.null(info$model_implementations[[framework]])) {
    stop2("`info` has no ", framework, " implementation.")
  }
  structure(as.character(x), class = c("pdb_model_code", "character"),
            info = info, framework = framework)
}

#' @rdname model_code
#' @export
as.model_code.stanmodel <- function(x, info, ...) {
  as.model_code(x@model_code[1], info = info, framework = "stan")
}

#' @rdname model_code
#' @export
as.stan_code <- function(x, info, ...) as.model_code(x, info = info, framework = "stan")

#' @export
print.pdb_model_code <- function(x, ...) {
  cat(x, "\n")
  invisible(x)
}

#' Framework of model code
#'
#' @param x A `pdb_model_code` object.
#' @param value A supported framework, such as `"stan"`.
#' @return The framework as a string.
#' @export
framework <- function(x) attr(x, "framework")

#' @rdname framework
#' @export
`framework<-` <- function(x, value) {
  checkmate::assert_choice(value, supported_frameworks())
  attr(x, "framework") <- value
  x
}

# A posterior's connection, with a clear error for in-memory posteriors.
posterior_pdb <- function(x) {
  pdb(x) %||% stop2("Posterior '", x$name, "' is not attached to a database.")
}
