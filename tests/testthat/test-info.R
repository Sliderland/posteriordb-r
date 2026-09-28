context("test-info")

test_that("info() should extract the object information", {
  assert_pdb_path_exists()
  expect_silent(pdb_test <- pdb_local())
  posteriordb:::pdb_clear_cache(pdb_test)
  expect_silent(po <- posterior("eight_schools-eight_schools_noncentered", pdb = pdb_test))

  # Data
  expect_silent(d <- pdb_data(po))
  expect_silent(di1 <- pdb_data_info(po))
  expect_silent(di2 <- info(d))
  expect_identical(di1, di2)
  expect_s3_class(d, "pdb_data")
  expect_s3_class(d, "list")

  # Models
  expect_silent(m <- pdb_model_code(po, "stan"))
  expect_silent(mi1 <- pdb_model_info(po))
  expect_silent(mi2 <- info(m))
  expect_identical(mi1, mi2)
  expect_s3_class(m, "pdb_model_code")
  expect_s3_class(m, "character")

  # Reference posterior draws
  expect_silent(rp <- pdb_reference_posterior_draws(po, "stan"))
  expect_silent(rpi1 <- pdb_reference_posterior_draws_info(po))
  expect_silent(rpi2 <- info(rp))
  expect_identical(rpi1, rpi2)
  expect_s3_class(rp, "pdb_reference_posterior_draws")
  expect_s3_class(rp, "draws_list")

})


test_that("data info constructor ", {
  x <- list(name = "wells_data2",
            keywords = c("wells","arsenic","Bangladesh"),
            title = "Factors affecting the decision to switch wells",
            description = "Decisions of households in Bangladesh about whether to change their source of
                     drinking water.",
            urls = "https://github.com/stan-dev/example-models/tree/master/ARM/Ch.5",
            references = "gelman2006data",
            added_date = Sys.Date(),
            data_file = "data/data/.json",
            added_by = "Phil Clemson")
  expect_error(di <- as.pdb_data_info(x))
  x$data_file <- NULL
  expect_silent(di <- as.pdb_data_info(x))
  x$data_file <- "data/data/wells_data2.json"
  expect_silent(di <- as.pdb_data_info(x))
})


test_that("model info constructor ", {
  x <- list(name = "test_eight_schools_model",
            keywords = c("test_model", "hiearchical"),
            title = "Test Non-Centered Model for Eight Schools",
            description = "An hiearchical model, non-centered parametrisation.",
            urls = c("https://cran.r-project.org/web/packages/rstan/vignettes/rstan.html"),
            framework = "stan",
            references = NULL,
            added_by = "Stanislaw Ulam",
            added_date = Sys.Date())

  expect_silent(mi <- as.pdb_model_info(x))
  checkmate::expect_class(mi, "pdb_model_info")
})

test_that("unused non-Stan implementation details are preserved and ignored", {
  model_info <- list(
    name = "stan-with-other-framework",
    model_implementations = list(
      stan = list(model_code = "models/stan/example.stan", stan_version = ">=2.26.0"),
      pymc = list(model_code = "models/pymc/example.py", pymc_version = ">=5.0", extra = "ignored")
    ),
    title = "Test model",
    added_by = "testthat",
    added_date = as.Date("2026-09-28")
  )

  model <- as.pdb_model_info(model_info)

  expect_identical(model$model_implementations$pymc$pymc_version, ">=5.0")
  expect_identical(model$model_implementations$stan$stan_version, ">=2.26.0")
})

test_that("empty optional string arrays from JSON are normalized", {
  testthat::local_mocked_bindings(read_json_from_pdb = function(...) {
    list(name = "empty-fields", added_date = "2026-09-28",
         references = list(), urls = list(), keywords = list())
  }, .package = "posteriordb")
  fake_pdb <- structure(list(), class = c("pdb_local", "pdb"))

  info <- posteriordb:::read_info_json("empty-fields", "posteriors", fake_pdb)

  expect_identical(info$references, character())
  expect_identical(info$urls, character())
  expect_identical(info$keywords, character())
})
