make_diagnostic_cmdstan_fit <- function(n = 2500L, nchains = 4L) {
  testthat::skip_if_not_installed("cmdstanr")
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
