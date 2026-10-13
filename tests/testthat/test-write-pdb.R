context("test-write-pdb")

test_that("write data", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())
  expect_silent(po <- posterior("eight_schools-eight_schools_centered", pdb_test))
  expect_silent(d <- get_data(po))

  # Test write data
  di <- info(d); di$name <- "test_data"; info(d) <- di
  expect_error(write_pdb(d, pdb_test), "data_file")
  di$data_file <- "data/data/test_data.json"; info(d) <- di
  expect_silent(write_pdb(d, pdb_test))
  expect_error(write_pdb(d, pdb_test), "already exists")
  expect_silent(write_pdb(d, pdb_test, overwrite = TRUE))

  # Test write data info
  di$name <- "test_data"
  di$title <- di$description <- "Test data"
  di$data_file <- "data/data/test_data.json"

  expect_silent(write_pdb(di, pdb_test, overwrite = TRUE))
  expect_error(write_pdb(di, pdb_test), "already exists")
  expect_silent(write_pdb(di, pdb_test, overwrite = TRUE))

  info(d) <- di
  expect_silent(dt <- pdb_data("test_data", pdb_test))
  expect_equal(lapply(d, identity), lapply(dt, identity))
  expect_equal(info(dt)[sort(names(info(dt)))], info(d)[sort(names(info(d)))])
  expect_silent(dti <- pdb_data_info("test_data", pdb_test))

  # Remove test_data
  expect_silent(remove_pdb(x = dt, pdb = pdb_test))
  pdb_clear_cache(pdb_test)
  expect_error(pdb_data("test_data", pdb_test), "File does not exist")
  expect_error(pdb_data_info("test_data", pdb_test), "File does not exist")
})


test_that("write model", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())
  expect_silent(po <- posterior("eight_schools-eight_schools_centered", pdb_test))
  expect_silent(sc <- stan_code(po))

  # Test write model info
  mi <- info(sc)
  mi$name <- "test_model"
  mi$title <- mi$description <- "Test model"
  mi$model_implementations <- list(stan = list(model_code = "models/stan/test_model.stan"))

  # Test write model
  info(sc) <- mi
  expect_silent(write_pdb(sc, pdb_test, overwrite = TRUE))
  expect_error(write_pdb(sc, pdb_test), "already exists")
  expect_silent(write_pdb(sc, pdb_test, overwrite = TRUE))

  expect_silent(sct <- pdb_stan_code("test_model", pdb_test))
  expect_identical(sc, sct)

  # Remove model
  expect_silent(remove_pdb(sc, pdb = pdb_test))
  pdb_clear_cache(pdb_test)
  expect_error(pdb_model_code("test_model", "stan", pdb = pdb_test), "File does not exist")
  expect_error(pdb_model_info("test_model", pdb_test), "File does not exist")

  # Write model info
  expect_silent(write_pdb(mi, pdb_test))
  expect_error(write_pdb(mi, pdb_test), "already exists")
  expect_silent(write_pdb(mi, pdb_test, overwrite = TRUE))

  expect_silent(mit <- pdb_model_info("test_model", pdb_test))
  expect_named(mit$model_implementations, "stan")
  expect_named(
    mit$model_implementations$stan,
    "model_code"
  )
  expect_false("pymc_version" %in% names(mit$model_implementations$stan))

  # Remove model info
  expect_silent(remove_pdb(mi, pdb = pdb_test))
  pdb_clear_cache(pdb_test)
  expect_error(pdb_model_info("test_model", pdb_test), "File does not exist")
})





test_that("write posterior", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())
  expect_silent(po <- posterior("eight_schools-eight_schools_centered", pdb_test))
  expect_silent(sc <- stan_code(po))
  expect_silent(d <- pdb_data(po))

  # Test write model info
  info(sc)$name <- "test_model"
  info(d)$name <- "test_data"
  info(d)$data_file <- "data/data/test_data.json"

  # Test write gsd
  po$name <- "test_data-test_model"
  po$model_name <- "test_model"
  po$data_name <- "test_data"
  po["reference_posterior_name"] <- list(NULL)
  po$model_info <- info(sc)
  po$data_info <- info(d)

  expect_silent(write_pdb(po, pdb_test))
  expect_error(write_pdb(po, pdb_test), "already exists")
  expect_silent(write_pdb(po, pdb_test, overwrite = TRUE))

  # Test that we get identical posteriors
  write_pdb(d, pdb_test)
  write_pdb(sc, pdb_test)
  expect_silent(pot <- posterior("test_data-test_model", pdb_test))
  canonical_posterior <- function(x) {
    x <- unclass(x)
    for (field in c("data_info", "model_info")) {
      x[[field]] <- x[[field]][sort(names(x[[field]]))]
    }
    x[sort(names(x))]
  }
  expect_equal(canonical_posterior(po), canonical_posterior(pot))

  # Remove posterior
  expect_silent(remove_pdb(pot, pdb = pdb_test))
  pdb_clear_cache(pdb_test)
  expect_error(posterior("test_data-test_model", pdb_test), "File does not exist")

  remove_pdb(sc, pdb = pdb_test)
  remove_pdb(d, pdb = pdb_test)

})
