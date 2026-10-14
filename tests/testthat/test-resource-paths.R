resource_path_fixture <- function() {
  parent <- tempfile("resource-paths-")
  root <- file.path(parent, "database")
  outside <- file.path(parent, "database-sibling")
  for (folder in c("data", "models", "posteriors", "cache", "alias")) {
    dir.create(file.path(root, folder), recursive = TRUE)
  }
  dir.create(outside)
  writeLines("sentinel", file.path(outside, "sentinel"))
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  withr::defer(unlink(parent, recursive = TRUE), envir = parent.frame())
  list(
    pdb = pdb_local(root, cache_path = file.path(root, "cache")),
    root = normalizePath(root),
    outside = normalizePath(outside),
    parent = parent
  )
}

resource_path_snapshot <- function(parent) {
  paths <- list.files(
    parent,
    recursive = TRUE,
    all.files = TRUE,
    include.dirs = TRUE
  )
  stats::setNames(
    lapply(file.path(parent, paths), function(path) {
      if (dir.exists(path)) {
        return("directory")
      }
      if (!file.exists(path)) {
        return(Sys.readlink(path))
      }
      readBin(path, "raw", n = file.info(path)$size)
    }),
    paths
  )
}

test_that("a contained file cannot conceal an escaping parent directory", {
  fixture <- resource_path_fixture()
  internal <- file.path(fixture$root, "internal.json")
  writeLines("original", internal)
  skip_if_not(file.symlink(internal, file.path(fixture$outside, "safe.json")))
  skip_if_not(file.symlink(fixture$outside, file.path(fixture$root, "escape")))
  before <- resource_path_snapshot(fixture$parent)
  expect_error(
    write_json_to_path(
      "payload",
      "escape",
      fixture$pdb,
      name = "safe",
      info = FALSE,
      overwrite = TRUE
    ),
    "outside the database"
  )
  expect_identical(resource_path_snapshot(fixture$parent), before)
})
