# Final audit before the founder's invitations: results (11-12 Nov 2026)

Seat: it_engineer (coordinator), with customer_support auditors. Founder rulings 1608 (final paid round, USD 10 cap),
1620-1622 (the bar for inviting his network), 1638-1640 (audit on his word), **1641 (results first: nothing found here is
fixed until he has seen them)**. Run on production at main `2cc9d1017` (#1949), 22:30 UTC 11 Nov to 00:40 UTC 12 Nov.
ZZ DEMO identities only; 0 messages dispatched to a real person by any run.

**Nothing in this report has been fixed.** Each workstream's full report, with evidence and row ids, is in
`docs/reports/final-audit-2026-11-12/`.

## 1. Verdict

**Not ready to invite the founder's network yet.** The registration itself is close (15 of 16 paid registrations were
flawless). What a supplier or customer meets *after* registering (WhatsApp, the request chat, quoting, the comparison)
regressed on 11 Nov, and most of that regression has one cause (section 3).

| Workstream | Verdict | Report |
|---|---|---|
| Paid supplier registration certification, 2 runs | **NOT READY**: 3 of ~250 steps failed; 1 of 12 approvals not reached in time | `registration_certification_paid.md`, `regcert_diagnosis.md` |
| Customer journey (text; drawing + BOQ; voice note) and drawing read | **NO-GO as it stands** (3 blockers) | `customer_journey.md` |
| WhatsApp, deployed handler and real model | GO WITH FIXES (1 blocker) | `whatsapp.md` |
| Thinking effort, low against high | GO WITH FIXES (1 blocker for customers) | `effort.md` |
| Prompt diet and Haiku side by side | nothing to switch on; the eval itself is unreliable | `prompt_diet.md` |
| Production health (free) | GO WITH FIXES (4 high) | `health.md` |
| Integration review of 11 Nov's ~30 merges (free) | GO WITH FIXES (1 blocker, 4 high) | `integration_review.md` |

## 2. What held (measured)

- **Money:** the reveal fee was exact on 2 of 2 journeys (AED 286.62 = 3% of 9,554; AED 3,212.97 = 3% of 107,099),
  processing fee 0, the invoice right, only the chosen supplier unlocked.
- **Identity:** 0 leaks either way on every surface read (supplier copies, inquiry PDFs, comparison, customer quote PDFs,
  WhatsApp replies; 8 of 8 redacted drawing pages by OCR with a control).
- **Drawing count:** 7 of 7 quantities exact on the 8-sheet set, twice (duct 16,432.9 m read 16,433.2 m).
- **Matching:** the live matcher matched 10 of 10 of the journeys' own suppliers.
- **Registration:** speed inside every budget on 191 of 192 timed steps; licence fields 15 of 16 whole; 12 of 12 service
  proposals sensible, 0 absurd; no error, dead end, stray Arabic or impolite wording; the expired licence flagged.
- **Real visitors:** 0 server errors in 150 UAE requests in 24 h; one real supplier registered and was verified in
  7 min 52 s on 11 Nov.
- **Platform:** SQL drift 0; verify_jwt mismatches 0; Vercel at main with 0 runtime errors; 106 cron jobs, 0 failures;
  security advisors 0 ERROR; database 3.74 of 19.3 GB; no duplicate sends since #1938; load stub off.
- **Security:** no regression found in 11 Nov's diff.

## 3. The main cause: the effort raise met unchanged time limits

Ruling 1630 (effort by consequence) went live on 11 Nov ~10:15 UTC. The implementation raised effort without re-measuring
the time limit each call runs under. High effort writes about 2 to 4 times the tokens, and the limits stayed where they
were. Measured consequences:

| Where | Limit | Before | Since / at high |
|---|---|---|---|
| Request chat: spec reading and held reply | 24 s turn clock | 3 of 37 cut (10 Nov) | 23 of 41 cut; replay at high 0 of 22 finished; the customer is re-asked what he already said |
| Request chat reply | portal gives up at 30 s | p50 11.0 s | p50 17.9 s, p95 29.1 s, max 29.9 s |
| WhatsApp reply | none stated; founder accepts 30-40 s for a hard one | p50 32 s on 10 Nov (then a region fault) | p50 29.0 s, p95 51.2 s, none under 9 s; complaints 48-72 s |
| Comparison | page waits 30 s | not measured | fresh comparison 42-74 s; the page aborted 2 of 2 |
| One-sheet drawing | gateway wall 55 s | 12 lines read (10 Nov) | 67 s and 0 lines; model call cut 4 of 5 |
| Supplier "check my quote" | portal waits 20 s | not measured | 6 of 8 over 20 s (up to 66.6 s) |
| Marketing internal judgement | ~47 s | 143 of 143 ok | 4 of 4 failed |
| Internal reviewer (Qwen) | 45 s | not measured | 2 verdicts in 7 attempts; p50 53 s |

The side-by-side also showed that **low effort is proven nowhere** (the one sorting surface agreed with high on 23 of 26,
88% against a 95% bar), so the answer is not "lower everything".

**Decision needed from the founder (it amends ruling 1630).** Recommended: effort by consequence stays, with one added
rule: *a step a person is waiting on uses the highest effort that finishes inside that wait, measured; anything that
needs more thinking moves off the live turn* (it runs beside or after the reply, and the result is used on the next
turn or sent when ready). Background work (document reading, matching, pricing, the comparison behind a progress
screen) stays high, with its limit raised to fit.

## 4. Findings that block the invitation, by who meets them

### Supplier registering (ruling 1620)
| # | Finding | Evidence | Fix (not applied) |
|---|---|---|---|
| R1 BLOCKER | Two document reads overwrite each other: the profile read saved an older copy over the finished licence read. Activities came back empty and the supplier sat at Pending. A sweep would re-read, but it runs every 30 min, so Pending lasts an estimated 10-40 min. | 1 of 16 paid registrations; edge-log timeline; reproduced offline 2 of 2 | merge per document atomically in SQL; sweep back to 10 min |
| R2 HIGH | A photo or scanned licence that takes over 10 s to read shows "our reader has not finished" and the form never looks again (the reading landed 0.45 s later). | 1 of 4 photo/scan journeys | the form re-reads after a late answer |
| R3 HIGH | A slow read's fields can land on a row that now names a newer file. | offline only | filter the late write by file path |
| R4 MEDIUM | The real supplier of 11 Nov has 2 WhatsApp notices queued 16 h (template missing) and his trades still held for the sales engineer. | notifications queue; item 382385 | add the template; clear the hold |

### Supplier quoting
| # | Finding | Evidence |
|---|---|---|
| Q1 BLOCKER | Every supplier is told "your quote needs a few more details" in the same second it is approved and sent. | 8 of 8 quotes, e-mail and WhatsApp |
| Q2 BLOCKER | The supplier's request PDF and "requested" block lose everything the customer answered ("Required by: Not stated"); the masking trigger drops the whole key because it carries Arabic labels. | 2 of 2 requests |
| Q3 HIGH | The quotation reader keeps totals and loses quantity, unit, rate and VAT amount; the customer then reads "failed our completeness check" on every quote. | 0 of 56 lines |
| Q4 HIGH | "Check my quote" outlasts the portal's wait. | 6 of 8 |

### Customer
| # | Finding | Evidence |
|---|---|---|
| C1 BLOCKER | The request chat is slow and re-asks answered questions (section 3). | 12 of 19 turns over 15 s |
| C2 BLOCKER | A voice note is refused every time on the server path: an unset daily cap reads as 0. No transcription provider is set at all, so WhatsApp voice notes are not heard either (the reply says so honestly). | 429 on the first note; 0 voice keys in app_secrets |
| C3 HIGH | The comparison page gives up at 30 s on a 42-74 s comparison. | 2 of 2 |
| C4 HIGH | A one-sheet drawing: 67 s, no quantities. | 1 of 1 |
| C5 HIGH | The duplicate guard's key ignores the quote, so a second supplier's "new quote" notice inside 10 minutes would be cancelled. | by the guard's own key 6 of 8 would be dropped; not observed live (demo rows are suppressed) |
| C6 MEDIUM | Display defects: the expert comparison labelled "rules only"; "Best value" on the quote the report rejects; the brand hider rewrites ordinary words; internal markers printed in the customer's quotation; one answer recorded against the wrong question; a gypsum firm invited to an HVAC job; no budget asked. | `customer_journey.md` M1-M9 |

### WhatsApp
| # | Finding | Evidence |
|---|---|---|
| W1 BLOCKER | No reply is fast (section 3). | 31 replies |
| W2 BLOCKER | The same holding sentence precedes every reply, and is never recorded: the database refuses the row (`requested_by` 'wa_inbound' is not a seat), so the repeat guard never sees an earlier one. | 29 of 29 text turns; 0 rows ever; `wa_inbound/holding.ts:45` |
| W3 HIGH | Cases do not work on WhatsApp (ruling 1635): the case decision is given 4 s and never took under 4.77 s. | 0 summaries, 0 promises, 17 cases for 7 people |
| W4 HIGH | "This trade is not open yet" repeats in every later reply. | 7 replies, 4 people |
| W5 MEDIUM | "Talk to a person" gives the number they are already on; a burst splits if one delivery arrives unpinned; a repeated 20+ character message is silenced after four in an hour (the founder included). | `whatsapp.md`, `integration_review.md` |

### Behind the scenes
| # | Finding | Evidence |
|---|---|---|
| H1 HIGH | The IT seat's hourly duties have not completed since 00:45 UTC 11 Nov (statement timeout at 8 s). | 62 timeouts; 798 open findings, 646 stale |
| H2 HIGH | The scheduled Claude cloud routines do nothing: they "succeed" in 28 s with no repository access (GitHub 403). Weekly readings missing 8 days. | routine transcript |
| H3 HIGH | `resilience_ping/ticks/customer_support.ts:33` imports a wrong path; complaint/incident updates are never written. | 115 failures since 10 Nov |
| H4 HIGH | Stripe: the live secret key is in production and nothing holds it back; a real customer at reveal would pay on live Stripe. All recorded activity is test or demo. Whether the live account can take charges was not measured. | key prefix class only |
| H5 MEDIUM | The founder digest is fed ~15 reports an hour by H1's stale findings (117 pending). Registration mail left 13 min late on the 15-minute outbox. Service pages make one model call per view (p50 19 s), crawlers included. | `health.md` F5-F8 |
| H6 MEDIUM | main is red on two checks (a stale assertion in `_shared/read_ceiling.test.ts:26` since #1947; one pending SQL file over 24 h). | `integration_review.md`, `health.md` |
| H7 MEDIUM | Test clean-up fails after any run that used the quotation chat: case summary versions are append-only (ruling 1634) and demo rows are not exempt. Left in production: demo cases 2221, 2235, 2236 with their profiles (1034, 1036, 1037) and 4 summary versions. | `customer_journey.md` H6 |
| H8 LOW | Credit: OpenRouter USD 25.93 at 23:00 UTC before the last USD 2.5 of this audit (floor 20); Twilio USD 18.46. An audit agent's local working log captured the container's Supabase token variable (not copied anywhere). 7 cost rows lost their run tag. | `health.md` F9, `effort.md`, `prompt_diet.md` |

## 5. Model side-by-sides

- **Low effort:** not proven on any surface. `effort_policy.ts` unchanged.
- **Prompt-diet content switches:** none passed, and a same-prompt control failed the pass rule in 2 of 4, so the eval
  cannot tell a harmful cut from noise. All three stay OFF. The saving at stake is about USD 1.4-1.8 a week.
- **Haiku 5.5 as reviewer:** passed on 60 short drafts (30 of 30 defects, 2 of 30 clean flagged; Sonnet 30 and 1). Not
  measured on full-size reviews. As fallback: failed. It stays unrouted.

## 6. Not measured

Journey 3 after the microphone; reveal notices (demo hand-offs are not filed, ruling 1199); the supplier's on-screen
request detail; the fifth quote of each journey; Arabic and phone screens on the customer journey; the portal chat
widget, e-mail triage and the supplier@ reply gate since 11 Nov's changes (0 inbound); the WhatsApp loop cap, typing
indicator and memory turns 6-10; Stripe live `charges_enabled`; the nightly export of the three new tables.

## 7. Spend and safety

USD 5.51 for the audit (`ai_cost_log` since 22:20 UTC: 5.4924 tagged over 967 calls, plus about 0.02 of eval rows that
lost their tag), about USD 5.75 of the USD 10 round. Registration 0.05, WhatsApp 1.16, effort 0.22, prompt diet 1.39,
customer journey and drawing 2.51. All rehearsal windows closed (0 open at 00:40 UTC). 0 dispatched to a real person.
Leftovers: the demo case rows in H7. Branches pushed, no PR: `it_engineer-effort-low-vs-high-replay` (the replay tool),
`it_engineer-prompt-diet-eval-run` (nine harness fixes).

## 8. How this happened

About thirty changes were merged, applied and deployed on 11 Nov, each tested alone. The free registration check was
re-run after each registration change, which is why registration is the healthiest area. Nothing re-ran the customer
journey or WhatsApp with the models on after the effort change, because that was held for this paid round. The lesson
for the release process: a change to effort, model or a time limit is not done until one paid journey per affected
surface has run after it.
