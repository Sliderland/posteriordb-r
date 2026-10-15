#' Names of the content in a posterior database
#'
#' `posterior_names()` lists posteriors. Given a data, model or model-info
#' object, it lists the posteriors that use that data or model; given a
#' posterior (or a list of them), it returns their names.
#' `reference_posterior_names()` lists stored reference posteriors of one
#' `type`. `alias_names()` lists the posterior aliases.
#'
#' @param x A [pdb][pdb_local] connection or an object read from one.
#' @param pdb A [pdb][pdb_local] connection.
#' @param type For `reference_posterior_names()`, one of `"draws"`,
#'   `"mean_value"` or `"mean_squared_value"`. For `alias_names()`, only
#'   `"posteriors"`.
#' @param ... Not used.
#' @return A character vector (a list of them for a list input).
#' @export
posterior_names <- function(x = pdb_default(), ...) UseMethod("posterior_names")

#' @rdname posterior_names
#' @export
posterior_name <- posterior_names

#' @export
posterior_names.pdb <- function(x, ...) pdb_names(x, "posteriors", ".json")

#' @export
posterior_names.pdb_posterior <- function(x, ...) x$name

#' @export
posterior_names.list <- function(x, ...) lapply(x, posterior_names)

#' @export
posterior_names.pdb_data <- function(x, ...) linked_posteriors(pdb(x), "data_name", info(x)$name)

#' @export
posterior_names.pdb_data_info <- function(x, ...) linked_posteriors(pdb(x), "data_name", x$name)

#' @export
posterior_names.pdb_model_code <- function(x, ...) linked_posteriors(pdb(x), "model_name", info(x)$name)

#' @export
posterior_names.pdb_model_info <- function(x, ...) linked_posteriors(pdb(x), "model_name", x$name)

linked_posteriors <- function(pdb, field, value) {
  if (is.null(pdb)) stop2("The object has no database connection.")
  records <- read_all_posterior_records(pdb)
  names(records)[vapply(records, function(r) identical(r[[field]], value), logical(1))]
}

read_all_posterior_records <- function(pdb) {
  pns <- posterior_names(pdb)
  stats::setNames(lapply(pns, read_posterior_record, pdb = pdb), pns)
}

#' @rdname posterior_names
#' @export
model_names <- function(pdb = pdb_default(), ...) pdb_names(pdb, "models/info", ".info.json")

#' @rdname posterior_names
#' @export
data_names <- function(pdb = pdb_default(), ...) pdb_names(pdb, "data/info", ".info.json")

#' @rdname posterior_names
#' @export
reference_posterior_names <- function(pdb = pdb_default(), type = "draws", ...) {
  pdb_names(pdb, file.path("reference_posteriors", reference_type_dir(type), "info"), ".info.json")
}

#' @rdname posterior_names
#' @export
alias_names <- function(type = "posteriors", pdb = pdb_default()) {
  names(pdb_aliases(pdb, type))
}

pdb_aliases <- function(pdb, type = "posteriors") {
  checkmate::assert_choice(type, "posteriors")
  path <- file.path("alias", paste0(type, ".json"))
  # Alias files are optional in local test databases; GitHub reads it directly.
  if (inherits(pdb, "pdb_local") && !file.exists(file.path(pdb$path, path))) return(list())
  as.list(pdb_read_json(pdb, path))
}

resolve_alias <- function(x, pdb) pdb_aliases(pdb)[[x]] %||% x
