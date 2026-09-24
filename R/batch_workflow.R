#' Run reference-posterior sampling workflows sequentially
#'
#' Run one reference-posterior sampling workflow for each supplied
#' [pdb_reference_posterior_info] object. Workflows run one after another and
#' return a result record for each item.
#'
#' `sampling` may be one named list of sampler arguments, shared by every
#' workflow, or a list of named sampler-argument lists. In the latter form,
#' its length must equal the number of reference-posterior info objects; a
#' named outer list must use the workflow names. A single unnamed nested
#' sampling list is shared by all workflows. These arguments replace the method arguments in
#' each reference-posterior info object for this run.
#'
#' @param reference_posteriors a non-empty list of
#'   [pdb_reference_posterior_info] objects.
#' @param sampling either one named list of sampler arguments to reuse, or a
#'   list containing one named sampler-argument list per workflow.
#' @param pdb a PosteriorDB connection containing the posteriors to sample.
#' @param backend sampler backend, either `"rstan"` or `"cmdstanr"`.
#' @param check whether each sampled result should be checked against the
#'   reference-draw requirements.
#' @param write whether checked draws should be written to the database and
#'   linked to their posteriors.
#' @param overwrite whether existing reference-posterior files may be
#'   overwritten when `write = TRUE`.
#' @param on_error either continue with later workflows or stop after the first
#'   failure. With `"stop"`, remaining entries are returned with status
#'   `"not_run"`.
#' @return A named list of per-workflow result records, with class
#'   `sequential_batch_workflow_results`. Each record contains the reference
#'   name, status and last stage, the sampler arguments, returned draws when
#'   available, write and link flags, and an error message when a stage fails.
#' @export
sequential_batch_workflow <- function(
  reference_posteriors,
  sampling,
  pdb = pdb_default(),
  backend = c("rstan", "cmdstanr"),
  check = TRUE,
  write = FALSE,
  overwrite = FALSE,
  on_error = c("continue", "stop")
) {
  backend <- match.arg(backend)
  on_error <- match.arg(on_error)
  checkmate::assert_class(pdb, "pdb")
  checkmate::assert_flag(check)
  checkmate::assert_flag(write)
  checkmate::assert_flag(overwrite)
  if (write && !check) {
    stop("`write = TRUE` requires `check = TRUE`.", call. = FALSE)
  }
  if (write) checkmate::assert_class(pdb, "pdb_local")

  if (!is.list(reference_posteriors) || !length(reference_posteriors)) {
    stop("`reference_posteriors` must be a non-empty list.", call. = FALSE)
  }
  for (i in seq_along(reference_posteriors)) {
    assert_reference_posterior_info(reference_posteriors[[i]])
    if (!identical(reference_posteriors[[i]]$inference$method, "stan_sampling")) {
      stop(
        "Sequential sampling workflows require `stan_sampling` reference info.",
        call. = FALSE
      )
    }
  }
  if (is.null(names(reference_posteriors))) {
    names(reference_posteriors) <- vapply(
      reference_posteriors,
      `[[`,
      character(1),
      "name"
    )
  }
  if (anyNA(names(reference_posteriors)) ||
      any(!nzchar(names(reference_posteriors))) ||
      anyDuplicated(names(reference_posteriors))) {
    stop("Workflow names must be unique, non-empty strings.", call. = FALSE)
  }

  sampling_lists <- normalize_sequential_sampling_lists(
    sampling,
    workflow_names = names(reference_posteriors)
  )

  results <- vector("list", length(reference_posteriors))
  names(results) <- names(reference_posteriors)
  stopped <- FALSE
  for (i in seq_along(reference_posteriors)) {
    workflow_info <- reference_posteriors[[i]]
    sampling_args <- sampling_lists[[i]]
    stage <- "sampling"
    draws <- NULL
    written <- FALSE
    linked <- FALSE
    failure <- NULL

    tryCatch({
      workflow_info$inference$method_arguments <- sampling_args
      draws <- compute_reference_posterior_draws(
        workflow_info,
        pdb = pdb,
        backend = backend
      )

      if (check || write) {
        stage <- "checking"
        draws <- check_reference_posterior_draws(draws)
      }
      if (write) {
        stage <- "writing"
        write_pdb(draws, pdb = pdb, overwrite = overwrite)
        written <- TRUE
        link_reference_posterior(
          posterior = info(draws)$name,
          reference_posterior = info(draws)$name,
          pdb = pdb
        )
        linked <- TRUE
      }
    }, error = function(error) {
      failure <<- conditionMessage(error)
    })

    results[[i]] <- list(
      name = workflow_info$name,
      status = if (is.null(failure)) "completed" else "failed",
      stage = if (is.null(failure)) "completed" else stage,
      sampling = sampling_args,
      draws = draws,
      written = written,
      linked = linked,
      error = failure
    )
    if (!is.null(failure) && identical(on_error, "stop")) {
      stopped <- TRUE
      break
    }
  }

  if (stopped && i < length(reference_posteriors)) {
    for (j in seq.int(i + 1L, length(reference_posteriors))) {
      results[[j]] <- list(
        name = reference_posteriors[[j]]$name,
        status = "not_run",
        stage = "not_started",
        sampling = sampling_lists[[j]],
        draws = NULL,
        written = FALSE,
        linked = FALSE,
        error = NULL
      )
    }
  }
  class(results) <- c("sequential_batch_workflow_results", "list")
  results
}

normalize_sequential_sampling_lists <- function(sampling, workflow_names) {
  if (!is.list(sampling)) {
    stop("`sampling` must be a named argument list or a list of such lists.",
         call. = FALSE)
  }

  n_workflows <- length(workflow_names)
  sampler_argument_names <- c(
    "iter", "warmup", "chains", "thin", "seed", "refresh", "control",
    "cores", "parallel_chains", "iter_sampling", "iter_warmup",
    "threads_per_chain", "save_warmup", "adapt_delta", "max_treedepth",
    "init", "algorithm", "metric", "step_size", "adapt_engaged",
    "fixed_param", "sample_file", "diagnostic_file", "save_dso",
    "open_progress", "show_messages", "pars", "include", "output_dir",
    "output_basename", "sig_figs", "save_latent_dynamics",
    "save_cmdstan_config", "opencl_ids", "max_iterations", "output_refresh"
  )
  sampling_names <- names(sampling)
  named <- !is.null(sampling_names) && !anyNA(sampling_names) &&
    all(nzchar(sampling_names)) && !anyDuplicated(sampling_names)
  all_nested <- length(sampling) > 0L &&
    all(vapply(sampling, is.list, logical(1)))
  named_workflows <- named && all_nested &&
    length(sampling_names) == n_workflows &&
    setequal(sampling_names, workflow_names) &&
    !all(sampling_names %in% sampler_argument_names)
  common <- !length(sampling) || (named && !named_workflows)
  if (common) {
    validate_sequential_sampling_args(sampling)
    return(rep(list(sampling), n_workflows))
  }

  if (named_workflows) {
    sampling <- sampling[workflow_names]
  } else if (named) {
    stop(
      "Named per-workflow sampling lists must have the same names as `reference_posteriors`.",
      call. = FALSE
    )
  }
  if (!all(vapply(sampling, is.list, logical(1)))) {
    stop("Every per-workflow sampling entry must be a list.", call. = FALSE)
  }
  if (length(sampling) == 1L) {
    validate_sequential_sampling_args(sampling[[1L]])
    return(rep(sampling, n_workflows))
  }
  if (length(sampling) != n_workflows) {
    stop(
      "Supply one shared sampling list or exactly one sampling list per workflow.",
      call. = FALSE
    )
  }
  for (args in sampling) validate_sequential_sampling_args(args)
  sampling
}

validate_sequential_sampling_args <- function(args) {
  if (!is.list(args)) {
    stop("Each sampling configuration must be a list.", call. = FALSE)
  }
  if (!length(args)) return(invisible(args))
  if (is.null(names(args)) || anyNA(names(args)) ||
      any(!nzchar(names(args))) || anyDuplicated(names(args))) {
    stop("Sampling arguments must have unique, non-empty names.", call. = FALSE)
  }
  invisible(args)
}
