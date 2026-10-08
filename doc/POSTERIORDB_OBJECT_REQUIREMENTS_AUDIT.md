# PosteriorDB object requirements: exploratory audit

This is an untracked implementation guide based on a read-only review of
`~/Documents/posteriordb-r` (the unforked package), its original
`doc/CONTRIBUTING.md`, selected files in
`~/Documents/posteriordb/posterior_database`, and the current fork. No existing
project or database files were changed. An in-memory constructor check used
the installed `posteriordb` package and did not call any writer.

## Executive findings

1. The original contribution guide's list-constructor calls are stale or
   incorrect. `pdb_data_info()`, `pdb_data()`, and `pdb_model_info()` are
   retrieval generics/aliases in the original source; they do not construct
   objects from lists. The corresponding list constructors are
   `as.pdb_data_info()`, `as.pdb_data()`, and `as.pdb_model_info()`. Likewise,
   list-based posterior construction should use `as.pdb_posterior()` (or
   `as.posterior()`), because there is no `posterior.list()` method.
2. Data and model info have clear required fields and a few defaults. The
   posterior constructor has more important computed/defaulted fields, but it
   silently drops some user-supplied optional fields.
3. PosteriorDB's posterior JSON schema does use optional `keywords`, `urls`,
   and `references` fields: these appear in the local database and in the
   original contribution guide. However, the original and forked list
   constructors retain only the core posterior fields, so those three
   supplied fields are silently discarded.
4. The fork's `create_pdb_bundle()` supplies sensible shared contributor/date
   defaults, derives data/model/posterior structural fields, and defaults
   Stan's `stan_version` to `">=2.26.0"`. It still cannot set optional
   posterior metadata (`keywords`, `urls`, `references`) because the bundle's
   `posterior_info` validation rejects them and its posterior constructor
   filters extras.

## Original package: minimums, defaults, and serialization

### Data payload (`pdb_data`)

The original `assert_data()` requires a `pdb_data` object that is a named list
with unique names and an attached `pdb_data_info` object. It does not enforce
Stan-specific value types or validate whether the values match a model's data
block. The actual values are the list elements; there is no separate payload
field.

### Data info (`pdb_data_info`)

Required by `assert_data_info()`:

| Field | Required? | Behavior |
|---|---:|---|
| `name` | Yes | String; determines the default file path. |
| `data_file` | Yes after construction | Defaults to `data/data/<name>.json`; any supplied path must equal that exact path. |
| `title` | Yes | String. |
| `added_by` | Yes | String; no default in `as.pdb_data_info()`. |
| `added_date` | Yes | `Date`; no default in `as.pdb_data_info()`. |
| `references` | No | Optional character vector; explicit `NULL` is accepted. |
| `description` | No | Optional string; explicit `NULL` is accepted. |
| `urls` | No | Optional character vector; explicit `NULL` is accepted. |
| `keywords` | No | Optional character vector; explicit `NULL` is accepted. |

`write_pdb.pdb_data_info()` in the original package adds omitted optional
fields as JSON nulls. This is a writer convention, not a constructor or
`assert_data_info()` requirement: reading an object without those keys passes
the assertion. The fork currently retains this legacy serialization behavior.
Whether to preserve that output convention or make it omit missing optional
fields should be decided explicitly; the current project preference is to
avoid defaults unless the field is required.

### Model source and model info (`pdb_model_code`, `pdb_model_info`)

The model source is a character object (for example, a compiled RStan
`stanmodel` converted to a model-code object) with a framework and attached
model info. Writing the model-code object writes the info JSON and the source
file.

Required top-level fields in original `assert_model_info()`:

| Field | Required? | Behavior |
|---|---:|---|
| `name` | Yes | String; determines the conventional model-code path. |
| `model_implementations` | Yes after construction | Can be generated from `framework`; each non-null implementation needs `model_code`. |
| `title` | Yes | String. |
| `added_by` | Yes | String; no default in `as.pdb_model_info()`. |
| `added_date` | Yes | `Date`; no default in `as.pdb_model_info()`. |
| `prior` | No | Allowed at top level; not inferred from source code. |
| `description`, `references`, `urls`, `keywords`, `licence` | No | Allowed optional metadata. |

When `framework = "stan"` is supplied instead of
`model_implementations`, the constructor creates
`model_implementations$stan$model_code = "models/stan/<name>.stan"` and removes
the `framework` key. Supplying both is an error. If implementations are
supplied directly, every implementation needs `model_code`. Original code
allows `likelihood_code`, `stan_version`, and `pymc_version` as nested fields;
it does not require them or add defaults. The model-info writer serializes
the supplied list as-is, so absent optional keys remain absent.

The fork intentionally rejects `likelihood_code` under the user's explicit
requirement that it never appear in model info. Forked `create_pdb_bundle()`
uses the same conventional model-code path, supplies
`stan_version = ">=2.26.0"` by default, and permits an override at
`model_info$model_implementations$stan$stan_version` as long as `model_code`
matches the inferred path. Generic manually constructed model info does not
receive that bundle-specific version default.

`prior` is optional. When supplied, the established PosteriorDB shape is an
object such as `list(keywords = "stan_recommended_35dbfe6")`; the constructors
do not infer it from Stan source. The fork omits it when absent, retains it
when supplied, and does not synthesize `prior: null`.

### Posterior metadata and object (`pdb_posterior`)

There is no separate `pdb_posterior_info` class in this workflow. Posterior
metadata is represented by the posterior list itself. To create one from the
data and model objects, original `as.posterior.list()` derives:

| Field | Required in final object? | Default or derivation |
|---|---:|---|
| `name` | Yes | `<data name>-<model name>` when `pdb_data` and `pdb_model_code` are supplied. |
| `model_name` | Yes | From model info. |
| `data_name` | Yes | From data info. |
| `reference_posterior_name` | Yes | Explicit JSON null when omitted or `NULL`. |
| `dimensions` | Yes | Must be a named list. The code attempts a tiny Stan run when missing, then still errors; callers should supply it. |
| `model_info`, `data_info` | Yes in memory | Derived from the attached model/data objects. Removed from the posterior JSON writer because the links are stored by name. |
| `added_by` | Yes | Defaults to current R user and emits a message. |
| `added_date` | Yes | Defaults to `Sys.Date()`. |
| `keywords`, `urls`, `references` | Optional in the database schema | The list constructor currently drops these and all other extra fields. |

The posterior object also needs a `pdb` connection in the original package;
`assert_pdb_posterior()` checks its class. Before `check_pdb_posterior()` can
validate the complete contribution, the linked data and model files must
already be written. The posterior writer stores the structural/link fields,
dimensions, contributor/date, and reference link; it removes the in-memory
`pdb`, `model_info`, and `data_info` attributes.

The extra-field filtering is a substantive mismatch. The original
`doc/CONTRIBUTING.md` passes `keywords`, `urls`, and `references` to the
posterior constructor, and local database posterior JSON files commonly
contain those fields. But `as.posterior.list()` subsets the input to
`pdb_posterior_must_include()` before returning. An in-memory check against
the installed original package confirmed the result contains only
`name`, `model_name`, `data_name`, `reference_posterior_name`, `dimensions`,
`model_info`, `data_info`, `added_by`, and `added_date`; all three extras were
gone.

## The original contributing workflow has stale constructor calls

In the original source:

- `pdb_data_info <- data_info`, but there is no `data_info.list()` method.
- `pdb_data <- get_data`, but there is no `get_data.list()` method.
- `pdb_model_info <- model_info`, but there is no `model_info.list()` method.
- `pdb_posterior <- posterior`, but there is no `posterior.list()` method.
- List constructors are `as.pdb_data_info()`, `as.pdb_data()`,
  `as.pdb_model_info()`, and `as.pdb_posterior()`.

The calls in the original `doc/CONTRIBUTING.md` to the `pdb_*` retrieval
generics with a list therefore fail in a clean current package installation.
The model-source call `model_code(stanmodel, info = mi)` is the exception: it
has a `stanmodel` conversion method. The guide should be corrected when its
maintainer intends to refresh it; do not copy those list-constructor calls
into new fork documentation.

## Fork comparison and recommended implementation sequence

### Already aligned or improved

- Bundle metadata validation rejects unknown fields instead of silently
  ignoring them.
- `create_pdb_bundle()` requires data/model `name` and `title`, derives the
  data path and model implementation path, and shares `added_by` and
  `added_date` defaults. Per-object metadata can override the shared defaults.
- The bundle derives posterior name/link fields and dimensions from the
  constructed objects and fit, and sets `reference_posterior_name` to the
  matching data-model posterior name.
- Bundle Stan model info defaults `stan_version` to `">=2.26.0"`; the caller
  can override it while preserving the inferred model-code path.
- Model-info writing preserves fields the caller supplied and does not create
  optional `prior`/`pymc` fields by default. `likelihood_code` is rejected.

### Gaps to consider for a later implementation

1. **Preserve supported posterior metadata.** Add the actual optional
   PosteriorDB posterior fields (`keywords`, `urls`, `references`) to the
   posterior constructor's recognized fields and validation, rather than
   dropping them. Thread the same fields through `create_pdb_bundle()`'s
   `posterior_info` allowlist and assembly. Test both in-memory values and
   round-trip JSON. Keep structural fields (`name`, `model_name`,
   `data_name`, `reference_posterior_name`, `dimensions`) derived and reject
   conflicting caller values, as the bundle already does.
2. **Avoid silent drops in direct posterior construction.** For any
   unsupported extra fields, either reject them with a clear error or support
   them explicitly. Silent filtering conflicts with the rule that caller
   input should not disappear.
3. **Resolve data-info null filling.** The constructor does not require
   optional description/reference/URL/keyword fields, while the writer inserts
   all four as null when absent. Under the current preference to omit
   unprovided optional fields, remove writer completion for those fields;
   retain explicit caller values, including explicit nulls. If the team wants
   byte-level compatibility with the older writer's canonical output, record
   that as a deliberate data-info-specific serialization rule instead.
4. **Make dimensions omission fail without doing work.** In the original
   posterior constructor, missing dimensions triggers a minimal Stan run and
   then still errors. A later cleanup should stop immediately with a message
   that names and dimensions must be supplied or be inferred by a constructor
   that has fit output available.
5. **Keep schema requirements separate from writer conventions.** For each
   field, document whether it is required to construct an object, required in
   the serialized database schema, defaulted by a constructor, or merely
   inserted by a writer. The original data-info null completion is an
   example where those categories differ.

No source changes or tests were made for this audit. Suggested changes above
are planning items only.
