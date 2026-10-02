test_that("compiled CmdStan CSV imports preserve constrained parameters and honest failures", {
  skip_stan_integration()
  skip_if_not_installed("cmdstanr")
  skip_if(is.null(tryCatch(cmdstanr::cmdstan_path(), error = function(error) NULL)),
    "CmdStan is not installed")
  root <- normalizePath(withr::local_tempdir(), winslash = "/")
  source <- file.path(root, "constrained.stan")
  writeLines(constrained_parameter_model(), source)
  model <- cmdstanr::cmdstan_model(source, quiet = TRUE)
  # CmdStanR's unconstraining methods need precision for constrained matrices.
  fit <- suppressWarnings(model$sample(data = list(), chains = 2, parallel_chains = 2,
    iter_warmup = 6, iter_sampling = 6, seed = 412, refresh = 0, sig_figs = 18,
    output_dir = root))
  expected <- list(weights = 2L, C = 3L, Sigma = 3L, Lcorr = 3L, Lcov = 6L,
    M = 6L, singleton = 1L, a = 4L, theta = 1L)
  expect_identical(infer_unconstrained_parameter_counts_from_fit(fit), expected)
  expect_identical(infer_posterior_dimensions(source, list(), backend = "cmdstanr"), expected)
  object <- structure(list(name = "constrained-posterior", reference_posterior_name = NULL,
    dimensions = expected), class = "pdb_posterior")
  connection <- structure(list(pdb_local_endpoint = root), class = c("pdb_local", "pdb"))
  imported <- suppressWarnings(import_reference_posterior_draws(fit, object, connection,
    include = c("twice_theta", "prediction")))
  csv <- cmdstanr::read_cmdstan_csv(fit$output_files())
  saved <- posterior::subset_draws(csv$post_warmup_draws,
    variable = setdiff(posterior::variables(csv$post_warmup_draws), "lp__"))
  expect_equal(posterior::as_draws_array(imported), saved, ignore_attr = TRUE)
  expect_length(posterior::variables(imported), 49L)
  expect_equal(as.numeric(imported[[1]]$`fixed[1]`), rep(1, 6))
  expect_equal(info(imported)$diagnostics$ndraws, 12L)
  expect_true(is.na(info(imported)$diagnostics$mean_lag1_ac[["fixed[1]"]]))
  expect_true(nzchar(info(imported)$checks_made$check_failed))
  expect_true(nzchar(info(imported)$versions$cmdstanr_version))
  expect_null(info(imported)$versions$rstan_version)
  report <- suppressWarnings(reference_draw_diagnostics(fit))
  expect_equal(info(imported)$diagnostics$mean_lag1_ac, report$metrics$mean_lag1_ac)
  expect_equal(info(imported)$diagnostics$r_hat, report$metrics$r_hat)
  expect_equal(info(imported)$diagnostics$expected_fraction_of_missing_information,
    unname(report$metrics$efmi))
  expect_false(all(unlist(report$status)))
  expect_error(import_reference_posterior_draws(fit, object, connection, exclude = "fixed"),
    "Cannot exclude required")
  bad <- object
  bad$dimensions$weights <- 3L
  expect_error(import_reference_posterior_draws(fit, bad, connection), "unconstrained")
  before <- list.files(root, recursive = TRUE, all.files = TRUE)
  expect_error(suppressWarnings(import_reference_posterior_draws(fit, object, connection,
    write = TRUE)), "checks failed; nothing was written")
  expect_identical(list.files(root, recursive = TRUE, all.files = TRUE), before)
})
