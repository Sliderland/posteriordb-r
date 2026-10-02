test_that("bibliography failure changes database status and success messages", {
  testthat::local_mocked_bindings(
    posterior_names = function(...) character(),
    check_pdb_aliases = function(...) TRUE,
    check_pdb_all_models_have_posterior = function(...) TRUE,
    check_pdb_all_data_have_posterior = function(...) TRUE,
    check_pdb_all_reference_posteriors_have_posterior = function(...) TRUE,
    check_pdb_references = function(...) TRUE
  )
  connection <- structure(list(), class = c("pdb_local", "pdb"))

  messages <- testthat::capture_messages(
    result <- withVisible(check_pdb(connection))
  )
  expect_identical(result$value, 0L)
  expect_false(result$visible)
  expect_true(any(grepl("Posterior database is ok", messages, fixed = TRUE)))

  testthat::local_mocked_bindings(
    check_pdb_references = function(...) stop("bibliography failure")
  )
  errors <- capture.output(
    messages <- testthat::capture_messages(
      result <- withVisible(check_pdb(connection))
    ), type = "message"
  )
  expect_identical(result$value, 1L)
  expect_false(result$visible)
  expect_true(any(grepl("bibliography failure", errors, fixed = TRUE)))
  expect_false(any(grepl("All bibliography elements exist", messages, fixed = TRUE)))
  expect_false(any(grepl("Posterior database is ok", messages, fixed = TRUE)))
})
