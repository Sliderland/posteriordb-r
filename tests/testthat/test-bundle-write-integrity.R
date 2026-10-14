bundle_integrity_pdb <- function() {
  root <- tempfile("bundle-integrity-")
  for (folder in c("data", "models", "posteriors", "alias", "cache")) {
    dir.create(file.path(root, folder), recursive = TRUE)
  }
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  pdb_local(root, cache_path = file.path(root, "cache"))
}

test_that("failed ZIP creation retains the JSON payload and is reported as failure", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(
    list(n = 1L),
    info = as.pdb_data_info(list(
      name = "zip-failure",
      title = "Inputs",
      added_by = "test",
      added_date = Sys.Date()
    ))
  )
  testthat::local_mocked_bindings(zip = function(...) 1L, .package = "utils")
  messages <- character()
  error <- tryCatch(
    withCallingHandlers(
      write_pdb(object, database),
      message = function(message) {
        messages <<- c(messages, conditionMessage(message))
        invokeRestart("muffleMessage")
      }
    ),
    error = identity
  )
  expect_match(conditionMessage(error), "ZIP creation failed")
  expect_true(any(grepl("zip-failure", messages, fixed = TRUE)))
  expect_true(file.exists(pdb_file_path(
    database,
    "data/info/zip-failure.info.json"
  )))
  expect_true(file.exists(pdb_file_path(
    database,
    "data/data/zip-failure.json"
  )))
  expect_false(file.exists(pdb_file_path(
    database,
    "data/data/zip-failure.json.zip"
  )))
})

test_that("failed JSON cleanup reports the saved archive and retains both files", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(
    list(n = 1L),
    info = as.pdb_data_info(list(
      name = "cleanup-failure",
      title = "Inputs",
      added_by = "test",
      added_date = Sys.Date()
    ))
  )
  testthat::local_mocked_bindings(
    file.remove = function(...) FALSE,
    .package = "base"
  )
  expect_error(
    write_pdb(object, database),
    "Archive written, but JSON cleanup failed"
  )
  expect_true(file.exists(pdb_file_path(
    database,
    "data/data/cleanup-failure.json"
  )))
  archive <- pdb_file_path(database, "data/data/cleanup-failure.json.zip")
  expect_true(file.exists(archive))
  expect_identical(
    utils::unzip(archive, list = TRUE)$Name,
    "cleanup-failure.json"
  )
})

test_that("a nonzero ZIP status is a failure even when an archive exists", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(
    list(n = 1L),
    info = as.pdb_data_info(list(
      name = "zip-status",
      title = "Inputs",
      added_by = "test",
      added_date = Sys.Date()
    ))
  )
  original_zip <- utils::zip
  testthat::local_mocked_bindings(
    zip = function(...) {
      original_zip(...)
      1L
    },
    .package = "utils"
  )
  expect_error(
    suppressMessages(write_pdb(object, database)),
    "ZIP creation failed"
  )
  expect_true(file.exists(pdb_file_path(
    database,
    "data/data/zip-status.json"
  )))
})
