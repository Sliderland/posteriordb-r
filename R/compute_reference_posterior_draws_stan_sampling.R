#' Compute a Reference Posteriors for a reference posterior info object
#'
#' @param rpi a [reference_posterior_info] object.
#' @param pdb a [pdb] object.
#' @param backend Stan sampler backend, either `"rstan"` or `"cmdstanr"`.
#'
#' @export
compute_reference_posterior_draws <- function(
  rpi,
  pdb = pdb_default(),
  backend = c("rstan", "cmdstanr")
) {
  checkmate::assert_class(pdb, "pdb")
  assert_reference_posterior_info(x = rpi)
  backend <- match.arg(backend)
  if (rpi$inference$method == "stan_sampling") {
    rp <- compute_reference_posterior_draws_stan_sampling(rpi, pdb, backend)
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
#'
compute_reference_posterior_draws_stan_sampling <- function(
  rpi,
  pdb,
  backend = c("rstan", "cmdstanr")
) {
  checkmate::assert_class(pdb, "pdb")
  assert_reference_posterior_info(x = rpi)
  backend <- match.arg(backend)
  po <- posterior(rpi$name, pdb = pdb)
  pdn <- posterior_dimension_names(x = po$dimensions)

  stan_object <- run_stan.pdb_posterior(
    po,
    stan_args = rpi$inference$method_arguments,
    backend = backend
  )
  if (identical(backend, "rstan")) {
    rpi$versions <- pdb_stan_sampling_versions()
    rpi$diagnostics <- compute_stan_sampling_diagnostics(
      x = stan_object,
      keep_dimensions = pdn
    )
    rpd <- as.reference_posterior_draws(
      x = stan_object,
      info = rpi,
      pdb = pdb
    )
  } else {
    extracted <- extract_external_stan_fit(stan_object)
    draws <- posterior::subset_draws(extracted$draws, variable = pdn)
    rpi$diagnostics <- compute_stan_sampling_diagnostics(
      x = draws,
      keep_dimensions = pdn,
      sampler_diagnostics = extracted$sampler_diagnostics,
      expected_fraction_of_missing_information =
        extracted$metadata$expected_fraction_of_missing_information,
      max_treedepth = extracted$metadata$max_treedepth
    )
    rpi$versions <- stan_fit_sampling_versions(extracted$metadata)
    rpd <- as.reference_posterior_draws(
      x = posterior::as_draws_list(draws),
      info = rpi,
      pdb = pdb
    )
  }
  subset(rpd, variable = pdn)
}

stan_fit_sampling_versions <- function(metadata) {
  versions <- list(
    r_version = metadata$r_version %||% R.version$version.string,
    posterior_version = metadata$posterior_version %||%
      paste("posterior", utils::packageVersion("posterior"))
  )
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
  pds <- posterior::summarise_draws(pd)
  checkmate::assert_set_equal(keep_dimensions, pds$variable)

  # diagnostic_information
  d$diagnostic_information <- list(names = pds$variable)

  # ndraws
  d$ndraws <- posterior::ndraws(pd)

  # nchains
  d$nchains <- posterior::nchains(pd)

  # ESS bulk
  d$effective_sample_size_bulk <- stats::setNames(
    pds$ess_bulk,
    pds$variable
  )

  # ESS tail
  d$effective_sample_size_tail <- stats::setNames(
    pds$ess_tail,
    pds$variable
  )

  # r_hat
  d$r_hat <- stats::setNames(pds$rhat, pds$variable)

  # Mean absolute lag-1 autocorrelation across chains. This is kept as a
  # separate diagnostic from ESS because ESS is informative but is not part
  # of the reference-draw acceptance policy.
  d$mean_lag1_ac <- mean_lag1_ac(pd)

  # Sampler diagnostics are extracted at the external-fit boundary.  The
  # fallback keeps the existing internally-sampled workflow unchanged.
  if (is.null(sampler_diagnostics)) {
    sampler_diagnostics <- sampler_params_to_draws_array(
      rstan::get_sampler_params(x, inc_warmup = FALSE)
    )
  }

  if (!is.null(sampler_diagnostics)) {
    sampler_variables <- posterior::variables(sampler_diagnostics)
    if ("divergent__" %in% sampler_variables) {
      d$divergent_transitions <- vapply(seq_len(posterior::nchains(sampler_diagnostics)), function(i) {
        sum(sampler_diagnostics[, i, "divergent__"])
      }, numeric(1))
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
  if (is.null(expected_fraction_of_missing_information)) {
    expected_fraction_of_missing_information <- rstan::get_bfmi(x)
  }
  d$expected_fraction_of_missing_information <- expected_fraction_of_missing_information

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


#' Construct dimension names from a posterior dimension list
#'
#' Scalars may be represented by `integer(0)` or `1`; vectors with more than
#' one element and higher-dimensional arrays use Stan's indexed variable
#' names. The first index varies fastest. A one-element vector cannot be
#' distinguished from a scalar in the current PosteriorDB dimension format.
#'
#' @param x a named dimensions slot from a [pdb_posterior]
posterior_dimension_names <- function(x) {
  checkmate::assert_list(x, min.len = 1L)
  checkmate::assert_named(x)
  checkmate::assert_character(names(x), min.chars = 1L, unique = TRUE)

  dn <- Map(
    function(parameter, dims) {
      # RStan represents scalars as integer(0)
      if (length(dims) == 0L) {
        return(parameter)
      }

      checkmate::assert_integerish(
        dims,
        lower = 1,
        upper = .Machine$integer.max,
        min.len = 1,
        any.missing = FALSE
      )

      dims <- as.integer(dims)

      # Scalar explicitly represented as 1
      if (length(dims) == 1L && dims == 1L) {
        return(parameter)
      }

      indices <- do.call(
        expand.grid,
        c(
          lapply(dims, seq_len),
          KEEP.OUT.ATTRS = FALSE,
          stringsAsFactors = FALSE
        )
      )

      paste0(
        parameter,
        "[",
        apply(indices, 1L, paste, collapse = ","),
        "]"
      )
    },
    names(x),
    x
  )

  unlist(dn, use.names = FALSE)
}

#' Extract relevant stan versions
pdb_stan_sampling_versions <- function() {
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
  if (requireNamespace("rstan", quietly = TRUE)) {
    versions$rstan_version <- paste("rstan", utils::packageVersion("rstan"))
  }
  versions
}
