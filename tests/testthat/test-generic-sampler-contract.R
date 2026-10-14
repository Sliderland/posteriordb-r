test_that("optional sampler metrics remain independent and name undefined chains", {
  skip_if_not_installed("cmdstanr")
  values <- posterior::as_draws_array(array(seq_len(24), c(12, 2, 1),
    dimnames = list(NULL, NULL, "theta")))
  sampler <- array(0, c(12, 2, 1), dimnames = list(NULL, NULL, "energy__"))
  sampler[, 1, 1] <- rep(c(0, 1), 6)
  fit <- structure(list(
    draws = function(...) values,
    sampler_diagnostics = function(...) posterior::as_draws_array(sampler),
    metadata = function() list(iter_sampling = 12L, iter_warmup = 0L)
  ), class = "CmdStanMCMC")
  report <- reference_draw_diagnostics(fit, checks = c("efmi", "divergent_transitions"))
  expect_gt(report$metrics$efmi[["chain1"]], .2)
  expect_true(is.na(report$metrics$efmi[["chain2"]]))
  expect_identical(report$failures$efmi, "chain2")
  expect_identical(report$failures$divergent_transitions, "unavailable")
  expect_false(passes_reference_draw_checks(fit, "efmi"))
  sampler <- array(0, c(10, 2, 1), dimnames = list(NULL, NULL, "energy__"))
  expect_error(reference_draw_diagnostics(fit, "efmi"), "inconsistent.*dimensions")
})
