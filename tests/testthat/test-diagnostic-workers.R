test_that("missing sampler diagnostics are stored as NA", {
  set.seed(123)
  draws <- posterior::as_draws_array(array(
    rnorm(400),
    c(100, 4, 1),
    dimnames = list(NULL, NULL, "theta")
  ))
  stored <- compute_stan_sampling_diagnostics(draws, "theta")
  expect_true(all(is.na(stored$divergent_transitions)))
  expect_true(all(is.na(stored$expected_fraction_of_missing_information)))
  expect_equal(length(stored$divergent_transitions), 4L)
  expect_equal(length(stored$expected_fraction_of_missing_information), 4L)
  expect_true(is.finite(stored$r_hat))
})

test_that("Stan diagnostics use only retained posterior variables", {
  set.seed(123)
  values <- array(
    stats::rnorm(100L * 4L * 2L),
    dim = c(100L, 4L, 2L),
    dimnames = list(NULL, NULL, c("discard", "keep"))
  )
  sampler <- array(
    0,
    dim = c(100L, 4L, 2L),
    dimnames = list(NULL, NULL, c("divergent__", "treedepth__"))
  )
  sampler[1L, 1L, "divergent__"] <- 1
  sampler[1L, 1L, "treedepth__"] <- 10

  diagnostics <- posteriordb:::compute_stan_sampling_diagnostics(
    posterior::as_draws_array(values),
    keep_dimensions = "keep",
    sampler_diagnostics = posterior::as_draws_array(sampler),
    expected_fraction_of_missing_information = rep(0.5, 4L),
    max_treedepth = 10L
  )

  expect_equal(diagnostics$diagnostic_information$names, "keep")
  for (field in c(
    "r_hat",
    "effective_sample_size_bulk",
    "effective_sample_size_tail",
    "mean_lag1_ac"
  )) {
    expect_named(diagnostics[[field]], "keep")
  }
  expect_equal(diagnostics$r_hat[["keep"]], posterior::rhat(values[,, "keep"]))
  expect_equal(diagnostics$divergent_transitions, c(1, 0, 0, 0))
  expect_equal(diagnostics$max_treedepth_exceeded, c(1, 0, 0, 0))
})

test_that("internal sampling keeps declared and fitted parameters and stores sampler details", {
  set.seed(123)
  draws <- posterior::as_draws_array(array(
    rnorm(1600),
    c(100, 4, 4),
    dimnames = list(NULL, NULL, c("declared", "fitted", "optional", "lp__"))
  ))
  sampler <- posterior::as_draws_array(array(
    0,
    c(100, 4, 2),
    dimnames = list(NULL, NULL, c("divergent__", "treedepth__"))
  ))
  sampler[1:2, 3, "treedepth__"] <- 10
  testthat::local_mocked_bindings(
    posterior = function(...) {
      structure(list(dimensions = list(declared = 1L)), class = "pdb_posterior")
    },
    run_stan.pdb_posterior = function(x, stan_args, backend) {
      structure(list(), class = "CmdStanMCMC")
    },
    extract_external_stan_fit = function(fit, ...) {
      list(
        draws = draws,
        sampler_diagnostics = sampler,
        metadata = list(
          expected_fraction_of_missing_information = rep(.5, 4),
          max_treedepth = 10
        )
      )
    },
    fitted_parameter_names = function(fit) "fitted"
  )
  metadata <- as.reference_posterior_info(list(
    name = "internal-reference",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = NULL,
    checks_made = NULL,
    comments = NULL,
    added_by = "Test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  output <- compute_reference_posterior_draws(
    metadata,
    connection,
    "cmdstanr",
    include = "none"
  )
  expect_identical(posterior::variables(output), c("declared", "fitted"))
  diagnostics <- info(output)$diagnostics
  expect_equal(diagnostics$max_treedepth_exceeded, c(0, 0, 2, 0))
  expect_named(
    diagnostics$sampler_parameter_summaries,
    c("divergent__", "treedepth__")
  )
})
