#' Extract and construct model code objects
#'
#' @param x an object to access file path to.
#' @param framework model code framework (e.g. \code{stan}).
#' @param pdb a \code{pdb} object.
#' @param info a \code{pdb_model_info} object.
#' @param ... further arguments supplied to methods.
#'
#' @seealso framework()
#' @details A posterior with embedded code returns it for the matching
#'   framework. Other frameworks use the attached database, if available.
#'   Character-code construction preserves the requested framework (default
#'   `stan`) and requires a matching non-NULL implementation in `info`.
#'   Construction keeps the code unchanged; it does not compile or translate it.
#'   Stored code is read from the selected implementation's `model_code`
#'   path. Model info that does not record a path uses the
#'   conventional `models/<framework>/<name>.<extension>` location.
#'   For posterior or model-info inputs, the supplied object's implementation
#'   metadata selects the file for both code and file-path access. A posterior
#'   can look up additional implementations through its attached database.
#'
#' @export
model_code <- function(x, ...) {
  UseMethod("model_code")
}

#' @rdname model_code
#' @export
as.model_code <- function(x, info, ...) {
  UseMethod("as.model_code")
}


#' @rdname model_code
#' @export
model_code.pdb_posterior <- function(x, framework, ...) {
  if (!is.null(x$embedded_model_code)) {
    checkmate::assert_choice(framework, supported_frameworks())
    if (identical(attr(x$embedded_model_code, "framework"), framework))
      return(x$embedded_model_code)
    if (is.null(pdb(x))) stop("No embedded model code for framework `", framework,
                             "`; attach a database to load another implementation.", call. = FALSE)
  }
  if (is.null(x$model_info$model_implementations[[framework]]))
    return(model_code(x$model_name, framework, pdb = pdb(x), ...))
  model_code(x$model_info, framework, pdb = pdb(x), ...)
}

#' @rdname model_code
#' @export
model_code.character <- function(x, framework, pdb = pdb_default(), ...) {
  checkmate::assert_string(x)
  model_code(model_info(x, pdb = pdb), framework, pdb = pdb, ...)
}

#' @rdname model_code
#' @export
model_code.pdb_model_info <- function(x, framework, pdb = pdb_default(), ...) {
  scfp <- model_code_file_path(x, framework, pdb, ...)
  out <- paste0(readLines(scfp), collapse = "\n")
  class(out) <- c("pdb_model_code", "character")
  framework(out) <- framework
  info(out) <- x
  pdb(out) <- pdb
  assert_model_code(out)
  out
}

#' @rdname model_code
#' @export
as.model_code.stanmodel <- function(x, info, ...){
  as.model_code(x@model_code, info = info, framework = "stan")
}

#' @rdname model_code
#' @export
as.model_code.character <- function(x, info, framework = "stan", ...){
  class(x) <- "pdb_model_code"
  framework(x) <- framework
  info(x) <- info
  assert_model_code(x)
  x
}

#' @rdname model_code
#' @export
pdb_model_code <- model_code

#' @rdname model_code
#' @export
as.pdb_model_code <- as.model_code


#' @rdname model_code
#' @export
model_code_file_path <- function(x, ...) {
  UseMethod("model_code_file_path")
}

#' @rdname model_code
#' @export
model_code_file_path.pdb_posterior <- function(x, framework, ...) {
  if (!is.null(x$embedded_model_code) && identical(framework(x$embedded_model_code), framework))
    stop("This in-memory posterior is not persisted; its embedded model code has no database file path.", call. = FALSE)
  if (is.null(pdb(x))) stop("No database file path is available for this in-memory posterior.", call. = FALSE)
  if (is.null(x$model_info$model_implementations[[framework]]))
    return(model_code_file_path(x$model_name, framework, pdb = pdb(x), ...))
  model_code_file_path(x$model_info, framework, pdb = pdb(x), ...)
}

#' @rdname model_code
#' @export
model_code_file_path.pdb_model_info <- function(x, framework, pdb = pdb_default(), ...) {
  pdb_cached_local_file_path(pdb, model_implementation_file_path(x, framework), unzip = FALSE)
}

#' @rdname model_code
#' @export
model_code_file_path.character <- function(x, framework, pdb = pdb_default(), ...) {
  model_code_file_path(model_info(x, pdb = pdb), framework, pdb = pdb, ...)
}

model_implementation_file_path <- function(x, framework) {
  checkmate::assert_class(x, "pdb_model_info")
  checkmate::assert_choice(framework, supported_frameworks())
  implementation <- x$model_implementations[[framework]]
  checkmate::assert_list(implementation)
  path <- implementation$model_code %||% file.path("models", framework,
    paste0(x$name, ".", supported_frameworks_file_extension(framework)))
  checkmate::assert_string(path)
  path
}

#' @export
print.pdb_model_code <- function(x, ...) {
  cat(x)
  invisible(x)
}

#' @rdname model_code
#' @export
stan_code_file_path <- function(x) {
  checkmate::assert_class(x, "pdb_posterior")
  model_code_file_path(x, "stan")
}

#' @rdname model_code
#' @export
stan_code <- function(x, ...) {
  model_code(x, framework = "stan", ...)
}

#' @rdname model_code
#' @export
as.stan_code <- function(x, info, ...) {
  as.model_code(x, framework = "stan", info = info, ...)
}

#' @rdname model_code
#' @export
pdb_stan_code <- stan_code


assert_model_code <- function(x){
  checkmate::assert_class(x, "pdb_model_code")
  checkmate::assert_string(x)
  checkmate::assert_choice(framework(x), choices = supported_frameworks())
  checkmate::assert_class(info(x), "pdb_model_info")
  checkmate::assert_list(info(x)$model_implementations[[framework(x)]])
}

#' Identify the framework for a given [model_code]
#'
#' @param x a [pdb_model_code] object.
#' @param value a supported framework.
#'
#' @export
framework <- function(x){
  UseMethod("framework")
}

#' @rdname framework
#' @export
framework.pdb_model_code <- function(x){
  attr(x, which = "framework")
}

#' @rdname framework
#' @export
`framework<-` <- function(x, value){
  UseMethod("framework<-")
}

#' @rdname framework
#' @export
`framework<-.character` <- function(x, value){
  checkmate::assert_choice(value, supported_frameworks())
  attr(x, "framework") <- value
  x
}

#' @rdname framework
#' @export
`framework<-.pdb_model_code` <- function(x, value){
  `framework<-.character`(x, value)
}

supported_frameworks <- function() c("stan", "pymc3", "pymc", "tfp", "pyro")

supported_frameworks_file_extension <- function(x){
  checkmate::assert_choice(x, choices = supported_frameworks())
  sffe <- c("stan"="stan", "pymc3"="py", "pymc"="py", "tfp"="py", "pyro"="py")
  sffe[x]
}
