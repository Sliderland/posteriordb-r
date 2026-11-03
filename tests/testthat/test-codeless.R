codeless_model_info <- function(name = "codeless") {
  as.model_info(list(name = name, title = "No code", model_implementations = list(),
                     added_by = "Test", added_date = as.Date("2026-01-01")))
}

test_that("a model may have no code", {
  mi <- codeless_model_info()
  expect_length(mi$model_implementations, 0L)
  expect_output(print(mi), "Frameworks: none")
  expect_error(model_code_path(mi, "stan"), "Model 'codeless' has no stan implementation")
  bad <- unclass(mi)
  bad$model_implementations <- list(julia = list(model_code = "m.jl"))
  expect_error(as.model_info(bad), "model_implementations")
  bad$model_implementations <- NULL
  expect_error(as.model_info(bad), "model_implementations")
})

test_that("analytical draws can be added for a model with no code", {
  p <- local_pdb()
  write_pdb(as.pdb_data(list(n = 10L, y = 3L),
                        info = list(name = "binomial", title = "Binomial", added_by = "Test",
                                    added_date = as.Date("2026-01-01"))), p)
  write_pdb(codeless_model_info(), p)
  po <- as.posterior(list(model_name = "codeless", data_name = "binomial",
                          dimensions = list(theta = 1)), pdb = p)
  write_pdb(po, p)

  set.seed(1)
  draws <- posterior::draws_list(theta = stats::rbeta(10000, 4, 8))
  rpd <- as.reference_posterior_draws(draws, info = reference_info("binomial-codeless", "analytical"))
  write_pdb(rpd, p)

  back <- posterior("binomial-codeless", p)
  expect_length(back$model_info$model_implementations, 0L)
  expect_identical(back$reference_posterior_name, "binomial-codeless")
  expect_equal(reference_posterior_draws(back)[[1]]$theta, draws[[1]]$theta)
  expect_error(stan_code(back), "has no stan implementation")
  expect_message(check_pdb_posterior(back, run_stan_code_checks = TRUE),
                 "no Stan code; Stan checks skipped")
})

test_that("mcmc draws from other software get the draw-count check only", {
  set.seed(1)
  draws <- posterior::draws_list(theta = stats::rnorm(10000))
  rpd <- check_reference_posterior_draws(
    as.reference_posterior_draws(draws, info = reference_info("x", "mcmc")))
  expect_identical(info(rpd)$inference$method, "mcmc")
  expect_true(passed_checks(rpd))
  expect_error(as.reference_posterior_draws(draws, info = reference_info("x", "nuts_in_julia")),
               "inference\\$method")
})
