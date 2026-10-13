bundle_integrity_pdb <- function() {
  root <- tempfile("bundle-integrity-")
  for (folder in c("data", "models", "posteriors", "alias", "cache"))
    dir.create(file.path(root, folder), recursive = TRUE)
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  pdb_local(root, cache_path = file.path(root, "cache"))
}

bundle_integrity_extraction <- function(divergence = 0L) {
  set.seed(412)
  draws <- posterior::as_draws_array(array(rnorm(10000), c(2500, 4, 1),
    dimnames = list(NULL, NULL, "theta")))
  sampler <- array(0, c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("divergent__", "treedepth__")))
  sampler[1, 1, "divergent__"] <- divergence
  list(draws = draws, sampler_diagnostics = posterior::as_draws_array(sampler),
    metadata = list(expected_fraction_of_missing_information = rep(.5, 4), max_treedepth = 10),
    dimensions = list(theta = 1L),
    source = "parameters { real theta; } model { theta ~ normal(0,1); }",
    fit_class = "stanfit", import_versions = list())
}

bundle_integrity_snapshot <- function(pdb) {
  files <- list.files(pdb$pdb_local_endpoint, recursive = TRUE)
  files <- files[!grepl("^cache/", files)]
  stats::setNames(lapply(file.path(pdb$pdb_local_endpoint, files), function(path)
    readBin(path, "raw", n = file.info(path)$size)), files)
}

test_that("failed ZIP creation retains the JSON payload and is reported as failure", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(
    name = "zip-failure", title = "Inputs", added_by = "test", added_date = Sys.Date()
  )))
  testthat::local_mocked_bindings(zip = function(...) 1L, .package = "utils")
  messages <- character()
  error <- tryCatch(withCallingHandlers(write_pdb(object, database),
    message = function(message) {
      messages <<- c(messages, conditionMessage(message))
      invokeRestart("muffleMessage")
    }), error = identity)
  expect_s3_class(error, "error")
  expect_true(any(grepl("zip-failure", messages, fixed = TRUE)))
  expect_true(file.exists(pdb_file_path(database, "data/info/zip-failure.info.json")))
  expect_true(file.exists(pdb_file_path(database, "data/data/zip-failure.json")))
  expect_false(file.exists(pdb_file_path(database, "data/data/zip-failure.json.zip")))
})

test_that("failed JSON cleanup reports the saved archive and retains both files", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(
    name = "cleanup-failure", title = "Inputs", added_by = "test", added_date = Sys.Date()
  )))
  testthat::local_mocked_bindings(file.remove = function(...) FALSE, .package = "base")
  expect_error(write_pdb(object, database), "Archive written, but JSON cleanup failed")
  expect_true(file.exists(pdb_file_path(database, "data/data/cleanup-failure.json")))
  archive <- pdb_file_path(database, "data/data/cleanup-failure.json.zip")
  expect_true(file.exists(archive))
  expect_identical(utils::unzip(archive, list = TRUE)$Name, "cleanup-failure.json")
})
