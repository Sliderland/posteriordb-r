test_that("bundle acceptance agrees with writers and retains single-chain metrics", {
  set.seed(412)
  values <- posterior::as_draws_array(array(rnorm(10000), c(2500, 4, 1),
    dimnames = list(NULL, NULL, "theta")))
  sampler <- posterior::as_draws_array(array(0, c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("divergent__", "treedepth__"))))
  extracted <- list(draws = values, sampler_diagnostics = sampler,
    metadata = list(expected_fraction_of_missing_information = rep(.5, 4), max_treedepth = 10),
    dimensions = list(theta = integer()), source = "parameters { real theta; } model { theta ~ normal(0,1); }",
    fit_class = "stanfit", import_versions = list())
  testthat::local_mocked_bindings(extract_rstan_fit = function(...) extracted)
  make <- function(check = TRUE, ...) create_pdb_reference_draws(
    structure(list(), class = "stanfit"), data = list(),
    data_info = list(name = "acceptance-data", title = "Inputs"),
    model_info = list(name = "acceptance-model", title = "Model"), check = check, ...)
  make_pdb <- function() {
    root <- tempfile("bundle-acceptance-db-")
    for (folder in c("data/data", "data/info", "models/stan", "models/info",
                     "posteriors", "reference_posteriors/draws/info",
                     "reference_posteriors/draws/draws", "cache"))
      dir.create(file.path(root, folder), recursive = TRUE, showWarnings = FALSE)
    pdb_local(root, cache_path = file.path(root, "cache"))
  }
  pdb <- make_pdb()
  accepted <- make()
  expect_true(all(unlist(accepted$diagnostics$status)))
  expect_silent(assert_checked_reference_posterior_draws(accepted$reference_draws))
  expect_silent(check_reference_posterior_draws(accepted$reference_draws))
  expect_length(accepted$diagnostics$metrics$effective_sample_size_bulk, 1)
  expect_true(is.finite(accepted$diagnostics$metrics$effective_sample_size_bulk))
  # An attached local database is only a connection for later use. Even when
  # all inferred object names collide with existing files, construction must
  # leave their contents and the database tree untouched.
  sentinel_paths <- c(
    file.path(pdb$pdb_local_endpoint, "data/data/acceptance-data.json.zip"),
    file.path(pdb$pdb_local_endpoint, "models/info/acceptance-model.json"),
    file.path(pdb$pdb_local_endpoint, "models/stan/acceptance-model.stan"),
    file.path(pdb$pdb_local_endpoint, "posteriors/acceptance-data-acceptance-model.json")
  )
  sentinel_bytes <- list(charToRaw("existing data"), charToRaw("existing model info"),
                         charToRaw("existing model"), charToRaw("existing posterior"))
  Map(writeBin, sentinel_bytes, sentinel_paths)
  attached <- create_pdb_reference_draws(
    structure(list(), class = "stanfit"), data = list(),
    data_info = list(name = "acceptance-data", title = "Inputs"),
    model_info = list(name = "acceptance-model", title = "Model"),
    pdb = pdb)
  expect_identical(pdb(attached$data), pdb)
  expect_identical(pdb(attached$model_code), pdb)
  expect_identical(pdb(attached$posterior), pdb)
  expect_identical(pdb(attached$reference_draws), pdb)
  expect_setequal(list.files(pdb$pdb_local_endpoint, recursive = TRUE, all.files = TRUE),
                  c("data/data/acceptance-data.json.zip",
                    "models/info/acceptance-model.json",
                    "models/stan/acceptance-model.stan",
                    "posteriors/acceptance-data-acceptance-model.json"))
  expect_length(list.files(file.path(pdb$pdb_local_endpoint, "reference_posteriors"),
                           recursive = TRUE, all.files = TRUE), 0L)
  expect_identical(unname(Map(readBin, sentinel_paths, MoreArgs = list(what = "raw", n = 100L))), sentinel_bytes)
  expect_error(write_pdb(attached$model_code, pdb, overwrite = FALSE), "already exists")
  expect_identical(unname(Map(readBin, sentinel_paths, MoreArgs = list(what = "raw", n = 100L))), sentinel_bytes)
  unchecked <- make(FALSE)
  expect_null(info(unchecked$reference_draws)$checks_made)
  before_unchecked_write <- list.files(pdb$pdb_local_endpoint, recursive = TRUE, all.files = TRUE)
  expect_error(write_pdb(unchecked$reference_draws, pdb = pdb), "checks_made")
  expect_setequal(list.files(pdb$pdb_local_endpoint, recursive = TRUE, all.files = TRUE), before_unchecked_write)

  extracted$draws <- posterior::subset_draws(values, chain = 1)
  extracted$sampler_diagnostics <- posterior::subset_draws(sampler, chain = 1)
  extracted$metadata$expected_fraction_of_missing_information <- .5
  failed <- make()
  expect_false(failed$diagnostics$status$nchains)
  expect_false(failed$diagnostics$status$ndraws)
  expect_true(failed$diagnostics$status$efmi)
  expect_length(failed$diagnostics$metrics$max_treedepth_observed_by_chain, 1)
  before_failed_write <- list.files(pdb$pdb_local_endpoint, recursive = TRUE, all.files = TRUE)
  expect_error(write_pdb(failed$reference_draws, pdb = pdb), "checks_made")
  expect_setequal(list.files(pdb$pdb_local_endpoint, recursive = TRUE, all.files = TRUE), before_failed_write)

  expect_error(make(reference_info = list(checks_made = list(ndraws_is_10k = TRUE))), "Unknown field")
  expect_error(make(posterior_info = list(model_name = "wrong")), "conflicts")
})

test_that("ordinary Stan input values preserve empty dimensions without live attributes", {
  data <- list(n = 0L, empty = array(numeric(), dim = c(0L, 2L)))
  expect_identical(validate_stan_input_data(data, "data"), data)
  expect_error(validate_stan_input_data(structure(data, live = new.env()), "data"),
               "ordinary numeric")
})
