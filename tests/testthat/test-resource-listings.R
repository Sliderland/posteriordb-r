test_that("local resource listings preserve dotted names and exclude unrelated entries", {
  root <- tempfile("resource-listings-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  paths <- c("posteriors", "models/info", "data/info", "reference_posteriors/draws/info")
  connection <- structure(list(pdb_local_endpoint = root, cache_path = root),
    class = c("pdb_local", "pdb"))
  list_names <- function(path) switch(path,
    posteriors = posterior_names(connection), "models/info" = model_names(connection),
    "data/info" = data_names(connection), reference_posterior_names(connection, "draws"))
  for (path in paths) {
    directory <- file.path(root, path)
    dir.create(directory, recursive = TRUE)
    expect_identical(list_names(path), character())
    suffix <- if (path == "posteriors") ".json" else ".info.json"
    for (name in c("name.v2", "name.info")) writeLines("{}", file.path(directory, paste0(name, suffix)))
    for (name in c(".DS_Store", "notes.txt", "record.json.backup")) writeLines("unrelated", file.path(directory, name))
    dir.create(file.path(directory, paste0("directory", suffix)))
    expect_setequal(list_names(path), c("name.v2", "name.info"))
    expect_setequal(posteriordb:::pdb_list_files_in_cache(connection, path, file_ext = FALSE),
      c("name.v2", "name.info"))
  }
  expect_identical(posteriordb:::remove_file_extension(character()), character())
  expect_identical(posteriordb:::remove_file_extension("name.v2.stan"), "name.v2")
  expect_identical(posteriordb:::get_file_extension("name.v2.stan"), "stan")
})

test_that("GitHub resource listings preserve dotted names and exclude directories", {
  connection <- structure(list(github = list(username = "fixture", repo = "database",
    subdir = "posterior_database", ref = "fixture-ref")), class = c("pdb_github", "pdb"))
  empty <- FALSE
  testthat::local_mocked_bindings(gh = function(endpoint, ...) {
    if (empty) return(list())
    suffix <- if (grepl("/posteriors[?]", endpoint)) ".json" else ".info.json"
    list(list(name = paste0("name.v2", suffix), type = "file"),
      list(name = paste0("name.info", suffix), type = "file"),
      list(name = paste0("directory", suffix), type = "dir"),
      list(name = "notes.json.backup", type = "file"),
      list(name = "notes.txt", type = "file"))
  }, .package = "gh")
  expect_setequal(posterior_names(connection), c("name.v2", "name.info"))
  expect_setequal(model_names(connection), c("name.v2", "name.info"))
  expect_setequal(data_names(connection), c("name.v2", "name.info"))
  expect_setequal(reference_posterior_names(connection, "draws"), c("name.v2", "name.info"))
  # The endpoint checker still needs directory names from the same transport.
  expect_true("directory.info.json" %in% posteriordb:::github_dir("/fixture", connection))
  empty <- TRUE
  expect_identical(posterior_names(connection), character())
  expect_identical(model_names(connection), character())
  expect_identical(data_names(connection), character())
  expect_identical(reference_posterior_names(connection, "draws"), character())
})
