new_data <- function(name = "study") {
  as.pdb_data(list(N = 2L, y = c(1.5, 2)),
              info = list(name = name, title = "A study", added_by = "Test",
                          added_date = as.Date("2026-01-01")))
}

new_model <- function(name = "normal") {
  as.model_code("parameters { real mu; } model { mu ~ normal(0, 1); }",
                info = list(name = name, title = "Normal", framework = "stan",
                            added_by = "Test", added_date = as.Date("2026-01-01")))
}

test_that("data, models and posteriors round trip", {
  p <- local_pdb()
  written <- write_pdb(new_data(), p)
  expect_setequal(written, c("data/info/study.info.json", "data/data/study.json.zip"))
  expect_identical(get_data("study", pdb = p)$y, c(1.5, 2))
  expect_identical(data_info("study", pdb = p)$title, "A study")

  write_pdb(new_model(), p)
  mi <- model_info("normal", pdb = p)
  expect_identical(mi$model_implementations$stan$model_code, "models/stan/normal.stan")
  expect_match(stan_code("normal", pdb = p), "real mu")

  po <- as.posterior(list(model_name = "normal", data_name = "study", dimensions = list(mu = 1),
                          keywords = "test"), pdb = p)
  write_pdb(po, p)
  back <- posterior("study-normal", p)
  expect_identical(back$dimensions, list(mu = 1L))
  expect_null(back$reference_posterior_name)
  expect_identical(back$keywords, "test")
  expect_true("study-normal" %in% posterior_names(p))
})

test_that("existing files are never silently replaced", {
  p <- local_pdb()
  write_pdb(new_data(), p)
  expect_length(write_pdb(new_data(), p), 0)
  changed <- new_data()
  changed$y <- c(3.5, 4)
  expect_error(write_pdb(changed, p), "data/data/study.json.zip")
  nudged <- new_data()
  nudged$y <- nudged$y * (1 + 1e-10)
  expect_error(write_pdb(nudged, p), "data/data/study.json.zip")
  expect_identical(get_data("study", pdb = p)$y, c(1.5, 2))
  write_pdb(changed, p, overwrite = TRUE)
  expect_identical(get_data("study", pdb = p)$y, c(3.5, 4))
  # A conflict in one file means no file is written.
  model <- new_model("eight_schools_centered")
  expect_error(write_pdb(model, p), "models/info")
  expect_match(stan_code("eight_schools_centered", pdb = p), "theta")
})

test_that("unchanged database content is recognised whatever its formatting", {
  p <- local_pdb()
  expect_length(write_pdb(get_data("eight_schools", pdb = p), p), 0)
  expect_length(write_pdb(stan_code("eight_schools_centered", pdb = p), p), 0)
  expect_length(write_pdb(posterior("8schools", p), p), 0)
})

test_that("posteriors can only link to stored reference posteriors", {
  p <- local_pdb()
  po <- as.posterior(list(model_name = "eight_schools_centered", data_name = "eight_schools",
                          name = "copy", reference_posterior_name = "missing",
                          dimensions = list(theta = 8, mu = 1, tau = 1)), pdb = p)
  expect_error(write_pdb(po, p), "not in the database")
})

test_that("checked reference draws are written with summaries and linked", {
  p <- local_pdb()
  po <- as.posterior(list(model_name = "eight_schools_centered", data_name = "eight_schools",
                          name = "new_posterior", dimensions = list(theta = 8, mu = 1, tau = 1)),
                     pdb = p)
  write_pdb(po, p)
  rpd <- checked_iid_draws()
  info(rpd)$name <- "new_posterior"
  written <- write_pdb(rpd, p)
  expect_length(written, 7)
  expect_identical(posterior("new_posterior", p)$reference_posterior_name, "new_posterior")
  back <- reference_posterior_draws("new_posterior", pdb = p)
  expect_equal(posterior::as_draws_array(back), posterior::as_draws_array(posteriordb:::strip_reference_class(rpd)),
               ignore_attr = TRUE)
  expect_true(info(back)$checks_made$no_divergent_transitions)
  expect_identical(names(reference_posterior_summary_statistics("new_posterior", pdb = p)),
                   c("mean_value", "mean_squared_value"))
  # Writing again is a no-op; replacing needs overwrite.
  expect_length(write_pdb(rpd, p), 0)
  other <- checked_iid_draws(seed = 2)
  info(other)$name <- "new_posterior"
  expect_error(write_pdb(other, p), "overwrite")
})

test_that("reference draws need a posterior and passing checks", {
  p <- local_pdb()
  rpd <- checked_iid_draws()
  info(rpd)$name <- "nowhere"
  expect_error(write_pdb(rpd, p), "not in the database")
  rpd <- checked_iid_draws()
  expect_error(write_pdb(rpd, p, posterior_name = "eight_schools-eight_schools_centered",
                         overwrite = TRUE), NA)
  info(rpd)$name <- "other"
  expect_error(write_pdb(rpd, p, posterior_name = "eight_schools-eight_schools_centered"),
               "already links")
  bad <- as.reference_posterior_draws(iid_draws(iterations = 100), info = reference_info())
  expect_error(write_pdb(bad, p, overwrite = TRUE), "failed the checks")
})

test_that("objects are removed", {
  p <- local_pdb()
  write_pdb(new_data(), p)
  remove_pdb(get_data("study", pdb = p), p)
  expect_false("study" %in% data_names(p))
  write_pdb(new_model(), p)
  remove_pdb(stan_code("normal", pdb = p), p)
  expect_false(file.exists(file.path(p$path, "models", "stan", "normal.stan")))
  expect_error(remove_pdb(new_data(), p), "Not in the database")
  po <- posterior("8schools", p)
  remove_pdb(reference_posterior_summary_statistic(po, "mean_value"), p)
  expect_length(reference_posterior_names(p, "mean_value"), 0)
  remove_pdb(reference_posterior_draws(po), p)
  expect_length(reference_posterior_names(p), 0)
  remove_pdb(po, p)
  expect_false(po$name %in% posterior_names(p))
})

test_that("posteriors are linked to stored reference posteriors", {
  p <- local_pdb()
  po <- as.posterior(list(model_name = "eight_schools_centered", data_name = "eight_schools",
                          name = "linked", dimensions = list(theta = 8, mu = 1, tau = 1)), pdb = p)
  write_pdb(po, p)
  expect_error(link_reference_posterior("linked", pdb = p), "not in the database")
  ref <- "eight_schools-eight_schools_noncentered"
  link_reference_posterior("linked", ref, pdb = p)
  expect_identical(posterior("linked", p)$reference_posterior_name, ref)
  expect_error(link_reference_posterior("linked", "linked", pdb = p), "not in the database")
})

test_that("references are appended to the bibliography", {
  p <- local_pdb()
  entry <- "@article{new2026, title={New}, author={Doe, Jane}, journal={J}, year={2026}}"
  append_reference(entry, p)
  expect_true("new2026" %in% bibliography_keys(p))
  expect_error(append_reference(entry, p), "already in the bibliography")
  expect_error(append_reference(sub("new2026", "RUBIN1981ESTIMATION", entry), p), "already")
  bib <- utils::bibentry("Misc", key = "misc2026", title = "Misc", author = "A B", year = 2026)
  append_reference(bib, p)
  expect_true("misc2026" %in% bibliography_keys(p))
  expect_error(append_reference("@article{broken, title={x}", p))
})

test_that("renaming data follows posteriors, references and aliases", {
  p <- local_pdb()
  rename_pdb("eight_schools", "schools", pdb = p)
  expect_identical(data_names(p), "schools")
  expect_identical(info(get_data("schools", pdb = p))$data_file, "data/data/schools.json")
  expect_setequal(posterior_names(p), c("schools-eight_schools_centered",
                                        "schools-eight_schools_noncentered"))
  expect_identical(reference_posterior_names(p), "schools-eight_schools_noncentered")
  expect_identical(reference_posterior_names(p, "mean_value"), "schools-eight_schools_noncentered")
  po <- posterior("8schools", p)
  expect_identical(po$name, "schools-eight_schools_noncentered")
  expect_identical(posterior("schools-eight_schools_centered", p)$reference_posterior_name,
                   "schools-eight_schools_noncentered")
  expect_identical(info(reference_posterior_draws(po))$name, "schools-eight_schools_noncentered")
  expect_identical(check_pdb(p, verbose = FALSE), 0L)
})

test_that("renaming a model moves its code; posteriors can be renamed", {
  p <- local_pdb()
  rename_pdb(model_info("eight_schools_centered", pdb = p), "centered", pdb = p)
  expect_true(file.exists(file.path(p$path, "models", "stan", "centered.stan")))
  expect_true(file.exists(file.path(p$path, "models", "pymc", "centered.py")))
  expect_match(stan_code(posterior("eight_schools-centered", p)), "theta")
  expect_identical(rename_pdb("eight_schools-eight_schools_noncentered", "es", pdb = p)$name, "es")
  expect_identical(posterior("8schools", p)$reference_posterior_name, "es")
  expect_identical(check_pdb(p, verbose = FALSE), 0L)
  expect_error(rename_pdb("es", "eight_schools-centered", pdb = p), "already exists")
  expect_error(rename_pdb("nothing", "x", pdb = p), "Give `type`")
})

test_that("info fields outside the schema are rejected", {
  expect_error(as.data_info(list(name = "d", title = "D", keyword = "x")), "Unknown field.*keyword")
  info <- list(name = "m", title = "M", framework = "stan", licence = "BSD")
  expect_s3_class(as.model_info(info), "pdb_model_info")
  info$model_implementations <- list(stan = list(model_code = "models/stan/m.stan", version = "1"))
  expect_error(as.model_info(info), "Unknown field.*stan model implementation: version")
})

test_that("a posterior built in memory is checked before it is written", {
  p <- local_pdb()
  po <- as.posterior(list(pdb_model_code = new_model(), pdb_data = new_data(),
                          dimensions = list(mu = 1), references = "rubin1981estimation"))
  expect_true(check_pdb_posterior(po, verbose = FALSE, pdb = p))
  po$references <- "unknown2026"
  expect_error(check_pdb_posterior(po, verbose = FALSE, pdb = p), "unknown2026")
})
