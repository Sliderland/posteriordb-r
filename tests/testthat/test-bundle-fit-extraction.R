test_that("import selection retains every saved scalar for required base variables", {
  dimensions <- list(mu = 1L, theta = 1L, beta = 2L)
  variables <- c("mu", "theta[1]", "beta[1]", "beta[2]", "extra")
  draws <- posterior::as_draws_array(array(
    seq_len(10L),
    c(2L, 1L, 5L),
    dimnames = list(NULL, NULL, variables)
  ))
  required <- posteriordb:::posterior_dimension_names(dimensions)
  selected <- posteriordb:::resolve_import_variable_selection(
    draws,
    required,
    include = "none"
  )
  expect_identical(selected, c("mu", "theta", "beta"))
  retained <- posteriordb:::filter_external_posterior_draws(draws, selected)
  expect_identical(posterior::variables(retained), variables[1:4])
  expect_equal(as.numeric(retained), as.numeric(draws[,, 1:4]))
})

test_that("bundle extraction validates complete declared array coverage", {
  expect_silent(posteriordb:::validate_rstan_saved_coverage(
    "mu",
    "mu",
    integer()
  ))
  expect_silent(posteriordb:::validate_rstan_saved_coverage(
    "theta",
    "theta[1]",
    1L
  ))
  expect_silent(posteriordb:::validate_rstan_saved_coverage(
    "beta",
    c(
      "beta[1,1]",
      "beta[2,1]",
      "beta[1,2]",
      "beta[2,2]",
      "beta[1,3]",
      "beta[2,3]"
    ),
    c(2L, 3L)
  ))
  expect_error(
    posteriordb:::validate_rstan_saved_coverage(
      "theta",
      c("theta[1]", "theta[3]"),
      3L
    ),
    "partial"
  )
  expect_error(
    posteriordb:::validate_rstan_saved_coverage(
      "beta",
      c("beta[1,1]", "beta[2,1]", "beta[1,2]", "beta[2,2]"),
      c(2L, 3L)
    ),
    "partial"
  )
  expect_error(
    posteriordb:::validate_rstan_saved_coverage("mu", "mu[1]", integer()),
    "declared scalar shape"
  )
  expect_error(
    posteriordb:::validate_rstan_saved_coverage(
      "theta",
      c("theta[1]", "theta[2]", "theta[4]"),
      3L
    ),
    "partial"
  )
  expect_error(
    posteriordb:::validate_rstan_saved_coverage(
      "beta",
      c("beta[1]", "beta[1,2]"),
      c(1L, 2L)
    ),
    "partial"
  )
  expect_error(
    posteriordb:::validate_rstan_saved_coverage(
      "beta",
      c(
        "beta[1,1]",
        "beta[2,1]",
        "beta[1,2]",
        "beta[2,2]",
        "beta[1,3]",
        "beta[1,3]"
      ),
      c(2L, 3L)
    ),
    "partial"
  )
})

test_that("identical per-chain sampling arguments are stored once", {
  common <- list(
    list(
      chain_id = 1L,
      iter = 100L,
      warmup = 50L,
      seed = 7L,
      algorithm = "NUTS"
    ),
    list(
      chain_id = 2L,
      iter = 100L,
      warmup = 50L,
      seed = 7L,
      algorithm = "NUTS"
    )
  )
  expect_identical(
    posteriordb:::rstan_sampler_arguments(common),
    list(
      iter = 100L,
      warmup = 50L,
      seed = 7L,
      algorithm = "NUTS"
    )
  )

  chain_specific <- common
  chain_specific[[2L]]$seed <- 8L
  expect_named(
    posteriordb:::rstan_sampler_arguments(chain_specific),
    c("chain1", "chain2")
  )
  arguments <- posteriordb:::rstan_sampler_arguments(chain_specific)
  expect_identical(
    vapply(arguments, `[[`, integer(1), "seed"),
    c(chain1 = 7L, chain2 = 8L)
  )
})
