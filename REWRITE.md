# posteriordb R package: a from-scratch rewrite

This is a rewrite of the posteriordb R package, done as an exercise. It is
not a pull request, and nothing in `sliderland/posteriordb-r` or
`sliderland/posteriordb` was changed. The reference was a read-only clone of
`sliderland/posteriordb-r` at commit `8f475e2` (called "the fork" below). I
also read the pre-fork package, `stan-dev/posteriordb-r` at `8aeef19`, to
see what was meant to be implemented. That comparison is in
[the last section](#the-pre-fork-package-what-was-meant-and-what-was-built).

The rewrite reads and writes the same database format, and it keeps almost
the whole exported API: 87 of the original 94 exports, plus one new one. It
is about a third of the size.

| | Pre-fork (stan-dev) | Fork (original) | Rewrite |
|---|---|---|---|
| R code | 3,212 lines in 26 files | 9,206 lines in 35 files | 3,245 lines in 16 files |
| Tests | 18 files | 6,009 lines | 768 lines, plus a 100 KB fixture |
| Hard dependencies | bibtex, checkmate, gh, jsonlite, methods, posterior, tibble | same | bibtex, checkmate, jsonlite, posterior, tibble |

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
  and the cmdstanr backend for
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

The offline suite has 250 expectations and runs against a small
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

## The pre-fork package: what was meant and what was built

The fork's history doesn't share commits with `stan-dev/posteriordb-r`, so
this comparison is by content. I compared against upstream `main` at
`8aeef19` (2026-08-06) and the database's own docs (`doc/DATABASE_CONTENT.md`
and `doc/REFERENCE_POSTERIOR_DEFINITION.md`). Upstream's other branches have
nothing unmerged. Upstream's GitHub issues can't be reached from this
session, so open feature requests aren't covered.

**Upstream fell short of its own spec in a few places:**

- **Reference checks.** The definition asks for 10,000 draws, R-hat below
  1.01, lag-1 autocorrelation below 0.05, E-FMI of at least 0.2 and no
  divergent transitions. Upstream checks the draw count, at least 4 chains,
  ESS bounds, R-hat and E-FMI. It never checks lag-1 autocorrelation or
  divergences, even though it stores the divergence counts. It also reads
  the stored diagnostics instead of recomputing them. The fork added the
  two missing checks, and the rewrite keeps all five, recomputed from the
  draws.
- **ESS bounds** are a hard check upstream (ESS within 10,000 ± 4·√(7·10,000)),
  but the spec doesn't ask for them. In the rewrite they're reported but
  don't fail draws, because the band rejects independent draws often enough
  that the tests had to exclude it. This is the one place the rewrite
  knowingly differs from upstream's implemented behaviour.
- **Unused bibliography entries** never fail upstream's `check_pdb()`,
  because the result of that check isn't stored. The rewrite enforces it.
- **E-FMI wording.** The spec says "below 0.2" but means at least 0.2, which
  is what upstream, the stored flags and the rewrite all use.

**Upstream left a few things unfinished, and the rewrite treats them as follows:**

- Only Stan sampling can compute reference draws. Upstream stops with
  "Currently not implemented" for anything else. The rewrite is the same,
  but adds cmdstanr next to rstan.
- Upstream had a half-written `sd` summary statistic that wasn't among its
  supported types. The rewrite keeps the two types the database stores,
  `mean_value` and `mean_squared_value`.
- Upstream's tests skip posteriors without reference draws ("LDA model will
  work from version 0.4"). The rewrite reads those posteriors and gives a
  clear error only when reference draws are asked for.
- The database docs say JSON schemas are "currently not included". Upstream
  enforced closed field lists for data and model info instead.

**What reading upstream changed in the rewrite:**

- `pdb_local()` again accepts a path inside the database, such as
  `.../posterior_database/data/data`, and finds the root above it. Upstream
  tests this. I had dropped it, following the fork.
- Data and model info reject unknown fields, using upstream's field lists,
  so a typo like `keyword` is an error instead of being stored. The full
  database passes.
- `check_pdb_posterior()` reads the reference draws, not just their info,
  as upstream does. It also works on a posterior built in memory that
  hasn't been written yet, which the contributing vignette relies on.
- I ran the non-Stan steps of upstream's contributing vignette against the
  rewrite: data, model, posterior, check and reference info. They work
  unchanged.
- One upstream vignette bug is left as it is. The vignette calls
  `check_pdb_posterior(po, pdbl)`, which passes the database as
  `run_stan_code_checks` and fails in upstream too.

**API compatibility with upstream:** every upstream export exists in the
rewrite except the `assert_checked_*`, `assert_reference_posterior_draws`
and `check_summary_statistics_draws` helpers, which
`check_reference_posterior_draws()` replaces. `thin_draws` remains an S3
method for reference draws. The fork's additions are all kept: fit import,
bundles, renaming, output reconstruction, cmdstanr, and the batch workflow.
