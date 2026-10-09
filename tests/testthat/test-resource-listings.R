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

test_that("GitHub directory caching pairs file names and URLs and reports failures", {
  skip_if_not_installed("httr")
  cache <- withr::local_tempdir("github-directory-cache-")
  connection <- structure(list(cache_path = cache, github = list(username = "fixture",
    repo = "database", subdir = "posterior_database", ref = "fixture-ref")),
    class = c("pdb_github", "pdb"))
  testthat::local_mocked_bindings(gh = function(...) list(
    list(name = "nested", type = "dir", download_url = NULL),
    list(name = "value.json", type = "file", download_url = "https://fixture/value.json")
  ), .package = "gh")
  calls <- list()
  failure <- NULL
  testthat::local_mocked_bindings(github_download = function(download_url, to, pat, overwrite) {
    calls[[length(calls) + 1L]] <<- list(url = download_url, name = basename(to), overwrite = overwrite)
    if (identical(failure, "invalid")) stop("invalid download URL")
    writeLines("payload", to)
    if (identical(failure, "throw")) stop("interrupted download")
    !identical(failure, "false")
  })
  suppressMessages(pdb_cache_dir(connection, "posteriors"))
  expect_identical(calls, list(list(url = "https://fixture/value.json", name = "value.json",
    overwrite = FALSE)))
  expect_identical(list.files(file.path(cache, "posteriors")), "value.json")
  for (mode in c("false", "throw")) {
    unlink(file.path(cache, "posteriors/value.json"))
    failure <- mode
    expect_error(suppressMessages(pdb_cache_dir(connection, "posteriors")),
      if (mode == "false") "Could not download" else "interrupted download")
    expect_identical(list.files(file.path(cache, "posteriors")), character())
  }
  writeLines("cached", file.path(cache, "posteriors/value.json"))
  failure <- "invalid"
  expect_error(suppressMessages(pdb_cache_dir(connection, "posteriors")), "invalid download URL")
  expect_identical(readLines(file.path(cache, "posteriors/value.json")), "cached")
})

test_that("local directory caching reports copy failures and removes partial files", {
  root <- withr::local_tempdir("local-directory-cache-")
  for (path in c("posteriors", "cache")) dir.create(file.path(root, path))
  source <- file.path(root, "posteriors/value.json")
  writeLines('{"name":"value","data_name":"data","model_name":"model","keywords":"needle"}', source)
  original <- readLines(source)
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  failure <- "false"
  testthat::local_mocked_bindings(pdb_file_copy = function(pdb, from, to, overwrite) {
    writeLines("partial", to)
    if (failure == "throw") stop("interrupted copy")
    FALSE
  })
  for (mode in c("false", "throw")) {
    failure <- mode
    expect_error(search_posteriors(connection, "needle", fields = "posterior"),
      if (mode == "false") "Could not copy" else "interrupted copy")
    expect_identical(list.files(file.path(root, "cache/posteriors")), character())
  }
  expect_identical(readLines(source), original)
})

test_that("local caching preserves source files when the cache aliases the database", {
  parent <- withr::local_tempdir("overlapping-directory-cache-")
  root <- file.path(parent, "database")
  dir.create(file.path(root, "posteriors"), recursive = TRUE)
  source <- file.path(root, "posteriors/value.json")
  writeLines("{}", source)
  paths <- c(root, file.path(root, "."))
  alias <- file.path(parent, "alias")
  if (file.symlink(root, alias)) paths <- c(paths, alias)
  for (cache in paths) {
    connection <- structure(list(pdb_local_endpoint = root, cache_path = cache),
      class = c("pdb_local", "pdb"))
    expect_silent(pdb_cache_dir(connection, "posteriors"))
    expect_identical(readLines(source), "{}")
  }
})
