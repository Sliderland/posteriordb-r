
#' Remove objects from local pdb
#'
#' @description a function to simplify removing object from a local pdb.
#' @details Model-code removal follows the selected implementation's declared
#'   path, or the conventional location when the model info does not record one.
#'   `remove_info = TRUE` also removes the model's info JSON; use `FALSE` to
#'   retain metadata for other implementations. Refresh the connection or
#'   clear its cache before reading after removal.
#'   A failed removal raises an error naming the file. The info file is
#'   removed only after the file it describes has been removed.
#'
#' @param x an object to remove to the pdb.
#' @param pdb the pdb to remove from. Currently only a local pdb.
#' @param type supported reference posterior types.
#' @param remove_info should the information JSON be removed as well?
#' @param ... further arguments supplied to methods.
#'
#' @export
remove_pdb <- function(x, pdb, ...){
  checkmate::assert_class(pdb, "pdb_local")
  UseMethod("remove_pdb")
}

#' @rdname remove_pdb
#' @export
remove_pdb.character <- function(x, pdb, ...){
  checkmate::assert_file_exists(x)
  if (!file.remove(x)) stop("Could not remove file: ", x, call. = FALSE)
  TRUE
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_data <- function(x, pdb, remove_info = TRUE,...){
  fn <- paste0(info(x)$name, ".json.zip")
  fp <- pdb_file_path(pdb, "data", "data", fn)
  remove_pdb(fp, pdb)
  if(remove_info) remove_pdb(info(x), pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_data_info <- function(x, pdb, ...){
  fn <- paste0(x$name, ".info.json")
  fp <- pdb_file_path(pdb, "data", "info", fn)
  remove_pdb(fp, pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_model_code <- function(x, pdb, remove_info = TRUE, ...){
  fp <- pdb_local_resource_path(pdb, model_implementation_file_path(info(x), framework(x)))
  remove_pdb(fp, pdb)
  if(remove_info) remove_pdb(info(x), pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_model_info <- function(x, pdb, ...){
  fn <- paste0(x$name, ".info.json")
  fp <- pdb_file_path(pdb, "models", "info", fn)
  remove_pdb(fp, pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_posterior <- function(x, pdb, ...){
  fn <- paste0(x$name, ".json")
  fp <- pdb_file_path(pdb, "posteriors", fn)
  remove_pdb(fp, pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_reference_posterior_draws <- function(x, pdb, remove_info = TRUE, ...){
  fn <- paste0(info(x)$name, ".json.zip")
  fp <- pdb_file_path(pdb, "reference_posteriors", "draws", "draws", fn)
  remove_pdb(fp, pdb)
  if(remove_info) remove_pdb(info(x), type = "draws", pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_reference_posterior_info <- function(x, pdb, type, ...){
  checkmate::assert_choice(type, choices = supported_reference_posterior_types())
  fn <- paste0(x$name, ".info.json")
  type_path <- reference_posterior_type_path(type)
  fp <- pdb_file_path(pdb, "reference_posteriors", type_path, "info", fn)
  remove_pdb(fp, pdb)
}

#' @rdname remove_pdb
#' @export
remove_pdb.pdb_reference_posterior_summary_statistic <- function(x, pdb, remove_info = TRUE, ...){
  fn <- paste0(info(x)$name, ".json")
  sst <- summary_statistic_type(x)
  fp <- pdb_file_path(pdb, "reference_posteriors", "summary_statistics", sst, sst, fn)
  remove_pdb(fp, pdb)
  if(remove_info) remove_pdb(info(x), type = sst, pdb)
}
