# Reproducing the results

These scripts rerun every test, end-to-end run and comparison reported in
`REWRITE.md`. Run them from the package root.

1. **Set up.** On a Debian or Ubuntu machine, run `sh tools/setup-container.sh`.
   It installs R and the packages from apt, then clones the database, the
   pre-fork package (`stan-dev/posteriordb-r` at `8aeef19`) and the fork
   (`sliderland/posteriordb-r` at `8f475e2`) next to this folder. It also
   installs cmdstanr 0.9.0 from its git tag and builds CmdStan 2.36.0 there. Elsewhere,
   install R with the packages listed in `DESCRIPTION`, plus devtools and
   roxygen2.
2. **Run.** Use `sh tools/run-all.sh <step>`:

| Step | What it runs |
|---|---|
| `offline` (default) | The test suite against the bundled fixture database. |
| `stan` | One real rstan run of eight schools: import, bundle, write, reconstruct, batch workflow (`tests/testthat/test-stan.R`). |
| `cmdstanr` | One real CmdStanR run of the same model (`tests/testthat/test-cmdstanr.R`), in its own R process. Set `CMDSTAN` if CmdStan isn't at `../cmdstan-2.36.0`. |
| `corpus` | `check_pdb()` and recomputed reference checks on the full database (`test-corpus.R`). |
| `github` | Reading over the GitHub API (`test-github.R`). Set `PDB_TEST_GITHUB_REPO=sliderland/posteriordb` where `stan-dev` is unreachable, as it was here. |
| `check` | `roxygen2` and `R CMD check --no-manual`. |
| `vignette` | The non-Stan steps of upstream's contributing vignette (`tools/vignette-flow.R`). |
| `compare` | Exports and arguments compared with the pre-fork package and the fork (`tools/compare-api.R`), and formatter-independent code size (`tools/code-size.R`). |
| `differential` | Reads every posterior, data set, model, reference posterior, summary and check verdict in the full database with both the fork and the rewrite, and lists every difference (`tools/differential-dump.R`, `tools/differential-compare.R`). |
| `workflows` | Fit import, bundles, renaming, removing, linking, reconstruction and the batch sampling workflow, run by the fork and by the rewrite on fresh copies of the fixture, with rstan and with cmdstanr, then every difference (`tools/workflow-fits.R`, `tools/workflow-run.R`, `tools/differential-compare.R ... scenarios`). |
| `fork-suite` | The fork's 53 test files, each in its own R process, against the fork and then the rewrite, then every test whose outcome differs (`tools/fork-suite.sh`, `tools/fork-suite.R`, `tools/fork-suite-compare.R`). |
| `all` | Everything above. |

The test fixture database is built from the real database by
`tests/testthat/fixtures/make_fixture.R`. To rebuild it, run that script
from `tests/testthat/fixtures` with the path to the database:

```sh
Rscript make_fixture.R ../../../../posteriordb/posterior_database
```

Four things in the container needed workarounds, and the scripts include
them:
- rstan needs `rstan_options(boost_lib = "/usr/include")`.
- The `GITHUB_TOKEN` and `GH_TOKEN` variables held placeholders, so they are unset.
- There is no `en_US.UTF-8` locale, so `R CMD check` runs under `C.UTF-8`.
- Loading rstan and cmdstanr in one R process crashed when cmdstanr compiled
  its model methods, so each backend, and each fork test file, gets its own
  process.
