es_code <- function(p) as.character(stan_code("eight_schools_noncentered", pdb = p))

test_that("a fit becomes checked reference draws for an existing posterior", {
  p <- local_pdb()
  rpd <- as_reference_posterior_draws(mock_cmdstan_fit(), "8schools", pdb = p, comments = "mock")
  expect_s3_class(rpd, "pdb_reference_posterior_draws")
  rpi <- info(rpd)
  expect_identical(rpi$name, "eight_schools-eight_schools_noncentered")
  expect_identical(rpi$comments, "mock")
  expect_identical(rpi$inference$method_arguments$iter, 3500)
  expect_identical(rpi$inference$method_arguments$control$adapt_delta, 0.8)
  expect_true(rpi$checks_made$no_divergent_transitions)
  expect_false("lp__" %in% posterior::variables(rpd))
  expect_match(rpi$versions$cmdstanr_version, "cmdstanr")
})

test_that("failed fits are returned for inspection but not written", {
  p <- local_pdb()
  fit <- mock_cmdstan_fit(iid_draws(chains = 2, iterations = 5000))
  rpd <- import_reference_posterior_draws(fit, "8schools", pdb = p)
  expect_identical(attr(rpd, "check_failures")$nchains, 2L)
  expect_error(import_reference_posterior_draws(fit, "8schools", pdb = p, write = TRUE),
               "Nothing was written")
})

test_that("variable selection keeps required variables", {
  p <- local_pdb()
  draws <- posterior::bind_draws(iid_draws(), posterior::as_draws_array(array(
    stats::rnorm(10000), c(2500, 4, 1), dimnames = list(NULL, NULL, "y_rep[1]"))), along = "variable")
  fit <- mock_cmdstan_fit(draws)
  expect_true("y_rep[1]" %in% posterior::variables(as_reference_posterior_draws(fit, "8schools", pdb = p)))
  kept <- as_reference_posterior_draws(fit, "8schools", pdb = p, exclude = "y_rep")
  expect_false("y_rep[1]" %in% posterior::variables(kept))
  expect_identical(posterior::variables(as_reference_posterior_draws(fit, "8schools", pdb = p,
                                                                     include = character())),
                   posterior::variables(kept))
  expect_error(as_reference_posterior_draws(fit, "8schools", pdb = p, exclude = "mu"), "cannot be excluded")
  missing_tau <- mock_cmdstan_fit(posterior::subset_draws(iid_draws(), variable = c("theta", "mu")))
  expect_error(as_reference_posterior_draws(missing_tau, "8schools", pdb = p), "no saved draws for: tau")
  expect_error(as_reference_posterior_draws(fit, "8schools", pdb = p, dimensions = list(mu = 1)),
               "disagrees")
})

test_that("import writes passing draws and links them", {
  p <- local_pdb()
  po <- as.posterior(list(model_name = "eight_schools_centered", data_name = "eight_schools",
                          name = "imported", dimensions = list(theta = 8, mu = 1, tau = 1)), pdb = p)
  write_pdb(po, p)
  import_reference_posterior_draws(mock_cmdstan_fit(), "imported", pdb = p, write = TRUE)
  expect_identical(posterior("imported", p)$reference_posterior_name, "imported")
  expect_identical(posterior::ndraws(reference_posterior_draws("imported", pdb = p)), 10000L)
  expect_true("imported" %in% reference_posterior_names(p, "mean_squared_value"))
})

test_that("unconstrained counts from the fit must match the dimensions", {
  p <- local_pdb()
  parts <- posteriordb:::extract_fit(mock_cmdstan_fit())
  parts$upar_counts <- list(theta = 7L, mu = 1L, tau = 1L)
  local_mocked_bindings(extract_fit = function(fit) parts)
  expect_error(as_reference_posterior_draws(NULL, "8schools", pdb = p), "differ.*theta")
})

test_that("a fit is bundled as a new posterior and written", {
  p <- local_pdb()
  fit <- mock_cmdstan_fit()
  bundle <- create_pdb_bundle(
    fit, data = list(J = 8L, y = 1:8, sigma = rep(1, 8)), model_code = es_code(p),
    data_info = list(name = "new_schools", title = "New schools"),
    model_info = list(name = "new_model", title = "New model", keywords = "test"),
    posterior_info = list(dimensions = list(theta = 8, mu = 1, tau = 1)),
    reference_info = list(comments = "bundled"), added_by = "Tester")
  expect_s3_class(bundle, "pdb_reference_bundle")
  expect_identical(bundle$posterior$name, "new_schools-new_model")
  expect_identical(info(bundle$reference_draws)$name, "new_schools-new_model")
  expect_identical(info(bundle$data)$added_by, "Tester")
  expect_named(bundle$summary_statistics, c("mean_value", "mean_squared_value"))
  expect_output(print(bundle), "checks: +passed")
  # The bundle's posterior works without a database.
  expect_identical(get_data(bundle$posterior)$J, 8L)
  expect_identical(reference_posterior_draws(bundle$posterior), bundle$reference_draws)
  expect_identical(reference_posterior_info(bundle$posterior)$comments, "bundled")

  result <- write_pdb(bundle, p)
  expect_true(result$reference_draws_written)
  po <- posterior("new_schools-new_model", p)
  expect_identical(po$reference_posterior_name, po$name)
  expect_identical(model_info(po)$keywords, "test")
  expect_identical(check_pdb(p, verbose = FALSE), 0L)
  # Writing the same bundle again changes nothing.
  expect_length(write_pdb(bundle, p)$written, 0)
})

test_that("bundles can reuse stored data and models", {
  p <- local_pdb()
  bundle <- create_pdb_bundle(mock_cmdstan_fit(), data = "eight_schools", pdb = p,
                              model_code = "eight_schools_noncentered",
                              posterior_info = list(name = "reused",
                                                    dimensions = list(theta = 8, mu = 1, tau = 1)))
  expect_identical(info(bundle$data), data_info("eight_schools", pdb = p))
  written <- write_pdb(bundle, p)$written
  expect_false(any(grepl("^data/|^models/", written)))
  expect_true("reused" %in% reference_posterior_names(p))
})

test_that("unchecked and failing bundles", {
  p <- local_pdb()
  args <- list(data = list(J = 1L), model_code = es_code(p),
               data_info = list(name = "d", title = "D"), model_info = list(name = "m", title = "M"),
               posterior_info = list(dimensions = list(theta = 8, mu = 1, tau = 1)))
  unchecked <- do.call(create_pdb_bundle, c(list(mock_cmdstan_fit(), check = FALSE), args))
  expect_null(info(unchecked$reference_draws)$checks_made)
  expect_output(print(unchecked), "not checked")
  expect_true(check_reference_posterior_draws(unchecked)$summary_statistics$mean_value$names[1] == "theta[1]")

  failing <- do.call(create_pdb_bundle, c(list(mock_cmdstan_fit(iid_draws(chains = 2, iterations = 5000))), args))
  expect_null(failing$summary_statistics)
  expect_output(print(failing), "failed: nchains")
  expect_message(result <- write_pdb(failing, p), "were not written")
  expect_false(result$reference_draws_written)
  expect_null(posterior("d-m", p)$reference_posterior_name)
  expect_false("d-m" %in% reference_posterior_names(p))

  expect_error(do.call(create_pdb_bundle, c(list(mock_cmdstan_fit(code = "model {}")), args)),
               "differs from the Stan code")
  expect_error(create_pdb_bundle(mock_cmdstan_fit(), data = list(J = 1L), data_info = list(name = "d", title = "D"),
                                 model_info = list(name = "m", title = "M")), "supply `model_code`")
})

test_that("unsupported fits are rejected", {
  expect_error(as_reference_posterior_draws(list(), "8schools", pdb = local_pdb()), "Unsupported fit")
})
