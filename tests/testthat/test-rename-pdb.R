context("test-rename-pdb")

make_rename_fixture <- function() {
  root <- tempfile("posteriordb-rename-")
  dirs <- c(
    "data/info", "data/data", "models/info", "models/stan", "posteriors",
    "reference_posteriors/draws/info", "reference_posteriors/draws/draws",
    "reference_posteriors/summary_statistics/mean_value/info",
    "reference_posteriors/summary_statistics/mean_value/mean_value", "alias"
  )
  for (directory in dirs) dir.create(file.path(root, directory), recursive = TRUE)
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
      name = "data_old", title = "Data", added_by = "test",
      added_date = "2026-01-01", data_file = "data/data/data_old.json"
    ),
    file.path(root, "data/info/data_old.info.json")
  )
  write_zip("data/data", "data_old.json.zip", '{"y":[1,2]}')
  write_json(
    list(
      name = "model_old", title = "Model", added_by = "test",
      added_date = "2026-01-01",
      model_implementations = list(stan = list(model_code = "models/stan/model_old.stan"))
    ),
    file.path(root, "models/info/model_old.info.json")
  )
  writeLines("parameters {}", file.path(root, "models/stan/model_old.stan"))
  write_json(
    list(
      name = "data_old-model_old", model_name = "model_old", data_name = "data_old",
      reference_posterior_name = "data_old-model_old", dimensions = list(y = 2),
      added_by = "test", added_date = "2026-01-01"
    ),
    file.path(root, "posteriors/data_old-model_old.json")
  )
  reference_info <- list(
    name = "data_old-model_old",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = 1), checks_made = list(), comments = "test",
    added_by = "test", added_date = "2026-01-01", versions = list()
  )
  write_json(reference_info, file.path(
    root, "reference_posteriors/draws/info/data_old-model_old.info.json"
  ))
  write_zip(
    "reference_posteriors/draws/draws", "data_old-model_old.json.zip", '[{"y":[1]}]'
  )
  write_json(reference_info, file.path(
    root, "reference_posteriors/summary_statistics/mean_value/info/data_old-model_old.info.json"
  ))
  write_json(
    list(names = "y", mean_y = 1, mcse_mean_y = 0),
    file.path(
      root,
      "reference_posteriors/summary_statistics/mean_value/mean_value/data_old-model_old.json"
    )
  )
  write_json(list(alias = "data_old-model_old"), file.path(root, "alias/posteriors.json"))
  list(root = root, pdb = pdb_local(root))
}

test_that("data and model renames update the complete local PDB graph", {
  fixture <- make_rename_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  pdb <- fixture$pdb

  # Populate the old data cache before migrating; a successful migration must
  # not leave callers reading the old cached path.
  old_data <- get_data("data_old", pdb)
  expect_equal(old_data$y, c(1, 2))
  old_model_code <- readLines(file.path(fixture$root, "models/stan/model_old.stan"))

  expect_silent(rename_pdb("data_old", "data_new", type = "data", pdb = pdb))
  expect_false(file.exists(file.path(fixture$root, "data/info/data_old.info.json")))
  expect_true(file.exists(file.path(fixture$root, "data/info/data_new.info.json")))
  expect_equal(
    jsonlite::read_json(file.path(fixture$root, "data/info/data_new.info.json"), simplifyVector = FALSE)$data_file,
    "data/data/data_new.json"
  )
  expect_equal(
    utils::unzip(file.path(fixture$root, "data/data/data_new.json.zip"), list = TRUE)$Name,
    "data_new.json"
  )

  data_posterior <- jsonlite::read_json(
    file.path(fixture$root, "posteriors/data_new-model_old.json"), simplifyVector = FALSE
  )
  expect_identical(data_posterior$data_name, "data_new")
  expect_identical(data_posterior$name, "data_new-model_old")
  expect_identical(data_posterior$reference_posterior_name, "data_new-model_old")
  expect_identical(
    jsonlite::read_json(file.path(fixture$root, "alias/posteriors.json"), simplifyVector = FALSE)$alias,
    "data_new-model_old"
  )
  expect_true(file.exists(file.path(
    fixture$root, "reference_posteriors/summary_statistics/mean_value/mean_value/data_new-model_old.json"
  )))
  expect_equal(
    utils::unzip(file.path(
      fixture$root, "reference_posteriors/draws/draws/data_new-model_old.json.zip"
    ), list = TRUE)$Name,
    "data_new-model_old.json"
  )
  expect_equal(get_data("data_new", pdb)$y, c(1, 2))

  expect_silent(rename_pdb("model_old", "model_new", type = "model", pdb = pdb))
  expect_false(file.exists(file.path(fixture$root, "models/stan/model_old.stan")))
  expect_true(file.exists(file.path(fixture$root, "models/stan/model_new.stan")))
  expect_identical(readLines(file.path(fixture$root, "models/stan/model_new.stan")), old_model_code)
  model_info <- jsonlite::read_json(
    file.path(fixture$root, "models/info/model_new.info.json"), simplifyVector = FALSE
  )
  expect_identical(model_info$name, "model_new")
  expect_identical(model_info$model_implementations$stan$model_code, "models/stan/model_new.stan")

  final_posterior <- posterior("data_new-model_new", pdb)
  expect_identical(final_posterior$data_name, "data_new")
  expect_identical(final_posterior$model_name, "model_new")
  expect_identical(final_posterior$reference_posterior_name, "data_new-model_new")
  expect_equal(as.character(model_code(final_posterior, "stan")), "parameters {}")
  expect_equal(get_data(final_posterior)$y, c(1, 2))
})

test_that("rename rejects unsafe names and collisions without mutation", {
  fixture <- make_rename_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  pdb <- fixture$pdb
  writeLines("existing", file.path(fixture$root, "data/info/data_taken.info.json"))

  expect_error(
    rename_pdb("data_old", "../bad", type = "data", pdb = pdb),
    "single path components"
  )
  expect_error(
    rename_pdb("data_old", "data_taken", type = "data", pdb = pdb),
    "Refusing to overwrite"
  )
  expect_true(file.exists(file.path(fixture$root, "data/info/data_old.info.json")))
  expect_true(file.exists(file.path(fixture$root, "data/data/data_old.json.zip")))
})

test_that("posterior-only renames move its reference files and aliases", {
  fixture <- make_rename_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  pdb <- fixture$pdb

  expect_silent(rename_pdb(
    "data_old-model_old", "posterior_new", type = "posterior", pdb = pdb
  ))
  expect_false(file.exists(file.path(fixture$root, "posteriors/data_old-model_old.json")))
  expect_true(file.exists(file.path(fixture$root, "posteriors/posterior_new.json")))
  posterior_info <- jsonlite::read_json(
    file.path(fixture$root, "posteriors/posterior_new.json"), simplifyVector = FALSE
  )
  expect_identical(posterior_info$name, "posterior_new")
  expect_identical(posterior_info$data_name, "data_old")
  expect_identical(posterior_info$model_name, "model_old")
  expect_true(file.exists(file.path(
    fixture$root, "reference_posteriors/draws/info/posterior_new.info.json"
  )))
  expect_identical(
    jsonlite::read_json(file.path(fixture$root, "alias/posteriors.json"), simplifyVector = FALSE)$alias,
    "posterior_new"
  )
})
