test_that("an externally sampled stanfit retains all essential parameter variables", {
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
    c("A[1,1]", "A[2,1]", "A[1,2]", "A[2,2]", "declared", "undeclared")
  )
  expect_false(any(
    c(
      "lp__",
      "accept_stat__",
      "stepsize__",
      "treedepth__",
      "n_leapfrog__",
      "divergent__",
      "energy__"
    ) %in%
      posterior::variables(rpd)
  ))
  expected <- posterior::subset_draws(
    posterior::as_draws_array(fit),
    variable = posterior::variables(rpd),
    regex = FALSE
  )
  expect_equal(posterior::as_draws_array(rpd), expected)
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
    as_reference_posterior_draws(
      fit,
      po,
      pdb = empty_local_pdb(),
      dimensions = list(A = 4L, missing = 1L)
    ),
    "disagree with the posterior's declared dimensions"
  )
  expect_error(
    as_reference_posterior_draws(
      fit,
      po,
      pdb = empty_local_pdb(),
      dimensions = list(declared = 1L)
    ),
    "disagree with the posterior's declared dimensions"
  )
})

test_that("unsupported import options are rejected before conversion", {
  fit <- structure(list(), class = "stanfit")
  po <- external_posterior_fixture()
  pdb <- empty_local_pdb()
  testthat::local_mocked_bindings(
    extract_external_stan_fit = function(...) stop("conversion ran"),
    .package = "posteriordb"
  )
  expect_error(
    as_reference_posterior_draws(fit, po, pdb = pdb, commments = "typo"),
    "accepts only named"
  )
  expect_error(
    as_reference_posterior_draws(
      fit,
      po,
      pdb = pdb,
      sampling_timestamp = c("a", "b")
    ),
    "length 1"
  )
})

test_that("sampler metadata and diagnostics are retained", {
  fit <- external_fit_fixture()
  rpd <- as_reference_posterior_draws(
    fit,
    external_posterior_fixture(),
    pdb = empty_local_pdb()
  )
  metadata <- attr(rpd, "sampling_metadata")
  expect_equal(metadata$chains, 2)
  expect_equal(metadata$retained_iterations, 10)
  expect_equal(metadata$warmup, 10)
  expect_true(is.list(metadata$sampler_arguments))
  expect_false("chain_id" %in% names(metadata$sampler_arguments))
  expect_true(all(
    c(
      "r_hat",
      "effective_sample_size_bulk",
      "effective_sample_size_tail",
      "mean_lag1_ac",
      "divergent_transitions",
      "expected_fraction_of_missing_information"
    ) %in%
      names(info(rpd)$diagnostics)
  ))
  expect_equal(
    info(rpd)$diagnostics$expected_fraction_of_missing_information,
    rstan::get_bfmi(fit)
  )
  sampler <- rstan::get_sampler_params(fit, inc_warmup = FALSE)
  expect_equal(
    info(rpd)$diagnostics$divergent_transitions,
    vapply(sampler, function(chain) sum(chain[, "divergent__"]), numeric(1))
  )
})

test_that("unsupported fit objects fail clearly", {
  expect_error(
    as_reference_posterior_draws(
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
  expect_false(dir.exists(file.path(
    pdb$pdb_local_endpoint,
    "reference_posteriors"
  )))
})

test_that("the transactional writer round trips checked draws and refreshes the cache", {
  source_draws <- checked_import_fixture(123)
  pdb <- linked_local_pdb()
  linked <- posterior("external-data-external-model", pdb)

  expect_silent(posteriordb:::write_imported_reference_posterior_draws(
    source_draws,
    pdb = pdb,
    overwrite = FALSE,
    linked_posterior = linked
  ))
  expect_error(
    posteriordb:::write_imported_reference_posterior_draws(
      source_draws,
      pdb = pdb,
      overwrite = FALSE,
      linked_posterior = posterior("external-data-external-model", pdb)
    ),
    "already exist"
  )
  old_round_trip <- posteriordb:::read_reference_posterior_draws(
    "external-import-round-trip",
    pdb = pdb
  )
  replacement <- checked_import_fixture(456)
  expect_silent(posteriordb:::write_imported_reference_posterior_draws(
    replacement,
    pdb = pdb,
    overwrite = TRUE,
    linked_posterior = posterior("external-data-external-model", pdb)
  ))

  round_trip <- posteriordb:::read_reference_posterior_draws(
    "external-import-round-trip",
    pdb = pdb
  )
  expect_equal(
    posterior::variables(round_trip),
    posterior::variables(replacement)
  )
  expect_equal(posterior::ndraws(round_trip), posterior::ndraws(replacement))
  expect_equal(posterior::nchains(round_trip), posterior::nchains(replacement))
  expect_false(identical(
    as.numeric(round_trip[[1L]]$alpha),
    as.numeric(old_round_trip[[1L]]$alpha)
  ))
  expect_equal(
    as.numeric(round_trip[[1L]]$alpha),
    as.numeric(replacement[[1L]]$alpha)
  )
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
  # A supplied object must carry the saved posterior's dimension counts.
  stale <- posterior(posterior_name, pdb)
  stale$dimensions <- lapply(stale$dimensions, function(count) count + 1L)
  expect_error(
    import_reference_posterior_draws(
      fit = NULL,
      posterior = stale,
      pdb = pdb,
      write = TRUE
    ),
    "do not match the target database"
  )
  expect_null(posterior(posterior_name, pdb)$reference_posterior_name)
  expect_silent(import_reference_posterior_draws(
    fit = NULL,
    posterior = posterior_name,
    pdb = pdb,
    write = TRUE
  ))
  linked <- posterior(posterior_name, pdb)
  expect_identical(
    linked$reference_posterior_name,
    "external-import-round-trip"
  )
  expect_equal(
    as.numeric(reference_posterior_draws(linked)[[1L]]$alpha),
    as.numeric(source_draws[[1L]]$alpha)
  )
  expect_silent(posteriordb:::check_pdb_all_reference_posteriors_have_posterior(
    pdb
  ))
})

test_that("a failed final verification restores both existing files", {
  source_draws <- checked_import_fixture(123)
  pdb <- linked_local_pdb()
  posteriordb:::write_imported_reference_posterior_draws(
    source_draws,
    pdb = pdb,
    overwrite = FALSE,
    linked_posterior = posterior("external-data-external-model", pdb)
  )
  info_file <- file.path(
    pdb$pdb_local_endpoint,
    "reference_posteriors",
    "draws",
    "info",
    "external-import-round-trip.info.json"
  )
  draw_file <- file.path(
    pdb$pdb_local_endpoint,
    "reference_posteriors",
    "draws",
    "draws",
    "external-import-round-trip.json.zip"
  )
  original_info <- readBin(info_file, "raw", n = file.info(info_file)$size)
  original_draws <- readBin(draw_file, "raw", n = file.info(draw_file)$size)
  files <- posteriordb:::pdb_reference_output_paths(
    pdb,
    info(source_draws)$name,
    posteriordb:::supported_summary_statistic_types()
  )
  original_files <- lapply(files, function(path) {
    readBin(path, "raw", n = file.info(path)$size)
  })
  original_verifier <- posteriordb:::verify_imported_reference_posterior
  testthat::local_mocked_bindings(
    verify_imported_reference_posterior = function(
      pdb,
      expected,
      fresh_cache = FALSE
    ) {
      if (fresh_cache) {
        stop("injected final verification failure")
      }
      original_verifier(pdb, expected, fresh_cache = fresh_cache)
    },
    .package = "posteriordb"
  )
  expect_error(
    posteriordb:::write_imported_reference_posterior_draws(
      checked_import_fixture(456),
      pdb = pdb,
      overwrite = TRUE,
      linked_posterior = posterior("external-data-external-model", pdb)
    ),
    "injected final verification failure"
  )
  expect_identical(
    readBin(info_file, "raw", n = file.info(info_file)$size),
    original_info
  )
  expect_identical(
    readBin(draw_file, "raw", n = file.info(draw_file)$size),
    original_draws
  )
  expect_identical(
    lapply(files, function(path) {
      readBin(path, "raw", n = file.info(path)$size)
    }),
    original_files
  )
})

test_that("a failed linked import restores the posterior record", {
  pdb <- linked_local_pdb()
  source_draws <- checked_import_fixture(123)
  post_name <- "external-data-external-model"
  original_posterior <- posterior(post_name, pdb)
  post_file <- file.path(
    pdb$pdb_local_endpoint,
    "posteriors",
    paste0(post_name, ".json")
  )
  original_record <- readBin(post_file, "raw", n = file.info(post_file)$size)
  original_verifier <- posteriordb:::verify_imported_reference_posterior
  testthat::local_mocked_bindings(
    verify_imported_reference_posterior = function(
      pdb,
      expected,
      fresh_cache = FALSE
    ) {
      if (fresh_cache) {
        stop("injected final verification failure")
      }
      original_verifier(pdb, expected, fresh_cache = fresh_cache)
    },
    .package = "posteriordb"
  )
  expect_error(
    posteriordb:::write_imported_reference_posterior_draws(
      source_draws,
      pdb = pdb,
      overwrite = TRUE,
      linked_posterior = original_posterior
    ),
    "injected final verification failure"
  )
  expect_identical(
    readBin(post_file, "raw", n = file.info(post_file)$size),
    original_record
  )
  expect_length(
    list.files(
      file.path(pdb$pdb_local_endpoint, "reference_posteriors"),
      recursive = TRUE,
      all.files = TRUE
    ),
    0L
  )
  expect_null(jsonlite::read_json(post_file)$reference_posterior_name)
})

test_that("incomplete import rollback reports installed and backup paths", {
  actual_rename <- base::file.rename
  actual_unlink <- base::unlink
  run_case <- function(warn) {
    withr::local_options(warn = warn)
    pdb <- linked_local_pdb()
    withr::defer(unlink(pdb$pdb_local_endpoint, recursive = TRUE))
    source_draws <- checked_import_fixture(123)
    posteriordb:::write_imported_reference_posterior_draws(
      source_draws,
      pdb,
      overwrite = FALSE,
      linked_posterior = posterior("external-data-external-model", pdb),
      write_summary_statistics = FALSE
    )
    original <- file.path(
      pdb$pdb_local_endpoint,
      "reference_posteriors/draws/info",
      "external-import-round-trip.info.json"
    )
    original_bytes <- readBin(original, "raw", n = file.info(original)$size)
    draw_file <- file.path(
      pdb$pdb_local_endpoint,
      "reference_posteriors/draws/draws",
      "external-import-round-trip.json.zip"
    )
    original_draws <- readBin(draw_file, "raw", n = file.info(draw_file)$size)
    testthat::local_mocked_bindings(
      file.rename = function(from, to) {
        if (
          grepl(".import-backup-", from, fixed = TRUE) &&
            identical(to, original)
        ) {
          return(FALSE)
        }
        actual_rename(from, to)
      },
      unlink = function(x, ...) {
        if (identical(x, original)) {
          return(1L)
        }
        actual_unlink(x, ...)
      },
      .package = "base"
    )
    original_verifier <- posteriordb:::verify_imported_reference_posterior
    testthat::local_mocked_bindings(
      verify_imported_reference_posterior = function(
        pdb,
        expected,
        fresh_cache = FALSE
      ) {
        if (fresh_cache) {
          stop("injected verification failure")
        }
        original_verifier(pdb, expected, fresh_cache)
      },
      .package = "posteriordb"
    )
    warnings <- character()
    operation <- function() {
      tryCatch(
        posteriordb:::write_imported_reference_posterior_draws(
          checked_import_fixture(456),
          pdb,
          overwrite = TRUE,
          linked_posterior = posterior("external-data-external-model", pdb),
          write_summary_statistics = FALSE
        ),
        error = identity
      )
    }
    error <- if (warn == 2) {
      operation()
    } else {
      withCallingHandlers(operation(), warning = function(warning) {
        warnings <<- c(warnings, conditionMessage(warning))
        invokeRestart("muffleWarning")
      })
    }
    if (warn == 2) {
      warnings <- conditionMessage(error)
    }
    expect_match(
      conditionMessage(error),
      if (warn == 2) {
        "Could not remove installed"
      } else {
        "injected verification failure"
      }
    )
    backup <- list.files(
      dirname(original),
      full.names = TRUE,
      pattern = "[.]import-backup-"
    )
    expect_length(backup, 1L)
    expect_true(any(grepl(
      "Could not remove installed",
      warnings,
      fixed = TRUE
    )))
    expect_true(any(grepl(original, warnings, fixed = TRUE)))
    expect_true(any(grepl(backup, warnings, fixed = TRUE)))
    expect_identical(
      readBin(backup, "raw", n = file.info(backup)$size),
      original_bytes
    )
    expect_true(file.exists(original))
    expect_identical(
      readBin(draw_file, "raw", n = file.info(draw_file)$size),
      original_draws
    )
  }
  for (warn in c(0, 2)) {
    run_case(warn)
  }
})

test_that("CmdStanR-like MCMC methods retain import metadata", {
  skip_if_not_installed("cmdstanr")
  fit <- cmdstanr_fit_fixture()
  posterior <- external_posterior_fixture()
  posterior$dimensions <- list(alpha = 1L)
  rpd <- as_reference_posterior_draws(
    fit,
    posterior,
    pdb = empty_local_pdb()
  )
  expect_s3_class(rpd, "pdb_reference_posterior_draws")
  expect_equal(posterior::variables(rpd), c("alpha", "undeclared"))
  expect_equal(info(rpd)$inference$method_arguments$iter, 50L)
  expect_equal(info(rpd)$inference$method_arguments$warmup, 10L)
  expect_true(
    "expected_fraction_of_missing_information" %in%
      names(info(rpd)$diagnostics)
  )
  expect_match(info(rpd)$comments, "cmdstanr::CmdStanMCMC")
  expect_equal(
    attr(rpd, "sampling_metadata")$cmdstanr_version,
    paste("cmdstanr", utils::packageVersion("cmdstanr"))
  )
})

test_that("a valid external fit passes import acceptance and can be written", {
  # The existing fit fixture fixes its seed internally.
  fit <- cmdstanr_fit_fixture(iterations = 2500L, chains = 4L)
  fit$variable_skeleton <- function(...) list(alpha = 0, beta = 0)
  rename_draws <- function(draws) {
    posterior::rename_variables(draws, beta = "undeclared")
  }
  original_draws <- fit$draws
  original_unconstrained <- fit$unconstrain_draws
  fit$draws <- function(...) rename_draws(original_draws(...))
  fit$unconstrain_draws <- function(...) {
    rename_draws(original_unconstrained(...))
  }
  pdb <- linked_local_pdb()
  imported <- import_reference_posterior_draws(
    fit,
    "external-data-external-model",
    pdb,
    write = TRUE
  )
  expect_null(info(imported)$checks_made$check_failed)
  expect_silent(assert_checked_reference_posterior_draws(imported))
  saved <- reference_posterior_draws(
    posterior("external-data-external-model", pdb)
  )
  expect_equal(posterior::as_draws_array(saved), fit$draws())
})

test_that("CmdStan parameter schema protects saved zero-free-coordinate values", {
  fit <- cmdstanr_fit_fixture()
  original_draws <- fit$draws
  fit$draws <- function(...) {
    draws <- original_draws(...)
    posterior::bind_draws(
      draws,
      posterior::as_draws_array(array(
        1,
        c(40, 2, 1),
        dimnames = list(NULL, NULL, "fixed[1]")
      )),
      along = "variable"
    )
  }
  fit$variable_skeleton <- function(...) {
    list(alpha = 0, undeclared = 0, fixed = 1)
  }
  object <- structure(
    list(
      name = "zero-free-posterior",
      reference_posterior_name = NULL,
      dimensions = list(alpha = 1L)
    ),
    class = "pdb_posterior"
  )
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  imported <- as_reference_posterior_draws(
    fit,
    object,
    connection,
    include = "alpha"
  )
  expect_true("fixed[1]" %in% posterior::variables(imported))
  expect_true(is.na(info(imported)$diagnostics$mean_lag1_ac[["fixed[1]"]]))
  expect_true(nzchar(info(imported)$checks_made$check_failed))
  expect_error(
    as_reference_posterior_draws(fit, object, connection, exclude = "fixed"),
    "Cannot exclude required"
  )
})

test_that("public import shares aliases, protects dimensions, and rejects conflicts", {
  fit <- cmdstanr_fit_fixture()
  original_draws <- fit$draws
  fit$draws <- function(...) {
    draws <- original_draws(...)
    extras <- posterior::as_draws_array(array(
      rnorm(160),
      c(40, 2, 2),
      dimnames = list(NULL, NULL, c("dimension_output", "derived"))
    ))
    posterior::bind_draws(draws, extras, along = "variable")
  }
  object <- structure(
    list(
      name = "selection-posterior",
      reference_posterior_name = NULL,
      dimensions = list(alpha = 1L, dimension_output = 1L)
    ),
    class = "pdb_posterior"
  )
  connection <- structure(list(), class = c("pdb_local", "pdb"))
  all_names <- c("alpha", "undeclared", "dimension_output", "derived")
  required <- all_names[1:3]
  expect_identical(
    posterior::variables(as_reference_posterior_draws(fit, object, connection)),
    all_names
  )
  for (include in list(NULL, "all", "derived", "none", character())) {
    minimal <- as_reference_posterior_draws(
      fit,
      object,
      connection,
      include = include,
      exclude = "all"
    )
    expect_identical(posterior::variables(minimal), required)
    expect_named(info(minimal)$diagnostics$r_hat, required)
  }
  for (include in list("none", character())) {
    minimal <- as_reference_posterior_draws(
      fit,
      object,
      connection,
      include = include
    )
    expect_identical(posterior::variables(minimal), required)
    expect_named(info(minimal)$diagnostics$r_hat, required)
  }
  for (exclude in list(NULL, character(), "none")) {
    full <- import_reference_posterior_draws(
      fit,
      object,
      connection,
      include = "all",
      exclude = exclude,
      write = FALSE
    )
    expect_identical(posterior::variables(full), all_names)
  }
  expect_error(
    as_reference_posterior_draws(
      fit,
      object,
      connection,
      include = "derived",
      exclude = "derived"
    ),
    "both.*include.*exclude"
  )
  expect_error(
    as_reference_posterior_draws(
      fit,
      object,
      connection,
      exclude = "dimension_output"
    ),
    "Cannot exclude required"
  )
})

test_that("fit import rejects absent declared variables and accepts supplied dimensions", {
  fit <- cmdstanr_fit_fixture()
  po <- external_posterior_fixture()
  po$dimensions <- list(alpha = 1L, missing = 1L)
  expect_error(
    as_reference_posterior_draws(fit, po, empty_local_pdb()),
    "missing declared posterior variables: missing"
  )
  po$dimensions <- NULL
  imported <- as_reference_posterior_draws(
    fit,
    po,
    empty_local_pdb(),
    dimensions = list(alpha = 1L)
  )
  expect_identical(posterior::variables(imported), c("alpha", "undeclared"))
})

test_that("fit import retains per-chain sampler results", {
  fit <- cmdstanr_fit_fixture()
  sampler <- fit$sampler_diagnostics()
  sampler[1, 1, "divergent__"] <- 1
  sampler[1:2, 2, "divergent__"] <- 1
  fit$sampler_diagnostics <- function(...) sampler
  po <- external_posterior_fixture()
  po$dimensions <- list(alpha = 1L)
  imported <- as_reference_posterior_draws(fit, po, empty_local_pdb())
  expected <- vapply(
    1:2,
    function(chain) {
      energy <- sampler[, chain, "energy__"]
      mean(diff(energy)^2) / stats::var(energy)
    },
    numeric(1)
  )
  expect_equal(
    info(imported)$diagnostics$expected_fraction_of_missing_information,
    expected
  )
  expect_equal(info(imported)$diagnostics$divergent_transitions, c(1, 2))
})
