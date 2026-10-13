context("test-pdb-reference_posterior_summary_statistics")

test_that("Check that reference_posterior_summary_statistics work as expected", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())
  expect_silent(po <- posterior("eight_schools-eight_schools_noncentered", pdb_test))
  expect_silent(rpssi1 <- reference_posterior_info(po, type = "mean_value"))
  expect_s3_class(rpssi1, "pdb_reference_posterior_info")
  expect_silent(rpssi3 <- reference_posterior_info("eight_schools-eight_schools_noncentered", pdb_test, type = "mean_value"))
  expect_identical(rpssi1, rpssi3)

  expect_output(print(rpssi1), "Posterior: eight_schools-eight_schools_noncentered")

  expect_silent(rpm1 <- reference_posterior_summary_statistic(x = po, type = "mean_value"))
  expect_silent(rpm2 <- reference_posterior_summary_statistics(x = po))
  expect_identical(rpm1, rpm2$mean_value)

  expect_output(print(rpm1), "Posterior: eight_schools-eight_schools_noncentered")

  skip("LDA model will work from version 0.4")
  expect_silent(po <- posterior("prideprejustice_chapter-ldaK5", pdb_test))
  expect_error(rpm <- reference_posterior_summary_statistic(po, type = "mean_value"),
               regexp = "There is currently no reference posterior for this posterior.")
})
