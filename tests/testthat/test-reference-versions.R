version_info_fixture <- function(versions) {
  as.pdb_reference_posterior_info(list(
    name = "version-test",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = NULL,
    checks_made = NULL,
    comments = "Version metadata test",
    added_by = "test",
    added_date = Sys.Date(),
    versions = versions
  ))
}

test_that("fit version metadata satisfies the reference-info schema", {
  versions <- posteriordb:::stan_fit_sampling_versions(list(
    cmdstanr_version = "cmdstanr test",
    stan_version = "Stan 2.40.0",
    cmdstan_version = "CmdStan 2.40.0"
  ))
  expect_silent(version_info_fixture(versions))
  expect_true(all(
    c("r_Makevars", "r_version", "r_session") %in% names(versions)
  ))
  expect_identical(versions$stan_version, "Stan 2.40.0")
  expect_null(versions$rstan_version)
})
