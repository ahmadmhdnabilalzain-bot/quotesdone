# HAND-OVER — 2026-08-11, phases 1–7 · what landed, what did not

Session ran 14:57 → 17:00 UTC (Dubai 18:57 → 21:00). Branch `fix/employee-context-8s-wall`,
7 commits, PR [#195](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/195).

**Phase 8 (the 171 ABSENT) was not started.** Everything else in the prompt was attempted and the
result of each is below, including the four items where the measurement killed the plan.

---

## 1. WHAT LANDED, WITH THE MEASUREMENT

| | before | after |
|---|---|---|
| `fn_agent_context('docs')` | **7,302 ms** against an 8-second PostgREST wall | **765 ms** |
| `fn_ws_knowledge()` (the department health fn on the hot path) | 9,697 ms | **644 ms** |
| `docs` turns arriving with **no employment context at all** | 4 of the last 6 hourly runs | 0, and a failure now writes an `agent_runs` row and tells the model |
| Tier 0.4 cap live | asked 24,000 → got 35,813 | **24,012** for every live agent |
| retired category agents still answering | 44 reachable | 400 `unknown agent` |
| Layer 4 external authority reaching an employee | **0 of 118 rows** | live — `docs` cited two named UAE regulations verbatim |
| `regulation` chunks embedded | **0 / 45** | **17 / 17** (100%, after dedupe) |
| `material` | 0 / 3 | 3 / 3 |
| `trade` | 0 / 1,993 | 1,236 / 1,988 and climbing |
| `kb_chunks` byte-identical duplicates | 24,694 | **0** |
| `ops_knowledge` duplicates | 224 | **0** |
| embedding backlog | 69,225 rows | **52,612** (a 24% cut) |
| dead routines in 698 | 1 (`fn_simulate_growth`) | 0 |
| `fn_agent_context_capped(text,int,text)` executable by **anon** | **yes** | no |
| anon-executable SECURITY DEFINER | 57 | 56 |

**The dress rehearsal: 32 assertions, 32 passed, 0 failed.** Full report in
[`docs/rehearsal/REPORT_2026_08_11.md`](../rehearsal/REPORT_2026_08_11.md). Containment proved by
execution before the first seed row; **0** notifications reached a non-`.invalid` address, **0** real
leads matched; **15 of 96** empty tables reached, **81 not**, listed and grouped; teardown returned
the marker scan and the empty-table count to exactly the baseline, and all three scorers to exactly
their before values.

---

## 2. FOUR DIAGNOSES THAT DID NOT SURVIVE MEASUREMENT

Recorded because each would have cost a day.

1. **"Make `fn_kb_retrieve` hybrid first — backfilling changes nothing until then."** Inverted.
   `agent_brain.retrieve()` calls the **`kb_search` edge function**, which has always been hybrid
   (gte-small → `kb_match` → RRF with full-text). Probed: six results for a chilled-water query,
   **all six `via=semantic`**, similarity 0.891–0.922. Backfilling is the only lever. Corrected in
   `docs/audits/WORD_BY_WORD_2026_08_11/04_contradictions.md`.
2. **"Retire or map the 44 legacy `cat:` keys."** There are no orphan keys — all 132 resolve. The
   44 are `category_agents` rows with `active=false` that **`agent_brain` was still letting answer**,
   because that one lookup had no active filter while the `org_agents` branch beside it did.
3. **"`ops_knowledge` 1,197 duplicates, `os_runbooks` 21."** Re-measured on `md5(title|content)`:
   **224** and **0**. `kb_chunks` was 24,694, not 28,521. The audit used a different key; only one
   key is now stated.
4. **"`model_policy_by_identity`: alias the 96 keys."** Killed last session and confirmed this one.
   `scope='target_employee'` is selected nowhere. Not aliased — labelled, in the table's own comment.

---

## 3. TWO DECISIONS STILL YOURS

Both were left deliberately, because §3 of the working rules escalates money and destructive
production changes and both branches hit one.

1. **`model_policy_by_identity`, 96 `target_employee` rows — delete, or wire a reader?**
   Wiring a reader changes which model each of **94 employees** uses, with an immediate cost
   consequence. Deleting removes imported `v2026.07.31` pack configuration. Today they are inert and
   the table says so in its comment. **Nothing breaks while you decide.**
2. **The 8 pre-existing `ZZ DEMO` notification bodies** seeded 7–8 August with the original
   supplier-portal fixture were deleted by the rehearsal teardown, because the predicate is
   `body ~* 'ZZ DEMO|qd-demo'`. If you want that fixture's notification history kept, the predicate
   narrows to the rehearsal window in one line.

---

## 4. WHAT THE REHEARSAL EXPOSED — the Phase 5 list

Not enumerable in advance; this is what it actually turned up.

1. **`fn_edit_inquiry` accepts a post-quote requirements change and leaves the existing quotes live
   and unmarked.** Spec #7 L1351. Measured: `before=3, still-live=3`. Nothing told the suppliers,
   nothing marked the quotes stale, nothing asked for a re-quote. **The single largest build order
   the rehearsal produced.**
2. **A marker-based teardown is only half a teardown.** `supplier_dues` kept a row through the first
   teardown: written by the reveal path, carrying only foreign keys, a date and an amount, so no text
   predicate can reach it. Caught by `project_parity` reporting 95 empty tables against a baseline of
   96. An orphan sweep is the other half, and any future teardown needs both.
3. **`trg_enrich_capability` rewrote a fixture's `capability_summary` on approval** and the 7-Aug
   original text for `qd-demo-supplier-003` is gone. Real machinery, real side effect, no way to
   restore what it overwrote.
4. **81 of 96 empty tables the rehearsal could not reach**, grouped by cause in the report. The
   largest group is capabilities the RFQ chain never invokes at all — `inquiry_answer*` (6 tables),
   `inquiry_workstream*` (3), `comparison_run_v2`/`comparison_candidate_v2`, `quote_reviews`,
   `quote_requirements`, `drawing_redaction_runs`.

---

## 5. WHAT IS STILL RUNNING OR STILL OPEN

| item | state |
|---|---|
| **Embedding backfill** | 45.6% on production, 40.7% on staging. `trade` at 62% and climbing on its own hourly cron. `scripts/kb/drain_authoritative_embeddings.mjs --kinds=trade` finishes it in ~20 minutes of invocations. |
| **The arity defect** | Untouched. 9 of 11 `fn_agent_context` callsites pass no `p_query`, so 82% of callers get no LAYER 2b/2c. Measured last session, not re-measured today. |
| **Layer 4 external** | Reaches everything through `agent_brain`. The other **11 `fn_agent_context` callsites do not get it.** Widening is a separate change. |
| **`sec()` / `J()` divergence** | Pinned at 8 and 11 variants by `scripts/checks/shared_helpers_agree.test.mjs`. Not unified — the check stops it getting worse. Measured: **0** functions combine a `''`-returning `sec()` with a strict comparison, so it is a latent hazard, not a live hole. |
| **`scripts/sql` drift** | 175 routines, 166 identical to their newest file, 0 missing, **9 drifted** — named on every run by `scripts/checks/sql_files_match_live.test.mjs`. |
| **`leads` duplicate phones (675)** | Measured last session, **not touched**. Deleting real leads is a destructive production change. |
| **Phase 8 — the 171 ABSENT** | **Not started, except one measurement and one line — see §7.** OCR + Drawing Intelligence, vision routing, the 13 uncovered exception scenarios, the 5 missing workflows, cost per OS, Maturity Index, delete-proposer, the remaining spec #3 UI gaps are all untouched. |
| **Model cascading** | Still correctly blocked: confidence on 5 of 1,642 calls, 0 of 622 on sonnet-5. The output contract must carry a confidence first. |

---

## 6. STATE AT HAND-OVER — measured, not carried forward

```
clock                 2026-08-11 ~17:00 UTC (Dubai 21:00)
Row #3 scorer         126/152 on production — unchanged across the whole session
fn_os_portals_gates   23 met / 23 on BOTH projects
project_parity        BOTH PROJECTS IN SYNC · 197 edge fns · 418 tables · 846 functions ·
                      155 triggers · 0 tables without RLS · 56 anon-executable SECURITY DEFINER ·
                      96 empty prod / 255 staging
pack scorecard        INGESTED 100% · IN USE 37 of 37 · RETRIEVABLE 45.6% (prod), 40.7% (staging)
Supabase advisors     production: 0 ERROR, 448 INFO, 168 WARN
GitHub Actions        green after the one red run this session was fixed in the same session
Vercel                production READY, every preview READY
kb_chunks             95,841 rows, 0 byte-identical duplicates, 43,741 embedded
demand side           customers 0 · inquiries 0 · quotes 0 · transactions 0 — the rehearsal was
                      torn down and the score equality proves nothing was left behind
```

**`decision_policy.demo_rehearsal_active` is `false`** and the one genuinely held notification was
released. `zzz_notifications_demo_guard` is installed and inert; arm it before any future rehearsal
with `node scripts/rehearsal/hvac_dress_rehearsal.mjs arm`, which refuses unless it can prove the
guard by execution first.

---

## 7. INBOUND WHATSAPP IS NOT ABSENT — it can answer you, it cannot obey you

The prompt lists *"inbound WhatsApp (my command channel, outbound-only today)"* as a Phase 8 build
order. Measured before building anything:

**`wa_inbound` exists and is at v12.** Webhook authenticity with Twilio signature *and* provenance
verification, `fn_identify_contact` phone lookup, per-audience prompts for customer / supplier /
unknown, FAQ Level-0 answers with no model at all, a 20-messages-per-hour per-sender ceiling,
Arabic BIDI isolates, escalation to your inbox, and a dedicated **`audience === 'founder'` branch**
that replaces the public script with the leadership brain and an operator's answer contract.

**So inbound is built. The gap is narrower and sharper than "absent", and the code states it
itself**, in its own founder rules:

> *"If he asks you to DO something rather than tell him something, say plainly whether it is already
> automated, and if it is not, say what would have to be built. **Do not claim to have done it.**"*

You can ask it anything. It cannot dispatch a single piece of work.

### One line landed today

The founder branch called `fn_agent_context('brief', 9000, …)` — and that function ignores any
`p_max_chars` below 22,000. Measured on production just now:

```
fn_agent_context('brief', 9000, 'what is stuck today')          32,408 characters
fn_agent_context_capped('brief', 12000, 'what is stuck today')  12,011 characters
                                                                LAYER 4 (EXTERNAL) at offset 9,249
```

It was silently sending 32,408 characters on every message you wrote. It now sends 12,011 —
including the external authority layer that reached no employee at all before today.

### The design for making it obey, worked out and deliberately not built

`agent_brain` already has the whole mechanism: it assembles the capped context, and its
`@@ACTIONS@@` contract creates real `agent_actions` rows addressed to the sixteen named specialists
— that is the company's own work-dispatch path. Routing the founder branch to
`agent_brain(agent:'brief')` instead of a bare model call would turn "tell me what is stuck" into
"chase it", using the credential that already exists for exactly this hop
(`cred_fn_to_agent_brain`, scope `['agent_brain']`).

**Why it was not done in this session, plainly:** `agent_brain` runs to 70 seconds and Twilio's
webhook wall is 15. Calling it inline makes Twilio time out and **retry**, and `wa_inbound` has no
idempotency on `MessageSid` — so you would get duplicate replies and duplicate handoffs. Doing it
properly means moving the founder path into `EdgeRuntime.waitUntil`, returning `TW(200)`
immediately, and sending through `sendWa` when the brain finishes. That is a restructure of the
tail of a 381-line function on your own command channel, and it needed more verification budget
than this session had left. **It is the highest-value Phase 8 item and it is fully specified above.**
