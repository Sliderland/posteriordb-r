# Compares the exported API of two package source trees: exports missing on
# either side, exports whose arguments differ, and S3 methods only in the
# first tree. Used to compare the rewrite with the original packages.
#   Rscript tools/compare-api.R <other-package-tree> <this-package-tree>
args <- commandArgs(TRUE)
if (length(args) != 2) stop("Usage: Rscript compare-api.R <other> <this>")
load_tree <- function(path) {
  e <- new.env()
  for (x in list.files(file.path(path, "R"), full.names = TRUE)) sys.source(x, envir = e, toplevel.env = e)
  ns <- readLines(file.path(path, "NAMESPACE"))
  ex <- gsub("\"", "", sub("^export\\((.*)\\)$", "\\1", grep("^export\\(", ns, value = TRUE)))
  s3 <- sub("^S3method\\(([^,]+),([^,)]+).*", "\\1.\\2", grep("^S3method\\(", ns, value = TRUE))
  list(ex = ex, s3 = s3, e = e)
}
other <- load_tree(args[1]); this <- load_tree(args[2])
cat("Exports only in", args[1], ":\n"); print(setdiff(other$ex, this$ex))
cat("\nExports only in", args[2], ":\n"); print(setdiff(this$ex, other$ex))
cat("\nExports whose arguments differ:\n")
for (x in intersect(other$ex, this$ex)) {
  fo <- names(formals(get(x, other$e))); ft <- names(formals(get(x, this$e)))
  if (!identical(fo, ft)) {
    cat(sprintf("%-45s other: %s\n%-45s this:  %s\n", x, paste(fo, collapse = ","), "",
                paste(ft, collapse = ",")))
  }
}
cat("\nS3 methods only in", args[1], ":\n"); print(setdiff(other$s3, this$s3))
