test_that("standalone bundle argument and metadata errors are actionable", {
  fake <- structure(list(), class = "not_a_fit")
  expect_error(create_pdb_bundle(fake), "only `rstan::stanfit`")
  expect_error(resolve_standalone_fit_data(fake, NULL), "`data` is required")
  expect_equal(resolve_standalone_fit_data(fake, list()), list(data = list(), source = "caller-supplied"))
  expect_error(resolve_standalone_fit_data(fake, list(x = 1, x = 2)), "unique")
  expect_error(validate_stan_input_data(list(x = data.frame(y = 1)), "data"), "ordinary numeric")
  expect_error(validate_stan_input_data(list(x = new.env()), "data"), "ordinary numeric")
  expect_error(validate_stan_input_data(list(x = factor("a")), "data"), "ordinary numeric")
  expect_error(validate_stan_input_data(list(x = NA_real_), "data"), "ordinary numeric")
  expect_error(validate_stan_input_data(list(x = structure(1, external = new.env())), "data"), "ordinary numeric")
  expect_invisible(validate_stan_input_data(list(x = array(1:4, c(2L, 2L)), flag = c(TRUE, FALSE)), "data"))
  recovery <- list(x = 1)
  testthat::local_mocked_bindings(recover_stanfit_data = function(fit) recovery)
  expect_equal(resolve_standalone_fit_data(fake, NULL), list(data = list(x = 1), source = "fit-recovered"))
  expect_equal(resolve_standalone_fit_data(fake, list()), list(data = list(), source = "caller-supplied"))
  recovery <- "bad"
  expect_error(resolve_standalone_fit_data(fake, NULL), "Recovered `data` must be a list")
  expect_error(resolve_standalone_fit_data(fake, "bad"), "Supplied `data` must be a list")
  expect_error(validate_bundle_metadata(list(name = "x"), "data_info",
    c("name", "title"), c("name", "title")), "title")
  expect_error(validate_bundle_metadata(list(naem = "typo"), "data_info",
    character(), c("name", "title")), "Unknown field")
  expect_error(assert_bundle_required_metadata(list(), list()),
    "data_info\\$name, data_info\\$title, model_info\\$name, model_info\\$title")
  expect_error(assert_bundle_required_metadata(list(name = NULL, title = NULL),
    list(name = "m", title = "M")), "data_info\\$name, data_info\\$title")
  expect_error(validate_variable_selection(c("mu", "mu"), "include"), "unique")
})

test_that("a sampled stanfit produces a standalone bundle", {
  skip_if_not_installed("rstan")
  code <- paste(
    "parameters { real mu; matrix[2,3] beta; }",
    "transformed parameters { real twice_mu = 2 * mu; }",
    "model { mu ~ normal(0, 1); to_vector(beta) ~ normal(0, 1); }",
    "generated quantities { real prediction = mu; real constant = 1; }"
  )
  fit <- suppressWarnings(rstan::sampling(rstan::stan_model(model_code = code),
    data = list(), iter = 20, warmup = 10, chains = 2, seed = 781, refresh = 0))
  bundle <- create_pdb_bundle(fit, data = list(),
    data_info = list(name = "unit-data", title = "Unit inputs"),
    model_info = list(name = "unit-model", title = "Unit model"), check = FALSE)
  expect_s3_class(bundle, "pdb_reference_bundle")
  expect_identical(bundle$posterior$dimensions$beta, c(2L, 3L))
  expect_true(all(c("mu", "twice_mu", "prediction", "constant", "beta[2,3]") %in%
                  posterior::variables(bundle$reference_draws)))
  expect_true(is.null(pdb(bundle$data)))
  expect_true(is.null(pdb(bundle$model_code)))
  expect_true(nzchar(info(bundle$data)$added_by))
  expect_s3_class(info(bundle$data)$added_date, "Date")
  expect_equal(info(bundle$model_code)$added_by, info(bundle$data)$added_by)
  expect_equal(bundle$posterior$added_by, info(bundle$data)$added_by)
  expect_equal(info(bundle$reference_draws)$added_by, info(bundle$data)$added_by)
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
  expect_false(bundle$diagnostics$checked)
  expect_null(bundle$diagnostics$status)
  expect_length(bundle$diagnostics$metrics$effective_sample_size_bulk, posterior::nvariables(bundle$reference_draws))
  expect_true(is.finite(bundle$diagnostics$metrics$effective_sample_size_bulk[["mu"]]))
  expect_match(paste(capture.output(print(bundle)), collapse = "\n"), "unchecked")
  testthat::local_mocked_bindings(
    sampling = function(...) stop("unexpected sampling", call. = FALSE),
    stan_model = function(...) stop("unexpected compilation", call. = FALSE),
    .package = "rstan")
  no_sampling <- create_pdb_bundle(fit, data = list(),
    data_info = list(name = "no-sampling", title = "Inputs"),
    model_info = list(name = "no-sampling", title = "Model"), check = FALSE)
  expect_s3_class(no_sampling, "pdb_reference_bundle")
  overrides <- create_pdb_bundle(fit, data = list(),
    data_info = list(name = "overrides", title = "Inputs", added_by = "data curator"),
    model_info = list(name = "overrides", title = "Model", added_by = "model curator"),
    posterior_info = list(name = "overrides-overrides", added_by = "posterior curator",
      added_date = as.Date("2025-02-03")),
    reference_info = list(added_by = "draw curator", comments = "reviewed"), check = FALSE)
  expect_equal(info(overrides$data)$added_by, "data curator")
  expect_equal(info(overrides$model_code)$added_by, "model curator")
  expect_equal(overrides$posterior$added_by, "posterior curator")
  expect_equal(info(overrides$reference_draws)$added_by, "draw curator")
  expect_equal(info(overrides$reference_draws)$comments, "reviewed")
  expect_equal(overrides$posterior$added_date, as.Date("2025-02-03"))
  expect_error(create_pdb_bundle(fit, data = list(),
    data_info = list(name = "conflict", title = "Inputs"),
    model_info = list(name = "conflict", title = "Model"),
    posterior_info = list(dimensions = list(mu = 1L)), check = FALSE), "conflicts")
  failed_bundle <- create_pdb_bundle(fit, data = list(),
    data_info = list(name = "unit-data-failed", title = "Unit inputs"),
    model_info = list(name = "unit-model-failed", title = "Unit model"), check = TRUE)
  failed_print <- paste(capture.output(print(failed_bundle)), collapse = "\n")
  expect_match(failed_print, "Draws: 20 across 2 chains")
  expect_match(failed_print, "failed")
  expect_true(is.list(failed_bundle$diagnostics$metrics))
  expect_true(failed_bundle$diagnostics$checked)
  expect_true("constant" %in% names(failed_bundle$diagnostics$metrics$mean_lag1_ac))
  expect_true(is.na(failed_bundle$diagnostics$metrics$mean_lag1_ac[["constant"]]))
  root <- tempfile("bundle-write-"); dir.create(root)
  for (folder in c("data", "models", "posteriors")) dir.create(file.path(root, folder))
  dir.create(file.path(root, "cache"))
  pdb <- pdb_local(root, cache_path = file.path(root, "cache"))
  attached <- create_pdb_bundle(fit, data = list(),
    data_info = list(name = "attached-data", title = "Attached inputs"),
    model_info = list(name = "attached-model", title = "Attached model"),
    check = FALSE, pdb = pdb)
  expect_identical(pdb(attached$data), pdb)
  expect_identical(pdb(attached$model_code), pdb)
  expect_identical(pdb(attached$posterior), pdb)
  expect_identical(pdb(attached$reference_draws), pdb)
  expect_error(data_file_path(attached$posterior), "not persisted")
  expect_error(model_code_file_path(attached$posterior, framework = "stan"), "not persisted")
  expect_error(reference_posterior_draws_file_path(attached$posterior), "not persisted")
  write_pdb(bundle$posterior, pdb)
  posterior_json <- list.files(file.path(root, "posteriors"), pattern = "json$", full.names = TRUE)
  expect_length(posterior_json, 1L)
  serialized <- paste(readLines(posterior_json), collapse = "")
  expect_false(grepl("embedded_(data|model_code|reference_draws)", serialized))
  expect_error(create_pdb_bundle(fit, data = list(),
    data_info = list(name = "d", title = "D"),
    model_info = list(name = "m", title = "M"), typo = TRUE), "Unknown argument")
  expect_error(create_pdb_bundle(fit, data = list(),
    data_info = list(name = "d", title = "D"), model_info = list(name = "m", title = "M"),
    di = list(name = "d", title = "D")), "Unknown argument.*di")
  expect_error(do.call(create_pdb_bundle, c(list(fit = fit, data = list()),
    list(data_info = list(name = "d", title = "D"), data_info = list(name = "d", title = "D")))),
    "Duplicate argument")
  expect_error(do.call(create_pdb_bundle, list(fit = fit, data = list(),
    list(name = "d", title = "D"))), "must be named exactly")
})
