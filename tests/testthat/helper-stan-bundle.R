# Real sampled fits for test-stan-bundle.R. Each case is sampled once per
# backend with posteriordb's reference settings and reused across tests.
stan_bundle_case <- function(case) {
  eight_schools <- list(
    J = 8L,
    y = c(28, 8, -3, 7, -1, 1, 18, 12),
    sigma = c(15, 10, 16, 11, 9, 11, 10, 18)
  )
  switch(
    case,
    # posteriordb's eight_schools_noncentered, with its adapt_delta.
    accepted = list(
      model = "eight_schools_noncentered",
      data_name = "eight_schools",
      data = eight_schools,
      adapt_delta = 0.95,
      dimensions = list(theta_trans = 8L, mu = 1L, tau = 1L),
      code = "
        data {
          int<lower=0> J;
          array[J] real y;
          array[J] real<lower=0> sigma;
        }
        parameters {
          vector[J] theta_trans;
          real mu;
          real<lower=0> tau;
        }
        transformed parameters {
          vector[J] theta;
          theta = theta_trans * tau + mu;
        }
        model {
          theta_trans ~ normal(0, 1);
          y ~ normal(theta, sigma);
          mu ~ normal(0, 5);
          tau ~ cauchy(0, 5);
        }
      "
    ),
    # posteriordb's eight_schools_centered: the funnel gives hundreds of
    # divergences and strongly autocorrelated draws on every seed tried.
    rejected = list(
      model = "eight_schools_centered",
      data_name = "eight_schools",
      data = eight_schools,
      adapt_delta = 0.8,
      dimensions = list(theta = 8L, mu = 1L, tau = 1L),
      code = "
        data {
          int<lower=0> J;
          array[J] real y;
          array[J] real<lower=0> sigma;
        }
        parameters {
          array[J] real theta;
          real mu;
          real<lower=0> tau;
        }
        model {
          tau ~ cauchy(0, 5);
          theta ~ normal(mu, tau);
          y ~ normal(theta, sigma);
          mu ~ normal(0, 5);
        }
      "
    ),
    # A multivariate normal with an LKJ prior. The Cholesky factor's first
    # element and upper triangle, and the correlation diagonal, never vary.
    constrained = list(
      model = "mvn_lkj",
      data_name = "correlated_outcomes",
      data = withr::with_seed(4711, {
        n <- 40L
        k <- 3L
        correlation <- matrix(c(1, .5, -.3, .5, 1, .2, -.3, .2, 1), k)
        scaled_factor <- diag(c(1, 2, .5)) %*% t(chol(correlation))
        noise <- matrix(stats::rnorm(n * k), k, n)
        list(N = n, K = k, y = t(c(1, 0, -1) + scaled_factor %*% noise))
      }),
      adapt_delta = 0.8,
      dimensions = list(mu = 3L, tau = 3L, L_Omega = 3L),
      code = "
        data {
          int<lower=1> N;
          int<lower=1> K;
          array[N] vector[K] y;
        }
        parameters {
          vector[K] mu;
          vector<lower=0>[K] tau;
          cholesky_factor_corr[K] L_Omega;
        }
        model {
          mu ~ normal(0, 5);
          tau ~ exponential(1);
          L_Omega ~ lkj_corr_cholesky(2);
          y ~ multi_normal_cholesky(mu, diag_pre_multiply(tau, L_Omega));
        }
        generated quantities {
          corr_matrix[K] Omega = multiply_lower_tri_self_transpose(L_Omega);
        }
      "
    )
  )
}

stan_bundle_rstan_fit <- local({
  fits <- list()
  function(case) {
    skip_stan_integration()
    skip_if_not_installed("rstan")
    if (is.null(fits[[case]])) {
      spec <- stan_bundle_case(case)
      fits[[case]] <<- suppressWarnings(rstan::sampling(
        rstan::stan_model(model_code = spec$code),
        data = spec$data,
        chains = 10,
        cores = 1L,
        warmup = 10000,
        iter = 20000,
        thin = 10,
        seed = 4711,
        refresh = 0,
        control = list(adapt_delta = spec$adapt_delta)
      ))
    }
    fits[[case]]
  }
})

stan_bundle_cmdstan_fit <- local({
  fits <- list()
  function(case) {
    skip_stan_integration()
    skip_if_not_installed("cmdstanr")
    skip_if(
      is.null(tryCatch(cmdstanr::cmdstan_path(), error = function(error) NULL)),
      "CmdStan is not installed"
    )
    if (is.null(fits[[case]])) {
      spec <- stan_bundle_case(case)
      # The CSV files must outlive the test that first samples the fit.
      root <- normalizePath(
        withr::local_tempdir(.local_envir = testthat::teardown_env()),
        winslash = "/"
      )
      source <- file.path(root, paste0(spec$model, ".stan"))
      writeLines(spec$code, source)
      model <- cmdstanr::cmdstan_model(source, quiet = TRUE)
      # CmdStanR's unconstraining methods need precision for constrained matrices.
      fits[[case]] <<- suppressWarnings(model$sample(
        data = spec$data,
        chains = 10,
        parallel_chains = 1,
        iter_warmup = 10000,
        iter_sampling = 10000,
        thin = 10,
        seed = 4711,
        refresh = 0,
        adapt_delta = spec$adapt_delta,
        sig_figs = 18,
        output_dir = root,
        show_messages = FALSE
      ))
    }
    fits[[case]]
  }
})

stan_bundle_create <- function(fit, case, ...) {
  spec <- stan_bundle_case(case)
  create_pdb_bundle(
    fit,
    data = spec$data,
    data_info = list(name = spec$data_name, title = "Inputs"),
    model_info = list(name = spec$model, title = "Model"),
    ...
  )
}

stan_bundle_import <- function(fit, case) {
  object <- structure(
    list(
      name = "stan-bundle-posterior",
      reference_posterior_name = NULL,
      dimensions = stan_bundle_case(case)$dimensions
    ),
    class = "pdb_posterior"
  )
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  suppressWarnings(import_reference_posterior_draws(fit, object, connection))
}

stan_bundle_pdb <- function(.local_envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .local_envir)
  for (folder in c("data", "models", "posteriors", "alias", "cache")) {
    dir.create(file.path(root, folder))
  }
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  pdb_local(root, cache_path = file.path(root, "cache"))
}

# Saved draws without the log density, as an independent comparison.
stan_bundle_saved_draws <- function(draws) {
  draws <- posterior::as_draws_array(draws)
  posterior::subset_draws(
    draws,
    variable = setdiff(posterior::variables(draws), "lp__"),
    regex = FALSE
  )
}

# Variables that never change, up to rounding in a correlation diagonal.
stan_bundle_constant_variables <- function(draws) {
  spread <- apply(unclass(posterior::as_draws_array(draws)), 3L, function(x) {
    diff(range(x))
  })
  names(spread)[spread <= 1e-12]
}
