#' Check the content of a posterior database
#'
#' `check_pdb()` checks that every posterior (or those named) can be read
#' with its model code, data and reference posterior info, that aliases
#' point at posteriors, that every model, data set and reference posterior
#' is used by a posterior, and that cited references and bibliography
#' entries match. `check_pdb_posterior()` checks one posterior, and can also
#' compile its Stan code and run a few iterations.
#'
#' @param pdb A [pdb][pdb_local] connection.
#' @param posterior_names_to_check Posterior names to check; `NULL` checks all.
#' @param run_stan_code_checks Compile and briefly run the Stan code? Needs
#'   rstan.
#' @param verbose Print progress?
#' @param po A posterior.
#' @return `check_pdb()` returns `0L` when everything passed and `1L`
#'   otherwise, invisibly. `check_pdb_posterior()` returns `TRUE` or raises an
#'   error.
#' @export
check_pdb <- function(pdb = pdb_default(), posterior_names_to_check = NULL,
                      run_stan_code_checks = FALSE, verbose = TRUE) {
  say <- function(...) if (verbose) message(...)
  status <- 0L
  attempt <- function(label, expr) {
    result <- tryCatch({ force(expr); NULL }, error = conditionMessage)
    if (is.null(result)) {
      say("- ", label, ": ok")
    } else {
      status <<- 1L
      message("- ", label, ": ", result)
    }
  }
  pns <- posterior_names_to_check %||% posterior_names(pdb)
  say("Checking ", length(pns), " posterior(s):")
  posteriors <- list()
  for (pn in pns) {
    attempt(pn, {
      posteriors[[pn]] <- posterior(pn, pdb = pdb)
      check_pdb_posterior(posteriors[[pn]], run_stan_code_checks, verbose = FALSE)
    })
  }
  if (is.null(posterior_names_to_check)) {
    say("Checking the database:")
    records <- read_all_posterior_records(pdb)
    attempt("aliases", check_aliases(pdb))
    attempt("every model is used", check_used(model_names(pdb), records, "model_name", "Model"))
    attempt("every data set is used", check_used(data_names(pdb), records, "data_name", "Data"))
    attempt("every reference posterior is used",
            check_used(reference_posterior_names(pdb), records, "reference_posterior_name",
                       "Reference posterior"))
    attempt("every bibliography entry is cited", check_bibliography_used(pdb, records))
  }
  if (status == 0L) say("Posterior database is ok.")
  invisible(status)
}

#' @rdname check_pdb
#' @export
check_pdb_posterior <- function(po, run_stan_code_checks = FALSE, verbose = TRUE) {
  checkmate::assert_class(po, "pdb_posterior")
  say <- function(...) if (verbose) message(...)
  assert_posterior(po)
  for (framework in names(po$model_info$model_implementations)) model_code(po, framework)
  say("- model code can be read")
  get_data(po)
  say("- data can be read")
  if (!is.null(po$reference_posterior_name)) {
    reference_posterior_info(po)
    say("- reference posterior info can be read")
  }
  cited <- c(po$references, po$model_info$references, po$data_info$references)
  if (length(cited)) {
    missing <- setdiff(cited, bibliography_keys(posterior_pdb(po)))
    if (length(missing)) stop2("Reference(s) not in the bibliography: ", paste(missing, collapse = ", "))
    say("- references are in the bibliography")
  }
  if (run_stan_code_checks) {
    require_package("rstan", "for Stan code checks")
    utils::capture.output(suppressWarnings(
      run_stan(po, list(iter = 2, warmup = 0, chains = 1, refresh = 0))))
    say("- Stan code compiles and runs")
  }
  invisible(TRUE)
}

check_aliases <- function(pdb) {
  aliases <- pdb_aliases(pdb)
  pns <- posterior_names(pdb)
  bad <- names(aliases)[!unlist(aliases) %in% pns]
  if (length(bad)) stop2("Aliases pointing to unknown posteriors: ", paste(bad, collapse = ", "))
  shadow <- intersect(names(aliases), pns)
  if (length(shadow)) stop2("Aliases that are also posterior names: ", paste(shadow, collapse = ", "))
}

check_used <- function(names, records, field, what) {
  used <- unlist(lapply(records, `[[`, field))
  unused <- setdiff(names, used)
  if (length(unused)) stop2(what, "(s) not used by any posterior: ", paste(unused, collapse = ", "))
}

check_bibliography_used <- function(pdb, records) {
  cited <- unlist(lapply(records, `[[`, "references"))
  for (r in records) {
    cited <- c(cited, model_info(r$model_name, pdb = pdb)$references,
               data_info(r$data_name, pdb = pdb)$references)
  }
  unused <- setdiff(bibliography_keys(pdb), cited)
  if (length(unused)) stop2("Bibliography entries not cited: ", paste(unused, collapse = ", "))
}
