resource_path_fixture <- function() {
  parent <- tempfile("resource-paths-")
  root <- file.path(parent, "database")
  outside <- file.path(parent, "database-sibling")
  for (folder in c("data", "models", "posteriors", "cache", "alias"))
    dir.create(file.path(root, folder), recursive = TRUE)
  dir.create(outside)
  writeLines("sentinel", file.path(outside, "sentinel"))
  writeLines("{}", file.path(root, "alias", "posteriors.json"))
  withr::defer(unlink(parent, recursive = TRUE), envir = parent.frame())
  list(pdb = pdb_local(root, cache_path = file.path(root, "cache")),
       root = normalizePath(root), outside = normalizePath(outside), parent = parent)
}

resource_path_objects <- function(pdb) {
  annotation <- list(title = "Fixture", added_by = "test", added_date = Sys.Date())
  dat <- as.pdb_data(list(n = 1L), info = as.pdb_data_info(
    c(list(name = "data.v1-a"), annotation)))
  code <- as.pdb_model_code("parameters { real theta; }", framework = "stan",
    info = as.pdb_model_info(c(list(name = "model.v1-a", framework = "stan"), annotation)))
  # Supplied acceptance metadata exercises the writer contract, not diagnostics.
  ri <- as.pdb_reference_posterior_info(list(name = "data.v1-a-model.v1-a",
    inference = list(method = "analytical", method_arguments = list()),
    diagnostics = list(ndraws = 10000L, nchains = 4L), checks_made = stats::setNames(rep(list(TRUE), 6), c(
      "ndraws_is_10k", "nchains_is_gte_4", "abs_mean_lag1_ac_below_0_05",
      "r_hat_below_1_01", "efmi_above_0_2", "no_divergent_transitions")),
    comments = "Fixture", added_by = "test", added_date = Sys.Date(), versions = NULL))
  set.seed(741)
  draws <- as.pdb_reference_posterior_draws(posterior::as_draws_list(
    array(rnorm(10000), c(2500, 4, 1), dimnames = list(NULL, NULL, "theta"))), info = ri)
  po <- as.pdb_posterior(list(pdb_data = dat, pdb_model_code = code,
    dimensions = list(theta = 1L), reference_posterior_name = ri$name,
    added_by = "test", added_date = Sys.Date()), pdb = pdb)
  structure(list(data = dat, model_code = code, posterior = po, reference_draws = draws,
    diagnostics = list(checked = TRUE), provenance = list()), class = "pdb_reference_bundle")
}

resource_path_snapshot <- function(parent) {
  paths <- list.files(parent, recursive = TRUE, all.files = TRUE, include.dirs = TRUE)
  stats::setNames(lapply(file.path(parent, paths), function(path) {
    if (dir.exists(path)) return("directory")
    if (!file.exists(path)) return(Sys.readlink(path))
    readBin(path, "raw", n = file.info(path)$size)
  }), paths)
}

test_that("linking honors an explicit destination instead of the object's connection", {
  testthat::local_mocked_bindings(pdb_default = function(...) stop("unexpected default connection"))
  source <- resource_path_fixture()
  destination <- resource_path_fixture()
  for (fixture in list(source, destination)) {
    bundle <- resource_path_objects(fixture$pdb)
    suppressMessages(write_pdb(bundle, fixture$pdb, write_summary_statistics = FALSE))
    unlinked <- bundle$posterior
    unlinked["reference_posterior_name"] <- list(NULL)
    unlinked$embedded_reference_draws <- NULL
    write_pdb(unlinked, fixture$pdb, overwrite = TRUE)
    pdb_clear_cache(fixture$pdb)
  }
  object <- posterior(unlinked$name, source$pdb)
  stored_link <- function(fixture) jsonlite::read_json(file.path(fixture$root,
    "posteriors", paste0(object$name, ".json")))$reference_posterior_name
  result <- link_reference_posterior(object, pdb = destination$pdb)
  expect_identical(pdb(result), destination$pdb)
  expect_null(stored_link(source))
  expect_identical(stored_link(destination), object$name)

  result <- link_reference_posterior(object)
  expect_identical(pdb(result), source$pdb)
  expect_identical(stored_link(source), object$name)
  attr(object, "pdb") <- NULL
  expect_identical(pdb(link_reference_posterior(object, pdb = destination$pdb)), destination$pdb)

  unlink(file.path(destination$root, "reference_posteriors/draws/draws",
    paste0(object$name, ".json.zip")))
  expect_error(link_reference_posterior(result, pdb = destination$pdb), "Both reference-posterior")
  expect_identical(stored_link(source), object$name)
})

test_that("constructors, writers, rename and linking share safe resource names", {
  fixture <- resource_path_fixture()
  bundle <- resource_path_objects(fixture$pdb)
  before <- resource_path_snapshot(fixture$parent)
  for (name in c("", ".", "..", "../escape", "a/b", "a\\b", "a\nb", "a\tb")) {
    di <- info(bundle$data)
    di$name <- name
    di$data_file <- paste0("data/data/", name, ".json")
    mi <- info(bundle$model_code)
    mi$name <- name
    ri <- info(bundle$reference_draws)
    ri$name <- name
    po <- bundle$posterior
    po$name <- name
    expect_error(as.pdb_data_info(unclass(di)))
    expect_error(as.pdb_model_info(unclass(mi)))
    expect_error(as.pdb_reference_posterior_info(unclass(ri)))
    expect_error(as.pdb_posterior(unclass(po), pdb = fixture$pdb))
    for (object in list(di, mi, ri, po))
      expect_error(write_pdb(object, fixture$pdb, type = "draws"))
    expect_error(write_json_to_path("payload", "new/nested", fixture$pdb,
      name = name, info = FALSE))
    expect_error(rename_pdb("absent", name, type = "data", pdb = fixture$pdb))
    expect_error(link_reference_posterior("absent", name, pdb = fixture$pdb))
    expect_error(link_reference_posterior(name, "valid", pdb = fixture$pdb))
    expect_error(import_reference_posterior_draws(NULL, name, pdb = fixture$pdb, write = TRUE))
    expect_identical(resource_path_snapshot(fixture$parent), before)
  }
  for (path in c("../escape", "nested/../../escape", "/absolute", "C:/absolute",
                 "nested\\escape", "new\nnested")) {
    expect_error(write_json_to_path("payload", path, fixture$pdb, name = "safe"))
    expect_identical(resource_path_snapshot(fixture$parent), before)
  }
  # Ordinary names and nested internal paths remain valid.
  expect_true(write_pdb(bundle, fixture$pdb)$reference_draws_written)
  stored <- posterior(bundle$posterior$name, fixture$pdb)
  expect_identical(get_data(stored)$n, 1L)
  expect_equal(as.numeric(posterior::as_draws_array(reference_posterior_draws(stored))),
    as.numeric(posterior::as_draws_array(bundle$reference_draws)))
  expect_true(write_json_to_path("payload", "new/nested", fixture$pdb,
    name = "safe.v1-a", info = FALSE))
  expect_true(file.exists(file.path(fixture$root, "new/nested/safe.v1-a.json")))
})

test_that("multi-file writers reject escaping symlinks before saving metadata", {
  for (destination in c("data/data", "models/stan", "reference_posteriors/draws/draws",
      "reference_posteriors/summary_statistics/mean_value/mean_value")) {
    fixture <- resource_path_fixture()
    bundle <- resource_path_objects(fixture$pdb)
    dir.create(dirname(file.path(fixture$root, destination)), recursive = TRUE,
               showWarnings = FALSE)
    skip_if_not(file.symlink(fixture$outside, file.path(fixture$root, destination)))
    before <- resource_path_snapshot(fixture$parent)
    object <- if (destination == "data/data") bundle$data else if (destination == "models/stan")
      bundle$model_code else bundle$reference_draws
    expect_error(write_pdb(object, fixture$pdb, overwrite = TRUE), "outside the database")
    expect_error(write_pdb(bundle, fixture$pdb, overwrite = TRUE), "outside the database")
    if (grepl("reference_posteriors", destination))
      expect_error(write_imported_reference_posterior_draws(bundle$reference_draws, fixture$pdb,
        overwrite = TRUE, linked_posterior = bundle$posterior), "outside the database")
    if (grepl("summary_statistics", destination)) {
      summary <- summary_statistics_from_checked_reference_draws(bundle$reference_draws)$mean_value
      expect_error(write_pdb(summary, fixture$pdb, overwrite = TRUE), "outside the database")
    }
    expect_identical(resource_path_snapshot(fixture$parent), before)
  }
})

test_that("ZIP writers check temporary JSON, final archive and missing ancestors", {
  for (suffix in c(".json", ".json.zip")) {
    for (target in c("sentinel", "missing")) {
      fixture <- resource_path_fixture()
      bundle <- resource_path_objects(fixture$pdb)
      dir.create(file.path(fixture$root, "data/data"))
      skip_if_not(file.symlink(file.path(fixture$outside, target),
        file.path(fixture$root, "data/data", paste0(info(bundle$data)$name, suffix))))
      before <- resource_path_snapshot(fixture$parent)
      expect_error(write_pdb(bundle$data, fixture$pdb, overwrite = TRUE),
        "outside the database|dangling symlinks")
      expect_error(write_pdb(bundle, fixture$pdb, overwrite = TRUE),
        "outside the database|dangling symlinks")
      expect_identical(resource_path_snapshot(fixture$parent), before)
    }
  }
  fixture <- resource_path_fixture()
  skip_if_not(file.symlink(fixture$outside, file.path(fixture$root, "escape")))
  before <- resource_path_snapshot(fixture$parent)
  expect_error(write_json_to_path("payload", "escape/missing/nested", fixture$pdb,
    name = "safe"), "outside the database")
  expect_identical(resource_path_snapshot(fixture$parent), before)
  # A symlink to a directory inside the database remains usable.
  dir.create(file.path(fixture$root, "internal"))
  skip_if_not(file.symlink(file.path(fixture$root, "internal"), file.path(fixture$root, "shortcut")))
  expect_true(write_json_to_path("payload", "shortcut/nested", fixture$pdb,
    name = "safe", info = FALSE))
  expect_true(file.exists(file.path(fixture$root, "internal/nested/safe.json")))
})

test_that("rename preflight checks all paths before staging", {
  fixture <- resource_path_fixture()
  bundle <- resource_path_objects(fixture$pdb)
  write_pdb(bundle$data, fixture$pdb)
  destination <- file.path(fixture$root, "data/info/renamed.info.json")
  skip_if_not(file.symlink(file.path(fixture$outside, "sentinel"), destination))
  before <- resource_path_snapshot(fixture$parent)
  expect_error(rename_pdb(info(bundle$data), "renamed", pdb = fixture$pdb), "outside the database")
  expect_identical(resource_path_snapshot(fixture$parent), before)
})

test_that("public import and link reject escaping destinations without mutation", {
  fixture <- resource_path_fixture()
  bundle <- resource_path_objects(fixture$pdb)
  write_pdb(bundle$data, fixture$pdb)
  write_pdb(bundle$model_code, fixture$pdb)
  unlinked <- bundle$posterior
  unlinked["reference_posterior_name"] <- list(NULL)
  write_pdb(unlinked, fixture$pdb)
  # Populate the read cache before taking the snapshot.
  posterior(unlinked$name, fixture$pdb)
  testthat::local_mocked_bindings(as_reference_posterior_draws = function(...) bundle$reference_draws)
  dir.create(file.path(fixture$root, "reference_posteriors/draws"), recursive = TRUE)
  skip_if_not(file.symlink(fixture$outside,
    file.path(fixture$root, "reference_posteriors/draws/draws")))
  before <- resource_path_snapshot(fixture$parent)
  expect_error(import_reference_posterior_draws(NULL, unlinked$name, pdb = fixture$pdb,
    write = TRUE), "outside the database")
  expect_identical(resource_path_snapshot(fixture$parent), before)

  path <- file.path(fixture$root, "posteriors", paste0(unlinked$name, ".json"))
  unlink(path)
  skip_if_not(file.symlink(file.path(fixture$outside, "sentinel"), path))
  before <- resource_path_snapshot(fixture$parent)
  expect_error(link_reference_posterior(unlinked$name, pdb = fixture$pdb), "outside the database")
  expect_identical(resource_path_snapshot(fixture$parent), before)
})

test_that("bibliography append rejects escaping paths before replacement", {
  fixture <- resource_path_fixture()
  dir.create(file.path(fixture$root, "bibliography"))
  skip_if_not(file.symlink(file.path(fixture$outside, "sentinel"),
    file.path(fixture$root, "bibliography/references.bib")))
  before <- resource_path_snapshot(fixture$parent)
  ref <- utils::bibentry("Misc", title = "Test entry", key = "test-key")
  expect_error(append_reference(ref, fixture$pdb), "outside the database")
  expect_identical(resource_path_snapshot(fixture$parent), before)
})

test_that("a contained file cannot conceal an escaping parent directory", {
  fixture <- resource_path_fixture()
  internal <- file.path(fixture$root, "internal.json")
  writeLines("original", internal)
  skip_if_not(file.symlink(internal, file.path(fixture$outside, "safe.json")))
  skip_if_not(file.symlink(fixture$outside, file.path(fixture$root, "escape")))
  before <- resource_path_snapshot(fixture$parent)
  expect_error(write_json_to_path("payload", "escape", fixture$pdb,
    name = "safe", info = FALSE, overwrite = TRUE), "outside the database")
  expect_identical(resource_path_snapshot(fixture$parent), before)
})
