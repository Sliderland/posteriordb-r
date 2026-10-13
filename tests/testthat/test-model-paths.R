
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
