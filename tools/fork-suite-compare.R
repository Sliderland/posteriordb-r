# Compares two runs of tools/fork-suite.R (the fork against its own tests,
# and the rewrite against the same tests): totals, then every test whose
# outcome differs, with the rewrite's first failure or error message. With the
# fork's source tree as a third argument, tests that fail only because they
# call a function the fork does not export are counted, not listed.
#   Rscript tools/fork-suite-compare.R <baseline.rds> <rewrite.rds> [<fork-tree>]
args <- commandArgs(TRUE)
a <- readRDS(args[1]); b <- readRDS(args[2])
cat("Baseline:", paste(names(table(a$outcome)), table(a$outcome), collapse = ", "),
    "|", sum(a$expectations), "expectations\n")
cat("Rewrite: ", paste(names(table(b$outcome)), table(b$outcome), collapse = ", "),
    "|", sum(b$expectations), "expectations\n\n")
key <- function(x) paste(x$file, x$test, sep = " :: ")
m <- merge(data.frame(key = key(a), fork = a$outcome),
           data.frame(key = key(b), rewrite = b$outcome, message = b$message),
           by = "key", all = TRUE)
d <- m[is.na(m$fork) | is.na(m$rewrite) | m$fork != m$rewrite, ]
cat(nrow(d), "tests with a different outcome.\n")
if (length(args) > 2) {
  # Internal functions the tests call directly: "could not find
  # function", "object 'x' not found" and "Can't find binding for `x`".
  ns <- readLines(file.path(args[3], "NAMESPACE"))
  exported <- sub("^export\\((.*)\\)$", "\\1", grep("^export\\(", ns, value = TRUE))
  pattern <- paste0("could not find function \"([^\"]+)\"|object '([^']+)' not found|",
                    "Can't find binding for `([^`]+)`")
  hit <- regmatches(d$message, regexec(pattern, d$message))
  missing <- vapply(hit, function(h) if (length(h)) paste(h[-1], collapse = "") else NA_character_, "")
  # A failed local_mocked_bindings() call mocks an internal function too.
  missing[is.na(missing) & grepl("local_mocked_bindings", d$message)] <- "(a mocked internal)"
  internal <- !is.na(missing) & !missing %in% exported
  cat(sum(internal), "of them call or mock a function the fork does not export:\n")
  print(sort(table(missing[internal]), decreasing = TRUE))
  d <- d[!internal, ]
}
cat("\n", nrow(d), " tests listed:\n\n", sep = "")
for (i in seq_len(nrow(d))) {
  cat(sprintf("%s\n  fork: %s, rewrite: %s\n", d$key[i], d$fork[i], d$rewrite[i]))
  if (!is.na(d$message[i])) cat("  ", gsub("\n", " ", substr(d$message[i], 1, 220)), "\n", sep = "")
}
by_file <- tapply(d$key, sub(" :: .*", "", d$key), length)
cat("\nBy file:\n"); print(sort(by_file, decreasing = TRUE))
