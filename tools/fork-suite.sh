#!/bin/sh
# Runs the fork's test suite against a package tree (see tools/fork-suite.R).
#   sh tools/fork-suite.sh <package-tree> <fork-repo> <posteriordb-repo> <cmdstan-path> <out.rds>
# The fork's tests are copied to a temporary folder first, so the fork
# checkout is never written to.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
tests=$(mktemp -d)
cp -r "$2/tests" "$tests/"
cd "$here"
PDB_TEST_DATABASE=true PDB_TEST_STAN=true PDB_PATH="$3" CMDSTAN="$4" \
  env -u GITHUB_TOKEN -u GH_TOKEN Rscript tools/fork-suite.R "$1" "$tests/tests/testthat" "$5"
