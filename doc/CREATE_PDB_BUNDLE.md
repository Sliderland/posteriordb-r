<!-- CREATE_PDB_BUNDLE.md is generated from CREATE_PDB_BUNDLE.Rmd. Please edit that file. -->

# Create and contribute a reference-draw bundle

`create_pdb_bundle()` builds linked data, model, posterior, and
reference-draw objects around an already sampled `rstan::stanfit`. The
result is an R list that you can inspect and check before writing any of
its objects. The function does not compile or sample a model, read from
a database, or write files. The current implementation supports RStan
`stanfit` objects.

Choose the workflow based on whether the data, model, and posterior
records already exist:

- Use `create_pdb_bundle()` to construct new linked data, model,
  posterior, and reference-draw objects from a fit. Supply the data list
  and metadata; the function builds everything in memory and leaves
  persistence to you.
- Use `import_reference_posterior_draws()` when you already have a
  PosteriorDB posterior and want to import a completed fit for it. This
  supports RStan and CmdStanR fits, checks them, and can write the draws
  and summaries while linking them to the existing posterior. It does
  not rewrite the existing data, model, or posterior payloads.

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
call. The importer checks that fit variables and scalar dimensions match
the posterior specification, but it does not confirm that the fit used
the exact model source and data linked to that posterior.

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

Pass the same input list used for sampling, along with the required
names and titles for the data and model. `added_by` and `added_date` are
shared defaults for the objects in the bundle; a value in an individual
metadata list takes precedence.

`model_info$prior` is optional descriptive metadata, often a list of
keywords that points to prior information elsewhere in PosteriorDB. For
example, pass `prior = list(keywords = "stan_recommended_35dbfe6")` when
that reference is known. The bundle does not infer prior distributions
from the Stan source; if no prior metadata is supplied, the written
model info omits `prior`. The model writer does not emit a
`likelihood_code` entry. Optional model metadata is written only when
supplied; the writer does not add a `pymc` entry or a `pymc_version` by
default. The bundle API defaults the Stan implementation’s
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
    description = "A hierarchical model with a non-centered parameterization.",
    references = "rubin1981estimation"
  )
)
```

The constructor returns all four objects in memory:

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
metadata. Passing a `pdb` connection only attaches it to the objects; it
does not read or write database files.

## Choose when to compute diagnostics

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
decide whether the draws pass.

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

## Choose variables and write the objects

By default, the bundle includes saved parameters, transformed
parameters, and generated quantities, excluding `lp__`. Use `include` or
`exclude` with base variable names to select variables. For example,
`include = c("mu", "tau")` keeps all saved scalar elements of those
variables.

You can write the whole bundle with one call. If diagnostics have not
been computed yet, this checks the draws first. The data, model, and
posterior are written either way; reference draws and their summary
statistics are written only if all acceptance checks pass. The returned
report contains the checked bundle and records which components were
written or skipped:

``` r
pdbl <- pdb_local()
write_result <- write_pdb(bundle, pdbl, overwrite = FALSE)
write_result$written
write_result$reference_draws_written
write_result$skipped_reason
```

When a draw check fails, `write_result$bundle$diagnostics$failures`
describes the failed checks. A diagnostic error is recorded in
`write_result$diagnostic_error`; in either case, the three non-draw
objects are still written. Writing remains sequential, so an error
writing one of those objects can leave earlier successful writes in
place.

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
input list; it cannot establish that supplied data was the data used to
produce the fit.
