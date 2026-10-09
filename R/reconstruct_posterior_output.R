#' Reconstruct Stan output for a saved PosteriorDB posterior
#'
#' Follow a posterior's stored model, data, and reference-draw links, then call
#' \code{reconstruct_stan_output()}. Names are resolved by the existing readers,
#' including posterior aliases; the posterior name is not split into components.
#'
#' @param posterior_name A saved posterior name or posterior alias, not a
#'   reference-posterior archive name.
#' @param pdb A PosteriorDB connection.
#' @inheritParams reconstruct_stan_output
#' @return The result of \code{reconstruct_stan_output()}, including reconstructed
#'   \code{draws}, a reusable \code{evaluator}, and \code{timings}.
#' @details
#' The reference-draw info must declare \code{inference$method = "stan_sampling"}
#' and the linked model must provide a Stan implementation. These metadata checks
#' do not prove that the draws were generated with that exact source and data.
#' All constrained parameter-block columns must be present in the archive;
#' older archives containing only derived outputs may not be reconstructable.
#'
#' The linked Stan source is compiled with RStan and initialized with the linked
#' data without MCMC. Random generated quantities are regenerated, not recovered
#' exactly. Sampling diagnostics are not reconstructed. Database payloads are
#' not written; normal read caching and compilation may create cache/temp files.
#' @examples
#' \dontrun{
#' pdbl <- pdb_local("/path/to/posterior_database")
#' result <- reconstruct_posterior_output(
#'   "existing_data-existing_model", pdb = pdbl
#' )
#' result$draws
#' }
#' @seealso \code{\link{reconstruct_stan_output}}
#' @export
reconstruct_posterior_output <- function(
  posterior_name, pdb = pdb_default(), variables = NULL,
  seed = 1L, include_unconstrained = FALSE
) {
  checkmate::assert_string(posterior_name, min.chars = 1L)
  checkmate::assert_class(pdb, "pdb")
  po <- posterior(posterior_name, pdb = pdb)
  if (is.null(po$reference_posterior_name)) {
    stop("The posterior has no linked reference draws: ", po$name, call. = FALSE)
  }
  implementation <- po$model_info$model_implementations$stan
  if (is.null(implementation) || is.null(implementation$model_code)) {
    stop("The posterior's model has no Stan implementation: ", po$model_name,
         call. = FALSE)
  }
  reference_info <- reference_posterior_draws_info(po)
  if (!identical(reference_info$inference$method, "stan_sampling")) {
    stop("Reconstruction requires reference draws declaring Stan sampling ",
         "(inference$method = 'stan_sampling').", call. = FALSE)
  }
  reconstruct_stan_output(
    draws = reference_posterior_draws(po),
    model = model_code(po, framework = "stan"),
    data = get_data(po),
    variables = variables,
    seed = seed,
    include_unconstrained = include_unconstrained
  )
}
