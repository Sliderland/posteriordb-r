context("test-pdb-cache")

test_that("default caches are isolated by resolved database endpoint", {
  make_database <- function(value) {
    root <- tempfile("posteriordb-cache-test-")
    dir.create(file.path(root, "data"), recursive = TRUE)
    dir.create(file.path(root, "models"))
    dir.create(file.path(root, "posteriors"))
    writeLines(value, file.path(root, "posteriors", "same.json"))
    root
  }
  first <- pdb_local(make_database("first"))
  second <- pdb_local(make_database("second"))
  expect_false(identical(first$cache_path, second$cache_path))
  first_path <- posteriordb:::pdb_cached_local_file_path(
    first, "posteriors/same.json"
  )
  second_path <- posteriordb:::pdb_cached_local_file_path(
    second, "posteriors/same.json"
  )
  expect_identical(readLines(first_path), "first")
  expect_identical(readLines(second_path), "second")
})

test_that("remove reference posterior cache", {
  assert_pdb_path_exists()
  expect_silent(pdb_test <- pdb_local())
  posteriordb:::pdb_clear_cache(pdb_test)

  expect_length(dir(pdb_test$cache_path, recursive = TRUE),0)

  po <- posterior("8_schools", pdb_test)
  expect_false(any(grepl(dir(pdb_test$cache_path, recursive = TRUE),
                        pattern = "draws/draws/eight_schools-eight_schools_noncentered\\.json")))
  rp <- reference_posterior_draws(po)
  expect_true(any(grepl(dir(pdb_test$cache_path, recursive = TRUE),
                    pattern = "draws/draws/eight_schools-eight_schools_noncentered\\.json")))
  pdb_cache_rm(x = rp)
  expect_false(any(grepl(dir(pdb_test$cache_path, recursive = TRUE),
                         pattern = "draws/draws/eight_schools-eight_schools_noncentered\\.json")))

})


test_that("remove data cache", {
  assert_pdb_path_exists()
  expect_silent(pdb_test <- pdb_local())
  pdb_clear_cache(pdb_test)

  expect_length(dir(pdb_test$cache_path, recursive = TRUE),0)

  po <- posterior("8_schools", pdb_test)
  expect_false(any(grepl(dir(pdb_test$cache_path, recursive = TRUE),
                         pattern = "data/data/eight_schools\\.json")))
  sd <- get_data(po)
  expect_true(any(grepl(dir(pdb_test$cache_path, recursive = TRUE),
                        pattern = "data/data/eight_schools\\.json")))
  pdb_cache_rm(x = sd)
  expect_false(any(grepl(dir(pdb_test$cache_path, recursive = TRUE),
                         pattern = "data/data/eight_schools\\.json")))
})
