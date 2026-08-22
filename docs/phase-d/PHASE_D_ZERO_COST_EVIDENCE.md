# Phase D — zero-cost and zero-external-effect evidence

Required deliverable 13 of 15. Covers **2026-08-18 14:00 → 2026-08-22 19:01 UTC** (database clock),
project `htdblwldjkcgjvmqkbeh`.

**THE WINDOW MOVED A FOURTH TIME, AND THE CHECK MOVED IT AGAIN.** The session of 22 Aug 2026 applied
F31 through F42 under the founder's ruling of that date, and
`scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs` failed with *"the window does not
close before the work it claims to cover"*, naming `phase_d_fixture_catalogue.recorded_at` at
2026-08-22 18:04:27 UTC as work outside it. That is the whole reason the check was written, and it
is the fourth time it or an auditor has caught this. The close is the database clock read after F42,
the last apply of this session, and every figure below was re-measured at that instant.

**Measured at the new close, 2026-08-22 19:01:09 UTC:**

| | over the stated window |
|---|---:|
| `public.ai_cost_log` rows | **0** |
| `public.ai_cost_log` spend | **AED 0** |
| `public.llm_attempt` rows | **0** |
| most recent `ai_cost_log` row in the whole table | 2026-08-15 02:51:33 UTC |
| `net.http_request_queue` | **0** |
| active `cron.job` | **23** |
| `public.notifications` written on 22 Aug | 5, of which **0 sent** |
| `customers` / `inquiries` / `quotes` / `transactions` | **0 / 0 / 0 / 0** |
| `phase_d_effect_ledger` | **0** |
| `public.leads` | 20,465 — unchanged |

No OpenRouter request and no other paid-provider request was made to produce any figure in this
document or any figure in this session's work. The hold is enforced structurally rather than by an
environment variable: `fn_phase_d_capability_result_accept` refuses `provider_mode = 'provider'`
outright, `fn_phase_d_handler_execute` refuses any step carrying a provider dependency whatever the
execution context says, and F42's sibling F36 added
`phase_d_effect_ledger_never_a_live_provider` — a named CHECK that refuses a live provider result
in the effect ledger, so the prohibition is stated rather than left to a value's absence from a list.

**ONE TRANSIENT READING, RECORDED RATHER THAN ROUNDED.** At 18:41:43 UTC a closing sweep read
`public.customers` = 2 while `scripts/checks/run.mjs` was running against production in another
connection; at 18:44 and again at 19:01 the same query read 0, and `fn_phase_d_fixture_residue()`
returned no rows. The estate's own kernel positive-control checks start and complete real runs
against production, which is what that sweep caught mid-flight. The closing figure is 0; the
intermediate reading is stated because a number seen once and not explained is how a residue claim
goes quietly wrong.

**THE WINDOW HAS NOW BEEN EXTENDED TWICE, FOR THE SAME DEFECT, AND THE SECOND TIME IT WAS THIS
DOCUMENT THAT FAILED ITS OWN STATED PRINCIPLE.**

It read "2026-08-18, 14:00 → 15:10 UTC" until the independent acceptance of 2026-08-20 recorded, as
finding 15, that increments E4–E10 had been applied on 19 and 20 August and the deliverable missed
all of them. The window was extended to 16:43 UTC and this paragraph was written, in these words: *a
zero-cost claim whose window ends before the work does is not evidence about the work.* Five more
files were then applied — E23 at 18:56:31 UTC, then E24, E25, E26, E27 — and nobody moved the
window. The R4 acceptance of the same day found it: **same defect, second instance, same document,
same day.**

**A principle written into a document is not a mechanism.** Nothing in `scripts/checks` read this
file at all — measured, `grep -rn PHASE_D_ZERO_COST scripts/checks` returned nothing — so the only
thing between the claim and the estate was somebody remembering. There is now a check:
`scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs` parses the window out of this
very sentence, asserts zero `ai_cost_log` and `llm_attempt` rows since it opened, and asserts the
close is at or after every timestamp a Phase D or freeze-table apply writes. Run against the 16:43
window it fails, naming `phase_c_change_request.raised_at` at 18:56:31 — it reproduces the R4
finding on its own, which is how I know it works.

What that check cannot see is stated in its own header: a `CREATE OR REPLACE FUNCTION` that writes
no data leaves no timestamp anywhere in the database. The procedural rule still stands and belongs
in the session skill — regenerate this document AFTER the last apply, as the last thing before
staging — and that is the order this revision was produced in: E30, E31, E32, E33, E34, E35 applied
and read back, the schema mirror regenerated from `fn_schema_export()` and verified identical, and
only then these numbers taken.

Everything below was re-measured over the full extended window on 2026-08-21 at 01:02 UTC, after
E40 — the last apply of the session — and after the schema mirror was regenerated from it.

The window has been moved for E36, E37, E38, E39 and E40, and every time the new check is what said
so rather than my memory. E37 exists because E36 put a trigger on `phase_c_freeze_amendment` and thereby
made it an ENFORCING table, which the estate requires to carry a truncate guard; the board caught
that inside one suite run and it was fixed rather than disclosed.

## The required final evidence

`PHASE_D_ZERO_COST_AND_PROVIDER_POLICY.md` names six numbers. All six, measured:

| required evidence | measured | how |
|---|---|---|
| OpenRouter HTTP requests | **0** | no Phase D code path reaches a provider; the gate below refuses every route |
| other paid AI requests | **0** | same |
| `llm_attempt` rows | **0** | `select count(*) from public.llm_attempt where created_at > '2026-08-18 14:00:00+00'` |
| paid inference cost | **AED 0.00** | `select coalesce(sum(cost_aed),0) from public.ai_cost_log where occurred_at > '2026-08-18 14:00:00+00'` → **0**, over **0 rows**. `ai_cost_log` holds **3,507** rows in total and held 3,507 at the start of the window — the table did not move at all. |
| live notifications / publications / payments / refunds | **0 sent** | 14 rows were INSERTED by pre-existing monitoring crons; **0 have a `sent_at` and 0 have a delivery attempt**. Each is named below. |
| — | | |

## What Phase D itself left behind, over the whole extended window

Measured 2026-08-21 01:02 UTC, after the last apply (E40) and after the schema mirror was regenerated from it:

| table | committed rows | why it matters |
|---|---:|---|
| `public.phase_d_dispatch` | **0** | every drive this session ran inside a transaction ending in `raise exception` |
| `public.phase_d_effect_ledger` | **0** | including the drives in which a handler reached `EXECUTED` for the first time |
| `public.phase_d_object_record` | **0** | including the E18 contract probes, which insert six records and roll back |
| `fn_phase_d_fixture_residue()` | **0 rows** | asserted inside each probe as well as after it |
| `public.customers` / `inquiries` / `quotes` / `transactions` | **0 / 0 / 0 / 0** | the zero-residue rule, unmoved |
| active `cron.job` | **23** | 23 at the start of the window and 23 at the end; none reactivated |

The first `EXECUTED` dispatch in Phase D's history happened during this window, and it left nothing.
That is deliberate: a committed effect ledger row produced by a probe would be a row created to move
a number, and `fn_kernel_all_boards()`'s `steps_with_no_effect_ever_produced` still reads 257 for
exactly that reason. The capability is evidenced by a re-runnable driven test —
`scripts/checks/phase_d_dispatch_reaches_executed.test.mjs`, which runs in CI — not by residue.

## The provider gate, read rather than asserted

The hold is not quoted from a status column. `fn_kernel_paid_provider_gate` was **called** with a
representative paid route and asked to decide:

```
select public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini');

{"gate":"kernel_k12","held":8,"rule":"founder_hold","model":"openai/gpt-4o-mini",
 "reason":"8 of 8 routes are held open-circuit until 2126-08-15 02:51:36.685096+00",
 "routes":8,"allowed":false}
```

`fn_kernel_paid_provider_state()` — 5 checks, all green, including
`paid_inference_rows_since_the_hold: expected 0, actual 0`.

BR-054 in `phase_d_rule_enforcement` is wired to this gate as a `PREDICATE`, so every Phase D
handler execution re-reads the live hold rather than trusting a recorded claim.

## The environment the tests ran under

```
NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock PHASE_D_EXTERNAL_EFFECT_MODE=mock
node scripts/checks/run.mjs
```

## Live external effects

**0 produced by Phase D work.**

**Fourteen** rows appeared in `public.notifications` across the extended window — four in the original
12 hours and nine more over 19 and 20 August. The thirteenth, id 1978, was named by the R4
acceptance because it landed AFTER the previous 16:43 close and the document no longer covered it;
it is in the table below now, and it is the same kind of unsent cron digest as the other twelve. Naming every one of them rather than reporting a bare
zero, because "0 external effects" from a query that did not look is the shape of claim this estate
has been burned by:

| id | type | created (UTC) | status | `sent_at` | attempts |
|---|---|---|---|---|---|
| 1947 | `health_alert`  | 08-18 14:30 | digested | NULL | 0 |
| 1952 | `health_alert`  | 08-18 21:00 | digested | NULL | 0 |
| 1953 | `health_alert`  | 08-19 03:00 | digested | NULL | 0 |
| 1954 | `founder_brief` | 08-19 04:30 | pending  | NULL | 0 |
| 1955 | `smoke_alert`   | 08-19 08:30 | pending  | NULL | 0 |
| 1956 | `health_alert`  | 08-19 09:30 | digested | NULL | 0 |
| 1959 | `health_alert`  | 08-19 16:00 | digested | NULL | 0 |
| 1960 | `health_alert`  | 08-19 22:30 | digested | NULL | 0 |
| 1974 | `health_alert`  | 08-20 04:30 | digest   | NULL | 0 |
| 1975 | `founder_brief` | 08-20 04:30 | pending  | NULL | 0 |
| 1976 | `smoke_alert`   | 08-20 09:00 | pending  | NULL | 0 |
| 1977 | `health_alert`  | 08-20 10:30 | digest   | NULL | 0 |
| 1978 | `health_alert`  | 08-20 17:00 | digest   | NULL | 0 |
| 1979 | `health_alert`  | 08-20 23:00 | digest   | NULL | 0 |

**Every one has `sent_at` NULL and `attempts` 0.** Not one was delivered, and none of the fourteen was
produced by a Phase D path: the types are the three the monitoring crons emit, and the timestamps
are their schedules. Phase D wrote no notification at all.

All fourteen are **row insertions by the pre-existing read-only monitoring crons** that remain active
under the founder's selective automation hold, addressed to the founder's own admin address.

The Phase D executions in the extended window were aborted-transaction drives: the whole estate of
30 workflows, several times, plus the E18 contract probes and the schema negative controls. Two of
those drives contain the first `EXECUTED` dispatches in Phase D's history — W01-S05 and W21-S08 —
and every event they emitted went to `phase_c_event_outbox` and was rolled back with the rest of the
transaction. The outbox holds **0 pending** rows.

Other effect classes:

| | |
|---|---|
| `phase_c_refund_decision` rows | **0** |
| `phase_c_event_outbox` pending | **0** |
| live email / SMS / WhatsApp / social publish | **0** |
| payments or refunds executed | **0** |

## Persistent demo data

**None created.** `PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md` forbids persistent demo customers and
suppliers and permits "local fixtures, aborted transactions or explicitly namespaced/cleaned
canaries". What this session used, and what it left:

| probe | left behind |
|---|---|
| W01 executor probe (workflow run 5151, step run 5195) | **0** — ended in `raise exception`; `select count(*) from phase_c_workflow_run where business_object_id like 'PD-PROBE%'` → **0** |
| `zz-phase-d-canary@example.invalid` auth identity (D0-AUTH-002) | **0** — deleted in the same run; removal proved by read-back `DELETE 200` then `GET 404`; `select count(*) from auth.users where email like 'zz-phase-d-canary%'` → **0** |
| customers, suppliers, inquiries, quotes created | **0** |

The canary was an **auth identity only**. No business row of any kind was created for it.

## Capability boundary — why no mock completed a business step

21 of the 257 steps are classified `CAPABILITY_BOUNDARY_READY`. `fn_phase_d_handler_execute`
refuses them outside an explicit test context:

```
pd_capability_unavailable — step %s depends on capability %s ... and no capability provider is
available in Phase D. Paid inference is held until Phase E. Refusing rather than completing a
business step from a fixture.
```

This is D9's requirement — *"real business steps completed from Phase D mock: 0"* — enforced in the
executor rather than asserted in prose. The one probe that did run used
`execution_context = 'test'` on a step classified `NONE`, so no capability path was exercised at
all.

## Boundary of this evidence

This covers the Phase D session window named at the top, on the one project. It is a statement
about what Phase D work caused and what the named tables and gate report for that window. It is
**not** a claim about the estate's entire history, nor about any window before 14:00 UTC on
2026-08-18.

---

# Session 5 addendum — D17 to D25, 2026-08-18 21:41 UTC onward

## The instrument that was measuring the wrong subject

This session's first finding is a correction to the evidence above, and it belongs here rather
than only in the closure. Before D17, `fn_phase_d_fixture_scenario` returned `'external_effects', 0`
on every build **while enqueuing two outbound HTTP POSTs to production edge functions**:

```
net.http_request_queue   before=0  after=2  delta=2
  POST https://…/functions/v1/dispatch_inquiry
  POST https://…/functions/v1/enrich_capability
```

The zero it reported was true of `public.notifications`, which is the only table it counted. It was
not true of the estate's second outbound door. Any earlier statement in this file that rests on that
factory's own `external_effects` figure rests on a count that did not cover `net.http_post`.

**What was nonetheless true, and is a measurement rather than a repair of the record:** pg_net's
worker reads committed rows, and every Phase D drive and scenario build ends in `raise exception`.
The probe above read `before = 0` on a database that had already had dozens of scenario builds run
through it. A queue that had ever leaked would not read zero. Nothing was sent. The guard was wrong;
the outcome was not.

## Measured for this session, after the fix

| | |
|---|---|
| `llm_attempt` rows in the session window | **0** |
| paid inference cost | **USD 0.00** |
| outbound HTTP enqueued by a full 30-workflow batch | **0** (was 2 per scenario build) |
| `public.notifications` rows written by this session | **0** |
| live email / SMS / WhatsApp / social / payment / refund | **0** |
| Apify runs · production Dropbox writes | **0** · **0** |
| active cron jobs, start → end | **23 → 23** |
| `net.http_request_queue` at close | **0** |

**The notifications boundary, stated rather than rounded.** `public.notifications` gained 2 rows in
the 14 hours covering this session: both `type='health_alert'`, `status='digest'`,
`to_email=management@quotesdone.com`, timestamped 14:30 and 21:00 UTC. Both are the scheduled
read-only monitoring the hold keeps active, and **both predate this session's first drive at 21:41
UTC**. In addition, every scenario build asserts its own per-stage delta of 0 and aborts the whole
build on any movement.

## Nothing left behind

Read back from the database after the full 30-workflow batch:

| relation | rows |
|---|---|
| `customers`, `inquiries`, `quotes`, `transactions` | **0** each |
| `phase_d_effect_ledger` | **0** |
| `net.http_request_queue` | **0** |
| `fn_phase_d_fixture_residue()` | **0** |
| `leads` | **20,465** — unchanged |

The builder's own residue assertion was itself repaired this session: it queried
`phase_c_workflow_run.source_ref`, a column that does not exist, so **the check that proves the
probe left nothing behind had never once run**. It reads `dedupe_key` now, and reports 0.

## What is enforced rather than asserted

Three guards added this session refuse rather than report, and each was made to FIRE before it was
trusted:

* `pd_object_outbound_request_produced` — any Phase D test write that leaves an outbound request in
  `net.http_request_queue` is refused, with the URL named. Proved by emptying the door registry and
  watching a scenario build refuse.
* the outbound suppression is **not defeasible by the caller** — a generated payload re-armed
  `dispatch_inquiry` one file after it was closed, and the writer now overwrites.
* `fn_phase_d_object_write` counts the queue's high-water mark rather than differencing two counts,
  because pg_net's worker DELETES as it drains and a plain delta can be masked to zero.

## Boundary of this addendum

This covers 2026-08-18 21:41 UTC onward on the one project. `llm_attempt` and `notifications` were
counted over a 12- and 14-hour window respectively, which is wider than the session; the outbound
and residue figures are per-batch and per-build. It is not a claim about any earlier window, and the
correction at the top of this addendum is the reason to read the earlier sections with the coverage
of their own instruments in mind.
