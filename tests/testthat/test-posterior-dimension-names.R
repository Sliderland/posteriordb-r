test_that("posterior dimensions identify base variables, not draw shapes", {
  names <- posteriordb:::posterior_dimension_names(list(
    A = 4L, B = 2L, x = 3L, mu = 1L, scalar = 1L
  ))

  expect_identical(names, c("A", "B", "x", "mu", "scalar"))
  expect_identical(posteriordb:::posterior_dimension_names(c(mu = 1, theta = 2)), c("mu", "theta"))
  expect_identical(
    posteriordb:::posterior_dimension_names(list(C = 8L)),
    "C"
  )
})

test_that("invalid declarations fail before variable matching", {
  dimension_names <- posteriordb:::posterior_dimension_names

  expect_error(dimension_names(list()), "Must have length >= 1")
  expect_error(dimension_names(setNames(list(2L), "")), "Assertion on 'dimensions' failed")
  expect_error(dimension_names(setNames(list(2L, 3L), c("x", "x"))), "duplicated values")
  expect_error(dimension_names(list(x = 0L)), "must be one positive integer")
  expect_error(dimension_names(list(x = NA_integer_)), "must be one positive integer")
  expect_error(dimension_names(list(x = 1.5)), "must be one positive integer")
  expect_error(dimension_names(list(x = Inf)), "must be one positive integer")
  expect_error(dimension_names(list(x = TRUE)), "must be one positive integer")
})

test_that("saved unconstrained dimension arrays become counts on lookup", {
  root <- normalizePath(withr::local_tempdir(), winslash = "/")
  for (path in c("data/info", "models/info", "posteriors", "alias", "cache"))
    dir.create(file.path(root, path), recursive = TRUE)
  writeLines("{}", file.path(root, "alias/posteriors.json"))
  connection <- pdb_local(root, cache_path = file.path(root, "cache"))
  write_pdb(as.pdb_model_info(list(name = "model", title = "Model", framework = "stan",
    added_by = "test", added_date = Sys.Date())), connection)
  write_pdb(as.pdb_data_info(list(name = "inputs", title = "Inputs",
    added_by = "test", added_date = Sys.Date())), connection)
  record <- list(name = "inputs-model", model_name = "model", data_name = "inputs",
    reference_posterior_name = NULL, dimensions = list(pi1 = 2L, A = c(3L, 2L), w = c(3L, 4L)),
    added_by = "test", added_date = "2026-01-01")
  path <- file.path(root, "posteriors/inputs-model.json")
  jsonlite::write_json(record, path, auto_unbox = TRUE, null = "null")
  expect_silent(object <- posterior(record$name, connection))
  expect_equal(object$dimensions, list(pi1 = 2L, A = 6L, w = 12L))
  expect_identical(jsonlite::read_json(path, simplifyVector = TRUE)$dimensions$A, c(3L, 2L))
  object$dimensions <- record$dimensions
  expect_error(assert_pdb_posterior(object), "one positive integer")

  for (invalid in list(c(0L, 2L), c(-1L, -2L), c(0.5, 2), c(2, NA), c(2, Inf), c(TRUE, TRUE))) {
    record$dimensions$A <- invalid
    jsonlite::write_json(record, path, auto_unbox = TRUE, null = "null")
    pdb_clear_cache(connection)
    expect_error(posterior(record$name, connection), "dimension")
  }
})


test_that("free-coordinate count selection and representations stay canonical", {
  coordinates <- c("weights.1", "weights.2", "M.1.1", "M.2.1", "theta")
  expect_identical(unconstrained_parameter_counts(coordinates),
    list(weights = 2L, M = 2L, theta = 1L))
  bracket_coordinates <- c("weights[1]", "weights[2]", "M[1,1]", "M[2,1]", "theta")
  expect_identical(unconstrained_parameter_counts(bracket_coordinates),
    list(weights = 2L, M = 2L, theta = 1L))
  expect_identical(unconstrained_parameter_counts(coordinates, include = "weights"),
    list(weights = 2L))
  expect_identical(unconstrained_parameter_counts(coordinates, exclude = "weights"),
    list(M = 2L, theta = 1L))
  expect_error(unconstrained_parameter_counts(coordinates, include = "fixed"), "Unknown")
  expect_error(unconstrained_parameter_counts(coordinates, include = character()), "no unconstrained")
  expect_error(unconstrained_parameter_counts(character()), "No unconstrained")
  expect_equal(validate_import_dimensions(c(theta = 1, M = 2)), list(theta = 1L, M = 2L))
  expect_error(validate_import_dimensions(list(theta = c(2L, 3L))), "one positive integer")
  for (include in list(NULL, "all")) {
    for (exclude in list(NULL, character(), "none", "lp__")) {
      expect_identical(unconstrained_parameter_counts(coordinates, include, exclude),
        list(weights = 2L, M = 2L, theta = 1L))
    }
  }
  expect_error(unconstrained_parameter_counts(coordinates, include = "none"), "no unconstrained")
  expect_error(unconstrained_parameter_counts(coordinates, exclude = "all"), "no unconstrained")
  expect_error(unconstrained_parameter_counts(coordinates, include = "weights", exclude = "weights"),
    "both.*include.*exclude")
  fit <- structure(list(unconstrain_draws = function() posterior::as_draws_array(
    array(1:10, c(2, 1, 5), dimnames = list(NULL, NULL, coordinates)))), class = "CmdStanMCMC")
  expect_identical(infer_unconstrained_parameter_counts_from_fit(fit, include = "all", exclude = "none"),
    list(weights = 2L, M = 2L, theta = 1L))
})
