context("test-import-external-stanfit")

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
  jsonlite::write_json(list(
    name = "external-data",
    data_file = "data/data/external-data.json",
    title = "External test data",
    added_by = "testthat",
    added_date = as.character(Sys.Date())
  ), file.path(root, "data", "info", "external-data.info.json"),
  auto_unbox = TRUE, null = "null")
  jsonlite::write_json(list(
    name = "external-model",
    model_implementations = list(stan = list(
      model_code = "models/stan/external-model.stan"
    )),
    title = "External test model",
    added_by = "testthat",
    added_date = as.character(Sys.Date())
  ), file.path(root, "models", "info", "external-model.info.json"),
  auto_unbox = TRUE, null = "null")
  jsonlite::write_json(list(
    name = "external-data-external-model",
    model_name = "external-model",
    data_name = "external-data",
    reference_posterior_name = NULL,
    dimensions = list(alpha = 1L, beta = 1L),
    added_by = "testthat",
    added_date = as.character(Sys.Date())
  ), file.path(root, "posteriors", "external-data-external-model.json"),
  auto_unbox = TRUE, null = "null")
  pdb
}

external_fit_fixture <- local({
  fit <- NULL
  function() {
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
      dimensions = list(A = c(2, 2))
    ),
    class = "pdb_posterior"
  )
}

test_that("an externally sampled stanfit is filtered to declared scalar variables", {
  fit <- external_fit_fixture()
  po <- external_posterior_fixture()
  rpd <- as_reference_posterior_draws(
    fit,
    po,
    pdb = empty_local_pdb()
  )

  expect_s3_class(rpd, "pdb_reference_posterior_draws")
  expect_equal(
    posterior::variables(rpd),
    c("A[1,1]", "A[2,1]", "A[1,2]", "A[2,2]")
  )
  expect_false(any(c(
    "lp__", "accept_stat__", "stepsize__", "treedepth__", "n_leapfrog__",
    "divergent__", "energy__"
  ) %in% posterior::variables(rpd)))
  expect_equal(posterior::ndraws(rpd), 20)
  expect_equal(posterior::nchains(rpd), 2)
  expect_equal(info(rpd)$inference$method_arguments$warmup, 10)
  expect_equal(info(rpd)$inference$method_arguments$iter, 20)
})

test_that("matrix dimensions are explicit and missing declarations fail", {
  fit <- external_fit_fixture()
  po <- external_posterior_fixture()
  no_dimensions <- po
  no_dimensions$dimensions <- NULL
  expect_error(
    as_reference_posterior_draws(
      fit,
      no_dimensions,
      pdb = empty_local_pdb()
    ),
    "supply `dimensions` explicitly"
  )
  expect_error(
    as_reference_posterior_draws_from_stanfit(
      fit,
      po,
      pdb = empty_local_pdb(),
      dimensions = list(A = c(2, 2), missing = 1)
    ),
    "disagree with the posterior's declared dimensions"
  )
  expect_error(
    as_reference_posterior_draws(
      fit,
      po,
      pdb = empty_local_pdb(),
      dimensions = list(declared = integer())
    ),
    "disagree with the posterior's declared dimensions"
  )
})

test_that("unsupported import options are rejected before conversion", {
  fit <- external_fit_fixture()
  po <- external_posterior_fixture()
  pdb <- empty_local_pdb()
  expect_error(
    as_reference_posterior_draws(fit, po, pdb = pdb, policy = list(min_ess = 100)),
    "Custom diagnostic policies are not implemented"
  )
  expect_error(
    as_reference_posterior_draws(fit, po, pdb = pdb, commments = "typo"),
    "accepts only named"
  )
  expect_error(
    as_reference_posterior_draws(fit, po, pdb = pdb, sampling_timestamp = c("a", "b")),
    "length 1"
  )
})

test_that("sampler metadata and diagnostics are retained", {
  fit <- external_fit_fixture()
  rpd <- as_reference_posterior_draws_from_stanfit(
    fit,
    external_posterior_fixture(),
    pdb = empty_local_pdb()
  )
  metadata <- attr(rpd, "sampling_metadata")
  expect_equal(metadata$chains, 2)
  expect_equal(metadata$retained_iterations, 10)
  expect_equal(metadata$warmup, 10)
  expect_true(length(metadata$sampler_arguments) == 2)
  expect_true(all(c(
    "r_hat", "effective_sample_size_bulk", "effective_sample_size_tail",
    "mean_lag1_ac", "divergent_transitions",
    "expected_fraction_of_missing_information"
  ) %in% names(info(rpd)$diagnostics)))
})

test_that("unsupported fit objects fail clearly", {
  expect_error(
    as_reference_posterior_draws_from_stanfit(
      list(),
      external_posterior_fixture(),
      pdb = empty_local_pdb()
    ),
    "Unsupported Stan fit object"
  )
})

test_that("failed checks do not write partial reference-posterior files", {
  fit <- external_fit_fixture()
  pdb <- empty_local_pdb()
  rpd <- import_reference_posterior_draws(
    fit,
    external_posterior_fixture(),
    pdb = pdb,
    write = FALSE
  )
  expect_true("check_failed" %in% names(info(rpd)$checks_made))
  expect_error(
    import_reference_posterior_draws(
      fit,
      external_posterior_fixture(),
      pdb = pdb,
      write = TRUE
    ),
    "checks failed"
  )
  expect_false(dir.exists(file.path(pdb$pdb_local_endpoint, "reference_posteriors")))
})

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
    effective_sample_size_bulk = stats::setNames(summaries$ess_bulk, summaries$variable),
    effective_sample_size_tail = stats::setNames(summaries$ess_tail, summaries$variable),
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

test_that("the transactional writer round trips checked draws and refreshes the cache", {
  source_draws <- checked_import_fixture(123)
  pdb <- empty_local_pdb()

  expect_silent(posteriordb:::write_imported_reference_posterior_draws(
    source_draws,
    pdb = pdb,
    overwrite = FALSE
  ))
  expect_error(
    posteriordb:::write_imported_reference_posterior_draws(
      source_draws,
      pdb = pdb,
      overwrite = FALSE
    ),
    "already exist"
  )
  old_round_trip <- posteriordb:::read_reference_posterior_draws(
    "external-import-round-trip", pdb = pdb
  )
  replacement <- checked_import_fixture(456)
  expect_silent(posteriordb:::write_imported_reference_posterior_draws(
    replacement,
    pdb = pdb,
    overwrite = TRUE
  ))

  round_trip <- posteriordb:::read_reference_posterior_draws(
    "external-import-round-trip",
    pdb = pdb
  )
  expect_equal(posterior::variables(round_trip), posterior::variables(replacement))
  expect_equal(posterior::ndraws(round_trip), posterior::ndraws(replacement))
  expect_equal(posterior::nchains(round_trip), posterior::nchains(replacement))
  expect_false(identical(as.numeric(round_trip[[1L]]$alpha),
                         as.numeric(old_round_trip[[1L]]$alpha)))
  expect_equal(as.numeric(round_trip[[1L]]$alpha),
               as.numeric(replacement[[1L]]$alpha))
  expect_silent(check_reference_posterior_draws(round_trip))
})

test_that("public import links new reference draws to the existing posterior", {
  pdb <- linked_local_pdb()
  posterior_name <- "external-data-external-model"
  expect_null(posterior(posterior_name, pdb)$reference_posterior_name)
  source_draws <- checked_import_fixture(123)
  testthat::local_mocked_bindings(
    as_reference_posterior_draws = function(...) source_draws,
    .package = "posteriordb"
  )
  expect_silent(import_reference_posterior_draws(
    fit = NULL, posterior = posterior_name, pdb = pdb, write = TRUE
  ))
  linked <- posterior(posterior_name, pdb)
  expect_identical(linked$reference_posterior_name, "external-import-round-trip")
  expect_equal(
    as.numeric(reference_posterior_draws(linked)[[1L]]$alpha),
    as.numeric(source_draws[[1L]]$alpha)
  )
  expect_silent(posteriordb:::check_pdb_all_reference_posteriors_have_posterior(pdb))
})

test_that("a failed final verification restores both existing files", {
  source_draws <- checked_import_fixture(123)
  pdb <- empty_local_pdb()
  posteriordb:::write_imported_reference_posterior_draws(
    source_draws, pdb = pdb, overwrite = FALSE
  )
  info_file <- file.path(pdb$pdb_local_endpoint, "reference_posteriors", "draws",
                         "info", "external-import-round-trip.info.json")
  draw_file <- file.path(pdb$pdb_local_endpoint, "reference_posteriors", "draws",
                         "draws", "external-import-round-trip.json.zip")
  original_info <- readBin(info_file, "raw", n = file.info(info_file)$size)
  original_draws <- readBin(draw_file, "raw", n = file.info(draw_file)$size)
  original_verifier <- posteriordb:::verify_imported_reference_posterior
  testthat::local_mocked_bindings(
    verify_imported_reference_posterior = function(pdb, expected, fresh_cache = FALSE) {
      if (fresh_cache) stop("injected final verification failure")
      original_verifier(pdb, expected, fresh_cache = fresh_cache)
    },
    .package = "posteriordb"
  )
  expect_error(
    posteriordb:::write_imported_reference_posterior_draws(
      checked_import_fixture(456), pdb = pdb, overwrite = TRUE
    ),
    "injected final verification failure"
  )
  expect_identical(readBin(info_file, "raw", n = file.info(info_file)$size), original_info)
  expect_identical(readBin(draw_file, "raw", n = file.info(draw_file)$size), original_draws)
})

test_that("a failed linked import restores the posterior record", {
  pdb <- linked_local_pdb()
  source_draws <- checked_import_fixture(123)
  post_name <- "external-data-external-model"
  original_posterior <- posterior(post_name, pdb)
  post_file <- file.path(pdb$pdb_local_endpoint, "posteriors",
                         paste0(post_name, ".json"))
  original_record <- readBin(post_file, "raw", n = file.info(post_file)$size)
  posteriordb:::write_imported_reference_posterior_draws(
    source_draws, pdb = pdb, overwrite = FALSE
  )
  original_verifier <- posteriordb:::verify_imported_reference_posterior
  testthat::local_mocked_bindings(
    verify_imported_reference_posterior = function(pdb, expected, fresh_cache = FALSE) {
      if (fresh_cache) stop("injected final verification failure")
      original_verifier(pdb, expected, fresh_cache = fresh_cache)
    },
    .package = "posteriordb"
  )
  expect_error(
    posteriordb:::write_imported_reference_posterior_draws(
      source_draws, pdb = pdb, overwrite = TRUE,
      linked_posterior = original_posterior
    ),
    "injected final verification failure"
  )
  expect_identical(readBin(post_file, "raw", n = file.info(post_file)$size),
                   original_record)
  expect_null(jsonlite::read_json(post_file)$reference_posterior_name)
})
