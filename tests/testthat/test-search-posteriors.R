context("test-search-posteriors")

search_test_pdb <- function(empty = FALSE) {
  root <- tempfile("posteriordb-search-")
  dir.create(file.path(root, "posteriors"), recursive = TRUE)
  dir.create(file.path(root, "data", "info"), recursive = TRUE)
  dir.create(file.path(root, "models", "info"), recursive = TRUE)

  if (!empty) {
    write_info <- function(value, path) {
      jsonlite::write_json(value, file.path(root, path), auto_unbox = TRUE)
    }
    write_info(
      list(
        name = "data_a-model_a", data_name = "data_a",
        model_name = "model_a",
        keywords = c("pathfinder", "time series", "A.B literal")
      ),
      "posteriors/data_a-model_a.json"
    )
    write_info(
      list(
        name = "data_a-model_b", data_name = "data_a",
        model_name = "model_b", keywords = c("other", "time series")
      ),
      "posteriors/data_a-model_b.json"
    )
    write_info(
      list(
        name = "data_a", data_file = "data/data/data_a.json",
        title = "Data A", added_by = "tester", added_date = "2026-01-01",
        keywords = c("BDA3_example", "time series")
      ),
      "data/info/data_a.info.json"
    )
    model <- function(name, keywords) {
      list(
        name = name, title = name, added_by = "tester",
        added_date = "2026-01-01", keywords = keywords,
        model_implementations = list(stan = list(
          model_code = paste0("models/stan/", name, ".stan")
        ))
      )
    }
    write_info(
      model("model_a", c("HIEARCHICAL", "time series")),
      "models/info/model_a.info.json"
    )
    write_info(model("model_b", "unrelated"), "models/info/model_b.info.json")
    # Entries with no posterior link must not be read to answer the query.
    write_info(list(name = "orphan"), "data/info/orphan.info.json")
  }

  cache <- tempfile("posteriordb-search-cache-")
  dir.create(cache)
  pdb_local(root, cache_path = cache)
}

test_that("searches keywords across linked posterior, data, and model metadata", {
  pdb <- search_test_pdb()

  posterior_match <- search_posteriors(pdb, "PATHFINDER", "posterior")
  expect_equal(posterior_match$posterior_name, "data_a-model_a")
  expect_equal(posterior_match$matched_in, "posterior")
  expect_equal(posterior_match$matched_keywords, "pathfinder")

  data_match <- search_posteriors(pdb, "bda3_EXAMPLE", "data")
  expect_equal(data_match$posterior_name, c("data_a-model_a", "data_a-model_b"))
  expect_true(all(data_match$matched_in == "data"))

  model_match <- search_posteriors(pdb, "HIEARCHICAL", "model")
  expect_equal(model_match$posterior_name, "data_a-model_a")
  expect_equal(model_match$matched_in, "model")

  expect_equal(
    search_posteriors(pdb, "A.B", "posterior")$posterior_name,
    "data_a-model_a"
  )
  expect_equal(nrow(search_posteriors(pdb, "A.B", "model")), 0L)
})

test_that("any and all apply to selected scopes and preserve empty schema", {
  pdb <- search_test_pdb()

  any_match <- search_posteriors(pdb, "time series", match = "any")
  expect_equal(any_match$posterior_name, c("data_a-model_a", "data_a-model_b"))
  expect_equal(any_match$matched_in, c("posterior, data, model", "posterior, data"))

  all_match <- search_posteriors(pdb, "time series", match = "all")
  expect_equal(all_match$posterior_name, "data_a-model_a")
  expect_equal(
    search_posteriors(pdb, "time series", c("posterior", "data"), "all")$posterior_name,
    c("data_a-model_a", "data_a-model_b")
  )

  empty <- search_posteriors(pdb, "does-not-exist")
  expect_s3_class(empty, "tbl_df")
  expect_equal(nrow(empty), 0L)
  expect_named(empty, c(
    "posterior_name", "data_name", "model_name", "matched_in",
    "matched_keywords"
  ))
  expect_identical(search_posteriors(search_test_pdb(empty = TRUE), "x"), empty)
})

test_that("validates search arguments", {
  pdb <- search_test_pdb()

  expect_error(search_posteriors(pdb, "x", fields = "unknown"))
  expect_error(search_posteriors(pdb, "x", fields = character()))
  expect_error(search_posteriors(pdb, "x", fields = c("data", "data")))
  expect_error(search_posteriors(pdb, "x", match = "unknown"))
  expect_error(search_posteriors(pdb, ""))
})

test_that("the metadata reader dispatches for character names", {
  pdb <- search_test_pdb()
  record <- posteriordb:::read_info_json(
    "data_a-model_a", path = "posteriors", pdb = pdb
  )
  expect_equal(record$name, "data_a-model_a")
})
