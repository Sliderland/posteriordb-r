test_that("CmdStanR translation preserves supported RStan controls", {
  controls <- list(adapt_delta = 0.9, max_treedepth = 11L, stepsize = 0.5,
    adapt_engaged = FALSE, metric = "diag_e", adapt_init_buffer = 5L,
    adapt_term_buffer = 5L, adapt_window = 10L)
  expected <- controls
  names(expected) <- c("adapt_delta", "max_treedepth", "step_size",
    "adapt_engaged", "metric", "init_buffer", "term_buffer", "window")
  expect_identical(posteriordb:::translate_cmdstanr_sampling_args(list(control = controls)), expected)
  args <- posteriordb:::translate_cmdstanr_sampling_args(list(
    iter = 30L, warmup = 10L, cores = 2L, seed = 42L))
  expect_identical(args[c("iter_sampling", "iter_warmup", "parallel_chains", "seed")],
    list(iter_sampling = 20L, iter_warmup = 10L, parallel_chains = 2L, seed = 42L))
  expect_length(posteriordb:::translate_cmdstanr_sampling_args(list(control = list())), 0L)
  expect_identical(posteriordb:::translate_cmdstanr_sampling_args(list(
    step_size = 0.5, control = list(stepsize = NULL))), list(step_size = 0.5))
  for (args in list(list(iter_sampling = 20L), list(iter_warmup = 10L),
    list(iter_warmup = 10L, iter_sampling = 20L))) {
    expect_identical(posteriordb:::translate_cmdstanr_sampling_args(args), args)
  }
  expect_length(posteriordb:::translate_cmdstanr_sampling_args(list(
    iter = NULL, warmup = NULL, control = NULL)), 0L)
  expect_identical(posteriordb:::translate_cmdstanr_sampling_args(list(
    diagnostics = NULL)), list(diagnostics = NULL))
})

test_that("CmdStanR translation rejects lost or ambiguous settings", {
  for (control in c("adapt_gamma", "adapt_kappa", "adapt_t0", "stepsize_jitter", "int_time", "typo")) {
    expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(
      control = stats::setNames(list(0.1), control))), "Unsupported.*control")
  }
  for (args in list(
    list(cores = 2, parallel_chains = 8),
    list(step_size = 0.1, stepsize = 0.2),
    list(max_treedepth = 10, max_depth = 12),
    list(adapt_delta = 0.8, control = list(adapt_delta = 0.9)),
    list(step_size = 0.1, control = list(stepsize = 0.2)),
    list(stepsize = 0.1, control = list(stepsize = 0.2)),
    list(init_buffer = 5, control = list(adapt_init_buffer = 10)))) {
    expect_error(posteriordb:::translate_cmdstanr_sampling_args(args), "both|[Cc]onflict")
  }
  expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(control = list(0.1))), "names")
  expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(control = list(stepsize = 0.1, stepsize = 0.2))), "names")
  expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(iter = 20, iter_sampling = 10)), "either")
})

test_that("CmdStanR native aliases cannot override canonical options", {
  aliases <- c(cores = "parallel_chains", num_cores = "parallel_chains",
    num_chains = "chains", num_warmup = "iter_warmup", num_samples = "iter_sampling",
    stepsize = "step_size", max_depth = "max_treedepth",
    save_extra_diagnostics = "save_latent_dynamics")
  for (alias in names(aliases)) {
    target <- aliases[[alias]]
    translated <- posteriordb:::translate_cmdstanr_sampling_args(stats::setNames(list(1L), alias))
    expect_identical(translated[[target]], 1L)
    expect_false(alias %in% names(translated))
    expect_error(posteriordb:::translate_cmdstanr_sampling_args(
      stats::setNames(list(1L, 2L), c(alias, target))), "both")
  }
  expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(cores = 1, num_cores = 2)), "both")
  expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(iter = 20, num_samples = 10)), "either")
  for (value in list("divergences", NULL)) {
    expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(
      validate_csv = FALSE, diagnostics = value)), "both")
    expect_error(posteriordb:::translate_cmdstanr_sampling_args(list(
      validate_csv = TRUE, diagnostics = value)), "both")
  }
})
