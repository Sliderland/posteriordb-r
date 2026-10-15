# The reference posterior definition, in one place. See
# https://github.com/stan-dev/posteriordb/blob/master/doc/REFERENCE_POSTERIOR_DEFINITION.md
reference_policy <- function() {
  list(ndraws = 10000L, nchains = 4L, r_hat = 1.01, mean_lag1_ac = 0.05,
       efmi = 0.2, divergent_transitions = 0L)
}

# Stored flag name for each check, as used in `checks_made`.
check_flag_names <- function(summary = FALSE) {
  c(ndraws = if (summary) "ndraws_is_gte_10k" else "ndraws_is_10k",
    nchains = "nchains_is_gte_4", r_hat = "r_hat_below_1_01",
    mean_lag1_ac = "abs_mean_lag1_ac_below_0_05", efmi = "efmi_above_0_2",
    divergent_transitions = "no_divergent_transitions")
}

all_checks <- function() names(check_flag_names())

# Diagnostics of a set of draws, in the format stored in reference posterior
# info files. Chain-level sampler diagnostics (divergences, E-FMI) come from
# `sampler` (a draws_array of sampler parameters) when given, otherwise they
# are carried over from `previous` diagnostics.
compute_draw_diagnostics <- function(draws, method = "stan_sampling", sampler = NULL,
                                     previous = NULL) {
  draws <- posterior::as_draws_array(draws)
  vars <- posterior::variables(draws)
  d <- list(diagnostic_information = list(names = vars),
            ndraws = posterior::ndraws(draws), nchains = posterior::nchains(draws))
  if (method != "stan_sampling") return(d)
  per_variable <- function(fun) {
    unname(vapply(vars, function(v) {
      tryCatch(as.numeric(fun(posterior::extract_variable_matrix(draws, v))),
               error = function(e) NA_real_)
    }, numeric(1)))
  }
  d$effective_sample_size_bulk <- per_variable(posterior::ess_bulk)
  d$effective_sample_size_tail <- per_variable(posterior::ess_tail)
  d$r_hat <- per_variable(posterior::rhat)
  d$mean_lag1_ac <- per_variable(mean_lag1_autocorrelation)
  if (!is.null(sampler)) {
    d$divergent_transitions <- sampler_divergences(sampler)
    d$expected_fraction_of_missing_information <- sampler_efmi(sampler)
  } else {
    d$divergent_transitions <- previous$divergent_transitions
    d$expected_fraction_of_missing_information <- previous$expected_fraction_of_missing_information
  }
  d
}

# Mean over chains of the lag-1 autocorrelation of one variable
# (an iterations x chains matrix). Constant chains give NA.
mean_lag1_autocorrelation <- function(x) {
  x <- as.matrix(x)
  ac <- apply(x, 2, function(z) {
    z <- z - mean(z)
    denominator <- sum(z^2)
    if (length(z) < 2 || !is.finite(denominator) || denominator == 0) return(NA_real_)
    sum(z[-1] * z[-length(z)]) / denominator
  })
  mean(ac)
}

sampler_divergences <- function(sampler) {
  if (!"divergent__" %in% posterior::variables(sampler)) return(NULL)
  m <- posterior::extract_variable_matrix(sampler, "divergent__")
  unname(colSums(m))
}

# E-FMI per chain, with the normalisation used by rstan::get_bfmi() and the
# values stored in posteriordb.
sampler_efmi <- function(sampler) {
  if (!"energy__" %in% posterior::variables(sampler)) return(NULL)
  m <- posterior::extract_variable_matrix(sampler, "energy__")
  unname(apply(m, 2, function(e) sum(diff(e)^2) / length(e) / stats::var(e)))
}

# Named metrics for each check, from stored-format diagnostics.
diagnostic_metrics <- function(d) {
  chains <- if (!is.null(d$nchains)) paste0("chain", seq_len(d$nchains))
  vars <- d$diagnostic_information$names
  label <- function(x, labels) {
    if (is.null(x)) return("unavailable")
    x <- as.numeric(unlist(x))
    if (length(x) == length(labels)) names(x) <- labels
    x
  }
  list(ndraws = d$ndraws, nchains = d$nchains,
       r_hat = label(d$r_hat, vars), mean_lag1_ac = label(d$mean_lag1_ac, vars),
       efmi = label(d$expected_fraction_of_missing_information, chains),
       divergent_transitions = label(d$divergent_transitions, chains))
}

# Evaluate the reference posterior definition on stored-format diagnostics.
# Returns the logical `status` of each check, `failures` (offending variables
# or chains, or "unavailable"), and the flags to store as `checks_made`.
evaluate_reference_checks <- function(d, method = "stan_sampling", summary = FALSE,
                                      checks = all_checks()) {
  if (method != "stan_sampling") checks <- intersect(checks, "ndraws")
  policy <- reference_policy()
  metrics <- diagnostic_metrics(d)
  status <- list()
  failures <- list()
  for (key in checks) {
    x <- metrics[[key]]
    n_expected <- if (key %in% c("efmi", "divergent_transitions")) d$nchains else
      length(d$diagnostic_information$names)
    if (!is.numeric(x) || !length(x) ||
        (key %in% c("r_hat", "mean_lag1_ac", "efmi", "divergent_transitions") &&
         length(x) != n_expected)) {
      status[[key]] <- FALSE
      failures[[key]] <- "unavailable"
      next
    }
    # Undefined values (e.g. R-hat of a constant variable) fail.
    bad <- is.na(x) | switch(key,
      ndraws = if (summary) x < policy$ndraws else x != policy$ndraws,
      nchains = x < policy$nchains,
      r_hat = x > policy$r_hat,
      mean_lag1_ac = abs(x) > policy$mean_lag1_ac,
      efmi = x < policy$efmi,
      divergent_transitions = x > policy$divergent_transitions) %in% TRUE
    status[[key]] <- !any(bad)
    if (any(bad)) {
      failures[[key]] <- if (key %in% c("ndraws", "nchains")) x else names(x)[bad] %||% which(bad)
    }
  }
  flags <- stats::setNames(status, check_flag_names(summary)[names(status)])
  if (method == "stan_sampling") flags$ess_within_bounds <- ess_within_bounds(d)
  list(status = status, failures = failures, checks_made = flags)
}

# Informational only: is ESS within 4 approximate SDs of the number of draws?
ess_within_bounds <- function(d) {
  ess <- c(unlist(d$effective_sample_size_bulk), unlist(d$effective_sample_size_tail))
  bound <- 4 * sqrt(7 * d$ndraws)
  length(ess) > 0 && !anyNA(ess) && all(abs(ess - d$ndraws) <= bound)
}

format_failures <- function(failures) {
  paste(vapply(names(failures), function(key) {
    paste0(key, " (", paste(utils::head(failures[[key]], 5), collapse = ", "),
           if (length(failures[[key]]) > 5) ", ...", ")")
  }, ""), collapse = "; ")
}

#' Check reference posterior draws
#'
#' Checks draws against the
#' [reference posterior definition](https://github.com/stan-dev/posteriordb/blob/master/doc/REFERENCE_POSTERIOR_DEFINITION.md).
#' All reference draws need exactly 10,000 draws. Draws computed with Stan
#' (`inference$method == "stan_sampling"`) also need at least 4 chains,
#' R-hat at most 1.01 and absolute mean lag-1 autocorrelation at most 0.05 for
#' every variable, E-FMI at least 0.2 in every chain, and no divergent
#' transitions. Whether the effective sample sizes are close to the number of
#' draws is recorded as `ess_within_bounds` but does not decide the check.
#'
#' R-hat, ESS and autocorrelation are recomputed from the draws.
#' Divergences and E-FMI come from the sampler diagnostics kept when the draws
#' were made from a fit, or from the stored diagnostics otherwise.
#'
#' @param x Reference posterior draws, a posterior, a posterior name, or a
#'   bundle from [create_pdb_bundle()].
#' @param error If `TRUE`, failed checks raise an error. If `FALSE`, the
#'   object is returned with the failures recorded.
#' @param ... Passed to [posterior()] for a posterior name.
#' @return `x` with updated `diagnostics` and `checks_made` in its info,
#'   invisibly. With `error = FALSE`, failures are in the `check_failures`
#'   attribute.
#' @export
check_reference_posterior_draws <- function(x, ...) UseMethod("check_reference_posterior_draws")

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.character <- function(x, ...) {
  check_reference_posterior_draws(reference_posterior_draws(posterior(x, ...)))
}

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.pdb_posterior <- function(x, ...) {
  check_reference_posterior_draws(reference_posterior_draws(x), ...)
}

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.pdb_reference_posterior_draws <- function(x, error = TRUE, ...) {
  check_draws(x, error = error)
}

check_draws <- function(x, error = TRUE, summary = FALSE) {
  rpi <- info(x)
  if (posterior::nvariables(x) == 0L) stop2("The reference draws have no variables.")
  rpi$diagnostics <- compute_draw_diagnostics(x, rpi$inference$method,
                                              sampler = attr(x, "sampler_diagnostics"),
                                              previous = rpi$diagnostics)
  result <- evaluate_reference_checks(rpi$diagnostics, rpi$inference$method, summary = summary)
  rpi$checks_made <- result$checks_made
  info(x) <- rpi
  attr(x, "check_failures") <- if (length(result$failures)) result$failures
  if (error && length(result$failures)) {
    stop2("Reference posterior '", rpi$name, "' failed the checks: ",
          format_failures(result$failures))
  }
  invisible(x)
}

# Did the last check pass?
passed_checks <- function(x) {
  flags <- info(x)$checks_made
  !is.null(flags) && is.null(attr(x, "check_failures")) &&
    all(unlist(flags[setdiff(names(flags), "ess_within_bounds")]))
}

#' Check a Stan fit against the reference posterior definition
#'
#' Computes the reference posterior diagnostics directly from a fit, before
#' anything is imported. See [check_reference_posterior_draws()] for the
#' definition. `lp__` is never included.
#'
#' @param fit An `rstan::stanfit` or `cmdstanr::CmdStanMCMC` fit.
#' @param checks Checks to run: any of `"ndraws"`, `"nchains"`, `"r_hat"`,
#'   `"mean_lag1_ac"`, `"efmi"` and `"divergent_transitions"`, or `"all"`.
#' @param include,exclude Base variable names to keep or drop (see
#'   [as_reference_posterior_draws()]). By default all saved variables are
#'   checked.
#' @return `reference_draw_diagnostics()` returns a list with the `metrics`,
#'   `thresholds`, logical `status` and `failures` of each check.
#'   `passes_reference_draw_checks()` returns `TRUE` or `FALSE`.
#' @export
reference_draw_diagnostics <- function(fit, checks = "all", include = NULL, exclude = NULL) {
  if (identical(checks, "all")) checks <- all_checks()
  checkmate::assert_subset(checks, all_checks(), empty.ok = FALSE)
  fit_parts <- extract_fit(fit)
  draws <- select_variables(fit_parts$draws, required = character(), include, exclude)
  d <- compute_draw_diagnostics(draws, sampler = fit_parts$sampler)
  result <- evaluate_reference_checks(d, checks = checks)
  list(metrics = diagnostic_metrics(d)[checks], thresholds = reference_policy()[checks],
       status = result$status, failures = result$failures)
}

#' @rdname reference_draw_diagnostics
#' @export
passes_reference_draw_checks <- function(fit, checks = "all", include = NULL, exclude = NULL) {
  all(unlist(reference_draw_diagnostics(fit, checks, include, exclude)$status))
}

#' Compute reference posterior summary statistics
#'
#' Computes the posterior mean (`"mean_value"`) or the mean of the squared
#' draws (`"mean_squared_value"`) of every variable, with Monte Carlo standard
#' errors. The draws must pass the reference checks with at least 10,000
#' draws.
#'
#' @param rpd Reference posterior draws.
#' @param summary_statistic `"mean_value"` or `"mean_squared_value"`.
#' @return A `pdb_reference_posterior_summary_statistic` object.
#' @export
compute_reference_posterior_summary_statistic <- function(rpd, summary_statistic = "mean_value") {
  checkmate::assert_class(rpd, "pdb_reference_posterior_draws")
  checkmate::assert_choice(summary_statistic, summary_statistic_types())
  rpd <- check_draws(rpd, summary = TRUE)
  draws <- posterior::as_draws_array(strip_reference_class(rpd))
  if (summary_statistic == "mean_squared_value") draws <- draws^2
  s <- posterior::summarise_draws(draws, "mean", "mcse_mean")
  rpi <- info(rpd)
  rpi$versions$r_summary_statistic <- paste0("posterior R package, version ",
                                             utils::packageVersion("posterior"))
  out <- list(names = s$variable, s$mean, mcse_mean = s$mcse_mean)
  names(out)[2] <- summary_statistic
  new_summary_statistic(out, summary_statistic, rpi, pdb(rpd))
}

#' @rdname compute_reference_posterior_summary_statistic
#' @export
compute_summary_statistic <- compute_reference_posterior_summary_statistic

compute_all_summary_statistics <- function(rpd) {
  stats::setNames(lapply(summary_statistic_types(), compute_reference_posterior_summary_statistic,
                         rpd = rpd),
                  summary_statistic_types())
}
