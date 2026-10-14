test_that("connection subclasses retain their database type and cache identity", {
  for (type in c("local", "github")) {
    connection <- structure(
      list(pdb_id = "fixture"),
      class = c(paste0("pdb_", type), "pdb")
    )
    child <- connection
    class(child) <- c("custom_connection", class(child))
    expect_identical(pdb_type(child), type)
    expect_identical(
      pdb_cache_namespace(child),
      pdb_cache_namespace(connection)
    )
  }
})
