context("test-import-external-stanfit")

empty_local_pdb <- function() {
  root <- file.path(tempdir(), paste0("posteriordb-import-", as.integer(Sys.time()), "-", sample.int(1e6, 1)))
  dir.create(file.path(root, "data"), recursive = TRUE)
  dir.create(file.path(root, "models"), recursive = TRUE)
  dir.create(file.path(root, "posteriors"), recursive = TRUE)
  pdb_local(root)
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
    "missing declared posterior variables"
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

test_that("the transactional writer round trips checked draws and honors overwrite", {
  skip_if_not(nzchar(Sys.getenv("PDB_PATH")), "requires the PosteriorDB fixture")
  source_draws <- reference_posterior_draws(
    "eight_schools-eight_schools_noncentered",
    pdb_local()
  )
  draw_info <- info(source_draws)
  draw_info$name <- "external-import-round-trip"
  info(source_draws) <- draw_info
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
  expect_silent(posteriordb:::write_imported_reference_posterior_draws(
    source_draws,
    pdb = pdb,
    overwrite = TRUE
  ))

  round_trip <- posteriordb:::read_reference_posterior_draws(
    "external-import-round-trip",
    pdb = pdb
  )
  expect_equal(posterior::variables(round_trip), posterior::variables(source_draws))
  expect_equal(posterior::ndraws(round_trip), posterior::ndraws(source_draws))
  expect_equal(posterior::nchains(round_trip), posterior::nchains(source_draws))
  expect_silent(check_reference_posterior_draws(round_trip))
})
