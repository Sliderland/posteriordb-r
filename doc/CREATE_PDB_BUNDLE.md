Create and contribute a reference-draw bundle
============================================

`create_pdb_bundle()` builds the data, model, posterior, and reference-draw
objects from an already sampled `rstan::stanfit`. It keeps the objects in
memory: it does not compile or sample a model, read from a database, or write
files. The current implementation supports RStan fits.

Prepare the fit and its exact Stan input list. The eight schools example from
this repository follows the model used in `CONTRIBUTING.md`:

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

Pass the same named list of inputs that was used for sampling, plus the
required names and titles for the data and model. Contributor and date defaults
are shared across the bundle; values in an individual metadata list override
those defaults.

    bundle <- create_pdb_bundle(
      fit,
      data = eight_schools,
      added_by = "Stanislaw Ulam",
      data_info = list(
        name = "test_eight_schools_data",
        title = "A Test Data for the Eight Schools Model",
        description = "The data contain treatment estimates and standard errors for eight schools."
      ),
      model_info = list(
        name = "test_eight_schools_model",
        title = "Test Non-Centered Model for Eight Schools",
        description = "A hierarchical model with a non-centered parameterization.",
        references = "rubin1981estimation"
      ),
      check = TRUE
    )

The result is a list with the individual objects:

    bundle$data
    bundle$model_code
    bundle$posterior
    bundle$reference_draws

`check = TRUE` (the default) computes the reference-draw diagnostics during
construction. Inspect the report before writing:

    bundle$diagnostics$status
    bundle$diagnostics$failures

If you prefer to create the objects first and check them later, set
`check = FALSE`. The constructor retains the sampler diagnostics needed for a
later check, but leaves the draws unchecked and not writable:

    bundle <- create_pdb_bundle(
      fit,
      data = eight_schools,
      data_info = list(name = "test_eight_schools_data", title = "Eight schools data"),
      model_info = list(name = "test_eight_schools_model", title = "Eight schools model"),
      check = FALSE
    )

    bundle <- check_reference_posterior_draws(bundle)
    bundle$diagnostics$status
    bundle$diagnostics$failures

Checking can return a bundle with failed criteria recorded. Write the draws
only after the checks pass. Then write each object explicitly to the local
database configured by `PDB_PATH` (or pass a `pdb_local()` connection):

    assert_checked_reference_posterior_draws(bundle$reference_draws)

    pdbl <- pdb_local()
    write_pdb(bundle$data, pdbl, overwrite = FALSE)
    write_pdb(bundle$model_code, pdbl, overwrite = FALSE)
    write_pdb(bundle$reference_draws, pdbl, overwrite = FALSE)
    write_pdb(bundle$posterior, pdbl, overwrite = FALSE)

Each call uses the existing `write_pdb()` method for that object. Data,
model, and reference-draw payloads are written with their info files; the
posterior JSON records the links and dimensions. With `overwrite = FALSE`, an
existing destination file causes an error. Writes happen one at a time, so a
later error does not roll back earlier successful writes. Use
`overwrite = TRUE` only when replacing existing files is intended.

The default variable selection retains saved parameters, transformed
parameters, and generated quantities, excluding `lp__`. Use `include` or
`exclude` with base variable names to select variables, for example
`include = c("mu", "tau")`. See `?create_pdb_bundle` for all arguments and
validation details.
