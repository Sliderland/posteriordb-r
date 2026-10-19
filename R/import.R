#' Reference posterior draws from a Stan fit
#'
#' `as_reference_posterior_draws()` turns a completed Stan fit for an
#' existing posterior into reference posterior draws and checks them with
#' [check_reference_posterior_draws()]. Failed checks do not raise an error;
#' they are recorded in `checks_made` and the `check_failures` attribute so
#' the draws can be inspected. `import_reference_posterior_draws()` does the
#' same and, with `write = TRUE`, writes draws that pass to a local database,
#' together with their summary statistics, and links them to the posterior.
#'
#' All saved variables except `lp__` are kept by default. Parameter-block
#' variables and the variables named in the posterior's `dimensions` are
#' always kept. When the fit exposes its unconstrained parameter counts they
#' must match the posterior's `dimensions`. The fit is not compared with the
#' posterior's Stan code or data.
#'
#' @param fit A completed `rstan::stanfit` or `cmdstanr::CmdStanMCMC` fit.
#'   For cmdstanr, sample with `sig_figs = 18` to keep full precision.
#' @param posterior A posterior name or `pdb_posterior` object.
#' @param pdb A [pdb][pdb_local] connection. Must be local to write.
#' @param dimensions Unconstrained parameter counts, if the posterior does
#'   not have them.
#' @param include Base names of extra variables to keep; `NULL` or `"all"`
#'   keeps all, `"none"` only the parameters and posterior dimensions.
#' @param exclude Base names of variables to drop; `"all"` drops everything
#'   except the parameters and posterior dimensions.
#' @param write Write the draws if they pass the checks?
#' @param overwrite Replace existing reference posterior files?
#' @param write_summary_statistics Also write the summary statistics?
#' @param ... Reference info fields: `comments`, `added_by`, `added_date`.
#' @return A `pdb_reference_posterior_draws` object.
#' @export
as_reference_posterior_draws <- function(fit, posterior, pdb = pdb_default(), dimensions = NULL,
                                         include = NULL, exclude = NULL, ...) {
  po <- if (inherits(posterior, "pdb_posterior")) posterior else posteriordb::posterior(posterior, pdb = pdb)
  if (!is.null(dimensions) && length(po$dimensions) &&
      !identical(lapply(as.list(dimensions), as.integer), lapply(po$dimensions, as.integer))) {
    stop2("`dimensions` disagrees with the dimensions of posterior '", po$name, "'.")
  }
  fields <- list(...)
  checkmate::assert_subset(names(fields), c("comments", "added_by", "added_date"))
  fields$name <- po$reference_posterior_name %||% po$name
  rpd <- draws_from_fit(fit, as.list(dimensions %||% po$dimensions), fields, include, exclude,
                        pdb = posteriordb::pdb(po) %||% pdb)
  check_reference_posterior_draws(rpd, error = FALSE)
}

#' @rdname as_reference_posterior_draws
#' @export
import_reference_posterior_draws <- function(fit, posterior, pdb = pdb_default(), dimensions = NULL,
                                             include = NULL, exclude = NULL, write = FALSE,
                                             overwrite = FALSE, write_summary_statistics = TRUE,
                                             ...) {
  checkmate::assert_flag(write)
  if (write) checkmate::assert_class(pdb, "pdb_local")
  rpd <- as_reference_posterior_draws(fit, posterior, pdb = pdb, dimensions = dimensions,
                                      include = include, exclude = exclude, ...)
  if (!write) return(rpd)
  if (!passed_checks(rpd)) {
    stop2("Nothing was written; the draws failed the checks: ",
          format_failures(attr(rpd, "check_failures")))
  }
  name <- if (is.character(posterior)) resolve_alias(posterior, pdb) else posterior$name
  write_pdb(rpd, pdb, overwrite = overwrite, posterior_name = name,
            write_summary_statistics = write_summary_statistics)
  rpd
}

# Build unchecked reference draws from a fit. `fields` holds info fields
# (name, comments, ...); inference and versions come from the fit.
draws_from_fit <- function(fit, dimensions, fields, include = NULL, exclude = NULL, pdb = NULL,
                           method_arguments = NULL) {
  parts <- extract_fit(fit)
  assert_dimensions(dimensions)
  counts <- parts$upar_counts
  if (!is.null(counts)) {
    common <- intersect(names(dimensions), names(counts))
    differ <- common[vapply(common, function(n) prod(unlist(dimensions[[n]])) != counts[[n]],
                            logical(1))]
    if (length(differ)) {
      stop2("The fit's unconstrained parameter counts differ from the posterior dimensions for: ",
            paste(differ, collapse = ", "))
    }
  }
  draws <- select_variables(parts$draws, union(names(dimensions), parts$parameters),
                            include, exclude)
  fields$inference <- list(method = "stan_sampling",
                           method_arguments = method_arguments %||% parts$method_arguments)
  fields$versions <- parts$versions
  fields$diagnostics <- compute_draw_diagnostics(draws, fit = parts)
  rpd <- as.reference_posterior_draws(draws, info = fields, pdb = pdb)
  attr(rpd, "sampler_diagnostics") <- parts$sampler
  rpd
}

#' Compute reference posterior draws with Stan
#'
#' Samples the posterior named in a reference posterior info with Stan,
#' using the info's `method_arguments` (rstan argument names; they are
#' translated for cmdstanr). The draws are returned unchecked; use
#' [check_reference_posterior_draws()] and then [write_pdb()].
#'
#' `sequential_batch_workflow()` runs this for several infos, one after the
#' other, and optionally checks and writes each result. A failure in one
#' workflow is recorded and, with `on_error = "continue"`, the next one runs.
#'
#' @param rpi A reference posterior info whose `name` is a posterior name.
#' @param reference_posteriors A list of reference posterior infos.
#' @param pdb A [pdb][pdb_local] connection.
#' @param backend `"rstan"` or `"cmdstanr"`.
#' @param include,exclude Variable selection, see
#'   [as_reference_posterior_draws()].
#' @param sampling `NULL` to use each info's own arguments, one named list
#'   of sampling arguments for all workflows, or an unnamed list with one
#'   argument list per workflow.
#' @param check,write,overwrite Check, write and overwrite the results?
#'   Writing implies checking.
#' @param on_error `"continue"` with the next workflow or `"stop"`.
#' @return `compute_reference_posterior_draws()` returns
#'   `pdb_reference_posterior_draws`. `sequential_batch_workflow()` returns a
#'   named list with, for each workflow, its `status` (`"completed"`,
#'   `"failed"` or `"not_run"`), the `draws`, whether they were `written`,
#'   and the `error` message if any.
#' @export
compute_reference_posterior_draws <- function(rpi, pdb = pdb_default(),
                                              backend = c("rstan", "cmdstanr"),
                                              include = NULL, exclude = NULL) {
  rpi <- as.reference_posterior_info(rpi)
  if (rpi$inference$method != "stan_sampling") {
    stop2("Only `stan_sampling` reference posteriors can be computed.")
  }
  po <- posterior(rpi$name, pdb = pdb)
  fit <- run_stan(po, rpi$inference$method_arguments %||% list(), backend = backend)
  fields <- plain_list(rpi)[c("name", "comments", "added_by", "added_date")]
  draws_from_fit(fit, po$dimensions, fields, include, exclude, pdb = pdb,
                 method_arguments = rpi$inference$method_arguments)
}

#' @rdname compute_reference_posterior_draws
#' @export
sequential_batch_workflow <- function(reference_posteriors, sampling = NULL, pdb = pdb_default(),
                                      backend = c("rstan", "cmdstanr"), check = TRUE,
                                      write = FALSE, overwrite = FALSE,
                                      on_error = c("continue", "stop")) {
  backend <- match.arg(backend)
  on_error <- match.arg(on_error)
  checkmate::assert_list(reference_posteriors, min.len = 1)
  reference_posteriors <- lapply(reference_posteriors, as.reference_posterior_info)
  workflow_names <- vapply(reference_posteriors, `[[`, "", "name")
  if (anyDuplicated(workflow_names)) stop2("Workflow names must be unique.")
  n <- length(reference_posteriors)
  per_workflow <- !is.null(sampling) && is.null(names(sampling)) &&
    all(vapply(sampling, is.list, logical(1)))
  if (per_workflow && length(sampling) != n) {
    stop2("`sampling` needs one argument list per workflow (", n, ").")
  }
  results <- stats::setNames(vector("list", n), workflow_names)
  for (i in seq_len(n)) {
    rpi <- reference_posteriors[[i]]
    if (!is.null(sampling)) {
      rpi$inference$method_arguments <- if (per_workflow) sampling[[i]] else sampling
    }
    result <- list(name = rpi$name, status = "completed", draws = NULL, written = FALSE, error = NULL)
    stage <- "sampling"
    tryCatch({
      result$draws <- compute_reference_posterior_draws(rpi, pdb = pdb, backend = backend)
      if (check || write) {
        stage <- "checking"
        result$draws <- check_reference_posterior_draws(result$draws)
      }
      if (write) {
        stage <- "writing"
        write_pdb(result$draws, pdb, overwrite = overwrite)
        result$written <- TRUE
      }
    }, error = function(e) {
      result$status <<- "failed"
      result$error <<- paste0(stage, ": ", conditionMessage(e))
    })
    results[[i]] <- result
    if (result$status == "failed" && on_error == "stop") {
      for (j in seq_len(n)[-seq_len(i)]) {
        results[[j]] <- list(name = workflow_names[j], status = "not_run", draws = NULL,
                             written = FALSE, error = NULL)
      }
      break
    }
  }
  structure(results, class = c("pdb_batch_results", "list"))
}

#' @export
print.pdb_batch_results <- function(x, ...) {
  for (r in x) {
    cat0(r$name, ": ", r$status, if (!is.null(r$error)) paste0(" (", r$error, ")"), "\n")
  }
  invisible(x)
}
