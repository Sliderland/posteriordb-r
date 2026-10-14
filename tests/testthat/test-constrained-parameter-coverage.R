constrained_parameter_fit <- local({
  fit <- NULL
  function() {
    skip_stan_integration()
    skip_if_not_installed("rstan")
    if (is.null(fit)) {
      code <- constrained_parameter_model()
      fit <<- suppressWarnings(rstan::sampling(rstan::stan_model(model_code = code),
        data = list(), iter = 12, warmup = 6, chains = 2, seed = 412, refresh = 0))
    }
    fit
  }
})


test_that("fit import retains zero-free-coordinate parameters without accepting undefined metrics", {
  fit <- constrained_parameter_fit()
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  object <- structure(list(name = "constrained-posterior", reference_posterior_name = NULL,
    dimensions = infer_unconstrained_parameter_counts_from_fit(fit)), class = "pdb_posterior")
  imported <- as_reference_posterior_draws(fit, object, connection, include = "theta")
  expect_identical(posterior::variables(as_reference_posterior_draws(fit, object, connection,
    exclude = "all")), posterior::variables(imported))
  expect_true("fixed[1]" %in% posterior::variables(imported))
  expect_false(any(c("twice_theta", "prediction") %in% posterior::variables(imported)))
  expect_true(is.na(info(imported)$diagnostics$mean_lag1_ac[["fixed[1]"]]))
  expect_true(nzchar(info(imported)$checks_made$check_failed))
  expect_error(assert_checked_reference_posterior_draws(imported), "checks_made")
  expect_error(as_reference_posterior_draws(fit, object, connection, exclude = "fixed"),
    "Cannot exclude required")
})


test_that("RStan bundles recover absent compiled schema without changing draws", {
  fit <- constrained_parameter_fit()
  original <- extract_rstan_fit_for_bundle(fit, compute_diagnostics = FALSE)
  archived <- fit
  archived@.MISC <- list2env(as.list(fit@.MISC), parent = parent.env(fit@.MISC))
  archived@.MISC$stan_fit_instance <- NULL
  expect_null(archived@.MISC$stan_fit_instance)
  restored <- extract_rstan_fit_for_bundle(archived, data = list(), compute_diagnostics = FALSE)
  expect_identical(restored$dimensions, original$dimensions)
  expect_identical(restored$output_shapes, original$output_shapes)
  expect_equal(restored$draws, original$draws)
  expect_equal(restored$sampler_diagnostics, original$sampler_diagnostics)
})
