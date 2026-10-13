test_that("the package entry point runs without inspecting a configured corpus", {
  root <- tempfile("unused-corpus-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  withr::local_options(list(pdb_path = root))
  withr::local_envvar(c(PDB_PATH = root, PDB_TEST_DATABASE = "false"))
  environment <- new.env(parent = globalenv())
  environment$library <- function(...) NULL
  environment$file.copy <- function(...) stop("Unexpected corpus copy")
  called <- FALSE
  environment$test_check <- function(...) called <<- TRUE
  expect_silent(sys.source(file.path(testthat::test_path(), "..", "testthat.R"), environment))
  expect_true(called)
})

test_that("opt-in database tests isolate files, configuration and settings on failure", {
  root <- tempfile("corpus-source-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  original <- file.path(root, "record.json")
  writeLines("original", original)
  writeLines("hidden", file.path(root, ".fixture"))
  withr::local_options(list(pdb_path = root))
  withr::local_envvar(c(PDB_PATH = "environment-is-lower-priority", PDB_TEST_DATABASE = "true"))
  oldwd <- getwd()
  for (fail in c(FALSE, TRUE)) {
    staged <- working <- NULL
    run <- function() {
      local_test_database()
      staged <<- getOption("pdb_path")
      working <<- getwd()
      expect_false(identical(staged, root))
      expect_identical(Sys.getenv("PDB_PATH"), staged)
      expect_false(file.exists(".pdb_config.yml"))
      expect_identical(readLines(file.path(staged, ".fixture")), "hidden")
      expect_identical(readLines(file.path(staged, "record.json")), "original")
      writeLines("changed", file.path(staged, "record.json"))
      writeLines("type: local", ".pdb_config.yml")
      if (fail) stop("injected failure")
    }
    if (fail) expect_error(run(), "injected failure") else expect_silent(run())
    expect_identical(readLines(original), "original")
    expect_false(dir.exists(staged))
    expect_false(dir.exists(working))
    expect_identical(getOption("pdb_path"), root)
    expect_identical(Sys.getenv("PDB_PATH"), "environment-is-lower-priority")
    expect_identical(getwd(), oldwd)
  }
})

test_that("failed corpus copies stop before tests and preserve source files", {
  root <- tempfile("corpus-source-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  withr::local_options(list(pdb_path = root))
  withr::local_envvar(c(PDB_TEST_DATABASE = "true"))
  writeLines("original", file.path(root, "record.json"))
  testthat::local_mocked_bindings(file.copy = function(...) FALSE, .package = "base")
  expect_error(local_test_database(), "Could not copy")
  expect_identical(readLines(file.path(root, "record.json")), "original")
})

test_that("direct test_file runs load safety helpers and clean up after failures", {
  source <- tempfile("direct-corpus-")
  directory <- tempfile("direct-tests-")
  dir.create(source)
  dir.create(directory)
  on.exit(unlink(c(source, directory), recursive = TRUE), add = TRUE)
  writeLines("original", file.path(source, "record.json"))
  file.copy(file.path(testthat::test_path(), "helper-integration.R"), directory)
  file <- file.path(directory, "test-direct.R")
  writeLines(c('testthat::test_that("injected failure", {',
    '  local_test_database()',
    '  writeLines("changed", file.path(Sys.getenv("PDB_PATH"), "record.json"))',
    '  testthat::expect_true(FALSE)', '})'), file)
  withr::local_options(list(pdb_path = source))
  withr::local_envvar(c(PDB_TEST_DATABASE = "true", PDB_PATH = source))
  cwd <- getwd()
  expect_error(testthat::test_file(file, reporter = "silent", stop_on_failure = TRUE), "Test failures")
  expect_identical(readLines(file.path(source, "record.json")), "original")
  expect_identical(getOption("pdb_path"), source)
  expect_identical(Sys.getenv("PDB_PATH"), source)
  expect_identical(getwd(), cwd)
})
