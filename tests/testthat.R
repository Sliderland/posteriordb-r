library(testthat)
library(posteriordb)

(function() {
  source <- getOption("pdb_path", Sys.getenv("PDB_PATH"))
  staged <- tempfile("posteriordb-tests-")
  on.exit(unlink(staged, recursive = TRUE), add = TRUE)
  if (source == "") {
    git2r::clone("https://github.com/stan-dev/posteriordb", local_path = staged)
  } else {
    source <- normalizePath(source, winslash = "/", mustWork = TRUE)
    parent <- normalizePath(dirname(staged), winslash = "/", mustWork = TRUE)
    if (startsWith(paste0(parent, "/"), paste0(sub("/+$", "", source), "/"))) {
      stop("The test staging directory must be outside the source database")
    }
    dir.create(staged)
    files <- list.files(source, all.files = TRUE, full.names = TRUE, no.. = TRUE)
    if (!all(file.copy(files, staged, recursive = TRUE))) {
      stop("Could not copy the source database for testing")
    }
  }
  old_options <- options(pdb_path = staged)
  old_path <- Sys.getenv("PDB_PATH", unset = NA_character_)
  on.exit({
    options(old_options)
    if (is.na(old_path)) Sys.unsetenv("PDB_PATH") else Sys.setenv(PDB_PATH = old_path)
  }, add = TRUE)
  Sys.setenv(PDB_PATH = staged)
  test_check("posteriordb")
})()
