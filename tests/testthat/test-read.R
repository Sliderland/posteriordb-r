test_that("a local connection finds the database and prints", {
  p <- local_pdb()
  expect_s3_class(p, c("pdb_local", "pdb"))
  clone <- file.path(withr::local_tempdir(), "posteriordb")
  dir.create(clone)
  file.copy(p$path, clone, recursive = TRUE)
  file.rename(file.path(clone, "pdb"), file.path(clone, "posterior_database"))
  expect_match(pdb_local(clone)$path, "posteriordb/posterior_database$")
  expect_identical(pdb_local(file.path(clone, "posterior_database", "data", "data"))$path,
                   pdb_local(clone)$path)
  expect_output(print(p), "Posterior Database \\(local\\)")
  expect_error(pdb_local(withr::local_tempdir()), "No posterior database")
  expect_error(pdb_local(""), "No database path")
})

test_that("the version is read from git without a git dependency", {
  p <- local_pdb()
  expect_true(is.na(p$version$sha))
  git <- file.path(p$path, ".git")
  dir.create(file.path(git, "refs", "heads"), recursive = TRUE)
  writeLines("ref: refs/heads/main", file.path(git, "HEAD"))
  writeLines("abc123", file.path(git, "refs", "heads", "main"))
  expect_identical(pdb_local(p$path)$version$sha, "abc123")
  unlink(file.path(git, "refs", "heads", "main"))
  writeLines(c("# pack-refs", "def456 refs/heads/main"), file.path(git, "packed-refs"))
  expect_identical(pdb_local(p$path)$version$sha, "def456")
})

test_that("pdb_config and pdb_default build local connections", {
  p <- local_pdb()
  dir <- withr::local_tempdir()
  writeLines(c("type: local", paste0("path: ", p$path)), file.path(dir, ".pdb_config.yml"))
  expect_identical(pdb_config(dir)$path, p$path)
  withr::with_dir(dir, expect_identical(pdb_default()$path, p$path))
  withr::with_options(list(pdb_path = p$path), expect_identical(pdb_default()$path, p$path))
  writeLines("type: ftp", file.path(dir, ".pdb_config.yml"))
  expect_error(pdb_config(dir), "type")
})

test_that("names are listed", {
  p <- local_pdb()
  expect_identical(posterior_names(p), c("eight_schools-eight_schools_centered",
                                         "eight_schools-eight_schools_noncentered"))
  expect_identical(model_names(p), c("eight_schools_centered", "eight_schools_noncentered"))
  expect_identical(data_names(p), "eight_schools")
  expect_identical(reference_posterior_names(p), "eight_schools-eight_schools_noncentered")
  expect_identical(reference_posterior_names(p, "mean_value"), "eight_schools-eight_schools_noncentered")
  expect_setequal(alias_names(pdb = p), c("eight_schools", "8schools"))
  expect_error(reference_posterior_names(p, "sd"))
})

test_that("posteriors are read by name or alias with their model and data info", {
  p <- local_pdb()
  po <- posterior("8schools", p)
  expect_s3_class(po, "pdb_posterior")
  expect_identical(po$name, "eight_schools-eight_schools_noncentered")
  expect_identical(pdb(po), p)
  expect_identical(po$dimensions, list(theta = 8L, mu = 1L, tau = 1L))
  expect_s3_class(model_info(po), "pdb_model_info")
  expect_s3_class(data_info(po), "pdb_data_info")
  expect_s3_class(po$added_date, "Date")
  expect_identical(posterior_names(po), po$name)
  expect_identical(pdb_posterior, posterior)
  expect_output(print(po), "Model: eight_schools_noncentered")
  expect_error(posterior("missing", p), "not found")
  expect_error(posterior("../x", p), "single path component")
})

test_that("model code, data and their file paths are read", {
  p <- local_pdb()
  po <- posterior("eight_schools-eight_schools_centered", p)
  code <- stan_code(po)
  expect_s3_class(code, "pdb_model_code")
  expect_identical(framework(code), "stan")
  expect_match(code, "parameters")
  expect_identical(info(code), model_info(po))
  expect_match(model_code(po, "pymc"), "import pymc")
  expect_identical(as.character(model_code("eight_schools_centered", "stan", pdb = p)), as.character(code))
  expect_true(file.exists(stan_code_file_path(po)))
  expect_error(model_code(po, "tfp"), "no tfp implementation")

  dat <- get_data(po)
  expect_s3_class(dat, "pdb_data")
  expect_identical(dat$J, 8L)
  expect_identical(info(dat)$name, "eight_schools")
  expect_identical(stan_data(po), dat)
  expect_identical(pdb_data("eight_schools", pdb = p), dat)
  expect_true(file.exists(data_file_path(po)))
  expect_output(print(dat), "\\$J")
})

test_that("extracted zip files are refreshed when the database changes", {
  p <- local_pdb()
  first <- get_data("eight_schools", pdb = p)
  zipfile <- file.path(p$path, "data", "data", "eight_schools.json.zip")
  posteriordb:::write_zip_json('{"J": 1, "y": [1], "sigma": [1]}', zipfile, "eight_schools.json")
  Sys.setFileTime(zipfile, Sys.time() + 10)
  expect_identical(get_data("eight_schools", pdb = p)$J, 1L)
  pdb_clear_cache(p)
  expect_length(list.files(p$cache_path), 0)
})

test_that("linked posteriors are found from data and models", {
  p <- local_pdb()
  expect_length(posterior_names(get_data("eight_schools", pdb = p)), 2)
  expect_identical(posterior_names(model_info("eight_schools_centered", pdb = p)),
                   "eight_schools-eight_schools_centered")
})

test_that("reference posteriors and summary statistics are read", {
  p <- local_pdb()
  po <- posterior("eight_schools-eight_schools_centered", p)
  rpi <- reference_posterior_draws_info(po)
  expect_s3_class(rpi, "pdb_reference_posterior_info")
  expect_identical(rpi$name, "eight_schools-eight_schools_noncentered")
  expect_output(print(rpi), "stan_sampling")

  rpd <- reference_posterior_draws(po)
  expect_s3_class(rpd, c("pdb_reference_posterior_draws", "draws_list"))
  expect_identical(posterior::nchains(rpd), 10L)
  expect_identical(posterior::variables(rpd)[1], "theta[1]")
  expect_identical(info(rpd), rpi)
  expect_true(file.exists(reference_posterior_draws_file_path(po)))
  expect_output(print(rpd), "Reference posterior")
  expect_s3_class(summary(rpd), "draws_summary")

  mv <- reference_posterior_summary_statistic(po, "mean_value")
  expect_s3_class(mv, "pdb_reference_posterior_summary_statistic")
  expect_length(mv$names, 10)
  expect_identical(names(reference_posterior_summary_statistics(po)),
                   c("mean_value", "mean_squared_value"))
  expect_output(print(mv), "mean_value")

  expect_error(reference_posterior_draws(as.posterior(
    utils::modifyList(unclass(po), list(reference_posterior_name = NULL)), pdb = p)),
    "no reference posterior")
})

test_that("metadata tables, filtering and keyword search work", {
  p <- local_pdb()
  tbl <- posteriors_tbl_df(p)
  expect_s3_class(tbl, "tbl_df")
  expect_identical(nrow(tbl), 4L)
  expect_identical(nrow(as.data.frame(posterior("8schools", p))), 2L)
  skip_if_not_installed("dplyr")
  found <- filter_posteriors(p, model_name == "eight_schools_centered")
  expect_identical(posterior_names(found), list("eight_schools-eight_schools_centered"))

  expect_identical(nrow(search_posteriors(p, "BENCHMARK")), 2L)
  expect_identical(search_posteriors(p, "bda3", fields = "data")$matched_in, rep("data", 2))
  expect_identical(nrow(search_posteriors(p, "bda3", fields = c("data", "posterior"), match = "all")), 0L)
  expect_identical(names(search_posteriors(p, "nothing")),
                   c("posterior_name", "data_name", "model_name", "matched_in", "matched_keywords"))
})

test_that("the bibliography is read", {
  p <- local_pdb()
  expect_s3_class(bibliography(p), "bibentry")
  expect_identical(bibliography_keys(p), c("gelman2013bayesian", "rubin1981estimation"))
  expect_length(bibliography_entry("rubin1981estimation", p), 1)
  expect_error(bibliography_entry("nope", p))
})

test_that("check_pdb passes on the fixture and reports problems", {
  p <- local_pdb()
  expect_identical(check_pdb(p, verbose = FALSE), 0L)
  expect_message(check_pdb(p), "Posterior database is ok")
  writeLines('{"bad": "eight_schools-nope"}', file.path(p$path, "alias", "posteriors.json"))
  expect_message(status <- check_pdb(p, verbose = FALSE), "aliases: Aliases pointing")
  expect_identical(status, 1L)
})

test_that("in-memory posteriors can be built from objects or names", {
  p <- local_pdb()
  po <- as.posterior(list(model_name = "eight_schools_centered", data_name = "eight_schools",
                          dimensions = list(theta = 8, mu = 1, tau = 1)), pdb = p)
  expect_identical(po$name, "eight_schools-eight_schools_centered")
  expect_null(po$reference_posterior_name)

  standalone <- as.posterior(list(
    pdb_model_code = stan_code(po), pdb_data = get_data(po), name = "x",
    dimensions = list(theta = 8, mu = 1, tau = 1)))
  expect_null(pdb(standalone))
  expect_identical(get_data(standalone), get_data(po))
  expect_identical(stan_code(standalone), stan_code(po))
  expect_error(model_code(standalone, "pymc"), "not attached to a database")
  expect_error(as.posterior(list(model_name = "m")), "data_name")
  expect_error(as.posterior(list(model_name = "eight_schools_centered", data_name = "eight_schools",
                                 dimensions = list(theta = 0)), pdb = p), "positive")
})
