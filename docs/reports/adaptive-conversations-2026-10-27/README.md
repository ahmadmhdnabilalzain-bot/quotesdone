# Adaptive expert conversations in the portal chat — measured 27 Oct 2026

Seats: **customer_support** owns the conversation and the bank. **sales_engineer** answers in the portal.
Founder ledger 1200: adaptive, expert conversations, never a robotic yes/no, never "I don't know", zero tolerance for
mistakes. Ruling 1249: every job conversation happens in the portal.

Method:
- The bank is `scripts/e2e/adaptive_conversation_bank.mjs` and the harness is `scripts/e2e/live_seat_conversations.mjs`.
- The harness drives the portal's own call, `sales_engineer {action:'assist'}`, as a fresh ZZ DEMO
  `@example.invalid` customer per conversation, with the model on inside a capped rehearsal window.
- PR #1635's `sales_engineer` was served locally against production with `PORTAL_ASSIST_URL`. Nothing was deployed.
- Every transcript was scored by Claude as a strict senior UAE estimator, against each scenario's expert list, trap and
  `keeps`. No paid judge was used.
- A scenario's score is overall × 10, and only when every code gate passes. The target is ≥ 95 for every scenario.

## 27 Oct, late: code decides what is asked (the plan per trade)

**The 95 % bar is still not met: 0 of 22, and 0 of the whole 43-scenario bank. The mean fell from 83 % to 76 %.**
The three point losses the plan was built for are mostly gone. The plan also introduced flaws of its own, and two
conversations failed a code gate (scored 0). Each finding is listed below.

What changed (PR #1635, agent customer_support):
- **Plan source.** Every playbook section in `knowledge/brief/conversation/*.md` carries a "Must-haves" line.
  `sales_engineer/conversation_plan.ts` reads it from the compiled brief: 51 sections, each with location and timing.
  A slot written `id [a|b]` applies only once the customer's words name `a` or `b`.
- **State machine, per customer turn.** Code works out which slots are filled. Slots asked and then answered unsure
  or skipped become "to confirm at the site visit". So does a slot required next for two replies that is still open.
  Code then picks the single next must-have, plus one optional. When all are in, or after 6 replies, the reply is the
  summary and must ask "is this correct?". Once confirmed, the reply tells them to press New request.
- **Slot extraction.** Detectors run on normalised Arabic and English: diacritics removed, alef, ya and ta marbuta
  unified, light stems (كاميرا / الكاميرات), with or without the article. A bounded `json_extraction` call covers the
  one case code cannot decide: two slots were asked and no detector read the answer.
- **Re-asks.** A question is compared by the slot it targets, not by its words (`portal_conversation.replyFilter`).
- **Founder ruling 1339.** Every word shown is the model's. A test proves it while the model is up.
  #1640's `outage` and salvage were merged; salvage never brings back a sentence the filter dropped.

### Before and after (the same 22 scenarios, scored against the bank's rubric exactly as before)

| | before: #1635 at 1e64a9eca (3de61aa6 + ecb6b6b2) | after: 6cf746dea (26c1ea71) |
|---|---|---|
| per-turn p50 / p95 / max | 11.5 s / 25.6 s / 65.0 s | **10.1 s / 17.7 s / 51.7 s** |
| code gates pass | 22/22 | 20/22 |
| ≥ 95 % | 0/22 | **0/22** |
| mean | 83 % | **76 %** |
| stalled before the summary (counted from the transcript) | 8/22 (the judge counted 10) | **0/22** |
| timeline asked (the bank's `when` fact released) | 16/22 (the judge counted 17) | **21/22** |
| re-asks named by the judge | 4 conversations | 2 conversations |
| re-ask flags (harness, the bank's broad fact patterns) | 57 | 14 |

The rest of the bank, on the same commit (ae4f48c0, 21 scenarios):
- code gates 19/21;
- 0/21 at 95 %, mean 77 %;
- 19/21 summaries confirmed;
- timeline asked 21/21;
- per-turn p50 / p95 / max: 12.3 s / **32.0 s** / 64.3 s. That is over the 30 s budget, from two rewrite deadlocks and
  the photo turns.

Whole bank: 0/43 at 95 %, best 90 %, mean 76.5 %. Without the code gates, the judged mean is 82.3 %.

Interim run 34e94ae3 (commit 9b2f83013, before the #1640 merge and the article fix), not judged:
- 19/22 gates;
- 21/22 summaries;
- 20/22 timeline;
- 11 flags;
- p50 / p95: 11.5 s / 21.1 s.

### Why the mean fell, and what is fixed after the measured commit

The four code-gate zeros:
- **fire_alarm_office.** The seat did ask the tie-in to the building panel. The bank's must-have pattern needs "main
  panel" or "connect", so the fact was never released. This is the rubric, and the bank was not edited to pass.
- **water_tank_ar** (the rest of the bank). The capacity was asked as سعة, which the bank's size pattern does not
  know. Fixed after the measured commit: the plumbing plan's bathroom slot no longer applies to a tank.
- **smart_home_ar** (the rest of the bank). The room count was asked as عدد الغرف والأدوار, which the bank's pattern
  does not know. Fixed after the measured commit: the detector deadlock that sent a bare "تم، خلال شهر.".
- **painting_ar.** A rewrite deadlock (52 s) ended in a bare acknowledgement. Two detector gaps caused it: مساحتها and
  the wall-condition words placed on no slot.

The flaws the plan introduced:
- **"To confirm" items that do not belong to the job.** "Material, finish and colour" on a fire alarm. Fixed in
  e25b809b8: only the plan's own slots are listed.
- **A rigid label.** A doors-only kitchen job was asked the wall lengths and appliances. e25b809b8 tells the model to
  word the question for the job. **The spot check shows that this is not enough.**
- **"Empty until we move in" read as the timeline.** Fixed in e25b809b8.
- **An instruction spoken aloud** ("ما راح أكرر التصحيح"). Fixed in e25b809b8.

Every deadlock began with a seat question that the detectors placed on no slot, or on a filled one. One turn of the
ladder then cost 44-64 s. The guard (a slot required next twice becomes "to confirm") ends the loop, but only after
that one turn. **The next step:** when every question in a reply is dropped as a re-ask, skip the rewrite and move the
next slot to "to confirm".

Spot check of the final commit 4f508df60 (d7287478, 5 of the scenarios the fixes target):
- 4/5 code gates pass, where the same five scored 2/5 in the measured runs. smart_home_ar still fails on the bank's
  room-count wording.
- painting_ar is clean: no re-ask, no bare reply, and the summary carries the damp advice.
- kitchen_cabinets_en still asks a doors-only job the layout.
- The transcript file was lost to a full disk (ENOSPC), so this run is read from `assistant_logs`, not scored.

### json_extraction does not fit a portal turn
It runs on gpt-6-luna-pro in 7-13 s (8962e747). When it ran beside every turn, it held each turn 3 s and never
returned inside the bound. It is now called only for the undecided case, with up to 12 s. A faster route would need a
model_policy row, which is SQL, so it was not applied here.

### Spend and cleanup (this session)
- **Spend: AED 30.02 (USD 8.17), USD 0.17 over the USD 8 cap.** Source: `ai_cost_log`, fn `sales_engineer`, from
  13:55Z. Tagged runs 8962e747, 19a21e1c, fafbabb3, 34e94ae3, 26c1ea71, ae4f48c0 and d7287478 account for AED 26.53.
  67 untagged portal calls inside those windows, AED 3.49, are counted as this session's.
- **Fixtures.** Every run was torn down by its exact tag. The two stopped runs (19a21e1c, fafbabb3) were torn down
  with the harness's `closeRun`. Counts by tag read 0 for auth users, customers, email verifications, leads,
  inquiries, storage objects and open rehearsal windows.
- **Chat side effects.** Matched to the bank's scripted texts inside the run windows, then recounted by id:

| rows deleted | table |
|---:|---|
| 329 | `assistant_logs` |
| 329 | `sales_decision_log` |
| 329 | `support_reply_readability` |
| 210 | `sales_knowledge_gap`, with the 210 `org_tasks` they opened |

  A recount reads 0 on each. Not reverted: 25 gap rows from before the session had their `asks` counted up.

## Results (27 Oct, evening: before the plan)

| | conversations | code gates pass | ≥ 95 % | mean | turns | p50 / p95 / max per turn | no answer |
|---|---:|---:|---:|---:|---:|---|---:|
| production `sales_engineer` (runs 1b6b12b6, 5ac11cb6, 5acff4ec, a91b68b7) | 10 | 0 | 0 | 0 % | 22 | not recorded (546 / timeout) | 9 conversations lost a turn |
| #1635 head 4f6b63d07, think() road (98aa692f, 4d74ce2d, ab519dba, 4f59f1b9) | 10 | 10 after re-runs | 0 | 77 % | 57 | 63.6 s / 107.4 s / 130.0 s | 3 (HTTP 503) |
| interim: #1640 merged + first filter (143372b1) | 10 | 10 | 0 | 80 % | 49 | 11.9 s / 21.0 s / 36.7 s | 0 |
| **final, the same 10 (3de61aa6)** | 10 | **10** | **0** | **84 %** | 50 | **11.1 s / 27.8 s / 65.0 s** | **0** |
| **final, 12 more (ecb6b6b2)** | 12 | **12** | **0** | **83 %** | 53 | 12.0 s / 25.6 s / 33.6 s | **0** |
| **final, all 22** | 22 | **22** | **0** | **83 %** | 103 | **11.5 s / 25.6 s / 65.0 s** | **0** |

Notes on the latency figures:
- They are the time to the WHOLE reply: the harness asks for JSON, not the stream.
- They come from a local serve. On the edge, add at most 1.5 s for the gte-small embedding, plus the boot time.
- The 65 s turn was a fallback to gpt-6-luna-pro after a failed first call.

The final code is commit c639f66ac. One later commit, 9499820ae, changes only the clause splitter. It was spot-checked
on painting_ar and cctv_villa_ar (run 991bab87): both pass the code gates, and both still re-ask in other words
(see below).

**The 95 % bar is not met.** No scenario reached it; the best scored 90 %.

## What still costs points, in order of frequency

1. **No summary reached** (10 of 22). The conversation ends on a question about something the customer has no hidden
   fact for, so the scripted customer stalls. The read-back and the "New request" step never happen.
2. **A must-have the bank lists never asked** (timeline in 5 of 22).
3. **Re-asks the code cannot see.** These are the same ask in other words or another word form:
   - "how many rooms" asked again as "what type is your flat";
   - كاميرا / الكاميرات (camera, in two word forms);
   - a bare "Are you the tenant?".
   The deterministic filter catches the same ask with the same content words, a filled slot, and a measured object.
   It does not catch paraphrase or Arabic morphology.
4. **One lost-context slip** (ac_undersized_en: "change the old 1 ton" on a new installation).

## What the filter did (final runs: 103 turns, every drop audited in agent_runs)

- 15 sentences were dropped in 73 turns of runs f0684306 and 91fb819d. Four of them were false drops, and all four
  are fixed in c639f66ac, each with a test:
  - a decimal ("2.5 ton") ended the stream's sentence splitter;
  - a question quoting their own figure was dropped as a re-ask;
  - "handles or push-to-open" was dropped as the door type;
  - a summary's "is that correct?" was dropped (run 94311f64, stopped and torn down).
- About 1 turn in 4 is rewritten once. Most rewrites come from #1640's plain-language gate (a sentence over 28 words).
  About 6 in 73 come from this PR's shape rule (a reply that ends without a question).

## Spend and cleanup

**Spend:** AED 20.19 (USD 5.50) over 274 calls, from `ai_cost_log` by run tag. The tags are 143372b1, 94311f64,
cba6696b, f0684306, 91fb819d, 3de61aa6, ecb6b6b2 and 991bab87.

**Cleanup:** every fixture was torn down by its exact tag. Runs 94311f64 and cba6696b were stopped mid-run and torn
down with the harness's `closeRun`. A direct DB count across all 8 tags shows 0 in each of:
- auth.users
- customers
- email_verifications
- leads
- inquiries
- storage.objects
- open rehearsal windows

The turns' own side effects were removed too. Each delete was matched by the md5 of the bank's scripted texts,
created after 11:45Z:

| rows | table |
|---:|---|
| 273 | `assistant_logs` |
| 97 | `sales_knowledge_gap`, with the 97 `org_tasks` they opened |
| 269 | `sales_decision_log` |
| 273 | `support_reply_readability` (portal rows inside the runs' windows) |

A recount reads 0 on each.

**Not reverted:** gap rows that existed before this session had their `asks` counted up.

## Files

| file | what it is |
|---|---|
| `live_seat_conversations_26c1ea71.json`, `judged_26c1ea71.json`, `.scored.json` | **after**: the same 22 on 6cf746dea (the plan) |
| `live_seat_conversations_ae4f48c0.json`, `judged_ae4f48c0.json`, `.scored.json` | the rest of the bank, 21 scenarios on 6cf746dea |
| `live_seat_conversations_34e94ae3.json` | interim: the 22 on 9b2f83013 (not judged) |
| `live_seat_conversations_3de61aa6.json`, `judged_3de61aa6.json`, `.scored.json` | final run, the same 10 scenarios |
| `live_seat_conversations_ecb6b6b2.json`, `judged_ecb6b6b2.json`, `.scored.json` | final run, 12 more scenarios |
| `live_seat_conversations_143372b1.json`, `judged_143372b1.json`, `.scored.json` | interim run (first filter, before the summary and shape fixes) |
| `live_seat_conversations_991bab87.json` | spot check of 9499820ae (not scored as part of the 22) |
