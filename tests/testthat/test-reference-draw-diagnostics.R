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
  testthat::local_mocked_bindings(
    rhat = function(...) stop("unexpected R-hat calculation"),
    ess_bulk = function(...) stop("unexpected bulk ESS calculation"),
    ess_tail = function(...) stop("unexpected tail ESS calculation"),
    .package = "posterior"
  )
  testthat::local_mocked_bindings(
    cmdstanr_bfmi = function(...) stop("unexpected BFMI calculation"),
    .package = "posteriordb"
  )
  report <- reference_draw_diagnostics(mock$fit, "mean_lag1_ac")
  expect_false(mock$called$sampler)
  expect_named(report, c("metrics", "thresholds", "status", "failures"))
  expect_named(report$metrics$mean_lag1_ac, "theta")
  expect_type(passes_reference_draw_checks(mock$fit, "mean_lag1_ac"), "logical")
  expect_identical(passes_reference_draw_checks(mock$fit), report$status$mean_lag1_ac)
  expect_named(report$metrics, "mean_lag1_ac")
})

test_that("selector composition excludes lp and rejects malformed selectors", {
  arr <- array(stats::rnorm(20L * 4L * 3L), c(20L, 4L, 3L),
               dimnames = list(NULL, NULL, c("alpha[1]", "beta", "lp__")))
  draws <- posterior::as_draws_array(arr)
  selected <- posteriordb:::select_reference_diagnostic_draws(
    draws, include = c("alpha", "beta"), exclude = "beta")
  expect_identical(posterior::variables(selected), "alpha[1]")
  expect_error(posteriordb:::select_reference_diagnostic_draws(draws, include = c("alpha", "alpha")),
               "duplicated")
  expect_error(posteriordb:::select_reference_diagnostic_draws(draws, include = ""),
               "nonempty")
  expect_identical(posterior::variables(posteriordb:::select_reference_diagnostic_draws(draws)),
                   c("alpha[1]", "beta"))
})

test_that("constant variables retain named unavailable metrics without dropping others", {
  set.seed(882)
  arr <- array(stats::rnorm(1000L * 4L * 2L), c(1000L, 4L, 2L),
               dimnames = list(NULL, NULL, c("varying", "constant")))
  arr[, , 2L] <- 1
  report <- posteriordb:::reference_draw_diagnostics_from_extracted(
    list(draws = posterior::as_draws_array(arr), sampler_diagnostics = NULL,
         metadata = list(expected_fraction_of_missing_information = NULL)),
    checks = "mean_lag1_ac")
  expect_named(report$metrics$mean_lag1_ac, c("varying", "constant"))
  expect_true(is.finite(report$metrics$mean_lag1_ac[["varying"]]))
  expect_true(is.na(report$metrics$mean_lag1_ac[["constant"]]))
  expect_identical(report$failures$mean_lag1_ac, "constant")
})

test_that("all diagnostics aggregate failures and E-FMI is independent of chain count gate", {
  arr <- array(seq_len(12L * 3L), c(12L, 3L, 1L),
               dimnames = list(NULL, NULL, "theta"))
  sd <- array(1, c(12L, 3L, 1L), dimnames = list(NULL, NULL, "divergent__"))
  report <- posteriordb:::reference_draw_diagnostics_from_extracted(
    list(draws = posterior::as_draws_array(arr),
         sampler_diagnostics = posterior::as_draws_array(sd),
         metadata = list(expected_fraction_of_missing_information = rep(0.2, 3L))),
    checks = c("ndraws", "nchains", "mean_lag1_ac", "efmi", "divergent_transitions"))
  expect_true(report$status$efmi)
  expect_false(report$status$nchains)
  expect_false(report$status$divergent_transitions)
  expect_true(all(c("ndraws", "nchains", "mean_lag1_ac", "divergent_transitions") %in%
                    names(report$failures)))
})

test_that("exact count and E-FMI boundaries pass", {
  arr <- array(stats::rnorm(2500L * 4L), c(2500L, 4L, 1L),
               dimnames = list(NULL, NULL, "theta"))
  report <- posteriordb:::reference_draw_diagnostics_from_extracted(
    list(draws = posterior::as_draws_array(arr), sampler_diagnostics = NULL,
         metadata = list(expected_fraction_of_missing_information = rep(0.2, 4L))),
    checks = c("ndraws", "nchains", "efmi"))
  expect_true(report$status$ndraws)
  expect_true(report$status$nchains)
  expect_true(report$status$efmi)
  expect_equal(report$metrics$ndraws, 10000L)
  boundary <- posteriordb:::reference_diagnostic_evaluation(
    list(mean_lag1_ac = c(theta = 0.05), r_hat = c(theta = 1.01)),
    c("mean_lag1_ac", "r_hat"))
  expect_true(all(unlist(boundary$status)))
  expect_false(posteriordb:::reference_diagnostic_evaluation(
    list(ndraws = 10000.5), "ndraws")$status$ndraws)
})

test_that("R-hat is computed per scalar variable and malformed arrays error", {
  arr <- array(stats::rnorm(500L * 4L * 2L), c(500L, 4L, 2L),
               dimnames = list(NULL, NULL, c("a", "b")))
  report <- posteriordb:::reference_draw_diagnostics_from_extracted(
    list(draws = posterior::as_draws_array(arr), sampler_diagnostics = NULL,
         metadata = list()), checks = "r_hat")
  expect_true(all(is.finite(report$metrics$r_hat)))
  expect_named(report$metrics$r_hat, c("a", "b"))
  expect_error(posteriordb:::reference_draw_diagnostics_from_extracted(
    list(draws = posterior::as_draws_array(arr),
         sampler_diagnostics = posterior::as_draws_array(array(0, c(2, 4, 1))),
         metadata = list()), checks = "divergent_transitions"), "dimensions must match")
})

test_that("policy boundaries collect named variable and chain failures", {
  failed <- posteriordb:::reference_diagnostic_evaluation(
    list(ndraws = 9999L, nchains = 3L,
         mean_lag1_ac = c(ok = 0.05, bad = 0.0501),
         r_hat = c(ok = 1.01, bad = 1.011),
         efmi = c(chain1 = 0.2, chain2 = 0.199),
         divergent_transitions = c(chain1 = 0L, chain2 = 1L)),
    c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions"))
  expect_identical(failed$failures$mean_lag1_ac, "bad")
  expect_identical(failed$failures$r_hat, "bad")
  expect_identical(failed$failures$efmi, "chain2")
  expect_identical(failed$failures$divergent_transitions, "chain2")
  expect_named(failed$failures, c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions"))
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
