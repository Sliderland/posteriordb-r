#' Posteriors
#'
#' A posterior is a model paired with a data set. `posterior()` reads one
#' from a database by name or alias. `as.posterior()` builds one in memory,
#' for example to write a new posterior with [write_pdb()].
#'
#' A posterior object is a list with the fields of its JSON record (`name`,
#' `model_name`, `data_name`, `reference_posterior_name`, `dimensions`,
#' `keywords`, `added_by`, `added_date`, ...) plus the `model_info` and
#' `data_info` it links to. `dimensions` holds the number of unconstrained
#' parameters for each parameter (a `simplex[K]` counts `K - 1`). A few older
#' records store a shape such as `[3, 2]` instead; its product is the count.
#'
#' `as.posterior()` takes a named list. Either give `model_name` and
#' `data_name` (their info is read from `pdb`), or give `pdb_model_code` and
#' `pdb_data` objects; these are kept inside the posterior so its getters work
#' without a database, and `name` defaults to `"<data>-<model>"`. If
#' `dimensions` is missing it is inferred from the Stan code and data, which
#' compiles the model with rstan.
#'
#' @param x A posterior name or alias for `posterior()`; a named list for
#'   `as.posterior()`.
#' @param pdb A [pdb][pdb_local] connection. May be `NULL` for
#'   `as.posterior()` when model code and data are supplied.
#' @param ... Not used.
#' @return A `pdb_posterior` object.
#' @examples
#' \dontrun{
#' po <- posterior("eight_schools-eight_schools_centered", pdb_local())
#' stan_code(po)
#' get_data(po)
#' }
#' @export
posterior <- function(x, pdb = pdb_default(), ...) UseMethod("posterior")

#' @rdname posterior
#' @export
posterior.character <- function(x, pdb = pdb_default(), ...) {
  checkmate::assert_string(x)
  checkmate::assert_class(pdb, "pdb")
  po <- read_posterior_record(resolve_alias(x, pdb), pdb)
  po$model_info <- model_info(po$model_name, pdb = pdb)
  po$data_info <- data_info(po$data_name, pdb = pdb)
  new_posterior(po, pdb)
}

#' @rdname posterior
#' @export
pdb_posterior <- posterior

#' @rdname posterior
#' @export
as.posterior <- function(x, pdb = NULL, ...) UseMethod("as.posterior")

#' @rdname posterior
#' @export
as.pdb_posterior <- as.posterior

#' @rdname posterior
#' @export
as.posterior.list <- function(x, pdb = NULL, ...) {
  embedded <- list(model_code = x$pdb_model_code, data = x$pdb_data)
  x$pdb_model_code <- NULL
  x$pdb_data <- NULL
  if (!is.null(embedded$model_code)) {
    checkmate::assert_class(embedded$model_code, "pdb_model_code")
    x$model_info <- info(embedded$model_code)
  }
  if (!is.null(embedded$data)) {
    checkmate::assert_class(embedded$data, "pdb_data")
    x$data_info <- info(embedded$data)
  }
  x$model_name <- x$model_name %||% x$model_info$name
  x$data_name <- x$data_name %||% x$data_info$name
  if (is.null(x$model_name) || is.null(x$data_name)) {
    stop2("Give `model_name` and `data_name`, or `pdb_model_code` and `pdb_data`.")
  }
  x$name <- x$name %||% paste0(x$data_name, "-", x$model_name)
  if (is.null(x$model_info) || is.null(x$data_info)) {
    if (is.null(pdb)) stop2("A connection is needed to read the model and data info.")
    x$model_info <- x$model_info %||% model_info(x$model_name, pdb = pdb)
    x$data_info <- x$data_info %||% data_info(x$data_name, pdb = pdb)
  }
  if (is.null(x$dimensions)) {
    code <- embedded$model_code %||% (if (!is.null(pdb)) model_code(x$model_name, "stan", pdb = pdb))
    data <- embedded$data %||% (if (!is.null(pdb)) get_data(x$data_name, pdb = pdb))
    if (is.null(code) || is.null(data)) stop2("`dimensions` is missing and cannot be inferred.")
    x$dimensions <- infer_posterior_dimensions(code, data)
  }
  x$added_by <- x$added_by %||% unname(Sys.info()[["user"]])
  x$added_date <- as.Date(x$added_date %||% Sys.Date())
  if (!"reference_posterior_name" %in% names(x)) x["reference_posterior_name"] <- list(NULL)
  embedded <- embedded[!vapply(embedded, is.null, logical(1))]
  if (length(embedded)) x$embedded <- embedded
  new_posterior(x, pdb)
}

read_posterior_record <- function(name, pdb) {
  assert_name(name, "posterior name")
  po <- pdb_read_json(pdb, file.path("posteriors", paste0(name, ".json")))
  po <- normalize_info(po)
  if (!"reference_posterior_name" %in% names(po)) po["reference_posterior_name"] <- list(NULL)
  po
}

new_posterior <- function(x, pdb) {
  x$model_info <- as.model_info(x$model_info)
  x$data_info <- as.data_info(x$data_info)
  x$dimensions <- as.list(x$dimensions)
  x <- structure(x, class = "pdb_posterior")
  pdb(x) <- pdb
  assert_posterior(x)
  x
}

assert_posterior <- function(x) {
  for (field in c("name", "model_name", "data_name")) assert_name(x[[field]], field)
  if (!is.null(x$reference_posterior_name)) {
    assert_name(x$reference_posterior_name, "reference_posterior_name")
  }
  if (!identical(x$model_info$name, x$model_name)) stop2("`model_info` does not match `model_name`.")
  if (!identical(x$data_info$name, x$data_name)) stop2("`data_info` does not match `data_name`.")
  assert_dimensions(x$dimensions)
  checkmate::assert_string(x$added_by)
  checkmate::assert_date(x$added_date, len = 1)
  for (field in c("keywords", "references", "urls")) {
    checkmate::assert_character(x[[field]], null.ok = TRUE, .var.name = field)
  }
  invisible(x)
}

assert_dimensions <- function(x) {
  checkmate::assert_list(x, min.len = 1, names = "unique", .var.name = "dimensions")
  # A few older records store a shape such as [3, 2]; its product is the count.
  ok <- vapply(x, function(d) checkmate::test_integerish(unlist(d), lower = 1, min.len = 1,
                                                         any.missing = FALSE), logical(1))
  if (!all(ok)) {
    stop2("`dimensions` must hold positive integer counts; check: ",
          paste(names(x)[!ok], collapse = ", "))
  }
  invisible(x)
}

#' @export
print.pdb_posterior <- function(x, ...) {
  cat0("Posterior (", x$name, ")\n\n")
  print(x$data_info)
  cat0("\n")
  print(x$model_info)
  invisible(x)
}

#' Posterior metadata as a table
#'
#' `posteriors_tbl_df()` returns one row per posterior and keyword.
#' `filter_posteriors()` filters that table with `dplyr::filter()` syntax and
#' returns the matching posterior objects. `search_posteriors()` searches the
#' keywords of posteriors and of their data and models (case-insensitive,
#' fixed string).
#'
#' @param pdb A [pdb][pdb_local] connection.
#' @param ... For `filter_posteriors()`, conditions passed to
#'   `dplyr::filter()`, such as `data_name == "eight_schools"`.
#' @param query Text to look for.
#' @param fields Where to look: any of `"posterior"`, `"data"` and `"model"`.
#' @param match Whether a posterior must match in `"any"` or `"all"` of
#'   `fields`.
#' @return A tibble for `posteriors_tbl_df()` and `search_posteriors()`; a
#'   list of `pdb_posterior` objects for `filter_posteriors()`.
#' @export
posteriors_tbl_df <- function(pdb = pdb_default()) {
  records <- read_all_posterior_records(pdb)
  rows <- lapply(records, posterior_table_rows)
  tibble::as_tibble(do.call(rbind, rows))
}

posterior_table_rows <- function(x) {
  keywords <- unlist(x$keywords)
  if (!length(keywords)) keywords <- ""
  data.frame(name = x$name, model_name = x$model_name,
             reference_posterior_name = x$reference_posterior_name %||% NA_character_,
             data_name = x$data_name, added_by = x$added_by,
             added_date = as.Date(x$added_date), keywords = keywords,
             stringsAsFactors = FALSE)
}

#' @rdname posteriors_tbl_df
#' @param x A `pdb_posterior`; `as.data.frame()` gives its rows of the table.
#' @param row.names,optional Ignored.
#' @export
as.data.frame.pdb_posterior <- function(x, row.names = NULL, optional = FALSE, ...) {
  posterior_table_rows(x)
}

#' @rdname posteriors_tbl_df
#' @export
filter_posteriors <- function(pdb = pdb_default(), ...) {
  require_package("dplyr", "for filter_posteriors()")
  names <- unique(dplyr::filter(posteriors_tbl_df(pdb), ...)$name)
  lapply(names, posterior, pdb = pdb)
}

#' @rdname posteriors_tbl_df
#' @export
search_posteriors <- function(pdb = pdb_default(), query,
                              fields = c("posterior", "data", "model"),
                              match = c("any", "all")) {
  checkmate::assert_string(query, min.chars = 1)
  checkmate::assert_subset(fields, c("posterior", "data", "model"), empty.ok = FALSE)
  match <- match.arg(match)
  hits_in <- function(keywords) {
    keywords <- unique(as.character(unlist(keywords)))
    keywords[grepl(tolower(query), tolower(keywords), fixed = TRUE)]
  }
  records <- read_all_posterior_records(pdb)
  data_hits <- model_hits <- list()
  if ("data" %in% fields) {
    for (d in unique(vapply(records, `[[`, "", "data_name"))) {
      data_hits[[d]] <- hits_in(data_info(d, pdb = pdb)$keywords)
    }
  }
  if ("model" %in% fields) {
    for (m in unique(vapply(records, `[[`, "", "model_name"))) {
      model_hits[[m]] <- hits_in(model_info(m, pdb = pdb)$keywords)
    }
  }
  rows <- lapply(records, function(r) {
    hits <- list(posterior = hits_in(r$keywords), data = data_hits[[r$data_name]],
                 model = model_hits[[r$model_name]])[fields]
    found <- fields[lengths(hits) > 0]
    if (!length(found) || (match == "all" && length(found) < length(fields))) return(NULL)
    data.frame(posterior_name = r$name, data_name = r$data_name, model_name = r$model_name,
               matched_in = paste(found, collapse = ", "),
               matched_keywords = paste(unique(unlist(hits)), collapse = ", "),
               stringsAsFactors = FALSE)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows)) {
    rows <- data.frame(posterior_name = character(), data_name = character(),
                       model_name = character(), matched_in = character(),
                       matched_keywords = character())
  }
  tibble::as_tibble(rows)
}
