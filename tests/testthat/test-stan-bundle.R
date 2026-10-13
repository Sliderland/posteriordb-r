test_that("a well-sampled RStan fit is accepted, bundled, and written", {
  fit <- stan_bundle_rstan_fit("accepted")
  saved <- stan_bundle_saved_draws(fit)
  bundle <- stan_bundle_create(fit, "accepted")

  expect_true(all(unlist(bundle$diagnostics$status)))
  expect_null(info(bundle$reference_draws)$checks_made$check_failed)
  expect_identical(
    bundle$posterior$dimensions,
    list(theta_trans = 8L, mu = 1L, tau = 1L)
  )
  expect_equal(
    posterior::as_draws_array(bundle$reference_draws),
    saved,
    ignore_attr = TRUE
  )

  database <- stan_bundle_pdb()
  result <- suppressMessages(write_pdb(bundle, database))
  expect_true(result$reference_draws_written)
  stored <- reference_posterior_draws(posterior(
    bundle$posterior$name,
    database
  ))
  expect_silent(assert_checked_reference_posterior_draws(stored))
  expect_equal(posterior::as_draws_array(stored), saved, ignore_attr = TRUE)

  imported <- stan_bundle_import(fit, "accepted")
  expect_null(info(imported)$checks_made$check_failed)
  expect_silent(assert_checked_reference_posterior_draws(imported))
})

test_that("a poorly sampled RStan fit is marked failed and its draws are not written", {
  fit <- stan_bundle_rstan_fit("rejected")
  bundle <- stan_bundle_create(fit, "rejected")

  expect_false(bundle$diagnostics$status$divergent_transitions)
  expect_false(bundle$diagnostics$status$mean_lag1_ac)
  expect_true(bundle$diagnostics$status$ndraws)
  expect_match(
    info(bundle$reference_draws)$checks_made$check_failed,
    "mean_lag1_ac.*divergent_transitions"
  )

  database <- stan_bundle_pdb()
  result <- suppressMessages(write_pdb(bundle, database))
  expect_false(result$reference_draws_written)
  expect_length(
    list.files(
      pdb_file_path(database, "reference_posteriors"),
      recursive = TRUE
    ),
    0L
  )

  imported <- stan_bundle_import(fit, "rejected")
  expect_match(info(imported)$checks_made$check_failed, "mean_lag1_ac")
  expect_error(
    assert_checked_reference_posterior_draws(imported),
    "checks_made"
  )
})

test_that("a poorly sampled CmdStanR fit is rejected by import", {
  fit <- stan_bundle_cmdstan_fit("rejected")
  imported <- stan_bundle_import(fit, "rejected")

  expect_match(info(imported)$checks_made$check_failed, "mean_lag1_ac")
  expect_gt(sum(info(imported)$diagnostics$divergent_transitions), 0)
  expect_equal(info(imported)$diagnostics$ndraws, 10000L)
})

# This test pins a known limitation, not the intended behaviour: the fit is
# sampled well, and every failing variable is constant by construction. When
# constant variables are exempted from the lag-1 and R-hat checks, this fit
# should be accepted and the expectations below should be reversed.
structural_constants <- c(
  "L_Omega[1,1]",
  "L_Omega[1,2]",
  "L_Omega[1,3]",
  "L_Omega[2,3]",
  "Omega[1,1]"
)

test_that("structural constants alone reject a well-sampled RStan fit", {
  fit <- stan_bundle_rstan_fit("constrained")
  constant <- stan_bundle_constant_variables(fit)
  report <- suppressWarnings(reference_draw_diagnostics(fit))

  expect_identical(
    names(Filter(isFALSE, report$status)),
    c("mean_lag1_ac", "r_hat")
  )
  for (check in c("mean_lag1_ac", "r_hat")) {
    expect_true(all(structural_constants %in% report$failures[[check]]))
    # No variable that actually varies fails either check.
    expect_true(all(report$failures[[check]] %in% constant))
  }
  # The correlation diagonal is constant only up to rounding, so its metrics
  # are computed on noise and it passes or fails by chance.
  expect_true(all(c("Omega[2,2]", "Omega[3,3]") %in% constant))

  bundle <- stan_bundle_create(fit, "constrained")
  expect_identical(
    info(bundle$reference_draws)$checks_made$check_failed,
    "mean_lag1_ac, r_hat"
  )
  # The user cannot work around it: the parameter cannot be left out.
  expect_error(
    stan_bundle_create(fit, "constrained", exclude = "L_Omega"),
    "Cannot exclude"
  )
})

###
# CmdStanR tests kept for when CmdStanR bundle support is implemented
#

# test_that("a well-sampled CmdStanR fit is accepted by import", {
#   fit <- stan_bundle_cmdstan_fit("accepted")
#   imported <- stan_bundle_import(fit, "accepted")

#   expect_null(info(imported)$checks_made$check_failed)
#   expect_silent(assert_checked_reference_posterior_draws(imported))
#   expect_equal(info(imported)$diagnostics$ndraws, 10000L)
#   expect_equal(
#     posterior::as_draws_array(imported),
#     stan_bundle_saved_draws(fit$draws()),
#     ignore_attr = TRUE
#   )
# })

# test_that("structural constants alone reject a well-sampled CmdStanR fit", {
#   fit <- stan_bundle_cmdstan_fit("constrained")
#   constant <- stan_bundle_constant_variables(fit$draws())
#   report <- suppressWarnings(reference_draw_diagnostics(fit))

#   expect_identical(
#     names(Filter(isFALSE, report$status)),
#     c("mean_lag1_ac", "r_hat")
#   )
#   for (check in c("mean_lag1_ac", "r_hat")) {
#     expect_true(all(structural_constants %in% report$failures[[check]]))
#     expect_true(all(report$failures[[check]] %in% constant))
#   }

#   imported <- stan_bundle_import(fit, "constrained")
#   expect_match(info(imported)$checks_made$check_failed, "mean_lag1_ac")
# })
