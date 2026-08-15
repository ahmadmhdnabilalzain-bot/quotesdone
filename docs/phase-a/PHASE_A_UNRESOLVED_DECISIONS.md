# Phase A — unresolved, and who each one belongs to

15 August 2026. Everything Phase A could decide, it decided. This is what it could not, split by
whose call it actually is. Nothing here blocks the Phase A gate; all 48 deterministic invariants
pass. These are the things that would be dishonest to leave unsaid.

---

## 0. How to read a zero, after the closure corrections

There are now **two** instruments, because there are two subjects:

| function | asks | result |
|---|---|---|
| `fn_phase_a_organization_violations()` | is the ORGANISATION correct? | **0 rows** |
| `fn_phase_a_deferred_items()` | what is this phase forbidden to close? | **4 rows**, all `DEFERRED_TO_LATER_PHASES` |
| `fn_org_role_violations()` | can every employee WORK? | **4 rows**, unchanged and untouched |

`fn_org_role_violations` was **not weakened, redefined or scoped down** to produce the zero. It keeps
asking whether an employee can work and keeps answering "not yet" for the Product/UX Designer. The
new function is narrower on purpose and does not test tools, imported knowledge, live KPI bindings,
model policies, decision traces or provider connections.

## 1. `product_ux_designer` is defined but not activated — Phase B, not the founder

`fn_org_role_violations()` returned **0 before Phase A and returns 4 after**, all four against this
one role:

| rule | detail |
|---|---|
| `no_kpi` | `employee_kpi` has no active row |
| `no_knowledge` | `knowledge_scopes` is empty and `employee_knowledge` has no row |
| `no_authority` | advisory with no `employee_authority` row |
| `no_tools` | `tools` is empty |

**This is the trade-off Phase A was given, not an oversight.** The package ordered the role created
(`CURRENT_TO_FINAL_ROLE_CHANGES.csv` → `Create | Product/UX Designer`) and in the same document
forbade the four things that would clear these rules: *"Do not work on knowledge content, tools,
models, prompts, decision traces, runtime quality."*

Three reasons the count was not taken back to zero:

1. `fn_org_role_violations()` is a **runtime-readiness** check, not an organizational-design one. It
   asks "can this employee work?". For a role Phase A creates and Phase B activates, "not yet" is
   the true answer and a check that says so is working.
2. Granting them would be a Phase B change wearing a Phase A commit message.
3. **There is no honest tool to grant.** The tools held by comparable advisory specialists are
   `qualify_inquiry`, `route_category`, `supplier_verify`, `supplier_approve_clean`, `match_inquiry`
   and `capability_enrich`. Giving a UX designer the ability to approve a supplier, to satisfy a
   count, is a worse outcome than a red check — it is the exact shape of the silent over-grant this
   estate has been bitten by before.

The role is **runtime-deferred**, and that is now a declared fact rather than an inference:
`org_role.runtime_enabled` is **false** for it, and the column comment states that FALSE means
"deliberately not yet runtime-activated" and never "optional or retained to make a count". It owns
step 2 of W22 — experience design and UX acceptance criteria — so it is accountable for something
real, and `model_policy` is null so it could not make a paid call even if something invoked it.

**What closes it:** Phase B gives it a KPI, a knowledge scope, an authority row and whatever tool it
genuinely needs. Not before.

## 2. UAE tax coordination — recorded, and worth the founder knowing

`tax_overlay_uae` was created on 15 Aug at 01:21, outside this package, as a knowledge overlay. It
is now **retired**, and `tax_overlay_uae` resolves to `financial_controller`.

That is not a judgement call I made in a vacuum — the package makes it explicitly:
`CURRENT_TO_FINAL_ROLE_CHANGES.csv` → *"Expand scope | Financial Controller | UAE VAT/corporate-tax
coordination"*. The responsibility moved to an accountable role; it was not dropped.

**What is genuinely open:** whether "expanded scope" is enough for UAE VAT and corporate tax, or
whether that eventually needs a person or an external firm. That is a commercial and compliance
question, and it is the founder's. Nothing technical is waiting on it.

## 3. Eleven organizational workflows have no runtime steps behind them

`org_workflow_ownership` now records **30** workflows with exactly one accountable owner each.
`workflow_step` — the runtime table, which says who acts at step 4 — models **19**. The two are
different subjects and the gap is not an error, but it does mean eleven workflows are owned on
paper and have no executable sequence.

The eleven are the strategic and governance ones (founder mandate → objectives, target-miss
correction, partnership development, agent performance and organization design, and similar), which
is why they have no runtime steps: nothing dispatches them. **Phase C territory**, and named here so
that "30 workflows are owned" is not read as "30 workflows run".

## 4. What Phase A did NOT touch, listed so it cannot be assumed

No knowledge content or embeddings. No prompts. No model policy or routing. No tool connections. No
routes, cron jobs, dispatch, billing, refunds or autonomy. No Edge Function changes. No pricing or
commercial policy. No synthetic customers, suppliers, inquiries or payments. No notifications of any
kind. **Zero OpenRouter requests and USD 0.00 of paid inference** — every provider route remains
open-circuit in `llm_route_health`, and Phase A did not release one.

## 5. One check corrected during the post-deployment sweep, disclosed rather than quietly fixed

The first version of the "consequential workflows all have an owner" invariant swept
`workflow_name` for the invariant's own vocabulary — `supplier selection`, `privacy` — and reported
two unowned. **Both were owned.** Supplier selection is `W12 Supplier matching and dispatch`; the
privacy review is `W08 Supplier-safe payload and file approval`, whose owner is literally the
Marketplace Content & Privacy Reviewer. The organisation was right and the instrument was reading
for words rather than for the thing.

The check now pins each of the five concerns to a specific workflow id and requires exactly one row
with an owner, which is **stricter** than the sweep it replaced: a keyword match went green as soon
as anything matched, so it would have passed with privacy review owned by the wrong role.

**Phase A was not rolled back over it**, and that decision is stated plainly here: the rollback
trigger in the protocol is a Phase A invariant failing, and no Phase A invariant failed — a check
implementation did. Rolling back would have discarded the reviewer-independence fix, four correct
role changes and the 30-workflow registry to satisfy a bug in a script written minutes earlier.
