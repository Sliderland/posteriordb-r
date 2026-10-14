test_that("fit import preserves constant coordinates in a rejected short fit", {
  fit <- constrained_parameter_fit()
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  object <- structure(
    list(
      name = "constrained-posterior",
      reference_posterior_name = NULL,
      dimensions = infer_unconstrained_parameter_counts_from_fit(fit)
    ),
    class = "pdb_posterior"
  )
  imported <- as_reference_posterior_draws(
    fit,
    object,
    connection,
    include = "theta"
  )
  expect_identical(
    posterior::variables(as_reference_posterior_draws(
      fit,
      object,
      connection,
      exclude = "all"
    )),
    posterior::variables(imported)
  )
  expect_true("fixed[1]" %in% posterior::variables(imported))
  expect_false(any(
    c("twice_theta", "prediction") %in% posterior::variables(imported)
  ))
  expect_true(is.na(info(imported)$diagnostics$mean_lag1_ac[["fixed[1]"]]))
  expect_true(nzchar(info(imported)$checks_made$check_failed))
  expect_error(
    assert_checked_reference_posterior_draws(imported),
    "checks_made"
  )
  expect_error(
    as_reference_posterior_draws(fit, object, connection, exclude = "fixed"),
    "Cannot exclude required"
  )
})
