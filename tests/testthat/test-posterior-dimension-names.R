context("test-posterior-dimension-names")

test_that("posterior dimensions identify base variables, not draw shapes", {
  names <- posteriordb:::posterior_dimension_names(list(
    A = 4L, B = 2L, x = 3L, mu = 1L, scalar = 1L
  ))

  expect_identical(names, c("A", "B", "x", "mu", "scalar"))
  expect_identical(
    posteriordb:::posterior_dimension_names(list(C = 8L)),
    "C"
  )
})

test_that("invalid declarations fail before variable matching", {
  dimension_names <- posteriordb:::posterior_dimension_names

  expect_error(dimension_names(list()))
  expect_error(dimension_names(setNames(list(2L), "")))
  expect_error(dimension_names(setNames(list(2L, 3L), c("x", "x"))))
  expect_error(dimension_names(list(x = 0L)))
  expect_error(dimension_names(list(x = NA_integer_)))
  expect_error(dimension_names(list(x = 1.5)))
  expect_error(dimension_names(list(x = Inf)))
})
