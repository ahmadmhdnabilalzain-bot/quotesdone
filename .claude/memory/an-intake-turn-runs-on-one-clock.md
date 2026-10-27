---
name: an-intake-turn-runs-on-one-clock
description: "27 Oct 2026: customer intake interview turns took 72-130 s (p95 98.5 s on production) against a 30 s portal wait, because think()'s exact-spec reading ran a planner and serial answer passes after the interview call. An intake turn now runs on ONE 24 s clock; a slow model step is started alongside, not after, and is never the reason a spec gets filled."
metadata:
  type: feedback
---

**What happened** (sales_engineer, 27 Oct 2026; found by PR #1370's mystery shopper, ~72 s and two runs over 90 s).
Production agent_runs `fn:inquiry_intake` over 24-27 Oct, 53 turns: p50 11.5 s, p95 98.5 s, max 130 s. The portal
waits 30 s (`CustomerPortal.tsx` `CALL_TIMEOUT_MS`), so a customer mid-interview saw an error.

**Why** (ai_cost_log fn `inquiry_intake`; clean turns 10:40, 11:15 and 11:33 UTC):

- The interview call (`inquiry_qualification_conversation`, claude-sonnet-5.5) took 5-7 s.
- On a turn the model called ready with a required spec blank, `statedSpecs` then ran the whole think() chain:
  - a plan (`routine_employee_reasoning`, gpt-6-luna-pro) of 20-34 s;
  - one or two answer passes (`customer_communication`, ~51k tokens) of 38-47 s each.
- When the model call failed, `tradeOf` ran the same chain again, even with a trade already stored (73 s at 10:28 UTC).
- The held reply had its own 40 s.
- The main fetch had no timeout, and nothing bounded the turn.

**The rule.** An intake turn has ONE clock (`inquiry_intake/turn_clock.ts`, `TURN_BUDGET_MS` 24 s from the request).
Every model step goes on it:

- The interview fetch gets `AbortSignal.timeout` and `client_timeout_ms`.
- `tradeOf`, `statedSpecs` and `heldReply` get `deadline: clock.deadline()`, through `_shared/think.ts withDeadline`.

A decision with nothing to plan gets no planner. The trade is a choice among options (`plan: { steps: [] }`). The stated
specs are a reader of the customer's own words (`readerOfTheirOwnText`): per-field verbatim evidence, and unproven
fields are dropped and asked.

**Start a slow step alongside, not after.** Even plan-free, the reader's one pass is 13-17 s on luna-pro (measured, run
57a34ffb).

- On claude-sonnet-5.5 it was 9-13 s, but kept 1-2 proven fields where luna-pro kept up to 4. Moving the class was the
  wrong lever.
- It is started alongside the interview call, over the trade's required specs the row lacks, and applied only where it
  was before.

**A clock can only make a turn ASK, never let a spec through.** A step that does not finish fills nothing, and the
canonical gate (`absent` → needs_info) is untouched.

**Other things the measurement found:**

- The ready turn's supplier count re-downloaded ~1,047 service rows with two vectors each: 10.7-10.9 s. It is now read
  once per warm worker (5 min) and fetched while the model runs.
- Ten sequential opening and per-trade reads cost ~8-12 s from a laptop. Run together, they take 1.0-2.3 s.

**Measured** (same harness, `scripts/e2e/intake_turn_latency.mjs`, base vs fix served locally against production):
before p50 22.2 s / p95 113.5 s, 3 of 15 turns over 30 s. After: see `docs/reports/intake-turn-latency-2026-10-27/`.

**The portal** never shows an error for a turn it stopped waiting for. It shows "still working" after 12 s, then
Try again with the same `turn_id`. The server never records the message twice, and a turn that landed is answered from
the row (`storedReply`).

**How to apply:**

- Before adding a model step to a customer turn, add its worst case to the clock. If it is serial, ask whether it can
  start alongside.
- Read a turn's `agent_runs` `counts.laps` (read, prompt, model, exact_spec, held_reply, ready_reads, saved) before
  guessing where time goes.
- Our own harness gets the laps back as `timing`.

Related: PR #1640's note on the portal chat turn (one streamed call on a clock), [[exact-specs-or-the-quote-is-held]],
[[an-edge-function-has-a-cpu-cap-a-deadline-does-not-bound]].
