# Integration tests opt in explicitly; configured user paths alone do not opt in.
local_test_database <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not(identical(Sys.getenv("PDB_TEST_DATABASE"), "true"),
    "set PDB_TEST_DATABASE=true for corpus integration tests")
  source <- getOption("pdb_path", Sys.getenv("PDB_PATH"))
  testthat::skip_if_not(nzchar(source), "set PDB_PATH to an existing corpus")
  source <- normalizePath(source, winslash = "/", mustWork = TRUE)
  parent <- withr::local_tempdir(pattern = "pdb-test-", .local_envir = .local_envir)
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  if (startsWith(paste0(parent, "/"), paste0(sub("/+$", "", source), "/")))
    stop("The test staging directory must be outside the source database")
  staged <- file.path(parent, "database")
  dir.create(staged)
  files <- list.files(source, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  # ponytail: copy per corpus test; replace heavy cases with small fixtures if copy cost matters.
  if (!all(file.copy(files, staged, recursive = TRUE))) stop("Could not copy the test corpus")
  working <- file.path(parent, "working")
  dir.create(working)
  withr::local_options(list(pdb_path = staged), .local_envir = .local_envir)
  withr::local_envvar(c(PDB_PATH = staged), .local_envir = .local_envir)
  withr::local_dir(working, .local_envir = .local_envir)
  invisible(staged)
}

skip_stan_integration <- function() {
  testthat::skip_if_not(identical(Sys.getenv("PDB_TEST_STAN"), "true"),
    "set PDB_TEST_STAN=true for real Stan tests")
}

skip_github_integration <- function() {
  testthat::skip_if_not(identical(Sys.getenv("PDB_TEST_GITHUB"), "true"),
    "set PDB_TEST_GITHUB=true for live GitHub tests")
}
