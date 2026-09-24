#' Access a posterior in the posterior database
#'
#' @param x a posterior name that exist in the posterior database or a
#'          list used to construct a posterior object.
#' @param pdb a \code{pdb} posterior database object.
#' @param ... currently not in use.
#'
#' @details
#' To setup a posterior object from a list, a minimum och a `pdb_model`,
#' `pdb_data`, and a `dimension` element need to be included. See
#' `posterior("eight_schools")$dimensions` for an example.
#'
#' Posteriors returned by [create_pdb_reference_draws()] embed their data, model
#' code, and reference draws. Their normal getters work without a database.
#' A NULL connection is valid only with all three embedded objects; embedded
#' names and draw dimensions are checked even when a connection is attached.
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
  x <- handle_aliases(x, type = "posteriors", pdb)
  po <- read_info_json(x, "posteriors", pdb)
  pdb(po) <- pdb
  class(po) <- "pdb_posterior"
  po$model_info <- read_model_info(po)
  po$data_info <- read_data_info(po)
  assert_pdb_posterior(po)
  po
}

#' @rdname posterior
#' @export
as.posterior.list <- function(x, pdb = pdb_default(), ...) {
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
    suppressWarnings(otpt <- utils::capture.output(so <- run_stan.pdb_posterior(x, stan_args = list(iter = 2, warmup = 0, chains = 1))))
    stop("posterior dimensions are missing.")
  }
  embedded_fields <- intersect(
    names(x), c("embedded_data", "embedded_model_code", "embedded_reference_draws")
  )
  embedded_content <- x[embedded_fields]
  x <- x[pdb_posterior_must_include()]
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

assert_pdb_posterior <- function(x) {
  checkmate::assert_class(x, "pdb_posterior")
  checkmate::assert_list(x)
  checkmate::assert_names(names(x), must.include = pdb_posterior_must_include())
  checkmate::assert_list(x$dimensions)
  checkmate::assert_named(x$dimensions)
  checkmate::assert_class(x$added_date, "Date")
  checkmate::assert_class(x$data_info$added_date, "Date")
  checkmate::assert_class(x$model_info$added_date, "Date")
  checkmate::assert_list(x$model_info, min.len = 1)

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
    if (!setequal(posterior::variables(x$embedded_reference_draws),
                  bundle_dimension_names(x$dimensions)))
      stop("Embedded reference draws conflict with the posterior's dimensions.", call. = FALSE)
  }
  invisible(x)
}
