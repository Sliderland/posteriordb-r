cache_archive_fixture <- function(members, contents = '{"value":1}') {
  drive_member <- identical(members, "C:drive.json")
  if (drive_member) members <- "x-drive.json"
  root <- tempfile("cache-archive-")
  source <- file.path(root, "database")
  cache <- file.path(root, "cache")
  stage <- file.path(root, "stage")
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  for (folder in c(file.path(source, "data/data"), file.path(cache, "data/data"), stage))
    dir.create(folder, recursive = TRUE)
  sentinel <- file.path(cache, "data/sentinel.json")
  writeLines("sentinel", sentinel)
  for (member in members) {
    path <- file.path(stage, member)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(contents, path)
  }
  archive <- file.path(source, "data/data/value.json.zip")
  previous <- setwd(stage)
  on.exit(setwd(previous), add = TRUE)
  utils::zip(archive, members, flags = "-q")
  if (drive_member) {
    # Alter both ZIP filename headers without creating an invalid Windows path.
    bytes <- readBin(archive, "raw", n = file.info(archive)$size)
    for (offset in grepRaw("x-drive.json", bytes, fixed = TRUE, all = TRUE))
      bytes[offset + 0:1] <- charToRaw("C:")
    writeBin(bytes, archive)
  }
  list(pdb = structure(list(pdb_local_endpoint = source, cache_path = cache),
    class = c("pdb_local", "pdb")), cache = cache, sentinel = sentinel, archive = archive)
}

test_that("cache extraction validates archive members before extracting", {
  fixture <- cache_archive_fixture("value.json")
  path <- pdb_cached_local_file_path(fixture$pdb, "data/data/value.json", unzip = TRUE)
  expect_identical(readLines(path), '{"value":1}')
  expect_false(file.exists(paste0(path, ".zip")))
  expect_identical(pdb_cached_local_file_path(fixture$pdb, "data/data/value.json", unzip = TRUE), path)

  for (members in list("other.json", "nested/value.json", "../sentinel.json",
                       "C:drive.json", c("value.json", "extra.json"))) {
    fixture <- cache_archive_fixture(members)
    expect_error(pdb_cached_local_file_path(fixture$pdb, "data/data/value.json", unzip = TRUE), "Archive member|single JSON member|single path components")
    expect_identical(readLines(fixture$sentinel), "sentinel")
    expect_length(list.files(file.path(fixture$cache, "data/data")), 0L)
  }
})

test_that("damaged ZIP extraction cannot leave reusable partial output", {
  fixture <- cache_archive_fixture("value.json",
    paste0('{"value":"', strrep("A", 10000), '"}'))
  bytes <- readBin(fixture$archive, "raw", n = file.info(fixture$archive)$size)
  # First local ZIP header: filename and extra-field lengths locate deflate data.
  filename_length <- sum(as.integer(bytes[27:28]) * c(1, 256))
  extra_length <- sum(as.integer(bytes[29:30]) * c(1, 256))
  bytes[31L + filename_length + extra_length] <- as.raw(255L)
  writeBin(bytes, fixture$archive)
  expect_identical(pdb_json_archive_member(fixture$archive), "value.json")
  expect_error(pdb_cached_local_file_path(fixture$pdb, "data/data/value.json", unzip = TRUE),
               "extracting|unzip")
  path <- file.path(fixture$cache, "data/data/value.json")
  expect_false(file.exists(path))
  expect_false(file.exists(paste0(path, ".zip")))
  expect_true(file.exists(fixture$archive))
  destination <- file.path(fixture$cache, "renamed")
  expect_error(rename_pdb_stage_zip(fixture$archive, destination, "renamed.json"),
               "extracting|unzip")
  expect_false(file.exists(destination))
  expect_false(file.exists(paste0(destination, ".zip")))
})

test_that("cache paths reject traversal and escaping symlinks before mutation", {
  fixture <- cache_archive_fixture("value.json")
  before <- list.files(fixture$cache, recursive = TRUE)
  expect_error(pdb_cached_local_file_path(fixture$pdb, "../escape/new.json"), "paths must be relative")
  expect_false(dir.exists(file.path(dirname(fixture$cache), "escape")))
  expect_identical(list.files(fixture$cache, recursive = TRUE), before)
  skip_if_not(file.symlink(dirname(fixture$cache), file.path(fixture$cache, "escape")))
  expect_error(pdb_cached_local_file_path(fixture$pdb, "escape/new.json"), "outside")
  expect_identical(pdb_cache_path(fixture$pdb, ""), file.path(fixture$cache, ""))
  expect_length(pdb_cache_path(fixture$pdb, character()), 0L)
  expect_length(pdb_cache_path(fixture$pdb, c("data/a.json", "data/b.json")), 2L)
})

test_that("a failed plain-file copy reports the failed destination", {
  for (failure in c("status", "error")) {
    fixture <- cache_archive_fixture("value.json")
    copies <- 0L
    testthat::local_mocked_bindings(pdb_file_copy = function(pdb, from, to, ...) {
      copies <<- copies + 1L
      writeLines(if (copies == 1L) "partial" else "complete", to)
      if (copies == 1L) {
        if (failure == "error") stop("injected copy failure")
        return(FALSE)
      }
      TRUE
    }, .package = "posteriordb")
    destination <- file.path(fixture$cache, "data/data/value.json")
    expect_error(pdb_cached_local_file_path(fixture$pdb, "data/data/value.json"),
      if (failure == "status") destination else "injected copy failure", fixed = TRUE)
    expect_false(file.exists(destination))
    path <- pdb_cached_local_file_path(fixture$pdb, "data/data/value.json")
    expect_identical(readLines(path), "complete")
    expect_identical(copies, 2L)
  }
})
