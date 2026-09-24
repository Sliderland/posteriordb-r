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
#'   are named by scalar variable or chain. Unavailable metrics are marked
#'   `"unavailable"`; undefined variable metrics are `NA` and fail their check.
#'   Failed count checks report observed and required values. `ndraws` requires
#'   exactly 10,000 retained draws total.
#' @examples
#' \dontrun{
#' report <- reference_draw_diagnostics(fit, checks = "mean_lag1_ac")
#' passes_reference_draw_checks(fit, "mean_lag1_ac")
#' }
#' @export
reference_draw_diagnostics <- function(fit, checks = "all", include = NULL,
                                       exclude = NULL) {
  checks <- reference_diagnostic_checks(checks)
  extracted <- extract_external_stan_fit(fit, checks = checks, strict = FALSE)
  reference_draw_diagnostics_from_extracted(extracted, checks, include, exclude)
}

# Build the report from a plain list with post-warmup `draws` as a
# `posterior::draws_array`, optional `sampler_diagnostics` in the same format,
# and `metadata` containing per-chain E-FMI when available. Bundle construction
# uses this boundary to avoid reading a fit twice.
reference_draw_diagnostics_from_extracted <- function(extracted, checks = "all",
                                                       include = NULL,
                                                       exclude = NULL) {
  checkmate::assert_list(extracted)
  required <- c("draws", "sampler_diagnostics", "metadata")
  missing <- setdiff(required, names(extracted))
  if (length(missing)) stop("Malformed extracted fit; missing: ", paste(missing, collapse = ", "), call. = FALSE)
  checks <- reference_diagnostic_checks(checks)
  if (!inherits(extracted$draws, "draws_array") || !is.list(extracted$metadata) ||
      (!is.null(extracted$sampler_diagnostics) && !inherits(extracted$sampler_diagnostics, "draws_array")))
    stop("Malformed extracted fit; expected draws_array draws, list metadata, and optional draws_array sampler_diagnostics.", call. = FALSE)
  if (any(!is.finite(extracted$draws)))
    stop("Malformed extracted fit; posterior draws must be finite.", call. = FALSE)
  if (!is.null(extracted$sampler_diagnostics) &&
      !identical(dim(extracted$sampler_diagnostics)[1:2], dim(extracted$draws)[1:2]))
    stop("Malformed extracted fit; sampler diagnostics dimensions must match posterior draws.", call. = FALSE)
  draws <- select_reference_diagnostic_draws(extracted$draws, include, exclude)
  policy <- reference_draw_policy()
  observed <- reference_diagnostic_metrics(draws, extracted, checks)
  for (key in setdiff(checks, names(observed))) observed[[key]] <- "unavailable"
  observed <- observed[checks]
  thresholds <- policy$thresholds[checks]
  evaluated <- reference_diagnostic_evaluation(observed, checks, policy)
  list(metrics = observed, thresholds = thresholds,
       status = evaluated$status, failures = evaluated$failures)
}

reference_diagnostic_evaluation <- function(observed, checks, policy = reference_draw_policy()) {
  thresholds <- policy$thresholds[checks]
  failures <- list()
  status <- lapply(checks, function(key) {
    x <- observed[[key]]
    if (identical(x, "unavailable") || is.null(x) || !length(x) ||
        (is.numeric(x) && any(!is.finite(x)))) return(FALSE)
    switch(key,
      ndraws = length(x) == 1L && is.numeric(x) && x == policy$ndraws_exact,
      nchains = x >= policy$nchains_min,
      mean_lag1_ac = all(abs(x) <= policy$mean_lag1_ac_max),
      r_hat = all(x <= policy$r_hat_max),
      efmi = all(x >= policy$efmi_min),
      divergent_transitions = all(x == policy$divergences_max))
  })
  names(status) <- checks
  for (key in checks) {
    x <- observed[[key]]
    if (is.null(x) || identical(x, "unavailable") || !isTRUE(status[[key]])) {
      bad <- if (is.null(x) || identical(x, "unavailable")) {
        "unavailable"
      } else if (key %in% c("ndraws", "nchains")) {
        list(observed = unname(x), required = thresholds[[key]],
             comparison = if (key == "ndraws") "equal" else "at_least")
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

#' Test selected reference-draw checks
#'
#' Returns a scalar logical; it does not establish full acceptance unless all
#' checks are selected. See [reference_draw_diagnostics()] for report details.
#' Unavailable or undefined required metrics return `FALSE`; malformed objects
#' and selectors raise informative errors.
#' @inheritParams reference_draw_diagnostics
#' @return A single `TRUE` or `FALSE`.
#' @examples
#' \dontrun{passes_reference_draw_checks(fit, "mean_lag1_ac")}
#' @export
passes_reference_draw_checks <- function(fit, checks = "mean_lag1_ac", include = NULL,
                                         exclude = NULL) {
  report <- reference_draw_diagnostics(fit, checks, include, exclude)
  isTRUE(all(unlist(report$status, use.names = FALSE)))
}


select_reference_diagnostic_draws <- function(draws, include = NULL, exclude = NULL) {
  vars <- posterior::variables(draws)
  vars <- vars[!grepl("^lp__(?:\\[|$)", vars)]
  if (!length(vars)) stop("No posterior variables remain after excluding `lp__`.", call. = FALSE)
  base <- sub("\\[.*$", "", vars)
  available <- unique(base)
  if (!is.null(include)) {
    checkmate::assert_character(include, min.len = 1L, any.missing = FALSE, unique = TRUE)
    if (any(!nzchar(trimws(include)))) stop("`include` values must be nonempty.", call. = FALSE)
    unknown <- setdiff(include, available)
    if (length(unknown)) stop("Unknown base variable(s) in `include`: ", paste(unknown, collapse = ", "), call. = FALSE)
    keep <- base %in% include
    vars <- vars[keep]
    base <- base[keep]
  }
  if (!is.null(exclude)) {
    checkmate::assert_character(exclude, min.len = 1L, any.missing = FALSE, unique = TRUE)
    if (any(!nzchar(trimws(exclude)))) stop("`exclude` values must be nonempty.", call. = FALSE)
    unknown <- setdiff(exclude, available)
    if (length(unknown)) stop("Unknown base variable(s) in `exclude`: ", paste(unknown, collapse = ", "), call. = FALSE)
    vars <- vars[!base %in% exclude]
  }
  if (!length(vars)) stop("No posterior variables remain after `include`/`exclude`.", call. = FALSE)
  posterior::subset_draws(draws, variable = vars, regex = FALSE)
}

reference_diagnostic_checks <- function(checks) {
  known <- c("ndraws", "nchains", "mean_lag1_ac", "r_hat", "efmi", "divergent_transitions")
  checkmate::assert_character(checks, min.len = 1L, any.missing = FALSE)
  if (identical(checks, "all")) checks <- known
  if (anyDuplicated(checks) || any(!checks %in% known))
    stop("`checks` must contain unique supported check names or `\"all\"`.", call. = FALSE)
  checks
}

reference_diagnostic_metrics <- function(draws, extracted, checks) {
  out <- list()
  if ("ndraws" %in% checks) out$ndraws <- posterior::ndraws(draws)
  if ("nchains" %in% checks) out$nchains <- posterior::nchains(draws)
  vars <- posterior::variables(draws)
  if ("mean_lag1_ac" %in% checks) {
    out$mean_lag1_ac <- stats::setNames(vapply(seq_along(vars), function(j) {
      by_chain <- vapply(seq_len(posterior::nchains(draws)), function(i) {
        z <- draws[, i, j]
        if (length(z) < 2L || !is.finite(stats::var(z)) || stats::var(z) == 0) return(NA_real_)
        centered <- z - mean(z)
        sum(centered[-length(centered)] * centered[-1L]) / sum(centered^2)
      }, numeric(1))
      if (any(!is.finite(by_chain))) NA_real_ else mean(abs(by_chain))
    }, numeric(1)), vars)
  }
  if ("r_hat" %in% checks) {
    out$r_hat <- stats::setNames(vapply(seq_along(vars), function(j) {
      chain_matrix <- matrix(draws[, , j], nrow = dim(draws)[1L], ncol = dim(draws)[2L])
      tryCatch(as.numeric(posterior::rhat(chain_matrix))[1],
               error = function(e) NA_real_)
    }, numeric(1)), vars)
  }
  if ("efmi" %in% checks) {
    x <- extracted$metadata$expected_fraction_of_missing_information
    if (!is.null(x)) {
      if (!is.numeric(x) || length(x) != posterior::nchains(draws))
        stop("Malformed extracted fit; expected one numeric E-FMI value per chain.", call. = FALSE)
      out$efmi <- stats::setNames(as.numeric(x), paste0("chain", seq_along(x)))
    }
  }
  if ("divergent_transitions" %in% checks && !is.null(extracted$sampler_diagnostics)) {
    sd <- extracted$sampler_diagnostics
    if (!inherits(sd, "draws_array")) stop("Malformed extracted fit; `sampler_diagnostics` must be a draws_array or NULL.", call. = FALSE)
    if ("divergent__" %in% posterior::variables(sd))
      out$divergent_transitions <- stats::setNames(vapply(seq_len(posterior::nchains(sd)),
        function(i) sum(sd[, i, "divergent__"]), numeric(1)), paste0("chain", seq_len(posterior::nchains(sd))))
  }
  out
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
