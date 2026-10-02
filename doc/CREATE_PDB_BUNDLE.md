- [Create and contribute a reference-draw
  bundle](#create-and-contribute-a-reference-draw-bundle)
  - [Choose a workflow](#choose-a-workflow)
    - [Import a fit for an existing
      posterior](#import-a-fit-for-an-existing-posterior)
    - [Reuse existing bundle
      components](#reuse-existing-bundle-components)
  - [Create a new bundle: eight
    schools](#create-a-new-bundle-eight-schools)
    - [Supply metadata](#supply-metadata)
    - [Inspect the in-memory objects](#inspect-the-in-memory-objects)
  - [Choose when to compute
    diagnostics](#choose-when-to-compute-diagnostics)
  - [Choose variables](#choose-variables)
  - [Write the objects](#write-the-objects)
    - [Rename and bibliography
      recovery](#rename-and-bibliography-recovery)
  - [Reconstruct outputs from stored parameter
    draws](#reconstruct-outputs-from-stored-parameter-draws)
  - [Fit and provenance limitations](#fit-and-provenance-limitations)

<!-- CREATE_PDB_BUNDLE.md is generated from CREATE_PDB_BUNDLE.Rmd. Please edit that file. -->

# Create and contribute a reference-draw bundle

`create_pdb_bundle()` builds linked data, model, posterior, and
reference-draw objects around an already sampled `rstan::stanfit`. The
result is an R list that you can inspect and check before writing any of
its objects. The function does not resample the fit or write files. It
supports the existing list-based workflow by default, and can reuse
existing data, model-code, or posterior objects (or retrieve them by
name from a database). It currently accepts RStan `stanfit` objects;
`import_reference_posterior_draws()` also accepts CmdStanR fits.

## Choose a workflow

Choose the workflow based on whether the data, model, and posterior
records already exist:

- Use `create_pdb_bundle()` to construct linked objects from a fit. The
  standard workflow supplies the Stan data list plus `data_info` and
  `model_info`; the function builds everything in memory and leaves
  persistence to you. If records already exist, pass `data` as a
  `pdb_data` object or saved data name, and pass `model_code` and/or
  `posterior` as existing objects or saved names. A supplied posterior
  can provide its linked data and model code automatically. Existing
  model source must match the fit, and posterior links and unconstrained
  parameter counts must match.
- Use `import_reference_posterior_draws()` when you already have a
  PosteriorDB posterior and want to import a completed fit for it. This
  supports RStan and CmdStanR fits, checks them, and can write the draws
  and summaries while linking them to the existing posterior. It does
  not rewrite the existing data, model, or posterior payloads.

### Import a fit for an existing posterior

For example, to import into an existing posterior in a local database:

``` r
pdbl <- pdb_local("/path/to/posterior_database")
imported_draws <- import_reference_posterior_draws(
  fit,
  posterior = "existing_data-existing_model",
  pdb = pdbl,
  write = TRUE,
  overwrite = FALSE
)
```

The importer always runs the full reference-draw checks. With
`write = TRUE`, it writes only if those checks pass. It writes both
`mean_value` and `mean_squared_value` summaries by default; set
`write_summary_statistics = FALSE` to skip them. A posterior already
linked to a different reference-draw object cannot be relinked by this
call. The importer selects every saved scalar column for each declared
base variable in posterior dimensions, and always retains all inferred
parameter-block variables. Declared counts for actual model parameters
must match the fit’s unconstrained counts. Dimensions may also name
saved derived outputs, which have no independent unconstrained counts to
compare. The importer does not confirm that the fit used the exact model
source and data linked to that posterior.

To retain additional saved outputs, pass base names through `include`:

``` r
imported_draws <- import_reference_posterior_draws(
  fit, posterior = "existing_data-existing_model", pdb = pdbl,
  include = c("theta", "log_lik"), write = FALSE
)
```

Every variable named in `posterior$dimensions`, and every
parameter-block variable inferred from the fit, is retained
automatically even if omitted from `include`. Additional outputs may be
transformed parameters or generated quantities; all their indexed
columns are retained. `exclude` removes additional selections and takes
precedence over `include`, but excluding a dimensions or parameter-block
variable is an error. Unknown names are errors. Without these arguments,
only those required variables are retained. This can retain more
variables than older importer versions. Diagnostics and written
summaries cover the retained selection, not omitted outputs. Existing
dimensions are not changed. Required variables missing from the saved
fit cause an error. Retaining the complete parameter block provides the
inputs needed by `reconstruct_stan_output()`, but the importer does not
itself reconstruct outputs or verify model/data identity. Random
generated quantities cannot generally be recovered exactly.

The importer stages the reference-draw files, summaries, and any
required posterior-link update, checks their round trip, and restores
originals if the operation fails. This is its transactional import path;
it differs from the sequential whole-bundle writer below. Updating a
previously empty posterior link is allowed with `overwrite = FALSE`;
that flag controls replacement of existing draw and summary files.
Conversion-only helpers `as_reference_posterior_draws()`,
`as_reference_posterior_draws_from_stanfit()`, and
`as_reference_posterior_draws_from_cmdstanr()` accept the same selection
arguments and return checked draws without writing.

### Reuse existing bundle components

To build from saved data and model records while constructing the
missing posterior and reference draws, use:

``` r
pdbl <- pdb_local("/path/to/posterior_database")
bundle <- create_pdb_bundle(
  fit,
  data = "existing_data",
  model_code = "existing_model",
  pdb = pdbl,
  check = FALSE
)
```

You can pass `pdb_data`, `pdb_model_code`, and `pdb_posterior` objects
instead of names. If only `posterior` is supplied, its linked data and
model code are obtained with `get_data()` and `model_code()`. The
ordinary list plus metadata workflow remains the default. When reusing
an object, omit its corresponding metadata list. If both are supplied,
the function warns and uses the existing object’s metadata, ignoring the
corresponding list. When supplying an existing posterior, its
`dimensions` must use the fork’s current meaning: one scalar
unconstrained-parameter count per model parameter. Older PosteriorDB
entries that store output shapes may fail validation and cannot be
passed through unchanged. The selected variables and their inferred
counts must also agree with the supplied posterior.

Reused objects retain the database connection they came from, even when
`pdb` names a different destination. The writer may copy them into an
empty destination, but rejects same-name destination files from another
database under both overwrite settings. Passing a destination connection
does not make a source object belong to that destination.

If an existing posterior has an empty reference link, you can still
construct and inspect its bundle. To persist accepted draws and fill
that link together, use the existing-posterior importer:

``` r
imported_draws <- import_reference_posterior_draws(
  fit, posterior = "existing_data-existing_model", pdb = pdbl,
  write = TRUE
)
```

The whole-bundle writer leaves reused records untouched. It rejects an
accepted candidate before any writes if the reused posterior’s stored
reference link is empty or differs from the candidate reference name.
The importer can fill an empty link, but rejects a different existing
link.

## Create a new bundle: eight schools

Prepare the fit and the exact named Stan input list used for sampling.
The eight schools example below follows the model in `CONTRIBUTING.md`:

``` r
library(posteriordb)
library(rstan)

stan_data_file <- system.file("test_files/eight_schools.R", package = "posteriordb")
source(stan_data_file)

stan_file <- system.file(
  "test_files/eight_schools_noncentered.stan",
  package = "posteriordb"
)
stan_code <- paste(readLines(stan_file), collapse = "\n")
stan_model <- rstan::stan_model(model_code = stan_code)
fit <- rstan::sampling(
  stan_model,
  data = eight_schools,
  chains = 10,
  iter = 20000,
  warmup = 10000,
  thin = 10,
  seed = 4711,
  control = list(adapt_delta = 0.92)
)
```

### Supply metadata

Pass the same input list used for sampling, along with the required
names and titles for the data and model. `added_by` and `added_date` are
shared defaults for the objects in the bundle. `added_date` defaults to
`Sys.Date()`; supply a Date such as `as.Date("2026-09-30")` to override
it. A value in an individual metadata list takes precedence. The first
four positional arguments are `fit`, `data`, `added_by`, and
`added_date`. Supply other options, including `model_code` and
`posterior`, by name. `posterior_info` also accepts the optional
character fields `urls`, `references`, and `keywords`; supplied values
are written to the posterior JSON. If posterior keywords are omitted,
the posterior JSON writes `"keywords": null`.

For model metadata, `framework = "stan"` is a convenience form: the
bundle constructor creates `model_implementations$stan` for you, using
`models/stan/<model name>.stan` and `stan_version = ">=2.26.0"`. You do
not need to build that nested list for the usual Stan workflow. If you
prefer to supply `model_implementations` yourself, that remains
supported; the Stan `model_code` path must match the path inferred from
the model name, and an explicit `stan_version` is retained. For example,
this shorthand is sufficient:

``` r
model_info = list(
  name = "normal",
  title = "Normal model",
  framework = "stan"
)
```

`model_info$prior` is optional descriptive metadata, often a list of
keywords that points to prior information elsewhere in PosteriorDB. For
example, pass `prior = list(keywords = "stan_recommended_35dbfe6")` when
that reference is known. The bundle does not infer prior distributions
from the Stan source; if no prior metadata is supplied, the written
model info omits `prior`. The model writer does not emit a
`likelihood_code` entry. Optional model metadata is written only when
supplied; the writer does not add a `pymc` entry or a `pymc_version` by
default. If model keywords are omitted, the model info JSON writes
`"keywords": null`. The bundle API defaults the Stan implementation’s
`stan_version` to `">=2.26.0"`. You can override this by supplying the
`stan_version` inside `model_info$model_implementations$stan`, while
keeping `model_code` equal to the inferred path, for example:

``` r
model_info = list(
  name = "normal",
  title = "Normal model",
  model_implementations = list(stan = list(
    model_code = "models/stan/normal.stan",
    stan_version = ">=2.35.0"
  ))
)
```

``` r
bundle <- create_pdb_bundle(
  fit,
  data = eight_schools,
  added_by = "Stanislaw Ulam",
  data_info = list(
    name = "test_eight_schools_data",
    title = "A Test Data for the Eight Schools Model",
    description = "Treatment estimates and standard errors for eight schools."
  ),
  model_info = list(
    name = "test_eight_schools_model",
    title = "Test Non-Centered Model for Eight Schools",
    framework = "stan",
    description = "A hierarchical model with a non-centered parameterization.",
    references = "rubin1981estimation"
  )
)
```

### Inspect the in-memory objects

The constructor returns the four linked objects and, when accepted,
summaries:

``` r
bundle$data
bundle$model_code
bundle$posterior
bundle$reference_draws
bundle$summary_statistics$mean_value
bundle$summary_statistics$mean_squared_value
```

The posterior embeds the data, model code, and reference draws, so its
getters work before persistence. `bundle$provenance` records how the
input data was obtained, the fit class, selected variables, and sampling
metadata. Passing a `pdb` connection attaches it to the objects; when a
saved object name is supplied, the connection is also used to retrieve
that object. Construction never writes database files.

If a serialized RStan fit has lost its compiled model pointer, bundle
construction recompiles the saved Stan source and uses the supplied data
to recover unconstrained parameter counts. This does not resample or
replace the fit’s saved draws. RStan may print
`the number of chains is less than 1; sampling not done` during this
dimension-recovery step; that is expected.

## Choose when to compute diagnostics

The four common workflows are:

| Goal | Construction | Persistence |
|----|----|----|
| Create without diagnostics | `check = FALSE` | No writer call |
| Create and check | `check = TRUE` | No writer call |
| Check and write without replacing files | Either construction mode | `write_pdb(bundle, pdbl, overwrite = FALSE)` |
| Check and permit replacement | Either construction mode | `write_pdb(bundle, pdbl, overwrite = TRUE)` |

The whole-bundle writer checks unchecked bundles automatically. It may
still write the data/model/posterior components when reference-draw
checks fail; inspect its returned result as described below.

`check = TRUE` is the default. It calculates the reference-draw
diagnostic report during bundle creation. The report is available as:

``` r
bundle$diagnostics$metrics
bundle$diagnostics$status
bundle$diagnostics$failures
```

`status` contains one logical value per acceptance check. `failures`
identifies which checks failed and, where relevant, which variables or
chains were responsible. A failed check does not prevent bundle
creation: the bundle is returned with the failure recorded, so you can
inspect the report. Its reference draws cannot be written until they
pass.

When the reference-draw checks pass, the bundle also computes the
supported summary statistics (`mean_value` and `mean_squared_value`)
from those draws. They are returned in `bundle$summary_statistics`. An
unchecked bundle, or a bundle whose checks fail, has
`summary_statistics = NULL`; this prevents summaries from appearing
writeable before the required draw checks pass. The summary info objects
carry the same reference-posterior metadata as the draws, with the
summary-specific acceptance flags and summary-computation version added
by the existing summary-statistic constructor.

The acceptance checks require exactly 10,000 retained draws, at least
four chains, absolute lag-1 autocorrelation at most 0.05 for every
retained variable, R-hat at most 1.01 for every variable, E-FMI at least
0.2 for every chain, and no divergent transitions. Bulk and tail ESS are
also calculated and stored as diagnostic metrics, but ESS bounds do not
decide whether the draws pass. Bundle reports include observed tree
depths and configured maximum depths when available; maximum tree depth
is not an acceptance gate. The example sampling settings produce 10,000
retained draws, but no choice of settings guarantees that every
diagnostic will pass.

Set `check = FALSE` to create the objects without calculating the
diagnostic metrics or evaluating acceptance checks. The bundle has
`diagnostics = NULL` and its reference draws have no acceptance flags.
Sampler diagnostics are retained in memory for a later check; sampling
is not repeated. Unchecked draws are not writable.

``` r
unchecked <- create_pdb_bundle(
  fit,
  data = eight_schools,
  data_info = list(name = "test_eight_schools_data", title = "Eight schools data"),
  model_info = list(name = "test_eight_schools_model", title = "Eight schools model"),
  check = FALSE
)

is.null(unchecked$diagnostics)  # TRUE
info(unchecked$reference_draws)$checks_made  # NULL
```

To defer the check, pass the unchecked bundle to
`check_reference_posterior_draws()`. It returns an updated bundle with
the report and result attached:

``` r
bundle <- check_reference_posterior_draws(unchecked)
bundle$diagnostics$status
bundle$diagnostics$failures
```

The bundle workflow currently supports checking the full set of
acceptance criteria during construction or checking that full set later.
It does not provide a way to select one criterion for a bundle check.
For investigating an individual check on a sampled RStan or CmdStanR fit
before importing it, use `reference_draw_diagnostics()` and
`passes_reference_draw_checks()`. These functions accept a `checks`
selector such as `"mean_lag1_ac"`; passing one check does not establish
full reference-draw acceptance or make a draw object writable.

``` r
report <- reference_draw_diagnostics(fit, checks = "mean_lag1_ac")
report$metrics
report$thresholds
report$status
report$failures
passes_reference_draw_checks(fit, checks = "mean_lag1_ac")
```

## Choose variables

By default, the bundle includes saved parameters, transformed
parameters, and generated quantities, excluding `lp__`: this is the
`include = NULL` default. `include = "all"` is an equivalent bundle
option; `c("all")` means exactly the same thing. Use `include = "none"`
or `include = character(0)` to retain only the complete parameter block,
with no additional outputs. `c("none")` is equivalent to `"none"`. The
names `"all"` and `"none"` are reserved when used alone as bundle
selections; `exclude` still applies to derived outputs. In R, `c()` is
`NULL`, so `include = c()` selects all outputs rather than
parameter-block-only draws. Use `include` or `exclude` with base
variable names to select additional outputs. For example,
`include = c("mu", "tau")` keeps those variables **and every inferred
parameter-block variable**. `include = "theta"` can additionally retain
all elements of a transformed parameter or generated quantity. Excluding
an inferred parameter-block variable is an error; derived outputs can be
excluded. The same retained selection is used for immediate or deferred
diagnostics and summary statistics. The posterior’s `dimensions` entries
always describe the complete inferred parameter block and are unaffected
by selection of derived outputs. These entries record unconstrained
parameter counts, which can differ from the number or shape of saved
output columns (for example, a constrained simplex has one fewer
unconstrained coordinate than output elements).

The `dimensions` map describes the model parameters that have
unconstrained coordinates; it is not a complete inventory of every
variable saved in the draws. Transformed parameters and generated
quantities can be present in the draw payload without appearing in this
map. Use `include` and `exclude` to choose which saved variables are
retained and used for the bundle’s draw diagnostics. In particular,
exclude a generated quantity if it is not useful for diagnosing the fit.

Acceptance applies to the retained variables. Omitted derived outputs
are not certified by that report, even if the parameter-block variables
pass. Unknown base names are errors; selection requires the
corresponding columns to have been saved in the fitted object. Constant
outputs can have undefined R-hat or autocorrelation and may fail checks
rather than indicate a sampling problem.

Selection defaults differ between the two workflows:

| Selection | Bundle creator | Existing-posterior importer |
|----|----|----|
| `include = NULL` | All saved outputs except `lp__` | Complete inferred parameter block plus dimensions variables |
| Explicit base names | Required parameter block plus requested outputs | Required parameter block, dimensions variables, and requested outputs |
| `exclude` | May remove derived outputs only | May remove extras, but neither parameter-block nor dimensions variables |
| `"all"` / `"none"` aliases | Supported when used alone | Not aliases; interpreted as variable names |

There is no `keep_dims` or `diagnose_params` argument.
`include`/`exclude` control both stored outputs and variable-level
diagnostics. To diagnose more outputs in an import, explicitly include
their base names.

For an existing fit, the package can infer the named unconstrained
counts directly from either supported fit class:

``` r
rstan_dimensions <- infer_unconstrained_parameter_counts_from_fit(rstan_fit)
cmdstanr_dimensions <- infer_unconstrained_parameter_counts_from_fit(cmdstanr_fit)
```

The same helper dispatches on fit class and returns one count per model
parameter. If there is no fit object, `infer_posterior_dimensions()` can
infer counts from Stan source and data:

``` r
dimensions <- infer_posterior_dimensions(
  stan_code, eight_schools, backend = "rstan"
)
# list(theta_trans = 8L, mu = 1L, tau = 1L)
```

The RStan backend compiles and initializes data without MCMC. The
CmdStanR backend currently uses a short sampling run (`iter = 4L` by
default), so it is not a compile-only operation. With either backend,
counts require the matching data because parameter dimensions can depend
on it.

Each generated dimensions entry is a single unconstrained count, not a
shape: `list(B = c(2L, 3L))` is rejected; an unconstrained
`matrix[2,3] B` has `B = 6L`. A `simplex[3]` has count 2 despite three
constrained draw columns. Manual posterior validation checks that counts
are positive integers but cannot establish that a plausible scalar count
agrees with the model. Bundle construction rejects supplied dimensions
that conflict with its inference; the importer checks counts for actual
parameter-block variables and also allows saved derived variables in
existing dimensions. Existing scalar counts that describe constrained
rather than unconstrained dimensions can still fail import, and bundle
reuse remains stricter about the complete inferred map.

## Write the objects

You can write the whole bundle with one call. If diagnostics have not
been computed yet, this checks the draws first. New data, model, and
posterior objects are written either way; records reused from the
destination database are left in place. Reference draws and their
summary statistics are written only if all acceptance checks pass.
Before writing, the bundle writer checks every planned output path,
including info files and payloads, and draws/summaries when eligible for
writing:

``` r
pdbl <- pdb_local()
write_result <- write_pdb(bundle, pdbl, overwrite = FALSE)
write_result$written
write_result$reused
write_result$collisions
write_result$overwritten
write_result$reference_draws_written
write_result$summary_statistics_written
write_result$skipped_reason
# Keep the updated bundle, particularly after an automatic deferred check:
bundle <- write_result$bundle
```

When a draw check fails, `write_result$bundle$diagnostics$failures`
describes the failed checks. A diagnostic error is recorded in
`write_result$diagnostic_error`; in either case, the three non-draw
components are written or reused, while draws and summaries are skipped.
Newly written posterior JSON has a `null` reference link when the
reference files do not exist. When replacing a posterior after failed
checks, a link to already stored reference files is preserved. The
returned in-memory bundle retains its candidate reference name for
inspection; this does not mean that the candidate was persisted.

If a planned file already exists, `overwrite = FALSE` stops before
writing any bundle files and reports all colliding paths.
`overwrite = TRUE` still runs the same preflight, reports those paths in
`write_result$collisions`, and allows replacement of newly constructed
components. Data, model, or posterior objects reused from the
destination database are instead left in place and reported in
`write_result$reused`; the bundle writer never overwrites those records.
If a reused object comes from another database and the target has no
files with that name, it can be copied to the target. Partial or
ambiguous same-name files for a reused object stop the operation
regardless of `overwrite`.

Resource names must be nonempty single path components. Names such as
`example.v2-model` are valid; names containing `/`, `\\`, control
characters, or the entire name `.` or `..` are rejected during
construction and writing. The same rule applies to rename, link, and
import operations. Relative model implementation paths such as
`models/stan/example.v2-model.stan` remain paths, not resource names.

Before writing, local output paths are checked against the database
root, including existing symlink targets, missing parent directories,
and the temporary JSON files used to build ZIP archives. An escaping or
dangling symlink causes an error before the operation writes resource
files. The individual data, model, reference-draw, and summary writers
check payload destinations before saving metadata. These checks assume
paths do not change concurrently; they do not lock the filesystem.

After preflight, the writes remain sequential in data, model, posterior,
then reference-draw and summary order. Preflight prevents file-name
collisions from causing a partial write, but a later serialization or
filesystem error can still leave earlier successful writes in place. To
add accepted draws to a database that already has the matching data,
model, and posterior, write only the reference-draw object:

``` r
write_pdb(bundle$reference_draws, pdbl, overwrite = FALSE)
```

The associated posterior JSON must already exist. This individual draw
write requires a persisted link to the reference-draw name and also
writes both supported summary statistics by default. Use the
whole-bundle writer when the destination does not already contain
conflicting objects, or when replacing them with `overwrite = TRUE` is
intended. That option replaces files at the bundle’s destination names;
it does not merge metadata or protect against replacing a different
object’s files that use those same names.

You can also write the individual objects manually when you want to
control the steps separately. The individual reference-draw writer
rejects unchecked or failed draws and requires the associated posterior
JSON to exist first:

``` r
assert_checked_reference_posterior_draws(bundle$reference_draws)
write_pdb(bundle$data, pdbl, overwrite = FALSE)
write_pdb(bundle$model_code, pdbl, overwrite = FALSE)
write_pdb(bundle$posterior, pdbl, overwrite = FALSE)
write_pdb(bundle$reference_draws, pdbl, overwrite = FALSE)
```

By default, the reference-draw `write_pdb()` method also computes and
writes the supported summary statistics (`mean_value` and
`mean_squared_value`) using their existing constructors and writer
methods. Data, model, reference-draw, and summary-statistic payloads are
written with their info files; summary statistics are saved under
`reference_posteriors/summary_statistics/<type>/`. The posterior JSON
records the links and dimensions. `overwrite = FALSE` is the default and
causes an error if a destination file already exists. Each write happens
separately, so successful earlier writes remain if a later write fails.
Set `overwrite = TRUE` only when replacing existing files is intended.

If the associated posterior JSON is missing, writing reference draws
stops before writing any reference-draw or summary-statistic files. This
ensures the saved reference posterior is linked from an existing
posterior entry.

To save only the draws in that call, use
`write_summary_statistics = FALSE`. You can then write the summary
objects from the checked bundle individually:

``` r
write_pdb(
  bundle$reference_draws,
  pdbl,
  overwrite = FALSE,
  write_summary_statistics = FALSE
)
write_pdb(bundle$summary_statistics$mean_value, pdbl, overwrite = FALSE)
write_pdb(bundle$summary_statistics$mean_squared_value, pdbl, overwrite = FALSE)
```

The summary payload field names follow the existing PosteriorDB format:
`mean_value` contains `names`, `mean_value`, and `mcse_mean`;
`mean_squared_value` contains `names`, `mean_squared_value`, and
`mcse_mean`. The latter is the mean of squared draws, not a standard
deviation. Their info JSON uses the reference-draw metadata shape, with
`versions$r_summary_statistic` identifying the package version used to
compute the summaries.

For further details about accepted metadata and arguments, see
`?create_pdb_bundle`. The constructor requires the actual named Stan
input list for the default workflow. Alternatively, pass an existing
`pdb_data` object or its saved name, or supply a posterior whose linked
data can be retrieved. In all cases, the function cannot establish that
the supplied data was the data used to produce the fit. Automatic
recovery of sampling data from a fit is not supported. The importer’s
`policy = NULL` argument is retained for compatibility: it uses the
fixed package acceptance checks, and custom policies are rejected.

### Rename and bibliography recovery

`rename_pdb()` stages a migration before moving original data, model,
posterior, reference, and alias files. `append_reference()` validates
and stages the updated bibliography before replacing it:

``` r
rename_pdb("existing_data", "renamed_data", type = "data", pdb = pdbl)
append_reference("new-reference.bib", pdb = pdbl)
```

If reserving or installing a rename file fails, the migration attempts
to restore every moved original and remove installed targets. A
successful rollback restores the original file bytes and removes
temporary backups. If rollback is incomplete, the error identifies the
original and backup paths; the remaining backups are kept for recovery.
Other originals are still restored where possible.

If bibliography replacement fails, its original file is restored. If
that restoration also fails, a warning reports the retained backup and
its intended destination. The append operation raises an error and does
not report success or invalidate the previously cached bibliography.

After an incomplete rollback, resolve the filesystem problem and restore
the reported backups to their original paths before continuing database
writes. These recovery guarantees apply to rename and bibliography
operations; the whole-bundle writer still performs sequential writes as
described above.

## Reconstruct outputs from stored parameter draws

`reconstruct_stan_output()` evaluates a model at existing constrained
parameter-block draws. It performs no MCMC, diagnostics, or database
writes, and does not require a PosteriorDB connection.
`variables = NULL` returns all parameter, transformed-parameter, and
generated-quantity outputs, excluding `lp__` and sampler columns. Base
names select every indexed output element; exact indexed names are also
accepted.

For the eight schools bundle, reconstruct `theta` from the complete
parameter block (`theta_trans`, `mu`, and `tau`):

``` r
reconstructed <- reconstruct_stan_output(
  draws = bundle$reference_draws,
  model = bundle$model_code,
  data = bundle$data,
  variables = NULL
)
reconstructed$draws
reconstructed$timings

# Reuse the prepared evaluator without recompiling; omit data for fitted evaluators.
theta_only <- reconstruct_stan_output(
  draws = bundle$reference_draws,
  model = reconstructed$evaluator,
  variables = "theta"
)
```

The function accepts a data-bound RStan `stanfit` or CmdStanR
`CmdStanMCMC`, a compiled `stanmodel` or `CmdStanModel`, a Stan file
path, a single source string, or a `pdb_model_code`. Source/file inputs
and `CmdStanModel` source use RStan compilation and require matching
named data (`list()` for no data). A `CmdStanMCMC` uses native CmdStanR
model methods, which may compile additional C++ methods and require its
supporting files. Fitted evaluators already bind their data: leave
`data = NULL` when passing them.

The return value includes a `draws_array`, reusable evaluator, required
parameter names/shapes, backend, and preparation/setup/evaluation
timings. `include_unconstrained = TRUE` also returns intermediate
coordinates; CmdStanR uses positional `upars[i]` names. Every
constrained parameter-block column is required, even when requesting
just one derived output. Missing inputs raise an error; initialization
values are not substitutes for omitted draws.

For an already saved posterior, retrieve its components explicitly:

``` r
po <- posterior("existing_data-existing_model", pdb = pdbl)
reconstructed <- reconstruct_stan_output(
  reference_posterior_draws(po),
  model = model_code(po, framework = "stan"),
  data = get_data(po)
)
```

Alternatively, follow those links automatically with the convenience
wrapper:

``` r
reconstructed <- reconstruct_posterior_output(
  "existing_data-existing_model", pdb = pdbl, variables = NULL
)
```

The wrapper requires reference-draw metadata declaring `stan_sampling`
and a Stan model implementation. It retrieves the linked data
automatically and compiles the source using RStan. These metadata checks
do not prove model/data identity. Supply a posterior name or alias, not
a reference archive name. Ordinary draw retrieval does not reconstruct
automatically. Older archives may omit parameter-block inputs or store
derived variables instead; both reconstruction functions error when
required inputs are missing.

Important limitations:

- Deterministic outputs reproduce within numerical precision only with
  matching model/data. The function does not verify their identity.
- Random generated quantities are regenerated, not recovered exactly.
  `seed` initializes a new evaluator; it does not reset an existing
  evaluator’s RNG. Repeated calls advance that RNG. Random
  transformed-data calculations can also differ after initialization
  from source.
- Selecting fewer outputs does not skip full model-output evaluation.
  Large models may be expensive; reuse the evaluator to avoid repeated
  compilation.
- Divergences, tree depth, energy, and acceptance statistics are
  sampling history and are not reconstructed. Reconstructed output is
  not automatically certified or writable as reference draws.
- Supported inputs use scalar or rectangular numeric shapes; tuples and
  models without any nonempty parameter are not supported. Invalid
  serialized pointers require source and data for recompilation.

## Fit and provenance limitations

Bundle creation currently accepts completed RStan HMC fits, not CmdStanR
fits, optimization/variational results, or merged fits with
inconsistent/repeated chain IDs. CmdStanR fits can use the importer and
reconstruction function. Bundle source must be self-contained: saved
source containing `#include` is rejected. Zero-sized selected outputs
are rejected; an optional derived output can be excluded explicitly. A
fit that omitted required parameter variables cannot provide a complete
bundle or import.

The default recorded Stan version requirement (`>=2.26.0`) is not proof
of the version originally used for sampling. Bundle version metadata
describes the assembly environment. Preserve original sampling
provenance separately where needed. Unknown, duplicate, or misspelled
bundle arguments and unsupported metadata fields are rejected rather
than silently ignored.

Use a separate database directory when experimenting with writes.
Supplying a connection during construction does not persist anything,
but `write_pdb()` and `import_reference_posterior_draws(write = TRUE)`
do modify their explicit target.
