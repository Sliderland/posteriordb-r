summary_reference_fixture <- function(types = c("mean_value", "mean_squared_value")) {
  root <- withr::local_tempdir("summary-identity-", .local_envir = parent.frame())
  for (path in c("data", "models", "posteriors", "alias", "cache"))
    dir.create(file.path(root, path), recursive = TRUE)
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
  for (component in list(data, model)) write_pdb(component, connection)
  metadata <- as.reference_posterior_info(list(name = "distinct-reference",
    inference = list(method = "analytical", method_arguments = list()), diagnostics = NULL,
    checks_made = NULL, comments = "fixture", added_by = "test", added_date = Sys.Date(),
    versions = list(r_version = "fixture")))
  write_pdb(metadata, connection, type = "draws")
  draws <- as.reference_posterior_draws(posterior::as_draws_list(list(list(theta = 1))),
    info = metadata)
  write_json_to_path(draws, "reference_posteriors/draws/draws", connection,
    zip = TRUE, info = FALSE)
  write_pdb(object, connection)
  for (type in types) {
    write_pdb(metadata, connection, type = type)
    directory <- file.path(root, "reference_posteriors/summary_statistics", type, type)
    dir.create(directory, recursive = TRUE)
    jsonlite::write_json(stats::setNames(list("theta", 2.5, .01), c("names", type, "mcse_mean")),
      file.path(directory, "distinct-reference.json"), auto_unbox = TRUE)
  }
  list(root = root, connection = connection, object = object, metadata = metadata)
}

test_that("summary readers use a distinct reference name for payload and metadata", {
  fixture <- summary_reference_fixture()
  object <- fixture$object
  connection <- fixture$connection
  metadata <- fixture$metadata
  types <- c("mean_value", "mean_squared_value")
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


test_that("plural summary access omits types without metadata and unlinked posteriors", {
  fixture <- summary_reference_fixture(types = "mean_value")
  summaries <- reference_posterior_summary_statistics(fixture$object)
  expect_identical(names(summaries), "mean_value")
  expect_equal(summaries$mean_value$mean_value, 2.5)
  empty <- summary_reference_fixture(types = character())
  expect_identical(reference_posterior_summary_statistics(empty$object), list())
  empty$object$reference_posterior_name <- NULL
  attr(empty$object, "pdb") <- NULL
  expect_identical(reference_posterior_summary_statistics(empty$object), list())
})

test_that("plural summary access reports corrupt or incomplete advertised summaries", {
  for (failure in c("payload", "metadata", "missing_payload")) {
    fixture <- summary_reference_fixture(types = "mean_value")
    directory <- file.path(fixture$root, "reference_posteriors/summary_statistics/mean_value")
    payload <- file.path(directory, "mean_value/distinct-reference.json")
    metadata <- file.path(directory, "info/distinct-reference.info.json")
    if (failure == "payload") writeLines("not-json", payload)
    if (failure == "metadata") writeLines("not-json", metadata)
    if (failure == "missing_payload") unlink(payload)
    expect_error(reference_posterior_summary_statistics(fixture$object), info = failure)
  }
})

test_that("plural summary access propagates transport errors without network work", {
  connection <- structure(list(github = list(username = "fixture", repo = "database",
    subdir = "posterior_database", ref = "fixture-ref")), class = c("pdb_github", "pdb"))
  object <- structure(list(reference_posterior_name = "distinct-reference"),
    class = "pdb_posterior", pdb = connection)
  testthat::local_mocked_bindings(gh = function(...) stop("transport failed"), .package = "gh")
  expect_error(reference_posterior_summary_statistics(object), "transport failed")
})
