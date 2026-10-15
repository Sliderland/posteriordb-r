# Formatter-independent size of R code: parse tokens (comments excluded),
# lines holding code, roxygen and comment lines, and function count.
#   Rscript tools/code-size.R <package-tree> [<package-tree> ...]
measure <- function(dir) {
  files <- list.files(dir, "\\.[Rr]$", full.names = TRUE)
  tok <- 0; code <- 0; rox <- 0; com <- 0; raw <- 0; fns <- 0
  for (f in files) {
    l <- readLines(f, warn = FALSE); raw <- raw + length(l)
    t <- trimws(l)
    rox <- rox + sum(startsWith(t, "#'"))
    com <- com + sum(startsWith(t, "#") & !startsWith(t, "#'"))
    pd <- getParseData(parse(f, keep.source = TRUE))
    pd <- pd[pd$terminal & pd$token != "COMMENT", ]
    tok <- tok + nrow(pd)
    code <- code + length(unique(pd$line1))
    fns <- fns + sum(pd$token == "FUNCTION")
  }
  c(files = length(files), raw_lines = raw, roxygen = rox, comments = com,
    code_lines = code, tokens = tok, functions = fns)
}
for (d in commandArgs(TRUE)) {
  cat(d, "\n R:    "); print(measure(file.path(d, "R")))
  cat(" tests:"); print(measure(file.path(d, "tests/testthat")))
}
