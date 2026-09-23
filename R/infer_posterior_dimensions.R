#' Infer posterior parameter dimensions from Stan code and data
#'
#' Compile and run a short Stan fit to discover the parameter names and
#' dimensions required by PosteriorDB posterior metadata.
#'
#' @param model_code Stan model source as a string or `pdb_model_code` object.
#' @param data a named list of Stan data or a `pdb_data` object.
#' @param include optional parameter names to retain. Names refer to base Stan
#'   variables, before array indices are expanded.
#' @param exclude parameter names to omit. `lp__` is always omitted.
#' @param backend Stan backend to use, either `"rstan"` or `"cmdstanr"`.
#' @param iter total iterations for the short fit, split evenly between
#'   warmup and sampling.
#' @return A named list of PosteriorDB dimensions.
#' @export
infer_posterior_dimensions <- function(
  model_code,
  data,
  include = NULL,
  exclude = NULL,
  backend = c("rstan", "cmdstanr"),
  iter = 4L
) {
  backend <- match.arg(backend)
  checkmate::assert_string(model_code, min.chars = 1L)
  if (inherits(data, "pdb_data")) data <- unclass(data)
  checkmate::assert_list(data)
  if (length(data) &&
      (is.null(names(data)) || anyNA(names(data)) || any(!nzchar(names(data))))) {
    stop("`data` must be a fully named list.", call. = FALSE)
  }
  if (length(data)) {
    checkmate::assert_character(names(data), min.chars = 1L, unique = TRUE)
  }
  checkmate::assert_character(include, null.ok = TRUE, min.chars = 1L,
                              unique = TRUE)
  checkmate::assert_character(exclude, null.ok = TRUE, min.chars = 1L,
                              unique = TRUE)
  checkmate::assert_integerish(iter, len = 1L, lower = 4L)
  if (length(intersect(include, exclude))) {
    stop("A parameter cannot appear in both `include` and `exclude`.", call. = FALSE)
  }
  if ("lp__" %in% include) {
    stop("`lp__` is an internal Stan variable and cannot be included.", call. = FALSE)
  }

  if (identical(backend, "rstan")) {
    if (!requireNamespace("rstan", quietly = TRUE)) {
      stop("The `rstan` package is required for this backend.", call. = FALSE)
    }
    fit <- suppressWarnings(rstan::stan(
      model_code = model_code,
      data = data,
      chains = 1L,
      iter = as.integer(iter),
      warmup = as.integer(floor(iter / 2)),
      refresh = 0L
    ))
    dimensions <- fit@par_dims
  } else {
    if (!requireNamespace("cmdstanr", quietly = TRUE)) {
      stop("The `cmdstanr` package is required for this backend.", call. = FALSE)
    }
    stan_file <- cmdstanr::write_stan_file(model_code)
    model <- cmdstanr::cmdstan_model(stan_file, compile = TRUE, quiet = TRUE)
    fit <- model$sample(
      data = data,
      chains = 1L,
      iter_warmup = as.integer(floor(iter / 2)),
      iter_sampling = as.integer(iter - floor(iter / 2)),
      refresh = 0L
    )
    draws <- posterior::as_draws_array(fit$draws(format = "draws_array"))
    variables <- posterior::variables(draws)
    dimensions <- stats::setNames(lapply(variables, function(variable) {
      values <- posterior::extract_variable(draws, variable)
      value_dims <- dim(values)
      if (is.null(value_dims) || length(value_dims) <= 2L) integer() else value_dims[-c(1L, 2L)]
    }), variables)
  }

  available <- names(dimensions)
  if (!is.null(include)) {
    missing <- setdiff(include, available)
    if (length(missing)) {
      stop("Requested included parameter(s) not found: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    dimensions <- dimensions[include]
  }
  if (!is.null(exclude)) {
    missing <- setdiff(exclude, c(available, "lp__"))
    if (length(missing)) {
      stop("Requested excluded parameter(s) not found: ", paste(missing, collapse = ", "), call. = FALSE)
    }
  }
  dimensions <- dimensions[setdiff(names(dimensions), c(exclude, "lp__"))]
  if (!length(dimensions)) {
    stop("Parameter selection produced no posterior variables.", call. = FALSE)
  }
  dimensions
}
