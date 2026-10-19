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
is about 44% of the fork's size.

The fork is formatted with Air, which puts many arguments on lines of their
own, and the rewrite is not. Raw line counts therefore flatter the rewrite.
Parse tokens (from `getParseData()`, comments excluded) don't depend on
formatting, so the token rows are the fair comparison.
`tools/code-size.R` computes all of these.

| | Pre-fork (stan-dev) | Fork (original) | Rewrite |
|---|---|---|---|
| R code, parse tokens | 15,088 | 46,578 | 20,362 |
| R code, lines with code | 1,843 | 6,698 | 2,071 |
| R code, raw lines (files) | 3,212 (26) | 9,206 (35) | 3,335 (16) |
| Roxygen lines | 870 | 1,722 | 875 |
| Tests, parse tokens | 5,293 | 48,338 | 7,254 |
| Tests, raw lines (files) | 934 (18) | 6,009 (55) | 805 (9), plus a 100 KB fixture |
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
- `pdb_compare_stan_models()` and the cmdstanr backend for
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
  The fork and upstream raise "File at path already exists" instead, and
  upstream's own `write data` tests expect that error.
- **Mean lag-1 autocorrelation is the signed mean over chains**, as the
  stored diagnostics in the database are. The fork changed this to the mean
  of the absolute values per chain. Recomputing three stored references
  (eight schools, diamonds, mesquite) gives the stored values exactly with
  the signed mean and not with the fork's version. The fork's version is
  larger, so it rejects more draws.
- **Values that are not finite are written as JSON `null`.** The fork
  writes the strings `"NA"` and `"Inf"` (`jsonlite`'s default), which read
  back as text. No file in the database has either string.
- **Renaming a posterior whose reference posterior is shared** renames the
  reference too and repoints the other posteriors that use it. The fork
  refuses. The fork's data rename, on the other hand, renames a shared
  reference but leaves the other posterior pointing at the old name, which
  no longer exists.
- **Failed checks are stored as one flag per check**, with the offending
  variables or chains in the `check_failures` attribute. The fork stores a
  single `check_failed` message.
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

The offline suite has 247 expectations and runs against a small
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
- **Real CmdStanR run** (`PDB_TEST_STAN=true`, `CMDSTAN` set;
  `tests/testthat/test-cmdstanr.R`, run on its own because loading rstan
  and cmdstanr in one R process crashed): the same model with cmdstanr
  0.9.0 and CmdStan 2.36.0. It covers parameter counts, import, the stored
  Stan version and tree-depth counts, and output reconstruction.
  **Passes.**
- **Full database** (`PDB_PATH=<posteriordb>/posterior_database`):
  `check_pdb()` plus a recomputed check of every stored reference posterior.
  **Passes.**
- **GitHub** (`PDB_TEST_GITHUB=true`): reads a posterior, its data, code and
  reference draws over the API. **Passes** against `sliderland/posteriordb`.
  This session can't reach `stan-dev/posteriordb`.

`R CMD check --no-manual` gives **Status: OK** (0 errors, 0 warnings,
0 notes), now that cmdstanr is installed.

## Not verified

- Reading over GitHub from `stan-dev/posteriordb`, which this session
  can't reach. `sliderland/posteriordb` works.
- The fork's tests that fail only because they use the fork's internal
  functions or object layout (below) say nothing either way about the
  behaviour they test.

## Does it do the same thing as the fork?

Three comparisons answer this. Reading is checked by running both packages
on the full database and comparing what comes back. The workflows that
write (fit import, bundles, renaming, removing, linking, sampling) are run
by both packages on copies of the same database, with the same fits, and
their results and files are compared. Finally the fork's own test suite is
run against the rewrite. The reading and basic writing comparisons run with
`sh tools/run-all.sh differential`.

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

**Workflows: fits, bundles, renaming and the rest through both packages.**
Run with `sh tools/run-all.sh workflows`. `tools/workflow-run.R` runs 32
scenarios with one package, each on a fresh copy of the fixture database,
and saves what each call returns (or its error) plus every file left in
the database afterwards. Each package runs once per backend, in its own R
process:

- **Fit import** of an rstan and a cmdstanr fit of eight schools (4 chains,
  thinned to 2,500 draws each): `as_reference_posterior_draws()`,
  `import_reference_posterior_draws()` with `write` and `overwrite`, with
  `include` and `exclude`, with wrong `dimensions`, and with a 2-chain fit
  that fails the checks.
- **Diagnostics**: `reference_draw_diagnostics()`,
  `passes_reference_draw_checks()` and
  `infer_unconstrained_parameter_counts_from_fit()`.
- **Output reconstruction** with `reconstruct_stan_output()` on both backends.
- **Bundles**: a new posterior from a fit, a failing bundle, and one built
  from data and a model already in the database.
- **Renaming** data, a model, a posterior with its reference posterior, a
  posterior that links to another's reference, and onto an existing name.
- **Removing** a posterior with its reference draws and summaries, and
  **linking** a new posterior to an existing reference posterior.
- **Sampling**: `infer_posterior_dimensions()` and
  `sequential_batch_workflow()` with `write = TRUE`, which samples, checks
  and writes, on both backends.

Each process refits from the same compiled model with the same seed. The
fork's and the rewrite's processes got identical draws for both backends,
so both packages work on the same fits. A saved fit can't be reused, because it loses its compiled model.

**The results.** The draws match exactly in every scenario: imported,
written, bundled, reconstructed and sampled. So do the results of every
renaming, removing and linking scenario apart from the two below, and the
parameter counts, the check verdicts and the inferred dimensions. Every
remaining difference is one of these:

| Difference | Fork | Rewrite |
|---|---|---|
| Mean lag-1 autocorrelation | Mean of absolute values per chain | Signed mean, which matches the stored database values (see [Changed](#changed)) |
| Not-finite numbers in sampler summaries | Written as `"NA"`, `"Inf"` | Written as `null` |
| `ess_within_bounds` in summary statistic info files | Left out | Written, as in 92 of the 114 stored summary info files |
| `method_arguments` of a cmdstanr fit | `sampling_timestamp`, no seed or control | `seed` and `control` (adapt delta, max tree depth), as for rstan |
| Bundle reference info | Lacks `stan_version`, `posterior_version`, tree-depth counts, sampler summaries and `ess_within_bounds`, which the fork's own import writes | The same fields as an import |
| A bundle from data and a model already in the database | Errors when the model also has a PyMC implementation | Works |
| A failing fit | Info holds one `check_failed` message | One flag per check, failures in an attribute. Both refuse to write. |
| Renaming data whose posterior's reference is shared | Leaves `eight_schools-eight_schools_centered` linked to a reference that no longer exists | Repoints it |
| Renaming a posterior whose reference is shared | Refuses | Renames both and repoints the other posterior |
| Error messages for wrong dimensions, excluded parameters and existing names | Fork's wording | Rewrite's wording. Both refuse. |
| `r_session` in versions | Lists the fork and its imports | Lists the rewrite and its imports |
| The batch workflow's result per posterior | Also has `stage`, `sampling` and `linked` | Has `status`, `draws`, `written` and `error` only |

The comparison first found gaps in the rewrite, which are now fixed: the
stored Stan version, tree-depth counts and sampler parameter summaries
were missing; E-FMI used rstan's normalisation for cmdstanr fits too
(a 0.04% difference); the Makevars placeholder text differed; and missing
optional info fields weren't written as `null`. It also found a bug:
`reconstruct_stan_output()` failed on every cmdstanr fit with a scalar
parameter, because cmdstanr gives scalars dimension 1. A cmdstanr test
now covers it.

**The fork's own test suite against the rewrite.** Run with
`sh tools/run-all.sh fork-suite`. `tools/fork-suite.R` runs each of the
fork's 53 test files in its own R process, against the fork and then
against the rewrite. `tools/fork-suite-compare.R` lists every test whose
outcome differs.

Against the fork itself, 188 of 199 tests pass, 8 are skipped (6 need
live GitHub access, 2 are upstream's long-skipped LDA tests), and 3 fail:
`check_pdb()` on the full database returns 1, and two caching tests call
a function the fork no longer has.

Against the rewrite, 167 tests have a different outcome. They split like
this:

| Kind | Tests | Examples |
|---|---|---|
| Call or mock one of the fork's internal functions | 95 | `assert_pdb_path_exists`, `extract_rstan_fit_for_bundle`, `write_json_to_path`, `local_mocked_bindings()` on fork helpers |
| Build their fixtures from the fork's internal object layout | 42 | `structure(list(pdb_local_endpoint = ...), class = "pdb_local")`, fixtures that call `:::` |
| Deliberate changes listed in [Dropped](#dropped) and [Changed](#changed) | 16 | Checks recomputed from the draws (4), identical writes skipped (3), the dropped `assert_checked_*` and `check_summary_statistics_draws` exports (4), no transactional rename rollback (3), no symlink checks (2) |
| Wording only | 5 | Error messages, the order of check names, print layout in upstream's two skipped tests |
| Remaining gaps, listed under [Feature parity](#feature-parity-with-the-fork) | 9 | Checking a posterior that isn't in a database, `posterior()` warning about unused arguments |

The first two kinds don't test the rewrite's behaviour at all. Making
them run would mean reimplementing the fork's internals.

The suite found four bugs in the rewrite, now fixed:
- `pdb()` on model code read the code as a database path, because model
  code is also a character vector.
- `rename_pdb()` on an object without `pdb` failed with "promise already
  under evaluation".
- Checking a bundle raised an error when its draws failed. The fork
  records the failure, and the rewrite now does too.
- `rename_pdb()` returned the new name rather than the renamed object.

It also led to small additions:
- `"all"` and `"none"` as selectors.
- `include` and `exclude` for `infer_unconstrained_parameter_counts_from_fit()`.
- `reference_posterior_draws_file_path()` for a reference info.
- A check that sampler diagnostics match the draws' shape.
- Free-form fields in non-Stan model implementations.
- An error for duplicate `search_posteriors()` fields.
- The fork's "Posterior:" heading when printing a reference info.

## Why the rewrite is smaller

Parse tokens by area (formatting doesn't affect these):

| Area | Fork | Rewrite |
|---|---|---|
| Fit import, sampling, diagnostics, reconstruction, batch workflow | 16,114 | 6,013 |
| Connections, cache, GitHub | 5,847 | 2,026 |
| Bundles | 4,467 | 893 |
| Writing, removing, linking | 4,008 | 2,321 |
| Renaming | 3,735 | 1,748 |
| Bibliography | 1,833 | 422 |
| Everything else (objects, checks, tables, helpers) | 10,574 | 6,939 |
| **Total** | **46,578** | **20,362** |

The fork has 403 top-level functions and the rewrite has 273. The
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

The rewrite doesn't have full parity with the fork, but the gaps are now
measured rather than guessed. It covers every workflow the fork has, with
the same function names, and the workflow comparison above shows the same
results for them:
- reading a database;
- reference checks;
- writing, removing and renaming;
- fit import from rstan and cmdstanr;
- bundles, output reconstruction and the batch workflow.

These fork options and behaviours are missing:

- `infer_posterior_dimensions()` has no `backend = "cmdstanr"`, `iter`,
  `include` or `exclude`. It always compiles with rstan.
- `reconstruct_stan_output()` and `reconstruct_posterior_output()` have no
  `include_unconstrained`, and don't return timings.
- `link_reference_posterior()` has no `verify` argument.
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

The fork's test suite found these further gaps, one test each:
- Checking a posterior that was built in memory with embedded data, code
  and draws, without a database (2 tests).
- A bundle whose draws fail the checks is written by the fork without a
  reference link. The rewrite refuses to write the posterior, because it
  links to draws that weren't written.
- `posterior()` warns about unused arguments, and `as.posterior()` reports
  what it did, in the fork. The rewrite is silent.
- `reference_posterior_summary_statistic()` can't build a summary from a
  plain list.
- PyMC code can't be read from model info that isn't in a database, and
  renaming in-memory model code uses the database's info rather than the
  object's.
- A user-defined subclass of reference draws has `thin_draws()` applied
  twice instead of once.

How this list was made: exports and arguments (`tools/compare-api.R`), the
fork's roxygen docs, the workflow comparison and the fork's test suite. I
haven't read the fork's design documents in `doc/`, about 2,700 lines.
The 137 fork tests that use its internals can't show gaps in behaviour
those internals implement.

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
