# Focused cleanup: implemented changes and remaining work

Updated 2026-10-02. Implementation branch: `main`.

The initial sections explain cleanup through `472f867` and checkpoint
`811b425`. The resumed sections below record subsequent verified units through
`888b098`, including the interrupted dependency/documentation cleanup. It
describes what each change solves;
[conversation-handoff.md](conversation-handoff.md) holds the detailed
commit/test ledger and [AGENT_REVIEW_GUIDE.md](AGENT_REVIEW_GUIDE.md) is the
authoritative remaining queue. Earlier audit reports describe older snapshots.

**26 of the original 33 finding IDs are closed. Seven remain open,
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

### Initial legacy test protection — T1, superseded by `1e80aea`

Older package tests could overwrite/delete fixed names in the database
selected by a maintainer's option or environment variable. A failure could
leave that working database changed.

The package test entry point now stages a disposable copy of a configured
corpus, or a fresh clone, scopes both path settings, and restores settings
and removes staging on success or failure. It rejects overlapping staging
locations and checks copy results. Commit: `31ca4e9`; harness37 passed
development, installed and independent checks.

At that initial checkpoint, direct test/coverage runs could bypass isolation.
The later `1e80aea` unit below fixes that gap and separates offline/integration
tests; it supersedes this initial limitation. The broad suite has not been declared safe or run
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
| Public API | S5 | Framework setter remains deferred; construction and conversion documentation is verified. |
| Diagnostics and fits | D6 | Identity policy and compilation-fallback audit. |
| Persistence | P3, P4, P8 | Cache policy deferred; scoped I/O-result audit complete; future rollback discussion open; non-Stan writing deferred and custom-path writer contract open. |
| Validation | V4, V6 | Batch-list ambiguity, configuration/optional-resource/API and payload validation questions. |

Next priorities are optional-summary read errors (V6) and narrow stale-fit
compilation fallback (D6). T3 and V4 usage documentation are verified. D1–D5, D7, V5 and S4 are verified; V4
classification remains deferred. The handoff records current evidence and
commit boundaries for interruption/restart.

### Resumed work: version metadata — D7

CmdStanR internal-sampling metadata lacked the R session and Makevars required
by its own validator. Importing also started with a helper that could add
RStan metadata to a CmdStanR result. The fix reuses the existing R-environment
helper with RStan probing disabled for fit metadata, and shares the same
constructor between internal sampling and import. Available backend fields
are preserved. Documentation separates installed interface/environment
versions from CmdStan CSV evidence and avoids claims of historical provenance.

Commit `e3e59e6` passed versions11/extraction36 in development and installed
namespace-only checks, plus independent review. A genuine CmdStan CSV check
passed both normally and in a clean subprocess with RStan actually unavailable
through normal library lookup. This closes D7; it does not add a provenance
framework, change acceptance or expand bundle backend support.

### Resumed work: sampler argument translation — V5

Unsupported RStan controls were discarded and aliases could silently replace
explicit CmdStanR settings. Supported controls are now translated, unsupported
ones rejected, and native legacy aliases normalized with conflict checks.
Exact name lookup also prevents native iteration arguments from matching the
shorter `iter` name. NULL RStan-only options are omitted; native NULL settings
remain valid. The legacy `validate_csv` flag cannot override diagnostics.

Commit `3d519bb` passed arguments55/versions11 in development and installed
namespace-only checks, plus independent review. Review found and verified
repairs for two additional boundary cases. Genuine CmdStan CSV output confirmed
the translated step size and disabled adaptation for both chains. Source help
and the bundle guide document translations and conflicts. This closes V5
without adding an option registry or changing any sampling acceptance rule.

### Resumed work: conversion API documentation — S4

The help incorrectly suggested using `posterior()` for list construction
and misstated component fields. It now points to `as.posterior()` and names
`pdb_model_code`, `pdb_data`, and `dimensions` correctly. Help and the guide
also distinguish dotted draw wrapping (supplied metadata, no calculated
acceptance) from underscore fit import (counts and reference checks), with
correct return types and unchanged compatibility aliases. Backend-named
wrappers dispatch on the actual fit class; no new enforcement was added.

Commit `a5880da` is documentation-only. Public construction and alias probes,
existing connections16/standalone36 checks in development and installed usage,
and independent documentation review passed. This closes S4. V4's batch-list
classification was separately deferred at the maintainer's request.

The maintainer explicitly deferred P3 cache behavior, S5 framework relabelling,
non-Stan writing and V4 batch-list classification. P4 currently retains and reports partial writes; future
automatic rollback remains open for colleague discussion. Later decisions
also include E-FMI normalization, partial parameter-selection semantics,
stronger fit identity verification and the V6 API/fallback questions. These
must not be silently decided during mechanical cleanup.

### Resumed work: analytical acceptance — D3

Analytical draws could not pass the final checker because it demanded Stan
chain, lag, R-hat, E-FMI and divergence flags that analytical checking correctly
never generated. Required flags now depend on inference method and gate,
using one small helper shared with summary metadata transfer. No fake HMC
success flags are added. Reference draws still need exactly 10,000 actual
draws, summaries at least 10,000, and recorded counts must agree.

The public analytical writer now saves the draw archive and both summaries;
the metadata schema already supported analytical draws and needed no change.
The guide explains this ordinary-draw route without extending Stan bundles.
Initial regressions reproduced the defect. Analytical33 and five affected
suites passed in development and an installed namespace-only package;
independent review approved. Explicit cache refresh after a summary overwrite
respects the deferred cache policy. Commit: `9eaf04f`.

### Resumed work: shared acceptance and diagnostic identities — D2

Previously, acceptable numbers with unrelated variable or chain labels could
pass, and reports/stored checks repeated threshold evaluation and success-flag
lists. Both gates now share a checker and the existing policy evaluator;
a small flag-name mapping supplies the persisted schema consistently.
Named required metrics must match current variables or positional chains,
including at writer guards. Reordered named and unnamed legacy metrics remain
supported. Optional ESS mismatches are informational FALSE. No calculations
or E-FMI conventions changed and ordinary writers do not rerun diagnostics.

Eight focused suites passed development and installed namespace-only checks,
including new alignment22 and existing diagnostics53. Independent review
approved and reran those two. Help and the bundle guide explain labels and
legacy positional interpretation. Commit: `12ea517`.

### Resumed work: shared diagnostics and extraction — D1/D4

Duplicated diagnostic loops could diverge across fit reports, imports and
immediate/deferred bundles. Small shared workers now compute lag, R-hat/ESS,
divergences and E-FMI. Undefined lag remains NA in reports and an error in the
existing strict wrapper. Explicit normalization preserves both backends'
E-FMI formulas. Review reproduced a wrong RStan fallback convention when
E-FMI metadata was absent; that fallback now uses backend identity.

Internal sampling and bundles reuse the existing fit-extraction generic;
assembly stays independent of backend fit access. Missing generic sampler
metrics become unavailable rather than accidentally invoking RStan accessors.
No new dependency, extraction framework or CmdStan bundle support was added.
The final worker/report/deferred/acceptance checks passed development and
installed namespaces; broader focused installed checks passed before the
small reviewed fallback correction. Genuine RStan import50 passed, and
genuine CmdStan CSV calculations matched in a clean child without RStan.
Independent final review approved; guide regenerated. Commit: `2c55964`.

### Resumed work: complete constrained coverage — D5

Positive free-coordinate counts alone miss parameters such as simplex[1],
so include="none" could drop a saved model value and exclude could remove it.
Fit import and bundle extraction now protect the parameter-block schema from
the fitted model, separately from dimensions. Zero-free values remain saved
without invented count entries; genuinely zero-sized saved outputs remain
unsupported. Bundle report selection follows the extractor's already selected
outputs. Constant values keep undefined diagnostics and failed acceptance,
remaining inspectable. Named numeric count inputs share the existing validator.

A real RStan regression covers simplex/correlation/covariance/Cholesky types,
matrices/arrays/vector-one and derived outputs, confirming 29 free coordinates
versus 47 saved parameter values. The original missing-value failures were
reproduced. Seven focused development and installed suites passed, and
independent review approved. CmdStan selection has a bounded schema mock;
genuine compiled CmdStan counts were pending then and are now verified at `5b3c675`. The broad schema-recompile fallback
is retained for D6 review. Guide/help updated. Commit: `673281d`.

## Verification and agent workflow

The coordinator was the sole writer. Luna/medium supplied bounded read-only
inventories; a separate Sol 6.1/high reviewed frozen patches and sought
counterexamples. Review findings were reproduced, repaired and re-reviewed.
Both agents finished without edits or commits owed. The current workflow and
restart instructions are in the [resume checkpoint](conversation-handoff.md#resume-checkpoint--current-2026-10-02).

Checks use disposable fixtures and temporary installed libraries. Test counts
above belong to their named candidates; they are not summed into a full-suite
claim. Genuine CmdStan without RStan and complementary constrained-fit checks
are now verified in the resumed units. Live GitHub, Windows runtime, manual
corpus CI and a broad package check remain unrun. Unrelated pre-existing dirty/untracked files
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
is a net deletion of sixteen lines, with no dependency added. That polishing
pass did not close another backlog ID: eighteen remained at its checkpoint.

Independent Sol 6.1/high review approved the frozen production patch and
independently passed extraction36/rename69. Its sole fixture suggestion was
to use the supported `stan_version` field; that change was applied, approved
and verified again in development and the installed package. The audit,
inventory and review agents all finished read-only with no edits or commits
owed. The post-edit implementation commit is **`5b88e7d`**. This report and
the linked handoff are committed in a separate final documentation checkpoint.
Unrelated pre-existing working-tree changes remain untouched.

### Resumed work: safe offline tests — T1

The default suite no longer clones or requires an external database. Existing
small fixture tests run normally; legacy corpus tests explicitly opt in and
copy the configured corpus per test. Both path settings and the working
directory are scoped, so failure cannot leave writes in the source database
or configuration files in the repository. Direct test-file and coverage
execution use the same helper. Real Stan and live GitHub tests have separate
opt-ins. Automatic CI stays offline; manual corpus compatibility requires a
pinned full revision SHA. The README explains the commands and flag combinations.

Commit `1e80aea`; development and installed namespace-only runs each passed
1,203 assertions with 40 integration skips against a nonexistent corpus sentinel.
Harness33 and independent review passed. Manual corpus CI/live GitHub/Windows
remain unrun. This closes T1's test isolation contract; complementary real-fit
coverage and dependency/documentation work were pending then; the T2/T3 units
below now verify them.

### Resumed work: checked filesystem results — P4 audit slice

A rename could commit even after ZIP creation failed if a partial archive
remained. It now verifies ZIP status, member name and preserved payload before
moving originals. A failed cache copy could return a nonexistent path or leave
partial bytes for the next read; it now raises an error and removes incomplete
cache output so retry reads complete content. Failed payload removal used to
continue to metadata removal; one guard in the shared removal method now stops
that loss and identifies the failed path.

The transactional importer keeps original backups when recovery fails and now
reports their paths. It completes every deletion/restoration attempt before
warning, so `options(warn = 2)` cannot abort later recovery. These repairs use
the existing operations and staging; no transaction framework was added.
The chosen partial bundle/component write behavior remains intact and future
automatic rollback stays open under P4.

Commit `b74d113`. Final development/installed checks: rename81/cache41/model101,
import48 (five opted-out Stan tests), integrity57/resource170/reference27.
Independent review reproduced two additional failures (partial cache reuse and
warning-induced recovery abort), both repaired and rechecked. Help and bundle
guide regenerated; Windows/live GitHub unrun. Arbitrary-path removal and manual
cache refresh policies were preserved.

### Resumed work: genuine constrained CmdStan coverage — T2

The new gated integration checks public count inference and fit import against
compiled CmdStan CSV output, including simplex/correlation/covariance/Cholesky,
matrices, arrays and a zero-free-coordinate parameter. It verifies saved values,
derived-output selection, diagnostic agreement and safe rejection of a short
failed candidate. The fixture reuses the real-RStan model rather than introducing
another fixture framework.

It exposed a practical precision prerequisite: default rounded CSV values can
violate constrained matrix checks. The short count-inference helper now requests
18 significant figures; help and the bundle guide tell external-fit users to
retain precision and supporting files. It does not invent counts when the
backend cannot recover them.

Commit `5b3c675`; genuine CmdStan18 passed development, independent review and
an installed subprocess where RStan was unavailable. Shared real-RStan20 passed
development/installed, with installed dimension18/version11 checks. Windows,
live GitHub and long-run accepted CmdStan persistence were unrun. T2 is complete
within the requested complementary coverage; T3 dependency/docs work remains.


### Resumed work: optional dependencies and workflow documentation — T3

Local metadata tables unnecessarily depended on suggested `dplyr`, and YAML,
GitHub and filter boundaries otherwise gave missing-package errors late in the
workflow. Tables now use imported `tibble`; optional features fail with the
required package name before reading/network work. No dependencies were added
or promoted to Imports. Configuration replaces `eval(parse())` with validated
`local`/`github` dispatch and explicitly disables YAML expressions, including
when a global option enables them. Configuration fallback remains an open
maintainer choice under V6.

README now explains read/list construction, RStan bundle creation, existing-fit
import and sequential workflows from one entry point. It distinguishes free
counts/output shapes and backend support, links detailed guides, and documents
acceptance, explicit persistence, partial I/O writes, inspection/retry, PR
review and manual cache refresh. Examples render without loading a database.
Batch guide/help document current shared/per-workflow forms and ambiguity;
classification remains deferred. Generated Markdown/help follow their sources.

Interrupted changes were preserved at `813ea9c`; post-edit commit `888b098`.
Independent review's YAML execution counterexample was reproduced before the
parser fix; final focused23 passed independently. Installed offline suite1266
passed with0 failures/errors and41 skipped records. Actual no-Stan/no-optional
basic12 passed (one YAML-test skip). This completes T3; no release bump or
optional backend/provenance expansion was made.

Fresh Ponytail audit found one residual output-axis check to verify for a
roughly3-line cut. Earlier model rename duplication is already gone; GitHub
helper sharing stays deferred because behavior differs. The final T3 diff was
reviewed as lean. Read-only agents owe no edits or commits.
