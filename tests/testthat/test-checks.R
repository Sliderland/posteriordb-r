test_that("independent draws pass every check and get stored-format diagnostics", {
  rpd <- checked_iid_draws()
  rpi <- info(rpd)
  expect_true(all(unlist(rpi$checks_made[names(rpi$checks_made) != "ess_within_bounds"])))
  expect_setequal(names(rpi$checks_made),
                  c("ndraws_is_10k", "nchains_is_gte_4", "r_hat_below_1_01",
                    "abs_mean_lag1_ac_below_0_05", "efmi_above_0_2", "no_divergent_transitions",
                    "ess_within_bounds"))
  d <- rpi$diagnostics
  expect_identical(d$diagnostic_information$names, posterior::variables(rpd))
  expect_identical(c(d$ndraws, d$nchains), c(10000L, 4L))
  expect_length(d$r_hat, 10)
  expect_identical(d$divergent_transitions, c(0, 0, 0, 0))
  expect_length(d$expected_fraction_of_missing_information, 4)
  expect_null(attr(rpd, "check_failures"))
})

test_that("each failed check is reported with the offending variables or chains", {
  draws <- iid_draws()
  wrap <- function(x, sampler = iid_sampler(x)) {
    rpd <- as.reference_posterior_draws(x, info = reference_info())
    attr(rpd, "sampler_diagnostics") <- sampler
    rpd
  }
  failures <- function(rpd) attr(check_reference_posterior_draws(rpd, error = FALSE), "check_failures")

  expect_identical(failures(wrap(posterior::thin_draws(draws, 2)))$ndraws, 5000L)
  expect_identical(failures(wrap(iid_draws(chains = 2, iterations = 5000)))$nchains, 2L)
  expect_identical(failures(wrap(draws, iid_sampler(draws, divergent = 3)))$divergent_transitions, "chain1")

  shifted <- draws
  shifted[, 1, "mu"] <- shifted[, 1, "mu"] + 1
  expect_identical(failures(wrap(shifted))$r_hat, "mu")

  correlated <- draws
  for (chain in 1:4) correlated[, chain, "tau"] <- cumsum(correlated[, chain, "tau"])
  expect_true("tau" %in% failures(wrap(correlated))$mean_lag1_ac)

  constant <- draws
  constant[, , "mu"] <- 1
  expect_identical(failures(wrap(constant))$r_hat, "mu")

  sticky <- iid_sampler(draws)
  sticky[, , "energy__"] <- apply(sticky[, , "energy__"], 2, cumsum)
  expect_identical(failures(wrap(draws, sticky))$efmi, paste0("chain", 1:4))

  expect_identical(failures(wrap(draws, sampler = NULL))$divergent_transitions, "unavailable")
  expect_error(check_reference_posterior_draws(wrap(shifted)), "r_hat \\(mu\\)")
})

test_that("analytical draws only need the draw count", {
  rpd <- as.reference_posterior_draws(iid_draws(chains = 1, iterations = 10000),
                                      info = reference_info(method = "analytical"))
  rpd <- check_reference_posterior_draws(rpd)
  expect_identical(info(rpd)$checks_made, list(ndraws_is_10k = TRUE))
})

test_that("stored reference posteriors are checked from their draws", {
  p <- local_pdb()
  rpd <- check_reference_posterior_draws(reference_posterior_draws("8schools", pdb = p), error = FALSE)
  # The fixture keeps 100 of every 1000 draws per chain; the rest passes.
  expect_identical(names(attr(rpd, "check_failures")), "ndraws")
  expect_true(info(rpd)$checks_made$no_divergent_transitions)
})

test_that("subsetting and thinning keep the class and clear the checks", {
  rpd <- checked_iid_draws()
  sub <- subset(rpd, variable = c("mu", "tau"))
  expect_s3_class(sub, "pdb_reference_posterior_draws")
  expect_identical(posterior::variables(sub), c("mu", "tau"))
  expect_null(info(sub)$checks_made)
  thin <- posterior::thin_draws(rpd, 2)
  expect_s3_class(thin, "pdb_reference_posterior_draws")
  expect_identical(posterior::ndraws(thin), 5000L)
  expect_null(info(thin)$checks_made)
  expect_false(is.null(attr(thin, "sampler_diagnostics")))
})

test_that("summary statistics are computed from checked draws", {
  rpd <- checked_iid_draws()
  mv <- compute_reference_posterior_summary_statistic(rpd, "mean_value")
  msv <- compute_summary_statistic(rpd, "mean_squared_value")
  expect_identical(mv$names, posterior::variables(rpd))
  expect_equal(mv$mean_value[1], mean(posterior::extract_variable(rpd, "theta[1]")))
  expect_equal(msv$mean_squared_value[1], mean(posterior::extract_variable(rpd, "theta[1]")^2))
  expect_true(info(mv)$checks_made$ndraws_is_gte_10k)
  expect_match(info(mv)$versions$r_summary_statistic, "posterior R package")
  bad <- as.reference_posterior_draws(iid_draws(iterations = 100), info = reference_info())
  expect_error(compute_reference_posterior_summary_statistic(bad), "failed the checks")
})

test_that("fit diagnostics are reported before import", {
  fit <- mock_cmdstan_fit()
  report <- reference_draw_diagnostics(fit)
  expect_true(all(unlist(report$status)))
  expect_named(report$metrics$r_hat, c(paste0("theta[", 1:8, "]"), "mu", "tau"))
  expect_true(passes_reference_draw_checks(fit, "mean_lag1_ac"))
  slow <- mock_cmdstan_fit(iid_draws(chains = 2))
  expect_false(passes_reference_draw_checks(slow))
  expect_identical(reference_draw_diagnostics(slow, checks = "nchains")$failures, list(nchains = 2L))
  expect_named(reference_draw_diagnostics(fit, include = "mu")$metrics$r_hat, "mu")
  expect_error(reference_draw_diagnostics(fit, include = "sigma"), "Unknown variable")
  expect_error(reference_draw_diagnostics(fit, checks = "ess"))
})
