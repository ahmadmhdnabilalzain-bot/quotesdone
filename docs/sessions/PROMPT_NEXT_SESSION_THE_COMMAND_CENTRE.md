# Next session prompt — build the command centre

Copy everything below the line into a new session.

---

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Don't report the
OpenRouter balance, but DO tell me if it's refusing calls.

THE STANDARD. The company can operate, learn, manage itself, identify problems, make professional
decisions, improve its performance, and actively work toward **AED 1,000,000 by end of July 2027**
with minimal founder involvement. Not "the agent exists". Every item below is yours to build, fix or
decide. **I decide three things only: Stripe refunds, spending money, and the three go-live
switches.** Everything else is yours. Do not ask me to choose a number you can measure your way to.

**Deploy everything to PRODUCTION. I do not want anything sitting on staging.** Staging exists only
because `qd_guard` refuses direct production writes — apply there, read the verified definition back,
post that to production, assert md5 on both. If you tell me something is done, it is live on
`htdblwldjkcgjvmqkbeh`. We are running out of time.

Read `docs/sessions/HANDOVER_2026_08_13_THE_DOOR_THE_DRILL_AND_FOUR_LIARS.md` first (six sections
plus an addendum), then this. 6 PRs merged 12–13 Aug (#288–#292 plus one commit that wrongly went
straight to main, `ca0daa0`).

**State:** Row #3 **127/152** · gates 23/23 both · parity **IN SYNC** · main CI green including
`deploy edge functions` · invites **LIVE** (9 sent, 0 bounced that night, 3 bounced in 7d) ·
reflection budget 24/day · dr_drill **ok, 123,691 rows, 11/11 tables** · 1 real supplier ·
1 customer · **0 inquiries** · **0 phone-verified customers** · 3 go-live switches false ·
AI spend AED ~19/day, ~140/month.

---

## 1 — THE ORCHESTRATOR. This is the one that matters. Measured, not guessed.

I want a command centre: I text it, and **an agent takes the message and delivers it to the
responsible department and the responsible agent, who then does the work.** Today it says
*"Routing this to CFO now"* and nothing happens.

**Why nothing happens — measured on production 13 Aug:**

```
85 pending agent_actions across 15 kinds.
For EVERY kind, (select count(*) from org_action_executor where action_class = kind) = 0.
56 executors exist: 40 edge, 22 low-risk + advisory_safe + reversible + not notifies_human.
```

`agent_actions.kind` (`handoff` 42, `customer_escalation` 9, `strategy_rec` 7, `legal_flag` 6,
`security_incident` 3, `knowledge_task` 3 …) and `org_action_executor.action_class` are **disjoint
namespaces**. It is not a broken bridge — there is no shared vocabulary at all between what agents
write and what the company can run. 42 of the 85 are agents handing work to each other and nobody
picking it up.

Build the dispatcher. It needs: a kind→action_class map, a decision per class about what may run
unattended, and it MUST honour `org_action_executor.notifies_human` before any sweep touches a row —
an executor can be low-risk, advisory-safe and reversible and still email a supplier. A half-built
dispatcher that starts firing executors is the worst possible outcome; build it deliberately.

## 2 — THE WHATSAPP COMMAND CENTRE. My words, so nothing is lost.

The American Twilio number (`+1 218 316 6814`, `twilio_wa_from`) is the single channel. It must
carry three audiences, and **take it in general, not as a list of examples**.

**Me, from `+971 50 931 9355` (my work number, `admin_mfa_phone`, `fn_identify_contact` returns
`audience:founder`):** anything I ask, it replies. Anything I instruct, it does — including
operational changes, directly, not as a ticket. If I ask for a report it should reach me **as a
proper PDF**. If I ask for next week's invite plan it should send me the plan **with the suppliers
it is going to contact**. It goes that deep.

**Suppliers:** is my profile approved · how many inquiries have I missed · what was my last
quotation · adjust my quotation price · **attach a new trade licence and have it actually update the
system**. Everything except *generating* a quotation, which goes to the portal.

**Customers:** everything except creating a *new* inquiry, which goes to the portal. How many
suppliers received my inquiry · what is the average price of the quotes I received · status of
anything of mine.

### What is already built and PROVEN on production

- **Scoped read for all three audiences** — `fn_wa_context(audience, phone)`, scoping done in SQL off
  the sender's phone so a prompt can never reach another person's rows. Founder gets the company
  (leads, claimed, approved, licence-verified, invites, demand, money, health). Supplier gets only
  their lead row (approval, licence no/authority/expiry, doc on file, blocker, inquiries received /
  quoted / **missed**, quotes, last quote, jobs won). Customer gets only their inquiries (suppliers
  received, quotes received, and **pre-reveal a rounded band only** — never individual quotes, never
  a supplier name).
  Proven: *"how many suppliers do we have and how many are verified"* → "Claimed 7, Approved 1,
  Licence-verified 1 … 20,471 leads, 19,904 with an email". Same question returned *"I don't have
  that data"* an hour earlier.
- **Founder setting-writes** — `fn_founder_settings()` (16 keys) + `fn_founder_apply_setting()`.
  Proven end to end through the real webhook: *"change the weekly cap for emails into 15 instead of
  10"* → `invite_daily_cap` 10→15, audited in `founder_directive`, replied "Done — changed from 10
  to 15". Out-of-bounds, unregistered keys and switches all refuse with a reason. Money, refunds,
  `auto_action_max_aed` and the go-live switches are deliberately not in the registry.

### What is NOT built — do not let anyone tell you otherwise

1. **PDF / media OUT.** No report leaves as a document. Twilio carries media by URL, the estate
   already builds PDFs (`pdf_native`) and signs storage URLs. Nothing is wired.
2. **Media IN.** `wa_inbound` reads `Body` and **never looks at `MediaUrl0`**. A supplier attaching a
   trade licence achieves nothing — nothing OCRs it (`license_extract` exists), nothing updates
   `leads.license_doc_path` / `license_expiry` / `verification_status`.
3. **Writes for suppliers and customers.** "Adjust my quotation price" needs the registry-and-bounds
   treatment the founder settings got, scoped per supplier, plus an audit row.
4. **Dispatch** — item 1 above.

## 3 — The demand door is still shut. 0 customers are phone-verified.

`create_inquiry` refuses until `customers.phone_verified`. Both routes are live and proven:
`+97142587734` is a **landline** (Twilio Lookup; SMS returns 21635) and `kyc send_sms` now falls
back to `Channel=call` — HTTP 201, and the deployed function answered `{"ok":true,"channel":"call"}`.
`+971509319355` is a **mobile** and Twilio's Verify log shows an SMS to it **Approved on 14 Jul**.
The portal lets the number be corrected now (`Save details` is no longer hidden). It needs one human
action at `/en/me` and then intake `18e2c133-f728-464a-b5f1-43d1f9dc3c1e` reaches lead 30466
MERIDIAN MEP at score 5.0. **Do not fabricate an inquiries row.**

## 4 — Drawing redaction yields 4 of 6 pages, so no drawing reaches a supplier.

BoQ extraction is excellent (23 line items with quantities and cited schedule references from a real
7-sheet consultant set). Redaction refuses 2 of 6 pages, `create_inquiry` refuses a partial set, so a
real drawing arrives as a BoQ with no drawing. **Measured across five runs, stable at 4/6.** Two
things were tried: the verifier exclusion for view titles and scale notations was KEPT; a blanket
title-block mask was REVERTED because the yield was 4/6 with and without it. The verifier's own words
on what remains: *"Company name/logo visible in bottom right corner (appears to be a triangular
architectural firm logo)"* and a `REVISIONS` block. **Aim there, not at the title strip.** Repro:
`node scripts/staging/prove_boq_real_drawing.mjs <pages.json> [original.pdf]`.

## 5 — s36: read the WRITER, not the age of the row.

The brief before this one said "~600 of 1,311 carry NULL". Truth: **1,433 agent_actions in 30 days
and 2 carried all three columns**, because the writers shipped hours earlier. Built since:
`strategy_rec`, `supplier_risk_*`, `hot_lead`, `supply_gap` (all probed), and both `coverage_gap`
writers (deployed, typechecked, **not** execution-proven — the branch needs an RFQ that matches zero
suppliers). `sla_review` was already done by an earlier session. Check each writer before believing a
count.

## 6 — Spec #3 UI: 7 of the 22 unread tables remain.

`employee_knowledge` (900 rows) now has a reader in the Smart Engine drawer. Still unread:
`ai_quality_snapshots` (1,167), `scenario_expectation_baseline` (3,324), `internal_credential_audit`
(1,760), `marketing_library`, `catalog_subcategories`, `subcategory_agent_map`, `field_definition`.

## 7 — Pack scorecard: 6 artefacts unscorable until three zips are found.

100% across 31 of 37 on both projects; the AI_AUTONOMY_ROUTING pack and the model catalogue have no
source file in the working tree. All five probe IN USE against the database, so they are ingested and
read — only the disk-side comparison is missing. This is file recovery, not engineering.

## 8 — Watch the invite ramp yourself.

Live, cap 10, `fn_invite_ramp` doubles it daily while the list behaves, ceiling 200, hard pause at
5% bounce or `greatest(5, sent × rate)`. 3 bounces in the last 7 days. `select * from
v_invite_funnel;` and `leads where invite_status='bounced'`.

---

## Traps that cost time this session — do not rediscover

- **`apply_sql --promote` carries the DEFINITION, not the GRANTS.** A `REVOKE` in the same file lands
  on staging alone and the function stays **anon-executable on production**. Hit twice in one night;
  `project_parity` caught it both times. Use `--promote --ddl`, which carries the whole file, and
  always re-run parity after promoting a new SECURITY DEFINER function.
- **`ai_gateway`'s cache does a SEMANTIC lookup at 0.95 similarity** over
  `(sys_stable + sys).slice(0,400) + convo.slice(0,800)`. Any classifier whose system prompt dwarfs
  its input gets the PREVIOUS call's answer — measured: three different WhatsApp messages all
  classified as the first one's directive, `ai_cost_log` showing `cached:true`, 0 prompt tokens.
  Pass `cache_ttl_min: 0` on every classifier. Only `wa_inbound`'s is fixed.
- **A new table gets RLS on production automatically (event trigger) and NOT on staging.** Same DDL,
  two different tables. `project_parity` catches it.
- **A missing source file can score 100%.** `pct(got, 0)` returns 100. Ask what a scorer prints when
  its input vanishes.
- **Two chains sharing one staging table lie.** A 28s hop is long enough for the edge gateway to
  retry the POST and start a second chain.
- **A retention DELETE can veto a security-critical UPDATE** — one transaction, one raise, everything
  rolls back. `control_mode_sweep_5min` failed 377 times over 31 hours that way.
- Every `cron.schedule` needs a `cron_registry` row in the same change. `_` is a word character in
  Postgres regex. `least()`/`greatest()` ignore NULLs. BEFORE triggers fire in NAME order. A cron
  reporting `succeeded` for a `net.http_post` only means the request was QUEUED. HTTP 546 kills the
  isolate so the function's own catch never runs.
- **Never push to main.** One commit did (`ca0daa0`). Everything goes through a PR.

## The lens that keeps working

**Is this number measuring what its name says?** · **Has this recovery path ever actually run?** ·
**What does the user CLICK to reach this?** · **What does this table know that no screen shows?** ·
and new this session: **what does this instrument print when its input is absent?**

Verify by execution in the same turn. Aborted-transaction probes for writes. Never fabricate,
back-date or mass-close data to turn a gate green. Deploy to BOTH Supabase projects, merge via PR,
and run the end-of-session sweep before the one line.
