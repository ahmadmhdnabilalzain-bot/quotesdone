# Handover — 13 Aug 2026 (session ran 23:00–00:15 UTC / 03:00–04:15 Dubai)

Clock at start: `2026-08-12 23:00:53 UTC` = `2026-08-13 03:00 Dubai`.

**OpenRouter refused nothing.** 33 model calls in the six hours around this session, 0 failed. The
ten `ok=false` rows on `action_worker` that looked like refusals were ours, not theirs — see §1b.

One branch, `the-queue-that-had-nobody-to-hand-it-to` → **PR #294**, three commits, every change
deployed to BOTH projects before the commit and verified by execution in the same turn.

---

## 1 — THE ORCHESTRATOR. The dispatcher already existed. Three real defects, none of them the map.

The brief said `agent_actions.kind` and `org_action_executor.action_class` are disjoint namespaces
with no bridge between them. **Measured on production, that is no longer true.**
`fn_agent_action_work_sweep` turns an eligible `agent_action` into an `action_execution` row with
`action_class = 'agent_action_work'`, `fn_action_invoke_dispatch` POSTs it to `action_worker`, and
**257 of 267 model calls that path has made succeeded.** Both crons run and both are green.

47 rows were pending. Read the writer, not the count:

| | |
|---|---|
| 24 | kinds the machine must never settle alone. Correctly refused, then correctly forgotten. |
| 8 | eligible handoffs raised at 22:35–22:41, **after** the 22:35 sweep. Not a defect — they ran at 23:35. |
| 11 | eligible and already attempted; 9 failed, 8 of them the same way. |
| 3 | kinds in **neither** list: `backup_alert`, `coverage_gap`, `simulation_apply`. No policy at all. |
| 1 | succeeded and the source row never left pending (2 of 257 lifetime). |

### a. The gate never read `notifies_human`, and six live executors set it

Your instruction was exact and the column had been sitting there being true and being ignored.
`fn_action_invoke_dispatch` gates on active / required_authority / reversibility / and the triple
`risk_tier='low' AND advisory_safe AND reversible`. **41 executors pass that gate and six of them
have `notifies_human = true`** — `capability_review`, `expense_log`, `forecast`, `health_report`,
`money_verify`, `security_review`.

A blanket refusal would have been a regression, not a fix: all six exist to report the company's
own state to *you*, and `health_report` and `forecast` have already run 11 times between them. What
was missing was not a ban, it was **the decision per class you asked for** — so it is now data.
`org_action_executor.unattended_ok`, **default FALSE**. The six are opted in with the reason
recorded (each notifies the founder about our own state; none contacts a customer, a supplier or
any third party). Anything added later that notifies a human is refused until somebody decides.

Probed on production inside an aborted transaction: with `unattended_ok` false the dispatcher
returned `dispatched=0 refused=1`, the reason quoted in the row, **nothing POSTed**; with the
decision recorded the same row passes the same gate.

### b. The ceiling went up and the clock did not. This is what "the model returned nothing" was.

`max` was raised to 8,000 tokens on 11 Aug. `timeoutMs` stayed at the 70 seconds that had suited a
900-token answer. Of 267 calls, **10 returned `ok=false` with zero tokens, and eight of those ten
recorded `latency_ms` between 72,056 and 72,086** — the abort. One says it outright: *"ALL MODELS
FAILED after the full ladder: The signal has been aborted."* The successes run 34.5s to 72.0s for
2,762 to 6,138 output tokens.

**The harder the employee worked, the more likely we hung up on it** — and the item went back in the
queue reading "the model returned nothing", which is not what happened. Now 105s, chosen to sit
inside the executor row's own `timeout_seconds = 120`.

**After, on production: 9 dispatched, 9 succeeded, 0 failed.** Nine `agent_actions` settled in the
hour, each with a real deliverable — 5,279 / 4,020 / 3,917 characters and a closing OUTCOME line.

### c. Neither list could say "I don't know"

The 14 auto and 8 founder kinds were hard-coded **twice** — a SQL `IN` list inside the sweep and two
TypeScript `Set`s inside `action_worker`. They agreed; nothing made them agree. Worse, neither had a
third answer: a kind in neither list was not refused with a reason, it was **never selected**,
silently, by both. **24 kinds are in that position and 1,459 rows have been written under them.**

`agent_action_kind_policy` is now the single source both read. An unknown kind is refused **and
named**, by both languages, and reported by `fn_founder_queue`. The three pending orphans were
classified one at a time:

- **`coverage_gap` → auto.** An RFQ matched zero suppliers; what to do about it is a written
  determination and it is `ops_director`'s. **Proven: item 2701 settled on production with a
  5,279-character determination** — a kind that had no route at all four hours earlier.
- **`backup_alert` → founder.** Nobody should be able to mark a missed backup settled by writing an
  essay about it.
- **`simulation_apply` → founder.** Applying a simulated change to the live company is a change, not
  a determination.

## 2 — 27 decisions have been waiting on you. The oldest is 35 days old.

`fn_wa_context` handed you `health.actions_pending: 47` — one number, which reads as "the company is
busy" and is in fact mostly the machine's own work in flight. **The part that is yours was 27 rows
the machine is forbidden to touch**, and the oldest — a `legal_flag`, "Core legal documents missing"
— was raised on **9 July**. Nothing anywhere showed them to you. Not the dashboard, not an email,
not the command channel. They were correctly refused by `action_worker` and then correctly forgotten
by everything else, which is the most expensive kind of correct.

`fn_founder_queue()` separates the two populations, ages every item in days, and reports any kind
nobody has classified. `fn_wa_context` now carries it as **`your_decision_queue`**, so asking the
channel what needs you answers it. Verified on production for your number: 27 waiting, oldest 35
days, 0 unrouted kinds.

The five oldest, all 35 days: `prompt_approval` "Approve improved prompt: quote_review.system (v2)";
`legal_flag` ×4 — core legal documents missing, suppliers have not accepted current terms, customers
have not accepted current terms, regulatory change may affect your terms.

## 3 — The licence arrived and nothing read it

`wa_inbound` has read `Body` since the day it was written and **never once looked at `MediaUrl0`**.
Worse, a WhatsApp attachment usually arrives with an empty `Body`, and `if (!Body || !From) return`
dropped it before anything else ran. A supplier doing exactly what the invitation asks got a
courteous reply about how QuotesDone works, and the document went nowhere — not to storage, not to
`license_extract`, not onto the lead, not even into `doc_reviews`, so nothing recorded that it had
arrived.

The identical journey **by email** has worked for weeks, so this is that path reused rather than a
second one: same bucket, same sanitiser, same `license_extract`, same columns, same audit row.

**Proven end to end on staging through the deployed function** against a `ZZ DEMO` fixture: PDF in →
sanitised → stored at `inbound/3370/` → read → lead updated with licence no **9900771**, Dubai DET,
expiry **2028-03-14**, city, TRN **100299887700003**, `doc_extracted_at`; `doc_reviews` row filed
with confidence `high` and `auto_applied` true; reply *"Got it — your trade licence is on file and I
have updated your record."*

**And the guard that matters, proven separately:** a valid PDF with no readable licence on it left
`trade_license_no`, authority, expiry and TRN **unchanged** and replied *"stored, but the details
could not be read confidently"*. A blurry photo cannot wipe a supplier's real licence data.

**The host is pinned.** `MediaUrl0` arrives inside the request body, so fetching whatever URL it
names is a server-side request forgery primitive. Only `api.twilio.com` is fetched; a `data:` URL is
accepted only from an authenticated internal caller (`ops.wa_replay`), which is how the leg above
was exercised — **Twilio has never received a media message, 0 of the last 100.** Probed:
`MediaUrl0` pointing at `169.254.169.254` was refused and never fetched.

## 4 — A report now arrives as a document

Every piece existed and none were wired. `pdf_native` renders a branded, letterheaded PDF from an
HTML fragment and returns a **seven-day signed URL** — exactly the shape Twilio's `MediaUrl` wants,
because Twilio fetches it itself and unauthenticated. `sendWa` had never passed `MediaUrl`. Meanwhile
the channel truncated `agent_brain`'s two-to-four-thousand-character answers at 1,200 without saying
so.

**A keyword, not a classifier, deliberately.** A classifier would be a second model call on every
message you send AND is the exact shape `ai_gateway`'s semantic cache burns. "Did he use the word
report" costs nothing and has a correct answer, and when it is wrong the failure is a PDF you did
not want rather than a wrong answer.

Proven on staging through the deployed function: *"send me a full report on the supplier pipeline
and what is waiting on me"* → 2,223-character answer, a **102,965-byte branded PDF**, and a
933-character caption. 900 and not 1,200 because WhatsApp caps a **media** caption at 1,024 and
silently refuses above it — which would have turned "here is your report" into no report at all. The
full character count is kept in `wa_messages.meta` so a trimmed caption is never the only copy.

`sign`/`stamp` are off: this is an internal management report, not a document issued to a third
party, and a signature block on it would assert something untrue.

## 5 — A supplier can now change something, not just ask

`fn_supplier_apply_change` + `fn_supplier_changeable()`, the same shape your settings registry got,
with one difference that matters: **the scoping is not the model's job.** The function resolves the
supplier from the phone number in SQL and decides everything — which quotation, committed or not,
whether a customer has already paid to reveal them, whether the move is a fat-fingered zero. The
model's entire job is turning a sentence into a number, so the worst a misclassification can do is
produce a refusal.

Every branch probed on staging inside an aborted transaction:

| branch | result |
|---|---|
| applied | 690,100 → 828,120, the row actually changed, 1 audit row |
| idempotent | "already AED 828,120. Nothing to change." |
| fat finger | 9× refused — "more than half up or down … please set it in the portal" |
| after reveal | refused — "the customer has already paid to reveal you on one, so the price they paid to see stands" |
| wrong field | refused, with the list of what CAN be changed |
| no account | refused |
| ambiguous | "You have 5 open quotations, so I will not guess which one you mean", each listed with category, emirate and current amount |

Then end to end through the deployed webhook: *"please change my quotation price to 512000 AED"*
from a supplier with three open quotations came back with the three, priced, and a refusal to guess.
**No false positive:** *"how many inquiries have I missed and is my profile approved?"* from the same
audience fell through to the chat path and was answered from their own record.

`channel_directive`, not `founder_directive` — a supplier's price change recorded in a table called
`founder_directive` would be the defect this session keeps finding: a record whose name says
something other than what it holds. Refusals are stored beside applications, because a refused price
change is the record that the guard fired.

## 6 — Your daily brief had the same defect, and my first fix for it had it too

The email you actually read every morning said:

> `- Approvals waiting: 44 — 38 agent action(s) plus 6 supplier KYC`

`v_pend` counts every `agent_actions` row in five open statuses. **DECISIONS NEEDED — the one
section whose entire job is to list what you must decide — never mentioned agent_actions at all.**
So the queue built for exactly that purpose has never appeared in the list of things to decide, and
the number that did appear was the machine's work and yours added together, which is why ignoring
it was the correct response.

It now reads:

```
NEEDS YOU TODAY
- Waiting on YOU: 27 item(s) no agent may settle (oldest 35d) plus 6 supplier KYC — these are yours
- The machine is working on: 12 item(s) it will settle itself within the hour
- NOT MOVING: 39 item(s) sit in needs_review / proposed / open. The worker only selects
  status=pending, so nothing is draining these. They are not yours to decide and they are not
  being done either.

DECISIONS NEEDED
1. Approve/deny 6 supplier KYC application(s)
2. Settle 27 item(s) no agent is allowed to decide — the oldest has been waiting 35 day(s)
     · prompt_approval from ai_architect — Approve improved prompt: quote_review.system (v2) (35d)
     · legal_flag from legal — Core legal documents missing (35d)
     ...
```

**The third line is there because my first version of this fix was wrong.** I split 38 into "27
yours / 51 the machine's" and wrote *"51 item(s) it settles itself; no action needed"*. The
arithmetic was right and the claim was false for 39 of them: `fn_agent_action_work_sweep` selects
`status = 'pending'` and nothing else, and 39 auto-policy rows sit in `needs_review` — 31 handoffs
(oldest 3 days), 7 `strategy_rec`, 1 `report_task`. `fn_action_queue_sweep` runs hourly and
succeeds, but it only supersedes duplicates and auto-resolves stale incidents; it has decided
nothing since 10:35. I would have printed a fresh instance of the exact defect in your inbox every
morning, with more authority than the number it replaced. Caught by checking the claim instead of
the arithmetic, before it shipped.

**I did not make the worker drain them.** Something put those rows in a status literally named
`needs_review`, and emptying a queue on the grounds that nobody is emptying it is the mass-settling
the standing rules forbid. Who sets that status and what it means is a real open question — the
brief now says so out loud rather than absorbing 39 rows into a neighbouring number.

Both patches are applied by reading the definition back from the catalogue and replacing exact
anchor strings, each asserted to appear exactly once first. `fn_founder_brief` is ~200 lines that
compose your email; retyping it to change four lines is how a transcription error reaches your
inbox. Both projects verified byte-identical afterwards: `md5 25c6b29f6053454adab6de24725059ff`.

## 7 — A failed attempt was a life sentence, and eight of the ten were my predecessor's timeout

Applying the lens to my own fix: **has the retry path ever run?** It does not exist.
`fn_agent_action_work_sweep` skips any `agent_action` that already has an `action_execution` row —
any row, at any status — and the comment explains why: `idempotency_key` is UNIQUE, so re-sweeping
a previously failed item died on a 23505 during the first drain. The reasoning was sound and the
consequence was not noticed: **one failure is permanent.** The item stays `pending` for ever, the
sweep never looks at it again, and nothing anywhere says so.

Measured on production: **10 auto-policy rows pending and blocked by a failed attempt**, with
nothing live or succeeded beside them. **Eight of the ten failed for our own reason** — the
70-second timeout in §1b. We hung up on eight employees mid-sentence, recorded "the model returned
nothing", and made that verdict final.

The key now carries the attempt (`agent_action:<id>` then `agent_action:<id>#2`), two attempts and
no more so a genuinely unsettleable item stops rather than looping on the bill, and
`exhausted_two_attempts` is returned as its own number so *"we have stopped trying"* is never
counted as *"we are working on it"*.

Probed in an aborted transaction: run 1 queued exactly those 10 with `#2` keys — ids 2326, 2763,
2773, 2777, 2778, 2781, 2812, 2814, 2818, 2819, precisely the ones that failed on 10–12 Aug — and
run 2 queued 0. Then run for real: **10 queued**, `eligible_remaining 0`.

**Result: 9 of the 10 settled.** The tenth failed again at `latency_ms 107,070` — 107 seconds
against the new 105-second ceiling. It is a genuinely long item, not a regression, and it is now on
its second failure, so the sweep will stop offering it and `exhausted_two_attempts` will count it
once the collector marks the row. That is the design working: two attempts, then say so, rather
than retry for ever on the bill or fail silently. I did not raise the timeout again to chase it —
the executor's own ceiling is 120s, so there are only fifteen seconds left to give, and an item
that needs more than that needs looking at rather than waiting for.

## 8 — I watched the invite ramp, as asked. It goes silent exactly when it matters.

Measured on production at 00:10 UTC: `invite_enabled true`, `invite_daily_cap 10`,
`invite_max_bounce_rate 0.05`, and **7-day sends 29, bounces 3 — a rate of 10.3%, twice the pause
threshold.** The last `invite_ramp` run was 08:45 on 12 Aug and it recorded `PAUSED: invite_enabled
is false`, because you turned invites on later that evening. The next run is 08:45 today.

Here is what it would have done. `v_sent7` (29) ≥ 20 and `v_rate` (0.103) ≥ 0.05, so it takes the
throttle branch: `v_new := greatest(10, floor(10 × 0.5)) = 10`. Then:

```
if v_new <> v_cur then          <- 10 <> 10 is FALSE
  update app_secrets ...
  insert into agent_runs ...    <- the only record this function writes
  if v_new < v_cur then
    insert into founder_alerts  <- the only warning it raises
```

**Both the record and the warning live inside a condition that cannot be true once the cap is at
its floor.** A list bouncing at twice the pause threshold produces no `agent_runs` row and no alert
at all, and the cron reports success. The louder the problem, the quieter the instrument — because
loudness was gated on the cap still having room to fall.

That is backwards. *"I would throttle you but you are already as slow as I can make you"* is more
serious than a throttle, not less: it is the ramp saying it has run out of ways to protect the
sending domain short of stopping.

Fixed, narrowly: the `agent_runs` row is written on **every** run (a daily instrument that files a
report only on days it changed something cannot answer "is this healthy", which is the only
question anyone asks it), the run is recorded with status `error` in that state so the existing
failure watchers see it, and a `crit` founder alert fires for the case that used to be silent.
Also corrected: the throttle alert asserted *"Hard auto-pause still triggers at 8%"* — the value
became 0.05 on 12 Aug and the string did not. It now reads the live number out of `app_secrets`.

Probed on production, rolled back: `runs_written 1`, `status error`, `alerts 1`, and the text
*"THROTTLE WANTED BUT ALREADY AT THE FLOOR: 7d bounce 10.3% (3/29) >= 5% … Hard auto-pause triggers
at 5.0% or 5 hard bounces in the window, and 3 have been recorded."*

**This is a judgement for you, not for me.** The list is bouncing at 10.3% and the hard pause needs
5 hard bounces where there are 3. I have not paused it and I have not re-verified the list — that
is a commercial call about your sending domain. From 08:45 today the ramp will say so every
morning instead of saying nothing.

## 9 — s36: one live writer was left, and the gate is arithmetic, not effort

`s36-recommendation-seven-fields` requires seven fields non-null on **every** `agent_actions` row in
a **rolling 30-day window** that carries a recommendation. Measured across the 1,309 rows in that
window:

| field | missing |
|---|---|
| evidence, risk, confidence | **0** |
| assumptions, expected_impact, cost | **1,307** |
| alternatives | **1,208** |

Read the writer, not the age of the row, and the list of "kinds still missing s36" shrinks to one.
`supplier_risk_complaints` wrote 22 rows without the columns up to 21:20 and **both** rows since
22:20 carry all three — its helper shipped last night and has been correct ever since, so the brief
listing it as outstanding is stale, exactly as the previous handover warned. Every other kind that
has written since the helpers shipped is compliant too.

**One live writer was still producing rows without them, and it is the largest in the table:**
`agent_brain`'s handoff insert — 191 rows in 30 days, setting none of the four. The four fields now
live in the `@@ACTIONS@@` contract so the employee states its own terms, and an omitted key is
stored as `NULL`: a handoff that did not say what it assumed is recorded as not having said it.
Boilerplate would satisfy the scorer and tell the next reader nothing, which is the failure this
column set exists to prevent.

Proven on staging through the deployed function. A handoff to `legal` came back with:

- **assumptions** — *"The T&C change is already finalised and published somewhere suppliers can
  access it — I have not verified this"*, and *"No supplier has been individually notified of the
  change yet, based on the fact that zero have re-accepted"*
- **alternatives** — *"Could have routed to onboarding since they own the supplier registration flow
  mechanically, but the legal exposure judgment is Legal's call, not Onboarding's"*
- **impact** — *"100% of active suppliers will have accepted the current T&C version, closing the
  enforceability gap"*
- **cost** — *"Legal Counsel's time for exposure review and flow design; likely a comms/tooling ask
  onto CTO or onboarding"*

Real terms. The first assumption volunteers that it has not been verified, which is the point.

**The gate still cannot pass this month and that is arithmetic, not a shortfall.** A rolling 30-day
window over every historical row cannot flip until the last non-compliant row ages out — **mid
September at the earliest**, even if every writer were perfect from tonight. Do not read a NOT MET
here in August as a writer still being broken; check the newest rows instead.

*(CI note: `typecheck the edge functions` failed once on this branch with `Failed caching npm
package '@mediapipe/tasks-vision' — error reading a body from connection`. Infrastructure, not
code: `deno check` passed locally and `deploy changed functions` passed on the same commit. Re-ran,
green.)*

---

## Sweep

- **Row #3: 128/152 (84%)** on production, scorer run to completion twice — 127/152 mid-session and
  **128/152** at the end. `s33-replay-six-tracks` is no longer in the NOT MET list where it was at
  the start; the three at the tail are now s32, s34, s36. **I have not measured what flipped s33**
  and am not claiming my changes did — only that the number moved and the name left the list.
- **Portal gates 23/23 on BOTH projects.**
- **`project_parity.mjs` → BOTH PROJECTS IN SYNC.** Both new tables carry RLS on both projects
  (`table WITHOUT rls: prod 0, staging 0`) because the DDL declares it — the event-trigger trap was
  avoided rather than caught.
- **Pack scorecard, both projects: INGESTED 100% across 27 of 37 · IN USE 37/37.** RETRIEVABLE
  production **62.1%** (was 60.7), staging **51.3%** (was 50.3) — the embedding backfill is moving.
- `control_mode_sweep_5min`: 8 failures in the window, **all before 21:15**, then **28 consecutive
  successes** to 23:35. The previous session's fix holds.
- **Zero `agent_runs` failures in the two hours before hand-over.**
- GitHub Actions green; Vercel green.

**A correction to the brief.** It says six pack artefacts are unscorable. Measured today on both
projects, with the packs directory and with the nested pack directory, it is **ten**: the whole
86_CATEGORIES routing set (4), the whole AI_AUTONOMY_ROUTING pack (5), and one in
COMPANY_OPERATIONS. All ten probe **IN USE** against the database, so they are ingested and read —
only the disk-side comparison is missing. I did not reproduce 31/37 with either path and I do not
know why the earlier run reported it; I am reporting what measured.

## What is still open, honestly

1. **Drawing redaction is still 4 of 6 pages** (§4 of the previous handover). I did not touch it.
   The previous session measured that a blanket right-22% / bottom-12% mask changed nothing (4/6
   with and without), so the obvious next move is already known not to work, and the repro loop is
   ~65s and several vision calls per run. It needs a session that can afford to iterate on it, not
   the tail of this one. `create_inquiry` still fail-closes on a partial set, which is correct.
2. **`s36-recommendation-seven-fields` is still NOT MET** and cannot flip before mid-September — see
   §9. The last live non-compliant writer is fixed; what remains is the rolling window aging out.
3. **7 of the 22 unread tables remain** — unchanged from the previous handover.
4. **The three missing pack zips** are still file recovery, and the number is 10 artefacts, not 6.
5. **39 `agent_actions` sit in `needs_review` and nothing drains them** (§6). Deliberately left, and
   I found the writer before stopping: **`trg_action_gate`**, a BEFORE trigger on `agent_actions`
   that maps a row's kind onto an RBAC action, asks `fn_should_escalate`, and holds it for review
   when the authority check blocks it. So `needs_review` is not neglect — **it is a security
   decision**, and draining it would have been overriding an authority gate, not tidying a queue.
   That settles what to do (nothing, for now) and sharpens the real question: **28 of the 39 are
   plain handoffs from `docs` (Document Controller) to `it`**, and it is not obvious why a
   documentation handoff needs an authority escalation at all. Either the gate's kind→action
   mapping is catching `handoff` too widely, or those rows genuinely need someone — and nobody has
   ever been told either way. Start at `trg_action_gate`'s `action := case …` mapping and at
   `fn_should_escalate`. The brief now reports the count every morning so it cannot go quiet again.

## The one thing only you can do

Unchanged, and it is the same one: **finish phone verification at `/en/me`** — answer the call on
the office line, or type `+971 50 931 9355` and take the SMS. Then the terms checkbox, and intake
`18e2c133-f728-464a-b5f1-43d1f9dc3c1e` reaches lead 30466 MERIDIAN MEP at score 5.0. Still 0
inquiries, and nothing was fabricated to change that.

The 27 items in your decision queue are now visible to the command channel; ask it what is waiting
on you and it will list them with their ages.
