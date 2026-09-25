make_unchecked_test_bundle <- function(divergence = 0L) {
  iterations <- 2500L
  set.seed(20260925)
  draws_array <- array(
    stats::rnorm(iterations * 4L),
    dim = c(iterations, 4L, 1L),
    dimnames = list(NULL, NULL, "theta")
  )
  sampler_array <- array(
    0,
    dim = c(iterations, 4L, 3L),
    dimnames = list(NULL, NULL, c("divergent__", "energy__", "treedepth__"))
  )
  sampler_array[, , "energy__"] <- matrix(
    stats::rnorm(iterations * 4L), nrow = iterations, ncol = 4L
  ) + rep(seq_len(4L) * 0.25, each = iterations)
  sampler_array[, , "treedepth__"] <- 5
  if (divergence > 0L) sampler_array[1L, 1L, "divergent__"] <- divergence

  extracted <- list(
    draws = posterior::as_draws_array(draws_array),
    sampler_diagnostics = posterior::as_draws_array(sampler_array),
    metadata = list(
      ndraws = iterations * 4L,
      nchains = 4L,
      expected_fraction_of_missing_information = rep(0.8, 4L),
      max_treedepth = 10L,
      method_arguments = list()
    ),
    source = "parameters { real theta; } model { theta ~ normal(0, 1); }",
    dimensions = list(theta = integer()),
    fit_class = "stanfit",
    import_versions = list(R = "test", rstan = "test", posterior = "test")
  )
  testthat::local_mocked_bindings(
    extract_rstan_fit = function(fit, checks = "all", strict = TRUE,
                                 for_bundle = FALSE, compute_diagnostics = TRUE,
                                 include = NULL, exclude = NULL, ...) {
      expect_true(for_bundle)
      expect_false(compute_diagnostics)
      extracted
    },
    .package = "posteriordb"
  )
  create_pdb_bundle(
    structure(list(), class = "stanfit"),
    data = list(),
    data_info = list(name = "deferred-check-data", title = "Test data"),
    model_info = list(name = "deferred-check-model", title = "Test model"),
    check = FALSE
  )
}

test_that("an unchecked bundle can be checked later and becomes writable when accepted", {
  bundle <- make_unchecked_test_bundle()
  expect_null(bundle$diagnostics)
  expect_null(info(bundle$reference_draws)$checks_made)

  checked <- check_reference_posterior_draws(bundle)

  expect_s3_class(checked, "pdb_reference_bundle")
  expect_true(checked$diagnostics$checked)
  expect_true(all(unlist(checked$diagnostics$status, use.names = FALSE)))
  expect_named(checked$diagnostics$status,
    c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions"))
  expect_true(all(unlist(info(checked$reference_draws)$checks_made, use.names = FALSE)))
  expect_equal(checked$posterior$embedded_reference_draws, checked$reference_draws)
  expect_silent(assert_checked_reference_posterior_draws(checked$reference_draws))
})

test_that("a failed deferred bundle check records failures without certifying draws", {
  bundle <- make_unchecked_test_bundle(divergence = 1L)

  checked <- check_reference_posterior_draws(bundle)

  expect_true(checked$diagnostics$checked)
  expect_false(checked$diagnostics$status$divergent_transitions)
  expect_true("divergent_transitions" %in% names(checked$diagnostics$failures))
  expect_null(info(checked$reference_draws)$checks_made$no_divergent_transitions)
  expect_equal(checked$posterior$embedded_reference_draws, checked$reference_draws)

  root <- tempfile("deferred-check-write-")
  dir.create(root)
  for (folder in c("data", "models", "posteriors")) dir.create(file.path(root, folder))
  dir.create(file.path(root, "cache"))
  pdb <- pdb_local(root, cache_path = file.path(root, "cache"))
  expect_error(write_pdb(checked$reference_draws, pdb), "TRUE|assertion")
})
