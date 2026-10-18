# Differential test of writing: one package source tree writes a new data
# set, model and posterior (the objects from upstream's contributing
# vignette) into a fresh copy of the test fixture database. Run it with the
# fork and with the rewrite, then compare the two folders file by file:
#   Rscript tools/differential-write.R <package-tree> <out-dir>
#   diff -r <fork-out>/pdb <rewrite-out>/pdb
args <- commandArgs(TRUE)
suppressMessages(devtools::load_all(args[1], quiet = TRUE, export_all = FALSE))
dir.create(args[2], recursive = TRUE, showWarnings = FALSE)
fixture <- normalizePath("tests/testthat/fixtures/pdb.zip")
utils::unzip(fixture, exdir = args[2])
cache <- tempfile("pdbcache"); dir.create(cache)
# As in the vignette, the database is also the default one.
Sys.setenv(PDB_PATH = file.path(args[2], "pdb"))
pdbl <- pdb_local(file.path(args[2], "pdb"), cache_path = cache)
day <- as.Date("2026-01-01")

di <- as.pdb_data_info(list(name = "test_data", keywords = "test_data", title = "Test data",
                            description = "Eight schools.", urls = "https://example.org",
                            references = "rubin1981estimation", added_date = day, added_by = "Tester"))
dat <- as.pdb_data(list(J = 8L, y = c(28, 8, -3, 7, -1, 1, 18, 12), sigma = c(15, 10, 16, 11, 9, 11, 10, 18)),
                   info = di)
write_pdb(dat, pdbl)
mi <- as.pdb_model_info(list(name = "test_model", keywords = c("test_model", "hierarchical"),
                             title = "Test model", description = "Non-centered.",
                             urls = "https://example.org", framework = "stan",
                             added_by = "Tester", added_date = day))
code <- paste(readLines(file.path(args[2], "pdb", "models", "stan", "eight_schools_noncentered.stan")),
              collapse = "\n")
mc <- as.model_code(code, info = mi, framework = "stan")
write_pdb(mc, pdbl)
po <- as.pdb_posterior(list(pdb_model_code = mc, pdb_data = dat, keywords = "test",
                            references = "rubin1981estimation",
                            dimensions = list(theta_trans = 8, mu = 1, tau = 1),
                            reference_posterior_name = NULL, added_date = day, added_by = "Tester"))
write_pdb(po, pdbl)
cat("Wrote to", args[2], "\n")
