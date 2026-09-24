#' Inspect reference-draw diagnostics without constructing database objects
#'
#' Intended for callers who have an already sampled RStan or CmdStanR fit and
#' want a diagnostic report before importing it. Draws exclude warmup and retain
#' chain order. Checks are selected by name; `"all"` collects the complete
#' reference acceptance report. The lag-only path reads posterior draws only.
#'
#' @param fit a completed `rstan::stanfit` or `cmdstanr::CmdStanMCMC` fit.
#' @param checks character vector of checks: `ndraws`, `nchains`,
#'   `mean_lag1_ac`, `r_hat`, `efmi`, and `divergent_transitions`; or `"all"`.
#' @param include,exclude optional base parameter names to retain or omit.
#' @return `reference_draw_diagnostics()` returns a list with `metrics`,
#'   `thresholds`, named logical `status`, and named `failures`. Metric vectors
#'   are named by scalar variable or chain. Failed count checks report their
#'   observed and required values; unavailable values are marked `unavailable`. The
#'   `ndraws` criterion requires exactly 10,000 retained draws total.
#' @examples
#' \dontrun{
#' report <- reference_draw_diagnostics(fit, checks = "mean_lag1_ac")
#' passes_reference_draw_checks(fit, "mean_lag1_ac")
#' }
#' @export
reference_draw_diagnostics <- function(fit, checks = "all", include = NULL,
                                       exclude = NULL) {
  known <- c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions")
  checkmate::assert_character(checks, min.len = 1L, any.missing = FALSE)
  if (identical(checks, "all")) checks <- known
  if (anyDuplicated(checks) || any(!checks %in% known))
    stop("`checks` must contain unique supported check names or `\"all\"`.", call. = FALSE)
  extracted <- extract_external_stan_fit(fit, checks = checks, strict = FALSE)
  reference_draw_diagnostics_from_extracted(extracted, checks, include, exclude)
}

# Build the public report from the stable plain-list extraction contract. Bundle
# construction uses this boundary to avoid reading a fit twice.
reference_draw_diagnostics_from_extracted <- function(extracted, checks = "all",
                                                       include = NULL,
                                                       exclude = NULL) {
  known <- c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions")
  checkmate::assert_list(extracted)
  required <- c("draws", "sampler_diagnostics", "metadata")
  missing <- setdiff(required, names(extracted))
  if (length(missing)) stop("Malformed extracted fit; missing: ", paste(missing, collapse = ", "), call. = FALSE)
  checkmate::assert_character(checks, min.len = 1L, any.missing = FALSE)
  if (identical(checks, "all")) checks <- known
  if (anyDuplicated(checks) || any(!checks %in% known))
    stop("`checks` must contain unique supported check names or `\"all\"`.", call. = FALSE)
  draws <- select_reference_diagnostic_draws(extracted$draws, include, exclude)
  observed <- list()
  policy <- reference_draw_policy()
  thresholds <- policy$thresholds
  failures <- list()
  if ("ndraws" %in% checks) observed$ndraws <- posterior::ndraws(draws)
  if ("nchains" %in% checks) observed$nchains <- posterior::nchains(draws)
  if ("mean_lag1_ac" %in% checks) observed$mean_lag1_ac <- tryCatch(mean_lag1_ac(draws), error = function(e) NULL)
  if ("r_hat" %in% checks) {
    observed$r_hat <- tryCatch({
      sm <- posterior::summarise_draws(draws)
      stats::setNames(sm$rhat, sm$variable)
    }, error = function(e) NULL)
  }
  if ("efmi" %in% checks) {
    x <- extracted$metadata$expected_fraction_of_missing_information
    if (!is.null(x) && length(x) == posterior::nchains(draws) && all(is.finite(x)))
      observed$efmi <- stats::setNames(x, paste0("chain", seq_along(x)))
  }
  if ("divergent_transitions" %in% checks) {
    sd <- extracted$sampler_diagnostics
    if (!is.null(sd) && "divergent__" %in% posterior::variables(sd))
      observed$divergent_transitions <- stats::setNames(vapply(seq_len(posterior::nchains(sd)),
        function(i) sum(sd[, i, "divergent__"]), numeric(1)), paste0("chain", seq_len(posterior::nchains(sd))))
  }
  status <- lapply(checks, function(key) {
    x <- observed[[key]]
    if (is.null(x) || !length(x) || any(!is.finite(x))) return(FALSE)
    switch(key,
      ndraws = identical(as.integer(x), policy$ndraws_exact),
      nchains = x >= policy$nchains_min,
      mean_lag1_ac = all(abs(x) <= policy$mean_lag1_ac_max),
      r_hat = all(x <= policy$r_hat_max),
      efmi = length(x) >= policy$nchains_min && all(x >= policy$efmi_min),
      divergent_transitions = all(x == policy$divergences_max))
  })
  names(status) <- checks
  for (key in checks) {
    x <- observed[[key]]
    if (is.null(x) || !isTRUE(status[[key]])) {
      bad <- if (is.null(x)) {
        "unavailable"
      } else if (key %in% c("ndraws", "nchains")) {
        list(observed = unname(x), required = thresholds[[key]],
             comparison = if (key == "ndraws") "equal" else "at_least")
      } else if (key %in% c("mean_lag1_ac", "r_hat")) {
        names(x)[!is.finite(x) | abs(x) > thresholds[[key]]]
      } else {
        names(x)[!is.finite(x) | (if (key == "efmi") x < thresholds[[key]] else x != thresholds[[key]])]
      }
      failures[[key]] <- bad
    }
  }
  list(metrics = observed, thresholds = thresholds[checks], status = status,
       failures = failures)
}

#' Test selected reference-draw checks
#'
#' Returns a scalar logical; it does not establish full acceptance unless all
#' checks are selected. See [reference_draw_diagnostics()] for report details.
#' Missing or invalid required metrics raise an error rather than passing.
#' @inheritParams reference_draw_diagnostics
#' @return A single `TRUE` or `FALSE`.
#' @examples
#' \dontrun{passes_reference_draw_checks(fit, "mean_lag1_ac")}
#' @export
passes_reference_draw_checks <- function(fit, checks = "all", include = NULL,
                                         exclude = NULL) {
  report <- reference_draw_diagnostics(fit, checks, include, exclude)
  isTRUE(all(unlist(report$status, use.names = FALSE)))
}

select_reference_diagnostic_draws <- function(draws, include = NULL, exclude = NULL) {
  vars <- posterior::variables(draws)
  base <- sub("\\[.*$", "", vars)
  available <- unique(base)
  if (!is.null(include)) {
    checkmate::assert_character(include, min.len = 1L, any.missing = FALSE)
    unknown <- setdiff(include, available)
    if (length(unknown)) stop("Unknown base variable(s) in `include`: ", paste(unknown, collapse = ", "), call. = FALSE)
    vars <- vars[base %in% include]
  }
  if (!is.null(exclude)) {
    checkmate::assert_character(exclude, min.len = 1L, any.missing = FALSE)
    unknown <- setdiff(exclude, available)
    if (length(unknown)) stop("Unknown base variable(s) in `exclude`: ", paste(unknown, collapse = ", "), call. = FALSE)
    vars <- vars[!base %in% exclude]
  }
  if (!length(vars)) stop("No posterior variables remain after `include`/`exclude`.", call. = FALSE)
  posterior::subset_draws(draws, variable = vars, regex = FALSE)
}

# Single policy source for reference and summary-draw acceptance. Existing
# acceptance helpers consume this object alongside the direct-fit report.
reference_draw_policy <- function() {
  list(
    ndraws_exact = 10000L,
    ndraws_summary_min = 10000L,
    nchains_min = 4L,
    mean_lag1_ac_max = 0.05,
    r_hat_max = 1.01,
    efmi_min = 0.2,
    divergences_max = 0L,
    thresholds = list(ndraws = 10000L, nchains = 4L,
                      mean_lag1_ac = 0.05, r_hat = 1.01,
                      efmi = 0.2, divergent_transitions = 0L)
  )
}
