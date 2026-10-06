#' Access a posterior in the posterior database
#'
#' @param x For `posterior()`, a saved posterior name. For `as.posterior()`,
#'   a named list used to construct a posterior object.
#' @param pdb a \code{pdb} posterior database object.
#' @param ... currently unused; posterior name lookups warn when extra arguments
#'   are supplied and continue the lookup.
#'
#' @details
#' Use `posterior(name, pdb)` to look up a saved record. Use `as.posterior()`
#' for list construction: provide `pdb_model_code`, `pdb_data`, and
#' `dimensions` (named unconstrained parameter counts), or the complete
#' posterior metadata fields. If dimensions are omitted, supplied Stan code
#' and data are used to infer them, which can require compilation.
#' Construction does not write files. `pdb_posterior()` is the lookup alias;
#' `as.pdb_posterior()` is the construction alias.
#'
#' Saved records may contain legacy dimension vectors describing output shapes.
#' Lookup preserves that metadata for reading data, model code, and reference
#' draws. Construction, writing, and count-based inference require scalar
#' unconstrained parameter counts; legacy vectors are not converted to counts.
#'
#' Posteriors returned by [create_pdb_bundle()] embed their data, model
#' code, and reference draws. Their normal getters work without a database.
#' A NULL connection is valid only with all three embedded objects; embedded
#' names are checked even when a connection is attached. `dimensions` stores
#' one unconstrained parameter count per parameter, not output shapes.
#'
#' List-based posterior construction preserves the optional character fields
#' `urls`, `references`, and `keywords` when they are supplied. When writing a
#' posterior, an omitted `keywords` field is serialized as `null`.
#'
#' @export
posterior <- function(x, pdb = pdb_default(), ...) {
  UseMethod("posterior")
}

#' @rdname posterior
#' @export
as.posterior <- function(x, pdb = pdb_default(), ...) {
  UseMethod("as.posterior")
}

#' @rdname posterior
#' @export
posterior.character <- function(x, pdb = pdb_default(), ...) {
  checkmate::assert_string(x)
  checkmate::assert_class(pdb, "pdb")
  if (...length())
    warning("Extra arguments to posterior name lookup will be disregarded.", call. = FALSE)
  x <- handle_aliases(x, type = "posteriors", pdb)
  po <- read_info_json(x, "posteriors", pdb)
  pdb(po) <- pdb
  class(po) <- "pdb_posterior"
  po$model_info <- read_model_info(po)
  po$data_info <- read_data_info(po)
  assert_pdb_posterior(po, allow_legacy_dimensions = TRUE)
  po
}

#' @rdname posterior
#' @export
as.posterior.list <- function(x, pdb = pdb_default(), ...) {
  supplied_model_code <- x$pdb_model_code
  supplied_data <- x$pdb_data
  if(!is.null(x$pdb_model_code) & !is.null(x$pdb_data)){
    # We setup the posterior object from a data and model object
    mci <- info(x$pdb_model_code)
    di <- info(x$pdb_data)
    x$name <- paste0(di$name, "-", mci$name)
    x$model_name <- mci$name
    x$data_name <- di$name
    x$model_info <- mci
    x$data_info <- di
    x$pdb_model_code <- NULL
    x$pdb_data <- NULL
  }
  if(is.null(x$reference_posterior_name)){
    x["reference_posterior_name"] <- list(NULL)
  }
  if(is.null(x$added_by)){
    x$added_by <- unname(Sys.info()["user"])
    message("'added_by' set to '", x$added_by, "'")
  }
  if(is.null(x$added_date)){
    x$added_date <- Sys.Date()
  }
  if(is.null(x$dimensions)){
    if (is.null(supplied_model_code) || is.null(supplied_data)) {
      stop("Posterior dimensions are missing. Supply unconstrained parameter counts or provide `pdb_model_code` and `pdb_data` so they can be inferred.", call. = FALSE)
    }
    code <- if (inherits(supplied_model_code, "pdb_model_code")) as.character(supplied_model_code) else supplied_model_code
    if (inherits(supplied_model_code, "pdb_model_code") && !identical(framework(supplied_model_code), "stan"))
      stop("Unconstrained dimension inference currently supports Stan model code only.", call. = FALSE)
    x$dimensions <- infer_posterior_dimensions(code, supplied_data, backend = "rstan")
  }
  embedded_fields <- intersect(
    names(x), c("embedded_data", "embedded_model_code", "embedded_reference_draws")
  )
  embedded_content <- x[embedded_fields]
  retained_fields <- c(
    pdb_posterior_must_include(), "urls", "references", "keywords"
  )
  x <- x[intersect(names(x), retained_fields)]
  x[embedded_fields] <- embedded_content

  pdb(x) <- pdb
  class(x) <- "pdb_posterior"
  assert_pdb_posterior(x)
  x
}

#' @rdname posterior
#' @export
pdb_posterior <- posterior

#' @rdname posterior
#' @export
as.pdb_posterior <- as.posterior

#' @export
print.pdb_posterior <- function(x, ...) {
  cat0("Posterior (", x$name, ")\n\n")
  print(x$data_info)
  cat0("\n")
  print(x$model_info)
  invisible(x)
}


pdb_posterior_must_include <- function(){
  must.include <- c(
    "name", "model_name", "data_name", "reference_posterior_name", "dimensions",
    "model_info", "data_info",
    "added_by", "added_date"
  )
}

assert_pdb_posterior <- function(x, allow_legacy_dimensions = FALSE) {
  checkmate::assert_class(x, "pdb_posterior")
  checkmate::assert_list(x)
  checkmate::assert_names(names(x), must.include = pdb_posterior_must_include())
  for (field in c("name", "data_name", "model_name"))
    assert_pdb_resource_name(x[[field]])
  if (!is.null(x$reference_posterior_name))
    assert_pdb_resource_name(x$reference_posterior_name)
  checkmate::assert_list(x$dimensions, min.len = 1L)
  checkmate::assert_named(x$dimensions, type = "unique")
  if (allow_legacy_dimensions) {
    for (dimension in x$dimensions)
      checkmate::assert_integerish(dimension, lower = 1L, min.len = 1L,
                                  any.missing = FALSE, tol = 0)
  } else {
    x$dimensions <- validate_posterior_dimension_counts(x$dimensions)
  }
  checkmate::assert_class(x$added_date, "Date")
  checkmate::assert_class(x$data_info$added_date, "Date")
  checkmate::assert_class(x$model_info$added_date, "Date")
  checkmate::assert_list(x$model_info, min.len = 1)
  checkmate::assert_character(x$urls, null.ok = TRUE)
  checkmate::assert_character(x$references, null.ok = TRUE)
  checkmate::assert_character(x$keywords, null.ok = TRUE)

  embedded <- c("embedded_data", "embedded_model_code", "embedded_reference_draws")
  if (is.null(pdb(x)) && any(vapply(embedded, function(key) is.null(x[[key]]), logical(1))))
    stop("A posterior without `pdb` requires embedded data, model code, and reference draws.", call. = FALSE)
  if (!is.null(pdb(x))) checkmate::assert_class(pdb(x), "pdb")
  # A connection supplies fallback content; it must not bypass validation of
  # the in-memory objects that getters prefer over that connection.
  if (!is.null(x$embedded_data)) {
    assert_data(x$embedded_data)
    if (!identical(info(x$embedded_data), x$data_info) ||
        !identical(info(x$embedded_data)$name, x$data_name))
      stop("Embedded data metadata conflicts with the posterior's data link.", call. = FALSE)
  }
  if (!is.null(x$embedded_model_code)) {
    assert_model_code(x$embedded_model_code)
    if (!identical(info(x$embedded_model_code), x$model_info) ||
        !identical(info(x$embedded_model_code)$name, x$model_name) ||
        !framework(x$embedded_model_code) %in% names(x$model_info$model_implementations))
      stop("Embedded model metadata conflicts with the posterior's model link.", call. = FALSE)
  }
  if (!is.null(x$embedded_reference_draws)) {
    assert_reference_posterior_draws(x$embedded_reference_draws)
    if (!identical(info(x$embedded_reference_draws)$name, x$reference_posterior_name))
      stop("Embedded reference draws conflict with the posterior's reference link.", call. = FALSE)
    embedded_variables <- posterior::variables(x$embedded_reference_draws)
    present_bases <- unique(sub("\\[.*$", "", embedded_variables))
    if (length(setdiff(names(x$dimensions), present_bases)))
      stop("Embedded reference draws are missing parameter variables declared by the posterior.", call. = FALSE)
  }
  invisible(x)
}
