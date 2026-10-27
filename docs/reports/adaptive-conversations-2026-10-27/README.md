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

## Results

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
| `live_seat_conversations_3de61aa6.json`, `judged_3de61aa6.json`, `.scored.json` | final run, the same 10 scenarios |
| `live_seat_conversations_ecb6b6b2.json`, `judged_ecb6b6b2.json`, `.scored.json` | final run, 12 more scenarios |
| `live_seat_conversations_143372b1.json`, `judged_143372b1.json`, `.scored.json` | interim run (first filter, before the summary and shape fixes) |
| `live_seat_conversations_991bab87.json` | spot check of 9499820ae (not scored as part of the 22) |
