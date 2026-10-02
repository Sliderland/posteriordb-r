# Conversation handoff — updated 2026-10-02

**Start at the [resume checkpoint](#resume-checkpoint--current-2026-10-02).**
Implementation resumed at the maintainer's request; D1–D5/D7/V5/S4 are complete; offline test isolation and the scoped I/O-result audit are complete. V4 is deferred. The historical review
below explains the starting point; it is not the current work queue.

## What we completed

We reviewed import policy, recovery, S3 design, Stan workflows, tests, and
persistence with Ponytail/review/audit, including `a52d05c2`, `43b35058`,
`16cdd444`, and `d960a017`. The final review covered **all 74 commits in
`8aeef19..55e667e`**, crediting later repairs. Findings were documented;
no implementation or test files were changed.

Reviewed snapshot: `55e667e2b11267a5ab9db76e5a15c15ea82c6376` on local `main`.
The docs branch `Agent-ToDo` started from older `upstream/main` at `8aeef19`
and lacked those implementations. The user reports pushing the documents
to GitHub. Inspect the actual newer checkout/refs; do not assume this old
branch layout persists.

## Read these documents

| Document | Purpose |
| --- | --- |
| [AGENT_REVIEW_GUIDE.md](AGENT_REVIEW_GUIDE.md) | Main backlog: S3, diagnostics, persistence, validation, and tests; issue IDs S/D/P/V/T and proposed checks. |
| [ponytail-commit-review.md](ponytail-commit-review.md) | Complete chronological ledger, later fixes, and outstanding concerns. |
| [ponytail-audit.md](ponytail-audit.md) | Simplification, NULL policy decision, S3 consistency, importer recovery, and workflow follow-ups. |
| [ponytail-review-findings.md](ponytail-review-findings.md) | Priorities and minimal implementation recommendations. |
| [ponytail-test-suite-review.md](ponytail-test-suite-review.md) | Test history, historical execution evidence, and coverage limitations. |
| [implementation-guide-stan-workflow-gaps.md](implementation-guide-stan-workflow-gaps.md) | Separate optional proposals: CmdStanR bundles, provenance, archived RStan count recovery. |
| [agentic-implementation-orchestration.md](agentic-implementation-orchestration.md) | Implementation protocol, work units, worker/reviewer templates, and kickoff prompt. |
| [agentic_orchestration_alt.md](agentic_orchestration_alt.md) | Alternative **Plus-only OR Claude Code-only** assignments and kickoff prompts; neither requires both providers. |
| [polishing-cleanup-changes.md](polishing-cleanup-changes.md) | Detailed explanations of implemented changes, partial work, remaining issues and the follow-up Ponytail audit. |

## Historical review conclusions

- Preserve existing issue IDs; most concerns are already actionable in the
  handoff. Do not duplicate the backlog or obsolete criticisms.
- **P11, reproduced:** supplying reused data from database A with destination
  B replaces its source connection; preflight can accept unrelated same-name
  data in B and write accepted draws against that different stored data.
- **P12, reproduced:** an accepted bundle can assign a reused posterior's
  missing reference link only in memory. The writer skips its existing JSON,
  then rejects the draws because no persisted posterior points to them.
  No reference archive was created in the reproduction. Distinguish this
  from P2's failed-candidate dangling-link defect.
- NULL selects the ordinary fixed import policy, very likely to stay
  unchanged. Decide compatibility/redundant forwarding without inventing
  configurable acceptance.
- Fix S3 consistency; do not turn every helper into a generic.
- Coverage gaps extend beyond CmdStanR: public dispatch, constrained counts,
  persisted values, rollback, and database isolation also need attention.

Historical focused tests passed within documented scopes, not a full-suite
proof. P11/P12 probes used disposable databases and mocked extraction;
they did not verify real backend extraction.

## Historical bootstrap instructions

1. Read local instructions, establish the implementation SHA, and revalidate
   findings against newer code. Credit already-fixed issues with evidence.
2. Follow the chosen orchestration guide and authorized scope. Prioritize safe
   fixtures/P11, then P2/P12 if present; optional proposals need explicit scope.
3. Make small shared-cause fixes with public regressions, persisted-state
   checks, and final-patch review. Preserve acceptance, unconstrained counts,
   honest provenance, and compatibility.
4. Never run mutating tests against the user's working database. Rerun checks
   for new code; required unrun verification stays pending.

The user prefers minimal solutions and asks that **Markdown changes be
committed**. Three GPT-6-Luna/medium read-only subagents helped the review;
none wrote the orchestration guides. Future setups use Sol with separate
review, or Claude Opus/Fable; choose one provider profile and verify access.

Prior documentation commits: `a0b10aa` (initial documents), `d484878`
(commit review/P11/P12), `32e9ccc` (orchestration), and `0876fcf`
(separate Plus/Claude profiles). This handoff summarizes the conversation;
it does not declare the backlog implemented or authorize publishing changes.

## Implementation checkpoint — 2026-10-02

Authorized scope: address outstanding confirmed implementation defects using
the Plus-only orchestration profile. One writer; Luna/medium for bounded
read-only inventories, Sol 6.1/high for independent frozen-patch review.
Check assigned files before editing, preserve existing changes in a pre-edit
commit when necessary, and commit each coherent tested unit. Optional new
backend/provenance features remain outside this defect-fixing scope.

Implementation branch: `main`, starting at `b9515c1`. The existing handoff
was preserved before editing in `cd01b5c`. Other dirty/untracked files remain
outside ownership. Available: R 4.6.0, RStan 2.32.7, CmdStanR 0.9.0,
CmdStan 2.40.0, posterior 1.7.0, testthat 3.3.2, roxygen2 8.1.0.

| Findings | Current status and evidence |
| --- | --- |
| S1 | Verified at `688c7d8`: common positional arguments aligned; focused installed tests and S3 signature checker passed. |
| P2, P11, P12 | Verified at `56cb0dd`: persisted candidate links guarded, reused origins retained, accepted reused posterior requires a matching stored link. Empty-link updates use the existing importer. Forty isolated integrity assertions passed, including namespace-only installed loading. |
| V1 | Verified at `b9515c1`: bibliography result captured; eight status assertions and 48 bibliography assertions passed in an installed package. |
| P4 | Partial: rename/bibliography recovery at `ebb5d9e`; partial-write reporting at `ed51544`. Maintainer chose on 2026-10-02 to keep partial bundle/component writes on I/O failure, report completed components/destination, and document inspection/retry/cache refresh/PR review. ZIP/JSON-cleanup errors retain recoverable files. Vignette pre-edit preservation `d83998e`. Six regression failures before repair; final integrity57 passed development and installed namespace-only, with independent Sol review. Installed reference24, rename58, resource170, acceptance28 passed; guides/help rendered (contribution examples disabled). Scoped operation-result audit verified at `b74d113`; future automatic rollback remains open for colleague discussion. |
| P9 | Verified: names/write containment at `587bb86`/`8e5de0c`; common archive/cache boundaries at `fe74ebc`. One safe root JSON member, requested filename matching, cache containment, and partial extraction cleanup shared with rename/link. Initial archive regression had ten failures; damaged-ZIP review regression added three failures. Final 33 archive assertions pass, including a Windows-safe crafted drive-name ZIP. Installed archive33, rename58, resource170 and integrity40 passed; independent Sol review verified corruption repair and portability block. Windows runtime/live GitHub unrun. |
| P3 | Deferred by maintainer on 2026-10-02. Preserve existing manual cache refresh; retain the issue in the active guide for later decision. |
| S3 | Verified at `a5ef7c9`: shared coercion retains and validates an explicit connection; thinning forwards it, standalone NULL remains supported, JSON excludes connection attributes. Regression failed with eight assertions before repair and passed all 16 afterward. Installed reference-connections, import-external-stanfit (50 assertions, real RStan), and bundle-write-integrity (40 assertions) passed. Independent Sol 6.1/high review found no defects and reran the 16-assertion regression against repository sources. |
| S2 | Verified: external thinning registration at `5f93031`, subclass/type/serialization repairs at `e6b2b89`. Initial seven failures/errors; independent review found repeated subclass dispatch and sampler mismatch, reproduced before repair. Delegation now skips already-visited subclass methods and restores the original class chain, preserving direct exported method calls. Final subclass27, transformation28 and connection16 passed development, installed namespace-only and independent Sol review. Installed summary11, integrity57 and resource170 passed; S3 checker clean; help/bundle guide regenerated. Concrete internal backend/name-method bypasses retained after caller audit; no new generics/workers. |
| S4 | Verified at `a5880da`: documentation distinguishes saved-name lookup/list construction and dotted draw wrapping/underscore fit import, corrects component/dimensions names and return type, and explains actual-class dispatch through historical wrappers. Existing aliases and runtime behavior preserved. Public construction/alias probe, development and installed connections16/standalone36 passed; independent documentation review approved. No new tests for this documentation-only unit. |
| S5 | Partial at `d01d58b`: character constructor preserves all five frameworks, keeps Stan default, and requires matching non-NULL implementation metadata through shared assertion. Initial6 failures; final19 passed development, installed namespace-only and independent Sol review. Installed standalone17, lookup9, resource170 and integrity57 passed; help regenerated. Replacement setter deferred by maintainer on 2026-10-02; preserve existing relabelling behavior for now. |
| D1–D6 | Open; fixed NULL-policy compatibility/internal forwarding cleanup already implemented at `56cb0dd`. Preserve numerical conventions and honest historical evidence. |
| D5 | Verified at `673281d`: parameter schema protects zero-free-coordinate saved values independently of positive counts; complete constrained coverage and numeric dimension inputs tested. Real RStan20/import54/counts18 plus affected suites passed development/installed and independent review. Genuine CmdStan schema remains complementary T2 work. |
| D1, D4 | Verified at `2c55964`: small shared diagnostic kernels, explicit E-FMI normalization/fallback, generic extraction routing and no RStan accessor fallback for draw arrays. Focused development/installed checks, genuine RStan50 and genuine CmdStan CSV/no-RStan agreement passed; independent review approved. |
| D2 | Verified at `12ea517`: shared evaluator/flag mapping and check worker, diagnostic variable/chain identity validation at check/write boundaries. Eight focused suites passed development and installed checks; independent review approved. |
| D3 | Verified at `9eaf04f`: method-specific required flags fix analytical checking/writing and automatic summaries without fabricated HMC evidence. Analytical33 plus five affected suites passed development and installed checks; independent review approved. |
| D7 | Verified at `e3e59e6`: shared version construction satisfies the reference schema and avoids RStan probing for CmdStanR. Initial schema/probe regressions failed; final versions11/extraction36 passed development, installed namespace-only and independent review. Genuine CmdStan CSV extraction/version validation also passed in a clean subprocess with RStan unavailable. See the resumed-run details below; no historical-version or acceptance guarantee is added. |
| P1 | Verified at `5f93031`: transformations clear obsolete evidence, retain correct counts/connections, align variable diagnostics and raw sampler inputs; actual-count guards reject forged flags. Initial regression had 14 failures; final 28 assertions pass. Independent Sol review found and then verified repairs for reordered unnamed metrics and adaptive thinning; only fixed positive integer periods are supported. Namespace-only installed transformation and path tests passed (28 and 170 assertions); connections, generic acceptance, deferred checks, integrity, real-RStan imports, diagnostics and lag checks also passed, with one configured-corpus ESS test skipped. `tools::checkS3methods(dir = ".")` passed. Guide/help regenerated. |
| P7 | Verified at `2a71a30`: selected reference type maps consistently across listing/read/write/remove; GitHub consumes type. Original reproduction had one local error and two mocked-GitHub path failures. Final24 assertions passed development, installed namespace-only and independent Sol review. Installed rename58, resource170 and integrity40 passed; S3 checker clean. Help/bundle guide regenerated. Live GitHub unrun. |
| P6 | Verified at `182615b`: stdlib extension helpers, precise per-kind suffix removal, file-only local/GitHub listings and cache metadata names preserve dots/empty character vectors. Initial reproduction had three failures/errors; final listing24/reference27 passed development, installed namespace-only and independent Sol review. Installed rename58, resource170, integrity57 and search23 passed; reviewer also checked full-path cache stripping under a dotted directory. Bundle guide regenerated. Live GitHub/corpus-dependent filter/tibble tests unrun. |
| P5 | Verified at `4a8b7e4`: data/model/model-info lookup shares explicit metadata-link filtering, supports unrelated posterior filename spelling and hyphens, preserves standalone connection requirement. Initial four failures; review added a named-scalar regression that failed before normalization. Final9 assertions passed development, installed namespace-only and independent Sol review. Installed listing24/reference27/search23 passed before final one-line normalization; guide/help regenerated. Corpus-dependent legacy name tests/live GitHub unrun. |
| P10 | Verified at `857a044`: summary payload/metadata now use the same reference identity via existing direct info reader. Initial two failures; final11 passed development, installed namespace-only and independent Sol review across both types and object/name/info/multi access. Installed reference27, resource170, integrity57 and rename58 passed; help/bundle guide regenerated. Live database/GitHub unrun. |
| P8 | Partial at `bca0fd3`: reads/path getters/removal share declared implementation paths and conventional extension fallback for all five frameworks. Supplied posterior metadata is authoritative when it contains the requested implementation; additional frameworks retain attached-database fallback. Original custom-Stan/PyMC removal errors reproduced; independent review added a supplied-vs-stored path regression, then installed standalone checks exposed the additional-framework compatibility case. Final model-path97 and standalone17 passed development, installed namespace-only and independent Sol review. Installed framework19, resource170 and real-RStan import50 passed; help/bundle guide regenerated. Non-Stan writing deferred; custom-path writer contract open. Existing writer behavior preserved and documented. Live GitHub unrun. |
| V3 | Verified at `10cf216`: summary fields checked by name, required values/MCSE aligned to unique nonmissing variable labels, attached metadata validated; reference-info keys order-independent with the same required-key schema. Original16 failures/errors; final39 passed development, installed namespace-only and independent Sol review. Installed identity11, subclass27, transform28, integrity57, acceptance28 and rename58 passed; help/bundle guide regenerated. Numeric NA/Inf and extra numeric-field length behavior preserved and documented. |
| V2 | Verified at `472f867`: supplied posterior validated without reloading; getter-returned model/data/draw content and metadata checked; detached results skip cache eviction. No citations need no bibliography; supplied citations require a connection and are checked for all three component types. `check_pdb()` still loads saved records and checks database-wide consistency. Original reload errors reproduced; independent review added two failing metadata/getter-result regressions. Final standalone36 passed development, installed namespace-only and independent Sol review; installed status8, model-path97, bibliography48 and integrity57 passed. Help/bundle guide regenerated. Stan execution enabled during posterior checking and the broad corpus suite were not run for this unit. |
| V4 | Deferred by maintainer on 2026-10-02 after discussion of nested-list ambiguity. Preserve current batch behavior; clarify workflow usage in the guide. |
| V6 | Open; revalidate and separate demonstrated bugs from policy choices. |
| V5 | Verified at `3d519bb`: supported controls translated, aliases/conflicts/NULL options handled and native iteration names matched exactly. Final arguments55/versions11 passed development and installed namespace-only; independent review approved and reran arguments55. Genuine CmdStan CSV40-draw smoke confirmed step_size0.5 and disabled adaptation for both chains. Help and bundle guide regenerated; no broad suite run. |
| T1 | Verified at `1e80aea`: default tests are offline; each opt-in corpus test copies the configured database, scopes both path settings and working directory, and cleans up even after failure. Direct `test_file()` loads the same helper. Stan/GitHub integrations have separate explicit flags; automatic CI uses fixtures and a manual corpus workflow pins a full revision SHA. Development and installed namespace-only suites each passed 1,203 assertions with 40 explicit skips and a nonexistent corpus sentinel; harness33 and independent review passed. Manual corpus CI, live GitHub and Windows runtime remain unrun. |
| T2–T3 | Partial: new isolated fixtures, installed checks, affected help/guides, and unused dependency/helper removal added. Complementary backend coverage and broader public documentation remain open. |

The package harness now isolates configured database paths, but direct
test/coverage runs can bypass it and working-directory configuration can
override paths. Focused tests must use inspected disposable fixtures.
Existing passing runs are evidence for their listed commits only; new
changes require new checks.

No writer/reviewer owns an unfinished patch. Completed issues are removed
from the active guide; this checkpoint and Git retain their evidence.

## Resume checkpoint — current 2026-10-02

Previous checkpoint: the maintainer asked to finish the current unit and stop
for that usage window. V2 completed at `472f867` on `main`. All implementation changes,
tests, generated help and user-guide changes from this run are committed.
The final documentation checkpoint is a subsequent commit; use `git log`
to identify the current HEAD rather than assuming this implementation SHA
is the latest commit. Both agents finished read-only work and confirmed
that they have no edits or commits owed. Do not relaunch an old task.

The maintainer subsequently authorized a bounded report/audit polishing pass.
The [detailed report](polishing-cleanup-changes.md) was committed at `c83343b`
before a fresh read-only Luna/medium audit. Its small changes remove repeated
dimension validation, reuse the existing model-info rename method, and fix
recursive connection defaults found while exercising object renames. This
does not resume the broader backlog or change its eighteen remaining IDs.
The follow-up implementation is committed at `5b88e7d`: extraction36 and
rename69 passed development and installed namespace-only checks, and a
separate Sol 6.1/high reviewer approved the final patch. The fixture-only
review suggestion was applied and rechecked. All three read-only agents
finished with no edits or commits owed; no agent work is pending.
The audit also suggested sharing GitHub download code; that optional cut is
still open because the helper's existing-file behavior differs from the copy
method. Preserve overwrite and cache semantics before attempting it.

### Remaining scope and next unit

**24 of the original 33 finding IDs are fully verified; 9 remain open,
partial, or deferred.** The authoritative remaining list is the
[active guide](AGENT_REVIEW_GUIDE.md#active-backlog-maintenance--2026-10-02):
S5, D6, P3/P4/P8, V4/V6 and T2–T3. These are tracking groups, not
9 equally sized bugs. Several require a behavior decision or an audit.

Next priorities within the current usage window: complementary genuine CmdStan
coverage/dependency guards (T2/T3), then bounded V6 defects and V4 usage examples. Each stays a bounded reviewed unit with
its own implementation and checkpoint commits. Lower-priority API choices
remain explicit in the queue; do not guess a deferred policy to close an ID.

### Resumed run — D7 verified at `e3e59e6`

The maintainer authorized the remaining implementation plan and explicitly
kept P3, the S5 setter and non-Stan writing deferred. The same one-writer,
Luna/medium inventory and separate Sol 6.1/high review loop continues.

D7 reused the existing R-environment helper, with an explicit switch to skip
RStan probing. Both version constructors now agree with the reference-info
schema; CmdStanR paths omit RStan and preserve available backend fields.
Help and the bundle guide distinguish installed R/RStan versions from the
Stan version reported by CmdStan CSVs. No new provenance scheme was added.
Assigned files were clean before editing; no preservation commit was needed.

Two failing-before regressions established the missing session/Makevars
fields and forbidden RStan probe. Final versions11/extraction36 passed in
development and an installed namespace-only package; independent review
passed both and approved the final documentation correction. A genuine
CmdStan 2.40 Bernoulli executable produced 40 saved draws; extraction and
public reference-info validation passed. The same check passed in a fresh
subprocess whose temporary package library excluded RStan: normal
`requireNamespace("rstan")` returned FALSE, package lookup was empty, and
RStan was never loaded. This tests availability, not a mocked fit class.
The short run emitted adaptation warnings and is not acceptance evidence.

The dependency-only library check used symlinks to the installed packages
excluding RStan, with the verified posteriordb library first. Within that
subprocess only, base `.Library` and `.libPaths()` pointed to the temporary
view. Host packages were untouched. No live GitHub, Windows, or full package
suite was run. The code/test/generated-guide commit is `e3e59e6`; this
Markdown checkpoint follows separately.

### Resumed run — V5 verified at `3d519bb`

The translator previously discarded all but two RStan controls, and native
aliases could override explicit settings. It now maps eight supported nested
controls to the actual CmdStanR 0.9 interface, rejects unsupported controls,
normalizes eight native legacy aliases and detects duplicates. The special
`validate_csv` alias cannot override explicit `diagnostics`, including NULL.
Exact name access fixes `iter_sampling`/`iter_warmup` being mistaken for
`iter` through R partial matching; retired NULL RStan options are removed.
Explicit native NULL options remain intact. No backend registry was added.

Original control loss/conflicts and the native-only iteration error were
reproduced. Review supplied two more concrete counterexamples (validate_csv
precedence and NULL leftovers), both reproduced and covered by regressions.
Final arguments55/versions11 passed development and installed namespace-only;
separate Sol/high review reran arguments55 and approved source/docs. A
genuine precompiled CmdStan model sampled 40 retained draws with translated
settings; both CSVs and metadata confirmed step_size0.5 and adaptation off.
Adaptation is encoded as numeric0 in the metadata; the CSV header says false.
No acceptance claim is made. All assigned files were clean before editing;
no pre-edit commit was needed. Code/tests and regenerated help/bundle guide
are in `3d519bb`; this checkpoint is separate. Live GitHub, Windows and broad
package tests were not run.

### Resumed run — S4 verified at `a5880da`

This was a documentation correction, not an API redesign. `posterior()` looks
up a saved name, while `as.posterior()` constructs from a list. The component
fields are `pdb_model_code`, `pdb_data`, and `dimensions`; omitted counts can
require Stan compilation. Dotted draw coercion wraps supplied metadata and
omits lp__, whereas underscore fit import validates counts and runs checks.
Historical backend-named wrappers dispatch on the actual fit class. Aliases
are preserved and the documented draw return class is corrected.

A public probe reproduced the unsupported `posterior(list)` call and verified
`as.posterior()` plus its alias with typed components and explicit counts.
Development and installed connections16/standalone36 passed; independent
review approved the documentation and regenerated help/guide. No runtime code
or new tests were added. Assigned files were clean before editing, so no
preservation commit was required. Implementation/docs commit: `a5880da`.

### Resumed run — D3 verified at `9eaf04f`

Analytical checkers already omitted Stan diagnostics but the final guards
required HMC success flags, preventing analytical draws from being checked
or written. One small private helper now lists applicable flags by method
and gate; assertions and automatic summary transfer use it. Analytical
objects carry only count evidence. Stan keeps all six gates, unknown methods
reject, and actual/recorded counts must still agree: exactly 10,000 reference
draws versus at least 10,000 summary draws. No numerical calculation changed.

Three initial regressions failed against the old code. Final analytical33,
transformation28, summary-validation39, generic-acceptance28, connections16
and integrity57 passed development and installed namespace-only checks.
Independent Sol/high review approved and reran analytical33. Round trips cover
the draw archive, automatic summaries, and a separately written 11,000-draw
summary. Explicit cache clearing after overwrite preserves deferred P3.
Help and the bundle guide were regenerated. Assigned files were clean before
editing; no pre-edit commit was needed. No backend/network integration or
broad package suite was required for this unit. Agents remain read-only.

### Resumed run — D2 verified at `12ea517`

Reports and stored-draw checks now share the existing policy evaluator;
reference/summary checkers share one worker with distinct count rules. A
single small report-to-JSON flag mapping also feeds assertions, bundle flags,
and summary evidence transfer. Required Stan metric labels must match the
current variable set or positional chain1..n labels; the existing count guard
validates labels at check and write boundaries. Reordered named vectors and
unnamed legacy positional vectors remain supported. Mismatched ESS labels
produce informational FALSE rather than rejecting otherwise valid draws.
No diagnostic formulas changed and writers do not recompute metrics.

The initial alignment regressions reproduced acceptance of unrelated labels.
Final alignment22, diagnostics53, lag23 (one corpus skip), analytical33,
transformation28, acceptance28, deferred22 and integrity57 passed development
and installed namespace-only. Independent review approved and reran
alignment22/diagnostics53; no corpus-wide or live-backend check was done.
Assigned files were clean; implementation, tests and regenerated guide/help
are one commit and the queue/checkpoint is separate.

### Resumed run — D1/D4 verified at `2c55964`

Named lag, scalar-variable R-hat/ESS, divergence counts and E-FMI calculations
now use small shared workers rather than repeated loops. The strict lag
wrapper still rejects short/undefined series; reports retain named NA values.
The E-FMI worker explicitly preserves RStan sum(diff(energy)^2)/n/var(energy)
versus CmdStan mean(diff(energy)^2)/var(energy). Review found and reproduced a
pre-existing wrong-normalization fallback when RStan metadata lacked E-FMI;
the shared report fallback now chooses using backend metadata/provenance.
Deferred bundles forward provenance and drop their duplicate calculation.

Both internally sampled backends and bundle construction route through the
existing extraction generic. Saved source/count coverage remains bundle-only,
selective reports remain selective, and this adds no CmdStan bundle support.
A generic draws array with absent sampler evidence no longer calls RStan
fit accessors; absent required metrics remain NA and fail acceptance. The
legacy private worker still supports actual stanfit fallback.

Missing-metric and fallback regressions failed before their respective fixes.
Final workers27/diagnostics53/deferred22/acceptance28 passed development and
installed namespace-only. Before the reviewed fallback repair, the broader
installed set also passed lag23 (one corpus skip), extraction36, alignment22,
transformation28 and versions11. Independent final review approved and reran
workers27/deferred22. Genuine RStan import50 passed. Genuine saved CmdStan
CSV diagnostics matched report/stored calculations in a clean subprocess
with RStan unavailable and never loaded; short-fit ESS warnings were expected,
with no reference-acceptance claim. Guide rendered; files were clean before
editing and the implementation commit is separate from this checkpoint.

### Resumed run — D5 verified at `673281d`

Parameter selection now uses the compiled parameter-block schema independently
of positive unconstrained counts: RStan constrained_param_names(FALSE,FALSE)
and CmdStan's public variable_skeleton() with derived outputs disabled.
A simplex[1] value is mandatory saved coverage despite contributing zero free
coordinates and no dimensions entry. Existing-posterior import and bundles
retain/protect it; no fake positive count or Stan-source parser was introduced.
Bundle extraction checks full saved shapes, and assembly no longer repeats
count-based report selection. Schema recovery recompiles a zero-chain RStan
fit with supplied source/data, preserving the current broad fallback; D6's
narrowing audit remains open. Stored undefined lag metrics remain NA, letting
failed candidates be inspected without conferring acceptance. The strict
checker/writer still rejects them. Named numeric dimension vectors now reach
the common validator rather than failing an earlier list-only assertion.

Real RStan coverage initially failed four times for missing fixed[1]. Final
constrained20/import54/counts18/extraction36/workers27/acceptance28/deferred22
passed development and installed namespace-only. The real model includes
simplex, correlation/covariance and Cholesky types, matrix/array/vector-one,
zero-free values and derived outputs: 29 free coordinates versus 47 saved
parameter scalars. Import tests also cover CmdStan schema selection with a
bounded mock. Independent review approved and passed real coverage20/import54/
extraction36. Genuine compiled CmdStan count/schema coverage is still T2 work.
Files were clean before editing; guide/help regenerated and committed with
code/tests. No user database was involved.

### Resumed run — T1 verified at `1e80aea`

The old package entry point staged a corpus, but direct test and coverage
runs bypassed it; ordinary tests also implicitly cloned or used live backends.
Default tests now use the existing offline fixtures. Corpus, Stan and GitHub
checks require `PDB_TEST_DATABASE`, `PDB_TEST_STAN` and `PDB_TEST_GITHUB`
respectively, set to `true`. Each corpus test creates its own disposable copy,
including hidden entries, and scopes options, environment and working directory
with cleanup on failure. The helper runs at the test call site, so direct
`test_file()` and coverage runs get the same protection.

Automatic CI no longer checks out the external corpus. The new manual database
compatibility workflow requires a full commit SHA. README source/rendered text
explain the flags and commands. No runtime package behavior changed. Per-test
corpus copying is deliberately simple; replace heavy cases with small fixtures
if opt-in copy cost matters rather than adding a fixture-cache framework.

Final development and freshly installed namespace-only suites each passed
1,203 assertions with 40 explicit integration skips, `NOT_CRAN=true`, all
integration flags disabled, and a nonexistent PDB_PATH sentinel. The isolation
harness passed 33 assertions, including direct-file loading and failure cleanup;
independent Sol review approved and reran those 33. An initial fixture syntax
error was corrected before both full final runs. Real corpus/manual CI, live
GitHub and Windows runtime were not run for this unit. README's new section was
kept in sync with its Rmd; full README Rmd execution still depends on a live
configured corpus and is part of the broader T3 documentation work.

### Resumed run — P4 operation-result audit verified at `b74d113`

Rename used to accept a failed ZIP command when it still created a file.
Staging now checks status/existence, the expected root JSON member, and the
extracted payload checksum before reserving any originals. Wrong-member and
altered-payload cases also abort with original bytes and working directory
intact. Plain cache copies now reject failure and remove incomplete cache
files on either a false result or thrown error, so a retry cannot reuse partial
bytes. The shared removal primitive raises a path-specific error on failure;
component methods therefore stop before deleting their metadata. Successful
removal still returns TRUE; arbitrary-path semantics and P3 manual refresh
remain unchanged.

Import rollback reports incomplete installed-file deletion and the original /
retained backup paths. It attempts every recovery before emitting a combined
warning, including when warnings are errors (`warn = 2`). Review reproduced
partial cache reuse and early warning abort, and both were fixed in this unit.
No new transaction framework or automatic bundle rollback was added.

Development and installed namespace-only checks passed rename81, cache41,
model101, import48 (five real-Stan opt-in skips), integrity57, resource170 and
reference27. Cache/import were reinstalled and rerun after their review repairs;
other files were unchanged. Generated help and bundle guide rendered; independent
Sol review approved. Initial injected ZIP/cache/removal/rollback failures were
reproduced before repair. Windows runtime/live GitHub remain unrun. P4 stays
open for the maintainer's future sequential-write rollback discussion.

### Maintainer decisions and questions for later

- **V4 deferred:** preserve batch-list classification. Document the supported
  shared/per-workflow forms; revisit ambiguous-map rejection only after a new
  maintainer decision. Future questions must explain the concrete behavior,
  not only refer to an issue abbreviation.
- **P3 deferred:** keep manual cache refresh. Before changing it, decide
  whether writes/removals should immediately update reads on the same
  connection or retain the original refresh requirement.
- **S5 setter deferred:** the constructor is fixed. The existing setter
  changes a framework label without rewriting code. Leave it alone until
  the maintainer decides whether relabelling should require matching
  metadata or creating another object.
- **P8 partial:** read/removal paths are fixed. Non-Stan writing is deferred;
  decide writer support and custom-path handling before changing it.
- **P4 current choice:** keep partial writes after I/O errors, report what
  succeeded, and let contributors inspect/retry and reviewers assess the
  files in a pull request. Reporting and documentation are implemented.
  Keep automatic rollback open for colleague discussion. Changing this
  choice later is feasible, but needs staging/restoration and failure tests;
  the current code does not commit the project to a transaction framework.
- **Numerical/identity choices:** D1 preserves the intentional E-FMI finite-sample
  normalization difference explicitly. D5 preserves the current full-parameter
  contract: include/exclude cannot remove model parameter-block variables.
  D6 stronger source/data verification is an optional policy enhancement,
  not an undisclosed guarantee of the current importer.
- **API choices:** S4 is documented without breaking aliases. V6 needs decisions before changing configuration
  fallback, arbitrary-path removal, summary return values or endpoint return
  contracts. The active guide contains the specific examples.

The maintainer confirmed P3/S5/non-Stan writing deferrals and additionally
deferred V4 during the resumed run. Ask about any new choice when its unit is selected; do not
infer approval for a deferred change from elapsed time.

### How this implementation loop worked

One coordinator wrote code and committed the units. A reusable **GPT-6 Luna,
medium** agent (`p1_inventory`) mapped a bounded issue read-only. A separate
**GPT-6.1 Sol, high** agent (`unit_review`) reviewed each frozen patch and
ran focused checks. Both had explicit scope and no recursive delegation.
Actual reviewer counterexamples were repaired, reproduced in regressions,
retested, and submitted for final review. Reuse this small loop; no custom
agent framework or simultaneous writers are needed.

For each next unit:

1. Read this checkpoint, local `AGENTS.md`, the relevant active finding and
   the [Plus profile](agentic_orchestration_alt.md). Query the code graph to
   narrow scope, then verify the source and adjacent callers.
2. Inspect `git status` for assigned files. Commit relevant existing changes
   before editing if dirty; leave unrelated changes alone. If clean, edit
   directly. Record the unit's base SHA and ownership.
3. Reproduce the public failure in a disposable fixture, repair the shared
   cause with existing helpers, and run affected development tests. Preserve
   acceptance, counts, connections, JSON and honest provenance.
4. Regenerate affected roxygen help and Rmd-derived guides. Install into a
   temporary library and test without attaching the package. Run a real
   backend check when the changed interface requires it.
5. Freeze the exact patch for independent review. Repair concrete findings,
   rerun justified checks and review the final delta. Inspect staged files
   and make the post-edit implementation commit.
6. Remove verified work from the active guide/queue, leave partial and
   deferred work visible, record SHA/tests/limitations here, and commit the
   Markdown checkpoint. Stop at a coherent boundary when the user asks.

Example installed verification from the repository root (choose only
inspected disposable tests appropriate to the new change):

```r
verification_library <- tempfile("pdb-verification-")
dir.create(verification_library)
status <- system2(file.path(R.home("bin"), "R"), c(
  "CMD", "INSTALL", "--install-tests",
  paste0("--library=", shQuote(verification_library)), "."
))
stopifnot(status == 0L)
.libPaths(c(verification_library, .libPaths()))
stopifnot(requireNamespace("posteriordb", quietly = TRUE))
testthat::test_file(system.file("tests", "testthat",
  "test-standalone-posterior.R", package = "posteriordb"),
  package = "posteriordb", reporter = "summary", stop_on_failure = TRUE)
```

The package harness stages a disposable corpus, but direct test/coverage
runs can bypass it and working-directory YAML configuration remains open
under T1. Never run the broad legacy suite against a maintainer database.
Real RStan import50 last passed for the P8 candidate; the later units have
their own listed focused evidence. Live GitHub, Windows runtime, genuine
no-RStan CmdStanR environments and the broad package check remain unverified.

### Working-tree boundary at pause

Unrelated pre-existing changes remain: `.Rbuildignore`, `.gitignore`, the
untracked fit-import/reference-check documents, historical audit/review
Markdown files, and ad hoc test scripts/logs. They were not swept into
implementation commits. Inspect them before taking ownership; do not reset
or delete them to make the tree look clean. The alternate orchestration
guide was preserved before its resume edits in `ad90721`.

All fixes are separate ordinary commits with matching checkpoint commits;
use Git to inspect/revert selected units if needed. Do not reset/rebase the
shared branch or revert a unit without considering later dependent changes.
