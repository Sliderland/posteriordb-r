# Agentic implementation guide for the reviewed PosteriorDB gaps

Prepared on 2026-10-01. Give this file, the review documents listed below,
and access to the intended implementation checkout to the implementing agent.
This guide supplies a work protocol; the review documents supply findings
and feature specifications. Creating this guide did not implement any fixes.

For a Plus-only or Claude Code-only setup, also read the
[alternate provider profiles](agentic_orchestration_alt.md), which replace
the model assignments and kickoff prompt while preserving this work protocol.

## Recommended setup and model assignments

Use a small team with **one code writer at a time**. Start with these roles;
do not build a custom agent framework for this repository.

| Role | Specific model and reasoning effort | Responsibility |
| --- | --- | --- |
| Coordinator and usual implementer | **GPT-6.1 Sol — `gpt-6.1-sol`, high** | Resolve the implementation base, read contracts, sequence work, implement one bounded fix, inspect evidence, integrate and commit. |
| Independent correctness reviewer | **GPT-6 Astra — `gpt-6-astra`, high** | Review the exact patch and adjacent callers, especially persistence, source identity, unconstrained counts, acceptance, and numerical behavior. Do not edit the candidate being reviewed. |
| Explorer/test inventory assistant | **GPT-6 Luna — `gpt-6-luna`, medium** | Map callers, existing helpers, tests, and dependencies for a specific issue. Return source evidence and open questions. Default to read-only. |
| Optional separate implementation worker | **GPT-6.1 Sol — `gpt-6.1-sol`, high** | Use when the coordinator is another model or needs to delegate. Own one issue and explicitly assigned files; be the sole code writer for that unit. |

These role/effort assignments are recommendations for this package, not
published R/Stan-specific benchmarks. OpenAI describes Astra as its strongest
model for demanding work, Sol as a balance of capability and cost, and Luna
as suited to focused work. See the [official model catalog](https://developers.openai.com/api/docs/models)
and [model-selection guidance](https://developers.openai.com/api/docs/guides/model-selection).

For a lower-cost setup, use a separate **GPT-6.1 Sol/high** reviewer and
reserve **GPT-6 Astra/high** for unresolved persistence or mathematical
questions. For a quality-first setup, use **GPT-6 Astra/high** as coordinator
as well as a separate reviewer. Keep review contexts separate even when
using the same model. Neither separation nor a stronger model guarantees
correctness; observable behavior and test evidence govern acceptance.

Do not give Luna sole ownership of acceptance redesign, recovery semantics,
or provenance guarantees. It can implement a narrowly specified mechanical
change once its contract and checks are settled, with stronger review.

Check which exact models and effort settings the actual client exposes.
Specify both when spawning; do not assume subagents inherit the desired
configuration. Model selection and custom agent settings are described in
the [official subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents).
If a requested model is unavailable, report the actual substitute. If the
runtime cannot delegate, perform the same stages sequentially; disclose
that review was not independent. Do not claim nonexistent agents or model
upgrades. An unknown or weaker coordinator should delegate substantive
implementation/review to the stronger roles when available, and check their
evidence rather than attempting to settle difficult contracts by confidence.

Three active roles are usually enough: coordinator/writer, bounded explorer,
and reviewer. With four available slots, an additional read-only test
inventory task is reasonable. Read-only searches can run concurrently;
dependent edits, generated files, integration, and commits are sequential.
No recursive delegation unless the coordinator explicitly assigns it.

## Read these inputs and distinguish their authority

| Input | How to use it |
| --- | --- |
| [Agent handoff](AGENT_REVIEW_GUIDE.md) | Main defect/contract record, with S/D/P/V/T identifiers, affected behavior, and verification guidance. Read P11/P12 as well as the older sections. |
| [Commit review](ponytail-commit-review.md) | History and final-snapshot disposition. Repairs credited here are not bugs to reintroduce or fix again. |
| [Ponytail findings](ponytail-review-findings.md) | Priority and simplification guidance; contracts take precedence over an attractive refactor. |
| [Ponytail audit](ponytail-audit.md) | Redundant forwarding/diagnostics, S3 consistency, fixed NULL policy, and remaining workflow concerns. |
| [Test-suite review](ponytail-test-suite-review.md) | What earlier runs established, what they did not, and missing regression coverage. Its historical test results are not evidence for a new patch. |
| [Stan workflow proposals](implementation-guide-stan-workflow-gaps.md) | Optional CmdStanR bundles, provenance, and archived RStan recovery specifications. Implement only the features included in the current task. |

Read applicable `AGENTS.md`, package contribution instructions, `DESCRIPTION`,
test entry points, and CI configuration on the actual branch. Follow the
user's current scope and governing instructions. The historical documents
are evidence, not permission to change every policy or implement every
proposal. Verify each proposed defect against current source and callers.

If guides conflict, record the concrete contract conflict. Prefer the
current authorized task and demonstrated supported behavior; use history
to explain compatibility, not to overrule newer code blindly. Do not turn
a suggested helper/file name into a mandatory architecture.

## Stage 0: establish the correct implementation checkout

This step matters particularly here. `Agent-ToDo` was created from
`upstream/main` at `8aeef19` and contains review-document commits. The reviewed
feature code is on `main` through
`55e667e2b11267a5ab9db76e5a15c15ea82c6376`. The docs branch lacks those
features; implementing there would start from the wrong code.

Before editing, record:

```sh
git status --short
git branch --show-current
git rev-parse HEAD
git log -5 --oneline --decorate
git show-ref --heads --tags
```

1. Identify the implementation ref authorized by the user. For the reviewed
   work, this is `main`, or its authorized newer replacement, not
   `Agent-ToDo`. Compare its source with the reviewed snapshot. Do not assume
   a local remote-tracking ref is the latest remote version.
2. Create a separate implementation branch/worktree from that ref when useful.
   Keep unrelated user changes and untracked files untouched. Do not reset,
   rebase, merge feature history into an old base, or switch a dirty checkout
   merely to make the documents' paths resolve.
3. Make these documentation files available in that worktree. The historical
   docs-only commits are `a0b10aa` and `d484878`; additional docs commits may
   follow. Inspect their diffs before selectively copying or cherry-picking
   them. Do not merge the entire old-base docs branch as a shortcut.
4. Verify required symbols exist, such as `create_pdb_bundle`,
   `extract_external_stan_fit`, and `preflight_pdb_bundle_write`. If absent,
   resolve the base rather than recreating the missing feature history.
5. Record R/dependency versions and available Stan backends/toolchains.
   Missing backend resources are a testing limitation, not a reason to fake
   passing integration results.

**Exit evidence:** implementation ref and SHA, clean ownership boundary,
available input docs, and a short explanation of differences from `55e667e`.
If the correct source is unavailable, identify exactly what is missing.
Continue read-only preparation, but do not implement against a guessed base.

## Stage 1: turn findings into small work units

Maintain a compact status list in the existing handoff document or an
existing implementation log. Remove verified completed items from the active
issue guide and work queue; retain commit/test evidence in the handoff and Git
history. Keep partial, deferred, blocked, and decision-needed work visible. Do not create a second full copy of the backlog.
Use original issue identifiers; split combined rows below into individual
commits whenever contracts or tests are independent.

For each selected issue, record: current source status, public failure,
root cause/callers, intended contract, smallest repair, affected files,
tests, dependencies, and evidence needed to finish. Statuses should distinguish
`open`, `already fixed at <SHA>`, `in progress`, `verified at <SHA>`,
`implemented, verification pending`, `decision needed`,
`blocked by <specific resource>`, and `deferred by scope`.
Source-confirmed findings still need a reproduction where practical.

Suggested order for confirmed defects:

| Work area | Finding IDs | Scope and required result |
| --- | --- | --- |
| Test isolation for the selected work | T1 | Use disposable databases before any write/remove test. Refactor unsafe legacy harness/tests before a broad suite run. This need not delay isolated bug probes. |
| Report partial writes; future rollback open | P4 | Maintainer chose to retain partial bundle/component writes on I/O failure, report successful components, and document inspection/retry and contribution PR review. Keep automatic rollback open for colleague discussion. Existing rename/bibliography recovery fixes remain in place. |
| Deferred: cache contract | P3 | Maintainer deferred this on 2026-10-02; preserve current manual refresh until resumed. Original proposal: Successful shared writes/removals make public reads reflect disk; failed writes preserve usable prior state. |
| Review remaining remove/API boundaries | Relevant V6 | Write/cache containment and archive checks are verified (P9). Clarify arbitrary-path removal semantics before changing compatibility. |
| Repair public object/S3 contracts | S2, S4, S5 | Align signatures/registration, preserve connection/framework inputs, and support documented subclass behavior. Do not make every helper generic. |
| Repair database/object checking | V2 | In-memory checking actually checks the supplied object. |
| Repair lookup/path/reader contracts | P5, P8, P10 | Follow explicit metadata links and correct framework paths; handle distinct reference names. |
| Normalize other validation | V3, V4, remaining V6 | Validate summary fields/lengths and batch options; distinguish missing optional resources from malformed ones. |
| Consolidate applicable diagnostics | D1–D3 | Shared numerical workers and required-check evaluation, preserving fixed thresholds, selective/deferred behavior, and analytical applicability. |
| Align backend behavior and evidence | D4, D5, D7, V5 | Reuse extraction where contracts match; correct counts, metadata schema, and option translation. Verify changed real backend interfaces. |
| Resolve documented policy choices | D6, S4, NULL policy follow-up | State supported identity/conversion guarantees and compatibility decisions. Do not silently add configurable acceptance or claim unknown historical provenance. |
| Complete complementary tests/docs/dependencies | T2, T3 | Add installed-package/public-contract/backend coverage and accurate source documentation alongside affected fixes. |

This is a starting priority order, not permission for one giant patch.
Several rows touch the same files and must be serialized. Discover concrete
dependencies from callers. Make small correctness repairs before large
mechanical extraction/refactoring; defer speculative features and unrelated
cleanup. Optional features have their own specifications and completion
criteria in the Stan workflow guide.

## Stage 2: the protocol for every work unit

Use this cycle. A worker's “done” message cannot skip a stage.

1. **Trace.** Read the relevant exported entry point, dispatch, callers,
   constructors, validators, serialization, cache, and failure paths. Use
   `rg` to find existing helpers before adding one. Write a short behavior
   contract; distinguish data identity, mathematical acceptance, and database
   consistency.
2. **Reproduce before fixing.** Add the smallest meaningful failing regression
   check in the existing test framework, using a disposable fixture. Confirm
   it fails on the parent implementation for the intended reason. If newer
   code already passes, inspect the claimed repair and mark the finding
   already fixed only with corresponding evidence.
3. **Implement at the shared cause.** Repair the owner of the broken contract,
   rather than adding a workaround to each caller. Reuse installed packages
   and existing helpers. Keep names, outputs, compatibility adapters, and
   valid existing behavior unless the task explicitly changes them.
4. **Verify behavior and state.** Run the regression, affected existing tests,
   and relevant public/installed/backend checks. For persistence, assert
   actual saved values, links, cache reads, and failure state—not only messages
   or an in-memory class. Report exact commands and outcomes.
5. **Freeze and review.** Give the reviewer the base/candidate SHA or exact
   frozen diff, issue contract, reproduction, and evidence. The reviewer
   reads the patch and adjacent code independently, checking correctness and
   unnecessary complexity. Do not edit under an ongoing review.
6. **Resolve findings and commit.** Address concrete review defects; rerun
   checks justified by those changes and obtain review of the final changed
   diff. Inspect staged files, commit only the bounded unit, and update the
   issue record with the implementation SHA and limitations. Commit Markdown
   edits as the maintainer requested. Then select the next independent unit.

If the failure is nondeterministic, stabilize its fixture/seed and explain
what it tests. Do not repeatedly retry until green. If an initial regression
cannot be run because a resource is unavailable, say so and use the strongest
available source/unit evidence; keep the missing integration check explicit.
Passing mocks do not satisfy a real-backend completion criterion.

The coordinator must inspect actual tool output or saved test logs, not only
the worker's summary. After delegated implementation/integration, run the
critical regression against the integrated candidate, or have the separate
reviewer run it in an isolated test environment. Evidence must identify the
code tested. An unrun check required by the agreed contract leaves the unit
`implemented, verification pending`, even if available unit tests pass.

Ask about genuinely unresolved behavior choices once, with a concrete
example and alternatives. Continue unrelated authorized work while awaiting
the answer. Routine implementation choices do not need repeated approval.
Do not replace numerical policy, overwrite rules, or historical-evidence
claims merely because doing so makes a test pass.

## Contracts that every worker must preserve

- Posterior dimensions are scalar **unconstrained parameter counts** keyed
  by model parameter; saved constrained output names/shapes are separate.
  A simplex of length K has K saved elements and K - 1 free coordinates.
  Transformed parameters/generated quantities do not become free parameters.
- Preserve draw values, variable/chain/iteration order, and post-warmup
  boundaries. Import/conversion does not resample or secretly thin.
- The reviewed fixed Stan policy requires exactly 10,000 retained reference
  draws, at least four chains, mean absolute per-chain lag-1 correlation at
  most 0.05 per variable, R-hat at most 1.01, E-FMI at least 0.2 per chain,
  and no divergences. Summary acceptance permits at least 10,000 draws.
  ESS and treedepth are informational. Verify newer authorized changes
  before applying these historical values.
- Analytical draws require method-appropriate checks. Do not fabricate HMC
  successes to pass a writer guard. Selective checks calculate/fetch only
  requested or genuinely required inputs.
- `check = FALSE` skips diagnostic calculation while preserving required
  raw inputs for later checking; structural validation still applies.
- Construction/conversion is in memory. Persistence is explicit, and failed
  or unchecked candidate draws remain unwritable under the existing contract.
- Reused objects retain source identity until collision validation. Destination
  connection attachment does not prove origin or equivalence of contents.
- Metadata reflects available evidence. Import-environment versions and
  count-recovery compilation are not historical sampling provenance.
- Fixed policy/NULL compatibility should very likely remain unchanged.
  A decision about redundant forwarding does not authorize a policy engine.
- Preserve supported JSON layouts, explicit optional NULL fields, descriptive
  metadata, and supplied implementations. Update roxygen/Rmd sources and
  regenerate derived documentation when the corresponding API changes.

For changed acceptance algorithms, compare workflows using identical draws
and sampler inputs. Keep undefined diagnostic behavior explicit. The existing
RStan E-FMI finite-sample convention needs a deliberate mathematical decision
before replacing it with another formula; matching names are insufficient.

## Concrete acceptance checks for the two newly added defects

### P11: cross-database reused objects

Build isolated databases A and B with different payloads under the same data
name. Load the connected object from A, call the **public** bundle constructor
with `pdb = B`, and call the public writer. B's collision must be rejected
before mutation under both overwrite settings. Compare destination state
before/after, including links and reference files. Repeat for model objects;
cover supported supplied-posterior reuse without assuming its connection
follows the data/model path.

Also verify genuine same-database reuse and copying into an empty destination.
Read persisted values through public getters and compare with the intended
bundle contents. A private preflight test alone misses the constructor's
connection replacement. Preserve original origin or avoid early retargeting;
do not introduce data fingerprints just to repair this lost-origin defect.

### P2/P12: persisted links and accepted/failed candidates

Use a linked data/model fixture and a persisted posterior with an explicit
NULL reference field. Reload it through the public getter, construct a bundle,
and exercise writing for accepted, failed, and unchecked candidates. Cover
matching and conflicting pre-existing reference links separately.

For the agreed accepted-NULL contract, either the narrow link update and
reference files are saved consistently, or rejection happens in preflight
with an actionable instruction. If the task requires this reuse workflow
to succeed, early rejection is only an interim guard, not feature completion.
Never overwrite the whole reused record simply to save one new link.

No failed candidate should create a link to nonexistent reference files or
replace a valid existing link. Successful writes preserve descriptions and
round-trip the actual reference values. Inject a write failure at the relevant
stage to verify the chosen recovery contract. The historical P12 probe threw
the stored-link error and wrote no archive; do not change its description
to a proven successful orphan write.

## Testing protocol and limits of evidence

Use the repository's existing `testthat`/fixture patterns. Set both `PDB_PATH`
and the R `pdb_path` option explicitly to disposable paths **before loading
code**, since the option can override the environment. Inspect setup files
and automatic `.Renviron`/dotenv behavior as applicable. Use `Rscript --vanilla`
for a controlled subprocess and scoped restoration/cleanup inside tests.

The `tests/testthat.R` entry point now copies a configured database to a
disposable tree, sets both path settings, and restores settings/removes the
copy after success or failure. With neither setting configured it still
clones upstream, so this entry point remains an integration harness with
network/backend requirements. Direct `test_file()`, `devtools` and coverage
runs can bypass this entry point; explicitly isolate their paths. Audit the
selected tests and helpers before execution, including working-directory
configuration files that can override the database settings.
Minimal fixtures suffice for fast tests; use a disposable copy/pinned corpus
only for the integration tests that require one. Do not change production
default paths just to protect the test run.

A focused local command can follow this pattern after inspecting the selected
test and replacing the filename with the real regression file:

```r
# Run with Rscript --vanilla from the implementation worktree.
fixture_root <- tempfile("posteriordb-tests-")
dir.create(fixture_root)
Sys.setenv(PDB_PATH = fixture_root)
options(pdb_path = fixture_root)
pkgload::load_all(".", helpers = FALSE, export_all = FALSE)
testthat::test_file(
  "tests/testthat/test-create-pdb-bundle.R",
  reporter = "summary", load_helpers = FALSE, stop_on_failure = TRUE
)
```

This command does not build a valid database by itself. The selected tests
must create their required fixtures; enable only inspected helpers when
needed. An error exit matters: a printed failure with a successful process
exit is not a passing check.

| Change | Evidence beyond a narrow unit test |
| --- | --- |
| S3/signatures/classes | Exported generic with named and positional arguments; intended subclasses; `tools::checkS3methods(dir = ".")`; install into a temporary library and dispatch in a clean process, including namespace-only loading. |
| Writers/cache/links/rollback | Read actual disk files and public getters; compare full draw values/order/metadata; failure injection with prior-state and backup-preservation assertions. |
| Diagnostic consolidation | Same deterministic draws/sampler inputs across import, bundle immediate/deferred, and checker paths; numerical outputs, applicability, thresholds, undefined values, and selective-computation sentinels. |
| Counts/extraction | Complement mocks with small real fits for simplex/correlation and transformed/generated quantities; verify unconstrained counts independently of saved shapes. |
| CmdStanR adapter/options/versions | A genuine supported CmdStanR/CSV-backed fixture where required, exact forwarded arguments, valid version metadata, and no accidental RStan requirement. An environment wearing a class name is only an interface mock. |
| Archived RStan recovery | Live-fit fast path does not compile; missing-resource recovery requires the explicit option, source agreement, parameter-only counts, and original archived draws/diagnostics. No fallback for valid-but-inconsistent counts. |
| Optional provenance | Defined normalization and unknown/verified states, mismatches before writing, round trips; structural dimension agreement is not historical identity evidence. |

Broaden checks once affected focused tests pass and when the changed behavior
justifies it. Run normal package checks only after protecting the legacy
harness. Distinguish baseline failures from regressions; do not suppress either
by weakening assertions. Record skipped backend/toolchain tests precisely
and run them in a suitable environment before claiming the corresponding
integration feature verified. Do not repeat expensive sampling to test
metadata plumbing that deterministic fixtures cover.

## Delegation messages and required worker reports

Give every worker the exact base/candidate, issue IDs, relevant document
sections, ownership, and contract. Do not assume a child sees the whole chat.
Use short bounded requests such as:

```text
Explorer: investigate P11 at <base SHA>, read the handoff P11 and commit review.
Trace exported constructor -> connection attachment -> reuse flags -> writer
preflight -> persisted reads. Return callers, existing helpers/tests, source
locations, and uncertainties. Read-only; do not implement or delegate.
```

```text
Implementer: own P11 only at <base SHA> in <worktree>. Read this orchestration
guide and handoff P11. You are the sole writer for <assigned files>. Preserve
original source identity, existing naming/overwrite policy, and valid reuse.
First add a public-call regression that fails for the documented reason;
then make the smallest shared repair. Do not add fingerprints or redesign
bundles. Return the exact diff, commands/results, compatibility impact, and
remaining concerns. Do not commit or edit outside ownership unless assigned.
```

```text
Reviewer: review P11 at <candidate SHA/frozen diff> against <base SHA>.
Read the contract and adjacent callers independently. Check public
constructor-to-writer tests, both overwrite settings, copied/reused objects,
destination state, and whether the source-origin test can still be fooled
by retargeting. Report concrete defects with evidence and severity; also
identify unnecessary complexity. Read-only; no blanket approval from tests.
```

Required report fields: issue and contract; base/candidate; changed files;
root cause and repair; failing-before/passing-after evidence; other exact
checks with outcomes; assumptions and unrun checks; public compatibility;
remaining questions. Separate observed behavior from inference.

In a shared checkout, ownership is procedural: all agents can see edits.
Pause overlapping workers and freeze the candidate before review/testing.
In separate worktrees, require a patch/commit tied to the base SHA and
integrate sequentially. Review and rerun relevant checks after resolving
conflicts. A review of the pre-conflict patch does not certify a new merge.
Only the coordinator integrates and commits unless explicitly delegated.

## Completion, escalation, and resuming after context loss

An issue is complete only when its agreed behavior is implemented, the
regression has relevant evidence, affected contracts remain intact, concrete
review defects are resolved, and its documentation/status is accurate.
Source inspection, a model's confidence, or several agents agreeing is not
equivalent to a passing behavioral check. Never mark all findings resolved
because one combined suite was green.

Escalate a task to Sol/Astra when the worker cannot explain the actual state
transition, numerical convention, schema, or compatibility consequence.
Send the concrete failing case and unresolved contract, not a request to
“make it better.” If a second attempt repeats the same misunderstanding,
stop speculative edits to that unit and obtain a stronger review or a
maintainer decision. Continue independent authorized work. Missing tools,
scope exclusions, and unresolved policy decisions remain explicit statuses.

Before compaction or handoff, record: implementation base, current branch and
candidate, completed issue/commit pairs, active worker/file ownership,
decisions, exact check results, unrun checks, and next unit. On resume, read
that state, inspect Git status, and reconcile with the actual files before
editing. Do not repeat completed changes or promote historical results to
evidence for new code.

For each delivered commit or PR, explain the concrete before/after behavior,
validation, compatibility, and remaining limits. Markdown changes must be
committed. Do not publish, merge, or deploy unless the current task authorizes
that action. No release/version bump is implied by implementing these fixes.

## Copy-and-paste kickoff prompt

```text
Implement the outstanding confirmed correctness and integrity defects in
the attached posteriordb-r review documents. Follow
docs/agentic-implementation-orchestration.md. Start from the authorized main
implementation branch (or its authorized newer replacement), not the older
Agent-ToDo documentation base. Revalidate findings against current code.

Use GPT-6.1 Sol/high as coordinator and implementer, GPT-6 Astra/high for
independent review of persistence/numerical changes, and GPT-6 Luna/medium
for bounded read-only exploration, if those models are available. Report
actual substitutions. You may delegate; use one code writer at a time,
explicit file ownership, and no unassigned recursive delegation.

Read AGENT_REVIEW_GUIDE.md, ponytail-commit-review.md, the audit/findings,
and test-suite review. Optional Stan workflow proposals are reference only
unless I explicitly include a feature in scope. Preserve fixed acceptance,
unconstrained-count semantics, provenance honesty, and compatibility.

Work in small verified units. Trace callers, reproduce the public failure,
fix the shared cause, verify disposable database/round-trip state, review
the frozen final patch, and commit each coherent fix and Markdown update.
Start with safe test isolation and P11; coordinate P2/P12 next. Credit fixes
already present in newer commits. Keep going through independent authorized
units; ask only about genuinely unresolved behavior choices or missing inputs.

Never run mutating tests against my working PosteriorDB checkout. Do not
claim integration verification from mocks, weaken checks to pass tests,
or implement a new policy/backend framework. Maintain issue/commit/evidence
status and report blocked, deferred, or unrun work explicitly. Do not merge
or publish changes unless separately authorized.
```
