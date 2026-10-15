# Runs the non-Stan steps of upstream's contributing vignette
# (stan-dev/posteriordb-r, vignettes/contributing.Rmd) against this package,
# on a throwaway copy of the test fixture database: add data, a model and a
# posterior, check the posterior, create reference posterior info, and
# remove everything again.
#   Rscript tools/vignette-flow.R            (from the package root)
suppressMessages(devtools::load_all(".", quiet = TRUE))
dir <- tempfile("vignette"); dir.create(dir)
utils::unzip("tests/testthat/fixtures/pdb.zip", exdir = dir)
Sys.setenv(PDB_PATH = file.path(dir, "pdb"))
pdbl <- pdb_local()

x <- list(name = "test_eight_schools_data", keywords = c("test_data"),
          title = "A Test Data for the Eight Schools Model",
          description = "The data contain data from eight schools on SAT scores.",
          urls = "https://cran.r-project.org/web/packages/rstan/vignettes/rstan.html",
          references = "rubin1981estimation", added_date = Sys.Date(), added_by = "Stanislaw Ulam")
di <- as.pdb_data_info(x)
dat <- as.pdb_data(list(J = 8L, y = as.integer(c(28, 8, -3, 7, -1, 1, 18, 12)),
                        sigma = as.integer(c(15, 10, 16, 11, 9, 11, 10, 18))), info = di)
write_pdb(dat, pdbl, overwrite = TRUE)

x <- list(name = "test_eight_schools_model", keywords = c("test_model", "hierarchical"),
          title = "Test Non-Centered Model for Eight Schools",
          description = "An hierarchical model, non-centered parametrisation.",
          urls = c("https://cran.r-project.org/web/packages/rstan/vignettes/rstan.html"),
          framework = "stan", references = NULL, added_by = "Stanislaw Ulam", added_date = Sys.Date())
mi <- as.pdb_model_info(x)
smc <- as.character(stan_code("eight_schools_noncentered", pdb = pdbl))
mc <- as.model_code(smc, info = mi, framework = "stan")
write_pdb(mc, pdbl, overwrite = TRUE)

x <- list(pdb_model_code = mc, pdb_data = dat, keywords = "posterior_keywords",
          urls = "posterior_urls", references = "rubin1981estimation",
          dimensions = list("dimensions" = 2, "dim" = 3), reference_posterior_name = NULL,
          added_date = Sys.Date(), added_by = "Stanislaw Ulam")
po <- as.pdb_posterior(x)
write_pdb(po, pdbl, overwrite = TRUE)
stopifnot(isTRUE(check_pdb_posterior(po, run_stan_code_checks = FALSE)))

po <- posterior("test_eight_schools_data-test_eight_schools_model", pdbl)
x <- list(name = posterior_name(po),
          inference = list(method = "stan_sampling",
                           method_arguments = list(chains = 10, iter = 20000, warmup = 10000,
                                                   thin = 10, seed = 4711,
                                                   control = list(adapt_delta = 0.92))),
          diagnostics = NULL, checks_made = NULL, comments = "This is a test reference posterior",
          added_by = "Stanislaw Ulam", added_date = Sys.Date(), versions = NULL)
rpi <- as.pdb_reference_posterior_info(x)
stopifnot(inherits(rpi, "pdb_reference_posterior_info"))
# The vignette's next step, compute_reference_posterior_draws(rpi, pdbl),
# samples 10 x 20,000 iterations with rstan; tests/testthat/test-stan.R
# covers that path with a smaller run.

invisible(remove_pdb(mc, pdbl)); invisible(remove_pdb(dat, pdbl)); invisible(remove_pdb(po, pdbl))
unlink(dir, recursive = TRUE)
cat("Vignette flow ok.\n")
