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

---

## Sweep

- **Row #3: 127/152 (84%)** on production, scorer run to completion. Unchanged — no regression.
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
2. **`s36-recommendation-seven-fields` is still NOT MET** on the Row #3 scorer.
   `supplier_risk_complaints` (119 rows, still writing) and `improvement_question` have no helper.
3. **7 of the 22 unread tables remain** — unchanged from the previous handover.
4. **The three missing pack zips** are still file recovery, and the number is 10 artefacts, not 6.

## The one thing only you can do

Unchanged, and it is the same one: **finish phone verification at `/en/me`** — answer the call on
the office line, or type `+971 50 931 9355` and take the SMS. Then the terms checkbox, and intake
`18e2c133-f728-464a-b5f1-43d1f9dc3c1e` reaches lead 30466 MERIDIAN MEP at score 5.0. Still 0
inquiries, and nothing was fabricated to change that.

The 27 items in your decision queue are now visible to the command channel; ask it what is waiting
on you and it will list them with their ages.
