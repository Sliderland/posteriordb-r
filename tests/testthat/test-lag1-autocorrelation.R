test_that("lag-1 autocorrelation agrees with posterior package", {
  withr::local_seed(123)
  draws <- array(
    stats::rnorm(2500L * 4L * 2L),
    dim = c(2500L, 4L, 2L),
    dimnames = list(
      iteration = NULL,
      chain = NULL,
      variable = c("alpha", "beta")
    )
  )
  # Alpha is independent; beta has positive and negative AR(1) chains.
  coefficients <- c(0.9, 0.9, -0.9, -0.9)
  for (chain_index in seq_along(coefficients)) {
    draws[, chain_index, "beta"] <- stats::filter(
      draws[, chain_index, "beta"],
      coefficients[chain_index],
      method = "recursive"
    )
  }

  expected <- vapply(
    seq_len(dim(draws)[3L]),
    function(variable_index) {
      mean(vapply(
        seq_len(dim(draws)[2L]),
        function(chain_index) {
          lag1 <- posterior::autocorrelation(
            draws[, chain_index, variable_index]
          )[2L]
          expect_equal(
            unname(posteriordb:::mean_lag1_ac(
              draws[, chain_index, variable_index, drop = FALSE]
            )),
            abs(lag1),
            tolerance = 1e-12
          )
          abs(lag1)
        },
        numeric(1)
      ))
    },
    numeric(1)
  )

  expect_equal(
    posteriordb:::mean_lag1_ac(draws),
    stats::setNames(expected, c("alpha", "beta")),
    tolerance = 1e-12
  )
})

test_that("legacy lag-1 checks are computed from the draws", {
  draws <- small_checked_draws()
  draw_info <- info(draws)
  draw_info$diagnostics$mean_lag1_ac <- NULL
  info(draws) <- draw_info
  expect_silent(checked <- check_reference_posterior_draws(draws))
  expect_true(info(checked)$checks_made$abs_mean_lag1_ac_below_0_05)

  for (chain_index in seq_along(draws)) {
    draws[[chain_index]]$theta <- seq_along(draws[[chain_index]]$theta)
  }
  expect_error(
    check_reference_posterior_draws(draws),
    "Assertion on \'mean_lag1_ac\'"
  )
})

test_that("legacy draws fail when lag-1 autocorrelation is undefined", {
  draws <- small_checked_draws()
  draw_info <- info(draws)
  draw_info$diagnostics$mean_lag1_ac <- NULL
  info(draws) <- draw_info
  for (chain_index in seq_along(draws)) {
    draws[[chain_index]]$theta[] <- chain_index
  }
  expect_error(
    check_reference_posterior_draws(draws),
    "Lag-1 autocorrelation was undefined"
  )
})

# Stored draws with a varying `theta` and a second variable `fixed`.
stored_draws_with_fixed <- function(fixed, lag1 = c(0.01, NA), r_hat = c(1, NA)) {
  withr::local_seed(123)
  values <- array(
    stats::rnorm(2500L * 4L * 2L),
    dim = c(2500L, 4L, 2L),
    dimnames = list(NULL, NULL, c("theta", "fixed"))
  )
  values[,, "fixed"] <- fixed
  draw_info <- info(small_checked_draws())
  draw_info$diagnostics$mean_lag1_ac <- lag1
  draw_info$diagnostics$r_hat <- r_hat
  as.reference_posterior_draws(posterior::as_draws_list(values), info = draw_info)
}

test_that("stored draws accept undefined metrics only for a constant variable", {
  expect_warning(
    checked <- check_reference_posterior_draws(stored_draws_with_fixed(1)),
    "Constant variables.*fixed$"
  )
  expect_true(info(checked)$checks_made$abs_mean_lag1_ac_below_0_05)
  expect_true(info(checked)$checks_made$r_hat_below_1_01)

  legacy <- stored_draws_with_fixed(1, lag1 = NULL)
  expect_warning(checked <- check_reference_posterior_draws(legacy), "Constant variables")
  expect_true(info(checked)$checks_made$abs_mean_lag1_ac_below_0_05)

  # The same missing metrics are rejected when `fixed` is not constant.
  different <- rep(1:4, each = 2500L)
  expect_error(check_reference_posterior_draws(stored_draws_with_fixed(different)),
               "mean_lag1_ac")
  expect_error(
    suppressWarnings(
      check_reference_posterior_draws(stored_draws_with_fixed(1, lag1 = c(NA, NA)))
    ),
    "mean_lag1_ac"
  )
})

test_that("stored draws in which every variable is constant fail", {
  draws <- small_checked_draws()
  for (chain_index in seq_along(draws)) draws[[chain_index]]$theta[] <- 1
  expect_error(suppressWarnings(check_reference_posterior_draws(draws)), "mean_lag1_ac")
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

test_that("lag-1 autocorrelation needs at least two iterations", {
  values <- array(1, dim = c(1L, 4L, 1L), dimnames = list(NULL, NULL, "theta"))
  expect_error(posteriordb:::mean_lag1_ac(values), "At least two iterations")
})
