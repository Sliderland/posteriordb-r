bundle_fit_count_mock <- function(fit, include = NULL, exclude = NULL) {
  counts <- stats::setNames(rep(list(1L), length(fit$par_dims)), names(fit$par_dims))
  excluded <- if (is.null(exclude)) character() else exclude
  selected <- setdiff(if (is.null(include)) names(counts) else include,
                      excluded)
  counts[selected]
}

make_bundle_extraction_fit <- function(dimensions = list(mu = integer(), theta = 1L),
                                       variables = c("mu", "theta[1]"),
                                       algorithm = "NUTS", source = "parameters { real mu; real theta[1]; } model {}") {
  n <- 8L
  vals <- array(seq_len(n * 2L * length(variables)),
    dim = c(n, 2L, length(variables)),
    dimnames = list(NULL, NULL, variables))
  sampler <- array(0, c(n, 2L, 2L),
    dimnames = list(NULL, NULL, c("divergent__", "energy__")))
  structure(list(
    stanmodel = list(model_code = source), par_dims = dimensions,
    .MISC = list(stan_fit_instance = list(
      constrained_param_names = function(...) names(dimensions),
      unconstrained_param_names = function(...) names(dimensions))),
    sim = list(chains = 2L),
    stan_args = list(
      list(method = "sampling", algorithm = algorithm,
           control = list(max_treedepth = 10L), seed = 1L),
      list(method = "sampling", algorithm = algorithm,
           control = list(max_treedepth = 12L), seed = 2L)
    ),
    .draws = posterior::as_draws_array(vals),
    .sampler = posterior::as_draws_array(sampler)
  ), class = c("stanfit", "list"))
}
