# Test-suite review: fit imports and reference diagnostics

Reviewed on 2026-10-01 at commit
`55e667e2b11267a5ab9db76e5a15c15ea82c6376`.

The tests provide useful protection for acceptance rules, persistence, cache
refresh, and rollback. CmdStanR coverage is weaker: the import test uses a
synthetic object and does not establish that a genuine CSV-backed fit imports
correctly. The smallest useful improvements are stricter mock arguments, one
real CmdStanR fixture, and complete comparisons of persisted draws.

## Scope and limits

This report covers the exploration of external RStan/CmdStanR imports and
their related reference-draw acceptance and diagnostic tests. It is not a
review or execution of the entire package test suite. Related bundle tests
were inspected for constrained-parameter coverage, but were not part of the
focused execution reported below.

The maintainer indicated that this checkout is slightly outdated. Findings
apply to the reviewed snapshot and available local history; recheck them
against the newer branch before making changes. No package implementation or
test files were changed during this review.

## Where the tests came from

The table distinguishes new coverage from later assertion and fixture updates.

| Commit | Date | Coverage added or changed |
| --- | --- | --- |
| `e341b0c` | 2026-09-18 | Added a test that lag-1 autocorrelation averages absolute per-chain values for each variable. |
| `bb635c3` | 2026-09-18 | Added a test that poor ESS is recorded without rejecting draws. It reads a configured database through `PDB_PATH`. |
| `0291a0f` | 2026-09-18 | Introduced external RStan import tests: scalar-variable filtering, dimension declarations, sampler metadata, unsupported fits, failed-check write protection, and writer round trips/overwrite. |
| `a52d05c2` | 2026-09-18 | Added unsupported-option rejection, public posterior linking, final-verification rollback, linked-record rollback, and stronger cache-refresh assertions. Replaced the writer's external-database dependency with synthetic checked draws. Added acceptance tests for malformed/missing diagnostics, divergences, inconsistent counts, empty variables, informational ESS, and undefined autocorrelation; also added dimension-declaration tests. |
| `43b35058` | 2026-09-21 | Added one CmdStanR import test and a synthetic `CmdStanMCMC` fixture. Checks output class, variable filtering, iteration/warmup metadata, E-FMI field presence, backend comments, and package-version metadata. |
| `9c0848d` | 2026-09-24 | Added selective-diagnostic tests, invalid checks/selectors, shared-policy assertions, unavailable sampler metrics, and tolerant versus strict RStan sampler extraction. |
| `f96dbb0` | 2026-09-24 | Added include/exclude composition, constant-variable reporting, aggregate failures, exact policy boundaries, per-scalar R-hat, and malformed sampler-array checks. |
| `e268a35` | 2026-09-24 | Strengthened lag-only tests with functions that throw if unrelated R-hat, ESS, or E-FMI calculations run. Replaced an unconditional acceptance assertion on random draws with comparison to the reported status. |
| `3dd4dc1` | 2026-09-24 | Added sampler-contract tests for undefined energy diagnostics, named chain failures, independent optional metrics, and mismatched sampler dimensions. |
| `c986828` | 2026-09-25 | Updated sampler-metadata assertions for collapsing identical per-chain arguments. |
| `1eb3531` | 2026-09-28 | Updated fixtures for scalar unconstrained parameter counts, linked-posterior writing, required database directories, and CmdStanR unconstraining. These updates follow changed behavior rather than introducing a real CmdStanR integration test. |

`a52d05c2` also changed bibliography, search, and cache tests. Those changes
are outside this report's fit-import and diagnostic scope.

## Execution results

The following files were run against the current checkout with
`pkgload::load_all(..., helpers = FALSE, export_all = FALSE)` and
`testthat::test_file()`:

| Test file | Passed test blocks | Skipped test blocks |
| --- | ---: | ---: |
| `test-import-external-stanfit.R` | 11 | 0 |
| `test-reference-draw-diagnostics.R` | 11 | 0 |
| `test-generic-sampler-contract.R` | 1 | 0 |
| `test-lag1-autocorrelation.R` | 9 | 1 |
| `test-posterior-dimension-names.R` | 2 | 0 |
| **Total** | **34** | **1** |

No test failures, test errors, or testthat warnings were reported. The RStan
import tests compiled and sampled a real small model. The compiler emitted
macOS cache-permission messages, but the process completed and the assertions
passed.

The skipped test was the database-dependent ESS test: no `PDB_PATH` test
database was configured. The synthetic ESS test executed successfully.

Separately, commit `43b35058` was extracted into a disposable directory. Its
original CmdStanR test was executed against that snapshot, using the locally
installed dependencies, and all seven assertions passed. This is not a
reproduction of the dependency versions available when the commit was made.

These runs used disposable database fixtures. They did not run the full suite
against a maintainer's working PosteriorDB checkout. Development loading also
does not establish installed-package S3 registration behavior.

## Assessment and follow-up work

### 1. CmdStanR integration is not established — high priority

Source: [CmdStanR fixture and test](../tests/testthat/test-import-external-stanfit.R).

The test title says that fits are imported through their CSV-backed methods,
but the fixture is an environment assigned CmdStanR class names. Its methods
return synthetic arrays; no CSV files or genuine CmdStanR fit are involved.

This is a valid unit test of the converter's expected object interface. The
wrapper forwards through the S3 generic, so the test exercises dispatch under
development loading as well as filtering and metadata assembly. It does not
verify the actual backend interface, CSV reading, or a successful accepted
CmdStanR import followed by persistence. The fixture has only 80 retained
draws across two chains, below the current acceptance requirements.

Follow-up: retain the unit test, give it an accurate title, and add one small
genuine CmdStanR fixture test using saved CSV output. Exercise the exported
generic and compare the imported post-warmup values, variables, chain counts,
and metadata. Confirm that the fixture also supports any model information
needed for unconstrained-count inference. Keep successful acceptance/write
coverage explicit rather than implying that this small fixture provides it.

### 2. Mock arguments and numerical diagnostics are weakly checked — high priority

Source: [CmdStanR mock methods](../tests/testthat/test-import-external-stanfit.R).

The mock's `draws()` and `sampler_diagnostics()` methods accept but ignore
`inc_warmup` and `format`. A regression that requests warmup draws or the wrong
format could still pass. The import test checks only the presence of the
E-FMI field, not its numerical values. The later unconstraining mock returns
the same unconstrained real-scalar data and does not test actual constraints.

Follow-up: assert the requested arguments inside the existing mock and check
diagnostic values against a small, independently specified energy sequence.
This needs a few assertions, not a new mocking framework.

### 3. Persistence assertions cover only part of the data — medium priority

Source: [writer round-trip and public-linking tests](../tests/testthat/test-import-external-stanfit.R).

The writer test checks variable names, total draws, chains, and `alpha` values
from the first chain. It also verifies that replacing draws refreshes cached
reads. Those are useful checks, but corruption of another variable or chain
could escape the value comparison. The public-linking test mocks conversion,
which correctly isolates orchestration but does not test fit extraction
through to persistence.

Follow-up: compare every variable and chain after serialization, with an
appropriate numerical tolerance, and verify persisted metadata relevant to
the public contract. Keep the targeted orchestration mock; complement it
with limited integration coverage rather than replacing it.

### 4. Rollback tests are strong but cover one failure stage — medium priority

Source: [rollback tests](../tests/testthat/test-import-external-stanfit.R).

Injecting a failure in final verification is an appropriate way to exercise
rollback. Comparing original and restored files byte-for-byte is stronger
than merely asserting that files exist. The linked-record test similarly
verifies restoration of the posterior JSON.

These tests do not establish behavior for failure partway through installing
files or failure while restoring a backup. The linked-record test also does
not explicitly assert that newly created reference files disappear.

Follow-up: first add assertions that new files are absent after the existing
failed-creation case. If the writer is changed, add one targeted mid-install
failure case. These are coverage gaps, not reproduced rollback defects.

### 5. Constrained parameter counts need real regression coverage — medium priority

Sources: [import tests](../tests/testthat/test-import-external-stanfit.R),
[dimension-name tests](../tests/testthat/test-posterior-dimension-names.R), and
[bundle extraction tests](../tests/testthat/test-bundle-fit-extraction.R).

The current import fixtures use ordinary real scalars and matrices, whose
saved element counts equal their free parameter counts. They do not establish
the distinction needed for constrained types. A simplex of length K, for
example, has K saved elements and K - 1 free coordinates. Some bundle tests
mock count inference, which is appropriate for testing assembly but cannot
validate the inference itself.

Follow-up: add a small real constrained-parameter fixture and assert saved
variable coverage separately from unconstrained counts. Start with a simplex;
extend to other constrained types when their inference logic changes.

### 6. Diagnostic and acceptance tests are worth retaining

Sources: [selective diagnostics](../tests/testthat/test-reference-draw-diagnostics.R),
[sampler contract](../tests/testthat/test-generic-sampler-contract.R), and
[acceptance checks](../tests/testthat/test-lag1-autocorrelation.R).

These tests check meaningful behavior: exact pass/fail boundaries, named
variable and chain failures, constant or unavailable metrics, malformed
sampler dimensions, divergence rejection, metadata counts matching actual
draws, and independent diagnostic gates.

The throwing mocks added in `e268a35` are particularly useful: they establish
that lag-only requests do not calculate unrelated metrics, rather than merely
checking which fields appear in the result. There is no reason to delete
these tests as over-engineering.

### 7. One database-dependent ESS test remains — low priority

Source: [ESS tests](../tests/testthat/test-lag1-autocorrelation.R).

The older test requires a configured database and a particular posterior;
it skipped in this review. A synthetic test already verifies the essential
policy that poor ESS is recorded without rejecting otherwise valid draws.

Follow-up: keep the database case only if it has a distinct integration
purpose, and label it accordingly. Otherwise consolidate the policy coverage
into the existing synthetic test. Also avoid compiling a real RStan model
solely to test options that must be rejected before extraction; a minimal
mock can assert that extraction was never reached.

## Recommended order

1. Tighten the existing mock arguments and compare all persisted draw values.
2. Add one genuine CmdStanR fixture test and one constrained-count regression.
3. Strengthen failed-creation cleanup assertions; add failure-stage coverage
   when changing the writer.
4. Keep optional database integration tests separate from self-contained
   policy tests.

Passing tests support the exercised behavior. They do not establish complete
backend compatibility, installed-package dispatch, or every transactional
failure path. No implementation defect was reproduced by the focused runs;
the findings above concern coverage and assertion strength.
