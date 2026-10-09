
reference_diagnostic_evaluation <- function(observed, checks, policy = reference_draw_policy(),
                                            summary = FALSE) {
  thresholds <- policy$thresholds[checks]
  if (summary && "ndraws" %in% checks) thresholds$ndraws <- policy$ndraws_summary_min
  failures <- list()
  status <- lapply(checks, function(key) {
    x <- observed[[key]]
    if (!is.numeric(x) || !length(x) || any(!is.finite(x))) return(FALSE)
    switch(key,
      ndraws = length(x) == 1L && (if (summary) x >= policy$ndraws_summary_min else x == policy$ndraws_exact),
      nchains = length(x) == 1L && x >= policy$nchains_min,
      mean_lag1_ac = all(abs(x) <= policy$mean_lag1_ac_max),
      r_hat = all(x <= policy$r_hat_max),
      efmi = all(x >= policy$efmi_min),
      divergent_transitions = all(x == policy$divergences_max))
  })
  names(status) <- checks
  for (key in checks) {
    x <- observed[[key]]
    if (is.null(x) || identical(x, "unavailable") || !isTRUE(status[[key]])) {
      bad <- if (!is.numeric(x) || !length(x)) {
        "unavailable"
      } else if (key %in% c("ndraws", "nchains")) {
        list(observed = unname(x), required = thresholds[[key]],
             comparison = if (key == "ndraws" && !summary) "equal" else "at_least")
      } else if (key == "mean_lag1_ac") {
        names(x)[!is.finite(x) | abs(x) > thresholds[[key]]]
      } else if (key == "r_hat") {
        names(x)[!is.finite(x) | x > thresholds[[key]]]
      } else {
        names(x)[!is.finite(x) | (if (key == "efmi") x < thresholds[[key]] else x != thresholds[[key]])]
      }
      failures[[key]] <- bad
    }
  }
  list(status = status, failures = failures)
}

# Single policy source for reference and summary-draw acceptance. Existing
# acceptance helpers consume this object alongside the direct-fit report.
reference_draw_policy <- function() {
  ndraws_exact <- 10000L
  ndraws_summary_min <- 10000L
  nchains_min <- 4L
  mean_lag1_ac_max <- 0.05
  r_hat_max <- 1.01
  efmi_min <- 0.2
  divergences_max <- 0L
  list(
    ndraws_exact = ndraws_exact,
    ndraws_summary_min = ndraws_summary_min,
    nchains_min = nchains_min,
    mean_lag1_ac_max = mean_lag1_ac_max,
    r_hat_max = r_hat_max,
    efmi_min = efmi_min,
    divergences_max = divergences_max,
    thresholds = list(ndraws = ndraws_exact, nchains = nchains_min,
                      mean_lag1_ac = mean_lag1_ac_max, r_hat = r_hat_max,
                      efmi = efmi_min, divergent_transitions = divergences_max)
  )
}

# Map report keys to the existing persisted acceptance schema.
reference_diagnostic_flag_names <- function(summary = FALSE) {
  c(ndraws = if (summary) "ndraws_is_gte_10k" else "ndraws_is_10k",
    nchains = "nchains_is_gte_4", mean_lag1_ac = "abs_mean_lag1_ac_below_0_05",
    r_hat = "r_hat_below_1_01", efmi = "efmi_above_0_2",
    divergent_transitions = "no_divergent_transitions")
}
