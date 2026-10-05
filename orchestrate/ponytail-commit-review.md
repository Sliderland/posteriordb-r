# Ponytail commit review: completed through `096ed3f`

Reviewed on 2026-10-01 using the Ponytail, Ponytail Review, and Ponytail Audit
skills; continued on 2026-10-02 against local `main` at
`096ed3f99ad265f466d901d2fa14c3c920332fcc`. This is a historical review and
future-work record; no implementation was changed.

## Scope and conclusion

The ledger now covers all **83 commits in `8aeef19..096ed3f`**, in
chronological order: the original **74 commits in `8aeef19..55e667e`** and
the remaining **nine commits in `55e667e..096ed3f`**. The original rows and
reproductions retain their assessment at
`55e667e2b11267a5ab9db76e5a15c15ea82c6376`; the continuation below assesses
the newer changes at `096ed3f`. Existing code outside those changes was
inspected where needed to understand callers, dispatch, validation, and
persistence. This is not a review of every commit since the package began.

The original review recorded `Agent-ToDo` being created from `upstream/main` at
`8aeef19`, rather than from `main`/`origin/main` at `55e667e`. Its review
documents describe the newer feature history on local `main`.
An isolated archive of `55e667e` was used for the original source inspection
and probes, without switching the working branch. Its source locations remain
historical. The continuation used a separate archive of `096ed3f`; its source
locations refer to that newer commit. The present checkout is on `main` and
contains the feature implementations. Uncommitted changes, including newer
workflow documentation and standalone checks, are outside this committed
history review. Recheck findings against the implementation candidate before
fixing them.

The added functionality has useful boundaries: backend extraction, in-memory
bundle assembly, selective diagnostic reports, explicit acceptance, and
explicit persistence. A named CmdStanR extraction helper is not intrinsically
wrong merely because it is not an S3 method. The stronger simplification is
to reuse extraction and acceptance across workflows, while keeping ordinary
numeric and persistence helpers ordinary functions.

Several intermediate gaps were repaired by subsequent commits. At `55e667e`,
the code still had important consistency and persistence problems, but most were
already explained adequately in the existing handoff documents. This review
originally added **two reproduced bundle-reuse defects**, rather than another parallel
backlog containing all previously reported concerns. The snapshot is useful,
but its bundle writer is not yet reliable enough to assume that a successful
in-memory check guarantees a consistent database write.

## Original findings to implement or decide (`55e667e`)

In the short location/cut/replacement style of Ponytail Review:

- **High — `create_pdb_bundle.R:421-424`, `write_pdb.R:248-261`: stop replacing reused components' source connection before collision checking; validate their original origin.** Passing an object from A with destination B defeats the cross-database reuse guard. See [P11](AGENT_REVIEW_GUIDE.md#p11-bundle-construction-erases-reused-components-source-database--reproduced).
- **Medium — `create_pdb_bundle.R:517-522`, `write_pdb.R:105-117`: stop treating a changed NULL reference link as an entirely unchanged reused posterior; plan the narrow link update, or reject it before writing.** An accepted bundle can fail persistence because its new link exists only in memory. See [P12](AGENT_REVIEW_GUIDE.md#p12-a-reused-posteriors-new-reference-link-exists-only-in-memory--reproduced).

P11 was reproduced with two disposable databases containing different values
under the same data name. The public constructor and writer successfully
wrote accepted draws to B while reporting that data as reused; the bundle
held A's value, and the public database getter returned B's different value.
This is a lost-origin bug, not a request for a new fingerprinting framework.
`4df3f39` added a relevant guard, but the constructor undermines its premise.

P12 was reproduced with a persisted posterior whose reference link was NULL.
Construction returned passing checks and an in-memory link, but preflight
skipped the reused posterior record. The writer then rejected the draws
because no persisted posterior pointed to them. The stored link stayed NULL
and no reference archive was created. This differs from the already reported
failed-candidate dangling-link defect. Its policy choice is small: permit a
careful empty-link update with accepted draws, or require linking explicitly
before this reuse operation. The constructor and writer must agree.

The handoff entries contain affected flows, source locations, minimal fixes,
and regression cases. Neither fix needs a new object hierarchy or backend
registry.

## Existing concerns that already have sufficient documentation

These are concerns recorded against `55e667e`; they are not new discoveries
of the continuation. Use the existing entries as the implementation backlog,
with the current-source qualifications below.

| Area | Outstanding behavior or simplification | Existing explanation |
| --- | --- | --- |
| S3/public contracts | Bundle generic/method argument order, method registration/subclasses, lost database connection during coercion, ignored framework input | [Handoff S1–S5](AGENT_REVIEW_GUIDE.md#s3-dispatch-and-object-contracts); [audit S3 follow-up](ponytail-audit.md#follow-up-s3-consistency-and-standalone-functions) |
| Diagnostics/acceptance | Duplicated calculations and applicability/evaluation; analytical draws cannot satisfy the HMC-oriented final gate; preserve selective extraction | [Handoff D1–D4](AGENT_REVIEW_GUIDE.md#diagnostics-fit-extraction-and-acceptance) |
| Counts/provenance/backend metadata | Constrained-shape regression gaps; fit/data identity limits; inconsistent version schemas; cautious archived-fit recovery | [Handoff D5–D7](AGENT_REVIEW_GUIDE.md#d5-counts-output-shapes-and-parameter-selection-need-regression-coverage); [workflow proposals](implementation-guide-stan-workflow-gaps.md) |
| Persistence | Stale acceptance after transformations, failed-candidate links, stale caches, sequential writes and failed rollback restoration | [Handoff P1–P4](AGENT_REVIEW_GUIDE.md#persistence-transformations-names-and-cache) |
| Lookup/path/reader consistency | Metadata links versus parsed names, dotted names/empty directories, summary listing paths, framework extensions, resource validation, reference-name identity | [Handoff P5–P10](AGENT_REVIEW_GUIDE.md#p5-posterior-link-lookups-parse-names-instead-of-metadata--reproduced) |
| Validation/workflows | Bibliography failure status, checking the wrong in-memory object, summary schemas, batch input normalization, dropped/conflicting CmdStanR settings | [Handoff V1–V6](AGENT_REVIEW_GUIDE.md#validation-and-workflow-behavior) |
| Tests | Database-mutating legacy tests, weak backend/numeric assertions, incomplete persistence/failure coverage, installed-package dispatch, constrained parameter cases | [Test-suite review](ponytail-test-suite-review.md); [handoff T1–T3](AGENT_REVIEW_GUIDE.md#tests-dependencies-and-documentation) |

The NULL policy argument remains a decision to record, with the fixed
standard policy very likely to stay unchanged. The audit already explains
the compatibility argument and redundant forwarding. It is not evidence
that a configurable policy engine is needed.

CmdStanR is not the only remaining coverage gap. The already documented
public-contract, dimension, saved-value, rollback, and database-isolation
gaps matter too. P11/P12 add specific constructor-to-writer regression cases.

## Commit-by-commit ledger

The first 74 rows record functionality and disposition at `55e667e`; the
continuation table records the remaining nine commits at `096ed3f`. A
later repair is credited instead of criticizing obsolete intermediate code.
“No new issue” means no additional addressable issue beyond the linked
backlog was identified; it is not a claim of complete correctness or test
coverage. Handoff identifiers refer to `AGENT_REVIEW_GUIDE.md`.

### Original 74 commits (`8aeef19..55e667e`)

| Commit | Functionality understood | Disposition in the reviewed final snapshot |
| --- | --- | --- |
| `3a29ab0` | Expands posterior dimension names to handle matrix-shaped parameter metadata. | Later count/shape work in `a5d2a9e` changes the underlying dimension interpretation. Review the final unconstrained-count contract; D5 covers regression gaps. |
| `df6ad4f` | Appends bibliography entries from text, a BibTeX file, or bibliography objects. | Duplicate handling and write safety are improved later in `5edc3cd`, `a52d05c`, and `5fd45f0`. Final recovery concern is P4. |
| `5edc3cd` | Tightens duplicate bibliography entry detection. | Later hardening/atomic writing completes the feature's next steps. No additional final duplicate-detection concern identified. |
| `108789c` | Checkpoint with no tree change. | No implementation to criticize. |
| `1cfffe3` | Searches posterior metadata together with linked data/model metadata. | Later `a52d05c` hardens search behavior. No new major final search issue identified. |
| `d8d87b1` | Checkpoint with no tree change. | No implementation to criticize. |
| `e341b0c` | Replaces ESS acceptance gating with lag-1 autocorrelation. | This is the intended current policy. D1/D2 cover duplicated numeric/evaluation paths; do not restore an ESS gate as a cleanup. |
| `2f2b758` | Reuses retained draws for Stan diagnostic calculations. | Useful alignment of diagnostics with the retained sample. Selective extraction and shared report work follow; D1/D4 cover remaining duplication. |
| `bb635c3` | Records ESS quality without making ESS an acceptance condition. | Intentional informational output. D2 covers keeping acceptance definitions consistent across consumers. |
| `0291a0f` | Imports externally sampled RStan fits into existing posterior workflows. | Validation, transactional staging, and a second backend follow. Reusing importer boundaries internally is reasonable; D4 covers inconsistent routing. |
| `a52d05c` | Hardens bibliography/search/import validation, acceptance handling, and cache-related boundaries; rejects unsupported custom import policies. | NULL selects the ordinary fixed policy. Its compatibility/forwarding decision is already in the audit. Later fixes must be credited, especially `9c0848d` staging. |
| `5fd45f0` | Stages bibliography updates and replaces the destination with recovery support. | Atomic replacement is useful; failed backup restoration still needs P4's handling. Do not discard the only recoverable backup. |
| `0207615` | Adds coordinated renaming of linked database resources with staged updates and rollback. | No need for a new transaction framework. P4 covers unchecked restoration/backup cleanup; P9 covers sharing name validation. |
| `2f0f0dc` | Checkpoint with no tree change. | No implementation to criticize. |
| `43b3505` | Adds CmdStanR MCMC import, extracting draws, sampler diagnostics, and backend metadata. | An ordinary backend helper is valid. Shared extraction routing, version/argument correctness, and real-backend fixtures remain D4/D7/V5 and test-review work. |
| `16cdd44` | Adds dimension inference, internal Stan sampling helpers, and posterior-reference linking so internally generated fits can enter the import workflow. | `9c0848d` improves staging; `a5d2a9e` replaces count assumptions. The remaining internal/external extraction split and CmdStanR setting loss are D4/V5. |
| `06e403c` | Adds sequential batch sampling with checks before persistence. | Sequential operation is sufficient; parallel infrastructure is unnecessary. Malformed sampling-list classification remains V4. |
| `9533d29` | Regenerates roxygen documentation and registrations/exports for extraction and sampling APIs. | Necessary API bookkeeping. Review final registration consistency under S2, rather than assuming generated docs prove dispatch works. |
| `d960a01` | Introduces standalone reference-draw bundle construction and initial tests. | Selective diagnostics and embedded-object support are supplied in `9c0848d`/`fdc8156`. Those intermediate gaps are not final findings. |
| `9c0848d` | Adds selective diagnostic reports, shared threshold use, and corrects premature posterior linking during import staging. | Meaningful later repair. D1/D2 still cover calculation/evaluation duplication; P2 concerns the separate bundle writer, not this repaired import staging. |
| `fdc8156` | Allows standalone embedded data/model/reference objects, adds getter/persistence support, and exports the constructor. | Repairs the initial bundle integration. Final in-memory checking and connection consistency remain V2/S3. |
| `f96dbb0` | Normalizes diagnostic selectors, undefined values, and threshold/report handling. | Useful report boundary. D1/D2 describe what still needs one owner; selective behavior must be preserved. |
| `e268a35` | Strengthens lag-only tests with workers that throw if unrelated metrics are requested. | A meaningful test of selective computation, stronger than random-data success checks. Retain it. |
| `4421281` | Adds validated RStan bundle extraction, including saved parameter coverage and HMC inputs. | A useful adapter boundary. Source/count recovery should remain narrow; D4/D5 and the archived-fit proposal cover final reuse and recovery work. |
| `a6ae791` | Builds standalone bundles through extraction and assembly, validates ordinary Stan inputs, and uses shared diagnostic reports. | Reduces constructor duplication. Final public signature mismatch is S1; do not add another constructor framework to fix it. |
| `3dd4dc1` | Validates embedded object integration, handles framework lookup/zero-sized inputs, and documents/tests generic imports. | Repairs earlier standalone integration. Final framework, coercion, and checker contracts remain S3/S5/V2. |
| `659563b` | Adds acceptance and no-database-write tests for bundle construction. | Good separation-of-effects assertions. They do not establish writer round-trip correctness or reused-object integrity. |
| `a9291e7` | Corrects collision-sentinel paths in the bundle no-write tests. | Credits the test repair; no new runtime behavior. |
| `d773f98` | Clarifies that construction is in memory and persistence is explicit. | Correct public model. Final writers must still fulfill it consistently; P2/P11/P12 describe gaps. |
| `7aae28b` | Preserves constructor edits and formatting before the API rename. | No separate major feature or new outstanding issue identified in this change. |
| `4914255` | Renames the standalone constructor to `create_pdb_bundle`. | A name that better describes the returned collection. Review the final API, not obsolete constructor terminology. |
| `ab1e9e7` | Updates generic constructor usage in tests and documentation after the rename. | Necessary follow-through; no additional runtime issue identified. |
| `58a4238` | Regenerates the bundle API docs and clarifies reference-write acceptance guards. | Guards are useful, but stale evidence and differing applicable checks remain P1/D2/D3. |
| `11248dc` | Avoids sampler diagnostic extraction for unchecked construction. | Later `48b10ac` retains inputs needed for deferred checking. Judge that final deferred contract, rather than the earlier skip alone. |
| `f36501a` | Skips diagnostic calculations when `check = FALSE`. | Desired behavior; raw-input retention is completed later. Selective/deferred paths should share calculations, not acquire separate engines. |
| `c0a62a7` | Adds tests for unchecked construction and subsequent checking. | Valuable workflow assertions; later implementation/tests refine which raw inputs survive. |
| `395e946` | Tests retention of sampler inputs needed for deferred checks. | Useful evidence for the deferred contract. Backend/numeric correctness still needs the existing test-review follow-up. |
| `48b10ac` | Implements deferred bundle checking while retaining raw sampler inputs and using the report path. | Resolves the unchecked/deferred gap. D1/D2 cover remaining duplicated workers and applicability decisions. |
| `f830075` | Matches deferred RStan E-FMI calculation with the immediate RStan finite-sample convention. | Credits this consistency repair. Do not merge other E-FMI formulas without specifying the intended normalization (D1). |
| `2490336` | Supplies contributor/date metadata consistently across bundle components. | Appropriate small shared defaulting; no additional concern identified. |
| `403151b` | Uses `Sys.Date()` for bundle date defaults. | Small default correction; no extra abstraction warranted. |
| `1d00dc4` | Normalizes scalar dimensions in bundle metadata. | Later unconstrained-count work supersedes shape-based assumptions. Assess final semantics and D5 coverage. |
| `c986828` | Collapses identical per-chain sampler arguments, excluding chain identifiers from common-argument comparison. | Useful metadata normalization; differing arguments remain represented per chain. No new issue identified. |
| `e92d562` | Aligns reference metadata names, diagnostic variable information, and version entries. | Useful schema alignment, but cross-backend version validation still needs D7. |
| `69ac999` | Completes optional data/model info JSON fields, retaining explicit NULL values. | Schema completion is appropriate. Class preservation is repaired in `d9f0e16`; supplied metadata handling improves in `cd2d6f1`. |
| `d9f0e16` | Preserves info classes while completing JSON fields. | Credits the later class repair; no need to criticize the earlier class loss as current behavior. |
| `387b44b` | Documents the reference-bundle contribution workflow. | Documentation-only change; later guide updates refine the API and persistence contract. |
| `04706ef` | Clarifies immediate/deferred checking workflows in the guide. | Documentation-only; the deferred implementation already has supporting tests. |
| `43ded15` | Adds the R Markdown source for the bundle guide. | Edit the source for future generated-guide changes; no runtime effect. |
| `16cacb5` | Computes summary statistics and includes them in the bundle. | Useful existing numerical/output helpers should remain ordinary functions. Summary validation/reader issues are V3/P10. |
| `68978b8` | Documents summary-statistic JSON fields. | Documentation-only; field documentation does not replace round-trip/schema assertions. |
| `d91153f` | Writes summaries alongside reference draws and stages import outputs together. | Import staging is useful. Bundle/component writing remains sequential (P4), and full saved-value assertions remain a test gap. |
| `64fdd07` | Makes summary-statistic writing optional. | A concrete persistence option, not speculative flexibility. Readers should distinguish absent optional data from malformed data (V6). |
| `d522483` | Updates the bundle contribution guide. | Reverted by `0be9d7d`; no final runtime or surviving guide change from this pair. |
| `0be9d7d` | Reverts the preceding contribution-guide update. | Judge subsequent guide revisions rather than the reverted text. |
| `3e13b2a` | Uses mean squared value summaries and corresponding uncertainty calculations on squared draws. | Clarifies the statistic instead of conflating it with a different moment. Numeric/saved-value coverage is already requested in the test review. |
| `c5feef9` | Serializes an explicit NULL PyMC implementation entry. | Schema compatibility change; `cd2d6f1` later respects supplied implementation metadata. No need to erase caller metadata to satisfy defaults. |
| `de4aa1e` | Reviews/documents import workflows and adjusts validation of NULL implementation entries and optional fields. | Credits validation/schema compatibility improvements. Independent database-checker defects remain V1/V2. |
| `cd2d6f1` | Honors supplied model metadata and implementation defaults through serialization. | Repairs overly aggressive default/field replacement. Preserve it when consolidating schema completion. |
| `63fe79b` | Writes bundle components, persists only accepted reference draws, reports outcomes, and requires a stored posterior link for draw writes. | Good boundary intent. P2 documents failed-candidate links; P4 covers partial writes. P12 exposes a later reuse interaction with the stored-link guard. |
| `c5b3118` | Preserves descriptive posterior metadata in bundle assembly. | Useful preservation contract. Reuse fixes should update only necessary structural fields, not overwrite descriptions wholesale. |
| `332bffc` | Writes NULL keyword fields consistently for model/posterior info. | Schema normalization; no additional issue identified beyond shared completion/validation concerns. |
| `a5d2a9e` | Stores unconstrained posterior parameter counts, separately validates saved constrained output, and handles RStan count recovery. | Important semantic repair of earlier dimension assumptions. D5 covers real constrained-model cases; archived recovery should remain explicit and narrow. |
| `aea2548` | Excludes transformed parameters/generated quantities from RStan unconstrained parameter counts. | Credits parameter-selection correction. Tests should distinguish parameters, transformed parameters, and generated quantities (D5). |
| `5241f39` | Accepts existing connected data/model/posterior objects, resolving names and checking fit/source consistency. | Metadata and reuse handling improve later. Final reuse still has the new source-origin and empty-link problems P11/P12. |
| `2ada647` | Prefers reused database metadata and warns about conflicting supplied metadata. | Sensible preservation behavior. It does not preserve the original connection through destination retargeting (P11). |
| `3310c84` | Normalizes Stan source line endings, BOM, and trailing whitespace before comparison. | Appropriate narrow comparison; it does not claim semantic source equivalence or establish historical data identity (D6). |
| `daa4e12` | Treats classed model code as code, accepts missing structural reference links, and attaches embedded draws after creating them. | Credits earlier reuse fixes. Accepting a NULL persisted reference link still needs writer agreement (P12). |
| `fb38bb5` | Documents reused-object bundle contribution. | Documentation-only. Preserve the documented collision/reuse guarantees when fixing P11. |
| `211e40f` | Clarifies that posterior dimensions are unconstrained parameter counts. | Correct final semantics; saved constrained shapes remain separate. D5 asks for meaningful regression coverage. |
| `4df3f39` | Preflights bundle destinations, collisions, reuse origin, and duplicate planned paths before persistence. | Useful later guard, but P11 defeats its source-origin test. Preflight is not rollback/transaction support (P4). |
| `1eb3531` | Updates import fixtures, permits an existing target posterior under `overwrite = FALSE`, and improves empty-array/optional-schema handling. | Credits the existing-posterior collision repair; no need to keep the earlier failure as current. P11/P12 require additional reuse tests. |
| `913904b` | Refreshes the bundle guide's Rmd source. | Documentation-only; inspect source and generated guide together for future changes. |
| `55e667e` | Documents the Stan framework metadata shorthand and adds corresponding metadata tests. | Useful clarification/tests. The independent ignored framework argument in a different constructor is still S5. |

### Remaining nine commits (`55e667e..096ed3f`)

| Commit | Functionality understood | Disposition at `096ed3f` |
| --- | --- | --- |
| `532c7ac` | Adds importer/conversion `include` and `exclude` arguments shared across RStan and CmdStanR. Retains dimension variables and all inferred positive-count parameter variables; diagnoses and summarizes the selected outputs. Allows saved derived variables in existing dimensions and checks counts only for actual parameters. | A concrete output-selection feature, not speculative flexibility. Existing import tests pass. This intentionally widens the earlier dimension-name matching contract; it does not verify model/data identity (D6). Positive-count names do not identify every constrained parameter input; see the separate D5 follow-up below. |
| `0663392` | Makes bundle extraction retain all inferred parameter variables despite an explicit `include`, prohibits excluding them, preserves the full inferred dimension map, and accepts `character(0)` for parameter-only selection. | Credits the repair of partial parameter selection. Keep saved constrained coverage separate from unconstrained counts. Assembly repeats selection already completed by extraction; the new Ponytail cut below removes that repetition. The zero-coordinate parameter case remains incomplete (D5). |
| `2a632d7` | Adds the standalone bundle alias `include = "all"` for the existing NULL default. | Small documented convenience. It is normalized in extraction and again in assembly; keep one owner. The existing-posterior importer deliberately treats `"all"` as a variable name, not an alias. |
| `612ec88` | Adds the standalone bundle alias `include = "none"` for `character(0)`, retaining inferred parameters without extra outputs. | Small documented convenience; no policy engine is needed. `c()` still means NULL. Both aliases are reserved when used alone. Parameter-only reconstruction fails for the reproduced `simplex[1]` case below. |
| `f15661a` | Exports standalone Stan output reconstruction with RStan and native CmdStanR evaluators, constrained input checks, base/indexed output selection, optional unconstrained draws, evaluator reuse, and timings. | Useful standalone boundary; do not introduce a backend registry or S3 hierarchy solely to reorganize it. Real matrix/simplex probes passed for both backends. Keep validation and the documented RNG/model-data limitations. Committed reconstruction tests are absent; the probe results below are bounded evidence, not regression coverage. |
| `5d2a0e0` | Updates the Rmd source and generated bundle guide for import, selection, immediate/deferred checks, persistence, dimensions, and reconstruction. | Documentation-only. Correctly distinguishes staged imports from sequential bundle writes and documents different selection defaults. Documentation does not repair P11/P12 or prove rollback behavior. |
| `e15905b` | Exports `reconstruct_posterior_output()` to resolve a saved posterior or alias, check its Stan/reference metadata, and forward linked draws, code, and data to reconstruction. | Keep the wrapper: it owns lookup and eligibility checks, not merely a redundant name. It follows metadata links without splitting the posterior name. The wrapper was traced through readers but not exercised end to end; add disposable alias/link coverage under T2. |
| `8c8e423` | Preserves regenerated help pages for dimension inference and dimension names; some Markdown markup becomes literal and explanatory text is lost. | Intermediate documentation churn. `096ed3f` restores and expands source-backed explanations with `@md`; do not report the superseded help-page formatting as a current defect. No runtime change. |
| `096ed3f` | Synchronizes dimension-help roxygen sources and Rd pages, explaining unconstrained counts, parameter selection, backend requirements, and RStan zero-chain versus CmdStanR short-fit behavior. | Documentation-only; executable bodies are unchanged. The focused dimension-name tests pass. These helpers intentionally return positive unconstrained counts, which must not also serve as the complete constrained input schema for reconstruction. |

## Continuation findings at `096ed3f`

### Ponytail Review and Audit: one new cut

`R/create_pdb_bundle.R:L338-352,L373-374,L385-393,L479-482: shrink: remove the assembler's second include/exclude normalization, validation, and base selection, together with redundant argument forwarding. Let extraction own selection; assemble its already selected draws and call bundle_full_diagnostic_report(extracted).`

The exported constructor calls `extract_rstan_fit_for_bundle()` through
`extract_rstan_fit(for_bundle = TRUE)` before assembly. Extraction already
normalizes aliases, validates names, protects inferred parameters, checks saved
coverage, and subsets draws. Assembly has one runtime caller and does not
subset draws again; its repeated `chosen_bases` computation only reselects
the same variables for diagnostics. Keep the empty-draw and dimension guards,
provenance variable names, and all extractor validation. Fix the D5 schema
gap below at that selection boundary rather than adding another assembly rule.

The estimate is about 16 implementation lines: nine repeated selection lines,
four argument declaration/forwarding lines, and three lines from shortening
the diagnostic call. It excludes tests/docs and does not include the earlier
audit's cuts.

net: -16 lines possible.

The repo-wide caller/export/dependency scan and inspection of the earlier
audit locations found its existing candidates still present: metadata-validation
flexibility, unused helpers, the data-recovery stub, repeated download/rename
work, repeated shape checks, duplicated lag calculations, source-comparison
hashing, and generated-expression constructor lookup. Keep the original
[ranked audit](ponytail-audit.md#ranked-cuts) as their record; this continuation
adds the assembly cut without duplicating or re-estimating that backlog.
No new dependency-removal candidate was found in the nine commits.

Incremental audit net: -16 lines, -0 deps possible.

### Separate correctness follow-up: D5 parameter completeness — reproduced

This finding belongs to ordinary correctness review, outside Ponytail Review
and Audit's complexity scope. Extend the existing
[D5 count/shape/selection work](AGENT_REVIEW_GUIDE.md#d5-counts-output-shapes-and-parameter-selection-need-regression-coverage)
with a parameter that has constrained columns but zero free coordinates.

At `096ed3f`, a real RStan fit for
`parameters { real mu; simplex[1] fixed_p; } model { mu ~ normal(0,1); }`
returns inferred counts `list(mu = 1L)`. Default bundle selection retains
`mu` and `fixed_p[1]`, and reconstruction succeeds. Constructing the same
fit with `include = "none", check = FALSE` retains only `mu`;
`reconstruct_stan_output(bundle$reference_draws, fit)` then fails with
`Input must contain all parameter-block draw columns. Missing: fixed_p[1]`.
The probe used one chain with four iterations and two warmup iterations;
it establishes structural behavior, not acceptance or sampling quality.

The cause is `R/import_reference_posterior_draws.R:771-785`: protected and
mandatory parameter names come from the positive unconstrained-count map.
`R/reconstruct_stan_output.R:207-213` instead correctly requires every
constrained parameter column. The importer also builds its required selection
from `names(fitted_counts)` at lines 137-149, so it has the same source-level
gap when the existing dimensions omit the fixed parameter; that importer case
was not separately reproduced.

Use parameter-block schema names for required saved inputs and exclusion
protection, independently of the positive-count dimension map. Preserve the
count semantics: do not invent a positive free-coordinate count for
`simplex[1]`. Add a public regression for parameter-only and explicit selection,
exclusion protection, conversion/import, and reconstruction, including an
ordinary varying parameter so the model still has free coordinates. Backend
schema recovery should share existing introspection where practical; no new
object hierarchy is needed.

### Historical findings: current-source qualifications

The nine commits do not change the shared writers, diagnostic evaluation,
linking, cache invalidation, or the previously reported S3-contract fixes.
In particular, P11 still has destination retargeting at
`R/create_pdb_bundle.R:434-436`, paired with the unchanged origin test at
`R/write_pdb.R:248-261`. P12 still assigns the reused posterior link only
in memory at `R/create_pdb_bundle.R:530-535`, while the writer skips reused
posterior JSON. Those failure mechanisms remain in the current source;
the two database reproductions above were not rerun in this continuation.

No historical issue is marked resolved merely because these nine commits or
the focused checks passed. Other review documents remain records of their
original snapshot. The newer importer deliberately tolerates dimension names
for saved derived outputs, while new bundles preserve the inferred parameter
count map; account for that compatibility behavior before consolidating these
workflows.

## Continuation evidence and limits (2026-10-02)

The continuation was performed by the primary reviewer without subagents,
using the three Ponytail skills. All nine diffs were read in chronological
order, including their documentation/test changes and final source, and
callers were traced through extraction, assembly, diagnostic selection,
dimension inference, posterior/alias reads, and reconstruction. Checks ran
from a disposable `git archive` of `096ed3f`, not the dirty working tree.

| Check | Result and scope |
| --- | --- |
| `test-bundle-fit-extraction.R` | Passed: 36 expectations across seven cases; mocked backend extraction and coverage/provenance assertions. |
| `test-posterior-dimension-names.R` | Passed: nine expectations across two cases. |
| `test-import-external-stanfit.R` | Passed: 50 expectations across 11 cases, without failures, errors, warnings, or skips. Includes real RStan extraction, mocked CmdStanR extraction, and disposable persistence/rollback fixtures. |
| Real RStan reconstruction probe | Passed: two iterations across two input chains; scalar, `matrix[2,3]`, and `simplex[3]` inputs; deterministic output values/order, nine unconstrained coordinates, exact indexed selection, evaluator reuse, missing-column/unknown-output rejection, compiled-model input, and inferred counts. |
| Real native CmdStanR reconstruction probe | Passed for the same scalar/matrix/simplex input and deterministic value/order checks, unconstrained-coordinate count, indexed selection, and evaluator reuse. A short disposable one-chain fit initialized the native methods. |
| Import selection helper probe | Passed: required names retained, extras included/excluded, required exclusions rejected, and bundle aliases rejected as unknown importer variable names. This checks selection logic, not the complete public import flow. |
| Zero-coordinate RStan parameter probe | Reproduced the D5 failure above; default bundle reconstruction succeeds and parameter-only reconstruction fails. |

Environment: RStan 2.32.7, CmdStanR 0.9.0, CmdStan 2.40.0, posterior 1.7.0,
and testthat 3.3.2. Compilation and database fixtures used temporary paths;
no maintainer database was written. Probe scripts/logs were left in the local
temporary directory under `ponytail-review-096ed3f*`; they are session evidence,
not committed tests.

No full package suite, package installation/check, end-to-end posterior-name
wrapper test, archived-fit recovery test, or stochastic reproducibility test
was run. Neither new reconstruction function has committed test callers at
this snapshot. Retain the earlier T2/D5 recommendations and add focused
regressions rather than a second test framework. Only this review document
was edited; no package implementation or repository test file was changed.

## Original evidence and limits (`55e667e`, 2026-10-01)

The review read commit changes and followed final callers across fit
extraction, dimensional validation, diagnostics, schema completion, bundle
assembly, preflight, component writing, linking, and cached reads. Three
GPT-6-Luna agents at medium reasoning split historical areas, read the
Ponytail skills, and compared findings with the existing documents. Their
work was read-only; final findings and reproductions were checked by the
primary reviewer.

The two new probes exercised the exported constructor and writer in
disposable local databases. They mocked RStan extraction and supplied
deterministic synthetic draws satisfying the implemented checks, isolating
bundle/persistence behavior. They did not prove real RStan or CmdStanR
extraction correctness. No package source or test file was edited, no live
database was written, and no full package suite or Stan compilation was run
for this pass. Earlier execution results remain attributed to the
[test-suite review](ponytail-test-suite-review.md), not presented as new runs.

The package-wide audit did not uncover another major, undocumented
abstraction that warrants a separate redesign. The documented consolidation
of diagnostics/extraction and correction of public/persistence contracts
has higher value than making every helper generic or adding backend classes.
Absence of another finding is a review result, not a correctness guarantee.
