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

test_that("real constrained parameters separate free counts from complete saved shapes", {
  fit <- constrained_parameter_fit()
  counts <- infer_unconstrained_parameter_counts_from_fit(fit)
  expected <- list(weights = 2L, C = 3L, Sigma = 3L, Lcorr = 3L, Lcov = 6L,
    M = 6L, singleton = 1L, a = 4L, theta = 1L)
  expect_identical(counts, expected)
  expect_identical(sum(unlist(counts)), 29L)
  extracted <- extract_rstan_fit_for_bundle(fit, compute_diagnostics = FALSE, include = "none")
  vars <- posterior::variables(extracted$draws)
  expect_true("fixed[1]" %in% vars)
  expect_length(vars, 47L)
  expect_false(any(c("twice_theta", "prediction", "lp__") %in% vars))
  expect_identical(extracted$dimensions, expected)
  expect_equal(extracted$output_shapes$fixed, 1L)
  expect_equal(extracted$output_shapes$M, c(2L, 3L))
  expect_equal(extracted$output_shapes$a, c(2L, 2L))
  expect_equal(as.numeric(extracted$draws[, , "fixed[1]"]), rep(1, 12))
  expect_error(extract_rstan_fit_for_bundle(fit, compute_diagnostics = FALSE,
    exclude = "fixed"), "Cannot exclude parameter-block")
  bundle <- create_pdb_bundle(fit, data = list(), include = "none", check = FALSE,
    data_info = list(name = "constrained-data", title = "Inputs"),
    model_info = list(name = "constrained-model", title = "Model"))
  expect_identical(posterior::variables(bundle$reference_draws), vars)
  expect_identical(bundle$posterior$dimensions, expected)
  expect_error(create_pdb_bundle(fit, data = list(), include = "none", exclude = "fixed",
    check = FALSE, data_info = list(name = "constrained-data", title = "Inputs"),
    model_info = list(name = "constrained-model", title = "Model")), "Cannot exclude parameter-block")
})


test_that("fit import retains zero-free-coordinate parameters without accepting undefined metrics", {
  fit <- constrained_parameter_fit()
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  object <- structure(list(name = "constrained-posterior", reference_posterior_name = NULL,
    dimensions = infer_unconstrained_parameter_counts_from_fit(fit)), class = "pdb_posterior")
  imported <- as_reference_posterior_draws(fit, object, connection, include = "theta")
  expect_true("fixed[1]" %in% posterior::variables(imported))
  expect_false(any(c("twice_theta", "prediction") %in% posterior::variables(imported)))
  expect_true(is.na(info(imported)$diagnostics$mean_lag1_ac[["fixed[1]"]]))
  expect_true(nzchar(info(imported)$checks_made$check_failed))
  expect_error(assert_checked_reference_posterior_draws(imported), "checks_made")
  expect_error(as_reference_posterior_draws(fit, object, connection, exclude = "fixed"),
    "Cannot exclude required")
})
