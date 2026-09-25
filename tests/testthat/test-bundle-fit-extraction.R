test_that("bundle dimension names preserve scalar and singleton axes", {
  dimensions <- list(mu = integer(), theta = 1L, beta = c(2L, 3L))
  expect_identical(posteriordb:::bundle_dimension_names(dimensions), c(
    "mu", "theta[1]", "beta[1,1]", "beta[2,1]", "beta[1,2]",
    "beta[2,2]", "beta[1,3]", "beta[2,3]"
  ))
})

test_that("bundle extraction validates complete declared array coverage", {
  expect_silent(posteriordb:::validate_rstan_saved_coverage("mu", "mu", integer()))
  expect_silent(posteriordb:::validate_rstan_saved_coverage("theta", "theta[1]", 1L))
  expect_silent(posteriordb:::validate_rstan_saved_coverage("beta",
    c("beta[1,1]", "beta[2,1]", "beta[1,2]", "beta[2,2]",
      "beta[1,3]", "beta[2,3]"), c(2L, 3L)))
  expect_error(posteriordb:::validate_rstan_saved_coverage("theta",
    c("theta[1]", "theta[3]"), 3L), "partial")
  expect_error(posteriordb:::validate_rstan_saved_coverage("beta",
    c("beta[1,1]", "beta[2,1]", "beta[1,2]", "beta[2,2]"), c(2L, 3L)),
    "partial")
  expect_error(posteriordb:::validate_rstan_saved_coverage("beta",
    c("beta[1,1]", "beta[2,1]", "beta[1,2]", "beta[2,2]",
      "beta[1,3]", "beta[2,3]", "beta[2,3]"), c(2L, 3L)), "partial")
})

test_that("bundle dimensions retain declared scalar axes", {
  expect_identical(posteriordb:::bundle_dimension_names(list(theta = 1L)),
                   "theta[1]")
  expect_identical(posteriordb:::bundle_dimension_names(list(mu = integer())),
                   "mu")
})

make_bundle_extraction_fit <- function(dimensions = list(mu = integer(), theta = 1L),
                                       variables = c("mu", "theta[1]"),
                                       algorithm = "NUTS", source = "parameters { real mu; real theta[1]; } model {}") {
  n <- 8L
  vals <- array(seq_len(n * 2L * length(variables)),
    dim = c(n, 2L, length(variables)),
    dimnames = list(NULL, NULL, variables))
  sampler <- array(0, c(n, 2L, 2L),
    dimnames = list(NULL, NULL, c("divergent__", "energy__")))
  structure(list(
    stanmodel = list(model_code = source), par_dims = dimensions,
    sim = list(chains = 2L),
    stan_args = list(
      list(method = "sampling", algorithm = algorithm,
           control = list(max_treedepth = 10L), seed = 1L),
      list(method = "sampling", algorithm = algorithm,
           control = list(max_treedepth = 12L), seed = 2L)
    ),
    .draws = posterior::as_draws_array(vals),
    .sampler = posterior::as_draws_array(sampler)
  ), class = c("stanfit", "list"))
}

test_that("bundle extraction selects draws and keeps sampling provenance", {
  fit <- make_bundle_extraction_fit(dimensions = list(mu = integer(), theta = 1L),
                                    variables = c("mu", "theta[1]"))
  testthat::local_mocked_bindings(
    rstan_fit_slot = function(fit, slot_name) fit[[slot_name]],
    rstan_fit_stan_args = function(fit) fit$stan_args,
    extract_rstan_fit = function(fit, checks = "all", strict = TRUE, ...) {
      list(draws = fit$.draws, sampler_diagnostics = fit$.sampler,
        metadata = list(nchains = 2L, expected_fraction_of_missing_information = c(.3, .4),
          rstan_version = "installed", posterior_version = "installed",
          r_version = "installed", stan_version = "installed",
          sampler_arguments = fit$stan_args,
          method_arguments = list(sampler_arguments = fit$stan_args)))
    }
  )
  extracted <- posteriordb:::extract_rstan_fit_for_bundle(fit, strict = FALSE, include = "theta")
  expect_identical(posterior::variables(extracted$draws), "theta[1]")
  expect_identical(extracted$dimensions, list(theta = 1L))
  expect_identical(extracted$fit_class, "stanfit")
  expect_identical(extracted$source, fit$stanmodel$model_code)
  expect_identical(extracted$metadata$expected_fraction_of_missing_information, c(.3, .4))
  expect_length(extracted$metadata$max_treedepth, 2L)
  expect_false(any(c("rstan_version", "posterior_version", "r_version", "stan_version") %in%
                   names(extracted$metadata)))
  expect_false("sampling_timestamp" %in% names(extracted$metadata$method_arguments))
  expect_named(extracted$import_versions, c("R", "rstan", "posterior"))
})

test_that("unchecked bundle extraction retains sampler inputs without metrics", {
  fit <- make_bundle_extraction_fit()
  sampler_read <- FALSE
  testthat::local_mocked_bindings(
    rstan_fit_slot = function(fit, slot_name) fit[[slot_name]],
    rstan_fit_stan_args = function(fit) fit$stan_args,
    extract_rstan_fit = function(fit, checks = "all", strict = TRUE, ...) {
      expect_length(checks, 0L)
      list(
        draws = fit$.draws,
        sampler_diagnostics = NULL,
        metadata = list(nchains = 2L, max_treedepth = 10L,
                        sampler_arguments = fit$stan_args,
                        method_arguments = list())
      )
    },
    extract_rstan_sampler_diagnostics = function(fit, strict = TRUE) {
      sampler_read <<- TRUE
      expect_false(strict)
      fit$.sampler
    }
  )

  extracted <- posteriordb:::extract_rstan_fit_for_bundle(
    fit,
    strict = FALSE,
    compute_diagnostics = FALSE
  )

  expect_true(sampler_read)
  expect_equal(extracted$sampler_diagnostics, fit$.sampler)
  expect_null(extracted$metadata$expected_fraction_of_missing_information)
})

test_that("bundle extraction rejects unsupported provenance and incomplete variables", {
  fit <- make_bundle_extraction_fit()
  testthat::local_mocked_bindings(
    rstan_fit_slot = function(fit, slot_name) fit[[slot_name]],
    rstan_fit_stan_args = function(fit) fit$stan_args,
    extract_rstan_fit = function(fit, checks = "all", strict = TRUE, ...) {
      list(draws = fit$.draws, sampler_diagnostics = fit$.sampler, metadata = list())
    }
  )
  fixed <- fit
  fixed$stan_args[[1L]]$algorithm <- "Fixed_param"
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(fixed), "HMC sampling fits")
  missing_chain_method <- fit
  missing_chain_method$stan_args[[2L]]$algorithm <- NULL
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(missing_chain_method), "HMC sampling fits")
  misleading_method <- fit
  misleading_method$stan_args[[1L]]$method <- "not_sampling"
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(misleading_method), "HMC sampling fits")
  chain_mismatch <- fit
  chain_mismatch$stan_args <- chain_mismatch$stan_args[1L]
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(chain_mismatch), "Merged or inconsistent")
  missing <- fit
  missing$stanmodel$model_code <- ""
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(missing), "saved Stan source")
  include_file <- fit
  include_file$stanmodel$model_code <- "#include \\\"shared.stan\\\""
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(include_file), "#include")
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(fit, include = "missing"),
               "Unknown Stan variable.*include")

  partial <- make_bundle_extraction_fit(dimensions = list(theta = 3L),
    variables = c("theta[1]", "theta[3]"))
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(partial), "partial")
  fractional <- make_bundle_extraction_fit(dimensions = list(theta = 2.5),
    variables = c("theta[1]", "theta[2]"))
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(fractional), "invalid declared dimensions")
  zero <- make_bundle_extraction_fit()
  # A Stan declaration can be zero-sized while no scalar name appears in draws.
  zero$par_dims <- list(theta = 0L, mu = integer())
  zero$.draws <- posterior::as_draws_array(array(rnorm(16), c(8, 2, 1),
    dimnames = list(NULL, NULL, "mu")))
  expect_error(posteriordb:::extract_rstan_fit_for_bundle(zero), "zero-sized")
  expect_silent(posteriordb:::extract_rstan_fit_for_bundle(zero, exclude = "theta"))
})
