context("test-posterior-dimension-names")

test_that("posterior dimensions identify base variables, not draw shapes", {
  names <- posteriordb:::posterior_dimension_names(list(
    A = 4L, B = 2L, x = 3L, mu = 1L, scalar = 1L
  ))

  expect_identical(names, c("A", "B", "x", "mu", "scalar"))
  expect_identical(posteriordb:::posterior_dimension_names(c(mu = 1, theta = 2)), c("mu", "theta"))
  expect_identical(
    posteriordb:::posterior_dimension_names(list(C = 8L)),
    "C"
  )
})

test_that("invalid declarations fail before variable matching", {
  dimension_names <- posteriordb:::posterior_dimension_names

  expect_error(dimension_names(list()), "Must have length >= 1")
  expect_error(dimension_names(setNames(list(2L), "")), "Assertion on 'dimensions' failed")
  expect_error(dimension_names(setNames(list(2L, 3L), c("x", "x"))), "duplicated values")
  expect_error(dimension_names(list(x = 0L)), "must be one positive integer")
  expect_error(dimension_names(list(x = NA_integer_)), "must be one positive integer")
  expect_error(dimension_names(list(x = 1.5)), "must be one positive integer")
  expect_error(dimension_names(list(x = Inf)), "must be one positive integer")
})


test_that("free-coordinate count selection and representations stay canonical", {
  coordinates <- c("weights.1", "weights.2", "M.1.1", "M.2.1", "theta")
  expect_identical(unconstrained_parameter_counts(coordinates),
    list(weights = 2L, M = 2L, theta = 1L))
  expect_identical(unconstrained_parameter_counts(coordinates, include = "weights"),
    list(weights = 2L))
  expect_identical(unconstrained_parameter_counts(coordinates, exclude = "weights"),
    list(M = 2L, theta = 1L))
  expect_error(unconstrained_parameter_counts(coordinates, include = "fixed"), "Unknown")
  expect_error(unconstrained_parameter_counts(coordinates, include = character()), "no unconstrained")
  expect_error(unconstrained_parameter_counts(character()), "No unconstrained")
  expect_equal(validate_import_dimensions(c(theta = 1, M = 2)), list(theta = 1L, M = 2L))
  expect_error(validate_import_dimensions(list(theta = c(2L, 3L))), "one positive integer")
  for (include in list(NULL, "all")) {
    for (exclude in list(NULL, character(), "none", "lp__")) {
      expect_identical(unconstrained_parameter_counts(coordinates, include, exclude),
        list(weights = 2L, M = 2L, theta = 1L))
    }
  }
  expect_error(unconstrained_parameter_counts(coordinates, include = "none"), "no unconstrained")
  expect_error(unconstrained_parameter_counts(coordinates, exclude = "all"), "no unconstrained")
  expect_error(unconstrained_parameter_counts(coordinates, include = "weights", exclude = "weights"),
    "both.*include.*exclude")
  fit <- structure(list(unconstrain_draws = function() posterior::as_draws_array(
    array(1:10, c(2, 1, 5), dimnames = list(NULL, NULL, coordinates)))), class = "CmdStanMCMC")
  expect_identical(infer_unconstrained_parameter_counts_from_fit(fit, include = "all", exclude = "none"),
    list(weights = 2L, M = 2L, theta = 1L))
})
