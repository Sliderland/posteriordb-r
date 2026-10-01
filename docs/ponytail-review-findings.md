# Ponytail review: fix existing contracts before expanding the Stan workflows

Reviewed on 2026-10-01 against the local working checkout.

## Overall opinion

The guides are thoughtful and mostly point in the right direction. Their strongest recommendations are to reuse extraction and assembly, keep unconstrained counts separate from saved output shapes, preserve acceptance rules, and describe missing historical evidence honestly.

I would use them as a menu of independently reviewable changes. Implementing every recommendation together would be a large expansion, not a parsimonious cleanup. The best immediate return is fixing existing public contracts and consolidating duplicated diagnostic behavior. New backend support and input fingerprints should follow concrete workflow demand.

Documents reviewed:

- [Agent review and consolidation brief](../doc/AGENT_REVIEW_GUIDE.md).
- [Three Stan workflow implementation proposals](implementation-guide-stan-workflow-gaps.md).
- [Current bundle workflow guide](../doc/CREATE_PDB_BUNDLE.md), with its Rmd source checked for context. This is generated documentation; future edits belong in the Rmd.

There is one recent implementation guide in `docs/`; the other recent briefs are in `doc/`. This findings file intentionally stays in `docs/`.

## Changes I would prioritize

“Reproduced” below means a probe run during this review. “Source-confirmed” means the relevant implementation was inspected, without reproducing the complete failing workflow. These labels do not inherit the earlier guide's test claims.

| Priority | Finding and evidence | Smallest useful change |
| --- | --- | --- |
| First: persisted integrity | **Thinning preserves obsolete acceptance evidence — reproduced.** A checked fixture became 5,000 draws while metadata still said 10,000; `assert_checked_reference_posterior_draws()` still passed. See `thin_draws.pdb_reference_posterior_draws()` in [reference_posterior.R](../R/reference_posterior.R) and [assert_checked_draws.R](../R/assert_checked_draws.R). | Update retained counts and invalidate checks that depend on changed draws. Check actual counts at the draw-object acceptance boundary. Preserve useful analysis transformations without automatically rerunning every metric. |
| First: persisted integrity | **Failed bundle candidates can leave dangling reference links — source-confirmed.** Assembly assigns a reference name; the bundle writer writes the posterior even when reference draws are skipped. See [create_pdb_bundle.R](../R/create_pdb_bundle.R) and [write_pdb.R](../R/write_pdb.R). | Persist a candidate reference link only when its referenced files exist or are successfully written. Preserve valid existing links. Keep the documented ability to save data/model/posterior components after diagnostic failure. |
| First: file recovery | **Rollback can discard the only backup — source-confirmed.** Rename rollback ignores restoration results and then deletes its backup directory. Bibliography cleanup also removes a backup after an unchecked restore. See `rename_pdb_commit()` in [rename_pdb.R](../R/rename_pdb.R) and `append_bibliography_atomically()` in [bibliography.R](../R/bibliography.R). | Retain backups when restoration fails, report their paths, and check filesystem operation results. Reuse the import writer's more cautious recovery pattern where its contract fits. |
| First: write boundaries | **Resource identifiers are not consistently restricted to filenames — source-confirmed.** `pdb_write_output_path()` accepts a string name and interpolates it into a path; linking/renaming already apply stronger restrictions. See [pdb.R](../R/pdb.R). | Reuse a narrow resource-name validator at shared write boundaries and verify destination containment before mutation. Keep implementation paths distinct from resource names; preserve ordinary hyphens and dots. |
| Next: cheap correctness | **Generic and method positional arguments disagree — reproduced.** `create_pdb_bundle(fit, list(), "Reviewer", Sys.Date(), pdb = connection)` attempted to read `models/stan/Reviewer.stan`. `tools::checkS3methods(dir = ".")` also reported the mismatch. See [create_pdb_bundle.R](../R/create_pdb_bundle.R). | Align common generic/method arguments before extracting shared constructor orchestration. Check named and positional calls; assess direct-method compatibility explicitly. |
| Next: cheap correctness | **Conversion silently drops its supplied database connection — reproduced.** The draws-list constructor accepts `pdb` through `...` but does not attach it. Both fit conversion routes use it. See `as.reference_posterior_draws.draws_list()` in [reference_posterior.R](../R/reference_posterior.R). | Preserve an explicitly accepted connection in this shared constructor rather than repairing each caller. |
| Next: cheap correctness | **Bibliography failure can still produce successful database status — reproduced with an isolated failing checker.** `check_pdb()` returned `0`; its last `try()` result is never assigned to `res`. See [check_pdb.R](../R/check_pdb.R). | Assign that result. A new general-purpose check runner is unnecessary for this bug. Clarify the documented boolean versus implemented integer return contract separately. |
| Next: cheap correctness | **Ordinary writes leave cached metadata stale — reproduced in a disposable database.** After overwriting a title, disk contained `After` while `data_info()` returned `Before`. See [write_pdb.R](../R/write_pdb.R), [remove_pdb.R](../R/remove_pdb.R), and cache readers in [pdb.R](../R/pdb.R). | Invalidate affected cached files after successful shared writes/removals. Include cached unzipped payloads, not just metadata, and check directory-derived listings. |
| Next: backend correctness | **CmdStanR settings and version metadata are inconsistent — reproduced.** Translation discarded `control$stepsize`; `cores = 2` replaced explicit `parallel_chains = 8`. The internal CmdStanR version helper's result failed its own downstream metadata validator because session/Makevars fields were missing. See [run_stan.R](../R/run_stan.R) and [compute_reference_posterior_draws_stan_sampling.R](../R/compute_reference_posterior_draws_stan_sampling.R). | Translate supported settings or reject unsupported/conflicting ones. Share backend-aware version construction that satisfies the existing schema and distinguishes current import versions from historical sampling evidence. |

These are correctness changes with direct simplification benefits: fewer caller-specific repairs and fewer contradictory contracts. They are worth doing even if none of the three proposed features ships.

Before running broad checks, make the mutating tests disposable. Older write/contribution tests call `pdb_local()` against the default database, and `tests/testthat.R` clones a database only when no path is configured. A configured maintainer database is therefore still exposed to those tests. Existing temporary fixture patterns are sufficient; a new testing framework is unnecessary.

## The best consolidation: diagnostics and acceptance

I agree with D1/D2 in the agent brief, with one qualification: consolidate calculations and applicable checks incrementally, keeping public report/metadata formats as small adapters.

There are two lag-1 implementations in [utils_reference_posterior.R](../R/utils_reference_posterior.R) and [reference_draw_diagnostics.R](../R/reference_draw_diagnostics.R). On the same constant-chain fixture, the strict worker threw an error while the report worker returned `NA`. Those presentations can both be useful; the underlying formula should have one owner. Let a shared calculation return named values, with strict/report callers deciding how to present undefined results.

Thresholds already have one source in `reference_draw_policy()`. Reuse it. The remaining duplication is in applicability, evaluation, and mapping results into stored flags. I reproduced the analytical-draw defect: the checker skips HMC calculations but its final assertion still demands an HMC chain flag. One method-aware definition of required checks should govern checking and writer assertions; analytical draws should not receive invented HMC successes.

Do not casually merge the E-FMI formulas. The RStan compatibility path and the other path use different finite-sample normalization. Establish the intended behavior before sharing the calculation. Likewise, preserve selective diagnostics: requesting lag-1 alone should not fetch energy or compute ESS.

The useful target is small: backend extraction, shared numeric workers, shared applicable-check evaluation, and existing presentation adapters. No diagnostic engine class, backend registry, or generic for every helper is needed. A deterministic fixture comparing applicable workflows is more valuable than many tests repeating private implementation branches.

## Opinion on each implementation proposal

### Archived RStan recovery: the strongest first feature

This reuses capability the bundle adapter already has. I support explicit `recompile = FALSE` for existing-posterior imports, a lazy live-fit fast path, a source match before recovery, and an origin marker outside sampler arguments.

The important cleanup is narrowing the bundle's current fallback: `extract_rstan_fit_for_bundle()` catches every count-inference error and recompiles whenever data is available. That can conceal inconsistent count evidence. Start with the known missing-instance condition; add other safely distinguishable unavailable-instance cases only with evidence. Invalid counts should remain errors.

One private count-recovery helper shared by bundle/import paths is justified. Keep the public count function's return value unchanged. Recovery must use the RStan zero-chain path; the existing CmdStanR source/data inference path samples briefly and is unsuitable here. Recovery does not establish what data produced the archived draws.

### CmdStanR bundles: useful backend parity, conditional on demand

The proposed thin S3 method and common orchestration are sensible. `assemble_standalone_fit_bundle()` already consumes a backend-neutral record; duplicating it or its writer would create unnecessary maintenance.

Fix the constructor's positional mismatch before moving its argument handling. Preserve deferred raw diagnostics and selected output order. The adapter must distinguish saved outputs from unconstrained model parameters.

I would retain the guide's shape-validation work. It is needed to preserve the existing coverage contract, even though it makes the adapter longer. Deriving expected coverage from the saved columns cannot detect a missing last element. The public [CmdStanModel variables API](https://mc-stan.org/cmdstanr/reference/model-method-variables.html) reports declaration rank and permits inspection without compiling a sampling executable; the [fit skeleton API](https://mc-stan.org/cmdstanr/reference/fit-method-variable_skeleton.html) supplies a restructuring skeleton. These support the proposed combination, but documentation does not establish every singleton/multidimensional case. A small real-fit check remains necessary.

The [CSV metadata example](https://mc-stan.org/cmdstanr/reference/fit-method-metadata.html) also shows four chain IDs alongside `num_chains = 1`, supporting the warning against treating that field as the total retained chain count.

Limit initial support to fits with the required source/model resources. Universal CSV reconstruction, include resolution, private R6 inspection, and an alternative parameter-count compiler API can wait for actual demand. Document possible compilation during model-method initialization, even though construction does not sample.

### Provenance: split the cheap comparison from the lasting hash contract

The guide states the guarantee correctly: consistency with available evidence. A caller-created record can be attached to the wrong fit, and freshly supplied target data cannot prove historical sampling inputs.

I would deliver normalized source comparison first, with unavailable source recorded honestly. Reuse `normalize_stan_model_code()` and keep its conservative text semantics. A harmless comment change can fail this comparison; explain that behavior rather than adding a semantic equivalence/compiler fallback.

Add optional data fingerprint capture only when the sampling/import workflow needs it. The full proposal adds capture arguments, record validation, numeric/JSON normalization, persistence, and destination re-verification. That is a versioned compatibility contract, not a tiny cleanup. Its complexity is justified if preventing accidental model/data misassociation is a real requirement.

If implemented, keep the narrow design in the guide: existing JSON representation, optional `digest`, one nested `inference$provenance` field, and comparisons against the actual write destination. Keep provenance out of `method_arguments`, which can be replayed into a sampler. Pin normalization and round-trip fixtures before promising the fingerprint scheme.

I would defer partial/“legacy” records in the new fingerprint scheme unless a concrete producer needs them. Existing records can simply omit provenance. There are no existing fingerprint records in the inspected code requiring migration, so speculative compatibility is avoidable. An evidence registry, signatures, sidecars, and verification modes are also unnecessary for the stated guarantee.

## Corrections and cautions for the guides

1. **The implementation guide's boundary table overstates bundle persistence.** Its “Stage, verify, and commit writes” row includes the bundle writer. The current bundle writer preflights and then writes sequentially; only the import writer has the staged/verified workflow discussed there. The current bundle usage guide describes this limitation accurately. Backend parity can reuse the writer, but must not inherit a transactional guarantee it does not provide.
2. **The newer include/exclude correction is an assumption, not locally verified code.** The implementation guide explicitly assumes another version exists. Reconcile with that version before changing selection or asserting regression coverage; avoid implementing a competing policy in this checkout.
3. **Separate defects from API choices.** Dotted draws coercion and underscore fit import have different responsibilities. Compatibility wrappers can remain while shared internals improve. Similarly, subclass support, stronger mandatory provenance, and zero-free-coordinate parameters need explicit contracts rather than mechanical “cleanup.”
4. **Use existing mappings instead of adding new machinery.** Framework file extensions already have a helper. Posterior links are already metadata: read them instead of splitting filenames at hyphens. Listing should remove the expected suffix, not everything after the first dot. I reproduced `model.v2.info.json` becoming `model`; source inspection also confirmed the incorrect summary listing path and model-info lookup returning all posterior names.
5. **Document existing strengths.** Keeping failed candidates inspectable, construction in memory, separate counts/shapes, and optional backends are good decisions. Preserve those rather than replacing the whole object model.

## Suggested delivery sequence

1. Make the affected mutating tests use disposable fixtures, then fix persistence integrity, rollback backup retention, and write-name boundaries in focused changes.
2. Fix the small public-contract defects: positional dispatch, connection retention, bibliography status, cache invalidation, settings translation, and metadata construction.
3. Consolidate one diagnostic calculation and applicable acceptance checks at a time, with comparisons on the same draws/sampler inputs.
4. Add archived RStan recovery if needed; add CmdStanR bundles if needed. Neither requires a full provenance framework.
5. Add source comparison, then optional fingerprint capture as separate reviewed work with a pinned representation contract.

This sequence changes where behavior is owned before adding more consumers. It also gives useful stopping points: the package becomes more consistent even if feature work stops after cleanup.

## Verification performed and limits

I loaded the local package with `pkgload::load_all()` and ran small probes for positional dispatch, connection loss, analytical checking, thinning evidence, settings translation, version validation, constant-chain lag behavior, multi-dot names, cached metadata, and database-check failure propagation. The bibliography probe injected one failing checker while making unrelated checks succeed; it establishes status propagation, not real bibliography parsing.

The cache probe wrote only to a disposable temporary database and cleaned it up. I also ran `tools::checkS3methods(dir = ".")`, which reported the constructor mismatch. Four small matrix/array JSON cases with singleton axes round-tripped consistently through the writer's serialization settings and simplified JSON loading. Those cases do not prove the proposed fingerprint normalization contract.

No full test suite, package check, installed-package registration test, or real Stan compilation/sampling was run. Persistence failure and path-boundary findings above are source-confirmed, not fault-injected reproductions. The earlier guide's 264 passing assertions were not rerun or counted as this review's results. This review changes only this findings document.
