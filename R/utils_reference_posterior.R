#' Check that reference posterior draws follows the
#' reference posterior summary definition.
#'
#' @details Requires at least 10,000 retained draws. For Stan sampling,
#'   the recorded diagnostics must describe the draws and show at least four
#'   chains, mean absolute lag-1 autocorrelation across chains at most 0.05
#'   for every variable, R-hat at most 1.01, E-FMI at least 0.2 in every
#'   chain, and no divergent transitions. ESS bounds are recorded but do not
#'   determine acceptance.
#'
#' @param x a posterior name, posterior object or reference_posterior_draws object
#' @param ... currently not used.
#'
#' @export
check_summary_statistics_draws <- function(x, ...){
  UseMethod("check_summary_statistics_draws")
}

#' @rdname check_summary_statistics_draws
#' @export
check_summary_statistics_draws.character <- function(x, ...){
  x <- pdb_posterior(x, ...)
  check_summary_statistics_draws(x)
}

#' @rdname check_summary_statistics_draws
#' @export
check_summary_statistics_draws.pdb_posterior <- function(x, ...){
  x <- reference_posterior_draws(x)
  check_summary_statistics_draws(x)
}

#' @rdname check_summary_statistics_draws
#' @export
check_summary_statistics_draws.pdb_reference_posterior_draws <- function(x, ...){
  assert_reference_posterior_draws(x)
  rpi <- info(x)
  assert_reference_posterior_info(rpi)
  assert_diagnostic_draw_counts(x, rpi)

  tst <- list()

  # Assert that there is exactly 10000 draws
  checkmate::assert_true(rpi$diagnostics$ndraws >= 10000)
  tst$ndraws_is_gte_10k <- TRUE

  if(rpi$inference$method == "stan_sampling"){
    tst <- c(tst, check_stan_sampling_quality(x, rpi))
  }

  # Add checks made to reference posterior
  rpi$checks_made <- tst

  # Add the rp information
  assert_reference_posterior_info(x = rpi)
  attr(x, "info") <- rpi

  # Check the reference posterior
  assert_reference_posterior_draws(x)
  assert_checked_summary_statistics_draws(x)
  invisible(x)
}


#' Check that reference posterior draws follows the
#' reference posterior draws definition.
#'
#' @details Requires exactly 10,000 retained draws. For Stan sampling,
#'   the recorded diagnostics must describe the draws and show at least four
#'   chains, mean absolute lag-1 autocorrelation across chains at most 0.05
#'   for every variable, R-hat at most 1.01, E-FMI at least 0.2 in every
#'   chain, and no divergent transitions. ESS bounds are recorded but do not
#'   determine acceptance.
#'
#' @param x a posterior name, posterior object or reference_posterior_draws object
#' @param ... currently not used.
#'
#' @export
check_reference_posterior_draws <- function(x, ...){
  UseMethod("check_reference_posterior_draws")
}

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.character <- function(x, ...){
  x <- pdb_posterior(x, ...)
  check_reference_posterior_draws(x)
}

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.pdb_posterior <- function(x, ...){
  x <- reference_posterior_draws(x)
  check_reference_posterior_draws(x)
}

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.pdb_reference_posterior_draws <- function(x, ...){
  assert_reference_posterior_draws(x)
  rpi <- info(x)
  assert_reference_posterior_info(rpi)
  assert_diagnostic_draw_counts(x, rpi)

  tst <- list()

  # Assert that there is exactly 10000 draws
  checkmate::assert_true(rpi$diagnostics$ndraws == 10000)
  tst$ndraws_is_10k <- TRUE

  if(rpi$inference$method == "stan_sampling"){
    tst <- c(tst, check_stan_sampling_quality(x, rpi))
  }

  # Add checks made to reference posterior
  rpi$checks_made <- tst

  # Add the rp information
  assert_reference_posterior_info(x = rpi)
  attr(x, "info") <- rpi

  # Check the reference posterior
  assert_reference_posterior_draws(x)
  assert_checked_reference_posterior_draws(x)
  invisible(x)
}

# Recorded counts must describe the retained draws being checked.
assert_diagnostic_draw_counts <- function(x, rpi) {
  diagnostics <- rpi$diagnostics
  if (posterior::nvariables(x) == 0L) {
    stop("Reference-posterior draws must include at least one variable.",
         call. = FALSE)
  }
  if (!isTRUE(diagnostics$ndraws == posterior::ndraws(x))) {
    stop("Recorded ndraws does not match the reference-posterior draws.",
         call. = FALSE)
  }
  if (!is.null(diagnostics$nchains) &&
      !isTRUE(diagnostics$nchains == posterior::nchains(x))) {
    stop("Recorded nchains does not match the reference-posterior draws.",
         call. = FALSE)
  }
  invisible(NULL)
}

# Check the Stan diagnostics shared by the draws and summary-statistic gates.
# ESS is recorded for information, while the other checks are required.
check_stan_sampling_quality <- function(x, rpi) {
  diagnostics <- rpi$diagnostics
  checkmate::assert_true(diagnostics$nchains >= 4)
  checks <- list(nchains_is_gte_4 = TRUE)
  checks$ess_within_bounds <- ess_within_bounds(x, rpi)

  lag1 <- diagnostics$mean_lag1_ac
  if (is.null(lag1)) lag1 <- mean_lag1_ac(x)
  assert_finite_diagnostic(
    abs(lag1), posterior::nvariables(x), upper = 0.05,
    name = "mean_lag1_ac"
  )
  checks$abs_mean_lag1_ac_below_0_05 <- TRUE

  assert_finite_diagnostic(
    diagnostics$r_hat, posterior::nvariables(x), upper = 1.01,
    name = "r_hat"
  )
  checks$r_hat_below_1_01 <- TRUE

  assert_finite_diagnostic(
    diagnostics$expected_fraction_of_missing_information,
    diagnostics$nchains, lower = 0.2,
    name = "expected_fraction_of_missing_information"
  )
  checks$efmi_above_0_2 <- TRUE

  assert_finite_diagnostic(
    diagnostics$divergent_transitions, diagnostics$nchains,
    lower = 0, upper = 0, name = "divergent_transitions"
  )
  checks$no_divergent_transitions <- TRUE
  checks
}

assert_finite_diagnostic <- function(values, expected_length, lower = -Inf,
                                     upper = Inf, name) {
  checkmate::assert_numeric(
    values, lower = lower, upper = upper, finite = TRUE,
    any.missing = FALSE, len = expected_length, .var.name = name
  )
}

# Compute the mean absolute lag-1 autocorrelation across chains for every
# retained variable. Constant chains have undefined autocorrelation and fail.
mean_lag1_ac <- function(x){
  x <- posterior::as_draws_array(x)
  if (dim(x)[1L] < 2L) {
    stop("At least two iterations are required for lag-1 autocorrelation.",
         call. = FALSE)
  }
  n_chains <- dim(x)[2]
  n_variables <- dim(x)[3]
  variable_names <- posterior::variables(x)

  out <- stats::setNames(numeric(n_variables), variable_names)
  for (variable_index in seq_len(n_variables)) {
    by_chain <- vapply(seq_len(n_chains), function(chain_index) {
      z <- x[, chain_index, variable_index]
      centered <- z - mean(z)
      sum(centered[-length(centered)] * centered[-1L]) /
        sum(centered^2)
    }, numeric(1))
    if (anyNA(by_chain) || any(!is.finite(by_chain))) {
      stop(
        "Lag-1 autocorrelation was undefined for a retained variable.",
        call. = FALSE
      )
    }
    out[variable_index] <- mean(abs(by_chain))
  }
  out
}

#' Compute ESS tail and bulk bounds
#'
#' @details Compute the bounds for ESS tail and bulk based on 100 000
#' simulated ESS computations.
#'
#' @param x a [pdb_reference_posterior_draws] object.
#' @keywords internal
ess_bounds <- function(x){
  checkmate::assert_class(x, "draws")

  npar <- posterior::nvariables(x)
  ndraws <- posterior::ndraws(x)
  # We approximate ESS SD as follows (after some simulations)
  # We then use 4 SD to check the ESSs
  approx_ess_sd <- sqrt(7) * sqrt(ndraws)
  bnds <- ndraws + 4 * c(approx_ess_sd, -approx_ess_sd)

  #  alpha <- 1 - exp(log(p)/npar)
  #  essb <- esst <- NULL # To mask check NOTEs

  list(ess_bulk = bnds,
       ess_tail = bnds)

}

# Evaluate ESS bounds without throwing an error. ESS is retained in the
# reference-posterior metadata, but it is not part of the acceptance gate.
ess_within_bounds <- function(x, rpi){
  bounds <- ess_bounds(x)
  n_variables <- posterior::nvariables(x)
  within <- function(values, limits) {
    is.numeric(values) &&
      length(values) == n_variables && n_variables > 0L &&
      all(is.finite(values)) &&
      all(values >= min(limits)) &&
      all(values <= max(limits))
  }

  within(
    rpi$diagnostics$effective_sample_size_bulk,
    bounds$ess_bulk
  ) &&
    within(
      rpi$diagnostics$effective_sample_size_tail,
      bounds$ess_tail
    )
}
