# Conversation handoff — 2026-10-01

## What we completed

We reviewed import policy, recovery, S3 design, Stan workflows, tests, and
persistence with Ponytail/review/audit, including `a52d05c2`, `43b35058`,
`16cdd444`, and `d960a017`. The final review covered **all 74 commits in
`8aeef19..55e667e`**, crediting later repairs. Findings were documented;
no implementation or test files were changed.

Reviewed snapshot: `55e667e2b11267a5ab9db76e5a15c15ea82c6376` on local `main`.
The docs branch `Agent-ToDo` started from older `upstream/main` at `8aeef19`
and lacked those implementations. The user reports pushing the documents
to GitHub. Inspect the actual newer checkout/refs; do not assume this old
branch layout persists.

## Read these documents

| Document | Purpose |
| --- | --- |
| [AGENT_REVIEW_GUIDE.md](AGENT_REVIEW_GUIDE.md) | Main backlog: S3, diagnostics, persistence, validation, and tests; issue IDs S/D/P/V/T and proposed checks. |
| [ponytail-commit-review.md](ponytail-commit-review.md) | Complete chronological ledger, later fixes, and outstanding concerns. |
| [ponytail-audit.md](ponytail-audit.md) | Simplification, NULL policy decision, S3 consistency, importer recovery, and workflow follow-ups. |
| [ponytail-review-findings.md](ponytail-review-findings.md) | Priorities and minimal implementation recommendations. |
| [ponytail-test-suite-review.md](ponytail-test-suite-review.md) | Test history, historical execution evidence, and coverage limitations. |
| [implementation-guide-stan-workflow-gaps.md](implementation-guide-stan-workflow-gaps.md) | Separate optional proposals: CmdStanR bundles, provenance, archived RStan count recovery. |
| [agentic-implementation-orchestration.md](agentic-implementation-orchestration.md) | Implementation protocol, work units, worker/reviewer templates, and kickoff prompt. |
| [agentic_orchestration_alt.md](agentic_orchestration_alt.md) | Alternative **Plus-only OR Claude Code-only** assignments and kickoff prompts; neither requires both providers. |

## Important conclusions to carry forward

- Preserve existing issue IDs; most concerns are already actionable in the
  handoff. Do not duplicate the backlog or obsolete criticisms.
- **P11, reproduced:** supplying reused data from database A with destination
  B replaces its source connection; preflight can accept unrelated same-name
  data in B and write accepted draws against that different stored data.
- **P12, reproduced:** an accepted bundle can assign a reused posterior's
  missing reference link only in memory. The writer skips its existing JSON,
  then rejects the draws because no persisted posterior points to them.
  No reference archive was created in the reproduction. Distinguish this
  from P2's failed-candidate dangling-link defect.
- NULL selects the ordinary fixed import policy, very likely to stay
  unchanged. Decide compatibility/redundant forwarding without inventing
  configurable acceptance.
- Fix S3 consistency; do not turn every helper into a generic.
- Coverage gaps extend beyond CmdStanR: public dispatch, constrained counts,
  persisted values, rollback, and database isolation also need attention.

Historical focused tests passed within documented scopes, not a full-suite
proof. P11/P12 probes used disposable databases and mocked extraction;
they did not verify real backend extraction.

## Continue on the newer repository

1. Read local instructions, establish the implementation SHA, and revalidate
   findings against newer code. Credit already-fixed issues with evidence.
2. Follow the chosen orchestration guide and authorized scope. Prioritize safe
   fixtures/P11, then P2/P12 if present; optional proposals need explicit scope.
3. Make small shared-cause fixes with public regressions, persisted-state
   checks, and final-patch review. Preserve acceptance, unconstrained counts,
   honest provenance, and compatibility.
4. Never run mutating tests against the user's working database. Rerun checks
   for new code; required unrun verification stays pending.

The user prefers minimal solutions and asks that **Markdown changes be
committed**. Three GPT-6-Luna/medium read-only subagents helped the review;
none wrote the orchestration guides. Future setups use Sol with separate
review, or Claude Opus/Fable; choose one provider profile and verify access.

Prior documentation commits: `a0b10aa` (initial documents), `d484878`
(commit review/P11/P12), `32e9ccc` (orchestration), and `0876fcf`
(separate Plus/Claude profiles). This handoff summarizes the conversation;
it does not declare the backlog implemented or authorize publishing changes.

## Implementation checkpoint — 2026-10-02

Authorized scope: address outstanding confirmed implementation defects using
the Plus-only orchestration profile. One writer; Luna/medium for bounded
read-only inventories, Sol 6.1/high for independent frozen-patch review.
Check assigned files before editing, preserve existing changes in a pre-edit
commit when necessary, and commit each coherent tested unit. Optional new
backend/provenance features remain outside this defect-fixing scope.

Implementation branch: `main`, starting at `b9515c1`. The existing handoff
was preserved before editing in `cd01b5c`. Other dirty/untracked files remain
outside ownership. Available: R 4.6.0, RStan 2.32.7, CmdStanR 0.9.0,
CmdStan 2.40.0, posterior 1.7.0, testthat 3.3.2, roxygen2 8.1.0.

| Findings | Current status and evidence |
| --- | --- |
| S1 | Verified at `688c7d8`: common positional arguments aligned; focused installed tests and S3 signature checker passed. |
| P2, P11, P12 | Verified at `56cb0dd`: persisted candidate links guarded, reused origins retained, accepted reused posterior requires a matching stored link. Empty-link updates use the existing importer. Forty isolated integrity assertions passed, including namespace-only installed loading. |
| V1 | Verified at `b9515c1`: bibliography result captured; eight status assertions and 48 bibliography assertions passed in an installed package. |
| P4 | Partial at `ebb5d9e`: rename/bibliography restoration results checked and failed-recovery backups retained. Rename 58 and bibliography 48 assertions passed. Broader component/bundle write atomicity remains open. |
| P9 | Verified: names/write containment at `587bb86`/`8e5de0c`; common archive/cache boundaries at `fe74ebc`. One safe root JSON member, requested filename matching, cache containment, and partial extraction cleanup shared with rename/link. Initial archive regression had ten failures; damaged-ZIP review regression added three failures. Final 33 archive assertions pass, including a Windows-safe crafted drive-name ZIP. Installed archive33, rename58, resource170 and integrity40 passed; independent Sol review verified corruption repair and portability block. Windows runtime/live GitHub unrun. |
| P3 | Deferred by maintainer on 2026-10-02. Preserve existing manual cache refresh; retain the issue in the active guide for later decision. |
| S3 | Verified at `a5ef7c9`: shared coercion retains and validates an explicit connection; thinning forwards it, standalone NULL remains supported, JSON excludes connection attributes. Regression failed with eight assertions before repair and passed all 16 afterward. Installed reference-connections, import-external-stanfit (50 assertions, real RStan), and bundle-write-integrity (40 assertions) passed. Independent Sol 6.1/high review found no defects and reran the 16-assertion regression against repository sources. |
| S2 | Partial at `5f93031`: external thinning registration verified without attaching the package. Direct-method calls and subclass contracts remain open. |
| S4, S5 | Open; revalidate against current source. |
| D1–D7 | Open; fixed NULL-policy compatibility/internal forwarding cleanup already implemented at `56cb0dd`. Preserve numerical conventions and honest historical evidence. |
| P1 | Verified at `5f93031`: transformations clear obsolete evidence, retain correct counts/connections, align variable diagnostics and raw sampler inputs; actual-count guards reject forged flags. Initial regression had 14 failures; final 28 assertions pass. Independent Sol review found and then verified repairs for reordered unnamed metrics and adaptive thinning; only fixed positive integer periods are supported. Namespace-only installed transformation and path tests passed (28 and 170 assertions); connections, generic acceptance, deferred checks, integrity, real-RStan imports, diagnostics and lag checks also passed, with one configured-corpus ESS test skipped. `tools::checkS3methods(dir = ".")` passed. Guide/help regenerated. |
| P5–P8, P10 | Open; revalidate against current source. |
| V2–V6 | Open; revalidate and separate demonstrated bugs from policy choices. |
| T1 | Partial at `31ca4e9`: package harness copies the selected configured corpus or clones into a fresh disposable tree; both path settings are scoped and restored, and failures clean staged files. Initial isolation regression failed before repair; final 37 assertions passed development, installed namespace-only, and independent Sol review. Review repaired Windows/root overlap guards and optional git2r test behavior. Windows runtime/real clone/broad suite unrun. Direct test/coverage runs bypassing the entry point, config-file isolation, offline fixtures and integration separation remain open. |
| T2–T3 | Partial: new isolated fixtures, installed checks, affected help/guides, and unused dependency/helper removal added. Complementary backend coverage and broader public documentation remain open. |

The package harness now isolates configured database paths, but direct
test/coverage runs can bypass it and working-directory configuration can
override paths. Focused tests must use inspected disposable fixtures.
Existing passing runs are evidence for their listed commits only; new
changes require new checks.

No writer/reviewer owns an unfinished patch. Completed issues are removed
from the active guide; this checkpoint and Git retain their evidence.
Next: P7 summary-reference listing; Luna inventory confirms local summary
directory selection and GitHub type forwarding defects. P4 broader I/O
rollback policy is awaiting maintainer clarification; no dependent edits.
P3 stays deferred. Remaining work stays in the active guide.
