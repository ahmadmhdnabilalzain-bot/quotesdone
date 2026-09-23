# 12 Aug 2026, part 6 — dead on arrival

Continues part 5. PR [#277](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/277). Both
projects, verified by execution.

---

## The RFQ that arrived before its supplier existed

Part 5 recorded a single failing journey step — 27, *supplier receives the inquiry*, inbox 0 — and
said it wanted a look. It was not a harness quirk. It is the demand loop's second door, and it was
shut.

`dispatch_inquiry` has **exactly one caller**: `trg_autodispatch_inquiry`, which fires on the
`rfq_ready` transition and only while `routing->>'dispatched_at'` is null. `dispatch_inquiry` writes
`dispatched_at` **unconditionally** — including on the run that fanned out to zero suppliers — and
then refused every later call with `skip: 'already_dispatched'`.

So an RFQ created before a matching supplier existed was routed to nobody and could never be routed
again:

- not by the trigger — `rfq_ready` never transitions twice, and `dispatched_at` is now set;
- not by a sweep — there was none;
- not by the supplier's own registration — nothing watches for that.

**It was dead the moment it was created, and nothing failed anywhere.** Step 26 answers `ok`. The
only visible trace is an empty supplier inbox.

That is this company's normal case, not an edge case. Demand arrives first; suppliers are onboarded
from 20,470 leads afterwards. Every RFQ that lands before its trade is staffed would have been lost
in silence.

### The fix, and the mistake I caught in my own first version

Two parts. The skip now requires the previous run to have **actually reached someone**, and
`fn_rfq_redispatch_sweep` offers the zero-reach ones to the matcher again every six hours — because
with the trigger one-shot, nothing else ever would.

My first version read `Number(routing.fanout ?? 0)` on one side and `coalesce(fanout, 0) = 0` on the
other. Both map an **absent** counter to zero, so any RFQ whose reach was merely unrecorded would
have been treated as having reached nobody and re-approached suppliers who had already been told.
That is `least(100, NULL)` returning `100` in a new place — absent evidence read as a specific
value. Both sides now require the counter to be **recorded** as 0; unknown reach is left alone,
which errs toward leaving an old RFQ dead rather than risking a duplicate approach to a supplier.

Re-notification is impossible by construction: only zero-fanout RFQs qualify, a zero-fanout RFQ
notified nobody, and the moment a retry reaches someone the row stops qualifying. Backoff six hours,
capped at 30 attempts, so an RFQ nobody can serve stops asking after a week instead of forever.
Completed, cancelled and awarded RFQs are excluded.

**Promote-safe.** The project ref is read from `app_secrets` with the same fallback
`fn_action_invoke_dispatch` uses. `trg_autodispatch_inquiry` hardcodes its own URL, which means its
definition is *not* the same text on both projects — a live example of why `--promote` needs
watching. The `REVOKE` was re-run directly on production, because promote carries the definition and
not the grants; confirmed `anon` and `authenticated` cannot execute on either project, and
`CREATE OR REPLACE` preserved that ACL on the second apply.

The cron and its `cron_registry` row are in one file, deliberately — a missing registry row is what
dropped Row #3 to 126 earlier today. **0 undocumented active crons on both projects** after.

### Verified

- Aborted transaction on staging: **0 RFQs eligible before**, the defect's exact shape manufactured,
  **1 eligible after**, `fn_rfq_redispatch_sweep(20)` returned `retried: 1`, rolled back.
- Worth knowing: `inquiries.rfq_ready` is **derived** — a plain `update … set rfq_ready = true` is
  overwritten, so the probe had to start from a row that already carried it.
- `journey_test` end to end on staging: **40/40**, step 27 now PASS, teardown showing
  `inquiry_matches 1` where the previous run had none.

### And the RFQ waiting behind your two clicks will land on a real supplier

Worth knowing before you tick the boxes: I ran the matcher that dispatch itself uses, against your
own HVAC brief, on production.

```
select * from fn_match_capability(array['hvac'], 'Supply and install 40 TR ducted split AC system',
                                  null, null, null, 180000, 'Dubai', 10);

30466  MERIDIAN MEP CONTRACTING LLC  score 5.0  trades hvac, electrical, plumbing, mep_general
                                                why: "trades hvac · covers Dubai"
```

So intake `18e2c133` has a real, approved, capability-enriched supplier waiting for it. The moment
`phone_verified` and `tos_accepted_at` are satisfied, Send creates the inquiry and dispatch reaches
that company — and if it somehow reached nobody, the sweep built here would offer it again six hours
later instead of leaving it dead.

---

## Two more one-shot triggers, measured not guessed

`trg_enrich_capability` has the identical shape: it fires only when `approval_status` becomes
`approved` and `capability_enriched_at` is null. If the `enrich_capability` call fails, the marker
stays null and `approval_status` never transitions again — so an approved supplier with no
capability record is invisible to `fn_match_capability`, and therefore to every RFQ, permanently.

Measured: **production 1 approved, 0 stuck.** Staging 50 approved and 50 unenriched, but staging
leads are largely fixtures and I did **not** establish that those 50 ever went through a real
approval transition, so that number should not be read as 50 real failures. Not biting production
today; business-critical the moment onboarding starts. Left as a flagged follow-up rather than a
rushed second sweep.

**Nothing follows up on a ready intake the customer never sends.** Production holds 3 `ready`
intakes and 0 consumed; two are a QA address from 29 Jul and one is yours from today. At scale, a
brief the customer completed and then abandoned is lost demand with no owner. Recorded, not built —
it would email customers, and there is exactly one real instance today.

---

## s36 — measured, and it is not a schema change

Item 3 of the brief. I checked `decision_log`, `agent_actions`, `evolution_proposal`,
`board_opinion`, `org_action_executor`, `agent_runs`, `org_tasks` and `challenge_record` for any
column matching `assumption|premise|impact|expected|cost|spend|price`. **There is none.** So unlike
`alternatives` — which was one join away in `decision_log` and could be extracted honestly — there
is nothing in the estate to extract assumptions, expected impact or cost from.

That makes s36 an **output-contract** change, not a schema change: the routines that write
recommendations have to state these three things at the moment they reason. Adding three columns
that could only ever be NULL would manufacture the appearance of a capability, which is worse than
the honest gap.

Where to start, measured: of the recommendations in the last 30 days, **556 of ~1,311 come from a
single agent, `it`** — 42% behind one contract. `onboarding` is next at 158. I did not start this
build; a half-finished contract change across 41 routines is worse than a stated gap.

---

## Sweep

```
Actions       8 most recent runs all success, including "deploy edge functions"
advisors      0 ERROR on BOTH (prod 453 INFO / 170 WARN, staging 441 / 168 — levels counted, not contents)
gates         23/23 met on BOTH
parity        BOTH PROJECTS IN SYNC
crons         0 undocumented on BOTH
OpenRouter    0 refusal / credit / rate-limit errors in agent_runs in 6h — it is not refusing calls
journey       40/40 on staging
```
