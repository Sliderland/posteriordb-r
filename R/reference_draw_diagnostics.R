#' Report reference-draw diagnostics for a Stan fit
#'
#' Computes the reference-draw checks directly on a sampled RStan or CmdStanR
#' fit, without building or writing any database objects. Use it to see
#' whether a fit is likely to be accepted, or to look at one check while
#' tuning sampler settings.
#'
#' @param fit a completed `rstan::stanfit` or `cmdstanr::CmdStanMCMC` fit.
#' @param checks character vector of checks: `ndraws`, `nchains`,
#'   `mean_lag1_ac`, `r_hat`, `efmi`, and `divergent_transitions`; or `"all"`.
#' @param include Base names of saved variables to check. The default
#'   `NULL` (or `"all"`) checks every saved output except `lp__`. A base name
#'   selects all of that variable's elements.
#' @param exclude Base names of saved variables to leave out. Naming a
#'   variable in both `include` and `exclude`, using an unknown name, or
#'   leaving nothing to check is an error.
#' @return A list with the measured `metrics`, the `thresholds` they are
#'   compared with, a named logical `status` with one entry per check, and
#'   `failures` naming the variables or chains that failed. A metric that
#'   cannot be computed, such as the autocorrelation of a constant variable,
#'   fails its check. See [check_reference_posterior_draws()] for the
#'   requirements.
#' @examples
#' \dontrun{
#' report <- reference_draw_diagnostics(fit, checks = "mean_lag1_ac")
#' passes_reference_draw_checks(fit, "mean_lag1_ac")
#' }
#' @export
reference_draw_diagnostics <- function(fit, checks = "all", include = NULL,
                                       exclude = NULL) {
  validate_variable_selections(include, exclude)
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

#' Test selected reference-draw checks
#'
#' Returns `TRUE` if the fit passes the selected checks. By default only the
#' lag-1 autocorrelation check is run; use `checks = "all"` to test every
#' reference-draw requirement. A check whose metric cannot be computed counts
#' as failed. See [reference_draw_diagnostics()] for the full report.
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
  selected <- resolve_variable_selection(unique(base), include = include, exclude = exclude)
  vars <- vars[base %in% selected]
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
  if ("mean_lag1_ac" %in% checks) {
    out$mean_lag1_ac <- reference_lag1_ac(draws)
  }
  if ("r_hat" %in% checks) {
    out$r_hat <- reference_variable_diagnostic(draws, posterior::rhat)
  }
  if ("efmi" %in% checks) {
    x <- extracted$metadata$expected_fraction_of_missing_information
    if (is.null(x) && !is.null(extracted$sampler_diagnostics)) {
      x <- sampler_diagnostics_bfmi(
        extracted$sampler_diagnostics,
        posterior::nchains(draws),
        strict = FALSE,
        normalization = if (identical(extracted$fit_class, "stanfit") ||
          !is.null(extracted$metadata$rstan_version)) "draws" else "differences"
      )
    }
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
      out$divergent_transitions <- stats::setNames(sampler_divergence_counts(sd),
        paste0("chain", seq_len(posterior::nchains(sd))))
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

# Map report keys to the existing persisted acceptance schema.
reference_diagnostic_flag_names <- function(summary = FALSE) {
  c(ndraws = if (summary) "ndraws_is_gte_10k" else "ndraws_is_10k",
    nchains = "nchains_is_gte_4", mean_lag1_ac = "abs_mean_lag1_ac_below_0_05",
    r_hat = "r_hat_below_1_01", efmi = "efmi_above_0_2",
    divergent_transitions = "no_divergent_transitions")
}

# Scalar-variable metrics shared by report and stored-diagnostic paths.
reference_variable_diagnostic <- function(draws, fun) {
  draws <- posterior::as_draws_array(draws)
  vars <- posterior::variables(draws)
  stats::setNames(vapply(seq_along(vars), function(j) {
    z <- matrix(draws[, , j], nrow = dim(draws)[1L], ncol = dim(draws)[2L])
    tryCatch(as.numeric(fun(z))[1L], error = function(error) NA_real_)
  }, numeric(1)), vars)
}

sampler_divergence_counts <- function(sampler) {
  vapply(seq_len(posterior::nchains(sampler)), function(i) {
    sum(sampler[, i, "divergent__"])
  }, numeric(1))
}
