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
