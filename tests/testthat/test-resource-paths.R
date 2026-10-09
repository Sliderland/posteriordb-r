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
