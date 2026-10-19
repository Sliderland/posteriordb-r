# Full workflow comparison, step 1: compile the eight schools (non-centred)
# model once for rstan, into rstan's auto_write cache next to its code:
#   Rscript tools/workflow-fits.R <out-dir> rstan
# A stanfit read back from disk has lost its compiled model, which
# unconstrained parameter names and reconstruct_stan_output() need. So
# tools/workflow-run.R refits in each R process, from this cache for rstan
# and with a fresh compile for cmdstanr, always with the same seed. That
# gives the same draws every time; the fit_<backend> scenarios record them,
# so a comparison shows if they ever differ.
args <- commandArgs(TRUE)
out <- args[1]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
fixture <- tempfile("fixture"); dir.create(fixture)
utils::unzip("tests/testthat/fixtures/pdb.zip", exdir = fixture)
code <- readLines(file.path(fixture, "pdb", "models/stan/eight_schools_noncentered.stan"))
if (identical(args[2], "rstan")) {
  rstan::rstan_options(boost_lib = "/usr/include", auto_write = TRUE)
  writeLines(code, file.path(out, "eight_schools_noncentered.stan"))
  rstan::stan_model(file.path(out, "eight_schools_noncentered.stan"))
}
cat("Compiled model saved in", out, "\n")
