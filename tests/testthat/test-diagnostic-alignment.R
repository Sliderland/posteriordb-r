alignment_reference_draws <- function() {
  set.seed(412)
  values <- posterior::as_draws_array(array(rnorm(20000), c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("alpha", "beta"))))
  metadata <- as.reference_posterior_info(list(
    name = "alignment-reference",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = list(ndraws = 10000L, nchains = 4L,
      diagnostic_information = list(names = c("alpha", "beta")),
      effective_sample_size_bulk = c(alpha = 10000, beta = 10000),
      effective_sample_size_tail = c(alpha = 10000, beta = 10000),
      mean_lag1_ac = c(alpha = .05, beta = .05),
      r_hat = c(alpha = 1.01, beta = 1.01),
      expected_fraction_of_missing_information = stats::setNames(rep(.2, 4), paste0("chain", 1:4)),
      divergent_transitions = stats::setNames(rep(0, 4), paste0("chain", 1:4))),
    checks_made = NULL, comments = NULL, added_by = "Test",
    added_date = Sys.Date(), versions = NULL))
  as.reference_posterior_draws(posterior::as_draws_list(values), metadata)
}

test_that("legacy positional metrics and reordered named metrics remain supported", {
  x <- alignment_reference_draws()
  metadata <- info(x)
  fields <- c("mean_lag1_ac", "r_hat", "expected_fraction_of_missing_information",
              "divergent_transitions")
  for (field in fields) metadata$diagnostics[[field]] <- rev(metadata$diagnostics[[field]])
  info(x) <- metadata
  expect_silent(check_reference_posterior_draws(x))
  metadata$diagnostics$diagnostic_information <- NULL
  for (field in fields) metadata$diagnostics[[field]] <- unname(metadata$diagnostics[[field]])
  info(x) <- metadata
  expect_silent(check_reference_posterior_draws(x))
  metadata$diagnostics$effective_sample_size_bulk <- c(wrong = 10000, beta = 10000)
  info(x) <- metadata
  checked <- check_reference_posterior_draws(x)
  expect_false(info(checked)$checks_made$ess_within_bounds)
})
