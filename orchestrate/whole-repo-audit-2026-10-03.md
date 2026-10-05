# Whole-repository review and Ponytail audit — 2026-10-03

This maintainer-authorized pass started on `main` at `c523d1f` and completed
implementation at `abdc357`. Four behavior findings were repaired in three
commits; a separate cleanup removed **10 R lines, one DESCRIPTION line and
the unused optional `dotenv` dependency**.

The original queue still contains **7 partial, open or deferred IDs**:
S5, D6, P3, P4, P8, V4 and V6. Their contracts and pending questions remain
in [AGENT_REVIEW_GUIDE.md](AGENT_REVIEW_GUIDE.md). This report records the
new audit work without replacing that queue.

## Scope and orchestration

Static review covered the 35 tracked R modules: connection/lookup,
metadata/data/model access, search/tables, reference draws/summaries,
diagnostics/acceptance, extraction/recovery, sampling/count inference,
reconstruction, bundle/batch orchestration, cache/transports,
write/rename/remove/link, bibliography, aliases and utilities. Related
tests/helpers, namespace registrations, dependencies, examples and the three
CI workflows were also inspected. Historical findings were revalidated
against current source; already implemented repairs were credited.

The coordinator was the sole writer. Reused **GPT-6 Luna/medium** agents
`cleanup_audit` and `p1_inventory` performed bounded read-only inventories.
A separate **GPT-6.1 Sol/high** agent `unit_review` performed correctness
review and independently reviewed each frozen patch. Ponytail governed
implementation, Ponytail Audit supplied complexity findings, and Ponytail
Review checked the diffs. Graph queries narrowed callers/impact; source
and tests overruled stale or incomplete graph relationships. No child edited
files or owes a commit.

Every owned tracked file was clean before its unit began, so no new pre-edit
preservation commit was needed. The coordinator staged only owned files and
made the four post-edit commits below. Pre-existing changes to `.Rbuildignore`,
`.gitignore`, untracked historical Markdown and ad hoc test scripts/logs remain
untouched. The older untracked `ponytail-audit.md` remains historical input.

## Implemented correctness findings

### 1. Acceptance assertions bypassed draw structure — `b079707`

**Before:** checking/writing draws validated labels and retained lengths,
but acceptance assertions inspected flags/counts alone. After shortening
a vector or duplicating a label on an already checked object, direct summary
computation could still proceed. The review reproduced posterior conversion
recycling a shortened vector and returning a misleading summary.

**Repair:** both draw-object acceptance methods call the existing
`assert_reference_posterior_draws()` before trusting saved flags. Two calls
cover direct assertions, checked-reference summary transfer and public
mean/mean-squared computation. Metadata-only assertion methods retain their
purpose. Numerical acceptance and analytical finiteness policy are unchanged.

**Evidence:** 15 assertions were added to existing duplicate/ragged cases;
12 failures were observed before repair. Analytical60 passed development,
installed namespace-only loading and independent review. Alignment22,
transformations28, bundle acceptance28 and integrity57 passed development.
Help and the bundle guide document validation before summary computation.

### 2. Directory caching disagreed with listings — `eb4daeb`

**Before:** local name listings ignored subdirectories, but bulk caching
copied them as files. A `posteriors/archive/` or `directory.json` directory
broke table/search reads. GitHub caching separately unlisted names and URLs:
a directory's NULL URL disappeared while its name remained, shifting a
following file's URL onto that directory name.

**Repair:** local caching filters directories before copying; GitHub caching
filters Contents API entries to files and iterates paired names/URLs.
No new listing helper or transport abstraction was needed.

**Evidence:** a public local table regression failed on a directory before
repair. Populated and empty tables/searches now match their original results.
The GitHub directory-first response is tested with scoped mocks, without
network access. Final search27/listing43 passed development and installed
checks; independent review exercised both stages.

### 3. Bulk caching ignored transfer failures — also `eb4daeb`

**Before:** bulk workers ignored FALSE copy/download results. Search could
return no matches despite source metadata, and GitHub caching could announce
completion after failure. Throwing transfers could leave partial cache files.

**Repair:** both workers check success and propagate failures. Local copying
removes the failed cache destination; GitHub downloading removes newly created
partial files and preserves a file that existed before failure. Unsuccessful
destinations and underlying exceptions remain visible. Existing overwrite
and manual-refresh behavior remain unchanged; P3 and P4 deferrals are preserved.

Independent review caught a data-loss edge case in the intermediate local
cleanup: cache/database overlap could make cleanup delete original metadata
after a same-file copy error. That draft was never committed. The final
worker skips copying when normalized source and destination paths are equal.
Tests verify preserved source contents with the database root, a `.` path
and a symlink alias.

**Evidence:** initial mocked GitHub checks produced five failures. The local
failure regression produced three failures with the parent worker; the overlap
regression failed before its guard. Final listing43 passed development,
installed namespace-only loading and independent review. Archives41 and
optional23 passed development/installed checks; cache3 passed with two corpus
skips. The GitHub regression skips if optional `httr` is absent. The user
guide explains directory handling and partial-cache cleanup.

### 4. Linking ignored an explicit destination — `a1ad0b0`

**Before:** `link_reference_posterior(object_from_A, pdb = B)` replaced B
with the object's connection and could update A. An omitted `pdb` could also
force the default-database promise during unqualified `pdb(object)` lookup,
despite the object already having a connection.

**Repair:** an explicit connection selects the destination. Only an omitted
connection is inherited from the object through the namespace-qualified
existing accessor. The saved target posterior is loaded by name and its
reference files validated before writing. Runtime repair is one line; public
help and the contribution workflow describe connection precedence.

**Evidence:** the parent failed three destination/state assertions and the
fail-fast default-lookup sentinel. Tests cover explicit B without modifying A,
implicit A without default lookup, detached input with explicit B and missing
reference files in B. Resource178 passed development, installed namespace-only
loading and independent review. Connections16, integrity57 and standalone36
also passed development. All databases were disposable fixtures.

## Ranked Ponytail cuts — `abdc357`

1. **delete:** unused diagnostic variable, unused ESS variable and obsolete
   commented placeholders; replacement: nothing. Formulas remain unchanged.
   [reference_draw_diagnostics.R](../R/reference_draw_diagnostics.R),
   [utils_reference_posterior.R](../R/utils_reference_posterior.R). **5 lines.**
2. **shrink:** copying `model_implementations` to a local and assigning the
   same value back; replacement: serialize the existing field directly.
   Validation, keyword completion and supplied fields remain intact.
   [write_pdb.R](../R/write_pdb.R). **4 lines including its redundant comment.**
3. **delete:** discarded `httr::http_error()` boolean in `github_download()`;
   replacement: its existing `status_code(...) == 200L` result. Installed httr
   methods were checked for side effects. Source verification corrected the
   explorer's two-call estimate: only one discarded call existed.
   [pdb_github.R](../R/pdb_github.R). **1 line.**
4. **delete:** unused `dotenv` Suggests entry; replacement: nothing. No
   executable package/test/vignette/workflow call uses it. Historical notes
   about earlier availability remain historical. [DESCRIPTION](../DESCRIPTION).
   **1 line and 1 optional dependency.**

**Measured cleanup net: -11 lines, -1 dependency.** This measures the cleanup
commit only; correctness repairs, regressions and requested documentation
add lines. The entire audit diff is not claimed to be smaller.

Kept after review: GitHub copy/download workers have different overwrite
contracts; public S3 methods/aliases retain callers and extension points;
parser/schema/recovery guards protect supported inputs and failure state.
Removing an unused internal writer parameter would save no lines and shift
positional arguments, so that optional churn was skipped. Test isolation,
backend opt-ins and the three CI workflows serve distinct purposes. No further
worthwhile broad consolidation was found in this pass.

## Final verification and continuation

| Final loading mode | Passing assertions | Failures/errors | Explicit skip records |
| --- | ---: | ---: | ---: |
| Development package | 1,337 | 0 / 0 | 42 |
| Fresh installed package, namespace only | 1,337 | 0 / 0 | 42 |

Both complete suites set `PDB_TEST_STAN=false`, `PDB_TEST_DATABASE=false`,
`PDB_TEST_GITHUB=false`, `NOT_CRAN=true` and a nonexistent `PDB_PATH` sentinel.
Development used `pkgload::load_all(..., helpers=FALSE, export_all=FALSE)`
and `testthat::test_dir()`. Installed verification used `R CMD INSTALL
--install-tests` in a temporary library and `requireNamespace()` without
attaching posteriordb. The 53 tracked test files participate in the suite;
opt-in integrations remain skipped as reported.

The final cleanup's independent workers27/model-paths101 passed. Development
alignment22, workers27, lag23 (one corpus skip), model-paths101, framework19,
listing43 and optional23 also passed. The S3 signature checker passed.
`codetools::checkUsagePackage()` now reports only the existing assignment used
as the implicit return of `pdb_posterior_must_include()`; that warning is not
dead code. Affected roxygen help and the Rmd-derived bundle guide were regenerated.

Source review and fixture tests are not an exhaustive proof. Live GitHub,
Windows runtime, real Stan backend integrations, the manual corpus workflow
and a broad `R CMD check` were not rerun for this pass. Earlier backend evidence
remains attached to its earlier commits in the handoff.

All confirmed findings selected in this pass are implemented and reviewed.
All agents finished with no edits or commits owed. Continue from the existing
seven-ID queue when the maintainer resolves pending choices or explicitly
resumes deferrals. Preserve the one-writer loop: check owned files, preserve
relevant dirty changes, reproduce, implement minimally, test, freeze for
independent review, commit and update the handoff. The four ordinary commits
above support inspection or a dependency-aware revert.
