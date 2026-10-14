#' Run Stan on a posterior
#'
#' @description
#' Run Stan on a posterior
#'
#' @param x a [pdb_posterior] object.
#' @param stan_args Arguments supplied to the selected Stan sampling backend.
#' @param backend either `"rstan"` or `"cmdstanr"`.
#' @param ... reserved for future arguments.
#' @details For CmdStanR, RStan-style `iter`/`warmup` and supported `control`
#'   settings are translated to native arguments. Conflicting aliases and
#'   unsupported controls raise an error before compilation. See
#'   [compute_reference_posterior_draws()] for supported controls.
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
  checkmate::assert_list(stan_args, names = "unique")
  args <- stan_args
  if (!is.null(args[["validate_csv"]]) && "diagnostics" %in% names(args))
    stop("Do not supply both `validate_csv` and `diagnostics`.", call. = FALSE)
  aliases <- c(cores = "parallel_chains", num_cores = "parallel_chains",
    num_chains = "chains", num_warmup = "iter_warmup", num_samples = "iter_sampling",
    stepsize = "step_size", max_depth = "max_treedepth",
    save_extra_diagnostics = "save_latent_dynamics")
  for (alias in names(aliases)) {
    target <- aliases[[alias]]
    if (!is.null(args[[alias]])) {
      if (!is.null(args[[target]]))
        stop("Do not supply both `", alias, "` and `", target, "`.", call. = FALSE)
      args[[target]] <- args[[alias]]
    }
    args[[alias]] <- NULL
  }
  if (!is.null(args[["iter"]])) {
    if (!is.null(args[["iter_sampling"]]) || !is.null(args[["iter_warmup"]])) {
      stop("Use either `iter`/`warmup` or CmdStanR iteration arguments, not both.", call. = FALSE)
    }
    warmup <- if (is.null(args[["warmup"]])) floor(args[["iter"]] / 2) else args[["warmup"]]
    args[["iter_sampling"]] <- args[["iter"]] - warmup
    args[["iter_warmup"]] <- warmup
  } else if (!is.null(args[["warmup"]])) {
    if (!is.null(args[["iter_warmup"]])) {
      stop("Do not supply both `warmup` and `iter_warmup`.", call. = FALSE)
    }
    args[["iter_warmup"]] <- args[["warmup"]]
  }
  if (!is.null(args[["control"]])) {
    controls <- args[["control"]]
    checkmate::assert_list(controls, names = "unique")
    control_map <- c(adapt_delta = "adapt_delta", max_treedepth = "max_treedepth",
      stepsize = "step_size", adapt_engaged = "adapt_engaged", metric = "metric",
      adapt_init_buffer = "init_buffer", adapt_term_buffer = "term_buffer", adapt_window = "window")
    unknown <- setdiff(names(controls), names(control_map))
    if (length(unknown))
      stop("Unsupported CmdStanR control setting(s): ", paste(unknown, collapse = ", "), call. = FALSE)
    for (name in names(controls)) {
      if (is.null(controls[[name]])) next
      target <- control_map[[name]]
      if (!is.null(args[[target]]))
        stop("Conflicting settings: `control$", name, "` and `", target, "`.", call. = FALSE)
      args[[target]] <- controls[[name]]
    }
  }
  args[c("iter", "warmup", "control")] <- NULL
  args
}
