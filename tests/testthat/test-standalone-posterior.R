standalone_posterior_fixture <- function() {
  date <- as.Date("2026-09-24")
  dat <- as.pdb_data(list(y = matrix(1:6, 2, 3)), info = as.pdb_data_info(list(
    name = "standalone-data", title = "Inputs", added_by = "Tester", added_date = date)))
  code <- as.pdb_model_code("parameters { vector[1] theta; } model { theta ~ normal(0,1); }",
    info = as.pdb_model_info(list(name = "standalone-model", title = "Model",
      framework = "stan", added_by = "Tester", added_date = date)), framework = "stan")
  ri <- as.pdb_reference_posterior_info(list(
    name = "standalone-data-standalone-model",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = NULL, checks_made = NULL, comments = "Fixture",
    added_by = "Tester", added_date = date, versions = NULL))
  draws <- posterior::as_draws_list(array(seq_len(40), c(10, 4, 1),
    dimnames = list(NULL, NULL, "theta[1]")))
  ref <- as.pdb_reference_posterior_draws(draws, info = ri)
  as.pdb_posterior(list(pdb_data = dat, pdb_model_code = code,
    dimensions = list(theta = 1L), reference_posterior_name = ri$name,
    added_by = "Tester", added_date = date, embedded_data = dat,
    embedded_model_code = code, embedded_reference_draws = ref), pdb = NULL)
}

test_that("embedded content is validated with and without an attached database", {
  po <- standalone_posterior_fixture()
  expect_silent(assert_pdb_posterior(po))
  expect_identical(get_data(po)$y, matrix(1:6, 2, 3))
  expect_equal(reference_posterior_draws_info(po), info(po$embedded_reference_draws))
  expect_error(model_code(po, "pymc"), "No embedded model code")
  expect_error(reference_posterior_info(po, "mean"), "attach a database")
  missing <- po
  missing$embedded_data <- NULL
  expect_error(assert_pdb_posterior(missing), "requires embedded")
  # Connection construction is irrelevant here: assertions only require its
  # class, and getter mocks below prove the fallback without database access.
  for (connection in list(NULL, structure(list(), class = "pdb"))) {
    bad <- po
    pdb(bad) <- connection
    bad$data_name <- "wrong"
    expect_error(assert_pdb_posterior(bad), "data link")
    bad <- po
    pdb(bad) <- connection
    bad$dimensions <- list(other_parameter = 1L)
    expect_error(assert_pdb_posterior(bad), "missing parameter variables")
    bad <- po
    pdb(bad) <- connection
    bad$reference_posterior_name <- "wrong"
    expect_error(assert_pdb_posterior(bad), "reference link")
  }
  pdb(po) <- structure(list(), class = "pdb")
  testthat::local_mocked_bindings(model_code.character = function(x, framework, pdb, ...) {
    expect_identical(x, "standalone-model")
    expect_identical(framework, "pymc")
    "database implementation"
  })
  expect_identical(model_code(po, "pymc"), "database implementation")
  expect_identical(model_code(po, "stan"), po$embedded_model_code)
})

test_that("standalone content survives serialization in a fresh R process", {
  po <- standalone_posterior_fixture()
  # Only the extraction boundary is stubbed; construction and all getters use
  # the public API. The real stanfit extraction is covered separately.
  extracted <- list(draws = posterior::as_draws_array(po$embedded_reference_draws),
    sampler_diagnostics = NULL, metadata = list(),
    source = as.character(po$embedded_model_code), dimensions = po$dimensions,
    fit_class = "stanfit", import_versions = list())
  testthat::local_mocked_bindings(extract_rstan_fit = function(...) extracted)
  bundle <- create_pdb_bundle(structure(list(), class = "stanfit"),
    data = list(y = get_data(po)$y),
    data_info = list(name = "standalone-data", title = "Inputs"),
    model_info = list(name = "standalone-model", title = "Model"), check = FALSE)
  serialized <- tempfile(fileext = ".rds")
  script <- tempfile(fileext = ".R")
  on.exit(unlink(c(serialized, script)), add = TRUE)
  saveRDS(bundle, serialized)
  package_path <- getNamespaceInfo(asNamespace("posteriordb"), "path")
  config <- list(libraries = .libPaths(), package_path = package_path, rds = serialized)
  config_path <- tempfile(fileext = ".rds")
  on.exit(unlink(config_path), add = TRUE)
  saveRDS(config, config_path)
  writeLines(c(
    "config <- readRDS(commandArgs(TRUE)[1])",
    ".libPaths(config$libraries)",
    "if (file.exists(file.path(config$package_path, 'R', 'posterior.R'))) {",
    "  pkgload::load_all(config$package_path, quiet = TRUE)",
    "} else library(posteriordb, lib.loc = dirname(config$package_path))",
    "bundle <- readRDS(config$rds)",
    "stopifnot(inherits(bundle, 'pdb_reference_bundle'))",
    "po <- bundle$posterior",
    "stopifnot(identical(get_data(po), bundle$data))",
    "stopifnot(identical(model_code(po, 'stan'), bundle$model_code))",
    "stopifnot(identical(reference_posterior_draws(po), bundle$reference_draws))",
    "stopifnot(is.null(pdb(po)), identical(get_data(po)$y, matrix(1:6,2,3)))",
    "stopifnot(identical(model_code(po, 'stan'), po$embedded_model_code))",
    "stopifnot(identical(reference_posterior_draws(po), po$embedded_reference_draws))",
    "stopifnot(identical(reference_posterior_draws_info(po), info(po$embedded_reference_draws)))"
  ), script)
  output <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(config_path)), stdout = TRUE, stderr = TRUE)
  expect_equal(attr(output, "status") %||% 0L, 0L, info = paste(output, collapse = "\n"))
})

test_that("posterior checking uses supplied standalone and connected content", {
  object <- standalone_posterior_fixture()
  expect_identical(check_pdb_posterior(object, run_stan_code_checks = FALSE, verbose = FALSE), TRUE)
  expect_null(pdb(object))
  malformed <- object
  invalid_info <- info(malformed$embedded_reference_draws)
  invalid_info$added_by <- NULL
  info(malformed$embedded_reference_draws) <- invalid_info
  expect_error(check_pdb_posterior(malformed, run_stan_code_checks = FALSE, verbose = FALSE), "added_by|names")

  root <- tempfile("posterior-checking-")
  for (path in c("data", "models", "posteriors", "alias", "cache", "bibliography"))
    dir.create(file.path(root, path), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines(paste0('{"fixture-alias": "', object$name, '"}'), file.path(root, "alias/posteriors.json"))
  writeLines("@misc{known, title={Known}}", file.path(root, "bibliography/references.bib"))
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  pdb(object) <- connection
  object$references <- "known"
  stored <- object
  stored$embedded_data <- stored$embedded_model_code <- stored$embedded_reference_draws <- NULL
  stored["reference_posterior_name"] <- list(NULL)
  for (component in list(object$embedded_data, object$embedded_model_code, stored)) write_pdb(component, connection)
  expect_identical(check_pdb_posterior(posterior(stored$name, connection),
    run_stan_code_checks = FALSE, verbose = FALSE), TRUE)
  expect_identical(check_pdb(connection, run_stan_code_checks = FALSE, verbose = FALSE), 0L)
  expect_identical(check_pdb_posterior(object, run_stan_code_checks = FALSE, verbose = FALSE), TRUE)

  modified <- object
  modified$dimensions <- list(theta = -1L)
  expect_error(check_pdb_posterior(modified, run_stan_code_checks = FALSE, verbose = FALSE))
  modified <- object
  modified$data_name <- "wrong"
  expect_error(check_pdb_posterior(modified, run_stan_code_checks = FALSE, verbose = FALSE), "data link")
  # Supplied-object checks leave the saved record alone.
  expect_equal(posterior(stored$name, connection)$dimensions, list(theta = 1L))
})

test_that("posterior checking validates the model getter result", {
  registerS3method("model_code", "invalid_code_posterior", function(...) NULL,
    envir = asNamespace("posteriordb"))
  on.exit(rm("model_code.invalid_code_posterior", envir = get(".__S3MethodsTable__.",
    asNamespace("posteriordb"))), add = TRUE)
  object <- standalone_posterior_fixture()
  class(object) <- c("invalid_code_posterior", class(object))
  expect_error(check_pdb_posterior(object, run_stan_code_checks = FALSE, verbose = FALSE), "pdb_model_code")
})

test_that("standalone bibliography checks require a connection when citations exist", {
  object <- standalone_posterior_fixture()
  root <- tempfile("posterior-citations-")
  dir.create(file.path(root, "bibliography"), recursive = TRUE)
  dir.create(file.path(root, "cache"))
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("@misc{known, title={Known}}", file.path(root, "bibliography/references.bib"))
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  for (component in c("posterior", "model", "data")) {
    cited <- object
    if (component == "posterior") cited$references <- "known"
    if (component == "model") {
      cited$model_info$references <- "known"
      info(cited$embedded_model_code) <- cited$model_info
    }
    if (component == "data") {
      cited$data_info$references <- "known"
      info(cited$embedded_data) <- cited$data_info
    }
    expect_error(check_pdb_posterior(cited, run_stan_code_checks = FALSE, verbose = FALSE), "attach.*database|bibliography")
    pdb(cited) <- connection
    expect_identical(check_pdb_posterior(cited, run_stan_code_checks = FALSE, verbose = FALSE), TRUE)
    if (component == "posterior") cited$references <- "missing"
    if (component == "model") {
      cited$model_info$references <- "missing"
      info(cited$embedded_model_code) <- cited$model_info
    }
    if (component == "data") {
      cited$data_info$references <- "missing"
      info(cited$embedded_data) <- cited$data_info
    }
    expect_error(check_pdb_posterior(cited, run_stan_code_checks = FALSE, verbose = FALSE), "does not exist.*bibliography")
  }
})
