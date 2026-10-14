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
        name = "data_a-model_a",
        data_name = "data_a",
        model_name = "model_a",
        added_by = "tester",
        added_date = "2026-01-01",
        keywords = c("pathfinder", "time series", "A.B literal")
      ),
      "posteriors/data_a-model_a.json"
    )
    write_info(
      list(
        name = "data_a-model_b",
        data_name = "data_a",
        model_name = "model_b",
        keywords = c("other", "time series"),
        added_by = "tester",
        added_date = "2026-01-01"
      ),
      "posteriors/data_a-model_b.json"
    )
    write_info(
      list(
        name = "data_a",
        data_file = "data/data/data_a.json",
        title = "Data A",
        added_by = "tester",
        added_date = "2026-01-01",
        keywords = c("BDA3_example", "time series")
      ),
      "data/info/data_a.info.json"
    )
    model <- function(name, keywords) {
      list(
        name = name,
        title = name,
        added_by = "tester",
        added_date = "2026-01-01",
        keywords = keywords,
        model_implementations = list(
          stan = list(
            model_code = paste0("models/stan/", name, ".stan")
          )
        )
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

test_that("the metadata reader dispatches for character names", {
  pdb <- search_test_pdb()
  record <- posteriordb:::read_info_json(
    "data_a-model_a",
    path = "posteriors",
    pdb = pdb
  )
  expect_equal(record$name, "data_a-model_a")
})
