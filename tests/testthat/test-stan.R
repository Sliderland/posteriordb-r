# One real Stan run, shared by every test in this file. Opt in with
# PDB_TEST_STAN=true: it compiles a model and keeps 4 x 2500 draws, thinned
# by 10 as the stored reference posteriors are (NUTS draws of this model
# are anticorrelated, which the lag-1 autocorrelation check rejects).
stan_fit <- local({
  fit <- NULL
  function() {
    if (is.null(fit)) {
      skip_unless_env("PDB_TEST_STAN")
      skip_if_not_installed("rstan")
      p <- local_pdb()
      po <- posterior("8schools", p)
      fit <<- suppressWarnings(rstan::stan(
        model_code = as.character(stan_code(po)), data = plain_list(get_data(po)),
        chains = 4, iter = 26000, warmup = 1000, thin = 10, seed = 4711, refresh = 0, cores = min(4, parallel::detectCores()),
        control = list(adapt_delta = 0.95)))
    }
    fit
  }
})
plain_list <- posteriordb:::plain_list

test_that("an rstan fit gives counts, reference draws and a written bundle", {
  fit <- stan_fit()
  p <- local_pdb()
  expect_identical(infer_unconstrained_parameter_counts_from_fit(fit),
                   list(theta_trans = 8L, mu = 1L, tau = 1L))

  rpd <- as_reference_posterior_draws(fit, "8schools", pdb = p)
  expect_null(attr(rpd, "check_failures"))
  expect_identical(posterior::ndraws(rpd), 10000L)
  expect_true(all(c("theta[1]", "theta_trans[1]", "mu", "tau") %in% posterior::variables(rpd)))
  expect_equal(info(rpd)$inference$method_arguments$thin, 10)
  expect_match(info(rpd)$versions$rstan_version, "rstan")

  bundle <- create_pdb_bundle(fit, data = "eight_schools", model_code = "eight_schools_noncentered",
                              pdb = p, posterior_info = list(name = "stan_run"))
  expect_identical(bundle$posterior$dimensions, list(theta_trans = 8L, mu = 1L, tau = 1L))
  expect_true(write_pdb(bundle, p)$reference_draws_written)
  expect_identical(check_pdb(p, verbose = FALSE), 0L)
})

test_that("model output is reconstructed from parameter draws", {
  fit <- stan_fit()
  draws <- posterior::subset_draws(posterior::as_draws_array(fit), iteration = 1:5)
  out <- reconstruct_stan_output(posterior::subset_draws(draws, variable = c("theta_trans", "mu", "tau")),
                                 fit)
  for (v in paste0("theta[", 1:8, "]")) {
    expect_equal(posterior::extract_variable_matrix(out$draws, v),
                 posterior::extract_variable_matrix(draws, v), tolerance = 1e-8)
  }
})

test_that("reference draws are computed from a reference posterior info", {
  fit <- stan_fit()
  p <- local_pdb()
  local_mocked_bindings(run_stan = function(po, stan_args, backend) fit)
  rpi <- reference_posterior_info("8schools", pdb = p)
  rpd <- check_reference_posterior_draws(compute_reference_posterior_draws(rpi, pdb = p))
  expect_true(all(unlist(info(rpd)$checks_made[setdiff(names(info(rpd)$checks_made), "ess_within_bounds")])))
  results <- sequential_batch_workflow(list(rpi), pdb = p, write = TRUE, overwrite = TRUE)
  expect_identical(results[[1]]$status, "completed")
  expect_true(results[[1]]$written)
})
