# posteriordb R package: a from-scratch rewrite

This is a rewrite of the posteriordb R package, done as an exercise. It is
not a pull request, and nothing in `sliderland/posteriordb-r` or
`sliderland/posteriordb` was changed. The reference was a read-only clone of
`sliderland/posteriordb-r` at commit `8f475e2`.

The rewrite reads and writes the same database format, and it keeps almost
the whole exported API: 87 of the original 94 exports, plus one new one. It
is about a third of the size.

| | Original | Rewrite |
|---|---|---|
| R code | 9,206 lines in 35 files | 3,214 lines in 16 files |
| Tests | 6,009 lines | 749 lines, plus a 100 KB fixture |
| Hard dependencies | bibtex, checkmate, gh, jsonlite, methods, posterior, tibble | bibtex, checkmate, jsonlite, posterior, tibble |

## Design

The package is plain S3 with roxygen2 docs and testthat 3. There is one
file per concern:

- `pdb.R` connects to a database (`pdb_local`, `pdb_github`, `pdb_default`) and handles the file cache.
- `github.R` reads the GitHub contents API through `gh`.
- `posterior.R`, `model.R`, `data.R` and `reference_posterior.R` define the objects and read them.
- `diagnostics.R` computes the reference checks.
- `stan.R` is the only file that knows rstan or cmdstanr.
- `import.R` turns a fit into reference posterior draws.
- `bundle.R` turns a fit into a whole new posterior.
- `write.R` holds `write_pdb`, `remove_pdb` and linking.
- `rename.R`, `check_pdb.R` and `bibliography.R` cover the rest.

Three ideas carry most of the weight:

1. **One boundary to Stan.** `extract_fit()` turns an rstan or cmdstanr fit
   into a plain list with the draws, sampler diagnostics, parameter names,
   unconstrained counts, sampling arguments, versions and code. Everything
   after that point is backend-neutral. Adding a backend means adding one
   method.
2. **Checks are recomputed, never trusted.** The reference checks are
   recomputed from the draws whenever draws are checked or written. Stored
   `checks_made` flags are output only. The policy (10,000 draws, at least
   4 chains, R-hat at most 1.01, mean lag-1 autocorrelation within ±0.05,
   E-FMI at least 0.2, no divergences) lives in one function. ESS bounds are
   reported but don't decide anything.
3. **Writes are plans.** Every `write_pdb` call first computes all the files
   it would write, then compares them with what is on disk (as canonical
   JSON, so formatting doesn't matter):
   - Identical files are skipped.
   - A file whose content differs is an error unless `overwrite = TRUE`, and then nothing is written at all.
   - If a write fails partway through, the files that call created are removed.

   Renames work the same way: they collect every move first, check for
   collisions, then apply the moves.

## Kept

- The database layout and JSON schemas. The rewrite reads the full
  posteriordb unchanged and writes files in the same format.
- The user-facing functions with their names and arguments. This includes
  `posterior()`, `stan_code()`, `get_data()`, `reference_posterior_draws()`,
  the summary statistics, `posteriors_tbl_df()`, `filter_posteriors()`,
  `search_posteriors()`, `write_pdb()`, `remove_pdb()`, `rename_pdb()`,
  `check_pdb()` and `create_pdb_bundle()`. It also includes
  `import_reference_posterior_draws()`, `compute_reference_posterior_draws()`,
  `sequential_batch_workflow()`, `reconstruct_stan_output()` and
  `infer_posterior_dimensions()`.
- Aliases, bibliography lookup and appending, and the `pdb_path` option and
  `PDB_PATH` environment variable.
- Both Stan backends, rstan and cmdstanr.

## Dropped

- The `remotes`, `httr` and `git2r` dependencies. The local git version is
  read straight from `.git`, and GitHub goes through `gh` only. `gh` is now
  a suggested package rather than a hard dependency.
- Symlink hardening and the transactional staging directory for writes.
  Plan-then-write with cleanup gives the same guarantee for the realistic
  failure modes, in much less code.
- The hand-written BibTeX tokenizer. The `bibtex` package does the parsing.
- The `policy` argument. There is one policy.
- The `_from_stanfit` and `_from_cmdstanr` variants of
  `as_reference_posterior_draws()`. The generic dispatches on the fit.
- The `assert_checked_*` and `check_summary_statistics_draws` exports. Use
  `check_reference_posterior_draws()`.
- `pdb_compare_stan_models()`, the `"all"` and `"none"` selector aliases,
  searching parent directories for a database, and the cmdstanr backend for
  `infer_posterior_dimensions()`. That one still uses rstan, and counts
  can also be read from a cmdstanr fit.

## Changed

- **Checks are recomputed from the draws** rather than read from stored
  flags. Against the full database, all 57 stored reference posteriors pass.
  The original's check fails all 57 because of a stored flag none of them
  has.
- **Legacy dimensions are accepted.** Three posteriors store a shape such as
  `[3, 2]` instead of a count. These are accepted and compared by their
  product.
- **Identical writes are skipped**, so re-running a workflow is a no-op
  instead of an error.
- **Subsetting and thinning** keep the reference class and clear
  `checks_made`, so modified draws must be checked again before they can be
  written. Thinning keeps the sampler diagnostics, so E-FMI can still be
  computed.
- **Tables use `NA`** rather than the string `"NULL"` for posteriors without
  a reference.
- **`pdb_clear_cache()`** is new. Zipped files are re-extracted
  automatically when the zip is newer than the cache.

## Tests and checks

The offline suite has 244 expectations and runs against a small
eight-schools fixture database. The fixture is cut from the real files and
can be rebuilt with `tests/testthat/fixtures/make_fixture.R`. It covers
reading, checks, writing and renaming. Fit import and bundles use a mocked
cmdstanr fit. **All pass.**

Opt-in tests, each run once here:

- **Real rstan run** (`PDB_TEST_STAN=true`): eight schools, 4 chains, thinned
  to 2,500 draws each. It covers parameter counts, import, bundle writing,
  output reconstruction, `compute_reference_posterior_draws()` and the
  batch workflow. **Passes.** Unthinned NUTS draws of this model fail the
  lag-1 autocorrelation check because they are anticorrelated. That matches
  why the stored references are thinned by 10.
- **Full database** (`PDB_PATH=<posteriordb>/posterior_database`):
  `check_pdb()` plus a recomputed check of every stored reference posterior.
  **Passes.**
- **GitHub** (`PDB_TEST_GITHUB=true`): reads a posterior, its data, code and
  reference draws over the API. **Passes** against `sliderland/posteriordb`.
  This session can't reach `stan-dev/posteriordb`.

`R CMD check --no-manual` gives **0 errors, 0 warnings, 1 note**. The note is
that cmdstanr isn't installed here.

## Not verified

- The cmdstanr path has only been tested with a mocked fit, because
  cmdstanr and CmdStan aren't installed in this environment.
- `reconstruct_stan_output()` has only been run on rstan.
