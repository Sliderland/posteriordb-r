# Reads from GitHub. Opt in with PDB_TEST_GITHUB=true; PDB_TEST_GITHUB_REPO
# picks another repository than stan-dev/posteriordb.
test_that("posteriors are read from GitHub", {
  skip_unless_env("PDB_TEST_GITHUB")
  skip_if_not_installed("gh")
  repo <- Sys.getenv("PDB_TEST_GITHUB_REPO", "stan-dev/posteriordb")
  p <- pdb_github(repo, cache_path = withr::local_tempdir())
  expect_match(pdb_version(p)$sha, "^[0-9a-f]{40}$")
  expect_true("eight_schools-eight_schools_noncentered" %in% posterior_names(p))
  po <- posterior("eight_schools-eight_schools_noncentered", p)
  expect_identical(get_data(po)$J, 8L)
  expect_match(stan_code(po), "theta_trans")
  expect_identical(posterior::ndraws(reference_posterior_draws(po)), 10000L)
})
