#' Infer unconstrained posterior parameter counts from Stan code and data
#'
#' Compile a Stan model and obtain the number of unconstrained coordinates for
#' each parameter (RStan uses a zero-chain fit; CmdStanR uses a short fit).
#' These scalar counts are the values stored
#' in PosteriorDB posterior `dimensions`; they are not the constrained output
#' shapes of the variables.
#'
#' @param model_code Stan source as a string or `pdb_model_code` object.
#' @param data A named list of Stan data or a `pdb_data` object.
#' @param include Optional base parameter names to retain.
#' @param exclude Base parameter names to omit.
#' @param backend Stan backend, either `"rstan"` or `"cmdstanr"`.
#' @param iter Total iterations for the short CmdStanR fit, split between
#'   warmup and sampling. RStan compiles without sampling.
#' @return A named list of positive integer unconstrained parameter counts.
#' @export
infer_posterior_dimensions <- function(
  model_code, data, include = NULL, exclude = NULL,
  backend = c("rstan", "cmdstanr"), iter = 4L
) {
  backend <- match.arg(backend)
  model_code <- as.character(model_code)
  checkmate::assert_string(model_code, min.chars = 1L)
  if (file.exists(model_code)) model_code <- paste(readLines(model_code, warn = FALSE), collapse = "\n")
  if (inherits(data, "pdb_data")) data <- unclass(data)
  validate_unconstrained_selection(include, exclude)
  checkmate::assert_list(data)
  if (length(data) && (is.null(names(data)) || anyNA(names(data)) || any(!nzchar(names(data))) || anyDuplicated(names(data))))
    stop("`data` must be a fully named list with unique, non-empty names.", call. = FALSE)
  checkmate::assert_integerish(iter, len = 1L, lower = 4L)

  if (identical(backend, "rstan")) {
    if (!requireNamespace("rstan", quietly = TRUE)) stop("The `rstan` package is required for this backend.", call. = FALSE)
    fit <- suppressWarnings(rstan::stan(
      model_code = model_code, data = data, chains = 0L, refresh = 0L
    ))
  } else {
    if (!requireNamespace("cmdstanr", quietly = TRUE)) stop("The `cmdstanr` package is required for this backend.", call. = FALSE)
    model <- cmdstanr::cmdstan_model(cmdstanr::write_stan_file(model_code), compile = TRUE, quiet = TRUE)
    fit <- suppressWarnings(model$sample(
      data = data, chains = 1L, iter_warmup = as.integer(floor(iter / 2)),
      iter_sampling = as.integer(iter - floor(iter / 2)), refresh = 0L
    ))
  }
  infer_unconstrained_parameter_counts_from_fit(fit, include, exclude)
}

#' Infer unconstrained parameter counts from a fitted Stan model
#'
#' @param fit An `rstan::stanfit` or `cmdstanr::CmdStanMCMC` object.
#' @param include Optional base parameter names to retain.
#' @param exclude Base parameter names to omit.
#' @return A named list of positive integer unconstrained parameter counts.
#' @export
infer_unconstrained_parameter_counts_from_fit <- function(fit, include = NULL, exclude = NULL) {
  validate_unconstrained_selection(include, exclude)
  if (inherits(fit, "stanfit")) {
    instance <- tryCatch(fit@.MISC$stan_fit_instance, error = function(e) NULL)
    if (is.null(instance)) stop("The `stanfit` does not expose its compiled model instance and unconstrained parameter names.", call. = FALSE)
    unconstrained_names <- tryCatch(instance$unconstrained_param_names(TRUE, TRUE), error = function(e) NULL)
    expected <- tryCatch(rstan::get_num_upars(fit), error = function(e) NA_integer_)
    if (is.null(unconstrained_names) || !length(unconstrained_names) || length(unconstrained_names) != expected)
      stop("RStan did not return a complete, consistent set of unconstrained parameter names.", call. = FALSE)
  } else if (inherits(fit, "CmdStanMCMC")) {
    if (!requireNamespace("posterior", quietly = TRUE)) stop("The `posterior` package is required.", call. = FALSE)
    unconstrained <- tryCatch(fit$unconstrain_draws(), error = function(e) {
      stop("CmdStanR could not obtain unconstrained draws from this fit: ", conditionMessage(e), call. = FALSE)
    })
    unconstrained_names <- posterior::variables(unconstrained)
    if (!length(unconstrained_names)) stop("CmdStanR returned no unconstrained parameter names.", call. = FALSE)
  } else {
    stop("`fit` must be an `rstan::stanfit` or `cmdstanr::CmdStanMCMC` object.", call. = FALSE)
  }
  unconstrained_parameter_counts(unconstrained_names, include, exclude)
}

validate_unconstrained_selection <- function(include, exclude) {
  checkmate::assert_character(include, null.ok = TRUE, min.chars = 1L, unique = TRUE)
  checkmate::assert_character(exclude, null.ok = TRUE, min.chars = 1L, unique = TRUE)
  if (length(intersect(include, exclude))) stop("A parameter cannot appear in both `include` and `exclude`.", call. = FALSE)
  if ("lp__" %in% include) stop("`lp__` is an internal Stan variable and cannot be included.", call. = FALSE)
  invisible(TRUE)
}

unconstrained_parameter_counts <- function(unconstrained_names, include = NULL, exclude = NULL) {
  if (!length(unconstrained_names)) stop("No unconstrained parameter names were returned for this fit.", call. = FALSE)
  unconstrained_names <- setdiff(unconstrained_names, "lp__")
  bases <- sub("\\[.*$", "", unconstrained_names)
  bases <- sub("\\.[0-9].*$", "", bases)
  counts <- as.list(table(factor(bases, levels = unique(bases))))
  counts <- lapply(counts, as.integer)
  available <- names(counts)
  if (!is.null(include)) {
    missing <- setdiff(include, available)
    if (length(missing)) stop("Included parameter(s) were not found among unconstrained parameters: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!is.null(exclude)) {
    missing <- setdiff(exclude, c(available, "lp__"))
    if (length(missing)) stop("Excluded parameter(s) were not found among unconstrained parameters: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  selected <- setdiff(if (is.null(include)) available else include, exclude %||% character())
  if (!length(selected)) stop("Parameter selection produced no unconstrained parameters.", call. = FALSE)
  counts[selected]
}

validate_posterior_dimension_counts <- function(dimensions) {
  if (is.atomic(dimensions) && !is.null(names(dimensions))) dimensions <- as.list(dimensions)
  checkmate::assert_list(dimensions, min.len = 1L)
  checkmate::assert_named(dimensions)
  checkmate::assert_character(names(dimensions), min.chars = 1L, unique = TRUE)
  for (nm in names(dimensions)) {
    count <- dimensions[[nm]]
    if (length(count) != 1L || !is.numeric(count) || is.na(count) || !is.finite(count) || count < 1 || count != floor(count))
      stop("Posterior dimension for `", nm, "` must be one positive integer unconstrained-parameter count.", call. = FALSE)
  }
  dimensions
}
