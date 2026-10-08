# Run the complete testthat suite against an isolated snapshot of the local
# PosteriorDB checkout and save console output to scripts/test-suite.log.

run_test_suite <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) stop("Run this script with Rscript scripts/run_test_suite.R")
  script_path <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
  scripts_dir <- dirname(script_path)
  repo_root <- normalizePath(file.path(scripts_dir, ".."), mustWork = TRUE)
  setwd(repo_root)

  source_repo <- Sys.getenv(
    "PDB_SOURCE_REPO",
    unset = path.expand("~/Downloads/posteriordb")
  )
  if (!dir.exists(file.path(source_repo, ".git"))) {
    stop(
      "Cannot find the source PosteriorDB Git checkout at ", source_repo,
      ". Set PDB_SOURCE_REPO to its path.",
      call. = FALSE
    )
  }

  isolated_root <- tempfile("posteriordb-test-suite-")
  dir.create(isolated_root, recursive = TRUE)
  on.exit(unlink(isolated_root, recursive = TRUE, force = TRUE), add = TRUE)
  archive <- tempfile(fileext = ".tar")
  on.exit(unlink(archive), add = TRUE)
  status <- system2(
    "git",
    c("-C", shQuote(source_repo), "archive", "--format=tar", "HEAD", "posterior_database"),
    stdout = archive
  )
  if (!identical(status, 0L)) {
    stop("Could not snapshot posterior_database from the source Git checkout.", call. = FALSE)
  }
  utils::untar(archive, exdir = isolated_root)
  test_db <- file.path(isolated_root, "posterior_database")
  if (!dir.exists(test_db)) stop("The source checkout has no posterior_database directory.", call. = FALSE)

  # Keep the repository-shaped root: some package tests also exercise
  # discovery of the nested posterior_database endpoint.
  Sys.setenv(PDB_PATH = isolated_root)
  options(pdb_path = isolated_root)
  testthat::set_max_fails(Inf)

  log_path <- file.path(scripts_dir, "test-suite.log")
  log_connection <- file(log_path, open = "wt")
  output_sinks <- sink.number()
  message_sinks <- sink.number(type = "message")
  sink(log_connection, split = TRUE)
  sink(log_connection, type = "message")
  on.exit({
    while (sink.number(type = "message") > message_sinks) sink(type = "message")
    while (sink.number() > output_sinks) sink()
    close(log_connection)
  }, add = TRUE)

  cat("Test suite started: ", format(Sys.time()), "\n", sep = "")
  cat("Package checkout: ", repo_root, "\n", sep = "")
  cat("Isolated PDB snapshot: ", test_db, "\n\n", sep = "")
  devtools::test(pkg = repo_root)
  cat("\nTest suite finished: ", format(Sys.time()), "\n", sep = "")
  cat("Full output saved to: ", log_path, "\n", sep = "")
  invisible(log_path)
}

run_test_suite()
