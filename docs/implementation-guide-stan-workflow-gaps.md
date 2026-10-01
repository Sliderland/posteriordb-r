# Implementation guide: three focused Stan workflow improvements

This document specifies three separate changes to `posteriordb`:

1. Construct standalone PosteriorDB bundles from CmdStanR MCMC fits.
2. Record and compare model/data provenance when importing fits into existing posteriors.
3. Recover unconstrained parameter counts when importing archived RStan fits whose compiled model instance is unavailable.

The guide is based on the local checkout reviewed on 2026-10-01. Function names describe that checkout, not necessarily the unpublished version. The include/exclude correction discussed separately is assumed to exist in that newer version. Preserve its behavior; do not implement a competing selection policy here.

These are implementation proposals, not descriptions of completed features. Each feature should be delivered separately, using the existing extraction, assembly, checking, and writing code. No changes to acceptance thresholds, sampling algorithms, draw thinning, database naming, or overwrite rules are needed.

## 0. Read these existing boundaries first

| Responsibility | Existing code to reuse |
| --- | --- |
| Resolve bundle inputs, metadata, and existing components | `create_pdb_bundle.stanfit()` in `R/create_pdb_bundle.R` |
| Assemble linked objects from an extracted fit | `assemble_standalone_fit_bundle()` in the same file |
| Read post-warmup draws, sampler diagnostics, and sampling metadata | `extract_external_stan_fit()`, `extract_rstan_fit()`, and `extract_cmdstanr_fit()` in `R/import_reference_posterior_draws.R` |
| RStan bundle-specific source, shape, method, and coverage validation | `extract_rstan_fit_for_bundle()` in the same file |
| Infer and validate unconstrained parameter counts | `infer_unconstrained_parameter_counts_from_fit()`, `infer_posterior_dimensions()`, and `validate_posterior_dimension_counts()` in `R/infer_posterior_dimensions.R` |
| Validate selected scalar coverage | `validate_rstan_saved_coverage()` in `R/import_reference_posterior_draws.R` |
| Validate ordinary Stan input values | `validate_stan_input_data()` in `R/create_pdb_bundle.R` |
| Normalize source for conservative text comparison | `normalize_stan_model_code()` in the same file |
| Import into an existing posterior | `as_reference_posterior_draws_external()` and `import_reference_posterior_draws()` in `R/import_reference_posterior_draws.R` |
| Apply reference acceptance checks | `reference_draw_diagnostics_from_extracted()`, existing reference-draw check methods, and `reference_draw_policy()` |
| Stage, verify, and commit writes | Existing bundle writer in `R/write_pdb.R` and `write_imported_reference_posterior_draws()` |
| Run a known model with known inputs | `run_stan.pdb_posterior()` in `R/run_stan.R` |

Before editing, inspect the current branch's equivalents and tests. Avoid moving large blocks merely to match the names proposed below.

### Invariants shared by all three changes

- `posterior$dimensions` contains positive integer **unconstrained parameter counts**, keyed by model parameter base name. It is not a list of saved output shapes.
- Output shapes and draw selection are separate. A selected transformed parameter or generated quantity does not acquire a fictitious unconstrained count.
- A simplex of length `K` saves `K` scalar outputs but has `K - 1` unconstrained coordinates. Similar distinctions apply to covariance and correlation objects.
- Preserve draw values, variable order, chain order, iteration order, and post-warmup boundaries. Do not merge runs, resample, or thin during import.
- Inference settings and diagnostics must describe the saved fit. Current installed package versions describe the import environment unless the fit supplies historical evidence.
- A failed or unchecked candidate does not become writable merely because a new backend or provenance check was added.
- Construction and conversion remain in memory. Database writes continue through existing writers.
- A dimension match is a structural consistency check. It is not proof that a model and dataset produced a fit.

## 1. Standalone bundles from CmdStanR MCMC fits

### 1.1 Problem and intended behavior

CmdStanR is supported by sampling, diagnostics, and import into an existing posterior. However, the standalone bundle constructor dispatches only to `create_pdb_bundle.stanfit()`.

Add a `create_pdb_bundle.CmdStanMCMC()` method. Given a completed HMC fit, the actual Stan input list, and the same metadata accepted by the RStan method, it should return the same `pdb_reference_bundle` structure and use the same acceptance and persistence workflows.

The first implementation supports ordinary `CmdStanMCMC` objects with usable source and model-method resources. A CSV-reconstructed object lacking these resources should fail with a precise explanation. Do not expand this change into universal reconstruction from arbitrary CSV files.

Illustrative call using the existing public argument names:

```r
bundle <- create_pdb_bundle(
  fit,
  data = stan_inputs,
  data_info = list(name = "study", title = "Study inputs"),
  model_info = list(name = "normal", title = "Normal model"),
  include = c("mu", "sigma", "prediction"),
  check = FALSE
)
bundle <- check_reference_posterior_draws(bundle)
```

The presence of CmdStanR in `Suggests` is appropriate. RStan-only users must not need CmdStanR or CmdStan installed.

### 1.2 Smallest useful refactor

The current RStan method combines backend-independent input resolution with a backend-specific extraction call. Extract the common orchestration into one private helper, for example `create_pdb_bundle_from_stan_fit()`. Keep both public methods as thin wrappers with matching argument defaults.

Move the existing resolution and metadata validation statements unchanged where practical. At the existing extraction call, select one of two adapters:

```r
# Pseudocode: forward the existing arguments explicitly.
extracted <- if (inherits(fit, "stanfit")) {
  extract_rstan_fit_for_bundle(
    fit, strict = FALSE, compute_diagnostics = check,
    include = include, exclude = exclude, data = data
  )
} else {
  extract_cmdstanr_fit_for_bundle(
    fit, strict = FALSE, compute_diagnostics = check,
    include = include, exclude = exclude, data = data
  )
}
```

Only the two registered public methods call this helper; validate the class before using the fallback branch. A third backend should still hit the public unsupported-class method. No backend registry, new public extraction API, or plugin mechanism is necessary.

Keep `assemble_standalone_fit_bundle()` backend-neutral. It must not read RStan slots or call CmdStanR methods. Its existing extraction-record contract is sufficient:

```r
list(
  draws = draws_array,                  # Selected, constrained saved outputs
  sampler_diagnostics = sampler_array,  # Same iterations and chains, or NULL
  metadata = sampling_metadata,
  source = stan_source_string,
  dimensions = parameter_counts,        # Selected model parameters only
  output_shapes = selected_shapes,
  fit_class = "CmdStanMCMC",
  import_versions = import_versions
)
```

Do not duplicate the assembly method or writer for CmdStanR.

### 1.3 CmdStanR extraction steps

Implement a private `extract_cmdstanr_fit_for_bundle()` beside the RStan adapter.

1. Validate the fit class, `strict`, `compute_diagnostics`, and selection arguments with existing validators.
2. Obtain raw CSV metadata once for bundle-specific validation. Keep it separate from the normalized `metadata` list returned by `extract_cmdstanr_fit()`, which currently discards some raw fields. If duplicate metadata access becomes an issue, add one private optional raw-metadata input to the existing extractor; do not add a public metadata cache.
3. Require completed HMC sampling. Check raw method/algorithm evidence, retained chains, and, where available, return codes and per-chain identifiers. Reject fixed-parameter sampling and non-MCMC objects even if their class or draw shape looks acceptable. A fit with a failed chain must not silently become a bundle containing only successful chains.
4. Read source using the public `fit$code()` method. Join its lines with `"\n"`, validate nonempty source, and apply the existing self-contained-source restriction. Reuse the RStan policy for unresolved `#include`; do not add an include resolver in this feature. [CmdStanR source API](https://mc-stan.org/cmdstanr/reference/fit-method-code.html)
5. Read post-warmup draws and normalized sampling metadata through `extract_cmdstanr_fit()`. Do not parse CSV files again or manually reshape their values.
6. Obtain declared constrained output shapes from the fit's model-method metadata through a public API, using `fit$variable_skeleton(transformed_parameters = TRUE, generated_quantities = TRUE)` where supported. Establish the supported API behavior with a real-fit test before relying on it. This method can initialize model methods and require compilation resources; it is not necessarily a cheap CSV-only accessor. [Variable skeleton API](https://mc-stan.org/cmdstanr/reference/fit-method-variable_skeleton.html)
7. Apply the existing include/exclude policy to base names. Validate all scalar outputs of each selected variable against its declared shape, then subset once with `regex = FALSE`, preserving saved variable order.
8. Reuse `infer_unconstrained_parameter_counts_from_fit(fit)` for parameter counts. Intersect the resulting count map with selected model parameter names. Never pass selected generated quantities into the unconstrained-count selector.
9. Return the existing extraction-record shape and call the existing assembly helper.

Use the public CmdStanR APIs documented for the supported version. Do not inspect private R6 environments or assume RStan slots exist.

### 1.4 Shape validation: avoid circular checks

Raw CSV metadata includes saved variable names and sizes, but those fields alone do not independently prove that a variable was saved completely. Inferring an array's expected size from its largest saved index would accept a truncated array missing its last row. The raw field `stan_variable_sizes` is also not a list of full declared array axes. [CSV metadata API](https://mc-stan.org/cmdstanr/reference/fit-method-metadata.html)

Use model-declared shapes, not the saved columns themselves, as the expected coverage source. Reuse `validate_rstan_saved_coverage()`; its logic is about scalar names and axes, not RStan internals. Either keep the current private name or rename it once to `validate_saved_scalar_coverage()` and update both callers and tests. Do not maintain two implementations.

The skeleton-to-axes conversion needs special care:

- Scalar: `integer()`.
- Vector: its declared length as a one-element integer vector.
- Matrix or array: declared dimensions in Stan index order.
- A vector of length one remains shape `1L`; it must not become a scalar.
- Singleton axes in arrays must be preserved.
- Zero-sized declarations follow the existing explicit-exclusion behavior.
- The currently reviewed CmdStanR skeleton implementation represents both a scalar and a length-one vector as an array with dimension `1`. Therefore, `dim()` alone is insufficient too. Combine the skeleton with public declaration-rank metadata as described below.
- Do not flatten tuple-like or nested representations into invented axes. Report unsupported metadata clearly until a separate change supports them.

Obtain declaration ranks with the public `CmdStanModel$variables()` API. Create a temporary model object from the already retrieved self-contained source using `cmdstanr::write_stan_file()` and `cmdstanr::cmdstan_model(..., compile = FALSE)`. This uses the Stan frontend for declaration inspection without compiling a sampling executable. It is a temporary inspection object, not another fit. Flatten only the `parameters`, `transformed_parameters`, and `generated_quantities` blocks into a named declaration map; fields such as `included_files` are not output declarations. Its `dimensions` field is the **number of axes**, not their lengths. [Public declaration API](https://mc-stan.org/cmdstanr/reference/model-method-variables.html)

Combine that declaration rank with the skeleton's runtime axes:

```r
# Pseudocode for an ordinary numeric output; validate all inputs first.
axes <- if (declared_rank == 0L) integer() else as.integer(dim(skeleton[[base]]))
if (declared_rank > 0L && length(axes) != declared_rank) {
  stop("Declared output rank disagrees with the fit's variable skeleton.")
}
```

For rank zero, also require the skeleton to contain exactly one scalar value. For other ranks, validate finite integer nonnegative axes, preserve singleton axes, and verify the skeleton length against their product. Then use the existing scalar-coverage validator. Do not evaluate dimension-expression strings as R code or infer declaration rank from saved columns. If the supported CmdStanR version provides a reliable public rank map on the original fit, reuse it instead of constructing the temporary inspection object; never reach into private model-method environments.

Inspect this combined path using scalar, `vector[1]`, `matrix[1, 2]`, and a non-square multidimensional array. If public APIs cannot reliably provide a shape for a selected output, fail for that output. Do not silently relax the RStan coverage contract. The reviewed scalar/vector skeleton behavior is visible in [CmdStanR's skeleton implementation](https://github.com/stan-dev/cmdstanr/blob/master/R/utils.R); the implementation should still depend on public methods, not that internal helper.

CmdStanR's model-method implementation can provide information beyond CSV columns, but requires model resources. This is why the initial supported scope excludes resource-poor CSV reconstructions. [CmdStanR implementation](https://github.com/stan-dev/cmdstanr/blob/master/R/fit.R)

### 1.5 Deferred diagnostics and metadata

`check = FALSE` must retain raw sampler diagnostics for a later bundle check without computing BFMI, ESS, R-hat, or acceptance metrics during construction. The current CmdStanR extractor reads sampler diagnostics only for certain checks. Mirror the RStan unchecked-bundle behavior: read the raw sampler array separately if needed, without evaluating its metrics. A small private reader can be shared by the existing extractor and bundle adapter if that avoids duplicating error handling.

If raw diagnostics are unavailable, preserve the existing missing-diagnostics policy; a later check must report failure rather than inventing values. A structurally invalid sampler array remains an error.

Keep per-chain settings intact. Do not reuse `cmdstanr_metadata_value()` to reduce genuinely chain-specific settings to their first element. It is suitable only for fields verified to be common or for an existing scalar contract. In particular, validate chain IDs against the actual retained chains rather than assuming raw `num_chains` always equals the total retained count.

Reuse the existing unconstrained-count routine. It calls `$unconstrain_draws()`, which can initialize model methods and transform draws; this is already the package's supported count-inference path. It must not call `$sample()`. Optimizing it into a new count-only compiler API is outside this feature. [Unconstrained draws API](https://mc-stan.org/cmdstanr/reference/fit-method-unconstrain_draws.html)

Update `new_bundle_reference_info()` just enough to avoid its hard-coded RStan comment and to include relevant CmdStanR/CmdStan version evidence. Pass backend identity from the extraction record explicitly. Do not infer the backend from whether RStan happens to be installed. Keep the current reference-info top-level field schema and distinguish import-environment versions from CSV-reported sampling versions.

### 1.6 Files and tests

Expected changes:

- `R/create_pdb_bundle.R`: new S3 method and shared orchestration helper; backend-specific comment/version handling.
- `R/import_reference_posterior_draws.R`: new CmdStanR bundle adapter and any small shared sampler/coverage helper.
- `NAMESPACE` and generated `man/create_pdb_bundle.Rd`: register and document the new method using the repository's documentation-generation workflow.
- Existing bundle documentation and vignette: add CmdStanR usage and resource limitations. Correct blanket claims that construction never compiles; model-method initialization may compile without sampling.
- Tests: extend extraction and bundle suites rather than duplicating all writer tests.

Minimum behavioral coverage:

| Case | Required result |
| --- | --- |
| Ordinary HMC fit, actual inputs, valid labels | Same linked bundle classes and names as RStan |
| Parameters, transformed parameters, generated quantities | Draw selection retains requested outputs; dimensions contain model parameters only |
| Simplex or correlation parameter | Counts reflect unconstrained coordinates, not saved output length |
| Scalar, length-one vector, non-square matrix, singleton axes | Exact declared scalar coverage is checked |
| Missing final array element or duplicate index | Structural error; no accepted bundle |
| Unknown selection name, empty selection, derived-only selection | Same policy as existing RStan bundle |
| Fixed-parameter fit, failed chain, inconsistent sampler shape | Clear error or existing diagnostic failure as appropriate |
| Missing source/model resources; unresolved include | Clear supported-scope error |
| `check = FALSE`, followed by a deferred check | No initial metrics; deferred result matches immediate checking |
| Missing sampler diagnostics | Cannot obtain full acceptance |
| RStan-only environment | Existing RStan tests remain usable |
| Accepted CmdStanR bundle written and read back | Existing writer preserves draws, links, and metadata |

Mock public fit methods for fast structural tests, following `cmdstanr_fit_fixture()`. Include one guarded real CmdStanR integration fixture to verify skeleton shapes and constrained/unconstrained counts. Existing mocks do not model all these APIs and are not sufficient evidence of backend parity. Small integration fits need not pass the 10,000-draw acceptance gate; use existing accepted-draw fixtures for writer coverage.

Completion means the new backend reaches the existing assembly/check/write path without copying it or changing RStan behavior.

## 2. Model and data provenance verification on import

### 2.1 Problem and precise guarantee

`as_reference_posterior_draws_external()` currently validates the selected posterior parameter counts. Models with the same count map but different likelihoods, priors, or data can still pass. The function's documentation explicitly states that model source and sampling data are not compared.

Add conservative source comparison and optional recorded input fingerprints. The guarantee is **consistency with the available evidence**, not forensic proof of an external fit's history.

There are three distinct facts:

1. The target posterior's currently linked source and data.
2. Source retrievable from the fit and, where recorded, a sampling-time source/data fingerprint.
3. Source/data freshly supplied by an importer.

The third cannot retrospectively prove the second. In particular, hashing target data during import and attaching that hash to an old fit does not establish the fit's input data.

A retrieved source may also be unavailable or may depend on backend resources. Describe it as fit-associated source unless its sampling-time origin is established. A filename, model name, seed, or count map is not a substitute for source/data evidence.

### 2.2 Keep the API additive

Recommended first-version API:

- Add `sampling_provenance = NULL` as an explicitly named argument to conversion methods, both convenience wrappers, and the writing import wrapper.
- Add one small public helper, tentatively `capture_stan_sampling_provenance(model_code, data)`, for callers who sample outside the package. It returns a plain, versioned list of fingerprints.
- When sampling through `run_stan.pdb_posterior()`, capture that same record from the already resolved source/input list at the sampling boundary and attach it to the returned fit with a package-specific attribute.
- Explicit records and attached records are evidence inputs, not metadata fields in `...`. If both exist, compare their fingerprint fields; reject conflicts instead of silently choosing one. Matching records can prefer package-attached capture metadata.

Do not introduce verification modes, an evidence registry, signatures, sidecar-file discovery, or mandatory migration of older reference records. Unknown evidence remains explicitly unknown. A future requirement to reject all unverifiable imports would be a separate compatibility decision.

A deliberately small capture record:

```r
list(
  schema_version = 1L,
  fingerprint_scheme = "posteriordb-stan-input-v1",
  algorithm = "sha256",
  model_hash = "...",  # Or NULL if unavailable in an imported legacy record
  data_hash = "...",   # Or NULL if unavailable
  captured_by = "caller"  # Package sampling wrapper records its own boundary
)
```

The capture helper takes both source and inputs and produces both hashes. The importer may accept a validated legacy/partial record, preserving unknown fields as unknown. Reject duplicate/unknown fields, unsupported schema or scheme versions, and malformed hashes. Validate `captured_by` as a descriptive enum, never as an authentication mechanism; plain R lists can be edited.

No sample/compile operation occurs in the capture helper. Require source text or an existing `pdb_model_code`, not an overloaded string that might be interpreted as either source or filename. Resolve objects to their contents before hashing.

### 2.3 Source comparison rules

Reuse `normalize_stan_model_code()`: normalize CRLF/CR to LF and trailing final newlines. Convert to UTF-8 before hashing. Preserve all other source content.

For imports into an existing posterior:

1. Resolve the posterior once using `resolve_import_posterior()`.
2. Obtain target Stan source using the normal `model_code()` getter, honoring embedded content.
3. Retrieve RStan source using existing safe slot accessors, or CmdStanR source using `$code()`.
4. If fit-associated source is available, compare normalized text with target source. A mismatch is an error before diagnostics or writes.
5. If a sampling-time model fingerprint is supplied or attached, compare it with the target fingerprint and with any available fit-associated source fingerprint. Any conflict is an error.
6. If evidence is absent, record that fact. Do not fabricate a successful comparison.

This is exact normalized-source comparison, not semantic equivalence. A harmless comment change may fail. Explain that limitation and report a concise mismatch; do not call the existing log-density comparison helper as an automatic fallback. That helper compiles/samples and tests a different property.

Do not resolve `#include` recursively or claim that a hash of the parent source covers external included files. The first version should mark full model-input fingerprint verification unavailable for unresolved includes, or reject their use in the capture helper with an actionable message. Raw parent-text comparison alone can be recorded separately, but must not be labeled complete model verification.

### 2.4 Data fingerprint rules

The scheme must compare input **content**, not database ZIP bytes, JSON whitespace, paths, or R object attributes. It also must survive the package's data write/read boundary.

Reuse `validate_stan_input_data()` after converting a `pdb_data` to its ordinary named input list. Strip only database wrapper metadata and attributes irrelevant to the sampler. Do not coerce arbitrary objects or raw data frames into Stan data here.

Recommended narrow definition: hash a canonical representation of the package's serialized Stan input JSON. This deliberately follows the existing data representation rather than inventing a second Stan type system.

1. Sort top-level input names by an explicitly deterministic ordering, such as UTF-8 byte order; do not use locale-dependent collation. Input-list order should not affect the hash.
2. Normalize integer/double/logical numeric payloads consistently: logical becomes `0`/`1`, integer and double representations of the same value compare equally, and negative zero becomes zero. Preserve dimensions and element order while doing this. Never round values for comparison.
3. Serialize with the relevant existing `jsonlite` writer settings: `auto_unbox = TRUE`, `null = "null"`, `digits = NA`, UTF-8; whitespace can be omitted. Preserve the current matrix/array serialization convention from `write_to_path()` in `R/pdb.R`.
4. Parse that JSON without vector simplification, then serialize its JSON structure deterministically with the same numeric precision and no formatting. This separates JSON array/object structure from incidental R classes and storage modes. Do not flatten arrays or sort numeric array elements.
5. Hash the exact UTF-8 bytes using SHA-256 without R serialization. `digest` is already in `Suggests`; keep it optional and check its availability when fingerprint functionality is invoked. Ordinary legacy imports without a fingerprint record need not depend on it.

This payload convention is part of `posteriordb-stan-input-v1`; write it down next to the implementation and pin expected small-fixture hashes in tests. Do not later change it silently. Never use `digest(data)` with default R serialization, which makes the record depend on incidental R representation.

Before finalizing the helper, prove capture-time and read-back hashes agree for the package's supported data representation: scalars, singleton vectors, matrices, multidimensional arrays, singleton axes, empty arrays where supported, and `list()`.

Historical JSON loading can lose shape distinctions through simplification. If a supported case cannot round-trip consistently, fix the fingerprint normalization for that case without changing existing stored data, or declare that case unverifiable in this first version. Do not silently hash a guessed shape, flatten a matrix into a vector, or treat a transpose as equivalent. The contract verifies the package's serialized input representation; it does not verify declaration types that serialization does not encode.

### 2.5 Capture and verification flow

In `run_stan.pdb_posterior()`, source and data are already resolved into `sa`. Compute the provenance record from those same values immediately before the backend call, and attach it only after sampling succeeds. This avoids resolving the database twice and accidentally capturing different inputs. Preserve the returned fit class and all existing sampling arguments. Attach to the fit, not to the model object globally.

Because hashing is an additive feature, avoid making `digest` mandatory for all existing sampling calls. A simple explicit `capture_provenance = FALSE` sampling option can opt into capture; it should be a formal package argument, never forwarded into Stan sampling arguments. Document the option and forward it through an existing higher-level sampler only if that wrapper is part of the desired capture workflow. Do not build a new sampler wrapper solely for capture.

External sampling example using proposed APIs:

```r
# Capture from the exact source text and already preprocessed input list.
record <- capture_stan_sampling_provenance(source_text, stan_inputs)
fit <- model$sample(data = stan_inputs)
rpd <- as_reference_posterior_draws(
  fit, posterior = target, pdb = db,
  sampling_provenance = record
)
```

The caller is responsible for associating the record with the correct fitted artifact. Do not describe the example as automatic proof of that association.

During import, extract evidence and compare it before expensive diagnostics. Resolve target data only when a data fingerprint exists; legacy imports without data evidence should not incur a new data download just to report unknown. Target source may need to be loaded for a fit-source comparison; missing target/source resources cannot become a successful comparison.

Recommended outcomes:

| Evidence | Model result | Data result | Import behavior |
| --- | --- | --- | --- |
| Fit source matches; no sampling record | `fit_source_match` | `unavailable` | Continue with existing structural/diagnostic checks |
| Valid full record matches target | `record_match` | `record_match` | Continue; preserve capture origin |
| Available fit source or record disagrees | `mismatch` where applicable | `mismatch` where applicable | Error before writes |
| Neither source nor record available | `unavailable` | `unavailable` | Continue with clearly recorded limitations |
| Record supplied but target resource cannot be read | Cannot compare | Cannot compare | Error; do not silently ignore requested evidence |
| Record malformed or unsupported | Invalid | Invalid | Error |

If a source match cannot be evaluated because no source resource is available, record unavailable. Distinguish this from an actual mismatch. Do not catch every getter error as unavailable: malformed target objects or broken database links should retain their normal actionable failures.

### 2.6 Persistence without changing the database format broadly

An attribute alone is insufficient: ordinary JSON round trips do not retain arbitrary R attributes. The existing bundle's `provenance` list is also not independently written as part of reference-draw info.

Use one optional nested field, `info(rpd)$inference$provenance`, for the validated capture record and computed comparison result. The current reference-info validator requires an exact set of top-level fields, so adding a new top-level `provenance` field would fail. Its existing `inference` list is the narrow extension point.

Suggested persisted structure:

```r
inference$provenance <- list(
  record = validated_record,  # NULL when no capture record exists
  comparison = list(
    model = "fit_source_match",
    data = "unavailable"
  )
)
```

Add conditional validation for that nested field. Keep old records valid when it is absent. Populate comparison statuses internally; callers must not supply them through `reference_info`, `...`, or acceptance flags. Keep this field outside `inference$method_arguments`, because those arguments can be passed back to sampling by `compute_reference_posterior_draws()`.

Use existing JSON info writers/readers. Verify that staging, round-trip comparisons, and summary-statistic info copies preserve this nested data. Do not add a separate provenance writer or alter posterior links.

The writing import wrapper re-resolves the destination posterior after conversion. When provenance evidence exists, repeat the target comparisons against that destination before calling `write_imported_reference_posterior_draws()`. This prevents evidence computed against a caller-supplied posterior object from being assumed to describe a different same-named database target. Preserve the existing pre-write dimension/selection consistency check from the newer branch.

A direct `write_pdb(rpd)` does not thereby become a new full provenance-validation entry point. Preserve its established checked-object contract; document the scope of verification performed by the import wrapper. Solving arbitrary object mutation or database races is outside this change.

### 2.7 Scope boundaries and tests

Initial scope is import into an existing posterior and optional capture at known sampling boundaries. The bundle already compares supplied model code with fit source. It may reuse the capture helper later, but adding a universal provenance policy to all constructors and writers is not required here.

Tests should establish:

- Same count map, different source: importer rejects the fit.
- Same source/count map, different numeric data: recorded data fingerprint rejects the fit.
- Matching record: conversion succeeds and still runs the usual diagnostic checks.
- No record: source evidence is checked when present; data result remains unavailable.
- Supplying target data at import time does not create sampling-time evidence.
- Top-level input order, integer/double equivalence, logical normalization, line endings, and final newlines follow the defined comparison policy.
- Array element order, transposes, singleton dimensions where representable, and a one-value input change remain distinguishable.
- Fingerprints survive existing data and reference-info write/read paths.
- Unknown schemes, invalid hashes, conflicting explicit/attached records, and unsupported includes fail clearly.
- Missing `digest` affects fingerprint calls, not ordinary imports without fingerprints.
- A same-named caller posterior and destination with different source/data cannot share a successful import-wrapper comparison.
- No record changes acceptance thresholds or allows a diagnostic failure to be written.
- Captured provenance is not forwarded as a Stan sampling argument.
- Old reference-info JSON still loads with its original top-level schema.

Extend `test-import-external-stanfit.R` with equivalent backend cases and add a small dedicated provenance test file for normalization and persistence. Mock sampler calls to verify the capture boundary rather than running full reference sampling just to test hashing.

Completion means the importer rejects conflicts in available model/data evidence and persists an honest account of what was and was not compared.

## 3. Archived RStan import when compiled count inference is unavailable

### 3.1 Problem and target behavior

The importer calls `infer_unconstrained_parameter_counts_from_fit(fit)`. For RStan, that routine needs `fit@.MISC$stan_fit_instance`. An archived fit can retain saved draws and source while lacking a usable compiled instance.

The bundle adapter already falls back to `infer_posterior_dimensions(code, data, backend = "rstan")`. Its RStan branch creates a zero-chain fit, obtaining parameter counts without sampling. Reuse that capability for existing-posterior import.

This is recovery of structural counts, not recovery of lost draws, missing diagnostics, or historical sampling data.

### 3.2 Make compilation explicit

Add a named `recompile = FALSE` argument to the conversion generic, methods, convenience wrappers, and writing import wrapper. When false, retain the existing no-recovery behavior, with an improved actionable error when the compiled instance is unavailable. When true, permit count recovery using the saved model source and the resolved posterior's linked Stan inputs.

Do not add a separate `data`/`model_code` override to the existing-posterior importer just for this feature. The target posterior already owns those resources, and an override creates another consistency problem. Callers with different intended inputs should construct/use the appropriate posterior or the existing standalone bundle workflow.

Illustrative proposed call:

```r
rpd <- as_reference_posterior_draws_from_stanfit(
  archived_fit,
  posterior = target,
  pdb = db,
  recompile = TRUE
)
```

For CmdStanR, the new flag must not invoke an RStan fallback. Document it as RStan-only; reject `recompile = TRUE` on CmdStanR with a clear message rather than silently interpreting it as CmdStan executable recovery. The default false value keeps normal generic calls working.

### 3.3 Narrow shared count-recovery helper

Create one private helper, for example `resolve_rstan_parameter_counts(fit, source = NULL, data = NULL, recompile = FALSE)`. Call it from the importer and, where compatible, the existing bundle adapter.

The helper should return both counts and their origin:

```r
list(
  counts = list(mu = 1L, theta = 7L),
  origin = "fit_instance"  # Or "recompiled_source_and_data"
)
```

Do not change the public return type of `infer_unconstrained_parameter_counts_from_fit()`, which remains a named count list. The helper is orchestration, not a second inference implementation.

Flow:

1. Try the existing fit-based inference routine first. A successful result means count recovery must not invoke any source/data getter or compiler, even when `recompile = TRUE`. Separate provenance comparisons, if implemented, may still need source/data getters for their own purpose.
2. Distinguish unavailable compiled-instance evidence from invalid counts. Add a small specific error class for unavailable RStan count inference at the existing failure sites if necessary. Catch that class, not error-message substrings and not all errors.
3. If the instance is missing or demonstrably unusable, and recovery is disabled, stop with instructions to supply a resolvable target posterior and set `recompile = TRUE`.
4. If recovery is enabled, retrieve the fit's saved source and target inputs. Verify any available source/provenance evidence according to feature 2 if that feature is present. Independently require saved source to match the target's normalized Stan source before compiling; the fallback must not compile an unrelated target model.
5. Validate the input list using existing validators and require self-contained source. Preserve existing restrictions; do not add include-path discovery or download model code from filenames stored inside an old fit.
6. Call `infer_posterior_dimensions(saved_source, target_inputs, backend = "rstan")` exactly once.
7. Validate the resulting count map with `validate_posterior_dimension_counts()`.
8. Return the origin marker and feed the counts into the importer's existing comparison against posterior dimensions. A mismatch remains an error.

Passing the backend explicitly matters: the CmdStanR branch of `infer_posterior_dimensions()` currently performs a short sampling run. That is not an acceptable recovery path for this feature.

The current bundle fallback catches all inference errors. If sharing the helper, tighten that behavior as part of this focused fix: an inconsistent nonempty unconstrained-name result should not be concealed by recompiling. Preserve the bundle's existing permission to recover from supplied source/data; do not force its users to adopt a new public flag unnecessarily.

### 3.4 What counts as unavailable versus inconsistent

Treat these as different conditions:

| Condition | Action |
| --- | --- |
| No compiled model instance | Eligible for explicit recovery |
| Instance cannot be used because its module/pointer is unavailable | Eligible for recovery only when that unavailability can be identified safely |
| Valid name retrieval, but names/counts disagree with `get_num_upars()` | Error; do not recover to hide inconsistency |
| Counts disagree with the posterior definition | Error; do not retry compilation |
| Invalid posterior dimensions or missing selected variables | Existing error; unrelated to count recovery |
| Compiler, toolchain, source, or data failure during recovery | Actionable recovery error preserving the underlying cause |

Do not turn every exception from RStan into an unavailable-instance error. If the cause cannot be distinguished reliably, keep the original failure rather than masking it. Start with the known missing-instance case and add narrowly tested unavailable-module cases.

### 3.5 Reuse the existing importer pipeline

Move posterior resolution ahead of count recovery if needed, but leave diagnostics and object construction in their current shared path. Use lazy source/data retrieval so the live-fit fast path does not acquire a new compiler requirement or database read.

Infer the full model parameter count map first, then compare/intersect according to the existing posterior and selection rules in the newer branch. Do not pass include/exclude names for generated quantities into parameter-only inference. Do not use saved scalar output counts as a fallback for unconstrained counts.

After recovery, use the archived fit's original draws and sampler diagnostics. The zero-chain temporary fit is only a count source. Do not extract its draws, diagnostics, seed, timestamp, or version metadata as if they described the archived sampling run.

Record count origin in an optional nested `info(rpd)$inference$dimension_inference` object, for example:

```r
list(origin = "recompiled_source_and_data")
```

Keep it outside `method_arguments`. When feature 2 is also present, preserve its separate provenance result: recompilation using target data does **not** make original data provenance verified. No compiler cache or database sidecar is needed. Temporary artifacts should follow the existing inference helper's cleanup behavior.

### 3.6 Tests and completion criteria

Extend importer tests with a fixture that retains draws/source but reports an unavailable compiled instance. Mock the existing inference helper to verify control flow. Also add one guarded real RStan test using an archived/reloaded fit with the instance made unavailable in the fixture.

Required tests:

1. Live compiled instance: original path succeeds, and fallback/getters are not called.
2. Missing instance, default flag: useful error; no compile or sample call.
3. Missing instance, explicit flag: zero-chain count inference occurs once; original draw values and sampler arrays are retained.
4. Source mismatch: rejected before compilation.
5. Missing source, unreadable target inputs, or unresolved includes: actionable error.
6. Compiler failure: error preserves its cause and produces no accepted reference object or write.
7. Recovered counts disagree with target dimensions: normal mismatch error.
8. Valid but inconsistent compiled counts: no fallback despite `recompile = TRUE`.
9. Simplex/correlation output: recovered counts use unconstrained coordinates.
10. Selected derived quantities: preserved according to the newer selection implementation, without adding them to the count map.
11. CmdStanR with `recompile = TRUE`: explicit unsupported-option error; no RStan invocation.
12. Existing bundle missing-instance recovery remains functional through the shared helper.
13. Persisted origin metadata survives round trips and cannot be mistaken for original sampling provenance.

If feature 2 is not implemented yet, source equality for recovery and the origin marker are still required. Do not make this feature dependent on a full fingerprint system.

Completion means a resource-poor RStan fit with intact source/draws can be converted with explicit recovery, while valid live-fit imports keep their existing fast path.

## 4. Suggested delivery and review sequence

1. **Archived RStan recovery:** smallest isolated change. Introduce the narrow count-recovery helper, explicit option, origin metadata, and tests.
2. **CmdStanR bundles:** share the current constructor orchestration, implement the backend adapter, and verify real shapes. Reuse the recovery helper only on RStan paths.
3. **Provenance:** add normalized comparisons, optional capture, nested persistence, and destination verification. Treat fingerprint normalization as a defined compatibility contract.

The order is a convenience, not a mandatory architecture dependency. Each change should have its own reviewed diff and documented limitations.

For each implementation, run its focused tests and the existing affected extraction/import/bundle/writer suites. Once those pass, run the repository's normal package checks. Do not repeatedly run costly reference sampling merely to exercise metadata plumbing. Use guarded real backend tests for the APIs mocks cannot establish.

Review checklist:

- Does this diff fix only the described workflow gap?
- Does it reuse the current assembly, diagnostics, dimension inference, and transactional writers?
- Are new arguments explicitly forwarded through every public wrapper without entering metadata `...` or Stan sampler arguments?
- Are variable selection and unconstrained counts still separate?
- Are unknown historical facts labeled unknown?
- Can a metadata addition survive JSON round trips without changing the exact top-level reference-info schema?
- Are backend/resource failures actionable rather than silently weakened validations?
- Are existing RStan calls, old metadata records, and optional dependencies still supported?
- Have generated help and examples been updated to describe compilation and provenance accurately?

The guide itself lives in `docs/` as requested. The repository already keeps package guides in `doc/`; do not relocate those documents as part of these feature changes. The existing `.Rbuildignore` pattern beginning `^doc` also excludes this `docs/` directory from the built package.
