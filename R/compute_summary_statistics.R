#' Compute Summary statistics from a reference posterior
#'
#' @param rpd a [reference_posterior_summary_statistic] object
#' @param summary_statistic summary statistic to compute
#'
#' @export
compute_reference_posterior_summary_statistic <- function(rpd, summary_statistic = "mean"){
  checkmate::assert_class(rpd, classes = "pdb_reference_posterior_draws")
  rpi <- info(rpd)
  checkmate::assert_class(rpi, classes = "pdb_reference_posterior_info")
  checkmate::assert_choice(summary_statistic, supported_summary_statistic_types())
  assert_checked_summary_statistics_draws(rpd)

  if(summary_statistic == "mean_value"){
    res <- posterior::summarise_draws(rpd, "mean", "mcse_mean")
    res <- as.list(res)
    names(res)[1] <- "names"
    names(res)[2] <- "mean_value"
    rpi$versions$r_summary_statistic <- paste0("posterior R package, version ", utils::packageVersion("posterior"))
  } else if (summary_statistic == "sd"){
    res <- posterior::summarise_draws(rpd, "sd", "mcse_sd")
    res <- as.list(res)
    names(res)[1] <- "names"
    rpi$versions$r_summary_statistic <- paste0("posterior R package, version ", utils::packageVersion("posterior"))
  } else {
    stop("Summary statistic is not implemented.")
  }

  rpss <- reference_posterior_summary_statistic(res, rpi, summary_statistic)
  rpss
}

# Create the summary-statistic acceptance record from a reference-draw object
# whose stricter PosteriorDB checks have already passed. The summary writer
# requires `ndraws_is_gte_10k`, while reference-draw writes require exactly
# 10,000 retained draws; preserve the common acceptance evidence in a separate
# info object and leave the original draw metadata unchanged.
summary_statistics_from_checked_reference_draws <- function(rpd) {
  assert_checked_reference_posterior_draws(rpd)
  reference_checks <- info(rpd)$checks_made
  shared_checks <- c(
    "nchains_is_gte_4",
    "abs_mean_lag1_ac_below_0_05",
    "r_hat_below_1_01",
    "efmi_above_0_2",
    "no_divergent_transitions"
  )
  summary_draws <- rpd
  summary_info <- info(rpd)
  summary_info$checks_made <- reference_checks[shared_checks]
  summary_info$checks_made$ndraws_is_gte_10k <- TRUE
  info(summary_draws) <- summary_info

  stats <- lapply(supported_summary_statistic_types(), function(type) {
    compute_reference_posterior_summary_statistic(summary_draws, type)
  })
  stats::setNames(stats, supported_summary_statistic_types())
}

#' @rdname compute_reference_posterior_summary_statistic
#' @export
compute_summary_statistic <- compute_reference_posterior_summary_statistic
