context("test-search-posteriors")

test_that("searches posterior, data, and model keywords", {
  assert_pdb_path_exists()
  pdb_test <- pdb_local()

  posterior_match <- search_posteriors(
    pdb = pdb_test,
    query = "pathfinder",
    fields = "posterior"
  )
  expect_true(
    "eight_schools-eight_schools_noncentered" %in%
      posterior_match$posterior_name
  )
  expect_true(all(posterior_match$matched_in == "posterior"))
  expect_true(any(grepl("pathfinder", posterior_match$matched_keywords)))

  data_match <- search_posteriors(
    pdb = pdb_test,
    query = "BDA3_EXAMPLE",
    fields = "data"
  )
  expect_true("eight_schools" %in% data_match$data_name)
  expect_true(all(data_match$matched_in == "data"))

  model_match <- search_posteriors(
    pdb = pdb_test,
    query = "HIEARCHICAL",
    fields = "model"
  )
  expect_true(
    "eight_schools-eight_schools_noncentered" %in%
      model_match$posterior_name
  )
  expect_true(all(model_match$matched_in == "model"))
})

test_that("supports any/all matching and empty results", {
  assert_pdb_path_exists()
  pdb_test <- pdb_local()

  any_match <- search_posteriors(
    pdb = pdb_test,
    query = "pathfinder",
    fields = c("posterior", "model"),
    match = "any"
  )
  all_match <- search_posteriors(
    pdb = pdb_test,
    query = "pathfinder",
    fields = c("posterior", "model"),
    match = "all"
  )

  expect_gt(nrow(any_match), 0L)
  expect_equal(nrow(all_match), 0L)

  cross_scope_match <- search_posteriors(
    pdb = pdb_test,
    query = "time series",
    match = "all"
  )
  expect_gt(nrow(cross_scope_match), 0L)
  expect_true(all(
    cross_scope_match$matched_in == "posterior, data, model"
  ))

  expect_named(
    search_posteriors(pdb_test, "does-not-exist"),
    c(
      "posterior_name",
      "data_name",
      "model_name",
      "matched_in",
      "matched_keywords"
    )
  )
})

test_that("validates search arguments", {
  assert_pdb_path_exists()
  pdb_test <- pdb_local()

  expect_error(search_posteriors(pdb_test, "x", fields = "unknown"))
  expect_error(search_posteriors(pdb_test, "x", fields = character()))
  expect_error(search_posteriors(pdb_test, "x", match = "unknown"))
  expect_error(search_posteriors(pdb_test, ""))
})
