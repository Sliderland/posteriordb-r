# Alternate orchestration: ChatGPT Plus OR Claude Code

Prepared on 2026-10-01. Choose **one** of the two provider profiles below.
The Plus profile needs no Claude account; the Claude Code profile needs no
ChatGPT subscription. Neither assumes separately purchased API access.

Use this file together with the [original orchestration guide](agentic-implementation-orchestration.md)
and the review documents. This is an operational supplement: it replaces
the original model assignments, concurrency defaults, and kickoff prompt
for the selected profile. Its implementation contracts, issue sequencing,
test requirements, review gates, and completion criteria remain in force.
Do not run the original kickoff prompt and accidentally request unavailable
models or a second provider.

The [handoff](AGENT_REVIEW_GUIDE.md), [commit review](ponytail-commit-review.md),
[audit](ponytail-audit.md), [findings](ponytail-review-findings.md),
[test review](ponytail-test-suite-review.md), and
[optional Stan workflow proposals](implementation-guide-stan-workflow-gaps.md)
remain the task inputs. These are implementation instructions for a future
run; creating this file did not apply any package fixes.

## What changes, and what does not

| Concern | Plus-only profile | Claude Code-only profile |
| --- | --- | --- |
| Lead | GPT-6.1 Sol, with effort adjusted to the unit | Claude Opus 5.5, or explicitly selected Claude Fable 5.1 |
| Reviewer | Separate Sol context; occasional Astra if available and affordable within included usage | Separate Opus context; Fable review if available and justified |
| Bounded explorer | GPT-6 Luna | Claude Sonnet 5.5; Haiku 4.5 only for straightforward inventory |
| Default scheduling | Sequential implementation and review; at most one bounded research helper | Same default; delegate more only when tasks are independent and usage permits |
| Runtime setup | Codex/Work access through ChatGPT sign-in | Claude Code native model selection and subagent definitions |
| Usage management | Small issue units and explicit resume checkpoints | Model/effort selection and explicit worker scope; check actual billing/access |
| Required quality | Public regression, correct saved state, contract preservation, final-patch review | Identical |

These are task-specific recommendations, not measured rankings for this
R package. OpenAI and Anthropic effort labels are not interchangeable
measures of intelligence or cost. More capable orchestration does not make
source identity, rollback, S3 dispatch, or numerical checks optional.

## Profile A: only a ChatGPT Plus subscription

### Access and recommended roles

Use a Codex client with repository/test tools and **ChatGPT sign-in** for
subscription access. API-key authentication uses separate API billing;
do not add an API-funded agent framework to a subscription-only setup.
See [OpenAI authentication guidance](https://learn.chatgpt.com/docs/auth).

GPT-6.1 Sol is included in the Plus rollout for Codex/Work, subject to actual
client/account availability. These model names are not ordinary Chat model
choices in every surface. Check the actual model picker rather than inferring
access from the subscription name. See [OpenAI model availability](https://learn.chatgpt.com/docs/models).

| Role | Specific model | Recommended effort for this task |
| --- | --- | --- |
| Lead and sole writer | **GPT-6.1 Sol — `gpt-6.1-sol`** | Medium for intake/simple units; high for P11/P12, acceptance, rollback, count inference, and numerical changes. |
| Separate reviewer | **GPT-6.1 Sol — `gpt-6.1-sol`** | High for correctness review of an exact frozen patch. Use a fresh context, not the writer congratulating its own work. |
| Optional read-only mapper | **GPT-6 Luna — `gpt-6-luna`** | Medium; one bounded caller/test inventory task. |
| Optional difficult checkpoint | **GPT-6 Astra — `gpt-6-astra`** | High when offered and enough usage remains; reserve it for a specific unresolved contract or high-impact final review. |

If Sol 6.1 is unavailable but **GPT-6 Sol (`gpt-6-sol`)** is offered, use it
with the same work protocol and report the substitution. Do not move a hard
persistence/mathematical task to Luna simply to maintain throughput.

Plus is not synonymous with “no Astra”: current OpenAI pricing guidance
lists Plus usage for Astra as well as Sol/Luna. Its allowance is limited
and varies with model, context, tools, and task. Use the dashboard or CLI
`/status`; do not promise a fixed number of fixes per reset window. See
[OpenAI usage guidance](https://learn.chatgpt.com/docs/pricing).

### Change the budget and scheduling, not the checks

1. Finish one independently reviewable issue before opening another. Default
   to one writer, then one reviewer. Spawn an explorer only if its bounded
   result will avoid duplicated investigation.
2. Use Standard speed initially. Avoid defaulting to the deepest reasoning
   or automatic broad fan-out for ordinary edits. Increase effort where the
   contract is difficult; insufficient reasoning can cost more through rework.
3. Have the lead read the overview once. Give workers their exact issue
   sections, base SHA, contract, and paths; require them to read adjacent
   callers as needed. Keep outputs concise and evidence-bearing. Do not
   resend every historical diff to each child.
4. Preserve the smallest failing-before/passing-after regression, affected
   checks, and review of the final patch. Save usage by avoiding redundant
   searches and repeated unchanged tests, not by dropping required evidence.
5. Record a resume checkpoint after each unit: branch/base/candidate SHA,
   issue status, decisions, exact test outcomes, unrun checks, and next action.
   Put it in the existing implementation/handoff record rather than creating
   another complete backlog.
6. If the available allowance cannot support required verification/review,
   leave the unit `implemented, verification pending` and resume when access
   returns. Do not mark it verified, silently weaken acceptance, or buy
   credits/switch to API billing without authorization. Commit only the
   coherent state allowed by the current task, with pending work explicit.

Two Sol contexts can provide separate implementation and review roles;
different vendors are not required. A review that only repeats the author's
explanation adds little: supply the public contract and frozen diff, and
ask the reviewer to seek a counterexample through adjacent callers.

If you use a chat surface without filesystem/execution tools, the workflow
becomes assisted coding: the model drafts a patch and runnable checks, and
someone with local tools applies/runs them. Label that boundary. A Plus
subscription alone does not let a text-only conversation claim it edited
the repository or executed R tests. Prefer a supported Codex client for the
agentic implementation described here.

### Plus-only kickoff prompt

```text
Use the Plus-only profile in docs/agentic_orchestration_alt.md and the
original orchestration guide's implementation/test contracts. This task
must work within my ChatGPT Plus access: no Claude dependency and no
separately billed API framework or unapproved credit purchases.

Use available GPT-6.1 Sol as lead/writer, medium for simple intake and high
for integrity/numerical fixes. Use a separate Sol/high review context.
An optional Luna/medium explorer gets one read-only task. Reserve available
Astra for difficult checkpoints; do not assume either that Plus excludes
it or that my account necessarily offers it. Report actual models/effort.

Verify the implementation main branch; Agent-ToDo contains docs on an older
code base. Revalidate outstanding findings against current source. Start
with safe disposable test fixtures and P11, then coordinate P2/P12. Keep
one code writer and complete one unit through regression, affected checks,
frozen-patch review, and commit before expanding scope. Preserve original
acceptance, count/provenance, compatibility, and overwrite contracts.

Use the existing finding IDs and write compact resume checkpoints. Never
replace verification with a model's confidence or historical test results.
Required unrun checks remain verification pending. Keep Markdown changes
committed; do not publish/merge or add optional features unless authorized.
```

## Profile B: only Claude Code access

### Opus or Fable as the orchestrator

Both requested names are documented models: **Claude Opus 5.5
(`claude-opus-5-5`)** and **Claude Fable 5.1 (`claude-fable-5-1`)**.
Anthropic recommends Opus 5.5 for most workloads and Fable 5.1 for demanding
reasoning/long-horizon work. See its [model overview](https://platform.claude.com/docs/en/models/overview).
For this repository, I would start with Opus and use Fable when access is
already available and a concrete cross-cutting question justifies it.
If the task specifies Fable as lead, retain that choice rather than replacing
it with Opus silently.

| Role | Opus-led setup | Fable-led setup |
| --- | --- | --- |
| Coordinator | **Opus 5.5**, medium for intake; high for difficult bug/contract work | **Fable 5.1**, high for sequencing and difficult contract decisions |
| Sole writer | Lead Opus, or explicitly assigned **Opus 5.5/high** worker | **Opus 5.5/high** worker for integrity/numerical fixes; lead Fable can handle an inseparable hard unit itself |
| Separate reviewer | **Opus 5.5/high**; optional **Fable 5.1/high** on a hard unresolved question | Separate **Opus 5.5/high**; a separate Fable context when review requires deeper investigation |
| Read-only mapper | **Sonnet 5.5 — `claude-sonnet-5-5`**, medium | Same |
| Simple inventory, if useful | **Haiku 4.5 — `claude-haiku-4-5-20251001`** | Same; not responsible for numerical/recovery guarantees |

Using Fable as lead changes where difficult synthesis happens; it does not
justify handing critical implementation to a much smaller model or opening
many simultaneous writers. Delegate simple inventories to Sonnet, keep
integrity repairs with Opus/Fable, and independently review the exact result.
Do not infer that a stronger lead can certify a worker's untested claims.

Launch examples for a compatible client/provider:

```sh
claude --model claude-opus-5-5 --effort medium
```

Or, for the explicitly chosen Fable alternative:

```sh
claude --model claude-fable-5-1 --effort high
```

Check the actual model and effort in the session. Model IDs/aliases and
access can depend on provider/client settings; Fable 5.1 needs a compatible
Claude Code version and may require usage credits on your plan. Do not
assume Opus access includes Fable. Consult [Claude Code model configuration](https://code.claude.com/docs/en/model-config)
before selecting it. Do not automatically upgrade software, purchase
credits, or route through another provider as part of implementation.

Medium is Opus 5.5's normal starting point; high is sensible for these
edge-case-heavy bug fixes. The effort assignments above are my recommendation,
not a claim that `high` means the same thing as OpenAI's setting.

### Native Claude Code delegation

Use native subagents, or separate sequential Claude Code sessions. No
OpenAI bridge, API-backed orchestration library, or cross-provider reviewer
is required. The lead reads this supplement and the original guide directly;
all code work stays on the verified implementation base.

Claude Code supports full model IDs, effort, and tool allowlists in custom
subagent definitions. Pass issue-specific constraints explicitly. Check
actual running models with `/tasks`; do not trust an intended model assignment
when runtime settings substituted another. See [Claude Code subagents](https://code.claude.com/docs/en/sub-agents).

Optional definition examples are shown below; this documentation does not
install them. Add them only if a persistent role is useful for your run.

For `.claude/agents/pdb-reviewer.md`:

```yaml
---
name: pdb-reviewer
description: Review a frozen PosteriorDB fix for correctness and unnecessary complexity.
tools: Read, Grep, Glob
model: claude-opus-5-5
effort: high
---
```

Its Markdown body should say:

```text
Read the orchestration guide and selected finding. The coordinator supplies
the base/candidate SHA and frozen diff. Read adjacent callers and tests;
find concrete contract violations, regressions, or unnecessary complexity.
Report evidence, severity, assumptions, and unrun checks. Do not edit or
delegate. With these tools you cannot execute R tests: identify needed
checks and have the coordinator run them; never claim you ran them.
```

For `.claude/agents/pdb-explorer.md`:

```yaml
---
name: pdb-explorer
description: Map callers and existing test helpers for one specified PosteriorDB issue.
tools: Read, Grep, Glob
model: claude-sonnet-5-5
effort: medium
---
```

Its body should request the entry points, caller/state flow, existing helpers,
tests, and unresolved questions for one issue, with source locations and no
edits/delegation. These roles omit shell and mutation tools deliberately.
The lead owns execution, code writes, integration, and commits. A separate
test runner needs its own explicitly assigned execution scope if used.

Read applicable `CLAUDE.md` and repository instructions, but give children
the task's contracts and document sections directly. Do not depend on
automatic instruction inheritance, a locally installed Ponytail plugin,
or access to the parent's complete conversation. The portable principles
are already in the original guide: trace callers, fix the shared cause,
reuse existing code, preserve contracts, and verify observable behavior.

Keep one writer and review sequentially. If a worker uses an isolated
worktree, verify its base SHA before editing or reviewing; isolation alone
does not guarantee it started from the lead's candidate. Never review an
older default-branch copy while certifying an uncommitted newer patch.

### Claude-only kickoff prompt

```text
Use the Claude Code-only profile in docs/agentic_orchestration_alt.md and
the original orchestration guide's contracts, issue order, and verification
requirements. No ChatGPT subscription, OpenAI model, or provider bridge is
required. Keep the explicitly selected Opus 5.5 or Fable 5.1 orchestrator;
report actual access/model/effort and any substitutions.

Use Opus 5.5/high for critical implementation and separate correctness
review; Sonnet 5.5/medium may map one bounded caller/test area read-only.
With a Fable lead, delegate independent bounded work but retain difficult
contract synthesis at the lead. Do not downgrade mathematical/integrity
work merely to increase concurrency. Avoid recursive delegation.

Read the review docs and verify the authorized implementation main branch,
not Agent-ToDo's older code base. Start with safe disposable fixtures and
P11, then coordinate P2/P12. One code writer at a time; each coherent unit
gets a public failing-before/passing-after regression, affected checks,
saved-state verification, frozen-patch review, and commit. Reviewers using
only read/search tools cannot claim to execute tests; the lead must run them.

Preserve acceptance policy, unconstrained counts, honest provenance, JSON,
metadata, S3 contracts, and existing valid reuse/overwrite behavior. Recheck
historical findings against newer code. Keep status and resume checkpoints;
required unrun checks stay verification pending. Commit Markdown changes.
Do not add optional features, buy access, publish, or merge unless authorized.
```

## Common completion rule

With either profile, the change is scheduling and model routing. The quality
bar stays the same: current-source verification, the right public behavior,
actual test evidence, consistent persisted state, and review of the final
candidate. Neither a more expensive plan nor Fable/Opus orchestration proves
those facts by itself. A well-scoped Plus run can implement these fixes;
it should expect more checkpoints rather than weaker guarantees.
