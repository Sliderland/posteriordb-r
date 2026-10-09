analytical_acceptance_draws <- function(n = 10000L) {
  set.seed(412)
  draws <- posterior::as_draws_list(list(list(theta = rnorm(n))))
  metadata <- as.reference_posterior_info(list(
    name = "analytical-reference",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = n), checks_made = NULL,
    comments = NULL, added_by = "Test", added_date = Sys.Date(), versions = NULL
  ))
  as.reference_posterior_draws(draws, metadata)
}

test_that("analytical draws require count evidence without HMC flags", {
  checked <- check_reference_posterior_draws(analytical_acceptance_draws())
  expect_identical(info(checked)$checks_made, list(ndraws_is_10k = TRUE))
  expect_silent(assert_checked_reference_posterior_draws(checked))
  summaries <- summary_statistics_from_checked_reference_draws(checked)
  expect_named(summaries, c("mean_value", "mean_squared_value"))
  for (type in names(summaries)) {
    expect_identical(info(summaries[[type]])$checks_made,
      list(ndraws_is_gte_10k = TRUE))
    expect_silent(assert_checked_summary_statistics_draws(summaries[[type]]))
  }
  expect_equal(summaries$mean_value$mean_value, mean(checked[[1]]$theta))
  expect_equal(summaries$mean_squared_value$mean_squared_value,
    mean(checked[[1]]$theta^2))
  expect_identical(info(checked)$checks_made, list(ndraws_is_10k = TRUE))
  more <- check_summary_statistics_draws(analytical_acceptance_draws(11000L))
  expect_identical(info(more)$checks_made, list(ndraws_is_gte_10k = TRUE))
  expect_silent(compute_reference_posterior_summary_statistic(more))
})

test_that("method applicability does not bypass counts or Stan checks", {
  for (n in c(9999L, 10001L))
    expect_error(check_reference_posterior_draws(analytical_acceptance_draws(n)), "diagnostics.ndraws")
  expect_error(check_summary_statistics_draws(analytical_acceptance_draws(9999L)), "diagnostics.ndraws")
  x <- analytical_acceptance_draws()
  expect_error(assert_checked_reference_posterior_draws(x), "checks_made")
  expect_error(assert_checked_summary_statistics_draws(x), "checks_made")
  metadata <- info(x)
  metadata$diagnostics$ndraws <- 10001L
  info(x) <- metadata
  expect_error(check_reference_posterior_draws(x), "Recorded ndraws")
  metadata$diagnostics$ndraws <- 10000L
  metadata$checks_made <- list(ndraws_is_10k = TRUE, ndraws_is_gte_10k = TRUE)
  metadata$inference$method <- "stan_sampling"
  expect_error(assert_checked_reference_posterior_draws(metadata), "checks_made")
  expect_error(assert_checked_summary_statistics_draws(metadata), "checks_made")
  metadata$inference$method <- "unknown"
  expect_error(assert_checked_reference_posterior_draws(metadata), "method")
})


test_that("duplicate draw variables fail before checking or persistence", {
  checked <- check_reference_posterior_draws(analytical_acceptance_draws())
  malformed <- checked
  malformed[[1]]$other <- malformed[[1]]$theta
  names(malformed[[1]]) <- c("theta", "theta")
  expect_error(as.reference_posterior_draws(posterior::as_draws_list(malformed),
    info(checked)), "unique")
  expect_error(check_reference_posterior_draws(malformed), "unique")
  expect_error(assert_checked_reference_posterior_draws(malformed), "unique")
  expect_error(summary_statistics_from_checked_reference_draws(malformed), "unique")
  info(malformed) <- info(check_summary_statistics_draws(checked))
  expect_error(assert_checked_summary_statistics_draws(malformed), "unique")
  for (type in supported_summary_statistic_types())
    expect_error(compute_reference_posterior_summary_statistic(malformed, type), "unique")

  root <- withr::local_tempdir("duplicate-draws-")
  dir.create(file.path(root, "posteriors"))
  dir.create(file.path(root, "cache"))
  connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
    class = c("pdb_local", "pdb"))
  jsonlite::write_json(list(reference_posterior_name = info(checked)$name),
    file.path(root, "posteriors/linked.json"), auto_unbox = TRUE)
  before <- list.files(root, recursive = TRUE)
  expect_error(write_pdb(malformed, connection), "unique")
  expect_identical(list.files(root, recursive = TRUE), before)
})


test_that("mutated draw shapes fail before checking or persistence", {
  values <- list(list(theta = seq_len(5000), other = seq_len(5000)),
    list(theta = seq_len(5000), other = seq_len(5000)))
  checked <- check_reference_posterior_draws(as.reference_posterior_draws(
    posterior::as_draws_list(values), info(analytical_acceptance_draws())))
  for (failure in c("variable_length", "chain_length")) {
    malformed <- checked
    if (failure == "variable_length") malformed[[1]]$other <- 1
    if (failure == "chain_length") {
      malformed[[2]]$theta <- c(malformed[[2]]$theta, 1)
      malformed[[2]]$other <- c(malformed[[2]]$other, 1)
    }
    expect_error(as.reference_posterior_draws(posterior::as_draws_list(malformed),
      info(checked)), "length", info = failure)
    expect_error(check_reference_posterior_draws(malformed), "length", info = failure)
    expect_error(assert_checked_reference_posterior_draws(malformed), "length", info = failure)
    expect_error(summary_statistics_from_checked_reference_draws(malformed), "length", info = failure)
    info(malformed) <- info(check_summary_statistics_draws(checked))
    expect_error(assert_checked_summary_statistics_draws(malformed), "length", info = failure)
    for (type in supported_summary_statistic_types())
      expect_error(compute_reference_posterior_summary_statistic(malformed, type),
        "length", info = failure)

    root <- withr::local_tempdir("malformed-draws-")
    dir.create(file.path(root, "posteriors"))
    dir.create(file.path(root, "cache"))
    connection <- structure(list(pdb_local_endpoint = root, cache_path = file.path(root, "cache")),
      class = c("pdb_local", "pdb"))
    jsonlite::write_json(list(reference_posterior_name = info(checked)$name),
      file.path(root, "posteriors/linked.json"), auto_unbox = TRUE)
    before <- list.files(root, recursive = TRUE)
    expect_error(write_pdb(malformed, connection, write_summary_statistics = FALSE),
      "length", info = failure)
    expect_identical(list.files(root, recursive = TRUE), before, info = failure)
  }
})
