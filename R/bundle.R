#' Bundle a Stan fit as a new posterior
#'
#' Builds everything needed to add a new posterior to a database from a
#' completed Stan fit: the data, the model code, the posterior, its reference
#' draws and their summary statistics. Nothing is sampled or written; inspect
#' the bundle, then write it with [write_pdb()].
#'
#' Data and model can be new or come from a database. For new ones, give the
#' data as a named list with `data_info` (at least `name` and `title`), and
#' take the model code from the fit or give it as a string, with
#' `model_info` (at least `name` and `title`). Existing ones can be given as
#' `pdb_data` / `pdb_model_code` objects, or as names together with `pdb`.
#' Model code given separately must match the code in the fit.
#'
#' The posterior's `dimensions` are read from the fit when possible, and
#' otherwise inferred by compiling the model with rstan; they can also be
#' given in `posterior_info`. The posterior is named `"<data>-<model>"`
#' unless `posterior_info$name` says otherwise, and the reference draws get
#' the posterior's name.
#'
#' The bundle's posterior keeps its data, model code and reference draws,
#' so [get_data()], [stan_code()] and [reference_posterior_draws()] work on
#' it before it is written.
#'
#' @param fit A completed `rstan::stanfit` or `cmdstanr::CmdStanMCMC` fit.
#' @param data The data the model was fitted to: a named list, a `pdb_data`
#'   object, or a data name in `pdb`.
#' @param model_code `NULL` to use the code in the fit (rstan only), Stan
#'   code as a string, a `pdb_model_code` object, or a model name in `pdb`.
#' @param data_info,model_info,posterior_info,reference_info Named lists of
#'   metadata for new objects, such as `name`, `title`, `description`,
#'   `keywords`, `references` and `urls`. `reference_info` takes `comments`.
#' @param include,exclude Variable selection, see
#'   [as_reference_posterior_draws()].
#' @param check Run [check_reference_posterior_draws()] now? A bundle can be
#'   checked later with that function, and [write_pdb()] checks it if needed.
#' @param pdb A [pdb][pdb_local] connection for data and models given by name.
#' @param added_by,added_date Defaults for all new metadata.
#' @return A `pdb_reference_bundle`: a list with `posterior`, `data`,
#'   `model_code`, `reference_draws` and `summary_statistics` (`NULL` until
#'   the draws pass the checks).
#' @examples
#' \dontrun{
#' bundle <- create_pdb_bundle(
#'   fit, data = stan_data,
#'   data_info = list(name = "study", title = "Study data"),
#'   model_info = list(name = "normal", title = "Normal model")
#' )
#' bundle
#' write_pdb(bundle, pdb_local("~/posteriordb"))
#' }
#' @export
create_pdb_bundle <- function(fit, data, model_code = NULL, data_info = list(),
                              model_info = list(), posterior_info = list(),
                              reference_info = list(), include = NULL, exclude = NULL,
                              check = TRUE, pdb = NULL,
                              added_by = unname(Sys.info()[["user"]]), added_date = Sys.Date()) {
  checkmate::assert_flag(check)
  defaults <- list(added_by = added_by, added_date = added_date)
  with_defaults <- function(x) utils::modifyList(defaults, as.list(x))

  if (is.character(data)) data <- get_data(data, pdb = pdb %||% stop2("`pdb` is needed to read data by name."))
  if (!inherits(data, "pdb_data")) data <- as.pdb_data(data, info = with_defaults(data_info))

  parts <- extract_fit(fit)
  if (is.character(model_code) && !inherits(model_code, "pdb_model_code") &&
      grepl("^[^{};[:space:]]+$", model_code)) {
    model_code <- stan_code(model_code, pdb = pdb %||% stop2("`pdb` is needed to read a model by name."))
  }
  if (is.null(model_code)) {
    if (is.null(parts$model_code)) stop2("The fit does not contain its Stan code; supply `model_code`.")
    model_code <- parts$model_code
  }
  if (!inherits(model_code, "pdb_model_code")) {
    model_code <- as.model_code(model_code, framework = "stan",
                                info = c(with_defaults(model_info), list(framework = "stan")))
  }
  if (!is.null(parts$model_code) && !same_code(parts$model_code, model_code)) {
    stop2("`model_code` differs from the Stan code in the fit.")
  }

  posterior_info <- with_defaults(posterior_info)
  posterior_info$dimensions <- posterior_info$dimensions %||% parts$upar_counts %||%
    infer_posterior_dimensions(model_code, data)
  posterior_info$pdb_model_code <- model_code
  posterior_info$pdb_data <- data
  po <- as.posterior(posterior_info, pdb = NULL)
  po$reference_posterior_name <- po$name

  fields <- c(with_defaults(reference_info), list(name = po$name))
  draws <- draws_from_fit(fit, po$dimensions, fields, include, exclude)
  bundle <- structure(list(posterior = po, data = data, model_code = model_code,
                           reference_draws = draws, summary_statistics = NULL),
                      class = "pdb_reference_bundle")
  if (check) bundle <- check_reference_posterior_draws(bundle, error = FALSE)
  set_bundle_draws(bundle, bundle$reference_draws)
}

same_code <- function(a, b) {
  normalize <- function(x) gsub("[[:space:]]+", " ", trimws(as.character(x)))
  identical(normalize(a), normalize(b))
}

set_bundle_draws <- function(bundle, draws) {
  bundle$reference_draws <- draws
  bundle$posterior$embedded$reference_draws <- draws
  bundle
}

#' @rdname check_reference_posterior_draws
#' @export
check_reference_posterior_draws.pdb_reference_bundle <- function(x, error = FALSE, ...) {
  draws <- check_draws(x$reference_draws, error = error)
  x$summary_statistics <- if (passed_checks(draws)) compute_all_summary_statistics(draws)
  set_bundle_draws(x, draws)
}

#' @export
print.pdb_reference_bundle <- function(x, ...) {
  draws <- x$reference_draws
  cat0("PosteriorDB bundle: ", x$posterior$name, "\n")
  cat0("  data:       ", info(x$data)$name, "\n")
  cat0("  model:      ", info(x$model_code)$name, "\n")
  cat0("  dimensions: ", paste0(names(x$posterior$dimensions), " = ",
                                unlist(x$posterior$dimensions), collapse = ", "), "\n")
  cat0("  draws:      ", posterior::ndraws(draws), " draws, ", posterior::nchains(draws),
       " chains, ", posterior::nvariables(draws), " variables\n")
  status <- if (is.null(info(draws)$checks_made)) {
    "not checked"
  } else if (passed_checks(draws)) {
    "passed"
  } else {
    paste("failed:", format_failures(attr(draws, "check_failures")))
  }
  cat0("  checks:     ", status, "\n")
  invisible(x)
}

#' @rdname write_pdb
#' @export
write_pdb.pdb_reference_bundle <- function(x, pdb, overwrite = FALSE,
                                           write_summary_statistics = TRUE, ...) {
  if (is.null(info(x$reference_draws)$checks_made)) {
    x <- check_reference_posterior_draws(x, error = FALSE)
  }
  accepted <- passed_checks(x$reference_draws)
  plan <- c(plan_data(x$data), plan_model_code(x$model_code),
            plan_posterior(x$posterior, link = accepted))
  if (accepted) {
    plan <- c(plan, plan_reference_draws(x$reference_draws))
    if (write_summary_statistics) {
      for (s in x$summary_statistics) plan <- c(plan, plan_summary_statistic(s))
    }
  } else {
    message("Reference draws were not written; they failed the checks: ",
            format_failures(attr(x$reference_draws, "check_failures")))
  }
  written <- execute_plan(plan, pdb, overwrite)
  invisible(list(written = written, reference_draws_written = accepted, bundle = x))
}
