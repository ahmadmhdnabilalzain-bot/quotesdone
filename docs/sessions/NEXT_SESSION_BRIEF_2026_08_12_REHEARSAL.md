# NEXT SESSION — TIERS 0, 1, 2 AND THE FULL DRESS REHEARSAL

Supersedes `NEXT_SESSION_BRIEF_WORD_BY_WORD_AUDIT.md`, which is complete and merged
(`docs/audits/WORD_BY_WORD_2026_08_11/`, PR #190). Conduct rules are in the `quotesdone-session`
skill and apply automatically.

**Minimum for this session: Tier 0, Tier 1 and Tier 2 finished.** The rehearsal is the headline and
depends on Tier 1.

---

## THE CORRECTION THAT CREATED THIS BRIEF

The audit repeatedly recorded "built and never exercised" and filed the demand side as
**"No code change fixes this."** The founder's correction, and it is right:

> "How can I launch if you didn't test these? … Create a set of demo list that covers all the stuff
> that you would need, and let us play a scenario that is real. Once that is done, you can test
> everything. … So what you're saying cannot be taken as an excuse to not fix what's already there."

**An unexercised path is a testing gap, not a blocker.** Seed it, run it end to end, prove it, tear
it down. 96 of 418 tables are empty; the rehearsal is how they get exercised before a real customer
ever arrives.

**Do not raise the OpenRouter balance again.** He tops it up in a minute, it does not gate the work,
and if it hits zero the system stops on its own. It is not a finding and not a blocker.

---

## THE ONE THING THAT CAN GO BADLY WRONG

```
leads with a real, unbanned email address:  19,903
notification channels wired:                email
executors that notify a human:              10 of 56
existing demo / test / seed marker columns:  NONE
```

**A rehearsal that triggers supplier matching and invitation can email ~20,000 real companies.**
`enqueue_supplier_invites`, `fn_notify_supplier`, `fn_notify_matched_supplier` and
`run_no_quote_nudges` all exist and all work. This is the single largest risk in the plan.

**Build the containment before the first seed row, not after.** Order is not negotiable:

1. outbound kill switch, verified by execution
2. demo registry
3. seed
4. rehearse
5. tear down and prove zero remain

---

## TIER 0 — cost (independent, do first, ~half a day)

| # | task | detail |
|---|---|---|
| 0.1 | **Turn `llm_cache` on** | fully built — `cache_key`, `prompt_hash`, `hits`, `expires_at`, `saved_usd`, `embedding_gte` — with `fn_llm_cache_get/put/lookup/store` and a `cache_ttl_min` on all 61 `model_policy` rows. Holds **1 row, 2 hits, $0.00**. This is a wiring bug: find the call site that should write and does not. Verify by execution — two identical calls, second must hit |
| 0.2 | **Stop provider-side prompt caching where it loses money** | read/write **0.115** over 7 days against a **0.278** break-even. Read it from `prompt_tokens_details`, not the top-level names |
| 0.3 | **Point `could_be_cheaper` at the spender** | flagged 179 calls: **175 on `gemini-3.1-flash-lite`** (1.1% of spend), **0 on `claude-sonnet-5`** (84% of spend) |
| 0.4 | **Cut `agent_reasoning` input** | 11,499 average input tokens × 622 calls. `fn_agent_context_capped` exists and is not on this path |

**Do not build model cascading.** Confidence is reported on **5 of 1,642 calls** and **0 of 622
sonnet-5 calls**; a confidence-gated cascade with no confidence escalates every time and pays twice.
The prerequisite is the output contract carrying a confidence — `agent_brain` returns prose plus an
`@@ACTIONS@@` tail and `selfReportedConfidence()` only parses whole-JSON bodies.

---

## TIER 1 — the instruments (**blocks the rehearsal — do before seeding**)

The rehearsal will produce numbers. If the instruments still report the wrong subject, the rehearsal
proves nothing and manufactures exactly the false confidence the audit was commissioned to end.

| # | task | detail |
|---|---|---|
| 1.1 | **`fn_goal_attainment` must not score unmeasured goals** | 55 of 63 active `company_goals` have no `measure_sql`. `least(100, NULL)` returns 100. Report "8 of 63 measurable" and exclude the rest from the denominator — do not invent measures |
| 1.2 | **`fn_scenario_run` status must say `STAFFED`, not `READY`** | the verdict *text* already admits it never injects the failure; the *status* does not, and 19/19 reads as disaster-recovery coverage |
| 1.3 | **`project_parity.mjs`: add a row-count dimension** | 418 = 418 tables hid **255 empty tables on staging against production's 96**, `board_advisor` **0 vs 7**, `workflow_run` **7 vs 198** |
| 1.4 | **One helper: no number derived from an empty source** | a value from an empty table, an unmeasured goal or an unexercised mechanism renders **"no data yet"** — never `0`, `100%`, `READY` or `IN SYNC`. Apply to Executive Home first: it currently shows a high Company Health beside AED 0 revenue and 0 customers |

---

## TIER 2 — the identity defect (instance 5)

| # | task | detail |
|---|---|---|
| 2.1 | **Resolve the 96 `target_employee` keys at the write boundary** | `org_agent_alias` + `fn_org_agent_resolve` in a **BEFORE INSERT trigger** — never by widening the reader's join. **48 of 96 already match a slugified `org_departments.name`** and fail only on `&` vs `and`; the other 48 need five rename mappings: `ai-and-model-operations`→AI Department, `it-sre-and-cybersecurity`→IT & Cybersecurity, `marketplace-operations`→Marketplace & Procurement, `payments-and-revenue-operations`→Payment, `strategy-performance-and-evolution`→Evolution. Present identically on both projects |
| 2.2 | **Retire or map the 44 legacy `cat:` keys** | of 132 `cat:` keys in `agent_knowledge`, **88 carry all 14 standard modules and 44 carry none** — the distribution is binary. The 44 are knowledge filed under the vocabulary `knowledge_module_standard` replaced. `cat:aluminium-glass` and `cat:aluminium-and-glass-suppliers` are the same agent twice |
| 2.3 | **Fix `dept_key='knowledge'` naming "Administration & Operations"** | a rename or an alias — decide and record which. `scenario_library.regulatory_change` names `knowledge` and reaches Admin & Ops |

---

## THE DRESS REHEARSAL — A to Z, then deleted

### Step 0 — the convention already exists. Extend it; do not invent one.

**A demo fixture set has existed since 7–8 Aug 2026 and this brief originally missed it.** The
convention lives in the data, not the schema:

```
company_name:  ZZ DEMO — Al Noor HVAC Manufacturing (QuotesDone fixture, not a real company)
email:         demo-supplier@example.invalid  /  qd-demo-supplier-00N@example.invalid
```

**Marker scan, 11 Aug 2026.** Covered every `text`/`varchar`/`char` column of every base table in
`public`, matching `ZZ DEMO|example\.invalid|qd-demo`. Found:

| table.column | rows |
|---|---|
| `leads.company_name` / `.email` / `.place_id` | 6 each |
| `leads.website` / `.claimed_by` | 1 each |
| `dropbox_files.path` | 12 |
| `dropbox_files.name` | 6 |
| `doc_backups.dropbox_path` | 6 |
| `notifications.body` | 8 |
| `supplier_catalog.source_hash` | 1 |

**Boundary of that scan, stated:** it finds only rows carrying one of those three markers in a text
column. Demo rows created under a different convention, or marked only in a numeric/jsonb column,
would not appear. It is evidence about the `ZZ DEMO`/`example.invalid` convention, not proof that
nothing else in the database is synthetic.

**Two things follow.**

1. **The six "claimed" suppliers are all demo fixtures.** Every prior statement that production has
   "6 claimed suppliers of 20,470" is wrong in substance — **real claimed suppliers is 0.** Correct
   this in `docs/audits/WORD_BY_WORD_2026_08_11/` rather than leaving it to be re-derived.
2. **The existing fixture reaches supplier registration and stops there.** It has documents and
   notifications; it has no customer, no inquiry, no quote, no transaction. The A→Z gap is
   everything downstream of onboarding.

**So: extend the existing convention. Do not build a `demo_run`/`demo_row` registry** — `ZZ DEMO —`
plus `@example.invalid` is already greppable, already deletable, and already in use.

### Step 1 — outbound containment, built and proven before any new seed row

- Every demo contact keeps the existing form: `ZZ DEMO — …` in the name, `@example.invalid` in the
  email (RFC 2606, guaranteed undeliverable), and a phone number that cannot route.
- **A hard block while any `ZZ DEMO` entity is live:** any `notifications` insert arising from a demo
  entity whose recipient is not `.invalid` is **held**, not sent. `notifications` already has a
  held/dead-letter path (`fn_notifications_dead_letter_held`, `fn_notifications_release_held`) —
  reuse it, do not invent one.
- Check `org_action_executor.notifies_human` (**10 of 56**) before anything sweeps.
- **Prove it by execution before seeding**: in an aborted transaction, create a demo inquiry, match
  it against real leads, assert every resulting notification to a non-`.invalid` address is held,
  then `raise exception` with the counts so nothing persists.

### Step 2 — teardown must be exact and provable

Teardown is a single greppable predicate across the tables the scan names, plus whatever the
rehearsal adds. After teardown, **re-run the marker scan above and assert every count is 0** —
except any pre-existing fixture the founder wants kept, which must be named explicitly rather than
left ambiguous.

### Step 3 — the seed, sized to exercise the chain and nothing more

Use **one category — HVAC**, because the six existing `ZZ DEMO` fixtures are already HVAC companies
(`Al Noor HVAC Manufacturing`, `Gulf Climate Systems`, `Emirates Air Engineering`,
`Northern Cooling Contracting`, `Al Barsha HVAC Trading`, `Capital Mechanical Works`). Extending
what is there beats seeding a second category. Spec #7's own observability trace is an HVAC RFQ
(L1476, "HVAC Agent qualified inquiry"), so this is also the trace the contract asks for.

| entity | count | why |
|---|---|---|
| customer organisation + customers | 2 | one straightforward, one that changes requirements later |
| project | 1 | exercises `projects`, `project_component` |
| **synthetic** supplier leads (claimed + approved) | 12 — **6 already exist, add 6** | matches the spec's "12 suppliers" trace. The 6 existing `ZZ DEMO` HVAC fixtures are `approval_status='pending'`; approving them is part of the rehearsal. **Never approve one of the 19,903 real leads** |
| inquiry (RFQ) with a BOQ attachment | 2 | one clean, one missing information |
| quotes | 7 | matches the trace's "7 quotations received" |
| quote_items | ~30 | `fn_quote_structured_score`, `trg_quote_items_rescore` |
| transaction / reveal | 1 | the only revenue path there is |
| refund | 1 | `fn_refund_request/decide/settle` and the `refunds` state machine |
| complaint + supplier suspension | 1 each | two of the 11 named workflows with no `workflow` row |
| review / rating | 3 | `recompute_supplier_rating`, `fn_reputation_recompute` |

### Step 4 — run the real scenario, end to end

Drive spec #7's observability trace (L1467–L1498) and assert **each step**, not the end state:

```
RFQ created → BOQ analysed → qualified → 12 suppliers matched → invitations →
7 quotes received → ranked → award recommendation
```

Then the second inquiry: **customer changes requirements after quotations are received** — spec #7
L1351, one of the 13 exception scenarios with no coverage at all.

Assert on a **non-zero effect** at every step, not an HTTP 200. `quote_compare` returned
`{ok:false}` at HTTP 200 for weeks.

Expected to move: `rfq_handling` **0 runs**, `supplier_onboarding` **0 runs**, and roughly 40 of the
96 empty tables. **Record which tables the rehearsal could NOT reach** — that list is the real output
of this exercise, more than the pass itself.

### Step 5 — teardown, and prove the score did not move

1. Run every scorer **before** seeding and record the numbers.
2. Seed, rehearse, tear down.
3. Run every scorer **again**. **They must match the before figures exactly.**

A moved score means either teardown was incomplete or a gate counted demo data — and a gate that
counts demo data is precisely the defect this audit exists to end. **Do not exclude demo rows by
editing 152 checks; prove it with the before/after equality instead.**

Leave behind: the seed script, the teardown script, the before/after scores, and the list of tables
the rehearsal could not reach.

---

## STATE AS OF 2026-08-11 16:30 UTC — do not re-derive

| | |
|---|---|
| audit | 888 claims — 423 PRESENT, 279 PARTIAL, 171 ABSENT, 15 CONTRADICTED |
| org | 25 departments, 94 agents (93 active), `manager_key` 100% resolving |
| suppliers | 20,470 leads · **0 real claimed** (the 6 claimed are `ZZ DEMO` fixtures) · 0 approved · 19,903 with a real email |
| demand | `customers` 0 · `inquiries` 0 · `quotes` 0 · `transactions` 0 |
| empty tables | **96 of 418** production · **255 of 418** staging |
| knowledge | `kb_chunks` 120,530 · **39% embedded** · 28,521 byte-identical duplicates |
| retrieval | 5 of 6 routines are full-text; `kb_match` is the only vector path and agents never call it |
| duplicates | 36 SQL functions redundantly defined (58 copies) · `sec()` in 134 of 198 edge functions |
| dead code | exactly **1** of 698 routines (`fn_simulate_growth`) |
| Actions / parity / advisors | green · IN SYNC · 0 ERROR |

---

## TRAPS

- **The 19,903 real emails.** Containment first, always.
- **Never approve a real lead** to make the rehearsal work. Synthetic suppliers only.
- Demo data must never turn a gate green. Before/after score equality is the proof.
- `least(100.0, NULL)` returns 100.0.
- BEFORE triggers fire in **name** order — `a00_` first, `zzz_` last.
- `revoke … from anon` is a silent no-op when the grant is held through PUBLIC.
- Every SECURITY DEFINER function you **CREATE** is granted EXECUTE to PUBLIC — revoke in the same
  migration. `CREATE OR REPLACE` preserves the ACL; do not revoke there.
- `idempotency_key` is UNIQUE — a not-exists guard excluding only live statuses collides on a
  previously FAILED row.
- Read the dates: `select now() at time zone 'utc';` first. Dubai is UTC+4.
