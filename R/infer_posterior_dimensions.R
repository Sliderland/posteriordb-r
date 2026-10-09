#' Infer unconstrained posterior parameter counts from Stan code and data
#'
#' Compiles a Stan model and returns the number of unconstrained parameters
#' for each model parameter. These counts are what a PosteriorDB posterior
#' stores in `dimensions`; they are not the shapes of the saved variables.
#'
#' @param model_code Stan source as a string, a Stan source file path, or a
#'   `pdb_model_code` object.
#' @param data A named list of Stan data or a `pdb_data` object.
#' @param include Names of model parameters to return counts for. The
#'   default `NULL` (or `"all"`) returns every parameter.
#' @param exclude Names of model parameters to leave out. Naming a parameter
#'   in both `include` and `exclude`, using an unknown name, or leaving no
#'   parameters is an error.
#' @param backend Stan backend, either `"rstan"` or `"cmdstanr"`.
#' @param iter Total iterations for the short CmdStanR fit, split between
#'   warmup and sampling. RStan compiles without sampling.
#' @return A named list of positive integer unconstrained parameter counts.
#' @details
#' An unconstrained `matrix[2,3]` counts as six, while a `simplex[3]` counts
#' as two even though three values are saved for it. Transformed parameters
#' and generated quantities have no count. Counts can depend on the data, so
#' supply the data that goes with the model.
#'
#' With `backend = "rstan"` the model is compiled but not sampled. With
#' `backend = "cmdstanr"` a very short fit of `iter` iterations is run to
#' read off the parameter names; its draws are discarded.
#' @seealso [infer_unconstrained_parameter_counts_from_fit()], [create_pdb_bundle()]
#' @md
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
  validate_variable_selections(include, exclude)
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
      iter_sampling = as.integer(iter - floor(iter / 2)), refresh = 0L, sig_figs = 18
    ))
  }
  infer_unconstrained_parameter_counts_from_fit(fit, include, exclude)
}

#' Infer unconstrained parameter counts from a fitted Stan model
#'
#' Obtain the number of unconstrained coordinates for each parameter-block
#' variable directly from a supported fitted object, without resampling.
#' Counts describe independent coordinates rather than constrained output shapes.
#'
#' @param fit An `rstan::stanfit` or `cmdstanr::CmdStanMCMC` object.
#' @inheritParams infer_posterior_dimensions
#' @return A named list of positive integer unconstrained parameter counts.
#' @details
#' Only model parameters are returned, not transformed parameters or
#' generated quantities. A parameter with no free value, such as a
#' `simplex[1]`, has no entry.
#'
#' A `stanfit` that was saved and reloaded in a new R session may have lost
#' its compiled model; in that case use [infer_posterior_dimensions()] with
#' the model code and data instead.
#'
#' For CmdStanR fits, the model and output files must still be available,
#' and the fit should be sampled with `sig_figs = 18`. Values rounded to
#' fewer digits can violate parameter constraints and be rejected.
#' @seealso [infer_posterior_dimensions()], [reconstruct_stan_output()]
#' @md
#' @export
infer_unconstrained_parameter_counts_from_fit <- function(fit, include = NULL, exclude = NULL) {
  validate_variable_selections(include, exclude)
  if (inherits(fit, "stanfit")) {
    instance <- tryCatch(fit@.MISC$stan_fit_instance, error = function(e) NULL)
    if (is.null(instance)) stop("The `stanfit` does not expose its compiled model instance and unconstrained parameter names.", call. = FALSE)
    # These flags include transformed parameters and generated quantities. The
    # PosteriorDB dimensions map describes model parameters, and get_num_upars()
    # counts only their unconstrained coordinates, so request parameters only.
    unconstrained_names <- tryCatch(instance$unconstrained_param_names(FALSE, FALSE), error = function(e) NULL)
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

unconstrained_parameter_counts <- function(unconstrained_names, include = NULL, exclude = NULL) {
  if (!length(unconstrained_names)) stop("No unconstrained parameter names were returned for this fit.", call. = FALSE)
  unconstrained_names <- setdiff(unconstrained_names, "lp__")
  bases <- sub("\\[.*$", "", unconstrained_names)
  bases <- sub("\\.[0-9].*$", "", bases)
  counts <- as.list(table(factor(bases, levels = unique(bases))))
  counts <- lapply(counts, as.integer)
  available <- names(counts)
  selected <- resolve_variable_selection(available, include = include, exclude = exclude)
  if (!length(selected)) stop("Parameter selection produced no unconstrained parameters.", call. = FALSE)
  counts[selected]
}

# Dimension maps agree when names and counts match, whatever the order or type.
same_dimension_counts <- function(x, y) {
  setequal(names(x), names(y)) &&
    identical(as.integer(unlist(x[names(y)])), as.integer(unlist(y)))
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

# Saved parameter-block names are independent of positive free-coordinate counts.
# In particular, simplex[1] has a saved value but no unconstrained coordinate.
fitted_parameter_names <- function(fit) {
  if (inherits(fit, "stanfit")) {
    instance <- rstan_fit_slot(fit, ".MISC")$stan_fit_instance
    if (is.null(instance)) stop("The stanfit has no usable compiled parameter schema.", call. = FALSE)
    scalar_names <- instance$constrained_param_names(FALSE, FALSE)
    checkmate::assert_character(scalar_names, any.missing = FALSE, unique = TRUE)
    return(unique(sub("\\.[0-9].*$", "", sub("\\[.*$", "", scalar_names))))
  }
  if (inherits(fit, "CmdStanMCMC")) {
    schema <- fit$variable_skeleton(transformed_parameters = FALSE, generated_quantities = FALSE)
    checkmate::assert_list(schema)
    checkmate::assert_names(names(schema), type = "unique")
    return(names(schema))
  }
  stop("Parameter schema requires a stanfit or CmdStanMCMC object.", call. = FALSE)
}

rstan_fit_slot <- function(fit, slot_name) {
  if (!isS4(fit) || !slot_name %in% methods::slotNames(fit)) return(NULL)
  methods::slot(fit, slot_name)
}
