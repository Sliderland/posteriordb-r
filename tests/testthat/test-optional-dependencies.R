optional_dependency_database <- function() {
  root <- normalizePath(withr::local_tempdir(.local_envir = parent.frame()), winslash = "/")
  for (path in c("data", "models", "posteriors", "cache", "alias")) dir.create(file.path(root, path))
  writeLines("{}", file.path(root, "alias/posteriors.json"))
  jsonlite::write_json(list(name = "inputs-model", model_name = "model", data_name = "inputs",
    reference_posterior_name = NULL, dimensions = list(theta = 1L),
    added_by = "test", added_date = "2026-01-01"),
    file.path(root, "posteriors/inputs-model.json"), auto_unbox = TRUE, null = "null")
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  write_pdb(as.pdb_model_info(list(name = "model", title = "Model", framework = "stan",
    added_by = "test", added_date = Sys.Date())), connection)
  write_pdb(as.pdb_data_info(list(name = "inputs", title = "Inputs",
    added_by = "test", added_date = Sys.Date())), connection)
  connection
}

test_that("local lookup and metadata tables do not require optional workflow packages", {
  connection <- optional_dependency_database()
  original <- base::requireNamespace
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (package %in% c("yaml", "remotes", "httr", "dplyr", "rstan", "cmdstanr")) return(FALSE)
    original(package, ...)
  }, .package = "base")
  expect_identical(posterior_names(connection), "inputs-model")
  expect_identical(posterior("inputs-model", connection)$dimensions, list(theta = 1L))
  table <- posteriors_tbl_df(connection)
  expect_s3_class(table, "tbl_df")
  expect_identical(table$name, "inputs-model")
  expect_output(print(connection), "Posterior Database")
})

test_that("posterior name lookups warn about extras without changing their result", {
  connection <- optional_dependency_database()
  expect_silent(expected <- posterior("inputs-model", connection))
  expect_warning(actual <- posterior("inputs-model", connection, typo = TRUE), "disregarded")
  expect_identical(actual, expected)
  expect_warning(actual <- pdb_posterior("inputs-model", connection, TRUE), "disregarded")
  expect_identical(actual, expected)
  expect_warning(actual <- posterior("inputs-model", connection,
    ignored = stop("Unused arguments must not be evaluated")), "disregarded")
  expect_identical(actual, expected)
  expect_warning(actual <- posterior("inputs-model", connection,
    allowed = stop("Unused arguments must not be evaluated"),
    which.call = stop("Unused arguments must not be evaluated")), "disregarded")
  expect_identical(actual, expected)
})

test_that("optional workflows report missing dependencies before network work", {
  connection <- optional_dependency_database()
  original <- base::requireNamespace
  missing <- c("yaml", "remotes", "httr", "dplyr")
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (package %in% missing) return(FALSE)
    original(package, ...)
  }, .package = "base")
  testthat::local_mocked_bindings(gh = function(...) stop("Network reached"), .package = "gh")
  expect_error(pdb_config(connection$pdb_local_endpoint), "yaml")
  configured <- connection
  configured$.pdb_config.yml <- list(type = "local")
  expect_error(print(configured), "yaml")
  expect_error(pdb_github("stan-dev/posteriordb"), "remotes")
  github <- structure(list(), class = c("pdb_github", "pdb"))
  expect_error(posteriordb:::pdb_file_copy.pdb_github(github, "file.json", tempfile()), "httr")
  expect_error(posteriordb:::pdb_cache_dir.pdb_github(github, "posteriors"), "httr")
  expect_error(posteriordb:::github_download("https://example.com/file.json", tempfile(),
    pat = NULL, overwrite = FALSE), "httr")
  expect_error(filter_posteriors(connection, name == "inputs-model"), "dplyr")
})

test_that("configuration selects only supported constructors without evaluating YAML", {
  skip_if_not_installed("yaml")
  connection <- optional_dependency_database()
  directory <- connection$pdb_local_endpoint
  config <- file.path(directory, ".pdb_config.yml")
  yaml::write_yaml(list(type = "local", path = directory), config)
  expect_identical(pdb_config(directory)$pdb_local_endpoint, directory)
  sentinel <- file.path(directory, "injected")
  withr::local_options(list(yaml.eval.expr = TRUE))
  writeLines(c("type: !expr |", paste0("  {writeLines('executed', ",
    encodeString(sentinel, quote = '"'), "); 'unknown'}")), config)
  expect_error(pdb_config(directory), "obj.+type.+failed")
  expect_false(file.exists(sentinel))
  for (type in list("unknown", c("local", "github"), NULL,
    paste0("local; writeLines('injected', ", encodeString(sentinel, quote = '"'), "); pdb_local"))) {
    yaml::write_yaml(list(type = type, path = directory), config)
    expect_error(pdb_config(directory), "obj.+type.+failed")
    expect_false(file.exists(sentinel))
  }
})
