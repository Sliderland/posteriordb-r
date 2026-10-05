#' Compute a Reference Posteriors for a reference posterior info object
#'
#' @param rpi a [reference_posterior_info] object.
#' @param pdb a [pdb] object.
#' @param backend Stan sampler backend, either `"rstan"` or `"cmdstanr"`.
#' @param include Saved base variable names to add to the required parameter
#'   block and posterior dimensions. The default `"none"`, or `character(0)`,
#'   retains only required variables. `NULL` or `"all"` retains every saved
#'   output except `lp__`. All indexed columns of selected variables are kept.
#' @param exclude Saved base variable names to omit from optional outputs.
#'   Required parameter-block and dimension-listed variables cannot be excluded.
#'   The returned draws and their variable diagnostics use the same selection.
#' @details With CmdStanR, `iter`/`warmup` become `iter_sampling`/`iter_warmup`
#'   and `cores` becomes `parallel_chains`. Supported nested RStan controls
#'   are `adapt_delta`, `max_treedepth`, `stepsize`, `adapt_engaged`, `metric`,
#'   `adapt_init_buffer`, `adapt_term_buffer`, and `adapt_window`.
#'   `stepsize` becomes `step_size`; adaptation buffers/window lose the
#'   `adapt_` prefix. Other controls raise an error rather than being discarded.
#'   Supply each setting once: aliases or nested controls cannot override an
#'   explicit native setting. Native CmdStanR arguments can be supplied directly.
#'   NULL `iter`, `warmup`, and `control` entries are omitted. Explicit native
#'   `diagnostics = NULL` remains supported; do not also supply `validate_csv`.
#'
#' @export
compute_reference_posterior_draws <- function(
  rpi,
  pdb = pdb_default(),
  backend = c("rstan", "cmdstanr"),
  include = "none",
  exclude = NULL
) {
  checkmate::assert_class(pdb, "pdb")
  assert_reference_posterior_info(x = rpi)
  backend <- match.arg(backend)
  if (rpi$inference$method == "stan_sampling") {
    rp <- compute_reference_posterior_draws_stan_sampling(
      rpi, pdb, backend, include = include, exclude = exclude
    )
  } else {
    stop("Currently not implemented")
  }
  rp
}

#' Compute reference draws using a Stan sampling backend
#'
#' @param rpi a [reference_posterior_info] object.
#' @param pdb a [pdb] object.
#' @param backend Stan sampler backend, either `"rstan"` or `"cmdstanr"`.
#' @inheritParams compute_reference_posterior_draws
#'
compute_reference_posterior_draws_stan_sampling <- function(
  rpi,
  pdb,
  backend = c("rstan", "cmdstanr"),
  include = "none",
  exclude = NULL
) {
  checkmate::assert_class(pdb, "pdb")
  assert_reference_posterior_info(x = rpi)
  backend <- match.arg(backend)
  if (identical(include, "all")) include <- NULL
  if (identical(include, "none")) include <- character(0)
  include <- validate_variable_selection(include, "include")
  exclude <- validate_variable_selection(exclude, "exclude")
  if ("lp__" %in% include) stop("`lp__` cannot be included in reference draws.", call. = FALSE)
  po <- posterior(rpi$name, pdb = pdb)
  pdn <- posterior_dimension_names(x = po$dimensions)

  stan_object <- run_stan.pdb_posterior(
    po,
    stan_args = rpi$inference$method_arguments,
    backend = backend
  )
  extracted <- extract_external_stan_fit(stan_object)
  if (is.null(include)) {
    include <- unique(sub("\\[.*$", "", setdiff(posterior::variables(extracted$draws), "lp__")))
  }
  selected <- resolve_import_variable_selection(
    extracted$draws, union(pdn, fitted_parameter_names(stan_object)), include, exclude
  )
  draws <- filter_external_posterior_draws(extracted$draws, selected)
  keep_draw_names <- posterior::variables(draws)
  rpi$diagnostics <- compute_stan_sampling_diagnostics(
    x = draws,
    keep_dimensions = keep_draw_names,
    sampler_diagnostics = extracted$sampler_diagnostics,
    expected_fraction_of_missing_information =
      extracted$metadata$expected_fraction_of_missing_information,
    max_treedepth = extracted$metadata$max_treedepth
  )
  rpi$versions <- stan_fit_sampling_versions(extracted$metadata)
  rpd <- as.reference_posterior_draws(
    x = posterior::as_draws_list(draws), info = rpi, pdb = pdb
  )
  subset(rpd, variable = keep_draw_names)
}

stan_fit_sampling_versions <- function(metadata) {
  versions <- pdb_stan_sampling_versions(include_rstan = FALSE)
  versions$r_version <- metadata$r_version %||% versions$r_version
  versions$posterior_version <- metadata$posterior_version %||%
    paste("posterior", utils::packageVersion("posterior"))
  for (name in c(
    "rstan_version", "cmdstanr_version", "cmdstan_version", "stan_version"
  )) {
    if (!is.null(metadata[[name]])) versions[[name]] <- metadata[[name]]
  }
  versions
}


#' @rdname reference_posterior_draws
#' @export
as.reference_posterior_draws.stanfit <- function(
  x,
  info,
  pdb = pdb_default(),
  ...
) {
  checkmate::assert_class(info, "pdb_reference_posterior_info")
  draws <- posterior::as_draws_list(posterior::as_draws(x))
  as.reference_posterior_draws(draws, info = info, pdb = pdb)
}


#' Extract diagnostics
#'
#' @description
#' The function extracts and computes the relevant diagnostics
#'
#' @param x a [stanfit] object.
#' @param keep_dimensions exact names of retained posterior variables
#'
#' @keywords internal
#' @noRd
compute_stan_sampling_diagnostics <- function(
  x,
  keep_dimensions,
  sampler_diagnostics = NULL,
  expected_fraction_of_missing_information = NULL,
  max_treedepth = NULL
) {
  checkmate::assert_character(keep_dimensions)

  d <- list()
  pd <- posterior::subset_draws(
    posterior::as_draws(x),
    variable = keep_dimensions
  )
  vars <- posterior::variables(pd)
  checkmate::assert_set_equal(keep_dimensions, vars)

  # diagnostic_information
  d$diagnostic_information <- list(names = vars)

  # ndraws
  d$ndraws <- posterior::ndraws(pd)

  # nchains
  d$nchains <- posterior::nchains(pd)

  d$effective_sample_size_bulk <- reference_variable_diagnostic(pd, posterior::ess_bulk)
  d$effective_sample_size_tail <- reference_variable_diagnostic(pd, posterior::ess_tail)
  d$r_hat <- reference_variable_diagnostic(pd, posterior::rhat)

  # Mean absolute lag-1 autocorrelation across chains. This is kept as a
  # separate diagnostic from ESS because ESS is informative but is not part
  # of the reference-draw acceptance policy.
  d$mean_lag1_ac <- reference_lag1_ac(pd)

  # Sampler diagnostics are extracted at the external-fit boundary.  The
  # fallback keeps the existing internally-sampled workflow unchanged.
  if (is.null(sampler_diagnostics) && inherits(x, "stanfit")) {
    sampler_diagnostics <- sampler_params_to_draws_array(
      rstan::get_sampler_params(x, inc_warmup = FALSE)
    )
  }

  d$divergent_transitions <- rep(NA_real_, d$nchains)
  if (!is.null(sampler_diagnostics)) {
    sampler_variables <- posterior::variables(sampler_diagnostics)
    if ("divergent__" %in% sampler_variables) {
      d$divergent_transitions <- sampler_divergence_counts(sampler_diagnostics)
    }

    if ("treedepth__" %in% sampler_variables && !is.null(max_treedepth)) {
      d$max_treedepth_exceeded <- vapply(seq_len(posterior::nchains(sampler_diagnostics)), function(i) {
        sum(sampler_diagnostics[, i, "treedepth__"] >= max_treedepth)
      }, numeric(1))
    }

    sampler_summary <- posterior::summarise_draws(sampler_diagnostics)
    d$sampler_parameter_summaries <- lapply(seq_len(nrow(sampler_summary)), function(i) {
      row <- sampler_summary[i, , drop = FALSE]
      as.list(row)
    })
    names(d$sampler_parameter_summaries) <- sampler_summary$variable
  }

  # expected_fraction_of_missing_information
  if (is.null(expected_fraction_of_missing_information) && inherits(x, "stanfit")) {
    expected_fraction_of_missing_information <- rstan::get_bfmi(x)
  }
  d$expected_fraction_of_missing_information <-
    expected_fraction_of_missing_information %||% rep(NA_real_, d$nchains)

  d
}

# Convert rstan's list of per-chain sampler parameter matrices to a posterior
# draws object.  Keeping this conversion here gives future fit extractors a
# stable, posterior-compatible boundary for sampler diagnostics.
sampler_params_to_draws_array <- function(sampler_params) {
  if (is.null(sampler_params) || length(sampler_params) == 0L) return(NULL)
  if (!all(vapply(sampler_params, is.matrix, logical(1)))) return(NULL)

  n_draws <- unique(vapply(sampler_params, nrow, integer(1)))
  variable_names <- unique(lapply(sampler_params, colnames))
  if (length(n_draws) != 1L || length(variable_names) != 1L) return(NULL)
  variable_names <- variable_names[[1L]]
  if (is.null(variable_names)) return(NULL)

  values <- array(
    NA_real_,
    dim = c(n_draws, length(sampler_params), length(variable_names)),
    dimnames = list(
      iteration = NULL,
      chain = as.character(seq_along(sampler_params)),
      variable = variable_names
    )
  )
  for (chain_index in seq_along(sampler_params)) {
    values[, chain_index, ] <- sampler_params[[chain_index]]
  }
  posterior::as_draws_array(values)
}


#' Get parameter names from PosteriorDB unconstrained dimension counts
#'
#' Returns the base parameter names. Each value in the dimensions list must
#' be one positive integer unconstrained-coordinate count, not a constrained
#' output shape. Names are not expanded into indexed draw columns.
#'
#' @param x A named dimensions list or numeric vector containing
#'   positive integer unconstrained parameter counts.
#' @return A character vector of base names, in dimensions-list order.
#' @seealso [infer_posterior_dimensions()]
#' @keywords internal
#' @md
posterior_dimension_names <- function(x) {
  x <- validate_posterior_dimension_counts(x)
  names(x)
}

#' Extract relevant stan versions
#'
#' @param include_rstan Whether to include the installed RStan version when available.
pdb_stan_sampling_versions <- function(include_rstan = TRUE) {
  M <- file.path(
    Sys.getenv("HOME"),
    ".R",
    ifelse(.Platform$OS.type == "windows", "Makevars.win", "Makevars")
  )
  Mfile <- if (file.exists(M)) {
    paste(readLines(M), collapse = "\n")
  } else {
    "[Could not find Makevar file]"
  }
  versions <- list(
    r_Makevars = paste(Mfile, collapse = "\n"),
    r_version = R.version$version.string,
    r_session = paste(
      utils::capture.output(print(utils::sessionInfo())),
      collapse = "\n"
    )
  )
  if (include_rstan && requireNamespace("rstan", quietly = TRUE)) {
    versions$rstan_version <- paste("rstan", utils::packageVersion("rstan"))
  }
  versions
}
