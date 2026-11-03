codeless_model_info <- function(name = "codeless_model") {
  as.pdb_model_info(list(
    name = name,
    title = "A model with no code",
    added_by = "Test",
    added_date = Sys.Date(),
    model_implementations = list()
  ))
}

test_that("a model may have no code", {
  mi <- codeless_model_info()
  expect_length(mi$model_implementations, 0L)
  expect_output(print(mi), "Frameworks: none")
  expect_error(
    model_implementation_file_path(mi, "stan"),
    "Model 'codeless_model' has no stan implementation."
  )
  bad <- unclass(mi)
  bad$model_implementations <- list(julia = list(model_code = "m.jl"))
  expect_error(as.pdb_model_info(bad), "model_implementations")
  bad$model_implementations <- NULL
  expect_error(as.pdb_model_info(bad), "model_implementations")
})

test_that("analytical draws can be added for a model with no code", {
  local_test_database()
  pdb_test <- pdb_local()

  di <- as.pdb_data_info(list(
    name = "codeless_data",
    title = "Binomial data",
    added_by = "Test",
    added_date = Sys.Date()
  ))
  dat <- as.pdb_data(list(n = 10L, y = 3L), info = di)
  mi <- codeless_model_info()
  name <- "codeless_data-codeless_model"
  po <- as.pdb_posterior(
    list(
      name = name,
      model_name = mi$name,
      data_name = di$name,
      model_info = mi,
      data_info = di,
      dimensions = list(theta = 1L),
      reference_posterior_name = NULL,
      added_by = "Test",
      added_date = Sys.Date()
    ),
    pdb = pdb_test
  )
  write_pdb(dat, pdb_test)
  write_pdb(mi, pdb_test)
  write_pdb(po, pdb_test)

  withr::local_seed(1)
  draws <- posterior::draws_list(theta = stats::rbeta(10000L, 4, 8))
  rpi <- as.pdb_reference_posterior_info(list(
    name = name,
    inference = list(
      method = "analytical",
      method_arguments = list(distribution = "beta", shape1 = 4, shape2 = 8)
    ),
    diagnostics = list(ndraws = 10000L, nchains = 1L),
    checks_made = NULL,
    comments = NULL,
    added_by = "Test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  rpd <- check_reference_posterior_draws(
    as.reference_posterior_draws(draws, info = rpi, pdb = pdb_test)
  )
  write_pdb(rpd, pdb_test)

  pdb_clear_cache(pdb_test)
  po2 <- posterior(name, pdb = pdb_test)
  expect_length(po2$model_info$model_implementations, 0L)
  expect_identical(po2$reference_posterior_name, name)
  expect_equal(
    reference_posterior_draws(po2)[[1]]$theta,
    draws[[1]]$theta
  )
  expect_error(stan_code(po2), "has no stan implementation")
  expect_message(
    check_pdb_posterior(po2, run_stan_code_checks = TRUE),
    "No Stan code; Stan checks skipped."
  )
})

test_that("mcmc draws from other software get the draw-count check only", {
  withr::local_seed(1)
  draws <- posterior::draws_list(theta = stats::rnorm(10000L))
  rpi <- list(
    name = "x",
    inference = list(method = "mcmc", method_arguments = list(software = "JAGS")),
    diagnostics = list(ndraws = 10000L, nchains = 1L),
    checks_made = NULL,
    comments = NULL,
    added_by = "Test",
    added_date = Sys.Date(),
    versions = NULL
  )
  checked <- check_reference_posterior_draws(
    as.reference_posterior_draws(draws, info = as.pdb_reference_posterior_info(rpi))
  )
  expect_identical(info(checked)$checks_made, list(ndraws_is_10k = TRUE))
  expect_silent(summary_statistics_from_checked_reference_draws(checked))
  rpi$inference$method <- "nuts_in_julia"
  expect_error(as.pdb_reference_posterior_info(rpi))
})
