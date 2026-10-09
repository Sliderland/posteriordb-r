test_that("transformations cannot reuse obsolete acceptance evidence", {
  set.seed(412)
  values <- posterior::as_draws_array(array(rnorm(20000), c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("alpha", "beta"))))
  sampler <- posterior::as_draws_array(array(0, c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("divergent__", "energy__"))))
  sampler[, , "energy__"] <- matrix(rnorm(10000), 2500, 4)
  diagnostics <- compute_stan_sampling_diagnostics(values, c("alpha", "beta"),
    sampler_diagnostics = sampler,
    expected_fraction_of_missing_information = rep(.5, 4))
  ri <- as.reference_posterior_info(list(
    name = "transform-reference",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = diagnostics, checks_made = bundle_acceptance_flags(),
    comments = "Preserve", added_by = "Test", added_date = Sys.Date(), versions = NULL
  ))
  root <- tempfile("transform-db-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("unchanged", file.path(root, "sentinel"))
  connection <- structure(list(pdb_local_endpoint = root), class = c("pdb_local", "pdb"))
  x <- as.reference_posterior_draws(posterior::as_draws_list(values), ri, pdb = connection)
  attr(x, "sampler_diagnostics") <- sampler
  attr(x, "sampling_metadata") <- list(expected_fraction_of_missing_information = rep(.5, 4))
  attr(x, "diagnostic_report") <- list(obsolete = TRUE)
  expect_silent(assert_checked_reference_posterior_draws(x))

  thinned <- thin_draws.pdb_reference_posterior_draws(x, 2L)
  expect_equal(posterior::ndraws(thinned), 5000L)
  expect_equal(info(thinned)$diagnostics$ndraws, 5000L)
  expect_null(info(thinned)$checks_made)
  expect_null(attr(thinned, "diagnostic_report"))
  expect_length(info(thinned)$diagnostics$r_hat, 0L)
  expect_equal(attr(thinned, "sampler_diagnostics"), posterior::thin_draws(sampler, 2L))
  expect_null(attr(thinned, "sampling_metadata")$expected_fraction_of_missing_information)
  expect_identical(pdb(thinned), connection)
  expect_identical(info(thinned)$comments, "Preserve")
  expect_error(write_pdb(thinned, connection, write_summary_statistics = FALSE), "ndraws_is_10k")
  expect_identical(list.files(root), "sentinel")
  expect_identical(readLines(file.path(root, "sentinel")), "unchanged")
  expect_equal(thin_draws.pdb_reference_posterior_draws(x, 1L), x)

  # The write boundary must also reject forged flags with accurate smaller counts.
  forged <- thinned
  forged_info <- info(forged)
  forged_info$diagnostics$ndraws <- 5000L
  forged_info$checks_made <- c(bundle_acceptance_flags(), list(ndraws_is_gte_10k = TRUE))
  info(forged) <- forged_info
  expect_error(assert_checked_reference_posterior_draws(forged), "ndraws_exact")
  expect_error(assert_checked_summary_statistics_draws(forged), "ndraws_summary_min")

  selected <- subset(x, variable = c("beta", "alpha"))
  expect_null(info(selected)$checks_made)
  expect_null(attr(selected, "diagnostic_report"))
  expect_identical(info(selected)$diagnostics$diagnostic_information$names, c("beta", "alpha"))
  expect_identical(info(selected)$diagnostics$r_hat, diagnostics$r_hat[c("beta", "alpha")])
  one <- subset(x, variable = "beta")
  expect_named(info(one)$diagnostics$effective_sample_size_bulk, "beta")
  expect_equal(posterior::as_draws_array(one)[, , 1L], values[, , "beta"])
  expect_silent(check_reference_posterior_draws(one))
  expect_equal(posterior::thin_draws(x, 2L), thinned)
  expect_error(posterior::thin_draws(x, NULL), "thin")
  expect_error(posterior::thin_draws(x, 1.5), "thin")

  # Unnamed metric vectors follow the recorded order, not the payload order.
  reordered <- x
  reordered_info <- info(reordered)
  reordered_info$diagnostics$diagnostic_information$names <- c("beta", "alpha")
  reordered_info$diagnostics$r_hat <- c(2, 1)
  info(reordered) <- reordered_info
  selected <- subset(reordered, variable = "beta")
  expect_identical(info(selected)$diagnostics$r_hat, c(beta = 2))
  expect_error(check_reference_posterior_draws(selected), "r_hat")
})
