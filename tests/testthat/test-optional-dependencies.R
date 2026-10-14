optional_dependency_database <- function() {
  root <- normalizePath(
    withr::local_tempdir(.local_envir = parent.frame()),
    winslash = "/"
  )
  for (path in c("data", "models", "posteriors", "cache", "alias")) {
    dir.create(file.path(root, path))
  }
  writeLines("{}", file.path(root, "alias/posteriors.json"))
  jsonlite::write_json(
    list(
      name = "inputs-model",
      model_name = "model",
      data_name = "inputs",
      reference_posterior_name = NULL,
      dimensions = list(theta = 1L),
      added_by = "test",
      added_date = "2026-01-01"
    ),
    file.path(root, "posteriors/inputs-model.json"),
    auto_unbox = TRUE,
    null = "null"
  )
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  write_pdb(
    as.pdb_model_info(list(
      name = "model",
      title = "Model",
      framework = "stan",
      added_by = "test",
      added_date = Sys.Date()
    )),
    connection
  )
  write_pdb(
    as.pdb_data_info(list(
      name = "inputs",
      title = "Inputs",
      added_by = "test",
      added_date = Sys.Date()
    )),
    connection
  )
  connection
}

test_that("local lookup and metadata tables do not require optional workflow packages", {
  connection <- optional_dependency_database()
  original <- base::requireNamespace
  testthat::local_mocked_bindings(
    requireNamespace = function(package, ...) {
      if (
        package %in% c("yaml", "remotes", "httr", "dplyr", "rstan", "cmdstanr")
      ) {
        return(FALSE)
      }
      original(package, ...)
    },
    .package = "base"
  )
  expect_identical(posterior_names(connection), "inputs-model")
  expect_identical(
    posterior("inputs-model", connection)$dimensions,
    list(theta = 1L)
  )
  table <- posteriors_tbl_df(connection)
  expect_s3_class(table, "tbl_df")
  expect_identical(table$name, "inputs-model")
  expect_output(print(connection), "Posterior Database")
})
