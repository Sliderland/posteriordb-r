# Runs the fork's own test suite against a package source tree and saves
# one row per test: file, test, result, and the first failure or error
# message. Run it against the fork itself (the baseline) and against the
# rewrite, then compare with tools/fork-suite-compare.R.
#   Rscript tools/fork-suite.R <package-tree> <fork-tests-dir> <out.rds>
# Set PDB_TEST_DATABASE=true and PDB_PATH (the posteriordb repository root)
# for the fork's database tests, PDB_TEST_STAN=true for its real Stan tests,
# and CMDSTAN for its CmdStanR tests. Each test file runs in its own R
# process, three at a time: rstan and cmdstanr in one process crash when
# cmdstanr compiles model methods, and a crash then costs only that file.
args <- commandArgs(TRUE)
if (identical(args[1], "--one")) {
  # Load rstan only when a test needs it, with the boost headers it needs here.
  setHook(packageEvent("rstan", "onLoad"),
          function(...) rstan::rstan_options(boost_lib = "/usr/include"))
  suppressMessages(devtools::load_all(args[2], quiet = TRUE))
  res <- testthat::test_file(file.path(args[3], args[4]), reporter = testthat::ListReporter$new(),
                             stop_on_failure = FALSE, stop_on_warning = FALSE,
                             load_package = "none")
  rows <- lapply(res, function(t) {
    kind <- vapply(t$results, function(r) class(r)[1], "")
    first <- function(k) {
      i <- which(kind == k)[1]
      if (is.na(i)) NA_character_ else substr(conditionMessage(t$results[[i]]), 1, 300)
    }
    outcome <- if (any(kind == "expectation_error")) "error"
      else if (any(kind == "expectation_failure")) "failure"
      else if (any(kind == "expectation_skip")) "skip"
      else "pass"
    data.frame(file = args[4], test = t$test, outcome = outcome,
               expectations = sum(kind == "expectation_success"),
               message = switch(outcome, error = first("expectation_error"),
                                failure = first("expectation_failure"),
                                skip = first("expectation_skip"), NA_character_))
  })
  saveRDS(do.call(rbind, rows), args[5])
  quit(save = "no")
}

pkg <- normalizePath(args[1]); tests <- normalizePath(args[2]); out <- args[3]
parts <- tempfile("suite"); dir.create(parts)
files <- list.files(tests, "^test.*[.]R$")
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))
cmds <- sprintf("cd %s && Rscript %s --one %s %s %s %s > %s 2>&1",
                shQuote(tests), shQuote(script), shQuote(pkg), shQuote(tests), shQuote(files),
                shQuote(file.path(parts, paste0(files, ".rds"))),
                shQuote(file.path(parts, paste0(files, ".log"))))
scripts <- file.path(parts, paste0(files, ".sh"))
for (i in seq_along(files)) writeLines(cmds[i], scripts[i])
writeLines(scripts, file.path(parts, "scripts"))
system(sprintf("xargs -P 3 -n 1 sh < %s", shQuote(file.path(parts, "scripts"))))
rows <- lapply(files, function(f) {
  part <- file.path(parts, paste0(f, ".rds"))
  if (file.exists(part)) return(readRDS(part))
  # The file's process died (a crash): record that, with the end of its log.
  log <- readLines(file.path(parts, paste0(f, ".log")), warn = FALSE)
  data.frame(file = f, test = "<file crashed>", outcome = "crash", expectations = 0L,
             message = substr(paste(utils::tail(log, 3), collapse = " "), 1, 300))
})
res <- do.call(rbind, rows)
saveRDS(res, out)
print(table(res$outcome))
