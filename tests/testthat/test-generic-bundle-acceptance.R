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
  accepted <- make()
  expect_true(all(unlist(accepted$diagnostics$status)))
  expect_silent(assert_checked_reference_posterior_draws(accepted$reference_draws))
  expect_silent(check_reference_posterior_draws(accepted$reference_draws))
  expect_length(accepted$diagnostics$metrics$effective_sample_size_bulk, 1)
  expect_true(is.finite(accepted$diagnostics$metrics$effective_sample_size_bulk))
  unchecked <- make(FALSE)
  expect_null(info(unchecked$reference_draws)$checks_made)
  expect_error(write_pdb(unchecked$reference_draws, pdb = NULL))

  extracted$draws <- posterior::subset_draws(values, chain = 1)
  extracted$sampler_diagnostics <- posterior::subset_draws(sampler, chain = 1)
  extracted$metadata$expected_fraction_of_missing_information <- .5
  failed <- make()
  expect_false(failed$diagnostics$status$nchains)
  expect_false(failed$diagnostics$status$ndraws)
  expect_true(failed$diagnostics$status$efmi)
  expect_length(failed$diagnostics$metrics$max_treedepth_observed_by_chain, 1)
  expect_error(write_pdb(failed$reference_draws, pdb = NULL))

  expect_error(make(reference_info = list(checks_made = list(ndraws_is_10k = TRUE))), "Unknown field")
  expect_error(make(posterior_info = list(model_name = "wrong")), "conflicts")
})

test_that("ordinary Stan input values preserve empty dimensions without live attributes", {
  data <- list(n = 0L, empty = array(numeric(), dim = c(0L, 2L)))
  expect_identical(validate_stan_input_data(data, "data"), data)
  expect_error(validate_stan_input_data(structure(data, live = new.env()), "data"),
               "ordinary numeric")
})
