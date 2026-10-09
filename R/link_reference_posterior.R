#' Link an existing reference posterior to a posterior
#'
#' Update a local PosteriorDB posterior to point to reference draws that are
#' already stored in the database. Both the reference-posterior information
#' file and draw archive must exist before the link is written.
#'
#' @param posterior a posterior name or [pdb_posterior] object.
#' @param reference_posterior the reference-posterior name. Defaults to
#'   `posterior` when it is a character name, or the object's name otherwise.
#' @param pdb a local destination connection. An explicitly supplied connection
#'   is used even for object input. When omitted, use the object's connection
#'   for a posterior object, or [pdb_default()] for a name.
#' @param verify verify the written link by reading the posterior JSON.
#' @return The updated [pdb_posterior] object, invisibly.
#' @export
link_reference_posterior <- function(
  posterior,
  reference_posterior = NULL,
  pdb = pdb_default(),
  verify = TRUE
) {
  checkmate::assert_flag(verify)

  if (inherits(posterior, "pdb_posterior")) {
    if (missing(pdb)) pdb <- posteriordb::pdb(posterior)
    posterior_name <- posterior$name
  } else {
    posterior_name <- posterior
  }
  assert_pdb_resource_name(posterior_name)
  if (!is.null(reference_posterior)) assert_pdb_resource_name(reference_posterior)
  checkmate::assert_class(pdb, "pdb_local")
  pdb_write_output_path(pdb, "posteriors", "json", posterior_name, info = FALSE)
  target <- posterior.character(posterior_name, pdb = pdb)
  checkmate::assert_class(target, "pdb_posterior")
  if (is.null(reference_posterior)) reference_posterior <- target$name
  link_reference_posterior_object(target, reference_posterior, pdb, verify)
}

link_reference_posterior_object <- function(target, reference_posterior, pdb, verify) {
  assert_pdb_resource_name(reference_posterior)
  pdb_write_output_path(pdb, "posteriors", "json", target$name, info = FALSE)
  current_reference <- target$reference_posterior_name
  if (!is.null(current_reference) &&
      !identical(current_reference, reference_posterior)) {
    stop(
      "Posterior already points to a different reference posterior: ",
      current_reference,
      call. = FALSE
    )
  }

  info_path <- pdb_file_path(
    pdb, "reference_posteriors", "draws", "info",
    paste0(reference_posterior, ".info.json")
  )
  draws_path <- pdb_file_path(
    pdb, "reference_posteriors", "draws", "draws",
    paste0(reference_posterior, ".json.zip")
  )
  if (!file.exists(info_path) || !file.exists(draws_path)) {
    stop(
      "Both reference-posterior info and draw files must exist before linking.",
      call. = FALSE
    )
  }
  reference_info <- jsonlite::read_json(info_path, simplifyVector = FALSE)
  if (!identical(reference_info$name, reference_posterior)) {
    stop("Reference-posterior info name does not match its file name.", call. = FALSE)
  }
  member <- pdb_json_archive_member(draws_path)
  if (!identical(member, paste0(reference_posterior, ".json"))) {
    stop("Reference-draw archive must contain its named JSON file.", call. = FALSE)
  }

  changed <- is.null(current_reference)
  if (changed) {
    target$reference_posterior_name <- reference_posterior
    write_pdb(target, pdb, overwrite = TRUE)
    pdb_clear_cache(pdb)
  }
  if (verify) {
    posterior_path <- pdb_file_path(
      pdb, "posteriors", paste0(target$name, ".json")
    )
    written <- jsonlite::read_json(posterior_path, simplifyVector = FALSE)
    if (!identical(written$reference_posterior_name, reference_posterior)) {
      stop("Posterior reference link failed round-trip verification.", call. = FALSE)
    }
  }
  invisible(target)
}
