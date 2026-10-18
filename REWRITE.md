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
is about 40% of the fork's size.

The fork is formatted with Air, which puts many arguments on lines of their
own, and the rewrite is not. Raw line counts therefore flatter the rewrite.
Parse tokens (from `getParseData()`, comments excluded) don't depend on
formatting, so the token rows are the fair comparison.
`tools/code-size.R` computes all of these.

| | Pre-fork (stan-dev) | Fork (original) | Rewrite |
|---|---|---|---|
| R code, parse tokens | 15,088 | 46,578 | 19,649 |
| R code, lines with code | 1,843 | 6,698 | 2,008 |
| R code, raw lines (files) | 3,212 (26) | 9,206 (35) | 3,245 (16) |
| Roxygen lines | 870 | 1,722 | 864 |
| Tests, parse tokens | 5,293 | 48,338 | 6,945 |
| Tests, raw lines (files) | 934 (18) | 6,009 (55) | 771 (8), plus a 100 KB fixture |
| Hard dependencies (Imports) | checkmate, gh, jsonlite | bibtex, checkmate, gh, jsonlite, methods, posterior, tibble | bibtex, checkmate, jsonlite, posterior, tibble |

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
   after that point is backend-neutral. A new backend needs an
   `extract_fit()` method, plus its sampling and evaluation code in `stan.R`.
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
   - If a write fails partway through, the files that call created are removed. Files it had already replaced (with `overwrite = TRUE`) are not restored.
   - Numbers count as equal when they agree to about 12 significant digits. That absorbs JSON formatting differences, but not real changes.

   Renames work the same way: they collect every move first, check for
   collisions, then apply the moves.

## Kept

- The database layout and JSON schemas. The rewrite reads the full
  posteriordb unchanged and writes files in the same format.
- The user-facing function names. Most arguments match too. The
  differences are listed under
  [Feature parity with the fork](#feature-parity-with-the-fork). The kept
  functions include
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
  Plan-then-write with cleanup covers conflicts and partial failures in much
  less code. It doesn't protect against symlinks inside the database or
  restore replaced files.
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

- **Checks are recomputed from the draws.** The fork's
  `check_reference_posterior_draws()` evaluates the diagnostic values
  stored in the info file. Only lag-1 autocorrelation is computed when it's
  missing. The rewrite computes every metric from the draws and the sampler
  diagnostics.
  - Both pass all 57 stored reference posteriors in the full database.
  - The fork's `assert_checked_reference_posterior_draws()` rejects all 57,
    because none of them has a `no_divergent_transitions` flag.
- **Legacy dimensions are accepted.** Three posteriors store a shape such as
  `[3, 2]` instead of a count. These are accepted and compared by their
  product.
- **Identical writes are skipped**, so re-running a workflow is a no-op.
  The fork raises "File at path already exists" instead.
- **Tables use `NA`** rather than the string `"NULL"` for posteriors without
  a reference.
- **`pdb_clear_cache()`** is exported. It was internal in the fork and
  upstream.
- **Zipped files are re-extracted** automatically when the zip is newer than
  the cached copy.

## Tests and checks

Everything in this section, plus the vignette run and API comparison
below, can be rerun with `tools/run-all.sh`. `tools/README.md` explains the
setup and each step.

The offline suite has 251 expectations and runs against a small
eight-schools fixture database. The fixture is cut from the real files and
can be rebuilt with `tests/testthat/fixtures/make_fixture.R`. It covers
reading, checks, writing and renaming. Fit import and bundles use a mocked
cmdstanr fit. **All pass.**

The opt-in tests below were run on the final code, the Stan test twice:

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

## Does it do the same thing as the fork?

The reading side is checked by running both packages on the full database
and comparing what comes back. The writing side is checked with a smaller
example. Run both with `sh tools/run-all.sh differential`.

**Reading: the full database through both packages.**
`tools/differential-dump.R` loads one package and reads everything in the
database through its public functions. That covers, for all 148
posteriors:
- the posterior record, model info, data info and data;
- Stan and other model code;
- for the 58 posteriors linked to a reference posterior: the reference info,
  every draw, both summary statistics and the verdict of
  `check_reference_posterior_draws()`;
- for the database: name lists, bibliography keys, `posteriors_tbl_df()`
  and `check_pdb()`.

`tools/differential-compare.R` compares the two results with zero numeric
tolerance. A planted change of one part in 10¹⁵ in one draw is reported, so
the comparison is strict enough to catch a real difference.

Everything matches exactly except four differences, all explained:

| Difference | Fork | Rewrite |
|---|---|---|
| 3 posteriors whose dimensions are stored as shapes (`hmm_gaussian_simulated-hmm_gaussian`, `iohmm_reg_simulated-iohmm_reg`, `state_wide_presidential_votes-hierarchical_gp`) | `posterior()` errors | Reads them. None has a reference posterior. |
| `check_pdb()` on the full database | Returns 1, failing on those 3 | Returns 0 |
| `posteriors_tbl_df()` for posteriors without a reference | The string `"NULL"` | `NA` |
| `stan_code()` for a model with no Stan code | Error from `checkmate` | Error naming the model |

One API difference showed up while writing the harness. The fork's
`reference_posterior_info(po)` requires `type`, and the rewrite defaults it
to `"draws"`.

**Writing: the same objects through both packages.**
`tools/differential-write.R` writes a new data set, model and posterior
into fresh copies of the test fixture database, using upstream's vignette
objects. All written files have identical content. Two JSON files list the
same fields in a different order, and the zip archives differ only in their
timestamps.

**What this doesn't cover yet:**
- Importing fits, bundles, renaming, removing and writing reference draws
  aren't compared between the two packages. They're covered only by the
  rewrite's own tests.
- The rewrite's mock cmdstanr fit doesn't satisfy the fork's extraction
  code, so comparing imports needs real fits.
- The strongest remaining check is to run the fork's 55 test files against
  the rewrite. Where they test the same public behaviour, they should pass.
  Where they fail, each failure is either a parity gap or a deliberate
  change.

## Why the rewrite is smaller

Parse tokens by area (formatting doesn't affect these):

| Area | Fork | Rewrite |
|---|---|---|
| Fit import, sampling, diagnostics, reconstruction, batch workflow | 16,114 | 5,510 |
| Connections, cache, GitHub | 5,847 | 2,012 |
| Bundles | 4,467 | 893 |
| Writing, removing, linking | 4,008 | 2,252 |
| Renaming | 3,735 | 1,658 |
| Bibliography | 1,833 | 422 |
| Everything else (objects, checks, tables, helpers) | 10,574 | 6,902 |
| **Total** | **46,578** | **19,649** |

The fork has 403 top-level functions and the rewrite has 269. The
difference comes from five patterns:

1. **Validation layers.** The fork has 63 `validate_*`, `assert_*`,
   `resolve_*` and `check_*` helpers, and the rewrite has 20. The fork
   checks arguments again at each layer: a bundle call passes through
   `validate_bundle_call_dots`, `validate_bundle_metadata`,
   `assert_bundle_required_metadata`, `validate_variable_selections` and
   `resolve_variable_selection`. The rewrite validates once where data
   enters, through the object constructors, and relies on the write plan to
   refuse conflicts.
2. **Backend duplication.** The fork has 29 functions specific to rstan or
   cmdstanr, such as `rstan_sampler_bfmi` next to `cmdstanr_bfmi`, and the
   rewrite has 4. In the rewrite, the fit becomes a plain list once, in
   `extract_fit()`, and diagnostics are computed from that list one way for
   both backends.
3. **Parallel pipelines.** Fork bundles have their own rstan extraction
   (`extract_rstan_fit_for_bundle`) and their own info and diagnostic
   builders. Rewrite bundles reuse the import path (`draws_from_fit()`).
4. **Defensive file machinery.** The fork has symlink checks, staging
   folders, preflight checks and an atomic bibliography append. The rewrite
   has one plan-then-write step. This is a real trade-off, not just
   trimming: the fork restores replaced files and resists symlinks, and the
   rewrite doesn't.
5. **Reimplemented parsing.** The fork's hand-written BibTeX key scanner
   sits next to `bibtex::read.bib`. The rewrite uses only the latter.

Part of the difference is missing features rather than simpler code. The
items under [Feature parity with the fork](#feature-parity-with-the-fork)
are examples. I haven't measured how much of the size gap each accounts
for.

## Feature parity with the fork

The rewrite doesn't have full parity with the fork. It covers every
workflow the fork has, with the same function names:
- reading a database;
- reference checks;
- writing, removing and renaming;
- fit import from rstan and cmdstanr;
- bundles, output reconstruction and the batch workflow.

These fork options and behaviours are missing:

- `infer_posterior_dimensions()` has no `backend = "cmdstanr"`, `iter`,
  `include` or `exclude`. It always compiles with rstan.
  `infer_unconstrained_parameter_counts_from_fit()` has no `include` or
  `exclude`.
- `reconstruct_stan_output()` and `reconstruct_posterior_output()` have no
  `include_unconstrained`, and don't return timings.
- `link_reference_posterior()` has no `verify` argument.
- There are no `"all"` or `"none"` shortcuts for `include`.
- The fork records a `sampling_timestamp` field and forces
  `sig_figs = 18` on short cmdstanr runs. The rewrite has neither.
- `as.reference_posterior_draws()` has no `stanfit` method, `write_pdb()`
  has no `stanmodel` method, and `remove_pdb()` can't remove a file by path.
- The fork's hardening is gone: symlink checks and staged, transactional
  writes. Plan-then-write covers conflicts and partial failures, but not a
  symlinked path inside the database.
- The `policy` argument, the `_from_stanfit` and `_from_cmdstanr` aliases,
  the `assert_checked_*` helpers, `check_summary_statistics_draws()` and
  `pdb_compare_stan_models()` were dropped on purpose.

How this list was made: it compares exports and arguments
(`tools/compare-api.R`) and the fork's roxygen docs. I haven't read the
fork's design documents in `doc/`, which run to about 2,700 lines, or run
the fork's own test suite against the rewrite. Its tests are about seven
times the rewrite's by tokens, so running them would be the real parity
test, and it would likely turn up behaviour differences this list misses.

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
- **ESS bounds** are a hard check upstream: bulk and tail ESS must lie
  within 10,000 ± 4·√(7·10,000), about ±1,058. The spec doesn't ask for
  this. The band is too tight for tail ESS: it rejected 13 of 60 sets of
  independent normal draws (4 × 2,500 draws, 10 variables), all 13 on tail
  ESS and one also on bulk ESS. The fork already made the check informational, and so does
  the rewrite. It is the only upstream check the rewrite relaxes.
- **Unused bibliography entries** don't fail upstream's `check_pdb()`,
  because the result of that check isn't stored. I confirmed this by adding
  an uncited entry to the fixture database. Upstream returns status 0 and
  the rewrite returns 1.
- **E-FMI wording.** The spec says "below 0.2" but means at least 0.2, which
  is what upstream, the stored flags and the rewrite all use.

**Upstream left a few things unfinished, and the rewrite treats them as follows:**

- Only Stan sampling can compute reference draws. Upstream stops with
  "Currently not implemented" for anything else. The rewrite is the same,
  but adds cmdstanr next to rstan.
- Upstream's summary statistic types are `mean_value` and `sd`, but the
  database stores `mean_value` and `mean_squared_value`. So upstream can't
  read the `mean_squared_value` files, and it writes `sd` files that the
  database doesn't use. The rewrite supports the two types the database
  stores and has no `sd`.
- Two upstream tests have been skipped since 2022 with "LDA model will work
  from version 0.4". They expect a clear error when asking for reference
  draws of an LDA posterior that has none. Upstream gives that error when
  the posterior name is spelled right; the tests misspell it as
  `prideprejustice`. The rewrite behaves the same way.
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
  unchanged. The one exception is the inline Stan code, which uses
  pre-2.33 array syntax, so the script takes the same model from the
  fixture instead.
- One upstream vignette bug is left as it is. The vignette calls
  `check_pdb_posterior(po, pdbl)`, which passes the database as
  `run_stan_code_checks` and fails in upstream too.

**API compatibility with upstream:** every upstream export exists in the
rewrite except the `assert_checked_*`, `assert_reference_posterior_draws`
and `check_summary_statistics_draws` helpers, which
`check_reference_posterior_draws()` replaces. `thin_draws` remains an S3
method for reference draws. The fork's additions are all kept: fit import,
bundles, renaming, output reconstruction, cmdstanr, and the batch workflow.
