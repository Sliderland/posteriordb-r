# Parse tokens (comments excluded) per R file, largest first.
#   Rscript tools/code-size-by-file.R <package-tree> [<package-tree> ...]
tok <- function(f) { pd <- getParseData(parse(f, keep.source = TRUE)); sum(pd$terminal & pd$token != "COMMENT") }
for (d in commandArgs(TRUE)) { fs <- list.files(file.path(d, "R"), full.names = TRUE); t <- sapply(fs, tok); o <- order(-t)
  cat("==", d, sum(t), "\n"); for (i in o) cat(sprintf("%6d %s\n", t[i], basename(fs[i]))) }
