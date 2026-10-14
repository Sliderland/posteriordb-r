make_rename_fixture <- function() {
  parent <- tempfile("posteriordb-rename-")
  root <- file.path(parent, "database")
  withr::defer(unlink(parent, recursive = TRUE), envir = parent.frame())
  dirs <- c(
    "data/info",
    "data/data",
    "models/info",
    "models/stan",
    "posteriors",
    "reference_posteriors/draws/info",
    "reference_posteriors/draws/draws",
    "reference_posteriors/summary_statistics/mean_value/info",
    "reference_posteriors/summary_statistics/mean_value/mean_value",
    "alias"
  )
  for (directory in dirs) {
    dir.create(file.path(root, directory), recursive = TRUE)
  }
  root <- normalizePath(root)
  write_json <- function(object, path) {
    jsonlite::write_json(object, path, pretty = TRUE, auto_unbox = TRUE)
  }
  write_zip <- function(directory, filename, contents) {
    path <- file.path(root, directory, filename)
    json_path <- sub("[.]zip$", "", path)
    writeLines(contents, json_path)
    oldwd <- setwd(dirname(path))
    on.exit(setwd(oldwd), add = TRUE)
    utils::zip(filename, basename(json_path), flags = "-jq")
    setwd(oldwd)
    unlink(json_path)
  }

  write_json(
    list(
      name = "data_old",
      title = "Data",
      added_by = "test",
      added_date = "2026-01-01",
      data_file = "data/data/data_old.json"
    ),
    file.path(root, "data/info/data_old.info.json")
  )
  write_zip("data/data", "data_old.json.zip", '{"y":[1,2]}')
  write_json(
    list(
      name = "model_old",
      title = "Model",
      added_by = "test",
      added_date = "2026-01-01",
      model_implementations = list(
        stan = list(model_code = "models/stan/model_old.stan")
      )
    ),
    file.path(root, "models/info/model_old.info.json")
  )
  writeLines("parameters {}", file.path(root, "models/stan/model_old.stan"))
  write_json(
    list(
      name = "data_old-model_old",
      model_name = "model_old",
      data_name = "data_old",
      reference_posterior_name = "data_old-model_old",
      dimensions = list(y = 2),
      added_by = "test",
      added_date = "2026-01-01"
    ),
    file.path(root, "posteriors/data_old-model_old.json")
  )
  reference_info <- list(
    name = "data_old-model_old",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = 1),
    checks_made = list(),
    comments = "test",
    added_by = "test",
    added_date = "2026-01-01",
    versions = list()
  )
  write_json(
    reference_info,
    file.path(
      root,
      "reference_posteriors/draws/info/data_old-model_old.info.json"
    )
  )
  write_zip(
    "reference_posteriors/draws/draws",
    "data_old-model_old.json.zip",
    '[{"y":[1]}]'
  )
  write_json(
    reference_info,
    file.path(
      root,
      "reference_posteriors/summary_statistics/mean_value/info/data_old-model_old.info.json"
    )
  )
  write_json(
    list(names = "y", mean_y = 1, mcse_mean_y = 0),
    file.path(
      root,
      "reference_posteriors/summary_statistics/mean_value/mean_value/data_old-model_old.json"
    )
  )
  write_json(
    list(alias = "data_old-model_old"),
    file.path(root, "alias/posteriors.json")
  )
  list(root = root, pdb = pdb_local(root))
}

rename_fixture_bytes <- function(root) {
  files <- list.files(root, recursive = TRUE)
  stats::setNames(
    lapply(file.path(root, files), function(path) {
      readBin(path, "raw", n = file.info(path)$size)
    }),
    files
  )
}

test_that("write_pdb refuses an existing payload before writing its metadata", {
  fixture <- make_rename_fixture()
  data <- get_data("data_old", fixture$pdb)
  data_info <- info(data)
  data_info$name <- "data_copy"
  data_info$data_file <- "data/data/data_copy.json"
  info(data) <- data_info
  file.copy(
    file.path(fixture$root, "data/data/data_old.json.zip"),
    file.path(fixture$root, "data/data/data_copy.json.zip")
  )
  before <- rename_fixture_bytes(fixture$root)
  expect_error(write_pdb(data, fixture$pdb), "already exists")
  expect_identical(rename_fixture_bytes(fixture$root), before)
})
