# Customer intake interview turn latency, 27 Oct 2026

Seat: sales_engineer (the intake interview). Branch `sales_engineer/intake-turn-latency-27-oct`, built on main + #1641
(`sales_engineer/drawing-intake-asks-27-oct`, head 05b1ff4b7). The harness is `scripts/e2e/intake_turn_latency.mjs`.
The run data is in this folder: `run_*.json`, one file per run, with per-turn wall time and the server's laps.
`summary.json` aggregates them.

## The defect

PR #1370's mystery-shopper drove the intake interview through `inquiry_intake` and the portal path:

- the passing run took about 72 s;
- two runs went past 90 s.

The portal waits 30 s (`CustomerPortal.tsx` `CALL_TIMEOUT_MS`), so a customer saw an error in the middle of the
interview.

On production (agent_runs `fn:inquiry_intake`, 24-27 Oct, 53 turns), a turn took p50 11.5 s, p95 98.5 s, max 130.0 s.

## Where the time went

Source: ai_cost_log fn `inquiry_intake`. The clean single-turn cases are 27 Oct 10:40, 11:15 and 11:33 UTC.

| step | class / model | measured |
|---|---|---|
| interview call | inquiry_qualification_conversation / claude-sonnet-5.5 | 5.0-7.0 s (3-day p50 7.0 s, p95 10.0 s) |
| exact-spec reading: plan | routine_employee_reasoning / gpt-6-luna-pro | 20.0-33.8 s (p50 20.0 s, p95 29.8 s) |
| exact-spec reading: answer pass, once or twice | customer_communication / gpt-6-luna-pro, ~51k tokens | 38.3-47.4 s each (p50 25.3 s, p95 41.9 s) |
| trade reasoning, re-run when the interview call failed (10:28 UTC) | the same chain | 73.2 s turn |

Nothing bounded the turn:

- the gateway fetch had no timeout;
- think() ran without a clock;
- the held reply had its own 40 s.

Measured locally, the opening and per-trade reads were about ten sequential round trips. A ready turn then
re-downloaded every active service with both vectors (about 1,047 rows twice): 10.7-10.9 s per ready turn.

## How it was measured

Each run drives three ZZ DEMO `@example.invalid` customers in parallel, inside its own capped rehearsal window:

- **A, English.** A complete window spec, then the taps (the ready path).
- **B, English.** An HVAC take-off and four "as per the drawings" replies (the held path, with #1641's held-spec
  questions).
- **C, Arabic.** A kitchen, then the taps.

**Before** is the base code (main + #1641) and **after** is this branch. Both were served locally (`deno run`) against
production's database and its real ai_gateway. From this container every database round trip goes to Singapore, so
reads cost more here than on the edge. Before, the base code's plain turns took 17-25 s here against a 10.4 s model
p50.

## Results

| run | code | turns | p50 | p95 | max | > 25 s | > 30 s | failed |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| production, 24-27 Oct (agent_runs) | deployed | 53 | 11.5 s | 98.5 s | 130.0 s | — | — | — |
| `before1` (78f83512) | base | 15 | 22.2 s | 113.5 s | 113.5 s | 6 | 3 | 0 |
| `after1` (3533035b) | first cut, before the vocabulary fix | 14 | 14.5 s | 25.5 s | 25.5 s | 1 | 0 | 0 |
| `after2` (bd45f66b) | fix | 15 | 15.0 s | 21.4 s | 21.4 s | 0 | 0 | 0 |
| `after3` (973b0571) | fix | 15 | 14.0 s | 19.4 s | 19.4 s | 0 | 0 | 0 |
| `final` (9171bea8) | fix, 3 turns each + retry check | 9 | 15.5 s | 18.3 s | 18.3 s | 0 | 0 | 0 |
| `ruling` (e44d9f33) | fix + the founder's ruling of 27 Oct | 15 | 15.9 s | 21.8 s | 21.8 s | 0 | 0 | 0 |
| **after, all fix runs combined** | | **54** | **15.4 s** | **20.1 s** | **21.8 s** | **0** | **0** | **0** |

By kind of turn:

| run | needs_info p50 / p95 | held p50 / p95 | ready p50 / p95 |
|---|---|---|---|
| before1 | 19.1 s / 113.5 s | 27.7 s / 34.2 s | 29.8 s / 31.4 s |
| ruling | 15.2 s / 19.1 s | 20.0 s / 20.1 s | 19.5 s / 21.8 s |

Laps in the fix runs: reads 1.0-3.2 s (they were about 8-12 s), the interview call 8.5-17.8 s, the held reply 7-10 s,
and the ready reads 2.4-3.8 s (they were 10.7-10.9 s).

## The exact-spec reader, measured alone

Run 57a34ffb: 6 readings through production's gateway each way, against the plan-free reader.

| answer class | model | model time | proven fields kept |
|---|---|---|---|
| customer_communication | gpt-6-luna-pro, ~20k tokens | 13.3-17.4 s | up to 4 of 4 |
| inquiry_qualification_conversation | claude-sonnet-5.5, ~9k tokens | 8.8-13.4 s | 1-2 (the rest failed the evidence guard) |

The class stays as it was. The reading is started alongside the interview call instead of after it, so the turn costs
the longer of the two. In the fix runs these readings took 15.3 s p50 and added nothing to the turn.
`reader_probe_sonnet_class.json` is the second set.

## The retry

Run `final`:

- the last turn of conversation A was sent again with its `turn_id`;
- it came back `replayed` in 1.8 s with the same reply;
- the message is stored once;
- 0 model calls were made.

Run `ruling` repeated the check. Its counter picked up B7's exact-spec reading, which was still landing from the
previous turn (customer_communication, 17.2 s, started before the retry). The harness now waits for in-flight readings
before it counts.

## Spend and cleanup

- **Model spend:** USD 2.19 across the seven run tags (ai_cost_log by `e2e_run_tag`). That is 0.70 before, 1.39 for the
  five fix runs, and 0.10 for the reader probe.
- **Removed by teardown:**
  - ai_qa_log: 83 rows;
  - seat_judgement: 41 rows (29 from the runs and 12 from the probe);
  - the fixtures themselves, by run tag: 18 demo customers with their auth users, intakes and verifications.
- **Counted afterwards across all seven tags:** auth users 0, customers 0, inquiry_intake 0, ai_qa_log 0,
  notifications 0, email_verifications 0, open rehearsal windows 0, intake judgements 0, held questions 0.

## Caveats

- The after numbers are from the branch served locally against production, not from the edge. Reads should be faster
  on the edge. Nothing was deployed or applied.
- The turn budget is 24 s and the target is a p95 under 25 s. Under the founder's ruling, the interview call may wait up
  to 27 s and a reply-writing step always gets 15 s. So a turn whose model is unusually slow can exceed 24 s rather
  than show code text. None did in 54 turns.
