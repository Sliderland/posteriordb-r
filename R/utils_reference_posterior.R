#' Check that reference posterior draws follows the
#' reference posterior summary definition.
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

  tst <- list()

  # Assert that there is exactly 10000 draws
  checkmate::assert_true(rpi$diagnostics$ndraws >= 10000)
  tst$ndraws_is_gte_10k <- TRUE

  if(rpi$inference$method == "stan_sampling"){
    # Assert that at least 4 chains has been used
    checkmate::assert_true(rpi$diagnostics$nchains >= 4)
    tst$nchains_is_gte_4 <- TRUE

    # Record ESS as an informational diagnostic without using it as an
    # acceptance criterion.
    tst$ess_within_bounds <- ess_within_bounds(x, rpi)

    # Assert that mean absolute lag-1 autocorrelation is below 0.05.
    lag1 <- rpi$diagnostics$mean_lag1_ac
    if (is.null(lag1)) lag1 <- mean_lag1_ac(x)
    checkmate::assert_numeric(abs(lag1), upper = 0.05)
    tst$abs_mean_lag1_ac_below_0_05 <- TRUE

    # Assert all Rhat < 1.01
    checkmate::assert_numeric(rpi$diagnostics$r_hat, upper = 1.01)
    tst$r_hat_below_1_01 <- TRUE

    # Assert that the EFMI is larger than 0.2
    checkmate::assert_numeric(rpi$diagnostics$expected_fraction_of_missing_information, lower = 0.2)
    tst$efmi_above_0_2 <- TRUE

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

  tst <- list()

  # Assert that there is exactly 10000 draws
  checkmate::assert_true(rpi$diagnostics$ndraws == 10000)
  tst$ndraws_is_10k <- TRUE

  if(rpi$inference$method == "stan_sampling"){
    # Assert that at least 4 chains has been used
    checkmate::assert_true(rpi$diagnostics$nchains >= 4)
    tst$nchains_is_gte_4 <- TRUE

    # Record ESS as an informational diagnostic without using it as an
    # acceptance criterion.
    tst$ess_within_bounds <- ess_within_bounds(x, rpi)

    # Assert that mean absolute lag-1 autocorrelation is below 0.05.
    lag1 <- rpi$diagnostics$mean_lag1_ac
    if (is.null(lag1)) lag1 <- mean_lag1_ac(x)
    checkmate::assert_numeric(abs(lag1), upper = 0.05)
    tst$abs_mean_lag1_ac_below_0_05 <- TRUE

    # Assert all Rhat < 1.01
    checkmate::assert_numeric(rpi$diagnostics$r_hat, upper = 1.01)
    tst$r_hat_below_1_01 <- TRUE

    # Assert that the EFMI is larger than 0.2
    checkmate::assert_numeric(rpi$diagnostics$expected_fraction_of_missing_information, lower = 0.2)
    tst$efmi_above_0_2 <- TRUE

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

# Compute the mean absolute lag-1 autocorrelation across chains for every
# retained variable. `posterior::autocorrelation()` returns zero for a
# constant chain, which is appropriate for this acceptance diagnostic.
mean_lag1_ac <- function(x){
  x <- posterior::as_draws_array(x)
  n_chains <- dim(x)[2]
  n_variables <- dim(x)[3]
  variable_names <- posterior::variables(x)

  out <- stats::setNames(numeric(n_variables), variable_names)
  for (variable_index in seq_len(n_variables)) {
    by_chain <- vapply(seq_len(n_chains), function(chain_index) {
      z <- x[, chain_index, variable_index]
      posterior::autocorrelation(z)[2]
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
  within <- function(values, limits) {
    length(values) > 0L &&
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
