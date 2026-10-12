small_checked_draws <- function() {
  set.seed(123)
  values <- array(
    stats::rnorm(2500L * 4L),
    dim = c(2500L, 4L, 1L),
    dimnames = list(NULL, NULL, "theta")
  )
  diagnostics <- list(
    ndraws = 10000L,
    nchains = 4L,
    effective_sample_size_bulk = 10000,
    effective_sample_size_tail = 10000,
    r_hat = 1,
    mean_lag1_ac = 0.01,
    divergent_transitions = rep(0, 4L),
    expected_fraction_of_missing_information = rep(0.5, 4L)
  )
  draw_info <- as.reference_posterior_info(list(
    name = "diagnostic-test",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = diagnostics,
    checks_made = NULL,
    comments = "",
    added_by = "test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  as.reference_posterior_draws(
    posterior::as_draws_list(values),
    info = draw_info
  )
}
alignment_reference_draws <- function() {
  withr::local_seed(123)
  values <- posterior::as_draws_array(array(
    rnorm(20000),
    c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("alpha", "beta"))
  ))
  metadata <- as.reference_posterior_info(list(
    name = "alignment-reference",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = list(
      ndraws = 10000L,
      nchains = 4L,
      diagnostic_information = list(names = c("alpha", "beta")),
      effective_sample_size_bulk = c(alpha = 10000, beta = 10000),
      effective_sample_size_tail = c(alpha = 10000, beta = 10000),
      mean_lag1_ac = c(alpha = .05, beta = .05),
      r_hat = c(alpha = 1.01, beta = 1.01),
      expected_fraction_of_missing_information = stats::setNames(
        rep(.2, 4),
        paste0("chain", 1:4)
      ),
      divergent_transitions = stats::setNames(rep(0, 4), paste0("chain", 1:4))
    ),
    checks_made = NULL,
    comments = NULL,
    added_by = "Test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  as.reference_posterior_draws(posterior::as_draws_list(values), metadata)
}
make_diagnostic_cmdstan_fit <- function(n = 2500L, nchains = 4L, n_var = 1L) {
  testthat::skip_if_not_installed("cmdstanr")
  withr::local_seed(123)
  var_names <- c("theta", "a", "b", "c", "d", "e", "f", "g", "h", "i")
  stopifnot(n_var <= length(var_names))
  vals <- array(
    stats::rnorm(n * nchains * n_var),
    c(n, nchains, n_var),
    dimnames = list(NULL, NULL, var_names[1:n_var])
  )
  sampler <- array(
    0,
    c(n, nchains, 3L),
    dimnames = list(NULL, NULL, c("divergent__", "energy__", "treedepth__"))
  )
  called <- new.env(parent = emptyenv())
  called$sampler <- FALSE
  fit <- list(
    draws = function(inc_warmup = FALSE, format = "draws_array") {
      posterior::as_draws_array(vals)
    },
    sampler_diagnostics = function(inc_warmup = FALSE, format = "draws_array") {
      called$sampler <- TRUE
      posterior::as_draws_array(sampler)
    },
    metadata = function() {
      list(
        iter_sampling = n,
        iter_warmup = 0L,
        thin = 1L,
        max_depth = 10L,
        model_name = "test"
      )
    }
  )
  class(fit) <- c("CmdStanMCMC", "list")
  list(fit = fit, called = called)
}
create_draws_arr <- function(n = 20L * 4L * 3L, size = c(20L, 4L, 3L)) {
  withr::local_seed(123)
  stopifnot(n == prod(size))
  arr <- array(
    stats::rnorm(n),
    size,
    dimnames = list(NULL, NULL, c("alpha[1]", "beta", "lp__"))
  )
  draws <- posterior::as_draws_array(arr)
  draws
}
create_transformed_ref_draws <- function(.local_envir = parent.frame()) {
  # Accepted two-variable reference draws with sampler diagnostics, a stale
  # report and a throwaway database, for tests that transform draws in memory.
  withr::local_seed(123)
  values <- posterior::as_draws_array(array(
    rnorm(20000),
    c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("alpha", "beta"))
  ))
  sampler <- posterior::as_draws_array(array(
    0,
    c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("divergent__", "energy__"))
  ))
  sampler[,, "energy__"] <- matrix(rnorm(10000), 2500, 4)
  diagnostics <- compute_stan_sampling_diagnostics(
    values,
    c("alpha", "beta"),
    sampler_diagnostics = sampler,
    expected_fraction_of_missing_information = rep(.5, 4)
  )
  ri <- as.reference_posterior_info(list(
    name = "transform-reference",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = diagnostics,
    checks_made = bundle_acceptance_flags(),
    comments = "Preserve",
    added_by = "Test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  root <- withr::local_tempdir("transform-db-", .local_envir = .local_envir)
  writeLines("unchanged", file.path(root, "sentinel"))
  connection <- structure(
    list(pdb_local_endpoint = root),
    class = c("pdb_local", "pdb")
  )
  x <- as.reference_posterior_draws(
    posterior::as_draws_list(values),
    ri,
    pdb = connection
  )
  attr(x, "sampler_diagnostics") <- sampler
  attr(x, "sampling_metadata") <- list(
    expected_fraction_of_missing_information = rep(.5, 4)
  )
  attr(x, "diagnostic_report") <- list(obsolete = TRUE)
  list(
    x = x,
    values = values,
    sampler = sampler,
    diagnostics = diagnostics,
    connection = connection,
    root = root
  )
}
