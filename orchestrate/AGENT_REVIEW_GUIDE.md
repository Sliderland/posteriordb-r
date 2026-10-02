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
P3 is deferred by the maintainer; keep it visible until explicitly resumed.

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

### S2. Registration, direct-method calls, and subclass behavior — mixed

Locations: `NAMESPACE`, `R/reference_posterior.R`,
`R/compute_reference_posterior_draws_stan_sampling.R`, `R/pdb.R`.

External thinning registration and stale transformation evidence were verified in the P1 unit; see the handoff checkpoint. Remaining S2 work follows.

Also inspect internal calls such as `run_stan.pdb_posterior()` and
`posterior.character()`: call a generic where subclass dispatch is intended;
use an explicitly named worker where dispatch is deliberately bypassed.

Review `class(x)[1]` allowlists in serialization, `pdb_type()` inferring type
from the first class string, and methods removing `class(x)[1]`. Prepending a
subclass should not accidentally change database type or select the wrong
serialization branch. Decide which classes promise extensibility, then test
those promises. Do not indiscriminately append base classes: `pdb()` serves
both as a connection factory for character input and a connection accessor.

### S4. Similar conversion APIs have different semantics — design review

Locations: `as.reference_posterior_draws()` versus
`as_reference_posterior_draws()`, aliases in their respective source files.

The dotted API wraps draws with supplied metadata; the underscore API imports
a fit for a posterior, infers/checks parameter counts, calculates diagnostics,
and records acceptance. This distinction can be intentional. Explain it in
the public docs and share lower-level workers where contracts overlap.
Retain compatibility wrappers unless deprecation is agreed. Backend-named
wrappers currently forward to the generic; decide whether their names imply
backend enforcement or merely convenience.

The `posterior()` documentation also describes list construction although
the list method is on `as.posterior()`, not `posterior()`. Either correct the
documentation or add deliberate forwarding, with a public-call test.

### S5. A constructor ignores its framework argument — reproduced

Location: `R/model_code.R`, `as.model_code.character()`.

It always executes `framework(x) <- "stan"`. Requesting `framework = "pymc"`
still creates a Stan-labelled object. Honor the argument and verify that the
metadata describes an available implementation. Preserve the fixed Stan
choice in the stanmodel-specific coercion, where it is appropriate.

Test supported frameworks and invalid/mismatched framework metadata. Review
the replacement accessor too: relabelling code should have an explicit
contract rather than silently making metadata inconsistent.

## Diagnostics, fit extraction, and acceptance

### D1. Share diagnostic calculations — confirmed duplication

Locations:

- `R/utils_reference_posterior.R`: `mean_lag1_ac()` and acceptance helpers.
- `R/reference_draw_diagnostics.R`: metric calculation and report evaluation.
- `R/compute_reference_posterior_draws_stan_sampling.R`:
  `compute_stan_sampling_diagnostics()`.
- `R/create_pdb_bundle.R`: `bundle_full_diagnostic_report()`.
- `R/import_reference_posterior_draws.R`: E-FMI helpers.

Lag-1 autocorrelation has two implementations. Constant chains cause an
exception in one and NA plus a reported failure in another. R-hat and ESS
are calculated through different routes as well.

Use a small common calculation layer accepting normalized draws and optional
sampler inputs. Preserve scalar-variable names and chain identities. It can
return undefined values with explanations; callers can then either produce a
report or raise an error. Keep exception/report presentation out of the
numerical formula itself.

Do not blindly deduplicate E-FMI formulas. The RStan helper uses
`sum(diff(energy)^2) / length(energy) / var(energy)`, whereas the other helper
uses `mean(diff(energy)^2) / var(energy)`. This finite-sample difference is
explicitly documented in the code. Establish the intended backend
compatibility contract and retain a normalization option if needed. Test
short energy sequences, constant energy, missing energy, and thresholds.

Compare shared results across direct-fit reports, existing-posterior imports,
internally sampled draws, immediate bundle checks, and deferred bundle checks.
Use deterministic fixtures and tolerances appropriate to the calculation.

Concrete implementation sequence:

1. Record current results on one normalized fixture, including failures and
   optional metrics. Identify intentional differences before moving code.
2. Extract one lag-1 worker returning named values; make undefined values
   explicit. Let the existing strict wrapper raise errors from those values.
3. Share R-hat/ESS workers or one `posterior::summarise_draws()` route,
   ensuring optional checks do not trigger unrequested calculations.
4. Share the E-FMI calculation with explicit normalization where backend
   equivalence requires it; share divergence counts and treedepth metrics.
5. Route report creation and stored-diagnostic creation through those workers.
   Keep their existing output schemas through small adapters.
6. Route acceptance evaluation through one policy implementation, with a
   mapping to existing JSON flag names. Specify method-specific applicability.
7. Compare immediate/deferred paths on the same retained sampler arrays.
8. Remove old calculations only after the cross-workflow comparisons pass.

### D2. One policy exists, but acceptance evaluation is still duplicated

Locations: `reference_draw_policy()`, `reference_diagnostic_evaluation()`,
`check_stan_sampling_quality()`, `bundle_acceptance_flags()`,
`assert_checked_*()`, and `summary_statistics_from_checked_reference_draws()`.

Thresholds already have a common source. Preserve that work. Consolidate
which checks apply, evaluation, and the mapping from report keys to stored
JSON flag names. Avoid duplicating lists of six successful booleans in
multiple places. Retain the distinct draw-count rules for draws and summaries.

Check names and alignment, not only vector lengths: diagnostic values for
the wrong variables/chains should not count as evidence for the current
object. Test missing/undefined/nonfinite metrics, exact boundaries, failed
checks, and count metadata inconsistent with the actual draws. Investigate
stale values after transformations without making ordinary writes recompute
all expensive diagnostics by default.

### D3. Analytical reference draws cannot pass the existing gate — reproduced

Locations: `R/utils_reference_posterior.R` and `R/assert_checked_draws.R`.

The checking functions skip Stan-specific checks for
`inference$method == "analytical"`, but the final assertion unconditionally
requires the Stan chain, autocorrelation, R-hat, E-FMI, and divergence flags.
A 10,000-draw analytical object therefore fails for a missing chain flag.

Define method-specific applicable checks. Do not invent HMC diagnostics or
stamp them TRUE for analytical draws. Cover both reference-draw and summary
gates, their writer assertions, and the method-specific metadata schema.

### D4. Fit extraction is a useful boundary; route workflows consistently

Locations: `extract_external_stan_fit()` and its methods,
`extract_rstan_fit_for_bundle()`, `assemble_standalone_fit_bundle()`, and
`compute_reference_posterior_draws_stan_sampling()`.

Maintain a documented normalized record: post-warmup draws, aligned sampler
diagnostics, honest metadata, and optional source/counts/output shapes.
Backend access belongs in extraction methods; assembly/calculation should
operate on that record. Internal RStan sampling currently follows a separate
diagnostic/conversion route, and bundle construction calls a backend helper
directly rather than the extraction generic.

Reduce those differences where their contracts agree. Preserve bundle-only
coverage/source checks and selective extraction. Check how missing sampler
metrics are handled: a backend-neutral calculation should not unexpectedly
fall back to `rstan::get_sampler_params()` on a draws_array.

### D5. Counts, output shapes, and parameter selection need regression coverage

Location: `R/infer_posterior_dimensions.R` and fit-import selection helpers.

The recent separation of unconstrained counts and saved output shapes is
correct in principle. Most current fit tests use unconstrained real scalars
or ordinary matrices; those do not establish constrained-type correctness.

Add meaningful coverage for simplex, correlation/covariance or Cholesky
parameters, arrays/matrices, a length-one vector, and transformed/generated
quantities. Confirm complete constrained draw coverage independently of the
unconstrained count. Test total dimension and original parameter names.

Determine the intended semantics when include/exclude removes actual model
parameters: does the resulting object represent a marginal posterior or a
complete model posterior? Do not silently change this policy during cleanup.
Investigate zero-sized parameters, degenerate zero-free-coordinate types,
empty selections, numeric versus integer representations, and count
canonicalization. `validate_posterior_dimension_counts()` accepts a named
atomic vector, while some callers reject it before invoking that validator.

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

### D7. Version metadata construction disagrees with validation — reproduced

Locations: `stan_fit_sampling_versions()`, `pdb_stan_sampling_versions()`,
`imported_reference_posterior_versions()`, `new_bundle_reference_info()`, and
`assert_reference_posterior_info()`.

The CmdStanR internal-sampling helper creates version fields without
`r_Makevars` and `r_session`; the validator requires both when CmdStanR
versions are present. Its output fails the validator.

Use shared metadata construction with explicit backend and provenance.
Distinguish versions at original sampling time from the current import/check
environment. The CmdStanR importer currently starts from a helper that queries
the installed RStan version and initially includes RStan metadata; it should
not require RStan merely to import a CmdStanR fit or imply that RStan sampled
it. Test helper/validator agreement and backend-only dependency environments.
Preserve unknown original versions honestly rather than manufacturing them.

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

Rename/bibliography rollback backup preservation and shared ZIP extraction failure handling are verified; see the handoff for commits and checks. The remaining scope is broader component/bundle failure behavior and operation-result checks.

Check success results from zip/file.copy/write/rename operations.

### P5. Posterior link lookups parse names instead of metadata — reproduced

Locations: `R/pdb.R`, `pn.pdb_model_code()`, `pn.pdb_data()`, and
`pn.pdb_model_info()`.

The first two split posterior filenames at hyphens. For a posterior named
`unit-data-unit-model`, linked to `unit-data` and `unit-model`, model-code
lookup returns no match. These hyphenated names are used by new bundle tests.
The model-info method currently returns all posterior names without filtering
for its model.

Read the explicit `data_name`/`model_name` links rather than guessing the
split point. Share a link-index helper if several consumers need it. Test
hyphens in either name, multiple linked posteriors, unrelated models, and
standalone objects without a database connection.

### P6. Filename/extension helpers mishandle dots and empty databases

Locations: `R/utils.R`, local/GitHub name-listing methods.

`remove_file_extension("model.v2.info.json")` returns `"model"`, losing the
actual identifier. Renaming permits dots. Removing extensions should remove
the expected suffix for the file kind, not split at the first dot.

`model_names()` on an empty fixture errors because empty extraction returns
NULL and is passed to `basename()`. Ensure list functions return character(0)
for empty directories. Filter actual JSON/info filenames before stripping
suffixes; unrelated files or subdirectories must not become object names.
Test `.DS_Store`, multi-dot names, `.info.json`, ordinary `.json`, and no files.

### P7. Summary reference-name listing uses the wrong path — confirmed

Locations: `reference_posterior_names.pdb_local()` and its GitHub method.

For `type = "mean_value"`, the local method looks under
`reference_posteriors/mean_value/info` rather than
`reference_posteriors/summary_statistics/mean_value/info`. The GitHub method
does not consume `type` and always lists draws/info.

Share a type-to-path mapping across listing, reading, writing, and removal.
Test draws and both summary types using a local fixture and mocked transport
responses; no live GitHub account is needed to verify path selection.

### P8. Framework extension logic is already available but bypassed

Locations: `model_code_file_path.character()`, model removal,
`supported_frameworks_file_extension()`, `write_to_path()`.

The character path method assigns an extension for Stan and PyMC only;
`framework = "pyro"` reproduces `object 'ft' not found`. Model removal uses
the framework name as the extension, so it targets `.pymc` instead of `.py`.
The package already has the correct framework-to-extension helper.

Reuse that helper. Prefer implementation metadata's declared code path when
retrieving an existing model. Audit writer support separately: declaring a
framework supported does not mean `write_to_path()` implements it. Clearly
support or reject each operation instead of failing after metadata is saved.
Test read/write/remove behavior per supported operation and custom code paths.

### P10. Reader sometimes conflates reference names with posterior names

Location: `read_reference_posterior_summary_statistic()` in
`R/summary_statistic.R`.

It receives a reference-posterior name but reads info through
`reference_posterior_info.character()`, which resolves a posterior of that
name first. Draw reading was already changed to read reference info directly
for staged references. Apply the same identity distinction to summaries.
Use a fixture where posterior and reference names differ, and verify both
single-summary and multi-summary access.

## Validation and workflow behavior

### V2. Posterior checking discards the supplied in-memory object — confirmed

Location: `R/check_posterior.R`, `check_pdb_posterior()`.

It replaces the input with `pdb_posterior(po$name, pdb = pdb(po))` before
checking it. This cannot validate a standalone posterior with pdb = NULL
and ignores unsaved changes even when a database is attached.

Separate object consistency from persisted round-trip validation. Use
getters/validators for embedded content. Require a connection for checks
that genuinely need bibliography or persisted files, and report unavailable
checks explicitly. Preserve existing database validation through an explicit
path. Audit cache-evicting helpers that assume getters returned a connected
object. Verify standalone, connected, modified, and persisted cases.

### V3. Summary validation depends on field order and ignores lengths — reproduced

Location: `assert_reference_posterior_summary_statistic()`.

It checks `x[[1]]` as character and all remaining fields as numeric despite
having already checked field names. Shuffling valid fields fails. Conversely,
two variable names, one summary value, and three MCSE values are accepted.

Validate named fields and compatible lengths; validate names for uniqueness
and values/MCSE according to a documented finite/missing-value policy.
Validate metadata too. Check both summary types and round trips with singleton
and multiple variables. Reordered JSON object keys should not change meaning.
Review the similarly strict ordering assertion for reference-info field names;
canonicalize order for output separately from validating required fields.

### V4. Batch sampling-list detection can misclassify malformed input — reproduced

Location: `normalize_sequential_sampling_lists()`.

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

### V5. CmdStanR argument translation silently drops options — source-confirmed

Location: `translate_cmdstanr_sampling_args()` in `R/run_stan.R`.

It removes the entire `control` list but only forwards `adapt_delta` and
`max_treedepth`. Other user options disappear. `cores` also overwrites an
explicit `parallel_chains` value without a conflict decision.

Define supported translations, conflicting aliases, and unsupported options.
Translate or reject unsupported controls; do not silently alter sampling
configuration. Use table-driven tests for argument translation, with a small
real-backend smoke test for an agreed configuration where available.

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

### T1. Make package tests independent of a user's database contents

Locations: `tests/testthat/test-write-pdb.R`, `test-contributing.R`,
`test-reference_posterior_summary_statistic.R`, `test-pdb.R`, getters/checkers,
and `.github/workflows/`.

Seventeen of the thirty test files contain environment/live-database
references. That count describes references, not seventeen wholly unsuitable
test files. Some new tests already use good temporary fixtures.

The concrete concern is mutation: older write/contribution tests operate on
`pdb_local()` from PDB_PATH, use fixed names such as `test_data` and
`test_model`, overwrite files, and later remove them. Cleanup often occurs
only at the end, so failures can leave modifications; pre-existing records
with those names can be overwritten or deleted.

Partial repair: the package `tests/testthat.R` entry point now stages a copy
of the configured corpus (or a fresh upstream clone), uses both path settings,
and cleans up/restores settings on success or failure. Direct test/coverage
runs still require explicit disposable paths. Offline minimal fixtures,
configuration-file isolation, and separation of integration tests remain open.

Create reusable fixture builders for minimal databases, linked models/data,
references with distinct names, bibliography, and synthetic draws. Use
per-test temp directories and scoped cleanup. Keep the builders small and
composable; do not duplicate an entire production database in every test.

Separate package unit/fixture tests from optional database compatibility
tests, real-backend tests, and live GitHub tests. Test the package's database
validator with intentionally valid/invalid fixtures; validate the actual
PosteriorDB corpus in its own workflow or a clearly identified integration
job. Pin the external database revision when reproducibility is important.
Assert failure reasons/results instead of specific corpus counts or only
messages. Standard package tests should not need PDB_PATH, credentials,
network access, Stan compilation, or a user's database checkout.

### T2. Keep useful mocks; add public-contract and installed-package coverage

Locations: `test-generic-bundle-acceptance.R`, `test-bundle-fit-extraction.R`,
`test-create-pdb-bundle.R`, `test-reference_posterior.R`.

Mocking extraction is appropriate for testing assembly/acceptance, and mocking
unconstrained count inference is appropriate for tests of saved array coverage.
Those tests do not establish that actual fit extraction/count inference works.
Named-only calls do not establish positional argument compatibility. Direct
method calls do not establish S3 registration.

Retain tests of important boundaries and add a limited set of complementary
public-generic tests. Install into a temporary library and test in a clean
subprocess. Include namespace-only usage. Add small real-fit tests for the
specific constrained/count contracts, separately from fast fixture tests.

Important regression matrix: compare all applicable workflows using the same
draws and sampler inputs; verify metric equality, acceptance equality, names,
metadata, and JSON round trips. Differences should have an explicit reason.
Do not write tests that merely repeat implementation branches or couple to
private helper names without asserting useful behavior.

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
