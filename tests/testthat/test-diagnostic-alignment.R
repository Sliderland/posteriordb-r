#Helpers: helper-diagnostics.R

test_that("diagnostic labels must identify the retained variables and chains", {
  x <- alignment_reference_draws()
  expect_silent(check_reference_posterior_draws(x))
  for (field in c(
    "mean_lag1_ac",
    "r_hat",
    "expected_fraction_of_missing_information",
    "divergent_transitions"
  )) {
    malformed <- x
    metadata <- info(x)
    names(metadata$diagnostics[[field]])[1] <- "unrelated"
    info(malformed) <- metadata
    expect_error(check_reference_posterior_draws(malformed), field)
    expect_error(check_summary_statistics_draws(malformed), field)
    metadata$checks_made <- bundle_acceptance_flags()
    info(malformed) <- metadata
    expect_error(assert_checked_reference_posterior_draws(malformed), field)
  }
  metadata <- info(x)
  metadata$diagnostics$diagnostic_information$names <- c("wrong", "beta")
  info(x) <- metadata
  expect_error(check_reference_posterior_draws(x), "diagnostic_information")
})

test_that("diagnostic labels cannot repeat variables or chains", {
  x <- alignment_reference_draws()
  expect_silent(check_reference_posterior_draws(x))
  for (field in c(
    "mean_lag1_ac",
    "r_hat",
    "expected_fraction_of_missing_information",
    "divergent_transitions"
  )) {
    malformed <- x
    metadata <- info(x)
    labels <- names(metadata$diagnostics[[field]])
    names(metadata$diagnostics[[field]])[1L] <- labels[2L]
    info(malformed) <- metadata
    expect_error(check_reference_posterior_draws(malformed), field)
    expect_error(check_summary_statistics_draws(malformed), field)
    metadata$checks_made <- bundle_acceptance_flags()
    info(malformed) <- metadata
    expect_error(assert_checked_reference_posterior_draws(malformed), field)
  }
  metadata <- info(x)
  metadata$diagnostics$diagnostic_information$names <- c("alpha", "alpha")
  info(x) <- metadata
  expect_error(check_reference_posterior_draws(x), "diagnostic_information")
})

test_that("legacy positional metrics and reordered named metrics remain supported", {
  x <- alignment_reference_draws()
  metadata <- info(x)
  fields <- c(
    "mean_lag1_ac",
    "r_hat",
    "expected_fraction_of_missing_information",
    "divergent_transitions"
  )
  for (field in fields) {
    metadata$diagnostics[[field]] <- rev(metadata$diagnostics[[field]])
  }
  info(x) <- metadata
  expect_silent(check_reference_posterior_draws(x))
  metadata$diagnostics$diagnostic_information <- NULL
  for (field in fields) {
    metadata$diagnostics[[field]] <- unname(metadata$diagnostics[[field]])
  }
  info(x) <- metadata
  expect_silent(check_reference_posterior_draws(x))
})

test_that("mislabelled ESS gives a false flag instead of an error", {
  x <- alignment_reference_draws()
  metadata <- info(x)
  metadata$diagnostics$effective_sample_size_bulk <- c(
    wrong = 10000,
    beta = 10000
  )
  info(x) <- metadata
  checked <- check_reference_posterior_draws(x)
  expect_false(info(checked)$checks_made$ess_within_bounds)
})

test_that("acceptance requires complete finite diagnostics and no divergences", {
  draws <- small_checked_draws()
  checked <- check_reference_posterior_draws(draws)
  expect_true(info(checked)$checks_made$no_divergent_transitions)
  expect_silent(assert_checked_reference_posterior_draws(checked))
  for (c in info(checked)$checks_made) {
    expect_true(c)
  }

  invalid <- list(
    list(field = "mean_lag1_ac", value = NA_real_),
    list(field = "mean_lag1_ac", value = numeric()),
    list(field = "r_hat", value = NA_real_),
    list(field = "expected_fraction_of_missing_information", value = NA_real_),
    list(field = "divergent_transitions", value = c(0, 0, 1, 0)),
    list(field = "divergent_transitions", value = numeric()),
    list(
      field = "expected_fraction_of_missing_information",
      value = c(Inf, 0.5, 0.5, 0.5)
    ),
    list(
      field = "expected_fraction_of_missing_information",
      value = c(Inf, 0.5, 0.5)
    ),
    list(field = "r_hat", value = c(1.1)),
    list(field = "r_hat", value = c(-Inf)),
    list(field = "r_hat", value = c(Inf)),
    list(field = "r_hat", value = c()),
    list(field = "r_hat", value = c(1, 1))
  )
  for (case in invalid) {
    altered <- draws
    draw_info <- info(altered)
    draw_info$diagnostics[case$field] <- list(case$value)
    info(altered) <- draw_info
    expect_error(
      check_reference_posterior_draws(altered),
      case$field,
      info = paste("field", case$field, "should fail")
    )
  }
})

test_that("summary checks also reject divergent transitions", {
  draws <- small_checked_draws()
  draw_info <- info(draws)
  draw_info$diagnostics$divergent_transitions[1L] <- 1
  info(draws) <- draw_info
  expect_error(check_summary_statistics_draws(draws), "divergent_transitions")
})

test_that("recorded draw and chain counts must match the draws", {
  draws <- small_checked_draws()
  for (field in c("ndraws", "nchains")) {
    altered <- draws
    draw_info <- info(altered)
    draw_info$diagnostics[[field]] <- 20L
    info(altered) <- draw_info
    expect_error(
      check_reference_posterior_draws(altered),
      paste0("Recorded ", field, " does not match")
    )
  }
})

test_that("draw acceptance rejects an empty variable set", {
  empty <- posterior::as_draws_array(
    array(numeric(), dim = c(2500L, 4L, 0L))
  )
  expect_error(
    posteriordb:::assert_diagnostic_draw_counts(
      empty,
      list(diagnostics = list(ndraws = 10000L, nchains = 4L))
    ),
    "at least one variable"
  )
})

test_that("a stored metric must have one value per variable or chain", {
  for (field in c("r_hat", "expected_fraction_of_missing_information")) {
    draws <- alignment_reference_draws()
    draw_info <- info(draws)
    draw_info$diagnostics[[field]] <- unname(draw_info$diagnostics[[field]][1])
    info(draws) <- draw_info
    expect_error(check_reference_posterior_draws(draws), field)
  }
})

test_that("every acceptance flag is set for valid draws", {
  checked <- check_reference_posterior_draws(small_checked_draws())
  checks <- c(
    "ndraws_is_10k",
    "nchains_is_gte_4",
    "abs_mean_lag1_ac_below_0_05",
    "r_hat_below_1_01",
    "efmi_above_0_2",
    "no_divergent_transitions",
    "ess_within_bounds"
  )
  expect_true(all(unlist(info(checked)$checks_made)))
  for (c in checks) {
    expect_true(info(checked)$checks_made[[c]])
  }
})

test_that("ESS outside the bounds is recorded without rejecting draws", {
  draws <- small_checked_draws()
  cases <- list(
    list(field = "effective_sample_size_bulk", value = 1),
    list(field = "effective_sample_size_tail", value = 1),
    list(field = "effective_sample_size_bulk", value = 1e6),
    list(field = "effective_sample_size_tail", value = 1e6)
  )
  for (case in cases) {
    altered <- draws
    draw_info <- info(altered)
    draw_info$diagnostics[[case$field]] <- case$value
    info(altered) <- draw_info
    checked <- check_reference_posterior_draws(altered)
    expect_false(
      info(checked)$checks_made$ess_within_bounds,
      info = paste(case$field, "=", case$value)
    )
    expect_silent(assert_checked_reference_posterior_draws(checked))
  }
})

# test_that("poor ESS tail is recorded without rejecting otherwise valid draws", {
#   draws <- small_checked_draws()
#   draw_info <- info(draws)
#   draw_info$diagnostics$effective_sample_size_tail <- 1
#   info(draws) <- draw_info
#   checked <- check_reference_posterior_draws(draws)
#   expect_false(info(checked)$checks_made$ess_within_bounds)
#   expect_silent(assert_checked_reference_posterior_draws(checked))
# })

# test_that("poor ESS bulk is recorded without rejecting otherwise valid draws", {
#   draws <- small_checked_draws()
#   draw_info <- info(draws)
#   draw_info$diagnostics$effective_sample_size_bulk <- 1
#   info(draws) <- draw_info
#   checked <- check_reference_posterior_draws(draws)
#   expect_false(info(checked)$checks_made$ess_within_bounds)
#   expect_silent(assert_checked_reference_posterior_draws(checked))
# })

# test_that("poor ESS (both) is recorded without rejecting otherwise valid draws", {
#   draws <- small_checked_draws()
#   draw_info <- info(draws)
#   draw_info$diagnostics$effective_sample_size_bulk <- 1
#   draw_info$diagnostics$effective_sample_size_tail <- 1
#   info(draws) <- draw_info
#   checked <- check_reference_posterior_draws(draws)
#   expect_false(info(checked)$checks_made$ess_within_bounds)
#   expect_silent(assert_checked_reference_posterior_draws(checked))
# })
