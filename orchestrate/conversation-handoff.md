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
