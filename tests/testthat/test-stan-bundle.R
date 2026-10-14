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
