# Agent handoff: review and consolidate posteriordb-r

This is a concrete investigation and implementation brief, not an instruction
to implement every suggestion. The maintainer and implementing agent will
choose scope and priority. Keep confirmed behavior defects separate from
refactoring opportunities and policy decisions.

Reviewed snapshot: `55e667e2b11267a5ab9db76e5a15c15ea82c6376`, on 2026-10-01.
Other-machine changes were unavailable. Recheck every finding against the
actual branch before changing it. Some findings predate the recent additions;
do not attribute all problems to those additions or to AI generation.

The [commit-by-commit review](ponytail-commit-review.md) traces the 74 commits
from `8aeef19` to this snapshot, distinguishes later repairs from outstanding
issues, and adds the reproduced bundle-reuse defects P11/P12 below. The
documentation branch `Agent-ToDo` itself is based on `8aeef19`; these findings
describe the reviewed feature snapshot, not implementation present on that
documentation branch.

## Active backlog maintenance — 2026-10-02

Completed implementation findings are removed from this active backlog.
Their commit/test evidence is in [the implementation checkpoint](conversation-handoff.md#implementation-checkpoint--2026-10-02); original findings remain in Git history.
Partial findings below retain only the remaining work as it is revalidated.
Implementation resumed at the maintainer's request. Read the
[resume checkpoint](conversation-handoff.md#resume-checkpoint--current-2026-10-02)
for the last completed unit, workflow, and suggested next step.

**8 of the original 33 finding IDs remain open, partial, or deferred; 25
are fully verified.** These IDs differ in size, and some are policy/design
questions rather than confirmed bugs requiring code. This document is the
active queue; dated audit/review reports are historical inputs.

| Remaining area | IDs | Current boundary |
| --- | --- | --- |
| Conversion/API contracts | S5 | Constructor fixed, setter deferred. S4 conversion documentation is verified. |
| Diagnostics, extraction and counts | D6 | Revalidate current source; preserve numerical/provenance contracts. D1–D5 diagnostics/extraction/schema coverage and D7 versions are verified. |
| Persistence and writing | P3, P4, P8 | P3 cache policy deferred; P4 reporting/operation-result audit fixed, future rollback open; P8 reads/removal fixed, non-Stan writing deferred and custom-path writer contract open. |
| Remaining validation | V4, V6 | Batch forms and smaller API/validation questions. V5 translation is verified; V4 is deferred by the maintainer. |
| Dependencies and documentation | T3 | T1 isolation and T2 complementary public/backend/installed coverage are verified; dependency guards and broader docs remain. |

Keep P3, the S5 setter, non-Stan writing, and V4 batch classification deferred until the maintainer
explicitly resumes those choices. Do not reopen completed fixes to fill an
old review checklist.

## Your task

Review the package for inconsistent public behavior, S3 contract violations,
duplicated implementation, and tests coupled to a particular database. Make
small, reviewable changes in the scope agreed with the maintainer. Explain the
before/after behavior of each change and preserve useful existing behavior.

For each candidate, provide:

- A public-call reproduction or a precise source-level explanation.
- Whether it is reproduced, source-confirmed, a design choice, or still only
  an investigation candidate.
- The affected workflows and compatibility implications.
- The smallest useful fix or consolidation, plus meaningful verification.
- A reason for deferring it if it is outside the selected scope.

Do not turn all helpers into S3 generics. Dispatch is useful where object
types require different behavior; ordinary functions are appropriate for
shared calculations and orchestration. Do not merge functions simply because
their names or bodies look similar: identify the behavior contract first.

Do not run the existing full test suite against a maintainer's working
PosteriorDB checkout. Several tests write, overwrite, or delete database
files. Use disposable fixtures or a disposable database copy instead.

## Behavior to preserve unless a policy change is agreed

- `posterior$dimensions` contains scalar unconstrained parameter counts,
  not output shapes. The sum describes the represented parameter dimension.
- Saved constrained scalar names and shapes are a separate concept. A
  `simplex[K]` has K constrained elements and K - 1 free coordinates.
- Reference acceptance currently requires exactly 10,000 retained draws;
  summary-statistic acceptance permits at least 10,000.
- Current Stan gates require at least four chains, mean absolute lag-1
  autocorrelation across chains at most 0.05 per variable, R-hat at most
  1.01, E-FMI at least 0.2 per chain, and no divergent transitions.
- ESS and treedepth are informational, not acceptance gates.
- Selective diagnostics should calculate and extract only what was requested.
  A lag-only request must not require energy or divergence diagnostics.
- `check = FALSE` bundle creation avoids diagnostic calculation and retains
  the inputs needed for a later check. Structural validation still applies.
- Bundle construction is in memory; persistence is explicit. Failed
  diagnostic candidates can still be inspected.
- The current bundle constructor supports RStan. The existing-posterior
  importer supports RStan and CmdStanR. Do not expand backend support merely
  as a side effect of a refactor.
- Database JSON layouts, optional null fields, descriptive metadata,
  provenance, and compatibility aliases need intentional treatment.

The local database documentation also contains potentially stale wording,
including an E-FMI direction inconsistent with the implemented policy. Do
not silently change numerical policy to match a sentence in a document.

## S3 dispatch and object contracts

### S5. Framework replacement setter — deferred

Location: `R/model_code.R`, the `framework<-` replacement accessor.

Constructor slice verified at `d01d58b`: requested framework retained,
omitted framework preserves Stan, and matching metadata is required.
The stanmodel-specific coercion retains its fixed Stan choice.

Remaining, deferred by maintainer on 2026-10-02: the replacement accessor
changes the framework label on existing code without translating it or
updating metadata. Preserve the existing setter for now. Future discussion
can decide whether to require matching implementation metadata or a new
object when changing frameworks.

## Diagnostics, fit extraction, and acceptance

### D6. Fit identity verification has a documented limit — policy decision

Location: existing-posterior import workflow; bundle source/data reuse.

The existing-posterior importer verifies selected base names and free counts,
but not exact source/data identity. Two different fits can share those names
and counts. The bundle guide already documents this limitation; do not report
it as an undisclosed feature bug.

Decide whether stronger verification is wanted and which evidence each fit
actually preserves. Keep unavailable evidence explicit. Caller-supplied data
must not be described as fit-recovered data. Preserve the existing explicit
source comparison for reused model objects. Do not resample a fit to establish
identity. Restrict compilation fallback for stale RStan instances to the
specific missing-instance case where possible, rather than hiding unrelated
errors behind an expensive fallback.

## Persistence, transformations, names, and cache

### P3. Ordinary writes/removals leave stale cache entries — deferred by maintainer

Deferred on 2026-10-02. Current-source investigation found longstanding manual
refresh semantics. Preserve current behavior; decide the cache contract before
implementing automatic invalidation. The original proposed repair follows.

Locations: `R/write_pdb.R`, `R/remove_pdb.R`, `R/pdb.R`, `R/tibble.R`.

In a temporary database: write data info with title "Before", read it to
cache it, overwrite with title "After", then read again. The getter returns
"Before". Transactional imports and bibliography updates invalidate cache;
ordinary component writers do not consistently do so.

Share narrow cache invalidation after successful mutations. Ensure failed
writes do not invalidate or replace valid cached content prematurely.
Test read-overwrite-read and read-remove-read for each public component.
Also test directory-derived tables after removal: `pdb_tibble()` reads all
cached filenames, whereas search filters cached posterior filenames against
current source names. Cached deleted entries should not remain in results.
Preserve endpoint-isolated default caches; explicit shared-cache semantics
and differing GitHub hosts with identical repository specs need review.

### P4. Preflight is not a transaction; rollback handling needs an audit

Locations: bundle writer, component writers, `write_to_path()`,
`write_imported_reference_posterior_draws()`, `rename_pdb_commit()`, and
`append_bibliography_atomically()`.

Bundle preflight prevents predictable collisions, but writes sequentially.
A later I/O or serialization failure can leave earlier components installed.
Individual data/model/reference writers likewise write metadata before the
payload. The fit importer already stages and verifies a multi-file write.

Maintainer decision, 2026-10-02: preserve partial writes after an I/O failure
and report the components that succeeded. Document this in the contribution
workflow: inspect the resulting files before retrying, and review them in the
contribution pull request. Diagnostic rejection keeps its distinct documented
partial-success behavior. Automatic rollback for bundle/component writes
remains open for discussion with colleagues; this decision does not close P4.
Changing the policy later requires staging/restoration and failure tests,
but no transaction framework is needed for the current reporting contract.

Current reporting contract implemented at `ed51544`: shared writes identify
the failed destination, bundle failures list completed components, and ZIP
creation/JSON-cleanup results are checked without deleting recoverable JSON
on failure. Contribution/bundle guides explain inspection, retry, cache
refresh, and pull-request review. This closes the reporting slice, not the
future rollback policy or the remaining operation-result audit below.

Rename/bibliography rollback backup preservation and shared ZIP extraction failure handling are verified; see the handoff for commits and checks. The remaining scope is the deferred automatic rollback policy for sequential
bundle/component writes; reporting and the scoped result audit are verified.

Scoped operation-result audit implemented at `b74d113`: rename staging checks
ZIP status, expected member and payload checksum before moving originals;
failed plain cache copies remove partial cache files and report the destination;
failed payload removal stops before deleting metadata. Import rollback completes
all recovery attempts before warning, reporting retained backups and installed
files even with `options(warn = 2)`. No arbitrary-path removal or manual-cache
policy changed. P4 remains open solely for future bundle/component rollback
discussion; do not rerun the completed audit as an unfinished unit.

### P8. Model writing support and custom paths — partial

Locations: model writers and `write_to_path()`.

Maintainer decision, 2026-10-02: defer non-Stan writing. Framework/custom-path
reads and removal are verified at `bca0fd3`; see the handoff for evidence.

Audit writer support separately: declaring a
framework supported does not mean `write_to_path()` implements it. Clearly
support or reject each operation instead of failing after metadata is saved.
Custom-path writing also remains open. Current writers use conventional Stan
destinations; the bundle guide documents this limit. Resume with a deliberate
writer contract and tests before changing support or pre-write rejection.

## Validation and workflow behavior

### V4. Batch sampling-list classification — deferred by maintainer

Location: `normalize_sequential_sampling_lists()`.

Maintainer decision, 2026-10-02: defer changing classification or rejecting
ambiguous forms. Preserve current behavior and give users clear usage examples.
When revisiting the choice, explain the concrete input and its consequence
alongside the issue ID. The ambiguity and proposed coverage below remain open.

For workflow names `a` and `b`, supplying
`list(wrong = list(iter = 20))` is treated as a common sampler argument named
`wrong`, rather than a mismatched per-workflow map. Detection depends on a
hard-coded sampler-argument list, complicating future backend options.

Specify the accepted forms and resolve structural ambiguity intentionally.
Reject clearly malformed workflow maps early with actionable errors. Do not
reject legitimate nested common arguments such as `control` or list-based
initialization. Test named/unnamed single and multiple configurations,
workflow-name collisions with sampler-option names, and mixed/unknown keys.
Add direct tests for continue/stop semantics and per-stage result reporting.

### V6. Other small validation/API inconsistencies to investigate

- `pdb_config()` uses `eval(parse())` to select a constructor from YAML.
  A validated explicit lookup of supported types is simpler and gives clearer
  errors. `pdb_default()` currently swallows configuration errors and can
  silently fall back to another database; decide which errors justify fallback.
- Some public methods accept `...` and ignore unsupported or misspelled
  arguments. Establish where forwarding is intentional and where rejection
  helps; do not blanket-reject legitimate downstream arguments.
- `reference_posterior_summary_statistics()` catches every read error and
  treats it as absence. Distinguish missing optional summaries from corrupt
  metadata, malformed payloads, or transport failure.
- `remove_pdb.character()` deletes the literal path supplied even if outside
  the connection's endpoint. Clarify whether it is a public arbitrary-path
  API or an internal worker; do not change its semantics without review.
- Validators frequently check class and a few fields but not full payload
  alignment. Review empty draws, nonfinite draws, unequal chain lengths,
  duplicate variable names, diagnostic name/length mismatches, dates, and
  serialized attributes using realistic malformed fixtures.
- `summary.pdb_reference_posterior_draws()` prints a summary rather than
  returning a useful structured summary object. Review the intended public
  contract rather than treating printing as automatically an S3 violation.
- `pdb_endpoint.pdb_local()` returns a path when an endpoint is already set,
  but a modified connection object when resolving an unset endpoint. Several
  callers rely on one of those forms. Clarify the contract and, if useful,
  separate endpoint resolution from endpoint access; test both initialized
  and uninitialized connection states before changing callers.

## Tests, dependencies, and documentation

### T3. Dependency contracts and public docs need consolidation

Location: `DESCRIPTION`, `README.Rmd`, contribution vignettes, generated man
pages, and the bundle guide Rmd source.

Core user-facing functions call several packages in Suggests, including
`dplyr`, `remotes`, `httr`, and `yaml`, without consistently guarding access.
Either require these for the relevant supported core workflow or provide a
clear optional-dependency error at its boundary. Test no-RStan CmdStanR
workflows and no-Stan database access. Keep the Imports/Suggests decision
proportional to actual functionality.

The README still primarily describes the original database-access package,
while the bundle guide documents substantial new workflows. Explain the
workflow choices and constructor/coercion distinctions in a single obvious
entry point, with detailed guides linked from it. Correct misleading defaults,
list-construction examples, dimension terminology, and return-value docs.
Update roxygen/Rmd sources and regenerate derived files rather than editing
generated files independently. Release version/date/changelog changes are
a maintainer decision, not an automatic consequence of this review.

## Suggested implementation shape

This is a dependency structure, not a required file hierarchy or priority list:

1. Backend S3 methods extract a normalized fit record.
2. Shared ordinary functions select variables and calculate requested metrics.
3. One policy evaluator produces applicable check results and failure reasons.
4. Thin adapters create the existing report objects and stored metadata/flags.
5. Object constructors preserve class contracts and honest provenance.
6. Persistence consumes validated objects, resolves shared paths, commits files
   according to its documented failure contract, and invalidates affected cache.

Keep database-specific integrity checks distinct from mathematical checks on
draws. Add or extract a helper only when multiple consumers share the same
contract. Separate bug fixes from large mechanical moves where useful for
review. Existing public functions can remain as compatibility adapters.

## Verification and final handoff

Initial review ran ten focused test files with 264 passing assertions and one
skip, plus source inspection and temporary-fixture probes of the behaviors
marked reproduced. It did not establish a full package check, live GitHub
compatibility, or correctness of every real Stan backend/type. The package
installed successfully into a temporary library.

After implementing agreed changes:

- Run the relevant fast fixture/public-contract tests and S3 consistency check.
- Run the specific real-backend/integration checks needed by the changed code.
- Run an installed-package check using a disposable test database after making
  sure legacy tests cannot mutate the maintainer's checkout.
- Verify that serialization matches the supported database schema and that
  no changes weaken draw acceptance or replace honest provenance with defaults.
- Report changed public behavior, compatibility decisions, test evidence,
  limitations, and deferred findings. Do not describe this checklist as an
  exhaustive proof that no other defects exist.
