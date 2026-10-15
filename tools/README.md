# Reproducing the results

These scripts rerun every test, end-to-end run and comparison reported in
`REWRITE.md`. Run them from the package root.

1. **Set up.** On a Debian or Ubuntu machine, run `sh tools/setup-container.sh`.
   It installs R and the packages from apt, then clones the database, the
   pre-fork package (`stan-dev/posteriordb-r` at `8aeef19`) and the fork
   (`sliderland/posteriordb-r` at `8f475e2`) next to this folder. Elsewhere,
   install R with the packages listed in `DESCRIPTION`, plus devtools and
   roxygen2.
2. **Run.** Use `sh tools/run-all.sh <step>`:

| Step | What it runs |
|---|---|
| `offline` (default) | The test suite against the bundled fixture database. |
| `stan` | One real rstan run of eight schools: import, bundle, write, reconstruct, batch workflow (`tests/testthat/test-stan.R`). |
| `corpus` | `check_pdb()` and recomputed reference checks on the full database (`test-corpus.R`). |
| `github` | Reading over the GitHub API (`test-github.R`). Set `PDB_TEST_GITHUB_REPO=sliderland/posteriordb` where `stan-dev` is unreachable, as it was here. |
| `check` | `roxygen2` and `R CMD check --no-manual`. |
| `vignette` | The non-Stan steps of upstream's contributing vignette (`tools/vignette-flow.R`). |
| `compare` | Exports and arguments compared with the pre-fork package and the fork (`tools/compare-api.R`), and formatter-independent code size (`tools/code-size.R`). |
| `all` | Everything above, with Stan last. |

The test fixture database is built from the real database by
`tests/testthat/fixtures/make_fixture.R`. To rebuild it, run that script
from `tests/testthat/fixtures` with the path to the database:

```sh
Rscript make_fixture.R ../../../../posteriordb/posterior_database
```

Three things in the container needed workarounds, and the scripts include
them:
- rstan needs `rstan_options(boost_lib = "/usr/include")`.
- The `GITHUB_TOKEN` and `GH_TOKEN` variables held placeholders, so they are unset.
- There is no `en_US.UTF-8` locale, so `R CMD check` runs under `C.UTF-8`.
