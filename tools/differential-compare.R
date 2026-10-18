# Differential test, step 2: compare two dumps from tools/differential-dump.R
# and print every difference, grouped by kind.
#   Rscript tools/differential-compare.R <fork-dir> <rewrite-dir>
args <- commandArgs(TRUE)
diffs <- list()
walk <- function(x, y, path) {
  if (is.list(x) && is.list(y) && !is.null(names(x)) && !is.null(names(y))) {
    for (n in union(names(x), names(y))) {
      if (!n %in% names(x)) diffs[[length(diffs) + 1]] <<- c(path = paste0(path, "/", n), what = "only in rewrite")
      else if (!n %in% names(y)) diffs[[length(diffs) + 1]] <<- c(path = paste0(path, "/", n), what = "only in fork")
      else walk(x[[n]], y[[n]], paste0(path, "/", n))
    }
    return(invisible())
  }
  same <- isTRUE(all.equal(x, y, tolerance = 0, check.attributes = TRUE))
  if (!same) {
    detail <- paste(utils::head(all.equal(x, y, tolerance = 0), 2), collapse = "; ")
    diffs[[length(diffs) + 1]] <<- c(path = path, what = substr(detail, 1, 160))
  }
}
files <- union(list.files(args[1]), list.files(args[2]))
for (f in files) {
  key <- if (f == "_database.rds") "" else paste0("/posteriors/", sub("[.]rds$", "", f))
  fa <- file.path(args[1], f); fb <- file.path(args[2], f)
  if (!file.exists(fa)) { diffs[[length(diffs) + 1]] <- c(path = key, what = "only in rewrite"); next }
  if (!file.exists(fb)) { diffs[[length(diffs) + 1]] <- c(path = key, what = "only in fork"); next }
  walk(readRDS(fa), readRDS(fb), key)
}
if (!length(diffs)) {
  cat("No differences.\n")
} else {
  d <- do.call(rbind, diffs)
  # Group by the path with posterior names removed, so one kind of difference shows once.
  kind <- sub("^/posteriors/[^/]+", "/posteriors/*", d[, "path"])
  for (k in unique(kind)) {
    rows <- which(kind == k)
    cat(sprintf("%s  [%d posterior(s)]\n    e.g. %s: %s\n", k, length(rows),
                d[rows[1], "path"], d[rows[1], "what"]))
  }
  cat("\nTotal differences:", nrow(d), "\n")
}
