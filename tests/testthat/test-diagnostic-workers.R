test_that("stored and report diagnostics agree on the same retained arrays", {
  set.seed(412)
  draws <- posterior::as_draws_array(array(rnorm(800), c(100, 4, 2),
    dimnames = list(NULL, NULL, c("alpha", "beta"))))
  sampler <- posterior::as_draws_array(array(0, c(100, 4, 3),
    dimnames = list(NULL, NULL, c("energy__", "divergent__", "treedepth__"))))
  sampler[, , "energy__"] <- matrix(rnorm(400), 100, 4)
  sampler[1, 2, "divergent__"] <- 1
  sampler[, , "treedepth__"] <- 5
  metadata <- list(expected_fraction_of_missing_information = rep(.5, 4), max_treedepth = 10)
  extracted <- list(draws = draws, sampler_diagnostics = sampler, metadata = metadata)
  report <- bundle_full_diagnostic_report(extracted)
  stored <- compute_stan_sampling_diagnostics(draws, c("alpha", "beta"),
    sampler, metadata$expected_fraction_of_missing_information, metadata$max_treedepth)
  for (field in c("mean_lag1_ac", "r_hat", "effective_sample_size_bulk", "effective_sample_size_tail"))
    expect_equal(stored[[field]], report$metrics[[field]])
  expect_equal(stored$divergent_transitions, unname(report$metrics$divergent_transitions))
  expect_equal(stored$expected_fraction_of_missing_information, unname(report$metrics$efmi))
  expect_equal(stored$max_treedepth_exceeded, rep(0, 4))
  expect_equal(unname(report$metrics$max_treedepth_observed_by_chain), rep(5, 4))
})

test_that("backend-neutral stored diagnostics do not call RStan for missing metrics", {
  set.seed(412)
  draws <- posterior::as_draws_array(array(rnorm(400), c(100, 4, 1),
    dimnames = list(NULL, NULL, "theta")))
  stored <- compute_stan_sampling_diagnostics(draws, "theta")
  expect_true(all(is.na(stored$divergent_transitions)))
  expect_true(all(is.na(stored$expected_fraction_of_missing_information)))
  expect_equal(length(stored$divergent_transitions), 4L)
  expect_true(is.finite(stored$r_hat))
})

test_that("shared kernels preserve undefined lag values and backend E-FMI conventions", {
  constant <- posterior::as_draws_array(array(1, c(3, 2, 1),
    dimnames = list(NULL, NULL, "theta")))
  expect_identical(reference_lag1_ac(constant), c(theta = NA_real_))
  expect_error(mean_lag1_ac(constant), "undefined")
  short <- posterior::as_draws_array(array(1, c(1, 2, 1)))
  expect_true(all(is.na(reference_lag1_ac(short))))
  expect_error(mean_lag1_ac(short), "At least two")
  energy <- posterior::as_draws_array(array(c(1, 2, 4, 8), c(4, 1, 1),
    dimnames = list(NULL, NULL, "energy__")))
  expected <- mean(diff(c(1, 2, 4, 8))^2) / var(c(1, 2, 4, 8))
  expect_equal(sampler_diagnostics_bfmi(energy, 1), expected)
  expect_equal(rstan_sampler_bfmi(energy, 1), expected * 3 / 4)
  energy[] <- 1
  expect_true(is.na(rstan_sampler_bfmi(energy, 1)))
  expect_error(sampler_diagnostics_bfmi(energy, 1), "invalid")
})


test_that("internal sampling routes both backends through fit extraction", {
  set.seed(412)
  draws <- posterior::as_draws_array(array(rnorm(60000), c(2500, 4, 6),
    dimnames = list(NULL, NULL, c("theta[2]", "derived[1]", "theta[1]", "bad", "derived[2]", "lp__"))))
  draws[, , "derived[1]"] <- exp(draws[, , "theta[1]"])
  draws[, , "derived[2]"] <- exp(draws[, , "theta[2]"])
  for (chain in 1:4) draws[, chain, "bad"] <- draws[, chain, "bad"] + chain * 10
  sampler <- posterior::as_draws_array(array(0, c(2500, 4, 1),
    dimnames = list(NULL, NULL, "divergent__")))
  calls <- character()
  testthat::local_mocked_bindings(
    posterior = function(...) structure(list(dimensions = list(theta = 2L)), class = "pdb_posterior"),
    run_stan.pdb_posterior = function(x, stan_args, backend) {
      structure(list(), class = if (backend == "rstan") "stanfit" else "CmdStanMCMC")
    },
    extract_external_stan_fit = function(fit, ...) {
      calls <<- c(calls, class(fit))
      list(draws = draws, sampler_diagnostics = sampler,
        metadata = list(expected_fraction_of_missing_information = rep(.5, 4)))
    },
    fitted_parameter_names = function(fit) "theta"
  )
  metadata <- as.reference_posterior_info(list(
    name = "internal-reference",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = NULL, checks_made = NULL, comments = NULL,
    added_by = "Test", added_date = Sys.Date(), versions = NULL))
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  outputs <- lapply(c("rstan", "cmdstanr"), function(backend) {
    compute_reference_posterior_draws(metadata, connection, backend, include = "none")
  })
  expect_identical(calls, c("stanfit", "CmdStanMCMC"))
  expect_equal(outputs[[1]], outputs[[2]])
  required <- c("theta[2]", "theta[1]")
  expect_identical(posterior::variables(outputs[[1]]), required)
  expect_named(info(outputs[[1]])$diagnostics$r_hat, required)
  for (backend in c("rstan", "cmdstanr")) {
    expect_silent(check_reference_posterior_draws(outputs[[1]]))
    minimal <- compute_reference_posterior_draws(metadata, connection, backend,
      include = character(0))
    expect_equal(minimal, outputs[[1]])
    extra <- compute_reference_posterior_draws(metadata, connection, backend, include = "derived")
    retained <- c("theta[2]", "derived[1]", "theta[1]", "derived[2]")
    expect_identical(posterior::variables(extra), retained)
    expect_named(info(extra)$diagnostics$r_hat, retained)
    expect_equal(as.numeric(posterior::as_draws_array(extra)),
      as.numeric(posterior::subset_draws(draws, variable = retained, regex = FALSE)))
    expect_silent(check_reference_posterior_draws(extra))
    for (include in list(NULL, "all")) {
      full <- compute_reference_posterior_draws(metadata, connection, backend, include = include)
      expect_equal(compute_reference_posterior_draws(metadata, connection, backend), full)
      expect_identical(posterior::variables(full), setdiff(posterior::variables(draws), "lp__"))
      expect_named(info(full)$diagnostics$r_hat, posterior::variables(full))
      expect_error(check_reference_posterior_draws(full), "r_hat")
      expect_error(assert_checked_reference_posterior_draws(full), "checks_made")
      omitted <- compute_reference_posterior_draws(metadata, connection, backend,
        include = include, exclude = "bad")
      expect_equal(omitted, extra)
      for (exclude in list(NULL, character(), "none")) {
        expect_equal(compute_reference_posterior_draws(metadata, connection, backend,
          include = include, exclude = exclude), full)
      }
      expect_equal(compute_reference_posterior_draws(metadata, connection, backend,
        include = include, exclude = "all"), minimal)
    }
    expect_error(compute_reference_posterior_draws(metadata, connection, backend,
      include = "derived", exclude = "derived"), "both.*include.*exclude")
    expect_error(compute_reference_posterior_draws(metadata, connection, backend,
      include = "unknown"), "Unknown")
    expect_error(compute_reference_posterior_draws(metadata, connection, backend,
      exclude = "theta"), "Cannot exclude")
    expect_error(compute_reference_posterior_draws(metadata, connection, backend,
      include = "lp__"), "cannot be included")
  }
  root <- withr::local_tempdir()
  for (directory in c("data", "models", "posteriors")) dir.create(file.path(root, directory))
  jsonlite::write_json(list(reference_posterior_name = metadata$name),
    file.path(root, "posteriors", "linked.json"), auto_unbox = TRUE)
  destination <- pdb_local(root)
  checked <- check_reference_posterior_draws(extra)
  write_pdb(checked, destination, write_summary_statistics = FALSE)
  restored <- reference_posterior_draws(info(checked), pdb = destination)
  expect_identical(posterior::variables(restored), retained)
  expect_equal(as.numeric(posterior::as_draws_array(restored)),
    as.numeric(posterior::as_draws_array(checked)))
  expect_identical(info(restored)$diagnostics$diagnostic_information$names, retained)
  expect_equal(info(restored)$diagnostics$r_hat, unname(info(checked)$diagnostics$r_hat))
  expect_silent(check_reference_posterior_draws(restored))
})


test_that("missing E-FMI metadata uses the declared backend normalization", {
  draws <- posterior::as_draws_array(array(1:4, c(4, 1, 1),
    dimnames = list(NULL, NULL, "theta")))
  sampler <- posterior::as_draws_array(array(c(1, 2, 4, 8), c(4, 1, 1),
    dimnames = list(NULL, NULL, "energy__")))
  extracted <- list(draws = draws, sampler_diagnostics = sampler,
    metadata = list(rstan_version = "rstan supplied"))
  report <- reference_draw_diagnostics_from_extracted(extracted, checks = "efmi")
  expect_equal(unname(report$metrics$efmi), rstan_sampler_bfmi(sampler, 1))
  extracted$metadata <- list()
  extracted$fit_class <- "stanfit"
  report <- reference_draw_diagnostics_from_extracted(extracted, checks = "efmi")
  expect_equal(unname(report$metrics$efmi), rstan_sampler_bfmi(sampler, 1))
  extracted$fit_class <- "CmdStanMCMC"
  report <- reference_draw_diagnostics_from_extracted(extracted, checks = "efmi")
  expect_equal(unname(report$metrics$efmi), sampler_diagnostics_bfmi(sampler, 1))
})
