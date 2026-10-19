#!/bin/sh
# Sets up a Debian/Ubuntu container like the one these results came from:
# R and every package from apt (CRAN and Posit Package Manager were blocked
# there), plus read-only clones of the database and the two older packages.
#   sh tools/setup-container.sh [clone-dir]     (default: ..)
set -e
dest="${1:-..}"
apt-get update
apt-get install -y zip git r-base-core r-base-dev \
  r-cran-bibtex r-cran-checkmate r-cran-jsonlite r-cran-posterior r-cran-tibble \
  r-cran-gh r-cran-yaml r-cran-dplyr r-cran-withr r-cran-testthat \
  r-cran-rstan r-cran-stanheaders r-cran-bh r-cran-rcppeigen \
  r-cran-devtools r-cran-roxygen2
# The database, for the full-database test and the fixture script.
[ -d "$dest/posteriordb" ] || git clone https://github.com/stan-dev/posteriordb "$dest/posteriordb"
# The pre-fork package and the fork, for tools/compare-api.R.
[ -d "$dest/upstream-r" ] || git clone https://github.com/stan-dev/posteriordb-r "$dest/upstream-r"
(cd "$dest/upstream-r" && git checkout -q 8aeef19)
[ -d "$dest/posteriordb-r" ] || git clone https://github.com/sliderland/posteriordb-r "$dest/posteriordb-r"
(cd "$dest/posteriordb-r" && git checkout -q 8f475e2)
# CmdStanR and CmdStan, for the cmdstanr workflows and the fork's test suite
# (tools/workflow-run.R, tools/fork-suite.sh). cmdstanr comes from its git tag
# because CRAN and r-universe were blocked; v0.9.0 works with the apt
# data.table. CmdStan is built from its release tarball.
apt-get install -y r-cran-data.table r-cran-processx r-cran-r6 r-cran-rlang
if ! Rscript -e 'quit(status = !requireNamespace("cmdstanr", quietly = TRUE))'; then
  [ -d "$dest/cmdstanr-src" ] || git clone https://github.com/stan-dev/cmdstanr "$dest/cmdstanr-src"
  (cd "$dest/cmdstanr-src" && git checkout -q v0.9.0)
  R CMD INSTALL "$dest/cmdstanr-src"
fi
if [ ! -d "$dest/cmdstan-2.36.0" ]; then
  curl -sSL -o "$dest/cmdstan.tar.gz" \
    https://github.com/stan-dev/cmdstan/releases/download/v2.36.0/cmdstan-2.36.0.tar.gz
  (cd "$dest" && tar xzf cmdstan.tar.gz && cd cmdstan-2.36.0 && make -j4 build)
fi
