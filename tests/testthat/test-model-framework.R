test_that("model-code constructors honor supported frameworks and matching metadata", {
  frameworks <- c("stan", "pymc3", "pymc", "tfp", "pyro")
  for (framework in frameworks) {
    metadata <- as.pdb_model_info(list(name = "model", title = "Model", framework = framework,
      added_by = "test", added_date = Sys.Date()))
    code <- as.model_code("example code", info = metadata, framework = framework)
    expect_identical(framework(code), framework)
    expect_identical(as.character(code), "example code")
    expect_identical(info(code), metadata)
  }
  stan_info <- as.pdb_model_info(list(name = "model", title = "Model", framework = "stan",
    added_by = "test", added_date = Sys.Date()))
  expect_identical(framework(as.model_code("example code", info = stan_info)), "stan")
  expect_identical(framework(as.stan_code("example code", info = stan_info)), "stan")
  expect_error(as.model_code("example code", info = stan_info, framework = "unknown"), "Must be element of set")
  expect_error(as.model_code("example code", info = stan_info, framework = "pyro"), "model_implementations")
})
