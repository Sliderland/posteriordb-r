#' @rdname model_info
#' @export
data_info <- function(x, ...) UseMethod("data_info")

#' @rdname model_info
#' @export
data_info.pdb_posterior <- function(x, ...) x$data_info

#' @rdname model_info
#' @export
data_info.pdb_data <- function(x, ...) info(x)

#' @rdname model_info
#' @export
data_info.character <- function(x, pdb = pdb_default(), ...) {
  assert_name(x, "data name")
  di <- as.data_info(pdb_read_json(pdb, file.path("data", "info", paste0(x, ".info.json"))))
  pdb(di) <- pdb
  di
}

#' @rdname model_info
#' @export
pdb_data_info <- data_info

#' @rdname model_info
#' @export
as.data_info <- function(x, ...) UseMethod("as.data_info")

#' @rdname model_info
#' @export
as.pdb_data_info <- as.data_info

#' @export
as.data_info.pdb_data_info <- function(x, ...) x

#' @rdname model_info
#' @export
as.data_info.list <- function(x, ...) {
  x <- normalize_info(x)
  x$data_file <- x$data_file %||% default_data_path(x$name)
  x$added_by <- x$added_by %||% unname(Sys.info()[["user"]])
  x$added_date <- x$added_date %||% Sys.Date()
  x <- structure(x, class = "pdb_data_info")
  assert_data_info(x)
  x
}

default_data_path <- function(name) paste0("data/data/", name, ".json")

assert_data_info <- function(x) {
  assert_name(x$name, "data name")
  checkmate::assert_string(x$title, .var.name = "title")
  if (!identical(x$data_file, default_data_path(x$name))) {
    stop2("`data_file` must be '", default_data_path(x$name), "'.")
  }
  assert_common_info(x)
}

#' @export
print.pdb_data_info <- function(x, ...) {
  cat0("Data: ", x$name, "\n", x$title, "\n")
  invisible(x)
}

#' Data of a posterior
#'
#' `get_data()` (also `pdb_data()` and `stan_data()`) returns the data used by
#' a posterior as a named list. `data_file_path()` returns a local path to the
#' extracted JSON file. `as.pdb_data()` wraps a named list with its data
#' info, for example before writing a new data set.
#'
#' @param x A posterior, a data name, a `pdb_data_info` object, or (for
#'   `as.pdb_data()`) a named list.
#' @param pdb A [pdb][pdb_local] connection, used when `x` is a name or info.
#' @param info A `pdb_data_info` object or a list for [as.data_info()].
#' @param ... Not used.
#' @return A `pdb_data` object: a named list with `info` and `pdb`
#'   attributes. File-path functions return a string.
#' @export
get_data <- function(x, ...) UseMethod("get_data")

#' @rdname get_data
#' @export
get_data.pdb_posterior <- function(x, ...) {
  x$embedded$data %||% get_data(x$data_info, pdb = posterior_pdb(x))
}

#' @rdname get_data
#' @export
get_data.character <- function(x, pdb = pdb_default(), ...) {
  get_data(data_info(x, pdb = pdb), pdb = pdb)
}

#' @rdname get_data
#' @export
get_data.pdb_data_info <- function(x, pdb = pdb_default(), ...) {
  out <- as.pdb_data(read_json_file(data_file_path(x, pdb = pdb)), info = x)
  pdb(out) <- pdb
  out
}

#' @rdname get_data
#' @export
pdb_data <- get_data

#' @rdname get_data
#' @export
stan_data <- function(x, ...) get_data(x, ...)

#' @rdname get_data
#' @export
data_file_path <- function(x, ...) UseMethod("data_file_path")

#' @rdname get_data
#' @export
data_file_path.pdb_posterior <- function(x, ...) {
  data_file_path(x$data_info, pdb = posterior_pdb(x))
}

#' @rdname get_data
#' @export
data_file_path.character <- function(x, pdb = pdb_default(), ...) {
  data_file_path(data_info(x, pdb = pdb), pdb = pdb)
}

#' @rdname get_data
#' @export
data_file_path.pdb_data_info <- function(x, pdb = pdb_default(), ...) {
  pdb_file(pdb, x$data_file, zip = TRUE)
}

#' @rdname get_data
#' @export
stan_data_file_path <- function(x, ...) data_file_path(x, ...)

#' @rdname get_data
#' @export
as.pdb_data <- function(x, info, ...) {
  checkmate::assert_list(x, names = "unique")
  structure(unclass(x), class = c("pdb_data", "list"), info = as.data_info(info))
}

#' @export
print.pdb_data <- function(x, ...) {
  print(plain_list(x))
  invisible(x)
}
