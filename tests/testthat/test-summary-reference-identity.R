test_that("summary readers use a distinct reference name for payload and metadata", {
  root <- tempfile("summary-identity-")
  for (path in c("data", "models", "posteriors", "alias", "cache"))
    dir.create(file.path(root, path), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("{}", file.path(root, "alias/posteriors.json"))
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  data <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(name = "inputs",
    title = "Inputs", added_by = "test", added_date = Sys.Date())))
  model <- as.model_code("parameters { real theta; }", framework = "stan",
    info = as.pdb_model_info(list(name = "model", title = "Model", framework = "stan",
      added_by = "test", added_date = Sys.Date())))
  object <- as.posterior(list(pdb_data = data, pdb_model_code = model,
    dimensions = list(theta = 1L), reference_posterior_name = "distinct-reference",
    added_by = "test", added_date = Sys.Date()), pdb = connection)
  for (component in list(data, model, object)) write_pdb(component, connection)
  metadata <- as.reference_posterior_info(list(name = "distinct-reference",
    inference = list(method = "analytical", method_arguments = list()), diagnostics = NULL,
    checks_made = NULL, comments = "fixture", added_by = "test", added_date = Sys.Date(),
    versions = list(r_version = "fixture")))
  types <- c("mean_value", "mean_squared_value")
  for (type in types) {
    write_pdb(metadata, connection, type = type)
    directory <- file.path(root, "reference_posteriors/summary_statistics", type, type)
    dir.create(directory, recursive = TRUE)
    jsonlite::write_json(stats::setNames(list("theta", 2.5, .01), c("names", type, "mcse_mean")),
      file.path(directory, "distinct-reference.json"), auto_unbox = TRUE)
  }
  # Multi-summary access must not silently drop summaries whose names differ.
  summaries <- reference_posterior_summary_statistics(object)
  expect_setequal(names(summaries), types)
  for (type in types) {
    direct <- reference_posterior_summary_statistic(object, type = type)
    expect_identical(info(direct), metadata)
    expect_equal(direct[[type]], 2.5)
    expect_identical(reference_posterior_summary_statistic(object$name, connection, type = type), direct)
    expect_identical(reference_posterior_summary_statistic(metadata, connection, type = type), direct)
    expect_identical(summaries[[type]], direct)
  }
})
