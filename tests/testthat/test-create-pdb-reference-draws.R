test_that("standalone bundle argument and metadata errors are actionable", {
  fake <- structure(list(), class = "not_a_fit")
  expect_error(create_pdb_reference_draws(fake), "only `rstan::stanfit`")
  expect_error(resolve_standalone_fit_data(fake, NULL), "`data` is required")
  expect_equal(resolve_standalone_fit_data(fake, list()), list(data = list(), source = "caller-supplied"))
  expect_error(resolve_standalone_fit_data(fake, list(x = 1, x = 2)), "unique")
  recovery <- list(x = 1)
  testthat::local_mocked_bindings(recover_stanfit_data = function(fit) recovery)
  expect_equal(resolve_standalone_fit_data(fake, NULL), list(data = list(x = 1), source = "fit-recovered"))
  expect_equal(resolve_standalone_fit_data(fake, list()), list(data = list(), source = "caller-supplied"))
  recovery <- "bad"
  expect_error(resolve_standalone_fit_data(fake, NULL), "Recovered `data` must be a list")
  expect_error(validate_bundle_metadata(list(name = "x"), "data_info",
    c("name", "title"), c("name", "title")), "title")
  expect_error(validate_bundle_metadata(list(naem = "typo"), "data_info",
    character(), c("name", "title")), "Unknown field")
  expect_error(assert_bundle_required_metadata(list(), list()),
    "data_info\\$name, data_info\\$title, model_info\\$name, model_info\\$title")
  expect_error(validate_variable_selection(c("mu", "mu"), "include"), "unique")
})

test_that("saved scalar array coverage is converted to dimensions", {
  expect_equal(infer_saved_dimensions(c("theta[1]", "theta[2]", "mu")),
               list(theta = 2L, mu = integer()))
  expect_equal(infer_saved_dimensions(c("A[1,1]", "A[2,1]", "A[1,2]", "A[2,2]"))$A,
               c(2L, 2L))
  expect_error(infer_saved_dimensions(c("A[1]", "A[3]")), "partial")
})

test_that("a sampled stanfit produces a standalone bundle", {
  skip_if_not_installed("rstan")
  code <- "parameters { real mu; } model { mu ~ normal(0, 1); }"
  fit <- suppressWarnings(rstan::sampling(rstan::stan_model(model_code = code),
    data = list(), iter = 20, warmup = 10, chains = 2, seed = 781, refresh = 0))
  bundle <- create_pdb_reference_draws(fit, data = list(),
    data_info = list(name = "unit-data", title = "Unit inputs"),
    model_info = list(name = "unit-model", title = "Unit model"), check = FALSE)
  expect_s3_class(bundle, "pdb_reference_bundle")
  expect_true(is.null(pdb(bundle$data)))
  expect_true(is.null(pdb(bundle$model_code)))
  expect_equal(bundle$posterior$embedded_data, bundle$data)
  expect_equal(bundle$posterior$embedded_model_code, bundle$model_code)
  expect_equal(bundle$posterior$embedded_reference_draws, bundle$reference_draws)
  expect_equal(get_data(bundle$posterior), bundle$data)
  expect_equal(model_code(bundle$posterior, framework = "stan"), bundle$model_code)
  expect_equal(reference_posterior_draws(bundle$posterior), bundle$reference_draws)
  bundle_rds <- tempfile(fileext = ".rds")
  saveRDS(bundle, bundle_rds)
  restored <- readRDS(bundle_rds)
  expect_s3_class(restored, "pdb_reference_bundle")
  expect_equal(get_data(restored$posterior), restored$data)
  expect_equal(model_code(restored$posterior, framework = "stan"), restored$model_code)
  expect_equal(reference_posterior_draws(restored$posterior), restored$reference_draws)
  expect_error(data_file_path(bundle$posterior), "not persisted")
  expect_error(model_code_file_path(bundle$posterior, framework = "stan"), "not persisted")
  expect_error(reference_posterior_draws_file_path(bundle$posterior), "not persisted")
  expect_null(info(bundle$reference_draws)$checks_made)
  expect_match(paste(capture.output(print(bundle)), collapse = "\n"), "unchecked")
  failed_bundle <- create_pdb_reference_draws(fit, data = list(),
    data_info = list(name = "unit-data-failed", title = "Unit inputs"),
    model_info = list(name = "unit-model-failed", title = "Unit model"), check = TRUE)
  failed_print <- paste(capture.output(print(failed_bundle)), collapse = "\n")
  expect_match(failed_print, "Draws: 20 across 2 chains")
  expect_match(failed_print, "failed")
  expect_true(is.list(failed_bundle$diagnostics$metrics))
  root <- tempfile("bundle-write-"); dir.create(root)
  for (folder in c("data", "models", "posteriors")) dir.create(file.path(root, folder))
  dir.create(file.path(root, "cache"))
  pdb <- pdb_local(root, cache_path = file.path(root, "cache"))
  attached <- create_pdb_reference_draws(fit, data = list(),
    data_info = list(name = "attached-data", title = "Attached inputs"),
    model_info = list(name = "attached-model", title = "Attached model"),
    check = FALSE, pdb = pdb)
  expect_identical(pdb(attached$data), pdb)
  expect_identical(pdb(attached$model_code), pdb)
  expect_identical(pdb(attached$posterior), pdb)
  expect_identical(pdb(attached$reference_draws), pdb)
  write_pdb(bundle$posterior, pdb)
  posterior_json <- list.files(file.path(root, "posteriors"), pattern = "json$", full.names = TRUE)
  expect_length(posterior_json, 1L)
  serialized <- paste(readLines(posterior_json), collapse = "")
  expect_false(grepl("embedded_(data|model_code|reference_draws)", serialized))
  expect_error(create_pdb_reference_draws(fit, data = list(),
    data_info = list(name = "d", title = "D"),
    model_info = list(name = "m", title = "M"), typo = TRUE), "Unused or unknown")
})
