test_that("connection subclasses retain their database type and cache identity", {
  for (type in c("local", "github")) {
    connection <- structure(list(pdb_id = "fixture"), class = c(paste0("pdb_", type), "pdb"))
    child <- connection
    class(child) <- c("custom_connection", class(child))
    expect_identical(posteriordb:::pdb_type(child), type)
    expect_identical(posteriordb:::pdb_cache_namespace(child),
      posteriordb:::pdb_cache_namespace(connection))
  }
})

test_that("subclassed metadata writes the same JSON through the public writer", {
  root <- tempfile("subclass-write-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root), class = c("pdb_local", "pdb"))
  metadata <- as.data_info(list(name = "fixture", title = "Fixture",
    added_by = "test", added_date = Sys.Date()))
  write_pdb(metadata, connection)
  path <- file.path(root, "data/info/fixture.info.json")
  expected <- readLines(path)
  class(metadata) <- c("custom_metadata", class(metadata))
  expect_silent(write_pdb(metadata, connection, overwrite = TRUE))
  expect_identical(readLines(path), expected)
})
