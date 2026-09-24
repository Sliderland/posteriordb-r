#' Run Stan on a posterior
#'
#' @description
#' Run Stan on a posterior
#'
#' @param x a [pdb_posterior] object.
#' @param stan_args Arguments supplied to the selected Stan sampling backend.
#' @param backend either `"rstan"` or `"cmdstanr"`.
#' @param ... reserved for future arguments.
#'
run_stan <- function(x, stan_args, backend = c("rstan", "cmdstanr"), ...){
  UseMethod("run_stan")
}

#' @rdname run_stan
#' @exportS3Method
run_stan.pdb_posterior <- function(
  x,
  stan_args,
  backend = c("rstan", "cmdstanr"),
  ...
){
  checkmate::assert_list(stan_args)
  checkmate::assert_names(names(stan_args), disjunct.from = c("model_name", "model_code", "data"))
  backend <- match.arg(backend)
  sa <- list(model_name = x$name,
             model_code = stan_code(x),
             data = stan_data(x))
  if (identical(backend, "rstan")) {
    if (!requireNamespace("rstan", quietly = TRUE)) {
      stop("The `rstan` package is required for this backend.", call. = FALSE)
    }
    stan_object <- do.call(rstan::stan, c(sa, stan_args))
    stan_object@model_name <- x$name
    return(stan_object)
  }
  if (!requireNamespace("cmdstanr", quietly = TRUE)) {
    stop("The `cmdstanr` package is required for this backend.", call. = FALSE)
  }
  stan_args <- translate_cmdstanr_sampling_args(stan_args)
  stan_file <- cmdstanr::write_stan_file(as.character(sa$model_code))
  model <- cmdstanr::cmdstan_model(stan_file, compile = TRUE, quiet = TRUE)
  do.call(model$sample, c(list(data = sa$data), stan_args))
}

translate_cmdstanr_sampling_args <- function(stan_args) {
  args <- stan_args
  if (!is.null(args$iter)) {
    if (!is.null(args$iter_sampling) || !is.null(args$iter_warmup)) {
      stop("Use either `iter`/`warmup` or CmdStanR iteration arguments, not both.", call. = FALSE)
    }
    warmup <- if (is.null(args$warmup)) floor(args$iter / 2) else args$warmup
    args$iter_sampling <- args$iter - warmup
    args$iter_warmup <- warmup
    args$iter <- NULL
    args$warmup <- NULL
  } else if (!is.null(args$warmup)) {
    if (!is.null(args$iter_warmup)) {
      stop("Do not supply both `warmup` and `iter_warmup`.", call. = FALSE)
    }
    args$iter_warmup <- args$warmup
    args$warmup <- NULL
  }
  if (!is.null(args$cores)) {
    args$parallel_chains <- args$cores
    args$cores <- NULL
  }
  if (!is.null(args$control)) {
    if (!is.list(args$control)) stop("`control` must be a list.", call. = FALSE)
    controls <- args$control
    args$control <- NULL
    for (name in c("adapt_delta", "max_treedepth")) {
      if (is.null(args[[name]]) && !is.null(controls[[name]])) {
        args[[name]] <- controls[[name]]
      }
    }
  }
  args
}
