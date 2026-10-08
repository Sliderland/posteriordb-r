#' Access data and model information
#'
#' @param x An object to access information for, or a named list to convert.
#'   For list input, `framework = "stan"` creates the Stan entry in
#'   `model_implementations` using the conventional model-code path and the
#'   default `stan_version = ">=2.26.0"`. A caller-supplied
#'   `model_implementations` list is retained as provided; if `framework` is
#'   also supplied, that implementation must be present in the list.
#' @param pdb a \code{pdb} object.
#' @param ... further arguments to methods.
#'
#' @export
# Retrieve existing metadata; as.model_info() constructs it from a list.
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
  # Expand framework shorthand, or retain explicit implementation metadata.
  if (!is.null(x$framework)) {
    framework <- x$framework
    checkmate::assert_string(framework)
    checkmate::assert_choice(framework, supported_frameworks())

    if (is.null(x$model_implementations)) {
      implementation <- list(
        model_code = paste0(
          "models/", framework, "/", x$name, ".",
          supported_frameworks_file_extension(framework)
        )
      )
      if (identical(framework, "stan")) {
        implementation$stan_version <- ">=2.26.0"
      }
      x$model_implementations <- stats::setNames(
        list(implementation), framework
      )
    } else {
      checkmate::assert_list(x$model_implementations)
      checkmate::assert_names(
        names(x$model_implementations),
        must.include = framework
      )
    }
    # Store the nested implementation entry, not the shorthand field.
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
  assert_pdb_resource_name(x$name)
  checkmate::assert_names(names(x$model_implementations), subset.of = supported_frameworks())
  checkmate::assert_true(any(!vapply(x$model_implementations, is.null, logical(1))))
  for (implementation_name in names(x$model_implementations)) {
    implementation <- x$model_implementations[[implementation_name]]
    if (is.null(implementation)) next
    checkmate::assert_list(implementation)
    # This package's fit import and model-code access workflows use Stan.
    # Preserve other implementation metadata from PosteriorDB without
    # validating framework-specific fields that these workflows ignore.
    if (implementation_name %in% c("pymc", "pymc3")) next
    allowed_fields <- if (implementation_name == "stan") {
      c("model_code", "stan_version")
    } else {
      c("model_code", "stan_version", "pymc_version")
    }
    # Check field names; source paths and code are not validated here.
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
