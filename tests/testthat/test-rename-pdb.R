context("test-rename-pdb")

make_rename_fixture <- function() {
  parent <- tempfile("posteriordb-rename-")
  root <- file.path(parent, "database")
  withr::defer(unlink(parent, recursive = TRUE), envir = parent.frame())
  dirs <- c(
    "data/info", "data/data", "models/info", "models/stan", "posteriors",
    "reference_posteriors/draws/info", "reference_posteriors/draws/draws",
    "reference_posteriors/summary_statistics/mean_value/info",
    "reference_posteriors/summary_statistics/mean_value/mean_value", "alias"
  )
  for (directory in dirs) dir.create(file.path(root, directory), recursive = TRUE)
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

rename_fixture_bytes <- function(root) {
  files <- list.files(root, recursive = TRUE)
  stats::setNames(lapply(file.path(root, files), function(path)
    readBin(path, "raw", n = file.info(path)$size)), files)
}

test_that("failed ZIP staging leaves every original file intact", {
  actual_zip <- utils::zip
  expected <- c(status = "Could not create staged ZIP archive",
    member = "wrong JSON member", payload = "changed the JSON payload")
  for (failure in names(expected)) {
    fixture <- make_rename_fixture()
    before <- rename_fixture_bytes(fixture$root)
    oldwd <- getwd()
    testthat::local_mocked_bindings(zip = function(zipfile, files, ...) {
      if (failure == "member") files <- "wrong.json"
      if (failure == "member") writeLines("{}", files)
      actual_zip(zipfile, files, ...)
      if (failure == "payload") {
        bytes <- readBin(zipfile, "raw", n = file.info(zipfile)$size)
        name_length <- sum(as.integer(bytes[27:28]) * c(1, 256))
        extra_length <- sum(as.integer(bytes[29:30]) * c(1, 256))
        payload <- 31L + name_length + extra_length
        bytes[payload] <- as.raw(bitwXor(as.integer(bytes[payload]), 255L))
        writeBin(bytes, zipfile)
      }
      if (failure == "status") 1L else 0L
    }, .package = "utils")
    expect_error(rename_pdb("data_old", "data_new", type = "data", pdb = fixture$pdb),
      expected[[failure]])
    expect_identical(rename_fixture_bytes(fixture$root), before)
    expect_identical(getwd(), oldwd)
    expect_length(list.files(dirname(fixture$root), all.files = TRUE,
      pattern = "^\\.pdb-rename-(stage|backup)-"), 0L)
  }
})

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
  expect_length(list.files(dirname(fixture$root), all.files = TRUE,
    pattern = "^\\.pdb-rename-(stage|backup)-"), 0L)
})

test_that("renames update every posterior sharing a moved reference", {
  for (type in c("data", "model")) {
    fixture <- make_rename_fixture()
    root <- fixture$root
    # `alternate` is read before the canonical posterior and shares its reference.
    shared <- jsonlite::read_json(file.path(root, "posteriors/data_old-model_old.json"))
    shared$name <- "alternate"
    jsonlite::write_json(shared, file.path(root, "posteriors/alternate.json"),
      pretty = TRUE, auto_unbox = TRUE)
    rename_pdb(paste0(type, "_old"), paste0(type, "_new"), type = type, pdb = fixture$pdb)
    moved <- if (type == "data") "data_new-model_old" else "data_old-model_new"
    for (name in c("alternate", moved)) {
      stored <- jsonlite::read_json(file.path(root, "posteriors", paste0(name, ".json")))
      expect_identical(stored$reference_posterior_name, moved)
    }
    expect_true(file.exists(file.path(root, "reference_posteriors/draws/draws",
      paste0(moved, ".json.zip"))))
    unlink(root, recursive = TRUE)
  }
})

test_that("model-code rename preserves code and unrelated implementation metadata", {
  fixture <- make_rename_fixture()
  code <- model_code("model_old", "stan", pdb = fixture$pdb)
  metadata <- info(code)
  metadata$model_implementations["pymc"] <- list(NULL)
  metadata$model_implementations$stan$stan_version <- "test-version"
  info(code) <- metadata

  renamed <- rename_pdb(code, "model_new")
  expect_identical(as.character(renamed), as.character(code))
  expect_identical(framework(renamed), framework(code))
  expect_identical(pdb(renamed), pdb(code))
  metadata$name <- "model_new"
  metadata$model_implementations$stan$model_code <- "models/stan/model_new.stan"
  expect_identical(info(renamed), metadata)
  expect_false(file.exists(file.path(fixture$root, "models/stan/model_old.stan")))
  expect_identical(readLines(file.path(fixture$root, "models/stan/model_new.stan")),
                   as.character(code))
  expect_identical(posterior("data_old-model_new", fixture$pdb)$model_name, "model_new")
})

test_that("data and posterior renames use their attached connection", {
  fixture <- make_rename_fixture()
  data <- get_data("data_old", fixture$pdb)
  renamed_data <- rename_pdb(data, "data_new")
  expect_identical(info(renamed_data)$name, "data_new")
  expect_equal(get_data("data_new", fixture$pdb), renamed_data, ignore_attr = TRUE)
  old_posterior <- posterior("data_new-model_old", fixture$pdb)
  renamed_posterior <- rename_pdb(old_posterior, "posterior_new")
  expect_identical(renamed_posterior$name, "posterior_new")
  expect_identical(posterior("posterior_new", fixture$pdb)$reference_posterior_name,
                   "posterior_new")
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

test_that("failed reservations and installations restore every original file", {
  actual_rename <- base::file.rename
  for (failure in c("reserve", "install", "error")) {
    fixture <- make_rename_fixture()
    before <- rename_fixture_bytes(fixture$root)
    reservations <- installations <- 0L
    testthat::local_mocked_bindings(file.rename = function(from, to) {
      if (startsWith(from, paste0(fixture$root, "/")) &&
          startsWith(basename(dirname(to)), ".pdb-rename-backup-")) {
        reservations <<- reservations + 1L
        if (failure == "reserve" && reservations == 2L) return(FALSE)
      }
      if (startsWith(basename(dirname(from)), ".pdb-rename-stage-") &&
          startsWith(to, paste0(fixture$root, "/"))) {
        installations <<- installations + 1L
        if (failure != "reserve" && installations == 2L) {
          if (failure == "error") stop("Injected installation error")
          return(FALSE)
        }
      }
      actual_rename(from, to)
    }, .package = "base")
    expect_error(rename_pdb("data_old", "data_new", type = "data", pdb = fixture$pdb),
                 "The migration was rolled back")
    expect_identical(rename_fixture_bytes(fixture$root), before)
    expect_length(list.files(dirname(fixture$root), all.files = TRUE,
      pattern = "^\\.pdb-rename-(stage|backup)-"), 0L)
  }
})

test_that("incomplete rename rollback retains original bytes and recovery paths", {
  fixture <- make_rename_fixture()
  before <- rename_fixture_bytes(fixture$root)
  original <- file.path(fixture$root, "data/info/data_old.info.json")
  actual_rename <- base::file.rename
  installations <- 0L
  testthat::local_mocked_bindings(file.rename = function(from, to) {
    if (startsWith(basename(dirname(from)), ".pdb-rename-stage-") &&
        startsWith(to, paste0(fixture$root, "/"))) {
      installations <<- installations + 1L
      if (installations == 2L) return(FALSE)
    }
    if (startsWith(basename(dirname(from)), ".pdb-rename-backup-") &&
        identical(to, original)) return(FALSE)
    actual_rename(from, to)
  }, .package = "base")
  error <- tryCatch(
    rename_pdb("data_old", "data_new", type = "data", pdb = fixture$pdb), error = identity
  )
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "Rollback incomplete")
  backup <- list.files(dirname(fixture$root), all.files = TRUE, full.names = TRUE,
    pattern = "^\\.pdb-rename-backup-")
  expect_length(backup, 1L)
  retained <- list.files(backup, full.names = TRUE)
  expect_length(retained, 1L)
  expect_match(conditionMessage(error), original, fixed = TRUE)
  expect_match(conditionMessage(error), retained, fixed = TRUE)
  expect_false(file.exists(original))
  expect_identical(readBin(retained, "raw", n = file.info(retained)$size),
                   before[["data/info/data_old.info.json"]])
  expect_identical(rename_fixture_bytes(fixture$root),
                   before[names(before) != "data/info/data_old.info.json"])
  expect_length(list.files(dirname(fixture$root), all.files = TRUE,
    pattern = "^\\.pdb-rename-stage-"), 0L)
  expect_true(actual_rename(retained, original))
  expect_identical(rename_fixture_bytes(fixture$root), before)
})
