#' Information attached to an object
#'
#' Objects read from a database carry their metadata record in an `info`
#' attribute: model code carries its model info, data its data info, and
#' reference posteriors their reference posterior info.
#'
#' @param x An object read from or written to a database.
#' @param value The new info object.
#' @return The info object.
#' @export
info <- function(x) attr(x, "info")

#' @rdname info
#' @export
`info<-` <- function(x, value) {
  attr(x, "info") <- value
  x
}

#' Reference posterior information
#'
#' The record that describes how a reference posterior was computed: the
#' inference method and its arguments, diagnostics, the checks it passed,
#' and software versions.
#'
#' @param x A posterior, a posterior name, or (for
#'   `as.reference_posterior_info()`) a named list.
#' @param type `"draws"`, `"mean_value"` or `"mean_squared_value"`.
#' @param pdb A [pdb][pdb_local] connection, used when `x` is a name.
#' @param ... Not used.
#' @return A `pdb_reference_posterior_info` object.
#' @export
reference_posterior_info <- function(x, ...) UseMethod("reference_posterior_info")

#' @rdname reference_posterior_info
#' @export
reference_posterior_info.pdb_posterior <- function(x, type = "draws", ...) {
  if (type == "draws" && !is.null(x$embedded$reference_draws)) {
    return(info(x$embedded$reference_draws))
  }
  read_reference_info(reference_name(x), type, posterior_pdb(x))
}

#' @rdname reference_posterior_info
#' @export
reference_posterior_info.character <- function(x, type = "draws", pdb = pdb_default(), ...) {
  reference_posterior_info(posterior(x, pdb = pdb), type = type)
}

#' @rdname reference_posterior_info
#' @export
reference_posterior_draws_info <- function(x, ...) reference_posterior_info(x, type = "draws", ...)

#' @rdname reference_posterior_info
#' @export
pdb_reference_posterior_info <- reference_posterior_info

#' @rdname reference_posterior_info
#' @export
pdb_reference_posterior_draws_info <- reference_posterior_draws_info

#' @rdname reference_posterior_info
#' @export
as.reference_posterior_info <- function(x, ...) UseMethod("as.reference_posterior_info")

#' @rdname reference_posterior_info
#' @export
as.pdb_reference_posterior_info <- as.reference_posterior_info

#' @export
as.reference_posterior_info.pdb_reference_posterior_info <- function(x, ...) x

#' @rdname reference_posterior_info
#' @export
as.reference_posterior_info.list <- function(x, ...) {
  x <- normalize_info(x)
  x$added_by <- x$added_by %||% unname(Sys.info()[["user"]])
  x$added_date <- as.Date(x$added_date %||% Sys.Date())
  fields <- c("name", "inference", "diagnostics", "checks_made", "comments",
              "added_by", "added_date", "versions")
  unknown <- setdiff(names(x), fields)
  if (length(unknown)) stop2("Unknown reference posterior info field(s): ", paste(unknown, collapse = ", "))
  for (f in setdiff(fields, names(x))) x[f] <- list(NULL)
  x <- structure(x[fields], class = "pdb_reference_posterior_info")
  assert_name(x$name, "reference posterior name")
  checkmate::assert_choice(x$inference$method, c("stan_sampling", "analytical"),
                           .var.name = "inference$method")
  checkmate::assert_list(x$inference$method_arguments, null.ok = TRUE,
                         .var.name = "inference$method_arguments")
  checkmate::assert_string(x$added_by, .var.name = "added_by")
  x
}

read_reference_info <- function(name, type, pdb) {
  path <- file.path("reference_posteriors", reference_type_dir(type), "info",
                    paste0(name, ".info.json"))
  as.reference_posterior_info(pdb_read_json(pdb, path))
}

reference_name <- function(x) {
  x$reference_posterior_name %||%
    stop2("Posterior '", x$name, "' has no reference posterior.")
}

#' @export
print.pdb_reference_posterior_info <- function(x, ...) {
  cat0("Posterior: ", x$name, "\n")
  cat0("Method: ", x$inference$method, "\n")
  args <- x$inference$method_arguments
  if (length(args)) {
    cat0("Arguments:\n")
    utils::str(args, no.list = TRUE, give.head = FALSE, comp.str = "  ")
  }
  invisible(x)
}

#' Reference posterior draws
#'
#' `reference_posterior_draws()` reads the reference draws of a posterior.
#' They are a [posterior::draws_list] with one element per chain, and the
#' reference posterior info in the `info` attribute, so all functions from
#' the posterior package work on them.
#'
#' `as.reference_posterior_draws()` wraps draws you already have (anything
#' [posterior::as_draws_list()] accepts) with a reference posterior info.
#' `lp__` is dropped. Use [check_reference_posterior_draws()] before writing
#' them, and [as_reference_posterior_draws()] to convert a Stan fit.
#'
#' @param x A posterior, posterior name or reference posterior info; for
#'   `as.reference_posterior_draws()`, draws.
#' @param info A reference posterior info, or a list for
#'   [as.reference_posterior_info()].
#' @param pdb A [pdb][pdb_local] connection.
#' @param ... Not used.
#' @return A `pdb_reference_posterior_draws` object.
#' @export
reference_posterior_draws <- function(x, ...) UseMethod("reference_posterior_draws")

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws.pdb_posterior <- function(x, ...) {
  x$embedded$reference_draws %||% read_reference_draws(reference_name(x), posterior_pdb(x))
}

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws.character <- function(x, pdb = pdb_default(), ...) {
  reference_posterior_draws(posterior(x, pdb = pdb))
}

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws.pdb_reference_posterior_info <- function(x, pdb = pdb_default(), ...) {
  read_reference_draws(x$name, pdb)
}

#' @rdname reference_posterior_draws
#' @export
pdb_reference_posterior_draws <- reference_posterior_draws

#' @rdname reference_posterior_draws
#' @export
as.reference_posterior_draws <- function(x, info, pdb = NULL, ...) {
  draws <- posterior::as_draws_list(x)
  draws <- posterior::subset_draws(draws, variable = setdiff(posterior::variables(draws), "lp__"))
  draws <- unclass(draws)
  names(draws) <- NULL
  out <- structure(draws, class = c("pdb_reference_posterior_draws", "draws_list", "draws", "list"),
                   info = as.reference_posterior_info(info))
  pdb(out) <- pdb
  out
}

#' @rdname reference_posterior_draws
#' @export
as.pdb_reference_posterior_draws <- as.reference_posterior_draws

read_reference_draws <- function(name, pdb) {
  path <- file.path("reference_posteriors", "draws", "draws", paste0(name, ".json"))
  chains <- pdb_read_json(pdb, path, zip = TRUE, simplify = FALSE)
  chains <- lapply(chains, function(chain) lapply(chain, function(v) as.numeric(unlist(v))))
  as.reference_posterior_draws(chains, info = read_reference_info(name, "draws", pdb), pdb = pdb)
}

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws_file_path <- function(x, ...) {
  UseMethod("reference_posterior_draws_file_path")
}

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws_file_path.pdb_posterior <- function(x, ...) {
  reference_posterior_draws_file_path(reference_name(x), pdb = posterior_pdb(x))
}

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws_file_path.pdb_reference_posterior_info <- function(x, pdb = pdb_default(), ...) {
  reference_posterior_draws_file_path(x$name, pdb = pdb)
}

#' @rdname reference_posterior_draws
#' @export
reference_posterior_draws_file_path.character <- function(x, pdb = pdb_default(), ...) {
  assert_name(x, "reference posterior name")
  pdb_file(pdb, file.path("reference_posteriors", "draws", "draws", paste0(x, ".json")), zip = TRUE)
}

# Re-wrap a plain draws_list after a posterior-package operation.
rewrap_draws <- function(draws, template, new_info) {
  out <- as.reference_posterior_draws(draws, info = new_info, pdb = pdb(template))
  attr(out, "sampler_diagnostics") <- attr(template, "sampler_diagnostics")
  out
}

strip_reference_class <- function(x) {
  class(x) <- setdiff(class(x), "pdb_reference_posterior_draws")
  x
}

# Changing the draws invalidates the recorded checks.
unchecked_info <- function(x) {
  out <- info(x)
  out["checks_made"] <- list(NULL)
  out
}

#' Subset or thin reference posterior draws
#'
#' These methods keep the result a `pdb_reference_posterior_draws` object.
#' Any recorded checks are cleared, because they no longer describe the
#' draws; run [check_reference_posterior_draws()] again before writing.
#'
#' @param x A `pdb_reference_posterior_draws` object.
#' @param variable Variable names to keep.
#' @param thin Keep every `thin`-th draw of each chain.
#' @param ... Passed on to the posterior package.
#' @return A `pdb_reference_posterior_draws` object.
#' @export
subset.pdb_reference_posterior_draws <- function(x, variable = NULL, ...) {
  out <- posterior::subset_draws(strip_reference_class(x), variable = variable, ...)
  rewrap_draws(out, x, unchecked_info(x))
}

#' @rdname subset.pdb_reference_posterior_draws
#' @exportS3Method posterior::thin_draws
thin_draws.pdb_reference_posterior_draws <- function(x, thin, ...) {
  out <- posterior::thin_draws(strip_reference_class(x), thin = thin, ...)
  rewrap_draws(out, x, unchecked_info(x))
}

#' @export
print.pdb_reference_posterior_draws <- function(x, ...) {
  cat0("Reference posterior: ", info(x)$name, "\n")
  print(strip_reference_class(x), ...)
  invisible(x)
}

#' @export
summary.pdb_reference_posterior_draws <- function(object, ...) {
  posterior::summarise_draws(strip_reference_class(object), ...)
}

#' Reference posterior summary statistics
#'
#' Summary statistics are stored separately from the draws: `mean_value` (the
#' posterior mean of each variable) and `mean_squared_value` (the mean of its
#' square), each with its Monte Carlo standard error. They are computed from
#' checked reference draws with
#' [compute_reference_posterior_summary_statistic()].
#'
#' @param x A posterior or posterior name.
#' @param type `"mean_value"` or `"mean_squared_value"`.
#' @param pdb A [pdb][pdb_local] connection, used when `x` is a name.
#' @param ... Not used.
#' @return `reference_posterior_summary_statistic()` returns a
#'   `pdb_reference_posterior_summary_statistic` object: a list with `names`,
#'   the statistic and `mcse_mean`, with its info attached.
#'   `reference_posterior_summary_statistics()` returns a named list of the
#'   statistics that exist for the posterior.
#' @export
reference_posterior_summary_statistic <- function(x, type, ...) {
  UseMethod("reference_posterior_summary_statistic")
}

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistic.pdb_posterior <- function(x, type, ...) {
  read_summary_statistic(reference_name(x), type, posterior_pdb(x))
}

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistic.character <- function(x, type, pdb = pdb_default(), ...) {
  reference_posterior_summary_statistic(posterior(x, pdb = pdb), type)
}

#' @rdname reference_posterior_summary_statistic
#' @export
pdb_reference_posterior_summary_statistic <- reference_posterior_summary_statistic

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistics <- function(x, ...) {
  if (is.character(x)) x <- posterior(x, ...)
  if (is.null(x$reference_posterior_name)) return(list())
  pdb <- posterior_pdb(x)
  types <- Filter(function(type) {
    x$reference_posterior_name %in% reference_posterior_names(pdb, type)
  }, summary_statistic_types())
  stats::setNames(lapply(types, read_summary_statistic, name = x$reference_posterior_name, pdb = pdb),
                  types)
}

#' @rdname reference_posterior_summary_statistic
#' @export
pdb_reference_posterior_summary_statistics <- reference_posterior_summary_statistics

read_summary_statistic <- function(name, type, pdb) {
  checkmate::assert_choice(type, summary_statistic_types())
  path <- file.path("reference_posteriors", "summary_statistics", type, type, paste0(name, ".json"))
  new_summary_statistic(pdb_read_json(pdb, path), type, read_reference_info(name, type, pdb), pdb)
}

new_summary_statistic <- function(x, type, info, pdb = NULL) {
  x <- as.list(x)
  checkmate::assert_character(x$names, any.missing = FALSE, unique = TRUE, .var.name = "names")
  for (field in c(type, "mcse_mean")) {
    checkmate::assert_numeric(x[[field]], len = length(x$names), .var.name = field)
  }
  out <- structure(x, class = c(paste0("pdb_summary_statistic_", type),
                                "pdb_reference_posterior_summary_statistic", "list"),
                   info = as.reference_posterior_info(info), type = type)
  pdb(out) <- pdb
  out
}

#' @export
print.pdb_reference_posterior_summary_statistic <- function(x, ...) {
  cat0("Reference posterior: ", info(x)$name, " (", attr(x, "type"), ")\n")
  print(as.data.frame(plain_list(x), stringsAsFactors = FALSE), row.names = FALSE)
  invisible(x)
}
