# Focused cleanup: implemented changes and remaining work

Updated 2026-10-02. Implementation branch: `main`.

This report explains the cleanup through implementation commit `472f867`
and continuation checkpoint `811b425`, including the small fixes made before
the orchestration loop started and the bounded follow-up audit below. It
describes what each change solves;
[conversation-handoff.md](conversation-handoff.md) holds the detailed
commit/test ledger and [AGENT_REVIEW_GUIDE.md](AGENT_REVIEW_GUIDE.md) is the
authoritative remaining queue. Earlier audit reports describe older snapshots.

**15 of the original 33 finding IDs are closed. Eighteen remain open,
partially implemented, or deferred.** An issue ID can contain several work
units, so this is a count of tracked findings, not a percentage of engineering
effort completed. Partial work is credited below without closing its whole ID.

## What was changed and why

### Persisted links and reused objects — P2, P11, P12

Previously, a bundle could attach its destination connection to reused data
before checking where that data came from. Same-named records in another
database could then be mistaken for the intended source. A candidate could
also give a posterior an in-memory reference link that was never saved, or
leave a saved link pointing to reference draws that had been rejected.

The repair preserves reused objects' origins until collision checks and
guards the link that is actually persisted. An accepted bundle reusing a
posterior must already have a matching saved reference link; assigning one
only in memory is insufficient. The existing importer remains the supported
route for installing accepted reference draws and updating an empty saved
link. Failed candidates remain inspectable without creating a dangling link.
This preserves the documented ability to write eligible ordinary components
after diagnostic rejection. Commit: `56cb0dd`; isolated integrity checks
included saved JSON, cross-database collisions and namespace-only loading.

### Recovery when file replacement fails — P4, partial

Rename and bibliography rollback previously ignored whether restoration
worked, then could delete the directory holding the only original backup.
The repair checks restoration outcomes and retains recoverable backups when
restoration also fails. Error/warning messages identify the retained path.
Successful restoration still cleans up normally. Commit: `ebb5d9e`.

This improves the existing recovery operations; it does not make every
component or bundle write transactional. The remaining P4 policy and audit
work are described below.

### Write identifiers, containment and archives — P9

Resource names were interpolated into filenames without a common boundary.
Archive extraction and cached paths also needed to agree about what an
acceptable reference payload looked like. These weaknesses could make
preflight inspect a different destination from the actual writer or leave
partial extracted content available to a later read.

Shared validation now checks resource names and local destination containment,
including existing symlink ancestors. Archive reads require one safe root
JSON member with the expected filename; traversal, drive paths and mismatched
members are rejected. Extraction warnings/errors remove incomplete output
instead of allowing it to masquerade as a good cache entry. Rename/link
operations reuse these boundaries. Commits: `587bb86`, `8e5de0c`, `fe74ebc`.
Archive33, resource170, rename58 and integrity40 installed assertions passed
at the documented candidates; independent review added damaged-ZIP coverage.

### Positional bundle arguments — S1

The generic and Stan-fit method placed common arguments differently. A call
supplying `added_by` positionally could instead bind it to `model_code` and
attempt to open a file named after the contributor.

The common argument order was aligned, with method-specific options kept
afterward. Named usage remains available; no new argument-normalization
layer was introduced. Commit: `688c7d8`. Focused installed calls and the S3
signature checker passed.

### Database status after bibliography failure — V1

The database checker did not capture its final bibliography checker result.
It could therefore return success based on the preceding check even when
bibliography validation failed.

The result is now assigned before interpreting it. The integer contract is
documented: `0L` for success and `1L` for failure, returned invisibly. This
needed one result assignment, not a general check runner. Commit: `b9515c1`;
status8 and bibliography48 installed assertions passed.

### Draw connections survive conversion — S3

The shared draws-list coercion accepted a connection but dropped it.
Converted or thinned draws could then lose the ability to resolve their
database even though the caller had supplied one.

The constructor now validates and attaches that explicit connection;
thinning forwards it. A detached `NULL` connection remains supported, and
connection attributes do not become part of the JSON payload. The fix lives
at the shared constructor rather than in each importer. Commit: `a5ef7c9`;
connection16, integrity40 and real-RStan import50 installed assertions passed
for that candidate, with independent source review.

### Changed draws cannot reuse old acceptance — P1

A checked 10,000-draw object could be thinned to 5,000 while retaining metadata
claiming 10,000 and successful checks. Variable selection could likewise
leave diagnostics aligned to an obsolete variable order.

Transformations now update retained counts, align variable diagnostics, and
clear obsolete acceptance flags and reports. Retained sampler diagnostics
are thinned in lockstep; E-FMI must be recalculated. Write/check boundaries
compare metadata counts with actual retained draws, so forged old flags do
not bypass the count requirement. Fixed positive integer thinning is
supported; a period of one preserves the unchanged object. Commit: `5f93031`;
transformation28 passed development, installed and independent review checks.
The acceptance thresholds themselves were preserved.

### Subclasses and S3 delegation — S2

Several helpers assumed the package class was the first class. Prepending
`custom_connection` could change the detected database type, metadata
subclasses could fail writing, and thinning could discard a subclass.

Type/serialization checks now recognize the existing supported classes
through the class chain. Draw transformations restore the original chain
and delegate past classes already visited. Independent review caught a
subclass method running twice, which thinned values differently from their
sampler diagnostics; that counterexample was repaired and retained as a
regression. External `posterior::thin_draws()` registration also works with
namespace-only loading. Commits: `5f93031`, `e6b2b89`; subclass27,
transformation28 and connection16 passed installed and independent checks.
Concrete internal backend/name-method bypasses were audited and retained.

### Disposable legacy package tests — T1, partial

Older package tests could overwrite/delete fixed names in the database
selected by a maintainer's option or environment variable. A failure could
leave that working database changed.

The package test entry point now stages a disposable copy of a configured
corpus, or a fresh clone, scopes both path settings, and restores settings
and removes staging on success or failure. It rejects overlapping staging
locations and checks copy results. Commit: `31ca4e9`; harness37 passed
development, installed and independent checks.

This protection applies to the entry point. Direct test/coverage runs can
bypass it, YAML configuration can override paths, and offline/integration
separation remains open. The broad suite has not been declared safe or run
against the maintainer's database.

### Reference-name listings use the selected summary type — P7

Local summary listings used the wrong directories, and GitHub listing did
not consistently consume the requested type. Asking for summary names could
fail or inspect the draw-info location instead.

A small existing-type path mapping is now shared by listing, reading,
writing and removal. GitHub consumes the type argument. Commit: `2a71a30`;
reference24 originally passed development, installed and independent checks,
including mocked GitHub paths. Subsequent file-listing coverage expanded that
test to 27 assertions. Live GitHub was not tested.

### Dotted names and directory listings — P6

Extension stripping could turn `model.v2.info.json` into `model` rather than
`model.v2`. Listing could also include suffix-like directories or return
the wrong empty-vector representation.

The code now uses standard-library extension helpers where appropriate and
removes exact per-resource suffixes. Local and GitHub resource listings select
files, preserve dots in names, and return `character()` when empty. Cache
metadata listing follows the same suffix rules. Commit: `182615b`;
listing24/reference27 passed installed and independent checks. Search and
affected persistence checks also passed at that candidate.

### Posterior lookup follows explicit metadata — P5

Lookup tried to infer data/model links from hyphenated posterior filenames;
model-info lookup could return unrelated posteriors. This failed when names
contained hyphens or when a posterior filename did not encode its links.

Data, model-code and model-info lookup now share filtering of stored
`data_name` or `model_name` fields. A named scalar resource name is normalized
without changing its value. A connection is still required for this database
lookup. Commit: `4a8b7e4`; lookup9 passed development, installed and independent
checks, including the named-scalar regression found during review.

### Summary payload and metadata use one reference identity — P10

A posterior's own name and its `reference_posterior_name` can differ. Summary
reading used the reference name for the payload but could resolve its
metadata as though that name were another posterior.

The summary reader now uses the existing direct reference-info reader with
the same identity and type used for the payload. Both summary types and
object/name/info/multiple-summary entry points are covered. Commit: `857a044`;
identity11 passed installed and independent checks.

### Framework-aware construction and model paths — S5/P8, partial

The character model-code constructor ignored its framework argument. Reading
had incomplete extension logic, and removing PyMC code could target `.pymc`
instead of `.py`. Custom implementation paths were not consistently used.

Construction now preserves any of the five declared frameworks, keeps the
existing Stan default, and requires matching implementation metadata. Reads,
file-path getters and removal share declared paths, with conventional
extension fallback where legacy metadata has no path. Supplied posterior
metadata remains authoritative for implementations it contains; another
framework can still be resolved from its attached database. Commits:
`d01d58b`, `bca0fd3`; framework19 and model-path97 passed installed and
independent checks, with a real-RStan import50 check for the path candidate.

The framework replacement setter and non-Stan writing remain deferred.
Custom-path writing remains open. Existing writer behavior was documented,
not silently expanded or changed to a new rejection policy.

### Partial I/O writes are reported — P4, partial

Sequential bundle/component writes can fail after earlier files were saved.
ZIP creation or JSON cleanup could also fail without clearly identifying
which output remained available.

The maintainer chose to retain partial writes for inspection. Failed shared
writes identify the destination; bundle errors report completed components
and explain that the failing group may itself be partial. ZIP status/output
and JSON cleanup results are checked, retaining recoverable files on failure.
The original error still propagates. Commit: `ed51544`; integrity57 passed
installed and independent checks, including injected model/ZIP/cleanup failures.

The contribution vignette and bundle guide explain inspecting tracked and
untracked files, fixing the I/O cause, retrying with reviewed overwrite/reuse
choices, refreshing cache, and reviewing the files in the contribution pull
request. Earlier vignette edits were preserved in `d83998e`. Future automatic
rollback remains an explicit discussion item; this slice does not close P4.

### Summary validation uses named, aligned fields — V3

Validation rejected valid reordered JSON because it treated the first field
as variable names. It also accepted two names with one value or a differently
sized MCSE vector.

Required fields are now validated by name. Variable labels must be unique
and nonmissing; values and MCSE must each have one entry per label. Attached
metadata is validated, and reference-info field order is no longer semantic.
The same required metadata keys remain required. Numeric `NA`/infinite-value
permissiveness and extra numeric-field length behavior were preserved and
documented. Commit: `10cf216`; validation39 passed installed and independent
checks, including reordered JSON round trips and rejection before mutation.

### Posterior checking inspects the supplied object — V2

The checker reloaded a posterior by name and discarded unsaved edits.
Standalone objects failed because they had no database to reload from.
Shared read-check helpers also assumed getter results were cached objects.

The checker now validates the supplied posterior and its getter-visible
model, data and reference content/metadata. Detached results have no cache
to evict. No bibliography is needed without citations; supplied posterior,
model or data citations require an attached database and are checked there.
`check_pdb()` still loads saved objects before database-wide checks.
Independent review found missing embedded-reference metadata validation and
an unchecked model getter result; both received existing-validator assertions
and regressions. Commit: `472f867`; standalone36 passed installed and
independent checks. Final installed status8, model-path97, bibliography48 and
integrity57 also passed. Stan execution enabled within this checker was not
run for this unit.

### Smaller deletions and documentation upkeep

The earlier `56cb0dd` cleanup removed unused helpers, the never-working
fit-data recovery seam, redundant internal NULL-policy forwarding, unused
metadata-validation flexibility and the unused `digest` dependency. The
public fixed `policy = NULL` compatibility was retained; no configurable
acceptance or provenance framework was added.

Changed API documentation was edited in roxygen/Rmd sources and regenerated.
The bundle guide and contribution guide explain current persistence,
acceptance, path and retry behavior. Implementation/status commits are
separate, and relevant existing dirty files were preserved before editing.
The continuation guides now direct agents to the active queue rather than
restarting already-completed P11/P2/P12 work.

## What remains

| Area | IDs | Remaining work |
| --- | --- | --- |
| Public API | S4, S5 | Explain wrapping versus fit import and construction APIs; the framework setter is deferred. |
| Diagnostics and fits | D1–D7 | Shared compatible calculations/acceptance, analytical applicability, extraction routing, constrained counts/selection coverage, identity policy and version metadata. |
| Persistence | P3, P4, P8 | Cache policy deferred; remaining I/O-result audit and future rollback discussion; non-Stan writing deferred and custom-path writer contract open. |
| Validation | V4–V6 | Batch-list ambiguity, silently dropped CmdStanR settings, configuration/optional-resource/API and payload validation questions. |
| Tests and docs | T1–T3 | YAML/direct-run isolation, offline/integration separation, complementary real backend/constrained coverage, dependencies and broader public docs. |

The next suggested small unit is **D7 version metadata agreement**, followed
by **V5 CmdStanR settings translation**. Read-only inventories exist for both;
they still need a fresh reproduction, implementation, tests and final review.

The maintainer explicitly deferred P3 cache behavior, S5 framework relabelling
and non-Stan writing. P4 currently retains and reports partial writes; future
automatic rollback remains open for colleague discussion. Later decisions
also include E-FMI normalization, partial parameter-selection semantics,
stronger fit identity verification and the V6 API/fallback questions. These
must not be silently decided during mechanical cleanup.

## Verification and agent workflow

The coordinator was the sole writer. Luna/medium supplied bounded read-only
inventories; a separate Sol 6.1/high reviewed frozen patches and sought
counterexamples. Review findings were reproduced, repaired and re-reviewed.
Both agents finished without edits or commits owed. The current workflow and
restart instructions are in the [resume checkpoint](conversation-handoff.md#resume-checkpoint--paused-2026-10-02).

Checks use disposable fixtures and temporary installed libraries. Test counts
above belong to their named candidates; they are not summed into a full-suite
claim. Live GitHub, Windows runtime, a genuinely RStan-free CmdStanR
environment, complementary real constrained/backend checks and the broad
package check remain unverified. Unrelated pre-existing dirty/untracked files
were left alone.

## Follow-up Ponytail audit

The detailed report was committed first at `c83343b`. A fresh Luna/medium
agent then applied the Ponytail audit skill read-only to the current source,
using the graph to narrow scope and source to verify findings. It identified
three remaining duplication candidates; no dependencies or speculative
abstractions were proposed. The coordinator made the following bounded changes.

### Remove repeated dimension validation

`extract_rstan_fit_for_bundle()` validated selected declared axes before
checking saved variables, then repeated its numeric, finite, nonnegative and
whole-number checks while building output shapes. The earlier validation
already rejects those invalid declarations with the applicable variable names.
The later duplicate block is removed. Integer conversion, the guard on the
converted dimensions, zero-sized declaration rejection and complete saved
scalar coverage checks remain. This removes four production lines without
changing variable selection, unconstrained counts or diagnostic acceptance.
The existing extraction regressions cover valid shapes, fractional/zero-sized
declarations and incomplete saved variables.

### Reuse the model-info rename implementation

Model-info and model-code rename methods previously maintained the same loop
over every implementation metadata field. The model-code method now calls
the existing concrete model-info method and attaches its result to the code.
That method still performs the filesystem migration once and updates matching
implementation paths. No new helper or dispatch contract was introduced.
Code text, framework, connection, unrelated implementation fields and explicit
NULL implementations are preserved. The filesystem action-planning loop is
kept because it also records file moves. This removes twelve production lines.

The new public regression also exposed an existing recursive default:
`pdb = pdb(x)` could evaluate its own argument promise instead of the getter.
The defect was reproduced against the original HEAD implementations for data,
model-code and posterior renames. All three now use the qualified existing
getter, `posteriordb::pdb(x)`, so attached objects can be renamed without
passing their connection again. Tests exercise all three object paths, saved
files and downstream posterior links. Generated rename help was updated.

### Leave the GitHub download candidate open

The audit proposed replacing the copy method's duplicated GET branch with
`github_download()`. Source inspection showed that this helper returns
success for an existing destination when overwrite is false; the copy method
currently attempts the download and its disk writer rejects that situation.
The shared copy generic validates output paths, but direct method calls and
races need consideration before declaring the substitution equivalent.
This optional simplification remains open. It is not a reproduced transport
bug, and it does not change the deferred manual cache policy (P3).

### Verification and commits for this pass

The touched source, test and generated-help files were clean before editing;
no pre-edit preservation commit was needed. Both original focused suites
passed before simplification (extraction36/rename58). Final extraction36 and
rename69 passed in development and a newly installed, namespace-only package.
The added regressions reuse disposable database fixtures; no live GitHub or
user database was involved. `git diff --check` passed. The production change
is a net deletion of sixteen lines, with no dependency added. This pass does
not close another backlog ID: the remaining count stays eighteen.

Independent Sol 6.1/high review approved the frozen production patch and
independently passed extraction36/rename69. Its sole fixture suggestion was
to use the supported `stan_version` field; that change was applied, approved
and verified again in development and the installed package. The audit,
inventory and review agents all finished read-only with no edits or commits
owed. The post-edit implementation commit is **`5b88e7d`**. This report and
the linked handoff are committed in a separate final documentation checkpoint.
Unrelated pre-existing working-tree changes remain untouched.
