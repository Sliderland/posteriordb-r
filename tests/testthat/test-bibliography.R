context("test-bibliography")

test_that("bibliography works as expected", {
  assert_pdb_path_exists()
  expect_silent(pdb_test <- pdb_local())
  expect_silent(bib <- bibliography(pdb_test))

})

test_that("append_reference accepts strings and bibentry objects", {
  root <- tempfile("pdb-bibliography-")
  dir.create(file.path(root, "bibliography"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  reference_path <- file.path(root, "bibliography", "references.bib")
  writeLines(character(), reference_path)
  pdb <- structure(
    list(pdb_local_endpoint = root, cache_path = tempfile("pdb-cache-")),
    class = c("pdb_local", "pdb")
  )
  dir.create(pdb$cache_path)
  on.exit(unlink(pdb$cache_path, recursive = TRUE), add = TRUE)

  first <- paste0(
    "@article{first, title={First}, author={Doe, Jane}, ",
    "journal={Journal}, year={2020}}"
  )
  expect_true(append_reference(first, pdb))

  second <- utils::bibentry(
    "Book", key = "second", title = "Second",
    author = utils::person("John", "Roe"), publisher = "Press", year = "2021"
  )
  third <- utils::bibentry(
    "Misc", key = "third", title = "Third", year = "2022"
  )
  expect_true(append_reference(c(second, third), pdb))
  expect_equal(length(bibtex::read.bib(reference_path)), 3L)
})

test_that("append_reference rejects duplicate keys and entries without writing", {
  root <- tempfile("pdb-bibliography-")
  dir.create(file.path(root, "bibliography"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  reference_path <- file.path(root, "bibliography", "references.bib")
  original <- paste0(
    "@article{original, title={Same}, author={Doe, Jane}, ",
    "journal={Journal}, year={2020}}"
  )
  writeLines(original, reference_path)
  pdb <- structure(
    list(pdb_local_endpoint = root, cache_path = tempfile("pdb-cache-")),
    class = c("pdb_local", "pdb")
  )
  dir.create(pdb$cache_path)
  on.exit(unlink(pdb$cache_path, recursive = TRUE), add = TRUE)

  duplicate_key <- sub("original", "ORIGINAL", original, fixed = TRUE)
  expect_error(append_reference(duplicate_key, pdb), "`original` and `ORIGINAL`")
  expect_identical(readLines(reference_path), original)

  duplicate_entry <- sub("original", "another-key", original, fixed = TRUE)
  expect_error(append_reference(duplicate_entry, pdb), "`original` and `another-key`")
  expect_identical(readLines(reference_path), original)
})

test_that("append_reference identifies duplicates within supplied references", {
  root <- tempfile("pdb-bibliography-")
  dir.create(file.path(root, "bibliography"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  reference_path <- file.path(root, "bibliography", "references.bib")
  writeLines(character(), reference_path)
  pdb <- structure(
    list(pdb_local_endpoint = root, cache_path = tempdir()),
    class = c("pdb_local", "pdb")
  )
  refs <- c(
    utils::bibentry("Misc", key = "first", title = "Same", year = "2020"),
    utils::bibentry("Misc", key = "second", title = "Same", year = "2020")
  )
  expect_error(append_reference(refs, pdb), "`first` and `second`")
  expect_identical(readLines(reference_path), character())
})
