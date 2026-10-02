test_that("reference names select the requested local type", {
  root <- tempfile("reference-names-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  paths <- c(draws = "draws", mean_value = "summary_statistics/mean_value",
    mean_squared_value = "summary_statistics/mean_squared_value")
  for (type in names(paths)) {
    directory <- file.path(root, "reference_posteriors", paths[[type]], "info")
    dir.create(directory, recursive = TRUE)
    writeLines("{}", file.path(directory, paste0(type, ".info.json")))
  }
  connection <- structure(list(pdb_local_endpoint = root), class = c("pdb_local", "pdb"))
  for (type in names(paths))
    expect_identical(reference_posterior_names(connection, type), type)
})

test_that("reference info writes, reads, lists and removes use the same type paths", {
  root <- tempfile("reference-info-paths-")
  dir.create(file.path(root, "cache"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  reference <- as.reference_posterior_info(list(
    name = "reference", inference = list(method = "analytical", method_arguments = list()),
    diagnostics = NULL, checks_made = NULL, comments = "fixture", added_by = "test",
    added_date = as.Date("2026-01-01"), versions = list(r_version = "fixture")
  ))
  linked <- structure(list(reference_posterior_name = reference$name),
    class = "pdb_posterior", pdb = connection)
  paths <- c(draws = "draws", mean_value = "summary_statistics/mean_value",
    mean_squared_value = "summary_statistics/mean_squared_value")
  for (type in names(paths)) {
    write_pdb(reference, connection, type = type)
    path <- file.path(root, "reference_posteriors", paths[[type]], "info/reference.info.json")
    expect_true(file.exists(path))
    expect_identical(reference_posterior_names(connection, type), "reference")
    expect_identical(reference_posterior_info(linked, type), reference)
    expect_true(remove_pdb(reference, connection, type = type))
    expect_false(file.exists(path))
  }
})

test_that("GitHub reference names use the requested type without network access", {
  connection <- structure(list(github = list(username = "fixture", repo = "database",
    subdir = "posterior_database", ref = "fixture-ref")), class = c("pdb_github", "pdb"))
  requested <- NULL
  testthat::local_mocked_bindings(
    github_dir = function(gh_path, pdb, files_only) {
      expect_true(files_only)
      requested <<- gh_path
      "reference.info.json"
    }, .package = "posteriordb"
  )
  paths <- c(draws = "draws", mean_value = "summary_statistics/mean_value",
    mean_squared_value = "summary_statistics/mean_squared_value")
  for (type in names(paths)) {
    expect_identical(reference_posterior_names(connection, type), "reference")
    expect_identical(requested, paste0(
      "/repos/fixture/database/contents/posterior_database/reference_posteriors/",
      paths[[type]], "/info?ref=fixture-ref"))
  }
})
