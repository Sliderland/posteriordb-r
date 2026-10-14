test_that("draw coercion retains explicit connections", {
  draws <- posterior::as_draws_list(list(
    list(alpha = 1:4, beta = 5:8),
    list(alpha = 9:12, beta = 13:16)
  ))
  ri <- as.reference_posterior_info(list(
    name = "connection-reference",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = 8L),
    checks_made = NULL,
    comments = NULL,
    added_by = "Test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  connection <- structure(list(), class = c("pdb_local", "pdb"))

  expect_identical(
    as.pdb_reference_posterior_draws,
    as.reference_posterior_draws
  )
  x <- as.reference_posterior_draws(draws, info = ri, pdb = connection)
  expect_identical(pdb(x), connection)
  expect_identical(pdb(subset(x, variable = "alpha")), connection)
  expect_identical(pdb(posterior::thin_draws(x, 2L)), connection)
  expect_null(pdb(as.reference_posterior_draws(draws, info = ri)))
  expect_null(pdb(as.reference_posterior_draws(draws, info = ri, pdb = NULL)))
  expect_error(
    as.reference_posterior_draws(draws, info = ri, pdb = "invalid"),
    "Must inherit from class 'pdb'"
  )
})
