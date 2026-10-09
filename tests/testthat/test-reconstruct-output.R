reconstruction_draws <- function() {
  values <- array(c(0.1, -0.4, 1.2, 0.7, 0.5, 2, 1.5, 0.25), dim = c(2, 2, 2),
                  dimnames = list(NULL, NULL, c("mu", "sigma")))
  posterior::as_draws_array(values)
}

test_that("reconstruction rejects invalid requests before compiling", {
  skip_if_not_installed("rstan")
  draws <- reconstruction_draws()
  expect_error(reconstruct_stan_output(draws, "model.stan", list(), variables = c("mu", "mu")),
               "unique, non-empty variable names")
  expect_error(reconstruct_stan_output(draws, "model.stan", list(), seed = 0),
               "positive integer")
  expect_error(reconstruct_stan_output(draws, "model.stan", data = NULL),
               "named Stan data list")
  expect_error(reconstruct_stan_output(draws, file.path(tempdir(), "missing-model.stan"), list()),
               "Stan source file does not exist")
  expect_error(reconstruct_stan_output(draws, 42, list()), "model must be a stanfit")
})

test_that("derived outputs are recomputed from parameter draws", {
  skip_stan_integration()
  skip_if_not_installed("rstan")
  code <- paste(
    "parameters { real mu; real<lower=0> sigma; }",
    "transformed parameters { real twice_mu = 2 * mu; }",
    "model { mu ~ normal(0, 1); sigma ~ normal(0, 1); }",
    "generated quantities { real ratio = mu / sigma; }"
  )
  draws <- reconstruction_draws()
  mu <- as.numeric(posterior::subset_draws(draws, variable = "mu"))
  sigma <- as.numeric(posterior::subset_draws(draws, variable = "sigma"))

  result <- suppressWarnings(reconstruct_stan_output(draws, code, list(), include_unconstrained = TRUE))
  expect_identical(result$backend, "rstan")
  expect_identical(result$parameter_names, c("mu", "sigma"))
  expect_setequal(posterior::variables(result$draws), c("mu", "sigma", "twice_mu", "ratio"))
  value <- function(x, name) as.numeric(posterior::subset_draws(x, variable = name))
  expect_equal(value(result$draws, "twice_mu"), 2 * mu)
  expect_equal(value(result$draws, "ratio"), mu / sigma)
  expect_equal(value(result$unconstrained_draws, "sigma"), log(sigma))

  # The returned evaluator is reused without data or recompilation.
  selected <- reconstruct_stan_output(draws, result$evaluator, variables = "twice_mu")
  expect_identical(posterior::variables(selected$draws), "twice_mu")
  expect_equal(value(selected$draws, "twice_mu"), 2 * mu)
  expect_null(selected$unconstrained_draws)

  expect_error(reconstruct_stan_output(draws, result$evaluator, variables = "absent"),
               "Unknown requested output")
  expect_error(reconstruct_stan_output(posterior::subset_draws(draws, variable = "mu"),
                                       result$evaluator),
               "Missing: sigma")
  expect_error(reconstruct_stan_output(draws, result$evaluator, data = list()),
               "already binds its data")
})

test_that("posterior reconstruction follows the saved links", {
  local_test_database()
  pdb_test <- pdb_local()
  expect_error(reconstruct_posterior_output("prideprejudice_chapter-ldaK5", pdb = pdb_test),
               "no linked reference draws")

  name <- "eight_schools-eight_schools_noncentered"
  received <- NULL
  testthat::local_mocked_bindings(reconstruct_stan_output = function(...) {
    received <<- list(...)
    "reconstructed"
  })
  expect_identical(reconstruct_posterior_output(name, pdb = pdb_test, variables = "theta", seed = 7L),
                   "reconstructed")
  po <- posterior(name, pdb = pdb_test)
  expect_equal(received$draws, reference_posterior_draws(po))
  expect_equal(received$model, model_code(po, framework = "stan"))
  expect_equal(received$data, get_data(po))
  expect_identical(received[c("variables", "seed", "include_unconstrained")],
                   list(variables = "theta", seed = 7L, include_unconstrained = FALSE))
})
