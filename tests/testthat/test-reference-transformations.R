#Helpers: helper-diagnostics.R

test_that("thinning clears acceptance evidence and blocks writing", {
  fixture <- create_transformed_ref_draws()
  x <- fixture$x
  expect_silent(assert_checked_reference_posterior_draws(x))

  thinned <- thin_draws.pdb_reference_posterior_draws(x, 2L)
  expect_equal(posterior::ndraws(thinned), 5000L)
  expect_equal(info(thinned)$diagnostics$ndraws, 5000L)
  expect_null(info(thinned)$checks_made)
  expect_null(attr(thinned, "diagnostic_report"))
  expect_length(info(thinned)$diagnostics$r_hat, 0L)
  expect_length(info(thinned)$diagnostics$effective_sample_size_bulk, 0L)
  expect_length(info(thinned)$diagnostics$effective_sample_size_tail, 0L)
  expect_length(info(thinned)$diagnostics$mean_lag1_ac, 0L)
  expect_true(all(is.na(
    info(thinned)$diagnostics$expected_fraction_of_missing_information
  )))
  expect_true(all(is.na(info(thinned)$diagnostics$divergent_transitions)))
  expect_equal(
    attr(thinned, "sampler_diagnostics"),
    posterior::thin_draws(fixture$sampler, 2L)
  )
  expect_null(
    attr(thinned, "sampling_metadata")$expected_fraction_of_missing_information
  )
  expect_equal(attr(thinned, "sampling_metadata")$ndraws, 5000L)
  expect_equal(attr(thinned, "sampling_metadata")$nchains, 4L)
  expect_identical(pdb(thinned), fixture$connection)
  expect_identical(info(thinned)$comments, "Preserve")
  expect_error(
    write_pdb(thinned, fixture$connection, write_summary_statistics = FALSE),
    "ndraws_is_10k"
  )
  expect_identical(list.files(fixture$root), "sentinel")
  expect_identical(readLines(file.path(fixture$root, "sentinel")), "unchanged")
})

test_that("thinning dispatches from posterior and validates the period", {
  x <- create_transformed_ref_draws()$x
  expect_equal(thin_draws.pdb_reference_posterior_draws(x, 1L), x)
  expect_equal(
    posterior::thin_draws(x, 2L),
    thin_draws.pdb_reference_posterior_draws(x, 2L)
  )
  expect_error(posterior::thin_draws(x, NULL), "thin")
  expect_error(posterior::thin_draws(x, 1.5), "thin")
})

test_that("forged flags on thinned draws can't by pass ndraws requirement", {
  x <- create_transformed_ref_draws()$x
  forged <- thin_draws.pdb_reference_posterior_draws(x, 2L)
  forged_info <- info(forged)
  forged_info$diagnostics$ndraws <- 5000L
  forged_info$checks_made <- c(
    bundle_acceptance_flags(),
    list(ndraws_is_gte_10k = TRUE)
  )
  info(forged) <- forged_info
  expect_error(assert_checked_reference_posterior_draws(forged), "ndraws_exact")
  expect_error(
    assert_checked_summary_statistics_draws(forged),
    "ndraws_summary_min"
  )
})

test_that("subsetting clears acceptance evidence and realigns diagnostics", {
  fixture <- create_transformed_ref_draws()
  x <- fixture$x
  selected <- subset(x, variable = c("beta", "alpha"))
  expect_null(info(selected)$checks_made)
  expect_null(attr(selected, "diagnostic_report"))
  expect_identical(
    info(selected)$diagnostics$diagnostic_information$names,
    c("beta", "alpha")
  )
  expect_identical(
    info(selected)$diagnostics$r_hat,
    fixture$diagnostics$r_hat[c("beta", "alpha")]
  )
  one <- subset(x, variable = "beta")
  expect_named(info(one)$diagnostics$effective_sample_size_bulk, "beta")
  expect_named(info(one)$diagnostics$effective_sample_size_tail, "beta")
  expect_equal(
    posterior::as_draws_array(one)[,, 1L],
    fixture$values[,, "beta"]
  )
  expect_silent(check_reference_posterior_draws(one))
  # Selecting every variable in the same order changes nothing.
  expect_identical(subset(x, variable = c("alpha", "beta")), x)
})

test_that("unnamed metrics follow the recorded order when subsetting", {
  # Unnamed metric vectors follow the recorded order, not the payload order.
  reordered <- create_transformed_ref_draws()$x
  reordered_info <- info(reordered)
  reordered_info$diagnostics$diagnostic_information$names <- c("beta", "alpha")
  reordered_info$diagnostics$r_hat <- c(2, 1)
  info(reordered) <- reordered_info
  selected <- subset(reordered, variable = "beta")
  expect_identical(info(selected)$diagnostics$r_hat, c(beta = 2))
  expect_error(check_reference_posterior_draws(selected), "r_hat")
})
