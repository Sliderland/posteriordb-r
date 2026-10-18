# Differential test, step 1: load one posteriordb package source tree, read
# everything in a database through its public functions, and save the
# results in a plain form (no classes or attributes) for comparison.
#   Rscript tools/differential-dump.R <package-tree> <posterior_database> <out-dir>
# Run once with the fork and once with the rewrite, then compare the two
# folders with tools/differential-compare.R. Each posterior is saved to its
# own file to keep memory use low.
args <- commandArgs(TRUE)
if (length(args) != 3) stop("Usage: Rscript differential-dump.R <package> <database> <out-dir>")
dir.create(args[3], recursive = TRUE, showWarnings = FALSE)
suppressMessages(devtools::load_all(args[1], quiet = TRUE, export_all = FALSE))
cache <- tempfile("pdbcache"); dir.create(cache)
p <- pdb_local(args[2], cache_path = cache)

# Plain values: drop classes and attributes (except names and dim), dates as text.
plain <- function(x) {
  if (inherits(x, "Date")) return(as.character(x))
  if (inherits(x, "draws")) {
    a <- unclass(posterior::as_draws_array(x))
    return(array(as.vector(a), dim = dim(a), dimnames = list(NULL, NULL, dimnames(a)[[3]])))
  }
  if (is.list(x)) {
    out <- lapply(unclass(x), plain)
    names(out) <- names(x)
    return(out)
  }
  keep <- attributes(x)[intersect(names(attributes(x)), c("names", "dim", "dimnames"))]
  attributes(x) <- NULL
  attributes(x) <- keep
  x
}
# Record either the value or the error message, so failures are compared too.
try_plain <- function(expr) tryCatch(plain(expr), error = function(e) list(error = conditionMessage(e)))

out <- list()
out$names <- list(
  posteriors = sort(posterior_names(p)), models = sort(model_names(p)), data = sort(data_names(p)),
  draws = sort(reference_posterior_names(p, "draws")),
  mean_value = sort(reference_posterior_names(p, "mean_value")),
  mean_squared_value = sort(reference_posterior_names(p, "mean_squared_value")))
out$bibliography_keys <- try_plain(sort(names(bibliography(p))))
out$posteriors_tbl_df <- try_plain(as.data.frame(posteriors_tbl_df(p)))

for (pn in out$names$posteriors) {
  cat(pn, "\n")
  po <- tryCatch(posterior(pn, p), error = function(e) e)
  if (inherits(po, "error")) {
    saveRDS(list(error = conditionMessage(po)), file.path(args[3], paste0(pn, ".rds")))
    next
  }
  rec <- list(
    name = po$name, model_name = po$model_name, data_name = po$data_name,
    reference_posterior_name = po$reference_posterior_name, dimensions = plain(po$dimensions),
    keywords = po$keywords, references = po$references, urls = po$urls,
    added_by = po$added_by, added_date = as.character(po$added_date),
    model_info = try_plain(model_info(po)), data_info = try_plain(data_info(po)),
    data = try_plain(get_data(po)), stan_code = try_plain(as.character(stan_code(po))))
  for (fw in names(model_info(po)$model_implementations)) {
    rec$model_code[[fw]] <- try_plain(as.character(model_code(po, framework = fw)))
  }
  if (!is.null(po$reference_posterior_name)) {
    rpd <- reference_posterior_draws(po)
    rec$reference_info <- try_plain(reference_posterior_info(po, type = "draws"))
    rec$reference_draws <- plain(rpd)
    rec$summary_mean_value <- try_plain(reference_posterior_summary_statistic(po, "mean_value"))
    rec$summary_mean_squared_value <- try_plain(reference_posterior_summary_statistic(po, "mean_squared_value"))
    rec$check <- tryCatch({ x <- check_reference_posterior_draws(rpd); plain(info(x)$checks_made) },
                          error = function(e) list(error = conditionMessage(e)))
  }
  saveRDS(rec, file.path(args[3], paste0(pn, ".rds")))
  rm(rec, po); gc(verbose = FALSE)
}
out$check_pdb <- tryCatch(suppressMessages(check_pdb(p, verbose = FALSE)), error = function(e) conditionMessage(e))
saveRDS(out, file.path(args[3], "_database.rds"))
cat("Saved", args[3], "\n")
