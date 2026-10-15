# Everything that touches rstan or cmdstanr objects lives in this file. The
# rest of the package works on the backend-neutral list from extract_fit().

# Convert a completed Stan fit to:
#   draws       post-warmup draws_array, without lp__
#   sampler     draws_array of sampler diagnostics (divergent__, energy__, ...)
#   parameters  base names of parameter-block variables (NULL if unknown)
#   upar_counts named list of unconstrained parameter counts (NULL if unknown)
#   method_arguments, versions, model_code
extract_fit <- function(fit) UseMethod("extract_fit")

#' @export
extract_fit.default <- function(fit) {
  stop2("Unsupported fit of class '", class(fit)[1], "'. ",
        "Use a completed rstan::stanfit or cmdstanr::CmdStanMCMC fit.")
}

#' @export
extract_fit.stanfit <- function(fit) {
  require_package("rstan", "to read rstan fits")
  if (fit@mode != 0L) stop2("The stanfit does not contain draws.")
  draws <- drop_lp(posterior::as_draws_array(fit))
  sampler <- tryCatch(sampler_params_to_draws(rstan::get_sampler_params(fit, inc_warmup = FALSE)),
                      error = function(e) NULL)
  instance <- tryCatch(fit@.MISC$stan_fit_instance, error = function(e) NULL)
  parameters <- tryCatch(unique(stan_base(instance$constrained_param_names(FALSE, FALSE))),
                         error = function(e) NULL)
  upar_counts <- tryCatch(count_by_base(instance$unconstrained_param_names(FALSE, FALSE)),
                          error = function(e) NULL)
  args <- fit@stan_args[[1]]
  control <- args$control[intersect(names(args$control), c("adapt_delta", "max_treedepth"))]
  method_arguments <- drop_nulls(list(
    chains = length(fit@stan_args), iter = args$iter, warmup = args$warmup,
    thin = args$thin, seed = args$seed, control = if (length(control)) control))
  list(draws = draws, sampler = sampler, parameters = parameters, upar_counts = upar_counts,
       method_arguments = method_arguments,
       versions = environment_versions(rstan_version = package_version_string("rstan")),
       model_code = fit@stanmodel@model_code[1])
}

#' @export
extract_fit.CmdStanMCMC <- function(fit) {
  draws <- drop_lp(posterior::as_draws_array(fit$draws(format = "draws_array")))
  sampler <- tryCatch(posterior::as_draws_array(fit$sampler_diagnostics(format = "draws_array")),
                      error = function(e) NULL)
  meta <- fit$metadata()
  parameters <- tryCatch(names(fit$variable_skeleton(transformed_parameters = FALSE,
                                                     generated_quantities = FALSE)),
                         error = function(e) NULL)
  upar_counts <- tryCatch({
    one_draw <- posterior::subset_draws(fit$draws(), iteration = 1, chain = 1)
    counts <- count_by_base(posterior::variables(fit$unconstrain_draws(draws = one_draw)))
    if (all(names(counts) %in% parameters)) counts
  }, error = function(e) NULL)
  warmup <- meta$iter_warmup %||% 0
  method_arguments <- drop_nulls(list(
    chains = posterior::nchains(draws), iter = (meta$iter_sampling %||% NA) + warmup,
    warmup = warmup, thin = meta$thin, seed = meta$seed,
    control = drop_nulls(list(adapt_delta = meta$adapt_delta, max_treedepth = meta$max_treedepth))))
  versions <- environment_versions(
    cmdstanr_version = package_version_string("cmdstanr"),
    cmdstan_version = if (!is.null(meta$cmdstan_version)) paste("CmdStan", meta$cmdstan_version))
  list(draws = draws, sampler = sampler, parameters = parameters, upar_counts = upar_counts,
       method_arguments = method_arguments, versions = versions,
       model_code = tryCatch(paste(fit$code(), collapse = "\n"), error = function(e) NULL))
}

package_version_string <- function(pkg) {
  version <- tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) "unknown")
  paste(pkg, version)
}

drop_lp <- function(draws) {
  posterior::subset_draws(draws, variable = setdiff(posterior::variables(draws), "lp__"))
}

drop_nulls <- function(x) x[!vapply(x, is.null, logical(1))]

# rstan names unconstrained coordinates "theta.1"; Stan output uses "theta[1]".
stan_base <- function(x) sub("\\.[0-9].*$", "", base_variable(x))

count_by_base <- function(x) {
  x <- setdiff(x, "lp__")
  if (!length(x)) return(NULL)
  bases <- stan_base(x)
  lapply(split(bases, factor(bases, levels = unique(bases))), length)
}

sampler_params_to_draws <- function(params) {
  if (!length(params)) return(NULL)
  arr <- array(NA_real_, dim = c(nrow(params[[1]]), length(params), ncol(params[[1]])),
               dimnames = list(NULL, NULL, colnames(params[[1]])))
  for (i in seq_along(params)) arr[, i, ] <- params[[i]]
  posterior::as_draws_array(arr)
}

environment_versions <- function(...) {
  makevars <- file.path(Sys.getenv("HOME"), ".R",
                        if (.Platform$OS.type == "windows") "Makevars.win" else "Makevars")
  c(list(...)[!vapply(list(...), is.null, logical(1))],
    list(posterior_version = paste("posterior", utils::packageVersion("posterior")),
         r_Makevars = if (file.exists(makevars)) paste(readLines(makevars), collapse = "\n") else "",
         r_version = R.version$version.string,
         r_session = paste(utils::capture.output(print(utils::sessionInfo())), collapse = "\n")))
}

# Keep the variables a reference posterior should contain. `required` base
# names are always kept; `include = NULL` keeps every saved variable.
select_variables <- function(draws, required, include = NULL, exclude = NULL) {
  checkmate::assert_character(include, null.ok = TRUE, any.missing = FALSE)
  checkmate::assert_character(exclude, null.ok = TRUE, any.missing = FALSE)
  vars <- posterior::variables(draws)
  bases <- base_variable(vars)
  available <- unique(bases)
  unknown <- setdiff(c(include, exclude), available)
  if (length(unknown)) stop2("Unknown variable(s) in include/exclude: ", paste(unknown, collapse = ", "))
  missing <- setdiff(required, available)
  if (length(missing)) stop2("The fit has no saved draws for: ", paste(missing, collapse = ", "))
  dropped <- intersect(exclude, required)
  if (length(dropped)) {
    stop2("Parameters and posterior dimensions cannot be excluded: ", paste(dropped, collapse = ", "))
  }
  keep <- if (is.null(include)) available else intersect(available, union(include, required))
  keep <- setdiff(keep, exclude)
  if (!length(keep)) stop2("No variables are left after include/exclude.")
  posterior::subset_draws(draws, variable = vars[bases %in% keep])
}

# Sampling --------------------------------------------------------------------

run_stan <- function(po, stan_args, backend = c("rstan", "cmdstanr")) {
  backend <- match.arg(backend)
  checkmate::assert_list(stan_args, names = "unique")
  code <- as.character(stan_code(po))
  data <- plain_list(get_data(po))
  if (backend == "rstan") {
    require_package("rstan", "for the rstan backend")
    return(do.call(rstan::stan, c(list(model_code = code, model_name = po$name, data = data),
                                  stan_args)))
  }
  require_package("cmdstanr", "for the cmdstanr backend")
  model <- cmdstanr::cmdstan_model(cmdstanr::write_stan_file(code))
  do.call(model$sample, c(list(data = data), cmdstanr_args(stan_args)))
}

# Translate rstan-style sampling arguments (as stored in reference posterior
# info) to cmdstanr's names.
cmdstanr_args <- function(args) {
  control <- args$control
  args$control <- NULL
  if (!is.null(args$iter)) {
    warmup <- args$warmup %||% floor(args$iter / 2)
    args$iter_warmup <- warmup
    args$iter_sampling <- args$iter - warmup
  } else if (!is.null(args$warmup)) {
    args$iter_warmup <- args$warmup
  }
  args$iter <- NULL
  args$warmup <- NULL
  if (!is.null(args$cores)) args$parallel_chains <- args$cores
  args$cores <- NULL
  renamed <- c(adapt_delta = "adapt_delta", max_treedepth = "max_treedepth",
               stepsize = "step_size", metric = "metric", adapt_engaged = "adapt_engaged")
  unknown <- setdiff(names(control), names(renamed))
  if (length(unknown)) stop2("Unsupported control setting(s) for cmdstanr: ", paste(unknown, collapse = ", "))
  for (name in names(control)) args[[renamed[[name]]]] <- control[[name]]
  args
}

# Dimensions ------------------------------------------------------------------

#' Unconstrained parameter counts
#'
#' The `dimensions` of a posterior hold the number of unconstrained
#' parameters for each parameter: a `matrix[2, 3]` counts 6 and a
#' `simplex[3]` counts 2. `infer_posterior_dimensions()` compiles Stan code
#' with rstan and reads the counts without sampling.
#' `infer_unconstrained_parameter_counts_from_fit()` reads them from a fit.
#' Parameters with no free coordinates (such as `simplex[1]`) are left out.
#'
#' @param model_code Stan code, a path to a `.stan` file, or a
#'   `pdb_model_code` object.
#' @param data The data, a named list or `pdb_data` object.
#' @param fit An `rstan::stanfit` (or a `cmdstanr::CmdStanMCMC` whose
#'   compiled model methods are available).
#' @return A named list of positive integers.
#' @export
infer_posterior_dimensions <- function(model_code, data) {
  require_package("rstan", "to infer dimensions")
  model_code <- as.character(model_code)
  if (length(model_code) == 1L && file.exists(model_code)) {
    model_code <- paste(readLines(model_code, warn = FALSE), collapse = "\n")
  }
  fit <- suppressWarnings(rstan::stan(model_code = model_code, data = plain_list(data),
                                      chains = 0L, refresh = 0L))
  infer_unconstrained_parameter_counts_from_fit(fit)
}

#' @rdname infer_posterior_dimensions
#' @export
infer_unconstrained_parameter_counts_from_fit <- function(fit) {
  counts <- if (inherits(fit, "stanfit")) {
    tryCatch(count_by_base(fit@.MISC$stan_fit_instance$unconstrained_param_names(FALSE, FALSE)),
             error = function(e) NULL)
  } else {
    extract_fit(fit)$upar_counts
  }
  counts %||% stop2("The unconstrained parameter names are not available from this fit. ",
                    "Use infer_posterior_dimensions() with the model code and data.")
}

# Reconstruction --------------------------------------------------------------

#' Recompute model output from parameter draws
#'
#' Evaluates transformed parameters and generated quantities of a Stan model
#' at existing draws of its parameters, without running MCMC.
#' `reconstruct_posterior_output()` does this for a posterior's reference
#' draws.
#'
#' Random generated quantities are drawn again, so they will not match the
#' original values. Sampler diagnostics are not reconstructed.
#'
#' @param draws Draws with every parameter-block variable, in any format
#'   the posterior package can convert.
#' @param model Stan code, a `.stan` file, a `pdb_model_code`, an
#'   `rstan::stanmodel`, or a fitted `rstan::stanfit`. A
#'   `cmdstanr::CmdStanMCMC` fit also works when its compiled model methods
#'   are available.
#' @param data The data (not needed for fits, which carry their data).
#' @param variables Base or full variable names to return; `NULL` returns
#'   everything.
#' @param seed Seed used when a new rstan model has to be initialised.
#' @param posterior_name A posterior name or alias.
#' @param pdb A [pdb][pdb_local] connection.
#' @return A list with the reconstructed `draws` (a `draws_array`) and the
#'   `evaluator`, which can be passed back as `model` to avoid recompiling.
#' @export
reconstruct_stan_output <- function(draws, model, data = NULL, variables = NULL, seed = 1L) {
  evaluator <- if (inherits(model, "pdb_stan_evaluator")) model else stan_evaluator(model, data, seed)
  draws <- posterior::as_draws_array(draws)
  missing <- setdiff(evaluator$parameter_names, base_variable(posterior::variables(draws)))
  if (length(missing)) stop2("The draws are missing parameter(s): ", paste(missing, collapse = ", "))
  dims <- dim(draws)
  rows <- vector("list", dims[1] * dims[2])
  for (chain in seq_len(dims[2])) {
    for (iter in seq_len(dims[1])) {
      values <- draws[iter, chain, , drop = TRUE]
      names(values) <- posterior::variables(draws)
      pars <- lapply(stats::setNames(nm = evaluator$parameter_names), function(p) {
        fill_variable(values, p, evaluator$parameter_dims[[p]])
      })
      rows[[(chain - 1) * dims[1] + iter]] <- flatten_variables(evaluator$evaluate(pars),
                                                                evaluator$output_dims)
    }
  }
  out <- do.call(rbind, rows)
  arr <- array(out, dim = c(dims[1], dims[2], ncol(out)),
               dimnames = list(NULL, NULL, colnames(out)))
  result <- posterior::as_draws_array(arr)
  if (!is.null(variables)) {
    vars <- colnames(out)
    result <- posterior::subset_draws(result, variable = vars[vars %in% variables |
                                                               base_variable(vars) %in% variables])
  }
  list(draws = result, evaluator = evaluator)
}

#' @rdname reconstruct_stan_output
#' @export
reconstruct_posterior_output <- function(posterior_name, pdb = pdb_default(), variables = NULL,
                                         seed = 1L) {
  po <- posterior(posterior_name, pdb = pdb)
  if (!identical(reference_posterior_info(po)$inference$method, "stan_sampling")) {
    stop2("Only reference posteriors computed with Stan can be reconstructed.")
  }
  reconstruct_stan_output(reference_posterior_draws(po), stan_code(po), get_data(po),
                          variables = variables, seed = seed)
}

# An evaluator maps a list of constrained parameter values to all model
# output (parameters, transformed parameters, generated quantities).
stan_evaluator <- function(model, data, seed) {
  if (inherits(model, "CmdStanMCMC")) return(cmdstanr_evaluator(model))
  require_package("rstan", "to reconstruct model output")
  fit <- if (inherits(model, "stanfit")) {
    model
  } else {
    if (is.null(data)) stop2("`data` is required unless `model` is a fit.")
    data <- plain_list(data)
    if (inherits(model, "stanmodel")) {
      rstan::sampling(model, data = data, chains = 0L, seed = seed)
    } else {
      code <- as.character(model)
      if (length(code) == 1L && file.exists(code)) code <- paste(readLines(code), collapse = "\n")
      suppressWarnings(rstan::stan(model_code = code, data = data, chains = 0L, seed = seed))
    }
  }
  parameters <- unique(stan_base(fit@.MISC$stan_fit_instance$constrained_param_names(FALSE, FALSE)))
  structure(list(
    parameter_names = parameters,
    parameter_dims = fit@par_dims[parameters],
    output_dims = fit@par_dims,
    evaluate = function(pars) rstan::constrain_pars(fit, rstan::unconstrain_pars(fit, pars))
  ), class = "pdb_stan_evaluator")
}

cmdstanr_evaluator <- function(fit) {
  skeleton_dims <- function(...) {
    lapply(fit$variable_skeleton(...), function(x) dim(x) %||% (if (length(x) > 1) length(x)))
  }
  parameter_dims <- skeleton_dims(transformed_parameters = FALSE, generated_quantities = FALSE)
  structure(list(
    parameter_names = names(parameter_dims),
    parameter_dims = parameter_dims,
    output_dims = skeleton_dims(transformed_parameters = TRUE, generated_quantities = TRUE),
    evaluate = function(pars) {
      fit$constrain_variables(fit$unconstrain_variables(pars),
                              transformed_parameters = TRUE, generated_quantities = TRUE)
    }
  ), class = "pdb_stan_evaluator")
}

# Stan's flattened names for a variable with dimensions `dims`, in the
# column-major order R uses to fill arrays.
indexed_names <- function(name, dims) {
  if (!length(dims) || prod(dims) == 0) return(if (!length(dims)) name else character())
  grid <- as.matrix(expand.grid(lapply(dims, seq_len)))
  paste0(name, "[", apply(grid, 1, paste, collapse = ","), "]")
}

fill_variable <- function(values, name, dims) {
  if (!length(dims)) return(values[[name]])
  out <- values[indexed_names(name, dims)]
  if (length(dims) == 1L) as.numeric(out) else array(out, dim = dims)
}

flatten_variables <- function(x, dims_by_name) {
  unlist(lapply(names(x), function(name) {
    v <- x[[name]]
    dims <- dims_by_name[[name]]
    stats::setNames(as.numeric(v), indexed_names(name, dims))
  }))
}
