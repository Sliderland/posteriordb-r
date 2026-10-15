#!/bin/sh
# Reruns everything reported in REWRITE.md, from the package root:
#   sh tools/run-all.sh [offline|stan|corpus|github|check|vignette|compare|all]
# Defaults to "offline". Paths can be overridden with the variables below.
set -e
PDB_CHECKOUT="${PDB_CHECKOUT:-../posteriordb}"
UPSTREAM="${UPSTREAM:-../upstream-r}"
FORK="${FORK:-../posteriordb-r}"
# Debian's rstan finds Boost headers only with this option set.
RSTAN_SETUP='if (requireNamespace("rstan", quietly = TRUE)) rstan::rstan_options(boost_lib = "/usr/include")'
# The containers' GitHub token variables held placeholders, which gh rejects.
GH_ENV="env -u GITHUB_TOKEN -u GH_TOKEN"

run_tests() { Rscript -e "$RSTAN_SETUP; devtools::test(filter = $1, reporter = 'summary', stop_on_failure = TRUE)"; }

case "${1:-offline}" in
  offline)  Rscript -e "devtools::test(reporter = 'summary', stop_on_failure = TRUE)" ;;
  # One real rstan run of eight schools (4 chains x 26,000 iterations, thinned by 10).
  stan)     (export PDB_TEST_STAN=true; run_tests "'stan'") ;;
  # check_pdb() and recomputed checks for every reference posterior.
  # testthat runs from tests/testthat, so the path is made absolute.
  corpus)   (export PDB_PATH="$(cd "$PDB_CHECKOUT" && pwd)/posterior_database"; run_tests "'corpus'") ;;
  # Reading over the GitHub API; set PDB_TEST_GITHUB_REPO to read another repository.
  github)   (unset GITHUB_TOKEN GH_TOKEN; export PDB_TEST_GITHUB=true; run_tests "'github'") ;;
  check)
    Rscript -e 'roxygen2::roxygenise()'
    out=$(mktemp -d); pkg=$(pwd)
    (cd "$out" && R CMD build "$pkg" && LANG=C.UTF-8 LC_ALL=C.UTF-8 $GH_ENV _R_CHECK_FORCE_SUGGESTS_=false \
      R CMD check --no-manual posteriordb_*.tar.gz) ;;
  vignette) Rscript tools/vignette-flow.R ;;
  compare)
    Rscript tools/compare-api.R "$UPSTREAM" .
    Rscript tools/compare-api.R "$FORK" .
    Rscript tools/code-size.R "$UPSTREAM" "$FORK" . ;;
  all) for step in offline corpus github check vignette compare stan; do sh "$0" "$step"; done ;;
  *) echo "Unknown step: $1" >&2; exit 1 ;;
esac
