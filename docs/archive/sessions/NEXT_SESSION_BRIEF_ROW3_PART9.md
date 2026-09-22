# Row #3, part 9 — opening brief: FINISH THE PACKS, DEPLOYED, NOT STAGED

Row #3 spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md`. Pack scorecard: `scripts/kb/pack_scorecard.mjs`.

**Row #3 measured 2026-08-10 ~12:00 UTC: 119/152 (78%), 0 errored.**

---

## HOW THIS SESSION IS WORKED — READ THIS BEFORE ANYTHING ELSE

**Work continuously. The only thing that stops you is the founder typing "stop".**

Nothing else stops you. Not finishing a task. Not a defect. Not a surprise. Not a decision you
think he needs to make. Not the end of a section of this brief.

- **Do NOT report progress.** No "I've finished X", no "here's what I did so far", no summaries
  between items, no asking whether to continue. He has said this three times.
- **Do NOT ask questions.** Make the engineering call, do it, and write the reasoning into the
  commit. If a fact is genuinely his alone (a credential, a price, a number only he holds), log it
  and carry on with everything that does not depend on it.
- **Do NOT wait.** When something needs time — an import, a cron, a scorer run — start it in the
  background and pick up different work immediately. Never idle against a clock.
- **The ONE approval that exists is a refund.** Nothing else. Not spend, not model routing, not
  org structure, not authority, not activation. Decide it yourself.
- **Speak once, at the end**, when the pack scorecard reads 100% DEPLOYED and you have proved it.
  That single message is the only output he wants.

---

## 0. READ THE CLOCK FIRST

```sql
select now() at time zone 'utc';
```

Dubai is UTC+4. Query `cron.job_run_details` — never take a cron table in a brief on faith. A
PARTIAL scorer run is not a score: check for the `SPEC FILE #3 … : N/152` summary line.

---

## 1. THE DEFINITION OF DONE THIS SESSION

**Deployed, not staged.** A record in a table nothing reads is not delivered. The test for every
artefact is the same and it is not "did the import succeed":

> Which production routine or edge function reads this, and does it return this data when called?

Last session that distinction was the whole story. All six packs measured **100% ingested** while
115,148 knowledge records sat in `kb_stage.records` — read by exactly one database function —
and every customer-facing path (`kb_search`, `agent_brain`, `inquiry_intake`) read `kb_chunks`,
which held **zero** of them. The schema being *named* `kb_stage` is how it hid behind a green
number. It is now deployed: `kb_chunks` 5,139 → **120,287**, and
`select count(*) from kb_chunks where citation ilike '%QD-KB%'` returns **115,148** where the
part-8 brief correctly measured 0.

**Assume the same defect is still present elsewhere and go looking for it.** Sections 2 and 3 are
the two places it is already known to be.

---

## 2. WHAT IS STILL STAGED — MEASURED, NOT GUESSED

### 2.1 `fn_ops_department_context` HAS NO CALLERS

```sql
-- callers of fn_ops_department_context  ->  NONE
-- callers of fn_ops_authority_check     ->  fn_dept_authority   (this one IS wired)
```

Last session enabled all 240 decision rules, 236 SOPs and 240 exception playbooks and put them
into `fn_ops_department_context`. **Nothing calls that function.** The Company Operations pack is
in exactly the position the knowledge half was in this morning: complete, enabled, unread.

`fn_agent_context` — 31 KB, feeds every AI call in the company — does reference `fn_ops_*`. Find
out precisely what it reads and what it does not, then wire the department's rules, SOPs and
playbooks into the context the deciding employee actually receives.

**Respect the timeout history.** `agent_brain` timed out twice at ~56 s when the handoff inbox
added 2,082 characters; `it`'s prompt is 30,821 tokens and its one prior success took 53,139 ms.
The inbox is bounded at 215 characters per line, 3 lines, 647 total. Bound whatever you add the
same way, and measure the resulting prompt size before and after.

### 2.2 115,113 OF 115,148 PACK ROWS HAVE NO EMBEDDING

`kb_search` tries `kb_match` (vector) **first** and falls back to full-text. The corpus answers
only on the fallback path. `kb_embed_backfill` runs every 2 minutes against the `kb_embed` edge
function; `embedding_gte` is the column.

This is a spend decision and the spend decision is yours. Read
`05_OPENROUTER_REDUCTION_PLAN.md` first — it says embed **narrative only, where retrieval needs
it**, not all 115,148. Decide a subset, embed it, measure recall against the FTS path, and record
what you chose and why. See section 5 on the balance.

### 2.3 THE 199 RELEASED ACTIONS ARE STILL PENDING

`approval-center-everything-else-automatic` counts `status='pending' or escalated` as *paused for
the founder* and does **not** count `needs_review`. So while 203 items sat in `needs_review` the
check read the company as automatic; re-gating moved them to `pending`, where the check can see
them — 204 of 1,266 in 30 days, 16.1% against a 10% bar.

**The founder's queue is 1. The backlog is 199 and it is real work.** The check goes green when
the work drains, not when it is hidden again. Do not move them back. Drain them.

Only ~18 of 66 employees do anything in a day and `cos_execute_hourly` reaches three items a run.
That arithmetic does not clear 199. Either the executors in section 3 have to run, or the dormant
workforce decision has to be made, or both.

---

## 3. THE 39 ACTIONS THAT CANNOT EXECUTE

```
org_action_executor              55  registered
org_action_executor_rpc_allowed  16  can actually execute
```

The 39 are **not broken rows**. Their `target` is an **edge function** — `quote_compare`,
`uptime_check`, `match`, `knowledge_exam`, `ai_health`, `send_outbox` — not a database routine, so
`fn_execution_run` cannot call them: it invokes nothing, it writes an `agent_actions` row telling
a person. One HTTP invoker is the missing piece, and `org_action_executor` was **already designed
for it**: `idempotency_strategy`, `timeout_seconds`, `max_attempts`, `backoff`,
`required_authority` and `compensation_action_class` are all columns on that table and **not one
is implemented**.

**Build order, and it matters.** The 28 that are `advisory_safe = true, reversible = true,
risk_tier = low` first, one at a time, each proved by execution. Then medium. `outreach_send`,
`pdpl_action` and `collections_chase` are high risk and **not reversible**, and
`refund_within_window` is the one action reserved to the founder — those come last or not at all.
A generic invoker written without room to watch it is how a session hands AI employees the ability
to email strangers and move money on the same afternoon.

---

## 4. WHAT IS ALREADY DONE — DO NOT REBUILD IT

Four things last session turned out to be already built, and two were nearly rebuilt. Check before
you write anything.

| already true | evidence |
|---|---|
| Both corpora imported **and** deployed into `kb_chunks` | 115,148 rows, FTS populated, proved on `kb_search`'s own path |
| All 86 routes activate | `fn_kb_route_activation_blocked` returns blocked=false for 1..86 |
| Every route names an authority | 0 routes read `confirmed_covered` with `named_authorities_in_corpus = 0` |
| Broad autonomy unblocked, both projects | `v_autonomy_status`: allowed true, blockers [], p0_open 0 |
| No credential holds blanket scope | `legacy.shared` narrowed from `{*}` to three callees |
| 61 model policies, 60 active | plus `ai_tool_matrix` 22, `model_catalog` 14, `model_policy_by_identity` 120 |
| `quote_compare` has a model-free fallback | proved on staging with the model forced to fail |
| Reputation can restore authority | gated 34 → 22, audited both ways, idempotent |
| The inbox shows all 22 kinds | bounded at 647 chars; closable = everything except money |

**The target org belongs in `ops_kb_stage`, not the live tables.** Promoting the 24 departments
and 96 roles into `org_departments`/`org_agents` was tried and reverted: `digital-twin-department-health`
counts every row in `org_departments`, so twenty unstaffed departments turned 15-of-15 into
15-of-35 and cost three Row #3 checks. The pack's `department_crosswalk` exists precisely so the
target state is *mapped*, not merged. Do not try it again.

---

## 5. MONEY, AND THE ONE THING THAT IS HIS

```
OpenRouter   $16.88  09 Aug 05:00
             $11.87  10 Aug 07:00     ~$4.62/day  ->  roughly two days from this brief
```

`agent_brain` is ~93% of it. Do not top up and do not disable it. If the balance is gone, say so
in one line at the end and do everything that does not need a model — which, after this session,
is most of it: routing, retrieval by FTS, authority checks, the deterministic quote comparison and
every executor in section 3 are all model-free.

**Genuinely blocked on him, and only these:**

1. **Mobile login.** `external_phone_enabled` is false and `sms_twilio_account_sid` is null. His OS
   sign-in emails a code. He asked for mobile number + verification. Needs Twilio credentials —
   only he can issue them. Flip the flag the day they exist.
2. **Stripe TEST keys.** Unchanged.
3. **The WhatsApp command channel.** He wants to run the company by texting his registered number
   — *"print me last month's revenue"*, *"what social media post do you have for next week"* — and
   deferred it explicitly. It is recorded in memory, not forgotten.

---

## 6. THE FINISH LINE, AND HOW TO PROVE IT

Run the scorecard against **both** projects:

```bash
node scripts/kb/pack_scorecard.mjs --ref=htdblwldjkcgjvmqkbeh --packs=<extracted packs dir>
node scripts/kb/pack_scorecard.mjs --ref=pglpqrhvozwepymcuunn --packs=<extracted packs dir>
```

It scores two axes on purpose — **INGESTED** and **IN USE** — because a corpus in a table nothing
reads is not delivered. At the close of part 8: overall **99.5% ingested, 22 of 37 artefacts in
use**. The number to move is the second one.

**You are done when, on both projects:**

- every pack reads **100%**, and
- **IN USE is 37 of 37**, and
- each of the four remaining OS_PORTALS gates is either met or has a stated reason that is not
  "not measured" (two need a human at a screen, one needs a rollback drill you can actually run,
  one is his signature), and
- Row #3 is re-measured on a **complete** run with the summary line present, and every regression
  against 119/152 is either fixed or explained as a true finding.

Then, and only then, one message: the scorecard, the proof, and what remains his.

---

## 7. FOUNDER RULES, UNCHANGED

One row at a time. Everything deploys to **BOTH** Supabase projects — production
`htdblwldjkcgjvmqkbeh` and staging `pglpqrhvozwepymcuunn`. Nothing is left on staging: it is a
rehearsal surface, not a destination. Verified by **EXECUTION** in the same turn, never by
typecheck or by reading. Committed and merged via PR.

A MISSING verdict is a BUILD ORDER, never an argument that something existing already covers it.
Never fabricate, back-date or mass-close data to turn a gate green, and never weaken a check. If a
change makes a check HARDER because the old pass was false, that is correct — say so.

**VERIFY THE VERIFICATION.** Assert on a 200 **and** on a non-zero effect. The aborted-transaction
probe pattern works: do the write, count the effect, `raise exception` with the counts so it all
rolls back and the numbers still come out. It has now caught four real failures, including one of
mine: a corpus evidence scan that marked 39 routes covered on regulation text that named no
regulator, on five of the most heavily licensed trades in the catalogue.

**Every SECURITY DEFINER function you create is granted EXECUTE to PUBLIC automatically.** Revoke
it in the same migration. Production is at **56**.

**The Supabase CLI bundles without typechecking.** `functions deploy` succeeding is not evidence
of a green build — `deno check` is. CI caught a TS2339 that a successful deploy had hidden.

---

## 8. END-OF-SESSION SWEEP

GitHub Actions, Vercel, and both Supabase projects. Report what you checked and what you found,
including "nothing". Zero-step Actions jobs mean quota, not code. **Read the dates** on anything
you find — a 30-day rolling window will keep showing you a failure that was fixed on day one.
