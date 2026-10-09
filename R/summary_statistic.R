supported_summary_statistic_types <- function() {
  c("mean_value", "mean_squared_value")
}

summary_statistic_class_name <- function(type) {
  checkmate::assert_subset(type, supported_summary_statistic_types())
  paste0("pdb_summary_statistic_", type)
}

supported_summary_statistic_classes <- function() {
  summary_statistic_class_name(supported_summary_statistic_types())
}


#' Extract the type of summary statistic
#'
#' @param x a [pdb_reference_posterior_summary_statistic]
#'
summary_statistic_type <- function(x) {
  checkmate::assert_class(x, "pdb_reference_posterior_summary_statistic")
  sst <- supported_summary_statistic_types()
  bool <- summary_statistic_class_name(sst) %in% class(x)
  checkmate::assert_true(sum(bool) == 1L)
  sst[bool]
}


#' @export
print.pdb_reference_posterior_summary_statistic <- function(x, ...) {
  cat(paste0("Posterior: ", info(x)$name, "\n\n"))
  attr(x, "info") <- NULL
  attr(x, "pdb") <- NULL
  x <- unclass(x)
  print(x)
}


assert_reference_posterior_summary_statistic <- function(x) {
  checkmate::assert_class(x, c("pdb_reference_posterior_summary_statistic"))
  sst <- summary_statistic_type(x)
  value_name <- sst
  mcse_name <- "mcse_mean"
  checkmate::assert_names(
    names(x),
    type = "unique",
    must.include = c("names", value_name, mcse_name)
  )

  checkmate::assert_character(x[["names"]], unique = TRUE, any.missing = FALSE)
  count <- length(x[["names"]])
  checkmate::assert_numeric(x[[value_name]], len = count)
  checkmate::assert_numeric(x[[mcse_name]], len = count)
  for (field in setdiff(names(x), c("names", value_name, mcse_name))) {
    checkmate::assert_numeric(x[[field]])
  }
  assert_reference_posterior_info(info(x))
}


#' Reference posterior summary statistics
#'
#' @param x a [posterior] object or a posterior name.
#' @param pdb a [pdb] object (if [x] is a posterior name)
#' @param info a [pdb_reference_posterior_info] object
#' @param type the type of summary statistic to extract
#' @param ... further arguments supplied to specific methods.
#' @return A [pdb_reference_posterior_summary_statistic] object for singular
#'   access; a named list of available types for plural access.
#' @details Summaries are looked up through the posterior's
#'   `reference_posterior_name`, which may differ from the posterior's own
#'   name. `reference_posterior_summary_statistics()` returns the types that
#'   are stored, and an empty list when the posterior has no reference
#'   posterior. A summary that is listed but cannot be read is an error.
#' @export
reference_posterior_summary_statistic <- function(x, ...) {
  UseMethod("reference_posterior_summary_statistic")
}

#' @rdname reference_posterior_summary_statistic
#' @export
pdb_reference_posterior_summary_statistic <- reference_posterior_summary_statistic

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistic.character <- function(
  x,
  pdb = pdb_default(),
  type,
  ...
) {
  reference_posterior_summary_statistic(posterior(x, pdb = pdb), type)
}

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistic.pdb_posterior <- function(x, type, ...) {
  read_reference_posterior_summary_statistic(
    x = x$reference_posterior_name,
    pdb = pdb(x),
    type = type
  )
}

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistic.pdb_reference_posterior_info <- function(
  x,
  pdb = pdb_default(),
  type,
  ...
) {
  read_reference_posterior_summary_statistic(x = x$name, pdb = pdb, type = type)
}

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistic.list <- function(x, info, type, ...) {
  checkmate::assert_class(info, "pdb_reference_posterior_info")
  checkmate::assert_choice(type, supported_summary_statistic_types())
  attr(x, "info") <- info
  class(x) <- c(
    summary_statistic_class_name(type),
    "pdb_reference_posterior_summary_statistic",
    "list"
  )
  assert_reference_posterior_summary_statistic(x)
  x
}


#' Read reference_posterior_summary_statistic json object
#' @param x a reference-posterior name
#' @param pdb a posterior db object to access the info json from
#' @param ... further arguments. Currently not used.
#' @noRd
#' @keywords internal
read_reference_posterior_summary_statistic <- function(x, pdb, type, ...) {
  checkmate::assert_string(x, null.ok = TRUE)
  checkmate::assert_choice(type, supported_summary_statistic_types())

  if (is.null(x)) {
    stop(
      "There is currently no reference posterior for this posterior.",
      call. = FALSE
    )
  }
  checkmate::assert_class(pdb, classes = "pdb")

  rpssfp <- pdb_cached_local_file_path(
    pdb,
    file.path(
      "reference_posteriors",
      "summary_statistics",
      type,
      type,
      paste0(x, ".json")
    ),
    unzip = FALSE
  )
  rpssd <- jsonlite::read_json(rpssfp, simplifyVector = TRUE)

  rpssi <- read_reference_posterior_info(x = x, type = type, pdb = pdb)
  rpss <- reference_posterior_summary_statistic(rpssd, rpssi, type)

  assert_reference_posterior_summary_statistic(rpss)
  rpss
}


#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistics <- function(x, ...) {
  UseMethod("reference_posterior_summary_statistics")
}

#' @rdname reference_posterior_summary_statistic
#' @export
pdb_reference_posterior_summary_statistics <- reference_posterior_summary_statistics

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistics.character <- function(
  x,
  pdb = pdb_default(),
  ...
) {
  reference_posterior_summary_statistics(x = posterior(x, pdb = pdb))
}

#' @rdname reference_posterior_summary_statistic
#' @export
reference_posterior_summary_statistics.pdb_posterior <- function(x, ...) {
  reference <- x$reference_posterior_name
  checkmate::assert_string(reference, null.ok = TRUE)
  ss_list <- list()
  if (is.null(reference)) {
    return(ss_list)
  }
  connection <- pdb(x)
  for (type in supported_summary_statistic_types()) {
    if (!reference %in% reference_posterior_names(connection, type = type)) {
      next
    }
    ss_list[[type]] <- read_reference_posterior_summary_statistic(
      x = reference,
      pdb = connection,
      type = type
    )
  }
  ss_list
}
