# Reviewer independence — six scopes, and the alias that walked past two guards

Written 15 August 2026. Every number here was measured on production before the change.

## The defect: one employee, two names, and a guard that could not see it

The Visual Design Director's `role_id` is `visual_design`. Its runtime `agent_key` is
`marketing_design`. They are the same employee.

```sql
select ('visual_design' = 'marketing_design')                                              as raw_guard_fires,
       (fn_org_agent_resolve('visual_design') = fn_org_agent_resolve('marketing_design'))  as same_employee;
-- raw_guard_fires = false      same_employee = true
```

Three places decide whether a reviewer is independent. On 14 August only one of them was taught to
resolve identities:

| Where | Before | After |
|---|---|---|
| `review_chain` — `trg_review_chain_no_self_review` | **resolves both sides and canonicalises on write** | unchanged — EXISTING_BETTER_KEEP |
| `artifact_review` — `fn_artifact_review_valid()` | `new.reviewer_agent = new.author_agent`, raw | resolves both sides |
| `artifact_review` edge function | `authorAgent === reviewerAgent`, raw, **and the reviewer defaulted to `marketing_design`** | resolves both sides; default is now the artifact-QA path |

So the default reviewer of every rendered artifact was the agent that draws the artifact, and the
guard built to stop exactly that answered "independent", because `visual_design` and
`marketing_design` are different strings.

This is the fourth instance of one root cause on this codebase: a routine comparing an identity it
never resolved. `fn_pick_reviewer` had it (182 self-approvals across all ten departments),
`fn_agent_tools` had it, the autonomy gate had it.

### Evidence that review_chain's version works

`trg_review_chain_no_self_review` resolves both sides and stores them canonical. Over 1,885 rows:

| | |
|---|---|
| author = reviewer, raw string | 285 |
| author = reviewer, after canonical resolution | 285 |
| **hidden by an alias** | **0** |

The counts agree because the trigger normalises on write. That is the shape the artifact path now
has too.

### Evidence that the artifact guard now fires

`artifact_review` holds **0 rows** on both projects, so a count could never distinguish a working
guard from a dead one. `scripts/checks/artifact_review_alias_cannot_self_approve.test.mjs` forces
it, inside an aborted transaction — 16/16 on both projects:

| Case | Result |
|---|---|
| author `visual_design`, reviewer `marketing_design` | **refused** — "same employee" |
| author `Visual Design Director` (the job title), reviewer `marketing_design` | **refused** |
| author `marketing_design`, reviewer `marketing_design` (the old guard's only case) | refused |
| verdict `pass` with **no reviewer at all** | **refused** — the old guard permitted this |
| author `visual_design`, reviewer `ai_quality_reviewer` | **accepted**, stored as `marketing_design` / `ai_qa_specialist` |

The last row matters as much as the refusals: a guard that refuses everything is not a guard.

## No creator is the sole final reviewer

| Creator | What it may no longer do | How |
|---|---|---|
| Visual Design Specialist | approve the rendered artifact it produced | `artifact.review` removed from its tools; authority dropped to `advisory`; forbidden_decisions names it; the resolving guard catches it under any alias |
| Test Automation Engineer | veto a release on its own evidence | reclassified to `event_driven_operator` with `execute_low`; "blocking a release" returned to the QA & Release Management Director |
| Marketplace Content & Privacy Reviewer | approve a brief or redaction it authored | forbidden_decisions names it; structurally it sits in `legal` and the payload is authored in `marketplace` |
| Billing & Reconciliation Specialist | reconcile a charge it took | `payment` steps 2–4 moved to the Payments & Billing Manager |

## Why the content and privacy reviewer sits in `legal`, not `assurance`

The instruction leaves the placement to whichever preserves true independence **in the current
code**, so it was decided on how the code actually picks reviewers.

`fn_pick_reviewer(p_dept_key, p_author)` returns the **head of the department it is given**. The
supplier-safe payload is authored inside `marketplace` — RFQ Qualification Manager, Inquiry Router,
Document Intelligence Manager. Placing the reviewer there would make the Marketplace Director, who
owns dispatch policy and whose operator consumes this approval, the fallback reviewer of the
privacy decision. Both `legal` and `assurance` avoid that. `legal` wins on two further points:

1. Every `assurance` role reports to `quality_and_release_director`, who holds release go/no-go.
   Routing per-artefact privacy approval through the release gate couples two decisions the
   instruction deliberately separates.
2. `legal` already holds the Compliance & Privacy Officer and the `pdpl_action` executor, and the
   Trust & Safety Manager — which the instruction says keeps general moderation policy, disputes
   and enforcement — is this role's manager today. The split the instruction asks for already
   exists there.

Independence is therefore structural, not procedural: the authors are in `marketplace`, the
reviewer is in `legal`, and no `fn_pick_reviewer` path can return one for the other.

## The six scopes, and what each is forbidden

| Reviewer | Owns | Explicitly not |
|---|---|---|
| **Model Evaluation Reviewer** | offline evaluation of a model, prompt, retrieval or routing change against a held-out set | live workflow behaviour; release go/no-go; authoring the change it evaluates |
| **AI Quality Assurance Reviewer** | agent behaviour inside complete workflows; the artifact-QA verdict on a rendered asset | offline evaluation; release go/no-go; brand/message approval; privacy approval; reviewing an artifact it produced |
| **QA & Release Management Director** | final system and release go/no-go | writing the tests it rules on; offline evaluation; per-artifact privacy approval; approving a release for a change it authored |
| **Knowledge Validator** | validity, source quality, contradiction and freshness of a knowledge record | agent behaviour; legal/policy compliance; authoring the record it validates; release go/no-go |
| **Compliance & Privacy Officer** | whether an action is legally and policy-compliant; data protection and retention | per-artifact supplier-safe approval; knowledge record validity; release go/no-go |
| **Marketplace Content & Privacy Reviewer** | the actual supplier-facing payload, files and redacted drawings | authoring what it approves; general moderation policy; dispatching; overriding a regulatory gate |

Checked as a matrix, not by reading the prose: `release go/no-go` is owned by **exactly one** of the
six, and every reviewer's forbidden list names another reviewer's territory.

## Founder-reserved decisions

`founder_reserved_decision` holds eleven entries — reveal-fee percentage, supplier subscription
price, subscription start date, founding-supplier exemption, ownership and equity, fundraising,
market/country expansion, material policy change, spending above budget, unapproved legal
commitment, permanent changes to founder-defined commercial rules.

`trg_org_role_no_reserved_decision` refuses any role that tries to **own** one. Forced to fire:

```
update org_role set owned_decisions = array['set the reveal fee percentage'] where role_id = 'ceo';
-- ERROR: role "ceo" cannot OWN a founder-reserved decision: The reveal-fee percentage charged to
--        a customer. (matched "reveal fee" in owned_decisions)
```

Even the AI CEO cannot hold it.

The settings channel was already correct and is left alone — **EXISTING_BETTER_KEEP**, verified
rather than asserted. `fn_founder_apply_setting` accepts only the sixteen keys
`fn_founder_settings()` returns, and all sixteen are operational caps and switches
(`invite_daily_cap`, `match_max_fanout`, `wa_daily_cap`, …). Not one reserved commercial item is
reachable from it, and its refusal text says so out loud. A test cross-joins the allowlist against
every reserved match string and asserts zero hits.
