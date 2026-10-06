context("test-posterior-getters")

test_that("every stored posterior can read its metadata, data, and model source", {
  local_test_database()
  connection <- pdb_local()
  posterior_ids <- posterior_names(connection)
  expect_gt(length(posterior_ids), 0L)
  for (name in posterior_ids) {
    po <- posterior(name, connection)
    expect_s3_class(po, "pdb_posterior")
    expect_s3_class(get_data(po), "pdb_data")
    implementations <- po$model_info$model_implementations
    for (framework in names(implementations)[!vapply(implementations, is.null, logical(1))]) {
      # Some corpus source files lack a final newline; reading must still work.
      expect_s3_class(suppressWarnings(model_code(po, framework)), "pdb_model_code")
    }
  }
})

test_that("Eight Schools can access stan_data and stan_code", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())

  expect_silent(po <- posterior("eight_schools-eight_schools_noncentered", pdb = pdb_test))

  # Test stan_data_file_path
  expect_silent(sdfp <- stan_data_file_path(po))
  expect_true(file.exists(sdfp))
  if(!posteriordb:::on_windows()) expect_true(grepl(pattern = tempdir(), x = sdfp))
  expect_equal(posteriordb:::get_file_extension(sdfp), "json")
  expect_silent(jsonlite::read_json(sdfp))

  # Test data_info
  expect_silent(di <- data_info(po))
  expect_s3_class(di, "pdb_data_info")
  expect_output(print(di), "Data: eight_schools")

  # Test model_code
  expect_silent(mcfp <- model_code_file_path(po, "stan"))
  expect_true(file.exists(mcfp))
  if(!posteriordb:::on_windows()) expect_true(grepl(pattern = tempdir(), x = mcfp))
  expect_equal(posteriordb:::get_file_extension(mcfp), "stan")
  expect_silent(scfp <- stan_code_file_path(po))
  expect_equal(scfp, mcfp)

  # Test model_code
  expect_silent(mc <- model_code(po, framework = "stan"))
  expect_s3_class(mc, "pdb_model_code")
  expect_output(print(mc), "data \\{")
  expect_output(print(mc), "parameters \\{")
  expect_output(print(mc), "model \\{")

  # Test stan_code
  expect_silent(sc <- stan_code(po))
  expect_s3_class(sc, "pdb_model_code")
  expect_equal(sc, mc)

  # Test model_info
  expect_silent(mi <- model_info(po))
  expect_s3_class(mi, "pdb_model_info")
  expect_output(print(mi), "Model: eight_schools_noncentered")

  expect_output(print(po), "Posterior")

  # Get posteriors draws directly
  expect_silent(gsd <- reference_posterior_draws(po))
  expect_silent(gsi <- reference_posterior_draws_info(po))

})



test_that("Check access only with posterior name", {
  local_test_database()
  expect_silent(pdb_test <- pdb_local())

  # Test stan_data_file_path
  expect_silent(di <- data_info("eight_schools", pdb_test))
  expect_silent(d1 <- get_data("eight_schools", pdb_test))
  expect_silent(d2 <- get_data(di, pdb_test))
  expect_identical(d1,d2)
  expect_silent(sdfp <- data_file_path("eight_schools", pdb_test))
  expect_silent(sdfp <- data_file_path(di, pdb_test))
  expect_true(file.exists(sdfp))

  # Test model_code/stan_code
  expect_silent(mi <- model_info("eight_schools_noncentered", pdb = pdb_test, framework = "stan"))
  expect_silent(sc1 <- stan_code("eight_schools_noncentered", pdb = pdb_test))
  expect_silent(sc2 <- stan_code(mi, pdb = pdb_test))
  expect_identical(sc1,sc2)
  expect_silent(mcfp <- model_code_file_path("eight_schools_noncentered", pdb = pdb_test, framework = "stan"))
  expect_silent(mcfp <- model_code_file_path(mi, pdb = pdb_test, framework = "stan"))
  expect_true(file.exists(mcfp))

  # Test reference_posterior
  expect_silent(gsi <- reference_posterior_draws_info("eight_schools-eight_schools_noncentered", pdb = pdb_test))
  expect_silent(gsd1 <- reference_posterior_draws("eight_schools-eight_schools_noncentered", pdb = pdb_test))
  expect_silent(gsd2 <- reference_posterior_draws(x = gsi, pdb = pdb_test))
  expect_identical(gsd1,gsd2)
  expect_silent(gsdfp <- reference_posterior_draws_file_path("eight_schools-eight_schools_noncentered", pdb = pdb_test))
  expect_silent(gsdfp <- reference_posterior_draws_file_path(gsi, pdb = pdb_test))
})



test_that("Check access only with posterior name and default pdb", {
  local_test_database()
  skip_if(is.null(github_pat()))

  # Test stan_data_file_path
  expect_silent(di <- data_info("eight_schools"))
  expect_silent(d1 <- get_data("eight_schools"))
  expect_silent(d2 <- get_data(di))
  expect_silent(sdfp <- data_file_path("eight_schools"))
  expect_silent(sdfp <- data_file_path(di))

  # Test model_code/stan_code
  expect_silent(mi <- model_info("eight_schools_noncentered", framework = "stan"))
  expect_silent(sc1 <- stan_code("eight_schools_noncentered"))
  expect_silent(sc2 <- stan_code(mi))
  expect_silent(mcfp <- model_code_file_path("eight_schools_noncentered", framework = "stan"))
  expect_silent(mcfp <- model_code_file_path(mi, framework = "stan"))

  # Test reference_posterior
  expect_silent(gsi <- reference_posterior_draws_info("eight_schools-eight_schools_noncentered"))
  expect_silent(gsd1 <- reference_posterior_draws("eight_schools-eight_schools_noncentered"))
  expect_silent(gsd2 <- reference_posterior_draws(x = gsi))
  expect_silent(gsdfp <- reference_posterior_draws_file_path("eight_schools-eight_schools_noncentered"))
  expect_silent(gsdfp <- reference_posterior_draws_file_path(gsi))

})



test_that("Check that model_code, data and reference_posteriors contain a pdb attr", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())

  expect_silent(po <- posterior("eight_schools-eight_schools_noncentered", pdb = pdb_test))
  expect_identical(pdb(po), pdb_test)

  expect_silent(d <- get_data(po))
  expect_identical(pdb(d), pdb_test)

  expect_silent(mc <- stan_code(po))
  expect_identical(pdb(mc), pdb_test)

  expect_silent(rp <- reference_posterior_draws(po))
  expect_identical(pdb(rp), pdb_test)

})


test_that("a posterior object can be created from a list", {
  local_test_database()

  expect_silent(pdb_test <- pdb_local())

  expect_silent(po <- posterior("eight_schools-eight_schools_noncentered", pdb = pdb_test))

  x <- list(pdb_data = get_data(po),
            pdb_model_code = model_code(po, framework = "stan"),
            dimensions = po$dimensions)

  expect_message(po2 <- as.posterior(x, pdb_test))

})

test_that("stored legacy dimension vectors remain readable without becoming counts", {
  # Exact dimension metadata from the three corpus records rejected by scalar
  # count validation; the linked data and source are deliberately tiny.
  dimensions <- list(
    "hmm_gaussian_simulated-hmm_gaussian" = list(
      pi1 = 2L, A = c(3L, 2L), mu = 3L, sigma = 3L),
    "iohmm_reg_simulated-iohmm_reg" = list(
      pi1 = 2L, w = c(3L, 4L), b = c(3L, 4L), sigma = 3L),
    "state_wide_presidential_votes-hierarchical_gp" = list(
      GP_region_std = c(14L, 10L), GP_state_std = c(14L, 50L),
      year_std = 11L, state_std = 50L, region_std = 10L, tot_var = 1L,
      prop_var = 16L, mu = 1L, length_GP_region_long = 1L,
      length_GP_state_long = 1L, length_GP_region_short = 1L,
      length_GP_state_short = 1L)
  )
  root <- withr::local_tempdir("legacy-posteriors-")
  for (path in c("data", "models", "posteriors", "alias", "cache"))
    dir.create(file.path(root, path))
  writeLines("{}", file.path(root, "alias/posteriors.json"))
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  date <- as.Date("2026-01-01")
  data <- as.pdb_data(list(y = 1:3), info = as.pdb_data_info(list(
    name = "inputs", title = "Inputs", added_by = "test", added_date = date)))
  source <- "parameters { real theta; } model { theta ~ normal(0, 1); }"
  code <- as.model_code(source, info = as.pdb_model_info(list(
    name = "model", title = "Model", framework = "stan",
    added_by = "test", added_date = date)), framework = "stan")
  write_pdb(data, connection)
  write_pdb(code, connection)

  for (name in names(dimensions)) {
    path <- file.path(root, "posteriors", paste0(name, ".json"))
    jsonlite::write_json(list(name = name, model_name = "model", data_name = "inputs",
      reference_posterior_name = NULL, dimensions = dimensions[[name]],
      added_by = "test", added_date = "2026-01-01"), path,
      auto_unbox = TRUE, null = "null")
    before <- readLines(path, warn = FALSE)

    expect_silent(po <- posterior(name, connection))
    expect_identical(po$dimensions, dimensions[[name]])
    expect_identical(get_data(po), get_data("inputs", connection))
    expect_identical(as.character(stan_code(po)), source)
    expect_identical(as.data.frame(po)$name, name)
    expect_identical(pdb(po), connection)
    expect_error(reference_posterior_draws(po), "no reference posterior")
    expect_error(as.posterior(unclass(po), connection), "one positive integer")
    expect_error(write_pdb(po, connection, overwrite = TRUE), "one positive integer")
    expect_error(posterior_dimension_names(po$dimensions), "one positive integer")
    expect_error(validate_import_dimensions(po$dimensions), "one positive integer")
    expect_identical(readLines(path, warn = FALSE), before)
  }
  expect_setequal(posterior_names(connection), names(dimensions))

  # Reading legacy vectors still validates their values and parameter names.
  for (invalid in list(list(A = c(3, 0)), list(A = c(3, 1.5)),
                       list(A = c(3, 2 + 1e-9)), list(A = c(3, Inf)),
                       list(A = c(3, NA_real_)), list(A = character()),
                       list(A = c("3", "2")), list(A = 2L, A = 3L))) {
    bad <- po
    bad$dimensions <- invalid
    expect_error(assert_pdb_posterior(bad, allow_legacy_dimensions = TRUE))
  }
})
