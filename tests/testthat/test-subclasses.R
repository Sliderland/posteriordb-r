test_that("connection subclasses retain their database type and cache identity", {
  for (type in c("local", "github")) {
    connection <- structure(
      list(pdb_id = "fixture"),
      class = c(paste0("pdb_", type), "pdb")
    )
    child <- connection
    class(child) <- c("custom_connection", class(child))
    expect_identical(pdb_type(child), type)
    expect_identical(
      pdb_cache_namespace(child),
      pdb_cache_namespace(connection)
    )
  }
})

test_that("summary subclasses retain the exact summary type", {
  metadata <- as.reference_posterior_info(list(
    name = "fixture",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = NULL,
    checks_made = NULL,
    comments = NULL,
    added_by = "test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  for (type in c("mean_value", "mean_squared_value")) {
    object <- reference_posterior_summary_statistic(
      stats::setNames(list("theta", 2, .1), c("names", type, "mcse_mean")),
      metadata,
      type
    )
    class(object) <- c("custom_mean_value_mean_squared_value", class(object))
    expect_identical(summary_statistic_type(object), type)
    expect_silent(assert_reference_posterior_summary_statistic(object))
  }
})

test_that("draw transformations preserve subclasses and clear obsolete evidence", {
  metadata <- as.reference_posterior_info(list(
    name = "fixture",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = 8L),
    checks_made = list(obsolete = TRUE),
    comments = NULL,
    added_by = "test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  object <- as.reference_posterior_draws(
    posterior::as_draws_list(list(
      list(alpha = 1:4, beta = 5:8),
      list(alpha = 9:12, beta = 13:16)
    )),
    metadata,
    pdb = connection
  )
  class(object) <- c("custom_draws", class(object))
  selected <- subset(object, variable = "beta")
  thinned <- posterior::thin_draws(object, 2L)
  for (result in list(selected, thinned)) {
    expect_identical(class(result), class(object))
    expect_identical(pdb(result), connection)
    expect_null(info(result)$checks_made)
  }
  expect_identical(posterior::variables(selected), "beta")
  expect_equal(unclass(thinned)[[1L]]$alpha, c(1L, 3L))
  expect_equal(unclass(thinned)[[2L]]$beta, c(13L, 15L))
  expect_identical(posterior::thin_draws(object, 1L), object)
})

test_that("draw transformations delegate past subclass methods only once", {
  thin_calls <- subset_calls <- 0L
  # Methods defined here are found by S3 dispatch from this test only.
  thin_draws.delegating_draws <- function(x, thin, ...) {
    thin_calls <<- thin_calls + 1L
    NextMethod(thin = thin * 2L)
  }
  subset.delegating_draws <- function(x, ...) {
    subset_calls <<- subset_calls + 1L
    NextMethod()
  }
  metadata <- as.reference_posterior_info(list(
    name = "fixture",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = 64L),
    checks_made = NULL,
    comments = NULL,
    added_by = "test",
    added_date = Sys.Date(),
    versions = NULL
  ))
  object <- as.reference_posterior_draws(
    posterior::as_draws_list(list(
      list(alpha = 1:32),
      list(alpha = 33:64)
    )),
    metadata
  )
  attr(object, "sampler_diagnostics") <- posterior::as_draws_array(array(
    1:64,
    c(32, 2, 1),
    dimnames = list(NULL, NULL, "energy__")
  ))
  class(object) <- c("delegating_draws", class(object))
  result <- posterior::thin_draws(object, 2L)
  expect_identical(thin_calls, 1L)
  expect_equal(posterior::ndraws(result), 16L)
  expect_equal(posterior::ndraws(attr(result, "sampler_diagnostics")), 16L)
  expect_identical(class(result), class(object))
  expect_equal(
    unname(posterior::as_draws_array(result)[,, 1L]),
    unname(posterior::as_draws_array(attr(result, "sampler_diagnostics"))[,,
      1L
    ])
  )
  selected <- subset(object, variable = "alpha")
  expect_identical(subset_calls, 1L)
  expect_identical(class(selected), class(object))
  nested <- object
  class(nested) <- c("outer_draws", class(object))
  subset(nested, variable = "alpha")
  expect_identical(subset_calls, 2L)
})
