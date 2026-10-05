# Generic fit import: proposal and orchestration guide

Status: proposal, 2026-09-24. This document narrows the earlier
`FIT_IMPORT_DESIGN.md` proposal to explicit data and a small generic interface.
Where the two differ, use this document for the first implementation. Creating
this guide does not authorize implementation. Leave this guide uncommitted as
requested; do not stage other existing untracked or modified files with it.

## Objective and first release

Allow a user who has already sampled a model to supply a fit, its data, and
human metadata and receive linked PosteriorDB data, model, posterior, and
reference-draw objects. No pre-existing posterior record should be necessary.
The constructor must not sample, compile, access the network, or write a
database as a side effect.

Implement one public S3 generic and a `stanfit` method first. S3 dispatch on
RStan's S4 fit class already has a precedent in this package. A generic does
not mean accepting arbitrary lists as fits: unsupported classes should produce
an informative error. Keep existing reference-draw import APIs compatible.

Require explicit data in this release. Defer automatic recovery, CmdStanR's
new bundle method, arbitrary backend registration, and all-object database
persistence. Existing CmdStanR conversion support stays available through its
current API. Future backend methods should reuse the common construction code.

## Proposed user interface

```r
create_pdb_reference_draws <- function(fit, data = NULL, ...) {
  UseMethod("create_pdb_reference_draws", fit)
}

# Proposed method, not an implementation:
create_pdb_reference_draws.stanfit <- function(
  fit, data = NULL,
  data_info = list(), model_info = list(),
  posterior_info = list(), reference_info = list(),
  include = NULL, exclude = NULL,
  check = TRUE, pdb = NULL, ...
) {
  # Resolve inputs, extract fit contents, construct objects, optionally check.
}
```

The `data = NULL` default reserves the future recovery behavior without changing
the signature. Today NULL or omitted data gives a clear error requesting the
actual input list. Explicit `list()` is a valid declaration of no data inputs.
An invalid explicit list must not trigger recovery. In future, explicit data
will always take precedence over backend extraction.

Users call the generic, never `.stanfit` directly. Document named metadata
arguments on its help page, even though they are forwarded through `...`.
Reject unknown, unnamed, or duplicate extra arguments instead of silently
discarding misspellings. Do not require users to instantiate info classes,
expand matrix parameter names, or invoke internal extraction helpers.

```r
result <- create_pdb_reference_draws(
  fit,
  data = stan_data,
  data_info = list(name = "experiment-1", title = "Experiment 1"),
  model_info = list(name = "normal-model", title = "Normal model"),
  posterior_info = list(added_by = "Contributor name"),
  include = c("mu", "sigma")
)

result$data
result$model_code
result$posterior
result$reference_draws
result$diagnostics
```

Return one simple S3 list, `pdb_reference_bundle`, with those five components
and a `provenance` component. The existing four object classes and their info
remain the public building blocks. A concise print method should show names,
selected variables, draw/chain counts, and checked/passed/failed status.
The name `create_pdb_reference_draws()` follows the current proposal, but its
bundle return must be explicit in the help title and return documentation.
If choosing `create_pdb_reference_bundle()` instead, settle it before release;
do not introduce several equivalent aliases simply to avoid a naming decision.

Metadata rules:

- Require data and model names and titles in the first version. Show all
  missing required fields together. Derive paths, framework, posterior name,
  and links. Do not invent scientific descriptions or references.
- Use `posterior_info$added_by` and `$added_date` as common contributor/import
  defaults for the bundle; fall back to existing package conventions. Allow
  object-specific contributor/date overrides. Do not require repetition in
  all four metadata lists.
- Validate structural fields against inferred values. Reject conflicting
  names, dimensions, framework/path declarations, and unknown fields before
  constructors can silently discard them.
- Keep reference metadata for human annotations. Do not accept caller-supplied
  diagnostics or passed-check flags as evidence of acceptance.

## Small implementation boundaries

Use ordinary internal functions; do not introduce an adapter registry,
capability framework, class hierarchy, or a collection of public helper
generics. The useful boundaries are:

1. **Resolve data.** A private helper validates explicit data and records its
   source. If NULL, call a small private backend extraction boundary, which
   currently returns unavailable. This may be a single helper receiving the
   fit; add dispatch only when a second implemented backend needs it. Keep
   unavailable distinct from an empty list and from malformed recovered data.
2. **Extract fit contents.** The backend method supplies source, selected
   dimensions, ordered post-warmup draws, sampling metadata, and any required
   sampler diagnostics in a plain internal list. Reuse/refactor the existing
   `extract_rstan_fit()` boundary instead of duplicating it. Specify required
   list fields and shapes in a short internal comment and tests; no new public
   intermediate class is needed.
3. **Construct the bundle.** A shared helper accepts resolved values and
   metadata, invokes existing constructors, links objects, and returns the
   bundle. It must not know how a particular backend recovers data.
4. **Compute and evaluate diagnostics.** Keep ordered draw extraction, metric
   calculation, and acceptance evaluation separable. Share policy with the
   existing APIs instead of maintaining a second copy of thresholds.

Future data extraction changes only the resolution/backend boundary. Once
recovered, data are validated and copied into ordinary R values in the bundle.
No temporary-file dependency or live C++ pointer should remain necessary to
use the constructed objects. Explicit-data calls keep their behavior.

## Integration details that remain necessary

Passing data resolves availability, not provenance: the package cannot
generally prove that a supplied dataset produced the fit. Record it as
caller-supplied. Structural validation must preserve types and dimensions,
but cannot establish scientific equivalence. The user should pass the actual
Stan input after preprocessing, not an earlier raw data frame.

The existing posterior constructor removes the data/model content objects,
and its getters resolve them through a database connection. Extend this
narrowly so a constructed posterior can retain embedded content and its normal
getters work before persistence. Preserve the database fallback for existing
posteriors. Allow `pdb = NULL` only where complete embedded content makes it
valid; do not weaken unrelated assertions. Embedded reference draws should be
reachable through the normal getter without cyclic references to the bundle.
Any existing writer must omit embedded payloads from posterior JSON, and file
path methods should clearly report when an object is not persisted.

Use the fit's dimensions and saved scalar variables; do not call
`infer_posterior_dimensions()` because it compiles and samples. Preserve full
matrix/array axes and validate complete coverage. Exclude `lp__`. The default
selection may include transformed parameters and generated quantities; state
this clearly and let `include`/`exclude` operate on base names. Partial saving,
zero-sized variables, missing source/includes, merged fits, and non-HMC fits
need explicit supported behavior or clear errors.

Retain per-chain sampler settings when they differ. Separate import-time
package versions and contributor dates from original sampling provenance.
Do not present today's installed version as a verified sampling version.

The supplied fit will often fail reference criteria despite being a useful
ordinary fit. Return structurally valid failed candidates with a full report;
do not automatically resample, thin, or select 10,000 draws. With `check = FALSE`,
return an explicitly unchecked candidate; no required acceptance flags may
be set. Existing writers must continue to reject unchecked or failed reference
draws. A bundle does not itself implement an atomic all-object database import.

## Diagnostics contract

Preserve the fork's current policy: exactly 10,000 retained draws per scalar
variable across chains; at least four chains; mean absolute per-chain lag-1
autocorrelation at most 0.05 per variable; R-hat at most 1.01; per-chain E-FMI
at least 0.2; zero post-warmup divergences. ESS bounds and treedepth remain
informational. The older database definition reverses the E-FMI inequality;
do not copy that discrepancy into implementation. Summary-statistic acceptance
uses at least 10,000 draws and remains distinct.

Expose the earlier proposed selective interfaces:

```r
reference_draw_diagnostics(fit, checks = "all", include = NULL, exclude = NULL)
passes_reference_draw_checks(fit, checks = "mean_lag1_ac")
```

These calls need neither data nor object metadata. The first returns observed
metrics, thresholds, per-check statuses, and failed variable/chain names; the
second returns scalar TRUE/FALSE for the requested checks. A selected check
passing is not full reference acceptance. Unknown checks/malformed objects
raise errors; unavailable or undefined required metrics cannot count as passes.
Collect all failures for an all-check report.

A lag-only check must not compute ESS, R-hat, BFMI, or require energy diagnostics.
Current eager extraction/calculation helpers need refactoring to honor this.
Preserve chain order and warmup exclusion. Keep current constant-chain failure
behavior; changing the policy for deterministic quantities is a separate task.

## Orchestrator responsibilities and delegation

Before implementation, inspect current source, tests, applicable AGENTS.md,
and git status. The earlier guide is background, not proof that code remains
unchanged. Agree on the public signature, metadata defaults, extracted-list
contract, and report shape before assigning overlapping work.

Suggested bounded assignments, only if delegation is useful:

| Assignment | Ownership and deliverables |
| --- | --- |
| Diagnostics | Selective metric/evaluation helpers, public diagnostic methods, focused tests and roxygen. |
| Bundle construction | Generic/stanfit method, data-resolution helper, metadata assembly, tests and roxygen. |
| Integration/orchestrator | Embedded content/getters/assertions, compatibility review, end-to-end examples, generated documentation, final validation. |

Assign exact file ownership before agents edit. Existing extraction code is
shared: designate one owner and send other agents agreed contracts. Serialize
Git mutations and roxygen generation. Test/documentation tasks can be given
to smaller models; integration deserves an agent comfortable with R package
dispatch, attributes, and serialization. Do not delegate an undefined contract.

Usability is an acceptance requirement. The orchestrator should explicitly
ask: how annoying will this be to call in six months? Review the common path
from the perspective of someone who only has a fit, data, and human labels.
Avoid repeated metadata, mandatory helper sequences, opaque dots, backend
knowledge, and generic assertion dumps. Provide actionable errors using public
argument names. Prefer sensible documented defaults to more configuration.

Every agent must deliver documentation of the specific files/functions it
owns, not just a change summary. Include purpose, intended callers, inputs and
outputs, one normal example, relevant failure behavior, and interactions with
other helpers. Public usage belongs in roxygen and one worked vignette or
package usage guide. Internal contracts belong in concise source comments;
provide an integration handoff with changed files and tests run. The
orchestrator consolidates this into coherent documentation instead of leaving
users to read agent transcripts. Do not write a separate manual for each
trivial helper or overcomment straightforward code.

Generate `man/` and NAMESPACE through `roxygen2::roxygenise()` only. A Markdown
proposal such as this file is not generated API documentation and does not
require running roxygen. Follow the user's current commit instructions: this
proposal must remain uncommitted. For a later authorized implementation, agree
on commit scope from the active instructions; never include existing untracked
guides merely because a broad staging command would pick them up.

## Implementation sequence and acceptance

1. Establish contracts and metadata defaults. Review the example above for
   usability before adding abstractions or optional arguments.
2. Refactor selective diagnostics and verify compatibility with existing checks.
3. Implement the generic, explicit-data resolution, stanfit extraction, and
   shared bundle assembly. Missing data must give an actionable error today.
4. Integrate embedded getters and standalone validation. Check that the full
   in-memory result works without an existing database or network connection.
5. Generate documentation, run focused tests and appropriate package checks,
   and have the orchestrator exercise the documented common path end to end.

Required tests include metadata defaults/conflicts/typos; NULL versus empty
data; array and non-square matrix preservation; selection and missing saved
variables; inference-method validation; exact policy boundaries and multiple
diagnostic failures; unchecked behavior; old API compatibility; and standalone
getters. Prove lag-only evaluation avoids unrelated metrics. Use a small real
fit for extraction and deterministic fixtures for acceptance thresholds.
Importing must not compile or sample. Save/read the constructed bundle in a
fresh R process and verify the content and getters remain usable.

The data-resolution seam should be testable with a stub returning a candidate
list or unavailable, without implementing real recovery now. Verify explicit
data bypass the seam. This is enough future-proofing; defer actual backend
file recovery and its lifecycle tests until that adapter is implemented.

Completion report: show a minimal call, returned components, diagnostic use,
known limitations, documentation locations, and tests/checks with outcomes.
Do not claim full database ingestion when only in-memory construction exists.
