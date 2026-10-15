# Checks a full posteriordb checkout. Opt in with PDB_PATH=<path>.
test_that("a full database passes check_pdb and its reference draws pass the checks", {
  path <- Sys.getenv("PDB_PATH")
  if (!nzchar(path)) skip("Set PDB_PATH to a posteriordb checkout to run")
  p <- pdb_local(path, cache_path = withr::local_tempdir())
  expect_identical(check_pdb(p, verbose = FALSE), 0L)
  for (name in reference_posterior_names(p)) {
    rpd <- check_reference_posterior_draws(reference_posterior_draws(name, pdb = p), error = FALSE)
    expect_null(attr(rpd, "check_failures"), label = name)
  }
})
