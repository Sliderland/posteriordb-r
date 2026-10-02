test_that("the package harness isolates configured databases and restores settings", {
  root <- tempfile("harness-source-")
  dir.create(file.path(root, "posterior_database/posteriors"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  original <- file.path(root, "posterior_database/posteriors/record.json")
  writeLines("original", original)
  writeLines("hidden", file.path(root, ".fixture"))
  withr::local_options(list(pdb_path = root))
  withr::local_envvar(c(PDB_PATH = "environment-is-lower-priority"))
  harness <- file.path(testthat::test_path(), "..", "testthat.R")

  for (fail in c(FALSE, TRUE)) {
    staged <- NULL
    environment <- new.env(parent = globalenv())
    environment$library <- function(...) NULL
    environment$test_check <- function(...) {
      staged <<- getOption("pdb_path")
      if (identical(staged, root)) stop("Harness did not isolate the database")
      expect_identical(Sys.getenv("PDB_PATH"), staged)
      expect_identical(readLines(file.path(staged, ".fixture")), "hidden")
      copy <- file.path(staged, "posterior_database/posteriors/record.json")
      expect_identical(readLines(copy), "original")
      writeLines("changed", copy)
      if (fail) stop("injected test failure")
    }
    if (fail) {
      expect_error(sys.source(harness, envir = environment), "injected test failure")
    } else {
      expect_silent(sys.source(harness, envir = environment))
    }
    expect_false(dir.exists(staged))
    expect_identical(readLines(original), "original")
    expect_identical(getOption("pdb_path"), root)
    expect_identical(Sys.getenv("PDB_PATH"), "environment-is-lower-priority")
  }
})

test_that("the package harness stages an environment-selected database", {
  root <- tempfile("harness-source-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("original", file.path(root, "record.json"))
  withr::local_options(list(pdb_path = NULL))
  withr::local_envvar(c(PDB_PATH = root))
  environment <- new.env(parent = globalenv())
  environment$library <- function(...) NULL
  staged <- NULL
  environment$test_check <- function(...) {
    staged <<- Sys.getenv("PDB_PATH")
    expect_false(identical(staged, root))
    expect_identical(getOption("pdb_path"), staged)
    expect_identical(readLines(file.path(staged, "record.json")), "original")
  }
  sys.source(file.path(testthat::test_path(), "..", "testthat.R"), envir = environment)
  expect_false(dir.exists(staged))
  expect_null(getOption("pdb_path"))
  expect_identical(Sys.getenv("PDB_PATH"), root)
})

test_that("the package harness cleans up a failed database copy", {
  root <- tempfile("harness-source-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("original", file.path(root, "record.json"))
  withr::local_options(list(pdb_path = root))
  withr::local_envvar(c(PDB_PATH = NA_character_))
  environment <- new.env(parent = globalenv())
  environment$library <- function(...) NULL
  staged <- NULL
  environment$file.copy <- function(from, to, ...) {
    staged <<- to
    writeLines("partial", file.path(to, "record.json"))
    FALSE
  }
  environment$test_check <- function(...) stop("Tests must not run after a failed copy")
  expect_error(
    sys.source(file.path(testthat::test_path(), "..", "testthat.R"), envir = environment),
    "Could not copy"
  )
  expect_false(dir.exists(staged))
  expect_identical(readLines(file.path(root, "record.json")), "original")
  expect_identical(getOption("pdb_path"), root)
  expect_identical(Sys.getenv("PDB_PATH", unset = NA_character_), NA_character_)
})

test_that("the package harness removes a default clone and restores unset settings", {
  skip_if_not_installed("git2r")
  withr::local_options(list(pdb_path = NULL))
  withr::local_envvar(c(PDB_PATH = NA_character_))
  staged <- NULL
  testthat::local_mocked_bindings(
    clone = function(url, local_path, ...) {
      staged <<- local_path
      dir.create(local_path)
      writeLines("cloned", file.path(local_path, "record.json"))
    },
    .package = "git2r"
  )
  environment <- new.env(parent = globalenv())
  environment$library <- function(...) NULL
  environment$test_check <- function(...) {
    expect_identical(getOption("pdb_path"), staged)
    expect_identical(Sys.getenv("PDB_PATH"), staged)
    expect_identical(readLines(file.path(staged, "record.json")), "cloned")
    stop("injected test failure")
  }
  expect_error(
    sys.source(file.path(testthat::test_path(), "..", "testthat.R"), envir = environment),
    "injected test failure"
  )
  expect_false(dir.exists(staged))
  expect_null(getOption("pdb_path"))
  expect_identical(Sys.getenv("PDB_PATH", unset = NA_character_), NA_character_)
})

test_that("the package harness rejects staging inside its source tree", {
  environment <- new.env(parent = globalenv())
  environment$library <- function(...) NULL
  environment$file.copy <- function(...) stop("Source-overlap guard did not run")
  harness <- file.path(testthat::test_path(), "..", "testthat.R")
  filesystem_root <- normalizePath(tempdir(), winslash = "/")
  while (!identical(filesystem_root, dirname(filesystem_root)))
    filesystem_root <- dirname(filesystem_root)
  for (root in c(tempdir(), dirname(tempdir()), filesystem_root)) {
    withr::local_options(list(pdb_path = root))
    expect_error(sys.source(harness, envir = environment), "outside the source database")
  }
})
