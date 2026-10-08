bundle_integrity_pdb <- function() {
  root <- tempfile("bundle-integrity-")
  for (folder in c("data", "models", "posteriors", "alias", "cache"))
    dir.create(file.path(root, folder), recursive = TRUE)
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  pdb_local(root, cache_path = file.path(root, "cache"))
}

bundle_integrity_extraction <- function(divergence = 0L) {
  set.seed(412)
  draws <- posterior::as_draws_array(array(rnorm(10000), c(2500, 4, 1),
    dimnames = list(NULL, NULL, "theta")))
  sampler <- array(0, c(2500, 4, 2),
    dimnames = list(NULL, NULL, c("divergent__", "treedepth__")))
  sampler[1, 1, "divergent__"] <- divergence
  list(draws = draws, sampler_diagnostics = posterior::as_draws_array(sampler),
    metadata = list(expected_fraction_of_missing_information = rep(.5, 4), max_treedepth = 10),
    dimensions = list(theta = 1L),
    source = "parameters { real theta; } model { theta ~ normal(0,1); }",
    fit_class = "stanfit", import_versions = list())
}

bundle_integrity_snapshot <- function(pdb) {
  files <- list.files(pdb$pdb_local_endpoint, recursive = TRUE)
  files <- files[!grepl("^cache/", files)]
  stats::setNames(lapply(file.path(pdb$pdb_local_endpoint, files), function(path)
    readBin(path, "raw", n = file.info(path)$size)), files)
}

test_that("public bundle reuse preserves origins and rejects cross-database collisions", {
  extracted <- bundle_integrity_extraction()
  testthat::local_mocked_bindings(extract_rstan_fit_for_bundle = function(...) extracted)
  fit <- structure(list(), class = "stanfit")
  source <- bundle_integrity_pdb()
  original <- create_pdb_bundle(fit, data = list(n = 1L),
    data_info = list(name = "reuse-data", title = "Inputs"),
    model_info = list(name = "reuse-model", title = "Model"), pdb = source)
  suppressMessages(write_pdb(original, source, write_summary_statistics = FALSE))

  for (component in c("data", "model_code")) {
    destination <- bundle_integrity_pdb()
    collision <- if (component == "data") {
      as.pdb_data(list(n = 2L), info = info(original$data))
    } else {
      as.pdb_model_code(paste0(extracted$source, "\n// destination model"),
        info = info(original$model_code), framework = "stan")
    }
    write_pdb(collision, destination)
    before <- bundle_integrity_snapshot(destination)
    args <- list(fit = fit, data = list(n = 1L),
      data_info = list(name = "reuse-data", title = "Inputs"),
      model_info = list(name = "reuse-model", title = "Model"), pdb = destination)
    args[[component]] <- original[[component]]
    args[[if (component == "data") "data_info" else "model_info"]] <- NULL
    bundle <- do.call(create_pdb_bundle, args)
    expect_identical(pdb(bundle[[component]]), source)
    expect_identical(bundle_integrity_snapshot(destination), before)
    for (overwrite in c(FALSE, TRUE)) {
      expect_error(write_pdb(bundle, destination, overwrite = overwrite,
        write_summary_statistics = FALSE), "unsafe reused-object collision")
      expect_identical(bundle_integrity_snapshot(destination), before)
    }
  }

  # Genuine same-database reuse and copying into an empty database still work.
  for (destination in list(source, bundle_integrity_pdb())) {
    reused <- create_pdb_bundle(fit, posterior = posterior(original$posterior$name, source),
      pdb = destination)
    expect_identical(pdb(reused$posterior), source)
    result <- suppressMessages(write_pdb(reused, destination,
      overwrite = TRUE, write_summary_statistics = FALSE))
    expect_true(result$reference_draws_written)
    pdb_clear_cache(destination)
    stored <- posterior(original$posterior$name, destination)
    expect_identical(get_data(stored)$n, 1L)
    expect_identical(stored$reference_posterior_name, info(reused$reference_draws)$name)
    expect_equal(as.numeric(posterior::as_draws_array(reference_posterior_draws(stored))),
                 as.numeric(extracted$draws), tolerance = 1e-12)
  }
})

test_that("accepted reused posteriors fill empty links and reject different links", {
  extracted <- bundle_integrity_extraction()
  testthat::local_mocked_bindings(extract_rstan_fit_for_bundle = function(...) extracted)
  fit <- structure(list(), class = "stanfit")
  database <- bundle_integrity_pdb()
  original <- create_pdb_bundle(fit, data = list(),
    data_info = list(name = "link-data", title = "Inputs"),
    model_info = list(name = "link-model", title = "Model"), pdb = database)
  write_pdb(original$data, database)
  write_pdb(original$model_code, database)
  unlinked <- original$posterior
  unlinked["reference_posterior_name"] <- list(NULL)
  unlinked$embedded_reference_draws <- NULL
  write_pdb(unlinked, database)
  reused <- create_pdb_bundle(fit, posterior = posterior(unlinked$name, database),
    pdb = database)
  expect_true(all(unlist(reused$diagnostics$status)))
  posterior_path <- pdb_file_path(database, "posteriors", paste0(unlinked$name, ".json"))

  suppressMessages(write_pdb(reused, database, write_summary_statistics = FALSE))
  expect_identical(jsonlite::read_json(posterior_path)$reference_posterior_name,
                   info(reused$reference_draws)$name)

  for (link in list("different-reference")) {
    stored <- jsonlite::read_json(posterior_path)
    stored["reference_posterior_name"] <- list(link)
    jsonlite::write_json(stored, posterior_path, auto_unbox = TRUE, null = "null")
    before <- bundle_integrity_snapshot(database)
    for (overwrite in c(FALSE, TRUE)) {
      expect_error(write_pdb(reused, database, overwrite = overwrite,
        write_summary_statistics = FALSE), "matching persisted reference link")
      expect_identical(bundle_integrity_snapshot(database), before)
    }
  }
})

test_that("failed bundle writes omit missing reference links and preserve stored references", {
  extracted <- bundle_integrity_extraction(divergence = 1L)
  testthat::local_mocked_bindings(extract_rstan_fit_for_bundle = function(...) extracted)
  fit <- structure(list(), class = "stanfit")
  database <- bundle_integrity_pdb()
  make <- function() create_pdb_bundle(fit, data = list(),
    data_info = list(name = "failed-data", title = "Inputs"),
    model_info = list(name = "failed-model", title = "Model"), pdb = database)
  failed <- make()
  result <- suppressMessages(write_pdb(failed, database))
  expect_false(result$reference_draws_written)
  expect_setequal(result$written, c("data", "model_code", "posterior"))
  expect_length(list.files(pdb_file_path(database, "reference_posteriors"), recursive = TRUE), 0L)
  pdb_clear_cache(database)
  stored <- posterior(failed$posterior$name, database)
  expect_null(stored$reference_posterior_name)
  expect_identical(result$bundle$posterior$reference_posterior_name,
                   info(failed$reference_draws)$name)
  expect_length(get_data(stored), 0L)

  # A reused unlinked record also stays unlinked when its candidate fails.
  reused <- create_pdb_bundle(fit, posterior = stored, pdb = database)
  before <- bundle_integrity_snapshot(database)
  suppressMessages(write_pdb(reused, database))
  expect_identical(bundle_integrity_snapshot(database), before)

  extracted <- bundle_integrity_extraction()
  accepted <- make()
  suppressMessages(write_pdb(accepted, database, overwrite = TRUE,
    write_summary_statistics = FALSE))
  # Preserve even a different existing reference link when replacing a failed candidate.
  stored <- accepted$posterior
  stored$reference_posterior_name <- "older-reference"
  stored$embedded_reference_draws <- NULL
  older_draws <- accepted$reference_draws
  metadata <- info(older_draws)
  metadata$name <- "older-reference"
  info(older_draws) <- metadata
  write_pdb(metadata, database, type = "draws")
  write_json_to_path(older_draws, "reference_posteriors/draws/draws", database,
    zip = TRUE, info = FALSE)
  write_pdb(stored, database, overwrite = TRUE)
  write_pdb(older_draws, database, overwrite = TRUE, write_summary_statistics = FALSE)
  reference_before <- bundle_integrity_snapshot(database)
  reference_before <- reference_before[grepl("^reference_posteriors/", names(reference_before))]
  extracted <- bundle_integrity_extraction(divergence = 1L)
  suppressMessages(write_pdb(make(), database, overwrite = TRUE))
  pdb_clear_cache(database)
  expect_identical(posterior(stored$name, database)$reference_posterior_name, "older-reference")
  after <- bundle_integrity_snapshot(database)
  expect_identical(after[names(reference_before)], reference_before)
})

test_that("I/O failures retain completed bundle components and report partial writes", {
  extracted <- bundle_integrity_extraction()
  testthat::local_mocked_bindings(extract_rstan_fit_for_bundle = function(...) extracted)
  database <- bundle_integrity_pdb()
  bundle <- create_pdb_bundle(structure(list(), class = "stanfit"), data = list(n = 1L),
    data_info = list(name = "partial-data", title = "Inputs"),
    model_info = list(name = "partial-model", title = "Model"), pdb = database)
  original_write <- writeLines
  testthat::local_mocked_bindings(writeLines = function(text, con, ...) {
    if (grepl("partial-model[.]stan$", con)) stop("injected payload I/O failure")
    original_write(text, con, ...)
  }, .package = "base")
  messages <- character()
  error <- tryCatch(withCallingHandlers(
    write_pdb(bundle, database, write_summary_statistics = FALSE),
    message = function(message) {
      messages <<- c(messages, conditionMessage(message))
      invokeRestart("muffleMessage")
    }
  ), error = identity)
  expect_match(conditionMessage(error), "injected payload I/O failure")
  expect_true(any(grepl("Completed components: data", messages, fixed = TRUE)))
  expect_true(any(grepl("partial-model", messages, fixed = TRUE)))
  expect_true(any(grepl("retained", messages, fixed = TRUE)))
  expect_identical(get_data("partial-data", database)$n, 1L)
  expect_true(file.exists(pdb_file_path(database, "models/info/partial-model.info.json")))
  expect_false(file.exists(pdb_file_path(database, "models/stan/partial-model.stan")))
  expect_false(file.exists(pdb_file_path(database, "posteriors", paste0(bundle$posterior$name, ".json"))))
})

test_that("failed ZIP creation retains the JSON payload and is reported as failure", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(
    name = "zip-failure", title = "Inputs", added_by = "test", added_date = Sys.Date()
  )))
  testthat::local_mocked_bindings(zip = function(...) 1L, .package = "utils")
  messages <- character()
  error <- tryCatch(withCallingHandlers(write_pdb(object, database),
    message = function(message) {
      messages <<- c(messages, conditionMessage(message))
      invokeRestart("muffleMessage")
    }), error = identity)
  expect_s3_class(error, "error")
  expect_true(any(grepl("zip-failure", messages, fixed = TRUE)))
  expect_true(file.exists(pdb_file_path(database, "data/info/zip-failure.info.json")))
  expect_true(file.exists(pdb_file_path(database, "data/data/zip-failure.json")))
  expect_false(file.exists(pdb_file_path(database, "data/data/zip-failure.json.zip")))
})

test_that("failed JSON cleanup reports the saved archive and retains both files", {
  database <- bundle_integrity_pdb()
  object <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(list(
    name = "cleanup-failure", title = "Inputs", added_by = "test", added_date = Sys.Date()
  )))
  testthat::local_mocked_bindings(file.remove = function(...) FALSE, .package = "base")
  expect_error(write_pdb(object, database), "Archive written, but JSON cleanup failed")
  expect_true(file.exists(pdb_file_path(database, "data/data/cleanup-failure.json")))
  archive <- pdb_file_path(database, "data/data/cleanup-failure.json.zip")
  expect_true(file.exists(archive))
  expect_identical(utils::unzip(archive, list = TRUE)$Name, "cleanup-failure.json")
})

test_that("reference links are saved only after successful draw writes", {
  extracted <- bundle_integrity_extraction()
  testthat::local_mocked_bindings(extract_rstan_fit_for_bundle = function(...) extracted)
  database <- bundle_integrity_pdb()
  bundle <- create_pdb_bundle(structure(list(), class = "stanfit"), data = list(),
    data_info = list(name = "delayed-data", title = "Inputs"),
    model_info = list(name = "delayed-model", title = "Model"), pdb = database)
  path <- pdb_file_path(database, "posteriors", paste0(bundle$posterior$name, ".json"))
  stored_link <- function() jsonlite::read_json(path)$reference_posterior_name
  before <- bundle_integrity_snapshot(database)
  expect_error(write_pdb(bundle$reference_draws, database,
    write_summary_statistics = FALSE), "no posterior")
  expect_identical(bundle_integrity_snapshot(database), before)
  original_zip <- utils::zip
  fail_zip <- TRUE
  testthat::local_mocked_bindings(zip = function(files, ...) {
    if (fail_zip && grepl("reference_posteriors/draws/draws", files, fixed = TRUE)) return(1L)
    original_zip(files = files, ...)
  }, .package = "utils")

  expect_error(suppressMessages(write_pdb(bundle, database,
    write_summary_statistics = FALSE)), "ZIP creation failed")
  expect_null(stored_link())
  expect_error(suppressMessages(write_pdb(bundle$reference_draws, database,
    overwrite = TRUE, write_summary_statistics = FALSE)), "ZIP creation failed")
  expect_null(stored_link())

  # Populate the cache before the standalone write updates the saved link.
  expect_null(posterior(bundle$posterior$name, database)$reference_posterior_name)
  fail_zip <- FALSE
  expect_silent(write_pdb(bundle$reference_draws, database, overwrite = TRUE,
    write_summary_statistics = FALSE))
  expect_identical(stored_link(), info(bundle$reference_draws)$name)
  expect_identical(posterior(bundle$posterior$name, database)$reference_posterior_name,
                   info(bundle$reference_draws)$name)
  expect_identical(bundle$posterior$reference_posterior_name, info(bundle$reference_draws)$name)

  unlinked <- bundle$posterior
  unlinked["reference_posterior_name"] <- list(NULL)
  unlinked$embedded_reference_draws <- NULL
  write_pdb(unlinked, database, overwrite = TRUE)
  renamed <- bundle$reference_draws
  info(renamed)$name <- "distinct-reference"
  expect_silent(write_pdb(renamed, database, posterior_name = unlinked$name,
    write_summary_statistics = FALSE))
  expect_identical(stored_link(), "distinct-reference")
  before <- bundle_integrity_snapshot(database)
  expect_error(write_pdb(bundle$reference_draws, database, overwrite = TRUE,
    posterior_name = unlinked$name, write_summary_statistics = FALSE), "different existing link")
  expect_identical(bundle_integrity_snapshot(database), before)

  write_pdb(unlinked, database, overwrite = TRUE)
  testthat::local_mocked_bindings(write_pdb.pdb_reference_posterior_summary_statistic =
    function(...) stop("injected summary failure"))
  expect_error(write_pdb(bundle$reference_draws, database, overwrite = TRUE),
    "injected summary failure")
  expect_identical(stored_link(), info(bundle$reference_draws)$name)
})

test_that("bundle writes reuse and validate summaries without recomputing them", {
  extracted <- bundle_integrity_extraction()
  testthat::local_mocked_bindings(extract_rstan_fit_for_bundle = function(...) extracted)
  database <- bundle_integrity_pdb()
  bundle <- create_pdb_bundle(structure(list(), class = "stanfit"), data = list(),
    data_info = list(name = "summary-data", title = "Inputs"),
    model_info = list(name = "summary-model", title = "Model"), pdb = database)
  compute <- summary_statistics_from_checked_reference_draws
  calls <- 0L
  testthat::local_mocked_bindings(summary_statistics_from_checked_reference_draws = function(x) {
    calls <<- calls + 1L
    compute(x)
  })
  malformed <- bundle
  metadata <- info(malformed$summary_statistics$mean_value)
  metadata$name <- "wrong-reference"
  info(malformed$summary_statistics$mean_value) <- metadata
  before <- bundle_integrity_snapshot(database)
  expect_error(write_pdb(malformed, database), "info\\$name")
  expect_identical(bundle_integrity_snapshot(database), before)

  result <- suppressMessages(write_pdb(bundle, database))
  expect_true(result$summary_statistics_written)
  expect_identical(result$bundle$summary_statistics, bundle$summary_statistics)
  expect_identical(calls, 0L)
  bundle$summary_statistics <- NULL
  result <- suppressMessages(write_pdb(bundle, database, overwrite = TRUE))
  expect_true(result$summary_statistics_written)
  expect_identical(calls, 1L)
})
