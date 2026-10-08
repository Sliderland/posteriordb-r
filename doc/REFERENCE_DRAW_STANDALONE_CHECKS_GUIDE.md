Design guide: standalone reference-draw checks
==============================================

**Proposal only.** This guide records possible behavior for future standalone
diagnostic checks. It does not describe functions that have been implemented
for bundles. The current bundle API checks the full acceptance set either in
`create_pdb_bundle(check = TRUE)` or later with
`check_reference_posterior_draws(bundle)`.

Purpose
-------

Let a contributor inspect one diagnostic criterion when investigating a fit,
without repeatedly running the entire acceptance suite. For example, someone
may want to check mean absolute lag-1 autocorrelation after changing sampling
settings. A focused result should make it easy to see the metric, threshold,
pass/fail result, and any variable or chain responsible for failure.

Possible interface
------------------

One option is a named function for each criterion, such as
`check_mean_lag1_ac(x)`, where `x` could be a completed RStan fit or a bundle.
The name should correspond to the metric in the diagnostic report:

- `check_ndraws()`
- `check_nchains()`
- `check_mean_lag1_ac()`
- `check_r_hat()`
- `check_efmi()`
- `check_divergent_transitions()`

These could be small, discoverable wrappers around shared diagnostic
calculation and evaluation code. Another option is to expose one general
function with a `checks` selector, then document short examples for selecting
one criterion. Before implementing aliases, compare this with the package's
existing `reference_draw_diagnostics()` and
`passes_reference_draw_checks()` functions to avoid overlapping public APIs.

The names above are illustrative. In particular, the code currently calls the
autocorrelation check `mean_lag1_ac`; the metric is the mean across chains of
the absolute chain-specific lag-1 autocorrelation for each variable.

Behavior to preserve
--------------------

- Use the same metric calculations, thresholds, variable selection rules, and
  failure details as the full reference-draw check. Do not duplicate formulas
  in each public wrapper.
- Return a diagnostic result that includes the selected metric, threshold,
  logical status, and relevant failures. If a convenience function returns a
  single logical value, retain an accompanying way to inspect the report.
- Support the same saved-variable selection rules as the full check, or state
  clearly if a standalone check only covers variables already selected into a
  bundle.
- Report unavailable or undefined metrics as unavailable or failed. Do not
  treat unavailable data as a passing result.
- Keep individual results separate from full acceptance evidence. Passing one
  criterion must never populate the complete `checks_made` flags or make
  `assert_checked_reference_posterior_draws()` succeed.
- Make clear whether a check only reports results or also updates an in-memory
  bundle. A read-only result is simpler to combine safely; if bundle mutation
  is desired, partial results must remain visibly partial and must not be
  mistaken for a completed acceptance check.

Acceptance criteria
--------------------

The current full reference-draw acceptance criteria are:

- exactly 10,000 retained draws total;
- at least four chains;
- mean absolute lag-1 autocorrelation no greater than 0.05 for every retained
  variable;
- R-hat no greater than 1.01 for every retained variable;
- E-FMI of at least 0.2 for every chain; and
- zero divergent transitions in every chain.

Bulk and tail effective sample size are calculated and stored for information,
but ESS bounds do not determine acceptance. A future diagnostic API should
keep this distinction clear: reporting an ESS value is useful, while adding an
ESS acceptance check would change the existing policy.

Example of the intended user experience
---------------------------------------

The exact function names and result shape remain to be decided. Conceptually,
a contributor should be able to ask for one check, inspect its result, then
run the full bundle check before writing:

    # Proposed API only; these calls are not implemented for bundles.
    ac_result <- check_mean_lag1_ac(bundle)
    ac_result$metric
    ac_result$status
    ac_result$failures

    bundle <- check_reference_posterior_draws(bundle)
    bundle$diagnostics$status

Only a bundle that passes the full acceptance set should be writable. A
successful standalone check is useful for investigation, but it is not a
substitute for the full check.

Implementation questions
------------------------

Before exposing standalone functions, decide:

1. Should they accept fits, bundles, or both? Fit checks can reuse the
   existing extraction path; bundle checks can use the retained draws and
   sampler diagnostics without sampling again.
2. Should named `check_*()` functions wrap one general diagnostic function,
   or should users select checks through one public function?
3. Should results be plain reports, logical values, or both through paired
   report and convenience functions?
4. If a bundle is accepted, should the function be strictly read-only, or
   should it attach partial results? Partial results must not set full
   acceptance flags.
5. How should unavailable sampler diagnostics be reported for checks such as
   E-FMI and divergent transitions?
6. Which diagnostic names should be public and stable, especially for the
   autocorrelation criterion (`mean_lag1_ac` versus a more explicit name)?

Keep `doc/CREATE_PDB_BUNDLE.md` as the usage guide for implemented bundle
behavior. Move material from this design guide there only after the matching
functions and semantics exist.
