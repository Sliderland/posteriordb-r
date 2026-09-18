context("test-posterior-dimension-names")

test_that("dimension names follow Stan indexing order", {
  names <- posteriordb:::posterior_dimension_names(list(
    A = c(2L, 2L), B = c(1L, 2L), x = 3L,
    mu = 1L, scalar = integer(0)
  ))

  expect_identical(names, c(
    "A[1,1]", "A[2,1]", "A[1,2]", "A[2,2]",
    "B[1,1]", "B[1,2]", "x[1]", "x[2]", "x[3]",
    "mu", "scalar"
  ))
  expect_identical(
    posteriordb:::posterior_dimension_names(list(C = c(2L, 1L, 2L))),
    c("C[1,1,1]", "C[2,1,1]", "C[1,1,2]", "C[2,1,2]")
  )
})

test_that("invalid declarations fail before variable matching", {
  dimension_names <- posteriordb:::posterior_dimension_names

  expect_error(dimension_names(list()))
  expect_error(dimension_names(setNames(list(2L), "")))
  expect_error(dimension_names(setNames(list(2L, 3L), c("x", "x"))))
  expect_error(dimension_names(list(x = c(2L, 0L))))
  expect_error(dimension_names(list(x = NA_integer_)))
  expect_error(dimension_names(list(x = 1.5)))
  expect_error(dimension_names(list(x = .Machine$integer.max + 1)))
})
