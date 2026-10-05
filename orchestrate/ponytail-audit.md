# Ponytail audit

Reviewed on 2026-10-01 against local commit `55e667e2b11267a5ab9db76e5a15c15ea82c6376` (2026-09-29). `DESCRIPTION` identifies package version **0.3.6**.

This checkout is slightly outdated. Findings describe the files here; they are not claims about the newest package. Recheck callers, exports, and tests on the current development version before applying any cut. No implementation files were changed, and no newer checkout was fetched.

Scope: unnecessary complexity across `R/`, with callers checked in tests, namespace registrations, documentation, and workflows. Correctness, security, and performance findings are outside this audit. The existing [review findings](ponytail-review-findings.md) cover a broader review separately.

## Ranked cuts

1. **shrink:** Remove unused metadata-validation flexibility and unreachable checks. Every runtime call supplies `required = character()`; keep actual required-field validation in `assert_bundle_required_metadata()`. The diagnostic-field rejection after `validate_bundle_metadata()` is unreachable because those fields already fail its allowlist. `new_bundle_reference_info()` also filters fields already filtered by its caller. Preserve the live allowlist and actionable required-field errors. **About 30 lines.** [create_pdb_bundle.R](../R/create_pdb_bundle.R), lines 208–275, 894–927, 997–1007.

2. **delete:** Remove unexported `warning2()`, `models_tbl_df()`, `data_tbl_df()`, and `write_txt_to_path()`: no repository callers or S3 registrations. `bundle_dimension_names()` has test callers only; retarget those checks to the live dimension-validation/selection path before deleting it. No replacement API is needed. **About 19 implementation lines.** [utils.R](../R/utils.R), line 15; [tibble.R](../R/tibble.R), lines 13–19; [pdb.R](../R/pdb.R), line 749; [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R), line 816.

3. **yagni:** Remove the future fit-data recovery seam. `recover_stanfit_data()` always returns `NULL`, so successful recovery and its alternative messages exist only through test mocks. Reject missing data directly, retain ordinary-input validation and `pdb_data` conversion, and record `caller-supplied` provenance. Add recovery when a supported backend can actually provide it. **About 12 lines.** [create_pdb_bundle.R](../R/create_pdb_bundle.R), lines 799–843.

4. **shrink:** Replace the duplicated authenticated/unauthenticated HTTP download branches in `pdb_file_copy.pdb_github()` with the existing `github_download()` worker. Keep the contents API lookup and pass through token, destination, and overwrite behavior. **About 8 lines.** [pdb_github.R](../R/pdb_github.R), lines 68–80 and 179–195.

5. **shrink:** Share the identical in-memory model metadata rename loop between `rename_pdb.pdb_model_info()` and `rename_pdb.pdb_model_code()`. One ordinary metadata transformation can serve both methods; retain their existing disk operation and return contracts. No transaction framework or new generic. **About 7 lines after adding the shared worker.** [rename_pdb.R](../R/rename_pdb.R), lines 65–97.

6. **shrink:** Remove the second numeric/finite/nonnegative/integer and zero-axis checks inside the `output_shapes` loop. The same selected axes were validated immediately above. Keep integer conversion and `validate_rstan_saved_coverage()`; shape completeness and unconstrained counts remain separate checks. **About 7 lines.** [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R), lines 717–750.

7. **shrink:** Replace the repeated lag-1 numerator/denominator calculations with the already-installed `posterior::autocorrelation(z)[2L]`. Preserve short-chain guards, strict errors, and report-mode `NA` values; the two callers intentionally present undefined results differently. **About 4 lines.** [utils_reference_posterior.R](../R/utils_reference_posterior.R), lines 214–218; [reference_draw_diagnostics.R](../R/reference_draw_diagnostics.R), lines 158–164.

8. **stdlib:** Replace hashing two source strings solely to compare them with `identical(mc1, mc2)`. This is the only executable `digest` use found, so its `Suggests` entry can also go if the newer version has not implemented fingerprints. The implementation guide's proposed hashing feature is not implemented in this snapshot. **One dependency and one DESCRIPTION line.** [pdb_compare_stan_models.R](../R/pdb_compare_stan_models.R), line 14; [DESCRIPTION](../DESCRIPTION), line 32.

9. **stdlib:** Replace `eval(parse(text = paste0("pdb_", obj$type)))` with ordinary function lookup using `get()`. No generated R expression is needed to select an existing constructor. **Same line count, less machinery.** [pdb.R](../R/pdb.R), line 140.

## Evidence and limits

Caller searches confirmed the unused helpers, empty runtime `required` arguments, and sole executable `digest` use. Read-only R probes confirmed the recovery stub returns `NULL`, prohibited reference metadata already fails the allowlist, native constructor lookup resolves the existing function, and the current lag-1 formula matches `posterior::autocorrelation()` on a finite varying-chain fixture. Edge cases must retain their existing checks when implementing that replacement.

No full test suite or database writes were run. Estimates concern implementation lines only, exclude test/documentation updates, and are not measured diffs. Keep public compatibility aliases, input validation, deferred diagnostics, and staging/rollback behavior. In particular, RStan and CmdStanR E-FMI calculations use different finite-sample conventions here; similar-looking bodies are not sufficient evidence to merge them.

## Follow-up: the importer's NULL policy argument

Reviewed the history from `0291a0f` through local HEAD `55e667e`, including `a52d05c2`. Unpublished or newer remote commits are not verified.

- `0291a0f` introduced `policy = NULL`. A supplied object was recorded as `method_arguments$diagnostic_policy`, but did not control acceptance.
- `a52d05c2` corrected that misleading behavior: non-NULL policies now raise an error, and the metadata no longer records them. It hardened the placeholder rather than introducing a working policy feature.
- `9c0848d` added the live internal `reference_draw_policy()`; `f96dbb0` refined its use in diagnostic evaluation. This centralizes package thresholds and remains useful. It does not consume the importer's public `policy` argument.
- At this HEAD, `new_import_reference_posterior_info()` accepts `policy` without reading it. A read-only probe confirmed that changing this helper's policy value changes nothing; the outer conversion rejects a custom policy before extraction.

**Decision needed:** explicitly decide whether acceptance policy should remain fixed or become caller-configurable. The maintainer expects the policy is very likely to remain unchanged; that expectation favors a fixed policy and removing the speculative public placeholder, subject to compatibility. A shared internal threshold definition remains useful even when the policy is fixed.

**Recommendation:** remove `policy` from the internal metadata constructor and its call now. If public compatibility matters, retain `policy = NULL` and its explicit rejection at the conversion boundary as a compatibility measure, without forwarding it farther. Remove the public argument only as an intentional API change: deleting it shifts later positional arguments in `import_reference_posterior_draws()`, and explicit `policy = NULL` calls would otherwise enter `...` and fail its metadata allowlist. Keep rejection of unsupported non-NULL values; silently accepting them would restore the original problem. Do not build configurable acceptance without a concrete requirement.

Sources: [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R), lines 69–85, 140–145, 262–284, and 870–898; [reference_draw_diagnostics.R](../R/reference_draw_diagnostics.R), lines 200–222. The earlier line estimate excludes this follow-up.

## Follow-up: S3 consistency and standalone functions

Requested separately from the complexity audit; this section includes S3 contract findings. It describes the same local HEAD `55e667e`, not unverified newer code.

**Assessment:** the overall design is reasonable: S3 at object/conversion/backend boundaries, ordinary functions for shared calculations and workflow orchestration. The implementation is not fully consistent. More generics alone would not resolve its main problems.

### Where additional dispatch could help

| Function | Current behavior | Recommendation |
| --- | --- | --- |
| `infer_unconstrained_parameter_counts_from_fit()` | Branches on `stanfit` versus `CmdStanMCMC` and uses substantially different backend APIs. | Strongest candidate for an S3 generic with backend methods, consistent with `extract_external_stan_fit()`. Keep selection validation and `unconstrained_parameter_counts()` shared; do not duplicate them into methods. This is organization/extensibility work, not an immediate behavior fix. |
| `link_reference_posterior()` | Accepts a character name or `pdb_posterior`, with a class branch for connection/name resolution. | Reasonable candidate for character and posterior methods, matching existing lookup APIs. Lower priority: two short adapters around the existing ordinary `link_reference_posterior_object()` worker suffice. Settle connection-argument behavior first; do not merely move the existing ambiguity into methods. |

Sources: [infer_posterior_dimensions.R](../R/infer_posterior_dimensions.R), lines 56–78; [link_reference_posterior.R](../R/link_reference_posterior.R), lines 14–40; [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R), lines 312–329.

### Functions that should remain ordinary

- `import_reference_posterior_draws()`, `reference_draw_diagnostics()`, and `passes_reference_draw_checks()` already delegate fit-specific behavior to generics. Adding another dispatch layer would repeat that boundary.
- `infer_posterior_dimensions()`, `compute_reference_posterior_draws()`, and `sequential_batch_workflow()` coordinate operations using backend/method options. Those options are values, not distinct object classes; manufacturing classes solely to dispatch on them would add machinery.
- `compute_reference_posterior_summary_statistic()`, numeric diagnostics, validators, metadata assembly, serialization, and staging/commit helpers implement shared work. Keep ordinary workers unless an actual class needs different behavior.
- `info()` and `info<-` correctly use a common attribute representation. Their location in `generics.R` does not make them S3 generics or require them to become generics. `posterior_names()` is also an ordinary public wrapper, but already reaches dispatch through `pn()`.

### Existing generics that may be more than needed

`framework()` has one attribute-getter method. Both `framework<-` methods perform the same validated attribute assignment, with one delegating to the other. Ordinary validated accessors could cover this representation, just as `info()` does. However, they are existing exported generics: changing them would remove extension points and requires a compatibility decision. Simplify the duplicated implementation first; do not break the public API solely to reduce the method count. See [model_code.R](../R/model_code.R), lines 164–193.

Likewise, a generic with one current method is not automatically wrong. `run_stan()` and `create_pdb_bundle()` are meaningful object operations. Keep established dispatch unless removing it has a concrete benefit.

### Fix consistency before expanding the object system

1. **Generic/method argument order — verified.** `tools::checkS3methods(dir = ".")` reports `create_pdb_bundle()` versus `create_pdb_bundle.stanfit()`. A read-only probe retaining the method's formals and substituting an argument-recording body confirmed that positional `added_by` and `added_date` bind to `model_code` and `posterior`. Align common arguments and their defaults; deliberately place method-specific options afterward. [create_pdb_bundle.R](../R/create_pdb_bundle.R), lines 115–143.
2. **Calls that bypass dispatch — source-confirmed.** Internal sampling/model comparison call `run_stan.pdb_posterior()` directly, and linking calls `posterior.character()` directly. Use their generics where overrides should apply. If bypass is intentional, make that contract explicit and prefer a clearly named ordinary worker for shared implementation. Do not automatically replace every direct method call. [compute_reference_posterior_draws_stan_sampling.R](../R/compute_reference_posterior_draws_stan_sampling.R), line 41; [pdb_compare_stan_models.R](../R/pdb_compare_stan_models.R), line 17; [link_reference_posterior.R](../R/link_reference_posterior.R), lines 26–30.
3. **Method registration — source-confirmed.** `thin_draws.pdb_reference_posterior_draws()` is exported but has no `S3method` registration for `posterior::thin_draws`. Register it and verify namespace-qualified dispatch in a fresh installed-package process; exporting or calling the method directly does not verify that contract. [reference_posterior.R](../R/reference_posterior.R), line 318; [NAMESPACE](../NAMESPACE).
4. **Subclass assumptions — partly reproduced.** `pdb_type()` derives type from `class(x)[1]`; a read-only probe with classes `c("custom_connection", "pdb_local", "pdb")` returned `"connection"`. Serialization also allowlists the first class, while subset/thinning remove it. Decide which classes support subclasses and use inherited-class checks or the appropriate next method consistently. [pdb.R](../R/pdb.R), lines 339–340 and 670–671; [reference_posterior.R](../R/reference_posterior.R), lines 273–278 and 318–322.
5. **Mixed return contracts — source-confirmed.** `pdb_endpoint.pdb_local()` returns an updated connection during initial resolution but a path string once resolved; the GitHub method returns a connection. Give endpoint setup and endpoint access clear, stable contracts using the existing setup boundary. [pdb.R](../R/pdb.R), lines 151–160 and 361–378; [pdb_github.R](../R/pdb_github.R), lines 110–119.
6. **Parallel conversion APIs — clarify, do not blindly merge.** `as.reference_posterior_draws()` wraps draws with supplied metadata; `as_reference_posterior_draws()` performs fit import, dimension validation, diagnostics, and checks. Their similar names conceal different contracts. Document one preferred entry point per task and share genuinely common construction code while preserving public aliases and validation. [reference_posterior.R](../R/reference_posterior.R), lines 159–203; [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R), lines 28–170.

Verification was read-only: the S3 signature checker, source/registration/caller inspection, and isolated positional/subclass probes. No package code or database was changed. Different method defaults alone were not treated as defects; methods can legitimately supply defaults for arguments introduced by a generic. No installed-package dispatch test was run in this follow-up. The earlier line estimate excludes this section.

### Package-wide S3 work to document and complete

**Documentation-only task:** implement none of these changes until the maintainer selects scope. The findings above identify current inconsistencies; this checklist defines the follow-up needed to make S3 use consistent throughout the package. It does not claim the package is already consistent.

Cover every current generic family, including private generics and aliases:

| Family | Generics and methods to review |
| --- | --- |
| Connections and storage | `pdb`, `setup_pdb`, `pdb_version`, `pdb_endpoint`, `is_pdb_endpoint`, `pdb_file_path`, `pdb_file_copy`, `pdb_assert_file_exist`, `pdb_cache_dir`, `pdb_cache_rm`, `read_info_json` |
| Names and object lookup | `pn` / `posterior_names`, `model_names`, `data_names`, `reference_posterior_names`, `posterior`, `data_info`, `model_info`, `get_data`, `model_code`, `data_file_path`, `model_code_file_path` |
| Coercion and fit boundaries | `as.posterior`, `as.data_info`, `as.model_info`, `as.pdb_data`, `as.model_code`, `as.reference_posterior_info`, `as.reference_posterior_draws`, `as_reference_posterior_draws`, `extract_external_stan_fit`, `create_pdb_bundle` |
| Reference lookup and checks | `reference_posterior_info`, `reference_posterior_draws`, `reference_posterior_draws_file_path`, `reference_posterior_summary_statistic`, `reference_posterior_summary_statistics`, `check_reference_posterior_draws`, `check_summary_statistics_draws`, `assert_checked_reference_posterior_draws`, `assert_checked_summary_statistics_draws` |
| Operations and accessors | `run_stan`, `write_pdb`, `remove_pdb`, `rename_pdb`, `append_reference`, `framework`, `framework<-` |
| Methods for external generics | All package `print`, `summary`, `subset`, and `as.data.frame` methods, plus `posterior::thin_draws` |

- [ ] Agree on one rule: dispatch when an object's class changes the operation; keep uniform calculations, validation, and orchestration as ordinary functions. Decide the fit-dimension and linking candidates above explicitly. Do not add generics merely to match a naming pattern or remove established ones solely because they currently have one method.
- [ ] Inventory each generic's dispatch argument, supported classes, methods, public aliases, and namespace registration. Confirm aliases reach the intended generic and preserve argument handling. Give unsupported classes an intentional, understandable failure; add default methods only where they improve the existing contract.
- [ ] Align common argument names and positions across each generic/method pair. Document intentional default differences and keep method-specific options unambiguous. Check named, positional, omitted, and explicit-NULL calls through the public generic. Fix the known bundle signature mismatch first.
- [ ] Define connection precedence consistently for name inputs, attached objects, and standalone objects: whether an explicit `pdb` overrides an attached connection, and when a default connection is used. Audit constructors that accept `pdb` through `...`; the draws-list coercion currently accepts but does not attach it. Do not silently drop an accepted connection.
- [ ] Audit `...` and option forwarding end to end, including convenience wrappers. Forward supported arguments to the intended layer or explicitly reject unsupported ones. Preserve backend-specific arguments and metadata; do not forward package metadata into samplers.
- [ ] Specify each operation's result class, attributes, visibility, and side effects. Stabilize endpoint setup/access returns. Ensure coercion, lookup, and mutation preserve the appropriate connection/metadata while serialization writes only the persisted representation. An unchecked object and a checked object must retain their documented distinction.
- [ ] Decide subclass support for each object family. Review first-class indexing, class replacement/removal, and direct method calls against that decision. Preserve intended subclass overrides and base representations; do not append classes indiscriminately.
- [ ] Register methods for both package and external generics using roxygen and regenerate `NAMESPACE`. Verify namespace-qualified public calls in a fresh installed-package subprocess without attaching this package; include `posterior::thin_draws` and alias entry points.
- [ ] Document the different wrapping/import conversion APIs and choose the preferred public entry point for each task. Consolidate shared workers where contracts match; preserve existing public names or retire them deliberately.
- [ ] Complete `tools::checkS3methods(dir = ".")` and focused contract checks in disposable fixtures. Exercise both connection backends and supported fit classes, and subclasses where promised. Use mocks/read-only checks for dispatch where possible; keep filesystem tests isolated from the maintainer's database. Treat the checker as a signature check, not proof of forwarding, registration, return, or subclass consistency.

This package-wide work is a recorded to-do list, not an implementation or an estimate of additional deletions. It preserves the fixed-policy decision recorded above.

### Clarify the import writer's failure handling

`new_import_reference_posterior_info()` constructs metadata only. `write_imported_reference_posterior_draws()` is a separate function in the same file, not a writer inside that constructor.

The current import flow is:

1. Convert the fit and calculate diagnostics. If acceptance checking raises an error, return an in-memory candidate with `checks_made$check_failed` so the caller can inspect it.
2. With `write = FALSE`, return that candidate without persistence.
3. With `write = TRUE`, stop on `check_failed`, then require all acceptance flags before calling the import writer. The writer repeats those guards before staging or changing database files.
4. For accepted draws, stage metadata, draws, optional summaries, and the required posterior record; verify and install the files. If installation or final verification fails, remove newly installed files and attempt to restore the original backups. Restoring originals is rollback, not saving a failed candidate.

- [ ] Document this distinction at the public importer and internal writer: failed diagnostic candidates are inspectable in memory but cannot be persisted by this path; filesystem failures trigger recovery of the previous database state. Explain that the import writer coordinates a multi-file operation around ordinary `write_pdb()` methods. Retain the writer's acceptance guard and backup recovery; simplify duplicated caller checks only if useful early error messages and write-boundary protection remain intact.

Source: [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R), lines 157–169, 262–310, 870–898, and 911–1077. The existing test at [test-import-external-stanfit.R](../tests/testthat/test-import-external-stanfit.R), lines 205–225, checks that a failed candidate is returned with `write = FALSE`, raises with `write = TRUE`, and creates no reference-posterior directory. That test was inspected, not rerun in this follow-up.

**Commit-specific clarification (`a52d05c2`):** the import writer already existed in its parent commit, including the `check_failed` rejection. This commit added an early rejection in the public importer, linked-posterior handling, and stronger rollback tracking. In this version the writer handles reference info/draw files and an optional posterior update; summary-statistic writing belongs to later versions. Its `failure` guard (lines 419–423 in that commit) stops before any writes when diagnostic checks failed. `committed <- FALSE` (line 483) means successful completion has not yet occurred, not that the draws failed diagnostics. `on.exit()` registers cleanup to run when the function exits: if completion failed, it removes paths tracked in `installed` and attempts to restore backups. After successful verification and cleanup, line 529 sets `committed <- TRUE`, so rollback is skipped. Keep these two failure concepts explicit in the documentation; do not describe rollback as persisting rejected draws.

## Follow-up: what remains after `16cdd444` and later fixes

Rechecked local history through `55e667e` on 2026-10-01. This section records
remaining concerns from the Stan-workflow discussion, including correctness
and test coverage requested separately from the original complexity audit.
It does not treat historical defects as current defects. Recheck the newer
development checkout before implementing these tasks.

### Improvements already present

- `9c0848d` fixed the import staging regression introduced in `16cdd444` by
  removing the premature assignment to the linked posterior's reference name.
  That assignment had prevented the shared linker from writing the staged
  posterior JSON. The historical failure was reproduced in a disposable
  snapshot; it is not an outstanding task at this HEAD.
- `9c0848d` centralized acceptance thresholds in `reference_draw_policy()`.
  `f96dbb0` refined diagnostic evaluation, and bundle workflows reuse the
  normalized diagnostic-report boundary. `48b10ac` added deferred bundle
  checks while retaining the sampler inputs needed for them.
- `06e403c` added the sequential workflow. It explicitly checks reference
  draws whenever `check` or `write` is true, before writing. The fact that
  `compute_reference_posterior_draws()` alone calculates diagnostics without
  recording acceptance is not evidence that the complete workflow omits
  validation. See [batch_workflow.R](../R/batch_workflow.R), lines 99–119.
- `a5d2a9e` changed dimension inference to unconstrained parameter counts and
  removed sampling from the RStan branch. `aea2548` restricted RStan count
  evidence to model parameters. Do not revive the old shape-based design or
  report its CmdStanR indexed-name problem as the current implementation.
- Later commits added substantial diagnostic, extraction, bundle, deferred
  checking, and fixture coverage. The absence of tests in `16cdd444` itself
  does not describe the current test suite.

### Remaining tasks, in priority order

1. **Sampling argument translation — confirmed behavior concern.**
   `translate_cmdstanr_sampling_args()` copies only `adapt_delta` and
   `max_treedepth` from nested `control`, then discards that list. Other
   requested controls can silently disappear; a probe confirmed that
   `control$stepsize` is dropped. Translate supported controls and explicitly
   reject unsupported controls. Resolve conflicting aliases deliberately;
   do not add a general configuration framework. Add a small argument-level
   regression check. Source: [run_stan.R](../R/run_stan.R), lines 46–78.

2. **Complete shared diagnostic ownership — partial consolidation remains.**
   Thresholds already have one owner. Internal sampling and external
   conversion still calculate through `compute_stan_sampling_diagnostics()`,
   while direct-fit reports and bundle checks use
   `reference_draw_diagnostics_from_extracted()`. Lag-1 calculations appear
   in two places; stored-draw acceptance and report acceptance also evaluate
   metrics through separate code. Reuse existing workers for compatible
   calculations and applicable-check evaluation. Preserve selective checks,
   informational ESS, named variables/chains, stored flag compatibility,
   failure presentation, and method-specific applicability. Retain intentional
   finite-sample E-FMI conventions. This is a maintenance/design concern,
   not a claim that all paths currently yield different thresholds or results.
   Sources: [compute_reference_posterior_draws_stan_sampling.R](../R/compute_reference_posterior_draws_stan_sampling.R),
   lines 125–207; [reference_draw_diagnostics.R](../R/reference_draw_diagnostics.R),
   lines 35–98 and 152–197; [utils_reference_posterior.R](../R/utils_reference_posterior.R),
   lines 104–227; [create_pdb_bundle.R](../R/create_pdb_bundle.R), lines 631–688.

3. **Strengthen focused regression coverage.** Keep the useful unit and
   rollback tests. Tighten mock argument assertions, compare all persisted
   variables/chains, add limited genuine CmdStanR and constrained-parameter
   coverage, and assert that failed creation leaves no new reference files.
   The current fake CmdStanR test exercises conversion and development-loaded
   dispatch; it does not read actual CSV files. Installed-package dispatch
   also needs separate verification where promised. Detailed findings,
   historical commits, and the 34 passing focused test blocks plus one skip
   are in [the test-suite review](ponytail-test-suite-review.md). Add targeted
   checks rather than duplicating a full suite for each workflow.

4. **Unify compatible fit extraction and clarify its name.** The internal
   computation path uses `extract_external_stan_fit()` for CmdStanR and an
   older direct RStan path for RStan. Reusing extraction for an internally
   created fit is appropriate: the fit interface depends on its backend,
   not who sampled it. Consider routing both through the existing extractor
   and renaming the internal boundary to reflect that shared responsibility.
   Preserve supplied `rpi` metadata and documented checking behavior; do not
   blindly call the full public importer, which creates import metadata and
   has additional orchestration responsibilities. This is a consolidation
   opportunity, not a defect caused by using an “external” helper internally.
   Source: [compute_reference_posterior_draws_stan_sampling.R](../R/compute_reference_posterior_draws_stan_sampling.R),
   lines 41–83; [import_reference_posterior_draws.R](../R/import_reference_posterior_draws.R),
   lines 69–169 and 312–329.

5. **Resolve the public NULL policy placeholder without changing acceptance.**
   `policy = NULL` already applies the standard package acceptance rules;
   it does not disable checks. Non-NULL policies are rejected. The real
   internal policy is shared, while the metadata constructor's forwarded
   `policy` remains unused. Follow the compatibility decision documented
   above: remove unused internal forwarding, and decide whether to retain
   the public placeholder for existing callers. The maintainer expects the
   acceptance rules are very likely to stay unchanged. Configurable policies
   are not a requested feature.

6. **Assess remaining CmdStanR dimension-discovery cost — low priority.**
   The RStan source/data branch now compiles without sampling, but the
   CmdStanR branch still compiles and runs a short fit before inferring counts.
   This is a documented cost and sampling dependency, not a reproduced
   correctness defect. Prefer count inference from an available completed
   fit. Investigate a supported sampling-free source/data route only if a
   concrete workflow requires it; avoid speculative backend machinery.
   Source: [infer_posterior_dimensions.R](../R/infer_posterior_dimensions.R),
   lines 18–46.

This follow-up changes documentation only. It does not alter acceptance rules,
implementation, tests, or the original estimated line savings.

net: -85 lines, -1 deps possible (conservative estimate).
