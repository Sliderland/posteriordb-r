# Full workflow comparison, step 2: run every write-side workflow with one
# package source tree, on fresh copies of the test fixture database, using
# the model compiled by tools/workflow-fits.R. Each scenario's return value (or
# error) and the database files it leaves behind are saved in a plain form.
# Run once with the fork and once with the rewrite, then compare the two
# folders with tools/differential-compare.R.
#   Rscript tools/workflow-run.R <package-tree> <fits-dir> <out-dir> rstan [sampling]
#   Rscript tools/workflow-run.R <package-tree> <fits-dir> <out-dir> cmdstanr <cmdstan-path> [sampling]
# "sampling-only" in place of "sampling" runs only the sampling scenarios.
# The rstan run also covers the scenarios that need no fit from a backend
# (bundles, renaming, removing, linking). Each backend gets its own process,
# because loading rstan and cmdstanr together crashed (see tools/README.md).
# With "sampling", the scenarios that run Stan themselves (dimension
# inference, compute_reference_posterior_draws via the batch workflow) run too.
args <- commandArgs(TRUE)
pkg <- args[1]; fits <- args[2]; out <- args[3]
backend <- args[4]
# "sampling-only" runs just the sampling scenarios.
sampling_only <- "sampling-only" %in% args
sampling <- sampling_only || "sampling" %in% args
dir.create(out, recursive = TRUE, showWarnings = FALSE)
if (backend == "rstan") rstan::rstan_options(boost_lib = "/usr/include")
if (backend == "cmdstanr") cmdstanr::set_cmdstan_path(args[5])
fixture_zip <- normalizePath("tests/testthat/fixtures/pdb.zip")
suppressMessages(devtools::load_all(pkg, quiet = TRUE, export_all = FALSE))
day <- as.Date("2026-01-01")

# Plain values: no classes or attributes except names and dims; dates as text.
plain <- function(x) {
  if (inherits(x, "Date")) return(as.character(x))
  if (inherits(x, "draws")) {
    a <- unclass(posterior::as_draws_array(x))
    return(list(variables = dimnames(a)[[3]], values = array(as.vector(a), dim = dim(a))))
  }
  if (is.function(x) || is.environment(x)) return("<function>")
  if (is.list(x)) {
    out <- lapply(unclass(x), plain)
    names(out) <- names(x)
    return(out)
  }
  keep <- attributes(x)[intersect(names(attributes(x)), c("names", "dim"))]
  attributes(x) <- NULL
  attributes(x) <- keep
  x
}

# Every file in a database folder: JSON parsed (zips opened), text as lines.
tree <- function(root) {
  files <- sort(list.files(root, recursive = TRUE))
  stats::setNames(lapply(files, function(f) {
    path <- file.path(root, f)
    if (grepl("[.]zip$", f)) {
      tmp <- tempfile(); dir.create(tmp)
      utils::unzip(path, exdir = tmp)
      path <- list.files(tmp, full.names = TRUE)[1]
    }
    if (grepl("[.]json([.]zip)?$", f)) jsonlite::read_json(path, simplifyVector = TRUE)
    else readLines(path, warn = FALSE)
  }), files)
}

fresh_pdb <- function() {
  dir <- tempfile("pdb"); dir.create(dir)
  utils::unzip(fixture_zip, exdir = dir)
  Sys.setenv(PDB_PATH = file.path(dir, "pdb"))
  cache <- tempfile("cache"); dir.create(cache)
  pdb_local(file.path(dir, "pdb"), cache_path = cache)
}

# A new data set, model and posterior written the same way in both packages
# (the contributing vignette's API), for workflows that need a fresh posterior.
add_test_posterior <- function(p) {
  di <- as.pdb_data_info(list(name = "test_data", title = "Test data", added_by = "Tester",
                              added_date = day))
  dat <- as.pdb_data(plain(get_data("eight_schools", pdb = p)), info = di)
  write_pdb(dat, p)
  mi <- as.pdb_model_info(list(name = "test_model", title = "Test model", framework = "stan",
                               added_by = "Tester", added_date = day))
  code <- as.character(stan_code("eight_schools_noncentered", pdb = p))
  mc <- as.model_code(code, info = mi, framework = "stan")
  write_pdb(mc, p)
  po <- as.pdb_posterior(list(pdb_model_code = mc, pdb_data = dat,
                              dimensions = list(theta_trans = 8, mu = 1, tau = 1),
                              reference_posterior_name = NULL, added_by = "Tester",
                              added_date = day), pdb = p)
  write_pdb(po, p)
  invisible(po)
}

scenario <- function(name, f) {
  if (sampling_only && !name %in% c("infer_dimensions", paste0("batch_", backend))) return(invisible())
  cat("==", name, "\n")
  p <- fresh_pdb()
  result <- tryCatch(withCallingHandlers(plain(f(p)), warning = function(w) invokeRestart("muffleWarning")),
                     error = function(e) list(error = conditionMessage(e)))
  saveRDS(list(result = result, files = tree(Sys.getenv("PDB_PATH"))), file.path(out, paste0(name, ".rds")))
}

if (backend == "rstan") {
  # Refit from the compiled cache (see workflow-fits.R): 4 chains x 2,500
  # kept draws like the stored references, and a 2-chain fit that fails the checks.
  rstan::rstan_options(auto_write = TRUE)
  es <- fresh_pdb()
  es_data <- plain(get_data("eight_schools", pdb = es))
  f <- rstan::stan(file.path(fits, "eight_schools_noncentered.stan"), data = es_data, chains = 4,
                   iter = 26000, warmup = 1000, thin = 10, seed = 4711, refresh = 0, cores = 4,
                   control = list(adapt_delta = 0.95))
  short <- rstan::stan(fit = f, data = es_data, chains = 2, iter = 2000, seed = 4711, refresh = 0)
} else {
  # Refit in this process, compiled with model methods (the same seed gives
  # the same draws): a saved CmdStanMCMC refers to a data file that no longer
  # exists, which its model methods need.
  es <- fresh_pdb()
  code <- as.character(stan_code("eight_schools_noncentered", pdb = es))
  model <- cmdstanr::cmdstan_model(cmdstanr::write_stan_file(code, dir = fits),
                                   compile_model_methods = TRUE, force_recompile = TRUE)
  f <- model$sample(data = plain(get_data("eight_schools", pdb = es)), chains = 4,
                    parallel_chains = 4, iter_warmup = 1000, iter_sampling = 25000, thin = 10,
                    seed = 4711, adapt_delta = 0.95, refresh = 0, show_messages = FALSE)
}
b <- backend
target <- "eight_schools-eight_schools_noncentered"

{
  scenario(paste0("fit_", b), function(p) {
    if (inherits(f, "stanfit")) posterior::as_draws_array(f) else f$draws()
  })
  scenario(paste0("import_", b), function(p) {
    rpd <- as_reference_posterior_draws(f, target, pdb = p, comments = "compared", added_by = "Tester",
                                        added_date = day)
    list(draws = rpd, info = info(rpd))
  })
  scenario(paste0("import_write_", b), function(p) {
    add_test_posterior(p)
    import_reference_posterior_draws(f, "test_data-test_model", pdb = p, write = TRUE,
                                     comments = "compared", added_by = "Tester", added_date = day)
    posterior("test_data-test_model", p)$reference_posterior_name
  })
  scenario(paste0("import_overwrite_", b), function(p) {
    import_reference_posterior_draws(f, target, pdb = p, write = TRUE, overwrite = TRUE,
                                     comments = "compared", added_by = "Tester", added_date = day)
    "written"
  })
  scenario(paste0("import_exclude_", b), function(p) {
    rpd <- as_reference_posterior_draws(f, target, pdb = p, exclude = "theta_trans",
                                        added_by = "Tester", added_date = day)
    posterior::variables(rpd)
  })
  scenario(paste0("import_include_none_", b), function(p) {
    rpd <- as_reference_posterior_draws(f, target, pdb = p, include = character(),
                                        added_by = "Tester", added_date = day)
    posterior::variables(rpd)
  })
  scenario(paste0("import_wrong_dimensions_", b), function(p) {
    as_reference_posterior_draws(f, target, pdb = p, dimensions = list(theta_trans = 7, mu = 1, tau = 1))
  })
  scenario(paste0("diagnostics_", b), function(p) {
    list(report = reference_draw_diagnostics(f), passes = passes_reference_draw_checks(f),
         counts = infer_unconstrained_parameter_counts_from_fit(f))
  })
  scenario(paste0("reconstruct_", b), function(p) {
    all <- if (inherits(f, "stanfit")) posterior::as_draws_array(f) else f$draws()
    draws <- posterior::subset_draws(all, iteration = 1:20)
    pars <- posterior::subset_draws(draws, variable = c("theta_trans", "mu", "tau"))
    reconstruct_stan_output(pars, f)$draws
  })
}

if (backend == "rstan") {
fit <- f
scenario("import_failing_checks", function(p) {
  rpd <- as_reference_posterior_draws(short, target, pdb = p, added_by = "Tester", added_date = day)
  list(failures = attr(rpd, "check_failures"), checks = info(rpd)$checks_made,
       write = tryCatch({ write_pdb(rpd, p, overwrite = TRUE); "written" },
                        error = function(e) "refused"))
})
scenario("bundle_new", function(p) {
  # The fork's documented call: the Stan code comes from the fit.
  b <- create_pdb_bundle(fit, data = plain(get_data("eight_schools", pdb = p)),
                         data_info = list(name = "new_schools", title = "New schools"),
                         model_info = list(name = "new_model", title = "New model", keywords = "test"),
                         reference_info = list(comments = "bundled"), pdb = p,
                         added_by = "Tester", added_date = day)
  write_pdb(b, p)
  list(posterior = b$posterior[c("name", "model_name", "data_name", "dimensions",
                                 "reference_posterior_name")],
       draws = b$reference_draws, info = info(b$reference_draws),
       check_pdb = suppressMessages(check_pdb(p, verbose = FALSE)))
})
scenario("bundle_failing", function(p) {
  b <- create_pdb_bundle(short, data = plain(get_data("eight_schools", pdb = p)),
                         data_info = list(name = "new_schools", title = "New schools"),
                         model_info = list(name = "new_model", title = "New model"), pdb = p,
                         added_by = "Tester", added_date = day)
  suppressMessages(write_pdb(b, p))
  "written"
})
scenario("bundle_by_name", function(p) {
  b <- create_pdb_bundle(fit, data = "eight_schools", model_code = "eight_schools_noncentered",
                         pdb = p, added_by = "Tester", added_date = day)
  list(posterior = b$posterior[c("name", "model_name", "data_name", "dimensions")],
       info = info(b$reference_draws))
})
scenario("rename_data", function(p) { rename_pdb("eight_schools", "schools", type = "data", pdb = p); "renamed" })
scenario("rename_model", function(p) {
  rename_pdb("eight_schools_centered", "centered", type = "model", pdb = p); "renamed"
})
scenario("rename_posterior", function(p) {
  rename_pdb("eight_schools-eight_schools_noncentered", "es", type = "posterior", pdb = p); "renamed"
})
scenario("rename_linking_posterior", function(p) {
  rename_pdb("eight_schools-eight_schools_centered", "es_centered", type = "posterior", pdb = p)
  "renamed"
})
scenario("rename_onto_existing", function(p) {
  rename_pdb("eight_schools-eight_schools_noncentered", "eight_schools-eight_schools_centered",
             type = "posterior", pdb = p)
})
scenario("remove_all", function(p) {
  po <- posterior(target, p)
  remove_pdb(reference_posterior_summary_statistic(po, "mean_value"), p)
  remove_pdb(reference_posterior_draws(po), p)
  remove_pdb(po, p)
  "removed"
})
scenario("link", function(p) {
  add_test_posterior(p)
  link_reference_posterior("test_data-test_model", target, pdb = p)
  posterior("test_data-test_model", p)$reference_posterior_name
})
}

if (sampling) {
  rpi_for <- function(p) {
    rpi <- reference_posterior_info(target, type = "draws", pdb = p)
    rpi$inference$method_arguments <- list(chains = 4L, iter = 26000L, warmup = 1000L, thin = 10L,
                                           seed = 4711L, control = list(adapt_delta = 0.95))
    rpi
  }
  if (backend == "rstan") scenario("infer_dimensions", function(p) {
    infer_posterior_dimensions(stan_code("eight_schools_noncentered", pdb = p),
                               plain(get_data("eight_schools", pdb = p)))
  })
  scenario(paste0("batch_", b), function(p) {
    sequential_batch_workflow(list(rpi_for(p)), sampling = rpi_for(p)$inference$method_arguments,
                              pdb = p, backend = b, write = TRUE, overwrite = TRUE)
  })
}
cat("Saved", out, "\n")
