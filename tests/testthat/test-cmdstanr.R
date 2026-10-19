# One real CmdStanR run. Opt in with PDB_TEST_STAN=true and CMDSTAN set to a
# CmdStan installation. It needs an R process without rstan loaded (loading
# both crashed when cmdstanr compiled its model methods), so run this file on
# its own: testthat::test_file("tests/testthat/test-cmdstanr.R").
test_that("a cmdstanr fit gives counts, reference draws and reconstructed output", {
  skip_unless_env("PDB_TEST_STAN")
  skip_if(!nzchar(Sys.getenv("CMDSTAN")), "Set CMDSTAN to a CmdStan installation")
  skip_if_not_installed("cmdstanr")
  skip_if("rstan" %in% loadedNamespaces(), "rstan is loaded in this process")
  cmdstanr::set_cmdstan_path(Sys.getenv("CMDSTAN"))
  p <- local_pdb()
  po <- posterior("8schools", p)
  model <- cmdstanr::cmdstan_model(cmdstanr::write_stan_file(as.character(stan_code(po))),
                                   compile_model_methods = TRUE)
  fit <- model$sample(data = posteriordb:::plain_list(get_data(po)), chains = 4,
                      parallel_chains = 4, iter_warmup = 1000, iter_sampling = 25000, thin = 10,
                      seed = 4711, adapt_delta = 0.95, refresh = 0, show_messages = FALSE)

  expect_identical(infer_unconstrained_parameter_counts_from_fit(fit),
                   list(theta_trans = 8L, mu = 1L, tau = 1L))
  rpd <- as_reference_posterior_draws(fit, "8schools", pdb = p)
  expect_null(attr(rpd, "check_failures"))
  expect_identical(info(rpd)$inference$method_arguments$iter, 26000L)
  expect_match(info(rpd)$versions$stan_version, "^Stan [0-9]")
  expect_length(info(rpd)$diagnostics$max_treedepth_exceeded, 4)

  # Scalars (mu, tau) and vectors (theta_trans) both go back through the model.
  pars <- posterior::subset_draws(fit$draws(), variable = c("theta_trans", "mu", "tau"),
                                  iteration = 1:5)
  out <- reconstruct_stan_output(pars, fit)$draws
  expect_equal(posterior::subset_draws(out, variable = "theta"),
               posterior::subset_draws(fit$draws(), variable = "theta", iteration = 1:5),
               tolerance = 1e-5, ignore_attr = TRUE)
})
