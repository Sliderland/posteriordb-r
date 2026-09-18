context("test-bibliography")

local_bibliography_fixture <- function(contents = character()) {
  root <- tempfile("pdb-bibliography-")
  cache <- tempfile("pdb-cache-")
  dir.create(file.path(root, "bibliography"), recursive = TRUE)
  dir.create(cache)
  reference_path <- file.path(root, "bibliography", "references.bib")
  writeLines(contents, reference_path)
  pdb <- structure(
    list(pdb_local_endpoint = root, cache_path = cache),
    class = c("pdb_local", "pdb")
  )
  list(root = root, cache = cache, path = reference_path, pdb = pdb)
}

test_that("bibliography works as expected", {
  fixture <- local_bibliography_fixture("@misc{one, title={One}}")
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)
  expect_length(bibliography(fixture$pdb), 1L)
})

test_that("append_reference accepts strings and bibentry objects", {
  fixture <- local_bibliography_fixture()
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)
  pdb <- fixture$pdb

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
  expect_equal(length(bibtex::read.bib(fixture$path)), 3L)
})

test_that("append_reference rejects duplicate keys and entries without writing", {
  original <- paste0(
    "@article{original, title={Same}, author={Doe, Jane}, ",
    "journal={Journal}, year={2020}}"
  )
  fixture <- local_bibliography_fixture(original)
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)
  pdb <- fixture$pdb

  duplicate_key <- sub("original", "ORIGINAL", original, fixed = TRUE)
  expect_error(append_reference(duplicate_key, pdb), "`original` and `ORIGINAL`")
  expect_identical(readLines(fixture$path), original)

  duplicate_entry <- sub("original", "another-key", original, fixed = TRUE)
  expect_error(append_reference(duplicate_entry, pdb), "`original` and `another-key`")
  expect_identical(readLines(fixture$path), original)
})

test_that("append_reference identifies duplicates within supplied references", {
  fixture <- local_bibliography_fixture()
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)
  pdb <- fixture$pdb
  refs <- c(
    utils::bibentry("Misc", key = "first", title = "Same", year = "2020"),
    utils::bibentry("Misc", key = "second", title = "Same", year = "2020")
  )
  expect_error(append_reference(refs, pdb), "`first` and `second`")
  expect_identical(readLines(fixture$path), character())
})

test_that("append_reference imports multiple entries from a .bib file", {
  fixture <- local_bibliography_fixture("@misc{original, title={Original}}")
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)
  input <- tempfile(fileext = ".bib")
  on.exit(unlink(input), add = TRUE)
  writeLines(c(
    "% @misc{also-fake, title={Ignored}}",
    "@string{journal = {Journal}}",
    "@comment{ A quoted \"@article{fake, title={Ignored}} }",
    paste0("@article{second, title={Text @article{fake, example}}, ",
           "author={Doe, Jane}, journal=journal, year={2020}}"),
    "@misc{third, title={Third}}"
  ), input)

  expect_length(bibliography(fixture$pdb), 1L)
  cache_path <- file.path(fixture$cache, "bibliography", "references.bib")
  expect_true(file.exists(cache_path))
  expect_true(append_reference(input, fixture$pdb))
  expect_false(file.exists(cache_path))
  expect_length(bibliography(fixture$pdb), 3L)
})

test_that("append_reference rejects invalid files and entries without writing", {
  fixture <- local_bibliography_fixture("@misc{original, title={Original}}")
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)
  input <- tempfile(fileext = ".bib")
  on.exit(unlink(input), add = TRUE)

  writeLines(c("@misc{new, title={New}}", "@unknown{bad, title={Bad}}"), input)
  expect_error(append_reference(input, fixture$pdb), "invalid or unsupported")
  expect_identical(readLines(fixture$path), "@misc{original, title={Original}}")

  writeLines(c("@misc{new, title={New}}", "@unknown{bad}"), input)
  expect_error(append_reference(input, fixture$pdb), "invalid or unsupported")
  expect_identical(readLines(fixture$path), "@misc{original, title={Original}}")

  writeLines(c("@misc{new, title={New}}", "@misc{NEW, title={Other}}"), input)
  expect_error(append_reference(input, fixture$pdb), "`new` and `NEW`")
  expect_identical(readLines(fixture$path), "@misc{original, title={Original}}")

  no_key <- utils::bibentry("Misc", title = "No key")
  expect_error(append_reference(no_key, fixture$pdb), "invalid or unsupported")
  expect_identical(readLines(fixture$path), "@misc{original, title={Original}}")
  expect_error(append_reference(
    "@misc{one, title={One}}\n@misc{two, title={Two}}", fixture$pdb
  ), "exactly one")
  expect_identical(readLines(fixture$path), "@misc{original, title={Original}}")
  expect_error(append_reference(paste0(input, "-missing.bib"), fixture$pdb),
               "file does not exist")
})

test_that("append_reference refuses an invalid existing bibliography", {
  original <- c(
    "@misc{original, title={Original}}",
    "@unknown{ignored, title={Ignored}}"
  )
  fixture <- local_bibliography_fixture(original)
  on.exit(unlink(c(fixture$root, fixture$cache), recursive = TRUE), add = TRUE)

  expect_error(append_reference("@misc{new, title={New}}", fixture$pdb),
               "existing bibliography contains an invalid or unsupported")
  expect_identical(readLines(fixture$path), original)
})
