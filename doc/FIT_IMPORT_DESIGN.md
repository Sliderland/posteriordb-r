# Constructing PosteriorDB objects from an external Stan fit

Design and implementation handoff, 2026-09-24. Inspected package baseline:
`9533d29`; installed rstan: 2.32.7 (Stan 2.32.2). This document is a design,
not an implemented API. No package functions or generated documentation were
changed for this investigation. Updated after reviewing the referenced
“Recover rstan input data” chat and CmdStanR development source (see below).

## Recommendation and feasibility

The workflow is feasible when the sampling data are supplied explicitly or
recovered from an available CmdStanR input file, and the caller supplies the
human metadata that the fit does not contain. An S3 generic with a `stanfit`
method is straightforward, even though `stanfit` is an S4 class; this package
already uses that combination for `as_reference_posterior_draws()`.

An arbitrary fit alone cannot reliably reconstruct the original data. RStan's
documented slots contain code, draws, parameter dimensions, chain arguments,
initial values, date, and a miscellaneous environment, but no original data
list. Inspection of the installed sampling method confirms that it passes
preprocessed data to C++ and stores a sampler instance in `.MISC`, without
saving that data list in the returned R object. A live model pointer is not a
supported data export interface and cannot be relied on after serialization.
Do not try to recover data from the caller's environment or decompile C++.

The generic and individual object constructors are easy. Reliable integration
is moderate work because current posterior accessors resolve content through
a database, the diagnostic evaluator is eager and stops at the first failure,
and persistence currently assumes that the posterior already exists. Use the
design handoff route before implementation rather than delegating the entire
feature as a small wrapper.

Subjective confidence, based on the inspected code rather than calibrated
probabilities:

| Claim | Confidence | Qualification |
| --- | --- | --- |
| Ordinary RStan fits have no supported original-data recovery API | 98% | Verified installed implementation and upstream source; third-party wrappers may store extra data separately. |
| CmdStanR input JSON can be recovered while its recorded file remains readable | 98% | Supported file accessor; file contents may have been changed since sampling. |
| Materialization alone preserves CmdStanR input data | 1% | Inspected implementation loads outputs, not the input file. |
| Stored model source can be extracted | 99% | Normal fits via `get_stancode()`; CSV-created fits and external include files need explicit handling. |
| Draws, dimensions, and chain settings can be reused | 95% | Ordinary HMC/NUTS fits; selective saving, merged fits, and older versions need validation. |
| Fit plus explicit data and metadata supports the requested workflow | 95% | Supplied data cannot generally be proven to be the data originally used. |
| Complete in-memory integration is a small independent patch | 35% | Several current assumptions must change together. |

Estimated focused engineering effort, including tests and documentation:
selective diagnostics 0.5–1.5 days; construction and in-memory access 1–2 days;
integration and compatibility tests another 0.5–1 day. A complete transactional
database writer adds approximately 1–2 days. These are planning estimates,
not execution-time guarantees. Recommend GPT-6-Sol or an R package developer
for integration, with Astra reviewing the interface and acceptance semantics.
GPT-6-Luna at medium effort is suitable for bounded fixtures, tests, and
roxygen comments after the contracts below are established.

## Evidence and source map

External primary sources:

- [RStan stanfit slots and accessors](https://mc-stan.org/rstan/reference/stanfit-class.html)
- [RStan fit contents vignette](https://mc-stan.org/rstan/articles/stanfit-objects.html)
- [RStan construction and sampling implementation](https://github.com/stan-dev/rstan/blob/develop/rstan/rstan/R/stanmodel-class.R)
- [CmdStanR input/output file methods](https://mc-stan.org/cmdstanr/reference/fit-method-save_output_files.html)
- [Inspected CmdStanR development fit implementation](https://github.com/stan-dev/cmdstanr/blob/aef0866d32c82f5092a74d204a1a2856349957d2/R/fit.R)
- [Stan diagnostic guidance](https://mc-stan.org/learn-stan/diagnostics-warnings.html)

The installed `sampling,stanmodel` method was also inspected through
`methods::selectMethod()` after loading rstan. No new model was compiled or
sampled during this investigation. Fresh-session RDS behavior remains an
implementation acceptance test, not an experiment claimed here.

Package code to reuse or extend:

| File | Relevant behavior |
| --- | --- |
| `R/import_reference_posterior_draws.R` | `extract_rstan_fit()`, chain metadata helpers, variable filtering, import metadata construction, existing staged reference writer. |
| `R/data_info.R`, `R/data.R` | `as.data_info()`, `as.pdb_data()`, validation, data retrieval. |
| `R/model_info.R`, `R/model_code.R` | `as.model_info()`, `as.model_code()`, Stan implementation paths. |
| `R/posterior.R` | `as.posterior.list()` constructs metadata from data/model objects, then discards the content objects; assertion currently requires a database. |
| `R/infer_posterior_dimensions.R` | Selection conventions; do not call this function during import because it compiles and samples again. |
| `R/compute_reference_posterior_draws_stan_sampling.R` | Diagnostic calculations and sampler-array conversion; currently calculates all summaries eagerly. |
| `R/utils_reference_posterior.R` | Current acceptance thresholds, lag-1 calculation, draw-count checks. |
| `R/reference_posterior.R` | Reference metadata shape, assertions, retrieval, and thinning. |
| `R/write_pdb.R` | Individual writers; sequential calls do not form an all-object transaction. |
| `tests/testthat/test-import-external-stanfit.R` | Real fit fixture, matrix ordering, metadata, failure and rollback tests. |

Also inspected the local database's `doc/REFERENCE_POSTERIOR_DEFINITION.md`
and `README.Rmd` under `~/Documents/posteriordb`. The README explicitly defines
mean absolute per-chain lag-1 autocorrelation. The definition document says
E-FMI should be *below* 0.2, while the fork requires at least 0.2; the document
appears to reverse the direction. Stan guidance treats low BFMI as a problem
and discusses a 0.3 warning threshold, which is a different policy from this
fork's 0.2 acceptance threshold. Preserve the fork's policy for this feature
and document the discrepancy; do not silently change thresholds.

## CmdStanR data recovery: revised scope

Pursue this as a bounded second backend increment after the shared bundle
constructor. It improves automatic inference substantially and does not require
changing the RStan conclusions. The referenced chat concerns CmdStanR's
`$materialize()`, not a new RStan data accessor. The thread reader returned
truncated messages; its local transcript was read to verify the discussion.
The local `~/Documents/cmdstanr_dev` checkout is version 0.9.0.9002, commit
`aef0866d32c82f5092a74d204a1a2856349957d2`. Its source confirms:

- `$data_file()` returns the recorded input-file path.
- `$save_data_file()` delegates preservation and path updates to the runset.
- `$materialize()` loads draws and tries diagnostics, initial values, and
  profiles. It does not read the input data into the fit. Some errors are
  suppressed, so successful materialization is not diagnostic validation.
- `$save_object()` calls materialization before serialization.
- `$code()` returns source retained by the runset, or warns and returns NULL
  when source was unavailable.

The data-file accessor is documented independently of the new materialization
method. Do not impose a development-version requirement for data recovery.
Check capabilities on the actual fit instance, including inherited methods;
a package version or the subclass's directly defined method names is not
sufficient. Do not install or upgrade packages inside the importer.

Being in memory is neither sufficient nor necessary: a live fit can point to
a deleted file, and a reloaded fit can point to a durable, readable file.
Snapshot recoverable data into the resulting bundle immediately. The bundle
must remain usable after temporary input and output files disappear.

### Backend contract and precedence

Add `create_pdb_reference_draws.CmdStanMCMC()` using the same metadata,
selection, checking, and return contracts. Keep `data = NULL` as “attempt
backend recovery”; for ordinary RStan it still leads to an explicit-data error.
For CmdStanR:

1. A non-NULL explicit `data` list wins, including `list()`. Record it as
   caller-supplied; do not require the original file or claim equality to it.
2. Otherwise call the public `$data_file()` accessor. Validate a single readable
   local path and read the input snapshot without moving the file or changing
   the fit's paths. No private R6 slot traversal or environment search.
3. Support Stan JSON first. Parse without collapsing singleton vectors/arrays;
   normalize with declared variable shapes/types where available. Preserve
   matrix orientation, integer semantics, empty arrays, and dimensions. If
   shapes cannot be resolved unambiguously, require an explicit data list.
   Standard JSON cannot restore arbitrary original R classes or preprocessing
   history, and zero-length shapes can be ambiguous.
4. Missing/unreadable/malformed files, unsupported formats, or unavailable
   accessors must produce actionable errors asking for `data = ...`. Never
   interpret them as a data-free model. Initially require explicit data for
   R dump inputs; never `source()` or evaluate a data file as R code.
5. Record source kind, recovery time, path and a content hash when available.
   A hash calculated at import only identifies that snapshot; without an
   original sampling-time hash it cannot prove the file was unchanged.

Use `$code()` for source, collapsing its lines with newlines. Add an explicit
`model_code = NULL` fallback argument to the CmdStanR method for fits lacking
source, especially objects reconstructed from CSVs. Record supplied source as
unverified against the sampled executable; do not guess it from a model name.
Preserve the existing include-resolution requirements.

Reuse `extract_cmdstanr_fit()` for draws and metadata, after the selective
extraction refactor. Derive variable dimensions from trustworthy metadata and
complete scalar-name coverage; do not copy the current short-fit CmdStanR
inference path blindly. Permit explicit `dimensions = NULL` fallback on this
method where metadata are insufficient and validate every scalar against the
saved draws. Treat sparse/ambiguous shapes as errors. Do not recompile merely
to discover dimensions or parse data declarations with a regular expression.

Read only the public outputs needed for construction and the requested checks.
Do not unconditionally call `$materialize()` in the importer, especially for
lag-only diagnostics: it loads additional outputs and mutates an R6 object.
Existing public draw/diagnostic accessors already load or reuse their caches.
After extraction, validate required diagnostics explicitly.

### Persistence examples and scope

A live ordinary CmdStanR fit with available JSON and stored source can omit
both `data` and `model_code` from the proposed constructor. For later import,
users can preserve the input file with `$save_data_file()` and save the fit
with `$save_object()`. The latter alone does not preserve data. The preferred
self-contained result is the constructed PosteriorDB bundle, whose data,
source, draws, and diagnostics have already been copied into R values.

Allow roughly another 0.5–1.5 focused engineering days for the adapter and
file-lifecycle/shape tests; ambiguous schema handling may take longer. This is
worth pursuing, with approximately 90% confidence in a useful bounded JSON
implementation. Keep the common constructor independent of the backend so
this addition does not block RStan support or require a development install.

## Proposed public contract

```r
create_pdb_reference_draws <- function(fit, ...) {
  UseMethod("create_pdb_reference_draws", fit)
}

# Proposed stanfit method arguments:
create_pdb_reference_draws.stanfit <- function(
  fit,
  data = NULL,
  data_info = list(),
  model_info = list(),
  posterior_info = list(),
  reference_info = list(),
  include = NULL,
  exclude = NULL,
  check = TRUE,
  pdb = NULL,
  ...
) {
  # Implementation follows the pipeline below.
}
```

Use explicit named metadata arguments on the method for discoverability;
the generic still dispatches through `...`. Reject unknown or duplicate
arguments. The default method gives a clear unsupported-class error.
Initial support covers completed RStan HMC/NUTS fits. Detect and reject VB,
empty/error fits, standalone generated quantities, and fixed-parameter runs
as unsupported reference-sampling methods rather than accepting by class alone.

Return a `pdb_reference_bundle`, a named list containing:

```r
list(
  data = data_object,                 # pdb_data, with info
  model_code = code_object,           # pdb_model_code, with info
  posterior = posterior_object,       # pdb_posterior, with linked content
  reference_draws = draws_object,     # pdb_reference_posterior_draws
  diagnostics = diagnostic_report,    # NULL when check = FALSE
  provenance = provenance            # inferred/supplied fields and limitations
)
```

This return value exposes all constructed objects and avoids hiding the new
data and model inside a draw object's attributes. Document that the function
returns a bundle despite its name. A possible clearer name is
`create_pdb_reference_bundle()`; settle the public name before release.

Construction does not write to a database. `pdb`, if supplied, associates a
destination; it must not require a pre-existing posterior. Do not call
`pdb_default()` during a purely in-memory import. Database persistence is a
separate optional phase with the contract below.

Example intended usage:

```r
stan_data <- list(N = length(y), y = y)
fit <- rstan::sampling(model, data = stan_data)

bundle <- create_pdb_reference_draws(
  fit,
  data = stan_data,
  data_info = list(name = "experiment-1", title = "Experiment 1"),
  model_info = list(name = "normal-model", title = "Normal model"),
  posterior_info = list(added_by = "Contributor name"),
  reference_info = list(comments = "External RStan sampling"),
  include = c("mu", "sigma")
)

# Preserve both components for import in a later R session.
saveRDS(list(fit = fit, data = stan_data), "fit-with-data.rds")
```

No `rstan` option was found that natively adds the original input list to the
fit. Saving a normal R list with both objects is sufficient. A future explicit
attachment helper could store a versioned data snapshot as an attribute;
that is package functionality, not native RStan retention. Omit automatic
recognition of arbitrary attributes in the first version. For RStan, missing
`data` must fail with an actionable error; CmdStanR first attempts the public
input-file recovery described above; `data = list()` explicitly represents a
model with no data inputs. Never interpret missing data as an empty dataset.

## Construction pipeline and metadata rules

1. Validate supported fit, named metadata lists, scalar flags, selection, and
   resolved data (explicit or backend-recovered) before any costly diagnostic
   calculation. Preserve numeric
   arrays, dimensions, integer values, and names; reject invalid or duplicate
   data names. Do not claim that shape validation proves the supplied data
   match the original sampling inputs.
2. Extract source with `rstan::get_stancode(fit)`. Fail clearly if absent.
   Detect unresolved includes and require self-contained source or an explicit
   future include-resolution API; do not resolve paths against today's working
   directory and silently change the program. No recompilation or resampling.
3. Get selected dimensions from `fit@par_dims` and actual saved variable names.
   Preserve full array/matrix axes and the package's column-major scalar-name
   expansion. Cross-check every selected scalar against the draws. Exclude
   `lp__` unconditionally. Reject partial saving of a selected base variable.
   Default to completely saved output variables and report the selection;
   these may include transformed parameters and generated quantities, not
   solely parameter-block variables. Document `include`/`exclude` as the way
   to choose the intended posterior variables. Do not infer dimensions from
   unconstrained dimension counts or a maximum index in sparse saved output.
4. Construct data/model metadata with existing constructors. Require data
   `name` and `title`; use fit model name only as a validated suggested model
   name, and require model `title`. Resolve common `added_by`/`added_date`
   from `posterior_info`, falling back to the existing user/date conventions;
   object-specific metadata may override those two human fields. Dates describe
   import, not sampling. Derive canonical paths and framework from names.
   Require explicit descriptive content, references, licence, and prior
   descriptions when needed; never invent these from the source code.
5. Construct `pdb_data` and `pdb_model_code` with their info. Construct posterior
   name as `data-name-model-name`, links, dimensions, and info. Reject supplied
   conflicting names, dimensions, file paths, or implementation declarations.
   The existing posterior constructor silently subsets to allowed fields;
   validate unknown `posterior_info` fields before calling it.
6. Extract chain-preserving post-warmup draws and sampling metadata using a
   refactored extraction boundary. Keep per-chain arguments; do not present
   the first chain's settings as common if they differ. Different seeds are
   valid. Validate compatible iteration structure and explain unsupported
   merged fits. Preserve algorithm, thinning, warmup, controls, seeds, chain
   identifiers, and available adaptation information with honest provenance.
   Installed R/RStan/Stan versions at import time are not necessarily the
   versions that sampled a saved fit. Label the distinction, recording unknown
   sampling versions as unknown rather than fabricating reproducibility.
7. Build reference metadata using the existing schema. `reference_info` should
   accept human metadata (name, comments, added_by, added_date, and a documented
   sampling_timestamp override), not caller-supplied diagnostics or pass flags.
   Resolve reference name consistently in the posterior and reference info.
8. If `check = TRUE`, compute and evaluate all required checks, collecting every
   failure; return failed candidates for inspection. If `check = FALSE`, keep
   diagnostics/checks unset and mark the bundle unchecked. Structural validity
   is always enforced. An unchecked or failed candidate cannot be written as
   accepted reference draws.

## In-memory object integration

Current `as.posterior.list()` deletes the input data/model content after
extracting metadata. `get_data.pdb_posterior()` and
`model_code.pdb_posterior()` then retrieve files through `pdb(x)`. Returning a
posterior that needs nonexistent database entries would not fulfill this API.

Add optional embedded content attributes to posterior objects and use them
first in the relevant getters; preserve the database fallback. Add embedded
reference draws after construction and teach `reference_posterior_draws()`
to use them too. Keep references one-way to avoid cyclic bundle graphs.
Do not store the whole fit in the bundle. Ensure saving/loading the bundle
preserves content without depending on live C++ pointers.

Narrowly extend `assert_pdb_posterior()` to accept either a valid database
connection or complete, validated embedded data and model content. Require
names/info consistency in the embedded case. Existing database posteriors
must keep their present behavior. Audit reference-draw constructors for
analogous required database attributes, and relax only what standalone
objects need. Serialization must explicitly omit embedded content from
posterior JSON. File-path access on a standalone object must report that
it has no persisted path, rather than inventing one.

## Selective diagnostic API

```r
# Proposed interfaces; both dispatch on supported fits/draws as appropriate.
reference_draw_diagnostics(fit, checks = "all", include = NULL, exclude = NULL)
passes_reference_draw_checks(fit, checks = "all", include = NULL, exclude = NULL)

passes_reference_draw_checks(fit, checks = "mean_lag1_ac")  # scalar TRUE/FALSE
passes_reference_draw_checks(fit)                         # all required checks
```

The report includes overall pass, the explicitly requested checks, per-check
pass/status, thresholds, observed values, and failed variable/chain names.
`checks = "all"` means the acceptance checks below. Individual success does
not certify full reference-draw acceptance. Missing or non-finite required
metrics fail; malformed inputs/unknown check names raise informative errors.
Report unavailable diagnostics explicitly rather than silently skipping them.

| Check identifier | Current fork acceptance rule |
| --- | --- |
| `ndraws` | Exactly 10,000 post-warmup draws per scalar variable, across all chains. |
| `nchains` | At least four chains. |
| `mean_lag1_ac` | For every scalar variable, mean across chains of absolute lag-1 autocorrelation is at most 0.05. |
| `rhat` | Finite R-hat at most 1.01 for every selected scalar variable. |
| `efmi` | Finite E-FMI/BFMI at least 0.2 for every chain. |
| `divergences` | Zero post-warmup divergent transitions in every chain. |

ESS bounds and maximum-treedepth counts are informational in this fork.
Neither should silently become an acceptance requirement. Summary-statistic
draws use at least 10,000 rather than exactly 10,000; keep that distinct.
The definition document uses strict "below" wording while the implementation
is inclusive; retain the implementation's boundary behavior and test it.

Separate extraction, metric computation, and policy evaluation. The existing
`compute_stan_sampling_diagnostics()` calls `summarise_draws()` and computes
ESS, R-hat, lag-1, sampler summaries, and BFMI together. Calling that function
for a lag-only request would violate the requested selective computation.
Likewise, the current `extract_rstan_fit()` requires valid BFMI before returning.
A lag-only request should need only ordered draws, never energy diagnostics.

Use one calculation/evaluation implementation for the new public API and the
existing acceptance functions so they cannot drift. Preserve existing return
types and `checks_made` keys at compatibility boundaries. The complete importer
may still record informational ESS for compatibility with reference-info
assertions; standalone selective checks must calculate only requested metrics.
For `check = FALSE`, the existing schema allows `diagnostics = NULL`; do not
populate a partial diagnostics list that violates its required fields.

Compute lag-1 within each chain before taking absolute values and averaging.
Do not permute/flatten chains, average signed correlations, or mix warmup in.
Keep the current undefined-constant-chain failure behavior in this change;
any policy for deterministic constrained entries is a separate decision.
Check sampler diagnostics over the original available post-warmup sampler
output. No automatic thinning/subsampling in the first version: excessive
autocorrelation or a wrong draw count should be reported. If later added,
recompute draw-based metrics after selection and preserve sampler-failure
evidence from the full original sampling output.

## Optional persistence phase

Object construction is the requested core. If adding bundle persistence,
provide `write_pdb.pdb_reference_bundle()` as a separate reviewed increment.
Preflight every name, path, collision, metadata field, and required diagnostic
before changing the destination. Stage data ZIP/info, model source/info,
posterior JSON, and reference ZIP/info together. Reload and compare values,
dimensions, scalar names/order, metadata, and reference links before promotion.

Extend the existing staged reference writer rather than calling individual
writers in sequence. Preserve originals for rollback of every affected file,
and test failures at promotion and verification. Default to no overwrite.
Account for shared model/data names: overwriting shared content can change
unrelated posteriors. Initially allow reuse only after content equality checks,
and reject conflicting shared entities. Refresh destination caches only after
successful promotion. Describe rollback guarantees honestly; a sequence of
file moves is not a crash-proof filesystem transaction.

## Implementation order and acceptance tests

1. Implement diagnostic extraction/computation/evaluation boundaries and the
   selective API. Route existing checks through the shared evaluator while
   preserving behavior. Test exact boundary values, multiple failures, missing
   metrics, non-finite/constant draws, signed-correlation cancellation, and
   per-chain failures. Instrument helpers to prove lag-only requests do not
   calculate ESS/R-hat/BFMI or require sampler diagnostics.
2. Implement fit-to-bundle construction and embedded getters. Use existing
   constructors, metadata helpers, and dimension expansion. Test a real small
   RStan HMC fit with nonempty data, a scalar, vector, matrix, and generated
   quantity. Test selection, missing selected variables, partial saved arrays,
   zero-sized dimensions, and unsupported inference methods. State supported
   behavior for each edge case; explicit errors are preferable to silent loss.
3. Verify an empty destination needs no pre-created posterior. With `pdb = NULL`,
   getters must work without network access, temporary database creation,
   compilation, or sampling. Verify explicit `data = list()` and missing-data
   behavior differ. Test metadata conflicts and unknown arguments.
4. Save/read the fit and data bundle in a fresh R process, then import it.
   Compare model source, data values/shapes, dimensions, chain settings, draws,
   and getter behavior. Separately save/read the constructed bundle. A short
   real fit need not pass the reference acceptance policy; use deterministic
   synthetic draws to test acceptance logic without flaky sampling assertions.
5. If implementing persistence, add all-file rollback and round-trip tests,
   including shared-name collisions and unchecked/failed rejection.
6. Add the CmdStanMCMC adapter as the next bounded increment. Test live fit
   recovery, explicitly supplied data precedence, missing/deleted/modified
   input JSON, unsupported R dump, empty data, singleton and zero-sized arrays,
   non-square matrices, source absent from CSV-reconstructed fits, and explicit
   dimension fallback. Prove the bundle works after input/output files are
   removed. Test saved/materialized fits both with and without durable input
   files, and an older-capability fixture without `$materialize()`. Tests must
   distinguish successful output caching from unavailable input data. Verify
   no unconditional materialization or private-slot extraction occurs.
7. Write roxygen comments in R source. Run `roxygen2::roxygenise()` from the
   package root and inspect generated `NAMESPACE` and `man/` changes. Never
   hand-write Rd files. Run targeted testthat tests, then package checks
   appropriate to the touched APIs. Report pre-existing warnings separately.

## Ready-to-use implementation prompt

Implement the design in `doc/FIT_IMPORT_DESIGN.md` in this posteriordb fork.
Read applicable AGENTS.md instructions and inspect the actual implementation
and tests; the document is based on commit 9533d29 and may need reconciliation
with newer work. Start with the selective diagnostic API, then the RStan bundle
constructor and working in-memory getters. Then implement the bounded
CmdStanMCMC adapter and JSON input-file recovery specified above as a separate
increment. Keep bundle persistence out of these increments. Reuse the current
import and metadata code. Feature-detect public accessors; do not require the
development-only materialization method or mistake cached outputs for input
data. Explicit data take precedence, and failed recovery asks for explicit
data. Snapshot recovered values in the bundle and test file deletion/reloading.
Do not compile/resample as part of importing a fit, infer missing data from the
environment, invent provenance, or silently mark unchecked draws as accepted.

Use the proposed explicit metadata lists and preserve current acceptance
thresholds. Add focused tests for the contracts and failure cases above.
Generate documentation only through roxygen2; comment non-obvious decisions
concisely. Give a report of public behavior, tests, limitations, and commits.

Before editing, inspect git status and commit relevant existing changes with
a descriptive baseline message. If the relevant files are clean, use the
existing HEAD as baseline and do not create an empty commit. After each
coherent completed increment, commit code, tests, and generated documentation
with a clear summary and explanatory body. Never include unrelated work or
rewrite another agent's commit. If delegating, give each agent explicit file
ownership and these same before/after commit instructions; serialize shared
source edits, roxygen generation, and Git mutations under the coordinator.
