empty_local_pdb <- function() {
  root <- tempfile("posteriordb-import-")
  dir.create(file.path(root, "data"), recursive = TRUE)
  dir.create(file.path(root, "models"), recursive = TRUE)
  dir.create(file.path(root, "posteriors"), recursive = TRUE)
  dir.create(file.path(root, "cache"))
  pdb_local(root, cache_path = file.path(root, "cache"))
}

linked_local_pdb <- function() {
  pdb <- empty_local_pdb()
  root <- pdb$pdb_local_endpoint
  dir.create(file.path(root, "alias"))
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  dir.create(file.path(root, "data", "info"), recursive = TRUE)
  dir.create(file.path(root, "models", "info"), recursive = TRUE)
  for (folder in c(
    "reference_posteriors/draws/info",
    "reference_posteriors/draws/draws",
    unlist(
      lapply(posteriordb:::supported_summary_statistic_types(), function(type) {
        c(
          file.path("reference_posteriors", "summary_statistics", type, "info"),
          file.path("reference_posteriors", "summary_statistics", type, type)
        )
      }),
      use.names = FALSE
    )
  )) {
    dir.create(file.path(root, folder), recursive = TRUE, showWarnings = FALSE)
  }
  jsonlite::write_json(
    list(
      name = "external-data",
      data_file = "data/data/external-data.json",
      title = "External test data",
      added_by = "testthat",
      added_date = as.character(Sys.Date())
    ),
    file.path(root, "data", "info", "external-data.info.json"),
    auto_unbox = TRUE,
    null = "null"
  )
  jsonlite::write_json(
    list(
      name = "external-model",
      model_implementations = list(
        stan = list(
          model_code = "models/stan/external-model.stan"
        )
      ),
      title = "External test model",
      added_by = "testthat",
      added_date = as.character(Sys.Date())
    ),
    file.path(root, "models", "info", "external-model.info.json"),
    auto_unbox = TRUE,
    null = "null"
  )
  jsonlite::write_json(
    list(
      name = "external-data-external-model",
      model_name = "external-model",
      data_name = "external-data",
      reference_posterior_name = NULL,
      dimensions = list(alpha = 1L, beta = 1L),
      added_by = "testthat",
      added_date = as.character(Sys.Date())
    ),
    file.path(root, "posteriors", "external-data-external-model.json"),
    auto_unbox = TRUE,
    null = "null"
  )
  pdb
}

external_fit_fixture <- local({
  fit <- NULL
  function() {
    skip_stan_integration()
    skip_if_not_installed("rstan")
    if (is.null(fit)) {
      model_code <- "
        parameters {
          matrix[2, 2] A;
          real declared;
          real undeclared;
        }
        model {
          to_vector(A) ~ normal(0, 1);
          declared ~ normal(0, 1);
          undeclared ~ normal(0, 1);
        }
      "
      sm <- rstan::stan_model(model_code = model_code)
      fit <<- suppressWarnings(rstan::sampling(
        sm,
        iter = 20,
        warmup = 10,
        chains = 2,
        seed = 1234,
        refresh = 0
      ))
    }
    fit
  }
})

external_posterior_fixture <- function() {
  structure(
    list(
      name = "external-fit-test",
      reference_posterior_name = NULL,
      dimensions = list(A = 4L)
    ),
    class = "pdb_posterior"
  )
}

checked_import_fixture <- function(seed) {
  set.seed(seed)
  values <- array(
    stats::rnorm(2500L * 4L * 2L),
    dim = c(2500L, 4L, 2L),
    dimnames = list(NULL, NULL, c("alpha", "beta"))
  )
  draws <- posterior::as_draws_list(posterior::as_draws_array(values))
  summaries <- posterior::summarise_draws(draws)
  diagnostics <- list(
    ndraws = 10000L,
    nchains = 4L,
    effective_sample_size_bulk = stats::setNames(
      summaries$ess_bulk,
      summaries$variable
    ),
    effective_sample_size_tail = stats::setNames(
      summaries$ess_tail,
      summaries$variable
    ),
    r_hat = stats::setNames(summaries$rhat, summaries$variable),
    mean_lag1_ac = posteriordb:::mean_lag1_ac(draws),
    divergent_transitions = rep(0, 4L),
    expected_fraction_of_missing_information = rep(1, 4L)
  )
  draw_info <- as.reference_posterior_info(list(
    name = "external-import-round-trip",
    inference = list(method = "stan_sampling", method_arguments = list()),
    diagnostics = diagnostics,
    checks_made = NULL,
    comments = "Synthetic writer test",
    added_by = "testthat",
    added_date = Sys.Date(),
    versions = NULL
  ))
  check_reference_posterior_draws(
    as.reference_posterior_draws(draws, info = draw_info)
  )
}

cmdstanr_fit_fixture <- function(iterations = 40L, chains = 2L) {
  testthat::skip_if_not_installed("cmdstanr")
  set.seed(2026)
  draws <- array(
    rnorm(iterations * chains * 2L),
    dim = c(iterations, chains, 2L),
    dimnames = list(
      iteration = as.character(seq_len(iterations)),
      chain = as.character(seq_len(chains)),
      variable = c("alpha", "undeclared")
    )
  )
  sampler <- array(
    0,
    dim = c(iterations, chains, 3L),
    dimnames = list(
      iteration = as.character(seq_len(iterations)),
      chain = as.character(seq_len(chains)),
      variable = c("divergent__", "treedepth__", "energy__")
    )
  )
  sampler[,, "treedepth__"] <- 3
  sampler[,, "energy__"] <- abs(rnorm(iterations * chains, 10, 1))
  fit <- new.env(parent = emptyenv())
  fit$draws <- function(inc_warmup = FALSE, format = "draws_array", ...) {
    posterior::as_draws_array(draws)
  }
  fit$unconstrain_draws <- function(
    variables = NULL,
    format = "draws_array",
    ...
  ) {
    unconstrained <- posterior::as_draws_array(draws)
    if (!is.null(variables)) {
      unconstrained <- posterior::subset_draws(
        unconstrained,
        variable = variables,
        regex = FALSE
      )
    }
    unconstrained
  }
  fit$variable_skeleton <- function(
    transformed_parameters = TRUE,
    generated_quantities = TRUE
  ) {
    list(alpha = 0, undeclared = 0)
  }
  fit$sampler_diagnostics <- function(
    inc_warmup = FALSE,
    format = "draws_array",
    ...
  ) {
    posterior::as_draws_array(sampler)
  }
  fit$metadata <- function() {
    list(
      num_chains = chains,
      iter_sampling = iterations,
      iter_warmup = 10L,
      thin = 1L,
      model_name = "cmdstanr-fixture",
      max_depth = 10L,
      stan_version_major = 2L,
      stan_version_minor = 37L,
      stan_version_patch = 0L
    )
  }
  class(fit) <- c("CmdStanMCMC", "CmdStanFit", "R6")
  fit
}
