# posteriordb (rewrite)

An R interface to [posteriordb](https://github.com/stan-dev/posteriordb), a
database of Bayesian posteriors with models, data and reference posterior
draws.

## Reading

```r
library(posteriordb)
pdb <- pdb_github()                   # or pdb_local("path/to/posteriordb")
posterior_names(pdb)
po <- posterior("eight_schools-eight_schools_noncentered", pdb)
stan_code(po)
get_data(po)
reference_posterior_draws(po)         # a posterior::draws object
reference_posterior_summary_statistic(po, "mean_value")
```

Set `PDB_PATH` (or `options(pdb_path = ...)`) to make a local checkout the
default. GitHub connections use the `gh` package and `GITHUB_PAT`.

## Adding reference posteriors

```r
fit <- rstan::stan(...)               # or a cmdstanr fit
diagnostics <- reference_draw_diagnostics(fit)
import_reference_posterior_draws(fit, "my_posterior", pdb, write = TRUE)

# A new posterior with its data, model and draws in one step:
bundle <- create_pdb_bundle(fit, data = my_data, model_code = code,
                            data_info = list(name = "my_data", title = "..."),
                            model_info = list(name = "my_model", title = "..."))
write_pdb(bundle, pdb)
```

Draws are only written when they pass the reference checks: 10,000 draws,
at least 4 chains, R-hat at most 1.01, mean lag-1 autocorrelation within
±0.05, E-FMI at least 0.2 and no divergent transitions. Writes never
replace different content unless `overwrite = TRUE`, and a write that
would conflict in any file writes nothing.

## Tests

`devtools::test()` runs offline against a small fixture database. Opt-in
tests:

- `PDB_TEST_STAN=true`: one real rstan run of eight schools.
- `PDB_PATH=<checkout>`: `check_pdb()` and every reference posterior's checks on a full database.
- `PDB_TEST_GITHUB=true` (and optionally `PDB_TEST_GITHUB_REPO=owner/repo`): reading over the GitHub API.
