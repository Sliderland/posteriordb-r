summary_validation_info <- function() {
  as.reference_posterior_info(list(name = "summary-fixture",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = NULL, checks_made = NULL, comments = NULL,
    added_by = "test", added_date = Sys.Date(), versions = NULL))
}

test_that("summary construction validates named fields independently of order", {
  metadata <- summary_validation_info()
  for (type in c("mean_value", "mean_squared_value")) {
    for (count in c(1L, 2L)) {
      payload <- stats::setNames(list(paste0("theta", seq_len(count)),
        seq_len(count), rep(.1, count)), c("names", type, "mcse_mean"))
      result <- reference_posterior_summary_statistic(payload[c(3L, 2L, 1L)], metadata, type)
      expect_identical(result$names, payload$names)
      expect_identical(result[[type]], payload[[type]])
      expect_identical(result$mcse_mean, payload$mcse_mean)
    }
    # Preserve the existing numeric missing/nonfinite-value contract.
    result <- reference_posterior_summary_statistic(stats::setNames(
      list(c("a", "b"), c(NA_real_, Inf), c(NA_real_, Inf)),
      c("names", type, "mcse_mean")), metadata, type)
    expect_equal(result[[type]], c(NA_real_, Inf))
  }
})

test_that("malformed summary columns and metadata fail before writing", {
  root <- tempfile("summary-validation-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root), class = c("pdb_local", "pdb"))
  metadata <- summary_validation_info()
  for (type in c("mean_value", "mean_squared_value")) {
    payload <- stats::setNames(list(c("a", "b"), c(1, 2), c(.1, .2)),
      c("names", type, "mcse_mean"))
    object <- reference_posterior_summary_statistic(payload, metadata, type)
    for (field in c(type, "mcse_mean")) {
      malformed <- payload
      malformed[[field]] <- 1
      expect_error(reference_posterior_summary_statistic(malformed, metadata, type), "length")
      malformed <- object
      malformed[[field]] <- 1
      expect_error(write_pdb(malformed, connection), "length")
    }
    for (names in list(c("a", "a"), c("a", NA_character_))) {
      malformed <- payload
      malformed$names <- names
      expect_error(reference_posterior_summary_statistic(malformed, metadata, type), "duplicated values|missing values")
    }
    malformed <- object
    invalid_info <- metadata
    invalid_info$added_by <- NULL
    info(malformed) <- invalid_info
    expect_error(write_pdb(malformed, connection), "added_by|names")
  }
  expect_identical(list.files(root, recursive = TRUE, all.files = TRUE), character())
})

test_that("reordered summary and metadata JSON round trip by field identity", {
  root <- tempfile("summary-json-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  connection <- structure(list(pdb_local_endpoint = root, cache_path = root),
    class = c("pdb_local", "pdb"))
  fields <- unclass(summary_validation_info())
  metadata <- as.reference_posterior_info(fields[rev(seq_along(fields))])
  for (type in c("mean_value", "mean_squared_value")) {
    write_pdb(metadata, connection, type = type)
    directory <- file.path(root, "reference_posteriors/summary_statistics", type, type)
    dir.create(directory, recursive = TRUE)
    payload <- stats::setNames(list(c(.1, .2), c(1, 2), c("a", "b")),
      c("mcse_mean", type, "names"))
    jsonlite::write_json(payload, file.path(directory, paste0(metadata$name, ".json")), auto_unbox = TRUE)
    result <- reference_posterior_summary_statistic(metadata, connection, type = type)
    expect_identical(result$names, payload$names)
    expect_equal(result[[type]], payload[[type]])
    expect_equal(result$mcse_mean, payload$mcse_mean)
    expect_identical(info(result), metadata)
  }
  expect_error(as.reference_posterior_info(fields[-1L]), "names")
  expect_error(as.reference_posterior_info(c(fields, list(unknown = NULL))), "names")
})
