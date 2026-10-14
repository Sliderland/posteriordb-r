context("test-check_posterior")


test_that("test checking a posterior", {
  skip_stan_integration()
  local_test_database()
  assert_pdb_path_exists()
  expect_silent(pdb <- pdb_test <- pdb_local())

  # Collect every failure so one broken posterior does not hide the rest.
  failures <- list()
  for (pn in test_posterior_names(pdb_test, "eight_schools")) {
    res <- tryCatch(check_pdb_posterior(posterior(pn, pdb_test), run_stan_code_checks = TRUE,
                                        verbose = FALSE),
                    error = conditionMessage)
    if (!isTRUE(res)) failures[[pn]] <- res
  }
  expect_equal(failures, list())

})


