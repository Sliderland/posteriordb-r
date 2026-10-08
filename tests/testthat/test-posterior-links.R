test_that("posterior name lookups follow metadata links rather than filename spelling", {
  root <- tempfile("posterior-links-")
  for (path in c("posteriors", "cache")) dir.create(file.path(root, path), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  records <- list(
    "unit-data-unit-model" = list(data_name = "unit-data", model_name = "unit-model"),
    "unrelated.filename" = list(data_name = "unit-data", model_name = "unit-model"),
    "unit-data-other-model" = list(data_name = "other-data", model_name = "other-model")
  )
  for (name in names(records)) jsonlite::write_json(
    c(list(name = name, added_date = "2026-01-01"), records[[name]]),
    file.path(root, "posteriors", paste0(name, ".json")), auto_unbox = TRUE)
  data <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(name = "unit-data",
    title = "Inputs", added_by = "test", added_date = Sys.Date())))
  model_info <- as.pdb_model_info(list(name = "unit-model", title = "Model",
    framework = "stan", added_by = "test", added_date = Sys.Date()))
  model <- as.model_code("parameters { real theta; }", info = model_info, framework = "stan")
  for (object in list(data, model, model_info)) {
    # Standalone objects still require a connection for database link queries.
    expect_error(posterior_names(object))
    attr(object, "pdb") <- connection
    expect_setequal(posterior_names(object), names(records)[1:2])
  }
  named_data <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(
    name = c(id = "unit-data"), title = "Inputs", added_by = "test", added_date = Sys.Date()
  )))
  attr(named_data, "pdb") <- connection
  expect_setequal(posterior_names(named_data), names(records)[1:2])
  attr(model_info, "pdb") <- connection
  model_info$name <- "not-linked"
  expect_identical(posterior_names(model_info), character())
  unlink(file.path(root, "posteriors"), recursive = TRUE)
  expect_identical(posterior_names(model_info), character())
})
