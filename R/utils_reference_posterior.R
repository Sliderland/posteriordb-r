#' Check that reference posterior draws follows the
#' reference posterior summary definition.
#'
#' @details Requires at least 10,000 retained draws. For Stan sampling,
#'   the recorded diagnostics must describe the draws and show at least four
#'   chains, mean absolute lag-1 autocorrelation across chains at most 0.05
#'   for every variable, R-hat at most 1.01, E-FMI at least 0.2 in every
#'   chain, and no divergent transitions. ESS bounds are recorded but do not
#'   determine acceptance. Analytical draws require the stated draw count
#'   and matching count metadata; Stan sampling checks do not apply. Named
#'   Stan metrics must identify the retained variables or `chain1`, `chain2`,
#'   etc. Unnamed legacy metrics retain positional interpretation.
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
  check_reference_draws(x, summary = TRUE)
}


#' Check that reference posterior draws follows the
#' reference posterior draws definition.
#'
#' @details Requires exactly 10,000 retained draws. For Stan sampling,
#'   the recorded diagnostics must describe the draws and show at least four
#'   chains, mean absolute lag-1 autocorrelation across chains at most 0.05
#'   for every variable, R-hat at most 1.01, E-FMI at least 0.2 in every
#'   chain, and no divergent transitions. ESS bounds are recorded but do not
#'   determine acceptance. Analytical draws require the stated draw count
#'   and matching count metadata; Stan sampling checks do not apply. Named
#'   Stan metrics must identify the retained variables or `chain1`, `chain2`,
#'   etc. Unnamed legacy metrics retain positional interpretation.
#'
#' @param x a posterior name, posterior object, reference-posterior draws, or
#'   a `pdb_reference_bundle` returned by [create_pdb_bundle()].
#' @param ... currently not used.
#' @return For a `pdb_reference_bundle`, the updated bundle with a full
#'   diagnostic report and acceptance flags attached when all required checks
#'   pass. Other supported objects retain their existing return behavior.
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
  check_reference_draws(x)
}

# Both gates use the same validation and policy, with distinct count rules.
check_reference_draws <- function(x, summary = FALSE) {
  assert_reference_posterior_draws(x)
  rpi <- info(x)
  assert_reference_posterior_info(rpi)
  assert_diagnostic_draw_counts(x, rpi)
  count <- reference_diagnostic_evaluation(
    list(ndraws = rpi$diagnostics$ndraws), "ndraws", summary = summary
  )
  checkmate::assert_true(count$status$ndraws, .var.name = "diagnostics$ndraws")
  rpi$checks_made <- stats::setNames(list(TRUE),
    reference_diagnostic_flag_names(summary)[["ndraws"]])
  if (rpi$inference$method == "stan_sampling") {
    rpi$checks_made <- c(rpi$checks_made, check_stan_sampling_quality(x, rpi))
  }
  info(x) <- rpi
  if (summary) assert_checked_summary_statistics_draws(x)
  else assert_checked_reference_posterior_draws(x)
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
  if (rpi$inference$method == "stan_sampling") {
    variables <- posterior::variables(x)
    recorded_names <- diagnostics$diagnostic_information$names
    if (!is.null(recorded_names)) {
      checkmate::assert_names(recorded_names, permutation.of = variables,
        .var.name = "diagnostic_information$names")
    }
    for (field in c("mean_lag1_ac", "r_hat",
                    "expected_fraction_of_missing_information", "divergent_transitions")) {
      labels <- if (field %in% c("mean_lag1_ac", "r_hat")) variables
        else paste0("chain", seq_len(posterior::nchains(x)))
      if (!is.null(names(diagnostics[[field]]))) {
        checkmate::assert_names(names(diagnostics[[field]]), permutation.of = labels,
          .var.name = field)
      }
    }
  }
  invisible(NULL)
}

# Check the Stan diagnostics shared by the draws and summary-statistic gates.
# ESS is recorded for information, while the other checks are required.
check_stan_sampling_quality <- function(x, rpi) {
  diagnostics <- rpi$diagnostics
  variables <- posterior::variables(x)
  lag1 <- diagnostics$mean_lag1_ac
  if (is.null(lag1)) lag1 <- mean_lag1_ac(x)
  observed <- list(nchains = diagnostics$nchains, mean_lag1_ac = lag1,
    r_hat = diagnostics$r_hat,
    efmi = diagnostics$expected_fraction_of_missing_information,
    divergent_transitions = diagnostics$divergent_transitions)
  fields <- c(mean_lag1_ac = "mean_lag1_ac", r_hat = "r_hat",
    efmi = "expected_fraction_of_missing_information",
    divergent_transitions = "divergent_transitions")
  for (key in names(fields)) {
    labels <- if (key %in% c("mean_lag1_ac", "r_hat")) variables
      else paste0("chain", seq_len(diagnostics$nchains))
    assert_finite_diagnostic(observed[[key]], length(labels), name = fields[[key]])
  }
  evaluated <- reference_diagnostic_evaluation(observed, names(observed))
  for (key in names(observed)) {
    checkmate::assert_true(evaluated$status[[key]],
      .var.name = if (key %in% names(fields)) fields[[key]] else key)
  }
  checks <- stats::setNames(evaluated$status,
    unname(reference_diagnostic_flag_names()[names(observed)]))
  # ESS remains informational, including mismatched labels.
  checks$ess_within_bounds <- ess_within_bounds(x, rpi)
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
  out <- reference_lag1_ac(x)
  if (any(!is.finite(out))) {
    stop("Lag-1 autocorrelation was undefined for a retained variable.", call. = FALSE)
  }
  out
}

# Nonthrowing worker for reports; strict callers use mean_lag1_ac().
reference_lag1_ac <- function(x) {
  x <- posterior::as_draws_array(x)
  vars <- posterior::variables(x)
  stats::setNames(vapply(seq_along(vars), function(j) {
    by_chain <- vapply(seq_len(posterior::nchains(x)), function(i) {
      z <- x[, i, j]
      if (length(z) < 2L || !is.finite(stats::var(z)) || stats::var(z) == 0) return(NA_real_)
      centered <- z - mean(z)
      sum(centered[-length(centered)] * centered[-1L]) / sum(centered^2)
    }, numeric(1))
    if (any(!is.finite(by_chain))) NA_real_ else mean(abs(by_chain))
  }, numeric(1)), vars)
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
      (is.null(names(values)) ||
       checkmate::test_names(names(values), permutation.of = posterior::variables(x))) &&
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
