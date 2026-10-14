test_that("posterior dimensions identify base variables, not draw shapes", {
  names <- posteriordb:::posterior_dimension_names(list(
    A = 4L,
    B = 2L,
    x = 3L,
    mu = 1L,
    scalar = 1L
  ))

  expect_identical(names, c("A", "B", "x", "mu", "scalar"))
  expect_identical(
    posteriordb:::posterior_dimension_names(c(mu = 1, theta = 2)),
    c("mu", "theta")
  )
  expect_identical(
    posteriordb:::posterior_dimension_names(list(C = 8L)),
    "C"
  )
})

test_that("invalid declarations fail before variable matching", {
  dimension_names <- posteriordb:::posterior_dimension_names

  expect_error(dimension_names(list()), "Must have length >= 1")
  expect_error(
    dimension_names(setNames(list(2L), "")),
    "Assertion on 'dimensions' failed"
  )
  expect_error(
    dimension_names(setNames(list(2L, 3L), c("x", "x"))),
    "duplicated values"
  )
  expect_error(dimension_names(list(x = 0L)), "must be one positive integer")
  expect_error(
    dimension_names(list(x = NA_integer_)),
    "must be one positive integer"
  )
  expect_error(dimension_names(list(x = 1.5)), "must be one positive integer")
  expect_error(dimension_names(list(x = Inf)), "must be one positive integer")
  expect_error(dimension_names(list(x = TRUE)), "must be one positive integer")
})
