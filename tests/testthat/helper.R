# A writable copy of the small fixture database (eight schools), removed
# when the calling test ends. It is zipped because its paths are too long
# for a portable package tarball.
local_pdb <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  utils::unzip(test_path("fixtures", "pdb.zip"), exdir = dir)
  pdb_local(file.path(dir, "pdb"), cache_path = withr::local_tempdir(.local_envir = env))
}

# Independent draws that pass every reference check: `chains` x `iterations`
# draws of the eight schools parameters.
iid_draws <- function(chains = 4, iterations = 2500, seed = 1) {
  set.seed(seed)
  vars <- c(paste0("theta[", 1:8, "]"), "mu", "tau")
  arr <- array(stats::rnorm(iterations * chains * length(vars)),
               dim = c(iterations, chains, length(vars)), dimnames = list(NULL, NULL, vars))
  arr[, , "tau"] <- abs(arr[, , "tau"])
  posterior::as_draws_array(arr)
}

# Sampler diagnostics matching `draws`: no divergences, healthy energy.
iid_sampler <- function(draws, divergent = 0) {
  dims <- dim(draws)[1:2]
  arr <- array(0, dim = c(dims, 2), dimnames = list(NULL, NULL, c("divergent__", "energy__")))
  arr[, , "energy__"] <- stats::rnorm(prod(dims))
  arr[seq_len(divergent), 1, "divergent__"] <- 1
  posterior::as_draws_array(arr)
}

reference_info <- function(name = "eight_schools-eight_schools_noncentered", method = "stan_sampling") {
  list(name = name, inference = list(method = method, method_arguments = list()),
       added_by = "Test", added_date = as.Date("2026-01-01"))
}

checked_iid_draws <- function(...) {
  draws <- iid_draws(...)
  rpd <- as.reference_posterior_draws(draws, info = reference_info())
  attr(rpd, "sampler_diagnostics") <- iid_sampler(draws)
  check_reference_posterior_draws(rpd)
}

# A stand-in for cmdstanr::CmdStanMCMC with the methods extract_fit() uses.
mock_cmdstan_fit <- function(draws = iid_draws(), sampler = iid_sampler(draws), code = NULL,
                             parameters = c("theta", "mu", "tau")) {
  lp <- posterior::as_draws_array(array(0, dim = c(dim(draws)[1:2], 1),
                                        dimnames = list(NULL, NULL, "lp__")))
  with_lp <- posterior::bind_draws(lp, draws, along = "variable")
  structure(list(
    draws = function(...) with_lp,
    sampler_diagnostics = function(...) sampler,
    metadata = function() list(iter_sampling = dim(draws)[1], iter_warmup = 1000, thin = 1,
                                seed = 1, adapt_delta = 0.8, max_treedepth = 10),
    variable_skeleton = function(...) stats::setNames(vector("list", length(parameters)), parameters),
    unconstrain_draws = function(...) stop("model methods are not compiled"),
    code = function() code %||% stop("no code")
  ), class = c("CmdStanMCMC", "CmdStanFit", "R6"))
}

skip_unless_env <- function(var) {
  if (!identical(Sys.getenv(var), "true")) skip(paste0("Set ", var, "=true to run"))
}
