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
