#' Link an existing reference posterior to a posterior
#'
#' Update a local PosteriorDB posterior to point to reference draws that are
#' already stored in the database. Both the reference-posterior information
#' file and draw archive must exist before the link is written.
#'
#' @param posterior a posterior name or [pdb_posterior] object.
#' @param reference_posterior the reference-posterior name. Defaults to
#'   `posterior` when it is a character name, or the object's name otherwise.
#' @param pdb a local PosteriorDB connection. Defaults to [pdb_default()].
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
    pdb <- pdb(posterior)
    checkmate::assert_string(posterior$name, min.chars = 1L)
    assert_link_resource_name(posterior$name, "posterior")
    target <- posterior.character(posterior$name, pdb = pdb)
  } else {
    checkmate::assert_string(posterior, min.chars = 1L)
    assert_link_resource_name(posterior, "posterior")
    target <- posterior.character(posterior, pdb = pdb)
  }
  checkmate::assert_class(pdb, "pdb_local")
  checkmate::assert_class(target, "pdb_posterior")
  if (is.null(reference_posterior)) reference_posterior <- target$name
  checkmate::assert_string(reference_posterior, min.chars = 1L)
  assert_link_resource_name(reference_posterior, "reference posterior")
  link_reference_posterior_object(target, reference_posterior, pdb, verify)
}

link_reference_posterior_object <- function(target, reference_posterior, pdb, verify) {
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
  members <- tryCatch(utils::unzip(draws_path, list = TRUE)$Name,
                      error = function(error) character())
  members <- members[!grepl("/$", members)]
  if (length(members) != 1L || !identical(members[[1L]], paste0(reference_posterior, ".json"))) {
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

assert_link_resource_name <- function(name, label) {
  if (name %in% c(".", "..") || grepl("[/\\\\]", name) ||
      grepl("[[:cntrl:]]", name)) {
    stop("The ", label, " name must be a single path component.", call. = FALSE)
  }
  invisible(name)
}
