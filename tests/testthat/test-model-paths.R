test_that("model reads and removal follow declared paths for every supported framework", {
  root <- tempfile("model-paths-")
  dir.create(file.path(root, "cache"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  for (framework in c("stan", "pymc3", "pymc", "tfp", "pyro")) {
    for (custom in c(FALSE, TRUE)) {
      name <- paste("model", framework, custom, sep = "-")
      extension <- if (framework == "stan") "stan" else "py"
      relative <- file.path("models", framework,
        paste0(if (custom) "custom.source.v2" else name, ".", extension))
      metadata <- as.pdb_model_info(list(name = name, title = "Model", framework = framework,
        model_implementations = stats::setNames(list(list(model_code = relative)), framework),
        added_by = "test", added_date = Sys.Date(), keywords = NULL))
      write_pdb(metadata, connection)
      source <- file.path(root, relative)
      dir.create(dirname(source), recursive = TRUE, showWarnings = FALSE)
      writeLines("# fixture code", source)
      expect_identical(readLines(model_code_file_path(name, framework, connection)), "# fixture code")
      code <- model_code(name, framework, connection)
      expect_identical(as.character(code), "# fixture code")
      expect_identical(framework(code), framework)
      expect_identical(info(code), metadata)
      expect_identical(model_code(metadata, framework, connection), code)
      object <- structure(list(model_name = name, model_info = metadata), class = "pdb_posterior", pdb = connection)
      expect_identical(model_code_file_path(object, framework), model_code_file_path(metadata, framework, connection))
      expect_identical(model_code(object, framework), code)
      remove_pdb(code, connection, remove_info = FALSE)
      expect_false(file.exists(source))
      expect_true(file.exists(file.path(root, "models/info", paste0(name, ".info.json"))))
    }
  }
})

test_that("legacy PyMC metadata without a code path uses its conventional Python path", {
  root <- tempfile("legacy-model-path-")
  for (path in c("models/pymc", "cache")) dir.create(file.path(root, path), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  metadata <- as.pdb_model_info(list(name = "legacy", title = "Model",
    model_implementations = list(pymc = list(pymc_version = "legacy")),
    added_by = "test", added_date = Sys.Date(), keywords = NULL))
  write_pdb(metadata, connection)
  source <- file.path(root, "models/pymc/legacy.py")
  writeLines("# legacy fixture", source)
  code <- model_code(metadata, "pymc", connection)
  expect_identical(as.character(code), "# legacy fixture")
  expect_error(model_code_file_path(metadata, "pyro", connection))
  remove_pdb(code, connection, remove_info = FALSE)
  expect_false(file.exists(source))
})

test_that("failed code removal preserves its metadata and reports the path", {
  root <- normalizePath(withr::local_tempdir(), winslash = "/")
  dir.create(file.path(root, "cache"))
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  metadata <- as.pdb_model_info(list(name = "model", title = "Model", framework = "stan",
    added_by = "test", added_date = Sys.Date()))
  write_pdb(metadata, connection)
  source <- file.path(root, "models/stan/model.stan")
  dir.create(dirname(source), recursive = TRUE)
  writeLines("parameters {}", source)
  code <- model_code(metadata, "stan", connection)
  removed <- character()
  testthat::local_mocked_bindings(file.remove = function(...) {
    removed <<- c(removed, ...)
    FALSE
  }, .package = "base")
  expect_error(remove_pdb(code, connection), source, fixed = TRUE)
  expect_identical(removed, source)
  expect_true(file.exists(source))
  expect_true(file.exists(file.path(root, "models/info/model.info.json")))
})

test_that("posterior code and file-path getters use the same supplied metadata", {
  root <- tempfile("posterior-model-path-")
  for (path in c("data", "models/stan", "posteriors", "cache"))
    dir.create(file.path(root, path), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  stored <- as.pdb_model_info(list(name = "model", title = "Model", framework = "stan",
    added_by = "test", added_date = Sys.Date()))
  write_pdb(stored, connection)
  writeLines("parameters { real original; }", file.path(root, "models/stan/model.stan"))
  selected <- "parameters { real selected; }"
  writeLines(selected, file.path(root, "models/stan/custom.stan"))
  supplied <- stored
  supplied$model_implementations$stan$model_code <- "models/stan/custom.stan"
  data <- as.pdb_data(list(), info = as.pdb_data_info(list(name = "inputs", title = "Inputs",
    added_by = "test", added_date = Sys.Date())))
  code <- as.model_code(selected, info = supplied, framework = "stan")
  object <- as.posterior(list(pdb_model_code = code, pdb_data = data, dimensions = list(selected = 1L),
    added_by = "test", added_date = Sys.Date()), pdb = connection)
  expect_identical(readLines(model_code_file_path(object, "stan")), selected)
  expect_identical(as.character(model_code(object, "stan")), selected)
  stored$model_implementations$pymc <- list(model_code = "models/pymc/additional.py")
  write_pdb(stored, connection, overwrite = TRUE)
  dir.create(file.path(root, "models/pymc"))
  writeLines("# additional implementation", file.path(root, "models/pymc/additional.py"))
  pdb_clear_cache(connection)
  expect_identical(readLines(model_code_file_path(object, "pymc")), "# additional implementation")
  expect_identical(as.character(model_code(object, "pymc")), "# additional implementation")
})
