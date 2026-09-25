#' Access data and model information
#'
#' @param x a object to access information for.
#' @param pdb a \code{pdb} object.
#' @param ... further arguments to methods.
#'
#' @export
model_info <- function(x, ...) {
  UseMethod("model_info")
}

#' @rdname model_info
#' @export
as.model_info <- function(x, ...) {
  UseMethod("as.model_info")
}

#' @rdname model_info
#' @export
pdb_model_info <- model_info

#' @rdname model_info
#' @export
as.pdb_model_info <- as.model_info

#' @rdname model_info
#' @export
model_info.pdb_posterior <- function(x, ...) {
  x$model_info
}

#' @rdname model_info
#' @export
model_info.character <- function(x, pdb = pdb_default(), ...) {
  checkmate::assert_string(x)
  read_model_info(x, pdb)
}

#' @rdname model_info
#' @export
as.model_info.list <- function(x, pdb = NULL, ...) {
  class(x) <- "pdb_model_info"
  if(!is.null(x$framework)){
    checkmate::assert_null(x$model_implementations)
    mi <- list(list("model_code" = paste0("models/", x$framework,"/", x$name, ".",
                supported_frameworks_file_extension(x$framework))))
    x$model_implementations <- mi
    names(x$model_implementations) <- x$framework
    x$framework <- NULL
  }
  assert_model_info(x)
  x
}


# read model info from the data base
read_model_info <- function(x, pdb = NULL, ...) {
  model_info <- read_info_json(x, path = "models/info", pdb = pdb, ...)
  class(model_info) <- "pdb_model_info"
  assert_model_info(model_info)
  model_info
}

#' @export
print.pdb_model_info <- function(x, ...) {
  cat0("Model: ", x$name, "\n")
  cat0(x$title, "\n")
  frameworks <- names(x$model_implementations)[!vapply(
    x$model_implementations, is.null, logical(1)
  )]
  cat0("Frameworks: '", paste(frameworks, collapse = "', '"), "'\n")
  invisible(x)
}

assert_model_info <- function(x){
  checkmate::assert_names(names(x),
                          subset.of = c("name", "model_implementations", "title", "prior", "added_by", "added_date", "references", "description", "urls", "keywords", "licence"),
                          must.include = c("name", "model_implementations", "title", "added_by", "added_date"))
  checkmate::assert_string(x$name)
  checkmate::assert_names(names(x$model_implementations), subset.of = supported_frameworks())
  checkmate::assert_true(any(!vapply(x$model_implementations, is.null, logical(1))))
  for (implementation_name in names(x$model_implementations)) {
    implementation <- x$model_implementations[[implementation_name]]
    if (is.null(implementation)) next
    checkmate::assert_list(implementation)
    allowed_fields <- if (implementation_name == "stan") {
      c("model_code", "likelihood_code", "stan_version")
    } else if (implementation_name %in% c("pymc", "pymc3")) {
      "model_code"
    } else {
      c("model_code", "likelihood_code", "stan_version", "pymc_version")
    }
    checkmate::assert_names(
      names(implementation),
      must.include = "model_code",
      subset.of = allowed_fields
    )
  }
  checkmate::assert_string(x$title)
  checkmate::assert_string(x$added_by)
  checkmate::assert_date(x$added_date)

  checkmate::assert_string(x$description, null.ok = TRUE)

  checkmate::assert_character(x$references, null.ok = TRUE)
  checkmate::assert_character(x$urls, null.ok = TRUE)
  checkmate::assert_character(x$keywords, null.ok = TRUE)
}
