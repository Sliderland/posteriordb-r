#' Assert that all checks of the reference posterior draws
#' are true
#'
#' @details
#' The draws must carry a passed result for the draw-count check and, for
#' Stan sampling, for the chain, autocorrelation, R-hat, E-FMI and divergence
#' checks. Analytical draws only need the draw-count result. The variable
#' names and the number of draws per variable are validated as well.
#'
#' See \url{https://github.com/stan-dev/posteriordb/blob/master/doc/REFERENCE_POSTERIOR_DEFINITION.md} for details.
#'
#' @param x a [pdb_reference_posterior_draws] object
#'
#' @export
assert_checked_reference_posterior_draws <- function(x){
  UseMethod("assert_checked_reference_posterior_draws")
}

#' @rdname assert_checked_reference_posterior_draws
#' @export
assert_checked_reference_posterior_draws.pdb_reference_posterior_draws <- function(x){
  assert_reference_posterior_draws(x)
  rpi <- info(x)
  assert_checked_reference_posterior_draws(rpi)
  assert_diagnostic_draw_counts(x, rpi)
  checkmate::assert_true(posterior::ndraws(x) == reference_draw_policy()$ndraws_exact)
}

#' @rdname assert_checked_reference_posterior_draws
#' @export
assert_checked_reference_posterior_draws.pdb_reference_posterior_info <- function(x){
  for (name in required_reference_draw_checks(x$inference$method)) {
    checkmate::assert_true(x$checks_made[[name]],
      .var.name = paste0("checks_made$", name))
  }
  invisible(TRUE)
}


#' @rdname assert_checked_reference_posterior_draws
#' @export
assert_checked_summary_statistics_draws <- function(x){
  UseMethod("assert_checked_summary_statistics_draws")
}

#' @rdname assert_checked_reference_posterior_draws
#' @export
assert_checked_summary_statistics_draws.pdb_reference_posterior_draws <- function(x){
  assert_reference_posterior_draws(x)
  rpi <- info(x)
  assert_checked_summary_statistics_draws(rpi)
  assert_diagnostic_draw_counts(x, rpi)
  checkmate::assert_true(posterior::ndraws(x) >= reference_draw_policy()$ndraws_summary_min)
}

#' @rdname assert_checked_reference_posterior_draws
#' @export
assert_checked_summary_statistics_draws.pdb_reference_posterior_summary_statistic <- function(x){
  rpi <- info(x)
  assert_checked_summary_statistics_draws(rpi)
}

#' @rdname assert_checked_reference_posterior_draws
#' @export
assert_checked_summary_statistics_draws.pdb_reference_posterior_info <- function(x){
  for (name in required_reference_draw_checks(x$inference$method, summary = TRUE)) {
    checkmate::assert_true(x$checks_made[[name]],
      .var.name = paste0("checks_made$", name))
  }
  invisible(TRUE)
}

# Applicable acceptance flags, shared by assertions and summary transfer.
required_reference_draw_checks <- function(method, summary = FALSE) {
  checkmate::assert_choice(method, c("stan_sampling", "analytical"))
  flags <- reference_diagnostic_flag_names(summary)
  unname(if (method == "stan_sampling") flags else flags["ndraws"])
}
