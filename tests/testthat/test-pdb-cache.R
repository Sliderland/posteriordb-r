test_that("cache removal is idempotent and protects database files", {
  root <- withr::local_tempdir()
  database <- file.path(root, "database")
  cache <- file.path(database, "cache")
  for (path in c("data/data", "models", "posteriors", "cache")) {
    dir.create(file.path(database, path), recursive = TRUE)
  }
  connection <- pdb_local(database, cache_path = cache)
  data <- as.pdb_data(
    list(y = 1),
    info = as.pdb_data_info(list(
      name = "value",
      title = "Inputs",
      added_by = "Tester",
      added_date = Sys.Date()
    ))
  )
  pdb(data) <- connection
  source <- file.path(database, "data/data/value.json")
  writeLines("source", source)
  target <- pdb_cache_path(connection, "data/data/value.json")
  unrelated <- file.path(cache, "keep.txt")
  writeLines("unrelated", unrelated)
  withr::local_options(list(warn = 2))
  expect_silent(pdb_cache_rm(data))
  writeLines("cached", target)
  expect_silent(pdb_cache_rm(data))
  expect_false(file.exists(target))
  expect_identical(readLines(unrelated), "unrelated")
  expect_identical(readLines(source), "source")

  # Equal roots, ancestor roots, and resource subdirectories can delete source.
  for (unsafe in c(
    database,
    root,
    file.path(database, "data"),
    file.path(database, "data/data")
  )) {
    unsafe_connection <- pdb_local(database, cache_path = unsafe)
    pdb(data) <- unsafe_connection
    expect_error(pdb_cache_rm(data), "overlaps")
    expect_error(pdb_clear_cache(unsafe_connection), "overlaps")
    expect_identical(readLines(source), "source")
    expect_identical(readLines(unrelated), "unrelated")
  }
  pdb(data) <- connection
  info(data)$name <- "../escape"
  expect_error(pdb_cache_rm(data), "single path components")
  expect_silent(pdb_clear_cache(connection))
  expect_false(file.exists(unrelated))
  expect_identical(readLines(source), "source")
  expect_silent(pdb_clear_cache(connection))

  alias <- file.path(root, "alias")
  skip_if_not(file.symlink(database, alias))
  expect_error(
    pdb_clear_cache(pdb_local(database, cache_path = alias)),
    "overlaps"
  )
  # Recursive clears must not follow a directory symlink out of the cache.
  writeLines("cached", target)
  skip_if_not(file.symlink(
    file.path(database, "data"),
    file.path(cache, "escape")
  ))
  expect_error(pdb_clear_cache(connection), "outside")
  expect_identical(readLines(target), "cached")
  expect_identical(readLines(source), "source")
})

test_that("default caches are isolated by resolved database endpoint", {
  make_database <- function(value) {
    root <- tempfile("posteriordb-cache-test-")
    withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
    dir.create(file.path(root, "data"), recursive = TRUE)
    dir.create(file.path(root, "models"))
    dir.create(file.path(root, "posteriors"))
    writeLines(value, file.path(root, "posteriors", "same.json"))
    root
  }
  first <- pdb_local(make_database("first"))
  second <- pdb_local(make_database("second"))
  expect_false(identical(first$cache_path, second$cache_path))
  first_path <- pdb_cached_local_file_path(
    first,
    "posteriors/same.json"
  )
  second_path <- pdb_cached_local_file_path(
    second,
    "posteriors/same.json"
  )
  expect_identical(readLines(first_path), "first")
  expect_identical(readLines(second_path), "second")
})

test_that("remove reference posterior cache", {
  local_test_database()
  assert_pdb_path_exists()
  expect_silent(pdb_test <- pdb_local())
  pdb_clear_cache(pdb_test)

  expect_length(dir(pdb_test$cache_path, recursive = TRUE), 0)

  po <- posterior("8_schools", pdb_test)
  expect_false(any(grepl(
    dir(pdb_test$cache_path, recursive = TRUE),
    pattern = "draws/draws/eight_schools-eight_schools_noncentered\\.json"
  )))
  rp <- reference_posterior_draws(po)
  expect_true(any(grepl(
    dir(pdb_test$cache_path, recursive = TRUE),
    pattern = "draws/draws/eight_schools-eight_schools_noncentered\\.json"
  )))
  pdb_cache_rm(x = rp)
  expect_false(any(grepl(
    dir(pdb_test$cache_path, recursive = TRUE),
    pattern = "draws/draws/eight_schools-eight_schools_noncentered\\.json"
  )))
})


test_that("remove data cache", {
  local_test_database()
  assert_pdb_path_exists()
  expect_silent(pdb_test <- pdb_local())
  pdb_clear_cache(pdb_test)

  expect_length(dir(pdb_test$cache_path, recursive = TRUE), 0)

  po <- posterior("8_schools", pdb_test)
  expect_false(any(grepl(
    dir(pdb_test$cache_path, recursive = TRUE),
    pattern = "data/data/eight_schools\\.json"
  )))
  sd <- get_data(po)
  expect_true(any(grepl(
    dir(pdb_test$cache_path, recursive = TRUE),
    pattern = "data/data/eight_schools\\.json"
  )))
  pdb_cache_rm(x = sd)
  expect_false(any(grepl(
    dir(pdb_test$cache_path, recursive = TRUE),
    pattern = "data/data/eight_schools\\.json"
  )))
})

test_that("cache clears refuse a cache that holds a linked resource directory", {
  root <- withr::local_tempdir()
  database <- file.path(root, "database")
  cache <- file.path(root, "cache")
  for (path in c("models", "posteriors")) {
    dir.create(file.path(database, path), recursive = TRUE)
  }
  dir.create(file.path(cache, "data-store"), recursive = TRUE)
  source <- file.path(cache, "data-store", "value.json")
  writeLines("source", source)
  skip_if_not(file.symlink(
    file.path(cache, "data-store"),
    file.path(database, "data")
  ))
  connection <- pdb_local(database, cache_path = cache)
  expect_error(pdb_clear_cache(connection), "overlaps")
  expect_identical(readLines(source), "source")
})

test_that("draw cache removal clears both the draws and their info", {
  root <- withr::local_tempdir()
  for (path in c("data", "models", "posteriors", "cache")) {
    dir.create(file.path(root, path))
  }
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  draws_info <- as.pdb_reference_posterior_info(list(
    name = "cached",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = NULL,
    checks_made = NULL,
    comments = "Fixture",
    added_by = "Tester",
    added_date = Sys.Date(),
    versions = NULL
  ))
  draws <- as.pdb_reference_posterior_draws(
    posterior::as_draws_list(array(
      seq_len(40),
      c(10, 4, 1),
      dimnames = list(NULL, NULL, "theta")
    )),
    info = draws_info
  )
  pdb(draws) <- connection
  cached <- pdb_cache_path(
    connection,
    c(
      "reference_posteriors/draws/draws/cached.json",
      "reference_posteriors/draws/info/cached.info.json"
    )
  )
  for (path in cached) {
    writeLines("cached", path)
  }
  pdb_cache_rm(draws)
  expect_false(any(file.exists(cached)))
})
