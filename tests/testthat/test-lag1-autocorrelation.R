test_that("mean_lag1_ac averages absolute per-chain lag-1 autocorrelation", {
  set.seed(123)
  draws <- array(
    stats::rnorm(100L * 4L * 2L),
    dim = c(100L, 4L, 2L),
    dimnames = list(
      iteration = NULL,
      chain = NULL,
      variable = c("alpha", "beta")
    )
  )

  expected <- vapply(seq_len(dim(draws)[3L]), function(variable_index) {
    mean(vapply(seq_len(dim(draws)[2L]), function(chain_index) {
      abs(posterior::autocorrelation(
        draws[, chain_index, variable_index]
      )[2L])
    }, numeric(1)))
  }, numeric(1))

  expect_equal(
    posteriordb:::mean_lag1_ac(draws),
    stats::setNames(expected, c("alpha", "beta"))
  )
})

test_that("Stan diagnostics use only retained posterior variables", {
  set.seed(41)
  values <- array(
    stats::rnorm(100L * 4L * 2L),
    dim = c(100L, 4L, 2L),
    dimnames = list(NULL, NULL, c("keep", "discard"))
  )
  sampler <- array(
    0,
    dim = c(100L, 4L, 2L),
    dimnames = list(NULL, NULL, c("divergent__", "treedepth__"))
  )
  sampler[1L, 1L, "divergent__"] <- 1
  sampler[1L, 1L, "treedepth__"] <- 10

  diagnostics <- posteriordb:::compute_stan_sampling_diagnostics(
    posterior::as_draws_array(values),
    keep_dimensions = "keep",
    sampler_diagnostics = posterior::as_draws_array(sampler),
    expected_fraction_of_missing_information = rep(0.5, 4L),
    max_treedepth = 10L
  )

  expect_equal(diagnostics$diagnostic_information$names, "keep")
  for (field in c("r_hat", "effective_sample_size_bulk",
                  "effective_sample_size_tail", "mean_lag1_ac")) {
    expect_named(diagnostics[[field]], "keep")
  }
  expect_equal(diagnostics$divergent_transitions, c(1, 0, 0, 0))
  expect_equal(diagnostics$max_treedepth_exceeded, c(1, 0, 0, 0))
})

small_checked_draws <- function() {
  set.seed(308)
  values <- array(
    stats::rnorm(2500L * 4L),
    dim = c(2500L, 4L, 1L),
    dimnames = list(NULL, NULL, "theta")
  )
  diagnostics <- list(
    ndraws = 10000L,
    nchains = 4L,
    effective_sample_size_bulk = 10000,
    effective_sample_size_tail = 10000,
    r_hat = 1,
    mean_lag1_ac = 0.01,
    divergent_transitions = rep(0, 4L),
    expected_fraction_of_missing_information = rep(0.5, 4L)
  )
  draw_info <- as.reference_posterior_info(list(
    name = "diagnostic-test",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = diagnostics,
    checks_made = NULL,
    comments = "",
    added_by = "test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  as.reference_posterior_draws(
    posterior::as_draws_list(values), info = draw_info
  )
}

test_that("acceptance requires complete finite diagnostics and no divergences", {
  draws <- small_checked_draws()
  checked <- check_reference_posterior_draws(draws)
  expect_true(info(checked)$checks_made$no_divergent_transitions)
  expect_silent(assert_checked_reference_posterior_draws(checked))

  invalid <- list(
    list(field = "mean_lag1_ac", value = NA_real_),
    list(field = "mean_lag1_ac", value = numeric()),
    list(field = "r_hat", value = NA_real_),
    list(field = "expected_fraction_of_missing_information", value = NA_real_),
    list(field = "divergent_transitions", value = c(0, 0, 1, 0)),
    list(field = "divergent_transitions", value = numeric())
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

test_that("legacy lag-1 metadata is computed from the draws", {
  draws <- small_checked_draws()
  draw_info <- info(draws)
  draw_info$diagnostics$mean_lag1_ac <- NULL
  info(draws) <- draw_info
  expect_silent(check_reference_posterior_draws(draws))
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
      empty, list(diagnostics = list(ndraws = 10000L, nchains = 4L))
    ),
    "at least one variable"
  )
})

test_that("poor ESS is recorded without rejecting otherwise valid draws", {
  draws <- small_checked_draws()
  draw_info <- info(draws)
  draw_info$diagnostics$effective_sample_size_bulk <- 1
  draw_info$diagnostics$effective_sample_size_tail <- 1
  info(draws) <- draw_info
  checked <- check_reference_posterior_draws(draws)
  expect_false(info(checked)$checks_made$ess_within_bounds)
})

test_that("undefined lag-1 autocorrelation fails explicitly", {
  values <- array(
    1,
    dim = c(3L, 4L, 1L),
    dimnames = list(NULL, NULL, "theta")
  )
  expect_error(
    posteriordb:::mean_lag1_ac(values),
    "Lag-1 autocorrelation was undefined"
  )
})

test_that("ESS bounds are recorded without rejecting draws", {
  skip_if_not(
    nzchar(Sys.getenv("PDB_PATH")),
    "requires a configured PosteriorDB test database"
  )

  pdb <- posteriordb::pdb_local()
  draws <- posteriordb::reference_posterior_draws(
    "eight_schools-eight_schools_noncentered",
    pdb
  )
  draw_info <- posteriordb::info(draws)
  draw_info$diagnostics$effective_sample_size_bulk[] <- 1
  draw_info$diagnostics$effective_sample_size_tail[] <- 1
  posteriordb::info(draws) <- draw_info

  checked <- posteriordb::check_reference_posterior_draws(draws)

  expect_false(
    posteriordb::info(checked)$checks_made$ess_within_bounds
  )
})
