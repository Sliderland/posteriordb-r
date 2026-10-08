- [Create and contribute a reference-draw
  bundle](#create-and-contribute-a-reference-draw-bundle)
  - [Choose a workflow](#choose-a-workflow)
    - [Import a fit for an existing
      posterior](#import-a-fit-for-an-existing-posterior)
    - [Reuse existing bundle
      components](#reuse-existing-bundle-components)
  - [Add BibTeX references](#add-bibtex-references)
  - [End-to-end example: eight
    schools](#end-to-end-example-eight-schools)
  - [Create a new bundle: eight
    schools](#create-a-new-bundle-eight-schools)
    - [Supply metadata](#supply-metadata)
    - [Inspect the in-memory objects](#inspect-the-in-memory-objects)
  - [Choose when to compute
    diagnostics](#choose-when-to-compute-diagnostics)
  - [Choose variables](#choose-variables)
  - [Run existing reference workflows
    sequentially](#run-existing-reference-workflows-sequentially)
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

The similar conversion names have different responsibilities:

| Task | Entry point | Behavior |
|----|----|----|
| Look up a saved posterior | `posterior(name, pdb)` | Reads the existing record. |
| Construct posterior metadata from a list | `as.posterior(list(...), pdb)` | Uses prepared `pdb_data`, `pdb_model_code` and `dimensions`, or complete metadata. Writes nothing. |
| Wrap prepared draws and metadata | `as.reference_posterior_draws(draws, info)` | Attaches supplied metadata; does not calculate acceptance checks. Omits `lp__`. |
| Import a completed fit for a posterior | `as_reference_posterior_draws(fit, posterior, pdb)` | Validates counts and runs reference checks; writes nothing. |

The dotted `as.pdb_reference_posterior_draws()` alias also wraps draws.
The backend-named `as_reference_posterior_draws_from_stanfit()` and
`as_reference_posterior_draws_from_cmdstanr()` wrappers dispatch through
the generic using the actual fit class; prefer the generic for fit
import. Wrapping a draw object does not establish that it passes
contribution checks. Use `check_reference_posterior_draws()` or fit
import before writing it.

For prepared analytical draws, set `inference$method = "analytical"` in
the reference metadata and record `diagnostics$ndraws` matching the
retained draws. `check_reference_posterior_draws()` requires exactly
10,000 draws; `check_summary_statistics_draws()` permits at least
10,000. Analytical draws receive only the applicable count flag, without
invented HMC diagnostics. For Stan sampling, named diagnostic vectors
must describe the retained variables or the positional chain labels
`chain1`, `chain2`, etc. Reordered named vectors are supported;
unrelated or duplicate labels are rejected. Unnamed legacy vectors are
interpreted in the recorded variable/chain order. Diagnostics from
imported fits, immediate/deferred bundles and internally sampled draws
use shared calculations. RStan E-FMI retains its division by the number
of energy draws; CmdStanR retains division by the number of energy
differences. Missing sampler evidence remains unavailable and cannot
establish acceptance; generic draw arrays never invoke an RStan fit
accessor.

Parameter selection uses the fitted model’s parameter-block schema,
separately from free-coordinate counts. A `simplex[1]` has one saved
value and zero free coordinates: it is retained and cannot be excluded,
but contributes no entry to `dimensions`. Truly zero-sized saved outputs
remain unsupported by bundle extraction. Undefined diagnostics for
constant constrained entries remain unavailable; they are never stamped
successful. Such candidates remain inspectable, with failed checks
preventing reference writes. Numeric or integer positive count inputs
have the same validation rules. ESS remains informational, including
when its labels cannot be matched.

The ordinary reference-draw writer also supports them and writes the two
supported summaries by default once the posterior link is saved. This
does not add analytical fits to `create_pdb_bundle()`, which remains a
Stan-fit workflow.

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

To check the structure and getter-visible content of an in-memory
posterior, including unsaved edits, use:

``` r
check_pdb_posterior(bundle$posterior, run_stan_code_checks = FALSE)
```

This validates the supplied object without reloading its saved posterior
record. A standalone object needs no database when it has no citations.
If posterior, model, or data citation keys are supplied, attach a
database so they can be checked against its bibliography. Use
`check_pdb(pdbl)` for saved database records and database-wide
consistency. Structural checking does not replace the reference-draw
acceptance checks described below.

### Import a fit for an existing posterior

For CmdStanR fits, retain supporting model/data files and sample with
`sig_figs = 18`. Count inference uses CmdStanR’s compiled unconstraining
methods; rounded CSV values can violate constraints such as unit
Cholesky rows and cause those methods to reject the fit. No approximate
counts are substituted.

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
columns are retained. `exclude` removes optional outputs from the
default all-output selection. Naming a variable in both selectors, or
explicitly excluding a dimension or parameter-block variable, raises an
error. Unknown names are errors. Without these arguments, all saved
model outputs except `lp__` are retained. This can retain more variables
than older importer versions. Diagnostics and written summaries cover
the retained selection, not omitted outputs. Existing dimensions are not
changed. Required variables missing from the saved fit cause an error.
Retaining the complete parameter block provides the inputs needed by
`reconstruct_stan_output()`, but the importer does not itself
reconstruct outputs or verify model/data identity. Random generated
quantities cannot generally be recovered exactly.

The importer stages the reference-draw files, summaries, and any
required posterior-link update, checks their round trip, and restores
originals if the operation fails. If rollback cannot remove an installed
file or restore an original, warnings identify the remaining installed
files and retained backups with their intended destinations. Resolve the
filesystem problem and restore the reported backups before continuing
writes. This is its transactional import path; it differs from the
sequential whole-bundle writer below. Updating a previously empty
posterior link is allowed with `overwrite = FALSE`; that flag controls
replacement of existing draw and summary files. Conversion-only helpers
`as_reference_posterior_draws()`,
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

## Add BibTeX references

Before checking a bundle that cites a new reference, add the entry to
your local checkout’s `bibliography/references.bib` with
`append_reference()`. It accepts three input forms:

``` r
pdbl <- pdb_local("/path/to/posteriordb/posterior_database")

# 1. Pasted BibTeX text: exactly one entry with a citation key.
append_reference(
  "@misc{my-study, title={My study}, year={2026}}", pdb = pdbl
)

# 2. A .bib file: one or more entries.
append_reference("new-references.bib", pdb = pdbl)

# 3. An R bibentry object: one or more entries.
ref <- utils::bibentry(
  "Misc", key = "my-software", title = "My model implementation",
  year = "2026"
)
append_reference(ref, pdb = pdbl)
```

You can also obtain a `bibentry` object with
`bibtex::read.bib("new-references.bib")` and pass it to
`append_reference()`. Choose the form that matches what you already
have. Duplicate citation keys (ignoring case) and duplicate entries are
rejected before changing the bibliography. A successful append
invalidates the cached bibliography.

Use the citation keys, such as `references = "my-study"` or
`references = c("my-study", "my-software")`, in `data_info`,
`model_info`, or `posterior_info`; these fields do not add BibTeX
entries themselves. Inspect the available keys with
`bibliography_keys(pdbl)`.

Retrieve an entry by key with `bibliography_entry()` and display its
BibTeX with `utils::toBibtex()`:

``` r
entry <- bibliography_entry("my-study", pdb = pdbl)
utils::toBibtex(entry)
```

## End-to-end example: eight schools

This is a continuous version of the eight-schools contribution in
`CONTRIBUTING.md`, using the bundle API instead of constructing and
writing each object separately. Run it with this version of the R
package, RStan, and a working C++ toolchain. Replace the database path
and contributor name before running it. The database path identifies
your local contribution checkout; this example writes files there after
the checks pass.

The data/model names below are demonstration names. Choose unused names
for a new contribution. If these records already exist, use the
existing-record workflow above rather than assuming `overwrite = TRUE`
is appropriate. As in the original guide, the citation key
`rubin1981estimation` must already exist in the database bibliography;
[add a missing reference](#add-bibtex-references) before proceeding.

``` r
library(posteriordb)
library(rstan)

# 1. Connect to your local PosteriorDB checkout explicitly.
database_path <- "/path/to/posteriordb/posterior_database"
pdbl <- pdb_local(database_path)
stopifnot("rubin1981estimation" %in% bibliography_keys(pdbl))

# 2. Keep the exact input list used for sampling.
source(system.file("test_files/eight_schools.R", package = "posteriordb"))
stan_file <- system.file(
  "test_files/eight_schools_noncentered.stan", package = "posteriordb"
)
stan_model <- rstan::stan_model(file = stan_file, auto_write = FALSE)
fit <- rstan::sampling(
  stan_model, data = eight_schools,
  chains = 10, iter = 20000, warmup = 10000, thin = 10,
  seed = 4711, control = list(adapt_delta = 0.99), refresh = 0
)
# 1,000 retained post-warmup draws per chain: 10,000 draws in total.

# 3. Construct all linked objects in memory and calculate diagnostics.
bundle <- create_pdb_bundle(
  fit, data = eight_schools, added_by = "Your Name",
  data_info = list(
    name = "test_eight_schools_data",
    title = "Eight schools treatment estimates",
    description = "Treatment estimates and standard errors for eight schools.",
    references = "rubin1981estimation"
  ),
  model_info = list(
    name = "test_eight_schools_model",
    title = "Non-centered eight schools model",
    framework = "stan",
    description = "A hierarchical model with a non-centered parameterization.",
    references = "rubin1981estimation"
  ),
  posterior_info = list(references = "rubin1981estimation"),
  reference_info = list(comments = "Eight schools bundle contribution."),
  include = NULL, exclude = NULL, check = TRUE, pdb = pdbl
)
bundle$posterior$name
bundle$posterior$dimensions
# theta_trans = 8, mu = 1, tau = 1: unconstrained counts, not output shapes.
# include = NULL also retains all eight derived theta values for diagnostics.

# 4. Inspect acceptance before writing anything.
bundle$diagnostics$metrics
bundle$diagnostics$status
bundle$diagnostics$failures
assert_checked_reference_posterior_draws(bundle$reference_draws)
check_pdb_posterior(bundle$posterior, run_stan_code_checks = FALSE)

# 5. Write the accepted bundle and inspect the returned report.
write_result <- write_pdb(bundle, pdbl, overwrite = FALSE)
write_result[c("written", "reused", "reference_draws_written",
               "summary_statistics_written", "skipped_reason")]
bundle <- write_result$bundle
stopifnot(isTRUE(write_result$reference_draws_written),
          isTRUE(write_result$summary_statistics_written))

# 6. Read the saved contribution through a fresh cache.
read_cache <- tempfile("eight-schools-readback-")
dir.create(read_cache)
read_pdb <- pdb_local(database_path, cache_path = read_cache)
saved_posterior <- posterior(bundle$posterior$name, pdb = read_pdb)
check_pdb_posterior(saved_posterior, run_stan_code_checks = FALSE)
saved_data <- get_data(saved_posterior)
saved_code <- model_code(saved_posterior, framework = "stan")
saved_draws <- reference_posterior_draws(saved_posterior)
saved_summaries <- reference_posterior_summary_statistics(saved_posterior)
saved_array <- posterior::as_draws_array(saved_draws)
stopifnot(posterior::ndraws(saved_array) == 10000L,
          posterior::nchains(saved_array) == 10L,
          setequal(names(saved_summaries), c("mean_value", "mean_squared_value")))
posterior::variables(saved_array)
# theta_trans[1:8], mu, tau, and theta[1:8] are saved as individual columns.
```

The sampling settings retain the original guide’s draw count, with a
higher `adapt_delta`. They do not guarantee acceptance: inspect any
failed checks, address the sampling problem, and construct a new bundle
from the new fit. The assertion in step 4 stops this example before
persistence when checks fail. Without that assertion, the bundle writer
can write data/model/posterior components while skipping rejected
reference draws and summaries. A small trial fit can demonstrate
construction, but will fail the required draw-count check and cannot
supply accepted reference draws.

There are 18 saved scalar columns in this model, but only 10
unconstrained parameters. `theta` is derived and contributes no
unconstrained coordinates; `include = NULL` nevertheless keeps it, so
its diagnostics also affect acceptance. To keep only the parameter
block, use `include = "none"` or `character(0)` instead. The example
uses `exclude = NULL` to omit nothing.

If step 5 fails with an I/O or serialization error, earlier successful
writes remain and the failing component may be incomplete. The failure
message reports completed components; the failed call does not return a
write report. Inspect the files, fix the cause, and review existing
paths before deciding whether to retry with `overwrite = TRUE`. That
option replaces files at the selected names; it is not automatic
recovery. See **Write the objects** below for the full partial-write and
retry behavior.

Finally, review the local database changes, including newly created
files:

``` sh
git -C /path/to/posteriordb status --short
git -C /path/to/posteriordb diff
```

`git diff` does not show the contents of untracked files: open the new
metadata and Stan source, and inspect payloads through the read-back
objects above. Check the names, citation keys, unconstrained counts,
persisted reference link, and selected outputs. Commit the reviewed
contribution files in your database checkout and open a pull request.
The R package checkout and the PosteriorDB data checkout are separate
repositories; the contribution files belong in the latter. The following
sections explain the individual steps and alternatives.

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

For stored summaries,
`reference_posterior_summary_statistics(posterior)` returns a named list
of types advertised by reference metadata, or an empty list when no
reference is linked. Types without metadata are omitted. A malformed or
unreadable advertised summary is an error, including a missing payload;
remote listing/transport errors also surface. Inspect and repair the
stored files rather than treating that error as a lack of summary
statistics.

The posterior embeds the data, model code, and reference draws, so its
getters work before persistence. `bundle$provenance` records how the
input data was obtained, the fit class, selected variables, and sampling
metadata. Passing a `pdb` connection attaches it to the objects; when a
saved object name is supplied, the connection is also used to retrieve
that object. Construction never writes database files.

If a serialized RStan fit no longer exposes its compiled parameter-name
methods, bundle construction recompiles the saved Stan source and uses
the supplied data to recover unconstrained parameter counts, bypassing
RStan’s lookup of same-source archived models. Errors from available
methods, including inconsistent counts or invalid names, propagate
without recompilation. This does not resample or replace the fit’s saved
draws. RStan may print
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

Stored summaries are validated by field name, so JSON field order does
not matter. Variable names must be unique and nonmissing, with one
numeric summary value and MCSE per name. Attached reference metadata is
validated too. Numeric `NA` and infinite entries retain the existing
permissive validation behavior; this cleanup does not impose a new
numerical policy.

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

Explicit reference-draw payloads require unique, nonmissing, nonempty
variable labels in the same order across chains. Retained vectors must
have equal lengths across variables and chains. Wrapping allows
zero-iteration objects, but those cannot satisfy the count requirements
for an accepted reference write. Mutating an object’s class or retaining
old acceptance flags does not bypass these checks. The acceptance
assertions repeat structural validation before using saved flags;
summary computation also rejects modified draws with invalid labels or
lengths.

For an existing reference-draw object, `subset(draws, variable = ...)`
keeps diagnostics for the selected variables and clears acceptance flags
when the selection changes. Recheck that object before writing it.
`posterior::thin_draws(draws, thin = ...)` updates retained counts and
clears obsolete diagnostics and acceptance evidence. Saved sampler draws
are thinned in lockstep; the old E-FMI is discarded. Subsetting and
thinning preserve the class chain, including prepended subclasses. These
transformations preserve the attached connection and do not write files.
Thinned draws still need to meet the unchanged acceptance requirements,
including exactly 10,000 retained draws for a reference-draw write.

The package uses the same selection conventions in bundle creation,
internal reference sampling, fit import, standalone diagnostics, and
unconstrained-count inference. All default to `include = NULL` and
`exclude = NULL`.

| Value | Meaning in `include` | Meaning in `exclude` |
|----|----|----|
| `NULL` | Select all applicable variables | Exclude nothing |
| `"all"` | Select all applicable variables | Reduce to the minimum required selection |
| `"none"` | Select the minimum required selection | Exclude nothing |
| `character(0)` | Select the minimum required selection | Exclude nothing |
| Explicit base names | Select those names plus any mandatory variables | Remove those names; required variables cannot be explicitly excluded |

`"all"` and `"none"` are reserved only when used alone. `c("all")` is
the same as `"all"`; `c()` is NULL, so an empty `c()` includes all
rather than requesting the minimum. Unknown names, duplicate names,
missing values, and empty or blank strings are errors. `lp__` is never
selected: explicitly including it is an error, and explicitly excluding
it is a harmless no-op. Base names select every saved indexed column, so
`include = "theta"` selects all eight saved elements in the
eight-schools example.

The applicable variables and minimum selection depend on the function:

| Workflow | All applicable variables | Minimum required selection |
|----|----|----|
| `create_pdb_bundle()` | Saved parameters, transformed parameters, and generated quantities, except `lp__` | Complete parameter block |
| `compute_reference_posterior_draws()` | All saved model outputs except `lp__` | Complete parameter block plus dimension-listed variables |
| `as_reference_posterior_draws()` / `import_reference_posterior_draws()` | All saved model outputs except `lp__` | Complete parameter block plus dimension-listed variables |
| `reference_draw_diagnostics()` / `passes_reference_draw_checks()` | All saved model outputs except `lp__` | Empty; raises an empty-selection error |
| `infer_posterior_dimensions()` / `infer_unconstrained_parameter_counts_from_fit()` | All inferred nonzero parameter counts | Empty; raises an empty-selection error |

Dimension helpers select parameter counts, not derived outputs or
constrained shapes. Every saved parameter-block variable remains
mandatory in a bundle, compute, or import selection, including
zero-free-coordinate parameters such as `simplex[1]`. Explicitly
excluding one raises an error. A dimension-listed derived output is also
mandatory for compute and import.

To retain and diagnose everything except a saved derived output, omit
`include` and specify only `exclude`. For example, for a model saving
`exp_mu`:

``` r
draws <- compute_reference_posterior_draws(rpi, pdb, exclude = "exp_mu")
draws <- check_reference_posterior_draws(draws)
write_pdb(draws, pdb)
```

The same selector works in bundle creation, import, and standalone
diagnostics when that output is available and is not mandatory.
`include = "all"` with that exclusion is valid but redundant. Use
`include = "none"` or `exclude = "all"` for required variables only in
bundle, compute, or import. In diagnostics and count helpers, those
requests leave nothing to process and raise an error.

Naming the same variable explicitly in both selectors is a configuration
error. For example, `include = "exp_mu", exclude = "exp_mu"` fails
instead of silently removing it. This also applies to mixed vectors such
as `include = c("mu", "exp_mu"), exclude = "exp_mu"`. The aliases are
controls, not explicit variable names: `exclude = "all"` always requests
the minimum selection, even with named inclusions.

Both stored outputs and variable-level diagnostics use the retained
selection. Acceptance does not certify omitted outputs. Constant outputs
can have undefined R-hat or autocorrelation and may fail the unchanged
checks. Counts are independent of output selection: for example,
`simplex[3]` has three saved values but two unconstrained coordinates,
and derived outputs add no counts.

**Compatibility:** compute and import previously defaulted to required
variables only; both now select all saved outputs. Existing calls may
return more variables and fail acceptance when an additional output has
poor or undefined diagnostics. Pass `include = "none"` to retain the
previous minimum selection. Callers that explicitly named a variable in
both selectors must remove that contradiction; named exclusion no longer
silently overrides it. These conventions apply to the package’s
output/count selectors, rather than backend-specific sampler options
passed inside `stan_args`.

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

## Run existing reference workflows sequentially

`sequential_batch_workflow()` takes a list of reference-info objects
declaring `stan_sampling`. Each object’s `name` identifies the posterior
to sample; names on the outer list label workflows and match
per-workflow settings. Supply an explicit connection and inspect each
result. For two prepared objects:

``` r
workflows <- list(a = reference_info_a, b = reference_info_b)

# One shared argument list, including ordinary nested control/init values.
shared <- list(iter = 5000, warmup = 2500, chains = 4,
               control = list(adapt_delta = 0.95))
results <- sequential_batch_workflow(workflows, sampling = shared, pdb = pdbl,
                                    write = FALSE, on_error = "continue")

# An explicit single-list wrapper also means shared settings.
results <- sequential_batch_workflow(workflows, sampling = list(shared), pdb = pdbl)

# Per-workflow settings: unnamed entries follow the workflow order.
per_workflow <- list(list(iter = 5000, warmup = 2500, chains = 4),
                     list(iter = 6000, warmup = 3500, chains = 4))
results <- sequential_batch_workflow(workflows, sampling = per_workflow, pdb = pdbl)

# Matching workflow names allow reordering when unambiguous.
named_settings <- list(b = per_workflow[[2]], a = per_workflow[[1]])
results <- sequential_batch_workflow(workflows, sampling = named_settings, pdb = pdbl)
```

Prefer the unnamed per-workflow form when workflow names overlap sampler
option names. A named nested list such as
`list(wrong = list(iter = 20))` is currently treated as shared sampler
arguments, rather than a rejected workflow map. Check the names
yourself; automatic rejection of ambiguous maps is deferred. Use
`list(shared)` to state a shared configuration explicitly.

With `on_error = "continue"`, later workflows still run after a failure.
With `"stop"`, remaining records have status `"not_run"`. Results retain
the supplied sampling arguments, last stage, error message, returned
draws where available, and write/link flags. `write = TRUE` requires
checking; inspect each result rather than assuming all workflows
succeeded. The shared and per-workflow forms replace each reference-info
object’s stored method arguments for this run.

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

To link reference files already stored in a destination, use
`link_reference_posterior(posterior_name, reference_posterior = reference_name, pdb = my_pdb)`.
Both the reference info and draw archive must exist there. With a
posterior object, an explicit `pdb` selects the destination and its
saved posterior record is read by name. Omitting `pdb` uses the object’s
attached connection.

Cached data/draw archives must contain one JSON file with the requested
filename at the archive root. Unexpected members, nested paths, and
unsafe cache destinations are rejected before extraction. Linking and
renaming use the same archive-member validation. Failed extraction
removes incomplete output rather than retaining it as a cached file or
repacking it during rename.

Resource names must be nonempty single path components. Names such as
`example.v2-model` are valid; names containing `/`, `\\`, control
characters, or the entire name `.` or `..` are rejected during
construction and writing. The same rule applies to rename, link, and
import operations. Relative model implementation paths such as
`models/stan/example.v2-model.stan` remain paths, not resource names.

Database name listings preserve dots within identifiers, ignore
unrelated files and directories, and return `character(0)` when no
matching records exist. Posterior records use `.json`; data, model and
reference metadata use `.info.json`. Metadata table and keyword-search
reads also ignore subdirectories. Failed local metadata copies or GitHub
downloads report an error and remove partial cache files. GitHub
downloads retain a file that was already cached before the failure.

For data or model objects with an attached database connection,
`posterior_names(object)` follows the stored `data_name` or `model_name`
links. It does not infer links from posterior filenames, so identifiers
containing hyphens or dots are supported. Standalone objects need a
database connection before their linked posterior names can be queried.

Existing model code is read from the selected implementation’s declared
`model_code` path, including custom filenames. Legacy metadata without a
code path uses the conventional framework location and extension
(`.stan` for Stan, `.py` for the supported Python frameworks).
Model-code removal uses the same path; `remove_info = FALSE` retains
metadata for other implementations. Refresh the connection or clear its
cache after removal. For posterior or model-info inputs, the supplied
object’s implementation metadata selects the file for both code and
file-path access. A posterior can look up additional implementations
through its attached database when they are absent from its own
metadata. Non-Stan writing and custom-path writer support remain open in
the issue guide; the current model-code writer writes to conventional
Stan locations. Non-Stan payload writing is not implemented and can fail
after saving model metadata, so use this writer only for conventional
Stan model-code writes.

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

If an I/O or serialization error interrupts a bundle or individual
component write, the operation stops and keeps files already written or
replaced. The failure message identifies the destination, and a bundle
failure lists completed components. The failing component may have only
its info file or some payloads saved; a failed ZIP command keeps the
uncompressed JSON for inspection. A failed call does not return a
successful write report.

Inspect `git status` and `git diff` in your local database checkout,
including new untracked files, before retrying. Fix the cause of the
error (for example, permissions, disk space, or the ZIP command), review
any incomplete files, and rerun the workflow. Existing new-component
files require an intentional `overwrite = TRUE`; reused components are
never overwritten, and incomplete reused components must be resolved
before rerunning. Refresh the connection or clear its cache before
checking changed files. Review the resulting metadata, links, and
payloads before committing them and opening the contribution pull
request. The pull request supplies a further review step; a partial
write does not establish that the contribution is complete or
acceptable. Automatic rollback for these writes remains an open policy
question in the implementation issue guide.

Use `reference_posterior_names(pdbl, type = "draws")` to list stored
draw references. Use `type = "mean_value"` or
`type = "mean_squared_value"` to list the corresponding stored
summaries. Each type is listed separately for local and GitHub
connections. These are reference names and can differ from the linked
posterior names. Summary getters use the stored reference link for both
metadata and payload.

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

Rename checks the ZIP command result, member name and extracted payload
bytes before moving any original files. A staging failure leaves
originals intact. If reserving or installing a rename file fails, the
migration attempts to restore every moved original and remove installed
targets. A successful rollback restores the original file bytes and
removes temporary backups. If rollback is incomplete, the error
identifies the original and backup paths; the remaining backups are kept
for recovery. Other originals are still restored where possible.

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

When computing new reference draws with
`compute_reference_posterior_draws(..., backend = "cmdstanr")`, stored
sampler arguments can use RStan-style `iter`/`warmup`, `cores`, and
supported `control` settings. `stepsize` maps to `step_size`;
`adapt_init_buffer`, `adapt_term_buffer`, and `adapt_window` map to
`init_buffer`, `term_buffer`, and `window`. `adapt_delta`,
`max_treedepth`, `adapt_engaged`, and `metric` retain their names.
Unsupported controls (such as `adapt_gamma` or `stepsize_jitter`) raise
an error before compilation. Conflicting aliases or nested/direct
settings also raise an error; supply each setting once. NULL `iter`,
`warmup`, and `control` entries are omitted. To disable CmdStanR’s
post-sampling diagnostics, use `diagnostics = NULL`; do not combine it
with the legacy `validate_csv` alias. Existing-fit import does not
replay these settings or sample again.

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

Existing-posterior imports record the current R session and Makevars,
and the installed backend interface version. RStan’s recorded Stan
version also comes from its currently installed library. A CmdStanR
import does not probe or add RStan versions; its CSV-reported Stan
version describes the fitted executable and is retained when available.
These environment fields do not prove which package versions produced an
archived fit; unavailable historical evidence remains unknown.

Use a separate database directory when experimenting with writes.
Supplying a connection during construction does not persist anything,
but `write_pdb()` and `import_reference_posterior_draws(write = TRUE)`
do modify their explicit target.
