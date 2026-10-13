# Integration tests opt in explicitly; configured user paths alone do not opt in.
local_test_database <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not(
    identical(Sys.getenv("PDB_TEST_DATABASE"), "true"),
    "set PDB_TEST_DATABASE=true for corpus integration tests"
  )
  source <- getOption("pdb_path", Sys.getenv("PDB_PATH"))
  testthat::skip_if_not(
    is.character(source) && length(source) == 1L && !is.na(source) && dir.exists(source),
    paste0("PDB_PATH is not an existing corpus directory: '", paste(source, collapse = ", "), "'")
  )
  source <- normalizePath(source, winslash = "/", mustWork = TRUE)
  parent <- withr::local_tempdir(
    pattern = "pdb-test-",
    .local_envir = .local_envir
  )
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  if (startsWith(paste0(parent, "/"), paste0(sub("/+$", "", source), "/"))) {
    stop("The test staging directory must be outside the source database")
  }
  staged <- file.path(parent, "database")
  dir.create(staged)
  files <- list.files(source, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  # Version-control history is not part of the corpus and can be gigabytes.
  files <- files[basename(files) != ".git"]
  if (!length(files)) {
    stop("The test corpus at PDB_PATH is empty: ", source)
  }
  copied <- file.copy(files, staged, recursive = TRUE)
  if (!all(copied)) {
    stop("Could not copy the test corpus: ", paste(basename(files)[!copied], collapse = ", "))
  }
  working <- file.path(parent, "working")
  dir.create(working)
  withr::local_options(list(pdb_path = staged), .local_envir = .local_envir)
  withr::local_envvar(c(PDB_PATH = staged), .local_envir = .local_envir)
  withr::local_dir(working, .local_envir = .local_envir)
  invisible(staged)
}

skip_stan_integration <- function() {
  testthat::skip_if_not(
    identical(Sys.getenv("PDB_TEST_STAN"), "true"),
    "set PDB_TEST_STAN=true for real Stan tests"
  )
}

skip_github_integration <- function() {
  testthat::skip_if_not(
    identical(Sys.getenv("PDB_TEST_GITHUB"), "true"),
    "set PDB_TEST_GITHUB=true for live GitHub tests"
  )
}
