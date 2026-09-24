make_diagnostic_cmdstan_fit <- function(n = 2500L, nchains = 4L) {
  vals <- array(stats::rnorm(n * nchains), c(n, nchains, 1L),
                dimnames = list(NULL, NULL, "theta"))
  sampler <- array(0, c(n, nchains, 3L),
                   dimnames = list(NULL, NULL, c("divergent__", "energy__", "treedepth__")))
  called <- new.env(parent = emptyenv())
  called$sampler <- FALSE
  fit <- list(
    draws = function(inc_warmup = FALSE, format = "draws_array") posterior::as_draws_array(vals),
    sampler_diagnostics = function(inc_warmup = FALSE, format = "draws_array") {
      called$sampler <- TRUE
      posterior::as_draws_array(sampler)
    },
    metadata = function() list(iter_sampling = n, iter_warmup = 0L, thin = 1L,
                               max_depth = 10L, model_name = "test")
  )
  class(fit) <- c("CmdStanMCMC", "list")
  list(fit = fit, called = called)
}

test_that("lag-only diagnostics do not read sampler or energy diagnostics", {
  mock <- make_diagnostic_cmdstan_fit()
  report <- reference_draw_diagnostics(mock$fit, "mean_lag1_ac")
  expect_false(mock$called$sampler)
  expect_named(report, c("metrics", "thresholds", "status", "failures"))
  expect_named(report$metrics$mean_lag1_ac, "theta")
  expect_type(passes_reference_draw_checks(mock$fit, "mean_lag1_ac"), "logical")
})

test_that("diagnostics reject unknown checks and empty selections", {
  mock <- make_diagnostic_cmdstan_fit()
  expect_error(reference_draw_diagnostics(mock$fit, "made_up"), "checks")
  expect_error(reference_draw_diagnostics(mock$fit, "mean_lag1_ac", include = "missing"),
               "Unknown base variable.*include")
  expect_error(reference_draw_diagnostics(mock$fit, "mean_lag1_ac", exclude = "missing"),
               "Unknown base variable.*exclude")
})


test_that("direct-fit diagnostics and object acceptance share one policy", {
  policy <- posteriordb:::reference_draw_policy()
  expect_identical(policy$ndraws_exact, 10000L)
  expect_identical(policy$ndraws_summary_min, 10000L)
  expect_identical(policy$thresholds, list(
    ndraws = 10000L, nchains = 4L, mean_lag1_ac = 0.05,
    r_hat = 1.01, efmi = 0.2, divergent_transitions = 0L
  ))

  mock <- make_diagnostic_cmdstan_fit(n = 2000L)
  report <- reference_draw_diagnostics(mock$fit, "ndraws")
  expect_false(report$status$ndraws)
  expect_equal(report$failures$ndraws$observed, 8000L)
  expect_equal(report$failures$ndraws$required, policy$ndraws_exact)
})


test_that("all-check reports retain metrics when sampler diagnostics are unavailable", {
  mock <- make_diagnostic_cmdstan_fit(n = 2500L)
  mock$fit$sampler_diagnostics <- function(...) stop("sampler CSV diagnostics absent")
  report <- reference_draw_diagnostics(mock$fit, "all")
  expect_named(report$status, c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions"))
  expect_true(all(c("mean_lag1_ac", "r_hat") %in% names(report$metrics)))
  expect_false(report$status$efmi)
  expect_false(report$status$divergent_transitions)
  expect_identical(report$failures$efmi, "unavailable")
  expect_identical(report$failures$divergent_transitions, "unavailable")
  expect_false(passes_reference_draw_checks(mock$fit, "efmi"))
})

test_that("RStan sampler extraction can be unavailable while draw metrics report", {
  skip_if_not_installed("rstan")
  set.seed(117)
  vals <- array(stats::rnorm(500L * 4L), c(500L, 4L, 1L),
                dimnames = list(NULL, NULL, "theta"))
  draws <- posterior::as_draws_array(vals)
  expect_null(posteriordb:::extract_rstan_sampler_diagnostics(list(), strict = FALSE))
  expect_error(posteriordb:::extract_rstan_sampler_diagnostics(list(), strict = TRUE),
               "Could not extract post-warmup sampler diagnostics")
  report <- posteriordb:::reference_draw_diagnostics_from_extracted(
    list(draws = draws, sampler_diagnostics = NULL,
         metadata = list(expected_fraction_of_missing_information = NULL)),
    checks = "all"
  )
  expect_true(all(c("ndraws", "nchains", "mean_lag1_ac", "r_hat") %in%
                     names(report$metrics)))
  expect_identical(report$failures$efmi, "unavailable")
  expect_identical(report$failures$divergent_transitions, "unavailable")
})
