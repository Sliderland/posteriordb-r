batch_reference_info <- function(name) {
  as.reference_posterior_info(list(
    name = name,
    inference = list(method = "stan_sampling", method_arguments = list(iter = 1)),
    diagnostics = NULL, checks_made = NULL, comments = "Batch workflow test",
    added_by = "testthat", added_date = Sys.Date(), versions = NULL
  ))
}

test_that("sampling settings are shared, positional, or matched by workflow name", {
  normalize <- normalize_sequential_sampling_lists
  first <- list(iter = 10, chains = 4)
  second <- list(iter = 20, chains = 4)
  expect_identical(normalize(first, c("a", "b")), list(first, first))
  expect_identical(normalize(list(first), c("a", "b")), list(first, first))
  expect_identical(normalize(list(first, second), c("a", "b")), list(first, second))
  expect_identical(unname(normalize(list(b = second, a = first), c("a", "b"))),
                   list(first, second))
  expect_error(normalize(list(first, second), c("a", "b", "c")), "exactly one sampling list per workflow")
  expect_error(normalize("iter", "a"), "named argument list")
  expect_error(normalize(list(list(10)), "a"), "unique, non-empty names")
})

test_that("a failed workflow is recorded and later workflows follow on_error", {
  workflows <- list(a = batch_reference_info("a"), b = batch_reference_info("b"),
                    c = batch_reference_info("c"))
  seen <- list()
  testthat::local_mocked_bindings(
    compute_reference_posterior_draws = function(x, pdb, backend) {
      seen[[x$name]] <<- x$inference$method_arguments
      if (x$name == "b") stop("sampler exploded")
      paste("draws for", x$name)
    }
  )
  connection <- structure(list(), class = "pdb")
  settings <- list(list(iter = 10), list(iter = 20), list(iter = 30))

  continued <- sequential_batch_workflow(workflows, settings, pdb = connection,
                                         check = FALSE, on_error = "continue")
  expect_s3_class(continued, "sequential_batch_workflow_results")
  expect_identical(vapply(continued, `[[`, "", "status"),
                   c(a = "completed", b = "failed", c = "completed"))
  expect_identical(continued$b$stage, "sampling")
  expect_identical(continued$b$error, "sampler exploded")
  expect_identical(continued$c$draws, "draws for c")
  # The supplied settings replace the stored method arguments for the run.
  expect_identical(seen, list(a = list(iter = 10), b = list(iter = 20), c = list(iter = 30)))

  stopped <- sequential_batch_workflow(workflows, settings, pdb = connection,
                                       check = FALSE, on_error = "stop")
  expect_identical(vapply(stopped, `[[`, "", "status"),
                   c(a = "completed", b = "failed", c = "not_run"))
  expect_false(any(vapply(stopped, `[[`, NA, "written")))
})

test_that("invalid batch requests are rejected before sampling", {
  connection <- structure(list(), class = "pdb")
  workflows <- list(a = batch_reference_info("a"))
  expect_error(sequential_batch_workflow(workflows, list(), pdb = connection,
                                         check = FALSE, write = TRUE),
               "requires `check = TRUE`")
  expect_error(sequential_batch_workflow(list(), list(), pdb = connection), "non-empty list")
  expect_error(sequential_batch_workflow(list(a = workflows$a, a = workflows$a), list(),
                                         pdb = connection), "unique, non-empty")
  analytical <- workflows$a
  analytical$inference$method <- "analytical"
  expect_error(sequential_batch_workflow(list(a = analytical), list(), pdb = connection),
               "stan_sampling")
})

test_that("checked workflows return checked draws and record check failures", {
  workflows <- list(a = batch_reference_info("a"), b = batch_reference_info("b"))
  testthat::local_mocked_bindings(
    compute_reference_posterior_draws = function(x, pdb, backend) {
      structure(paste("raw", x$name), info = x)
    },
    check_reference_posterior_draws = function(x) {
      if (info(x)$name == "b") stop("check failed")
      structure(paste("checked", info(x)$name), info = info(x))
    }
  )
  results <- sequential_batch_workflow(workflows, list(iter = 10),
                                       pdb = structure(list(), class = "pdb"))
  expect_identical(as.character(results$a$draws), "checked a")
  expect_identical(results$b$stage, "checking")
  expect_identical(results$b$error, "check failed")
})

test_that("written workflows are linked and require a local database", {
  workflows <- list(a = batch_reference_info("a"))
  linked <- character()
  testthat::local_mocked_bindings(
    compute_reference_posterior_draws = function(x, pdb, backend) structure("draws", info = x),
    check_reference_posterior_draws = function(x) x,
    write_pdb = function(x, pdb, overwrite) invisible(TRUE),
    link_reference_posterior = function(posterior, reference_posterior, pdb) {
      linked <<- c(linked, posterior)
    }
  )
  results <- sequential_batch_workflow(workflows, list(iter = 10),
    pdb = structure(list(), class = c("pdb_local", "pdb")), write = TRUE)
  expect_true(results$a$written)
  expect_true(results$a$linked)
  expect_identical(linked, "a")
  expect_error(sequential_batch_workflow(workflows, list(), pdb = structure(list(), class = "pdb"),
                                         write = TRUE), "pdb_local")
})

test_that("unnamed workflows are named by their reference names", {
  testthat::local_mocked_bindings(
    compute_reference_posterior_draws = function(x, pdb, backend) paste("draws for", x$name)
  )
  results <- sequential_batch_workflow(list(batch_reference_info("a"), batch_reference_info("b")),
                                       list(), pdb = structure(list(), class = "pdb"), check = FALSE)
  expect_named(results, c("a", "b"))
})
