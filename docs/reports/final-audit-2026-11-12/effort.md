## Thinking effort, low against high (it_engineer): GO WITH FIXES

Suppliers: go. Customers: not before finding 1 is fixed.

Branch `it_engineer-effort-low-vs-high-replay` (60656e33b, pushed, no PR). Replay built and run. Full tables: `docs/reports/2026-11-11-history-and-effort.md` section 6.

**provenLow: nothing to flip.** `effort_policy.ts` is unchanged.
- Menu, the only sorting surface with recorded input: low chose as high on 23 of 26 (88%; bar 95%). It is also never called on its own in production.
- `problem_state`, `case_match`: not run, no recorded input.
- Deciding surfaces stay high (reading 7 of 8, needs-a-person 8 of 8).
- Status lane: low passed 8 of 8, but it is a conversation, so medium.

**Findings**
1. **BLOCKER for customers.** At high, the intake spec reader is cut by the turn clock.
   - Replay: 0 of 22 high calls finished inside 21.5 s. Low finished all, in 11 to 19 s. Medium took 29 to 46 s.
   - Production since go-live: 10 of 18 readings held (4 of 55 before). Turn p50 went from 11.0 to 17.1 s; none over 30 s.
   - The customer is asked again for a spec already stated.
   - The fix touches ruling 1630, so it is your call. Either add `onTurnClock: true` to the two intake surfaces and `return s.onTurnClock ? 'low' : 'high'` in `surfaceEffort`, or take the reading off the clock.
2. **MEDIUM.** WhatsApp reading p50 5.3 s at low, 11.9 s at high. Production p95 13.9 to 19.1 s against a 20 s clock; the held rate did not rise.
3. **MEDIUM.** Supplier document reading p95 24.7 to 41.7 s, longest 60 s, cost 2.2 times. No failures.
4. **LOW, mine.** The first smoke sent 5 calls untagged (USD 0.0097; `ai_cost_log` 102237, 102244, 102255, 102265, 102277). Fixed in the branch; the rows still carry no tag.
5. **LOW.** Two anonymiser defects in the eval, fixed and pinned in its check.

**Customer-facing over 40 s since go-live:** one WhatsApp turn of 10 (42.1 s).

**Spend:** USD 0.2201 of 0.50. Six windows, all closed. No fixture created.

**Could not do**
- `REPORT.md`: the harness refuses report files from a subagent. The full text is below.
- Widget: no traffic since go-live.
- An early environment listing printed the `SUPABASE_ACCESS_TOKEN` variable into my own tool output. It was copied nowhere.

---

## REPORT (for `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/effort/REPORT.md`)

Everything was measured on 11 Nov 2026, 22:47 to 23:43 UTC.

### What was tested

| # | What | Pass bar | Measured | Result |
|---|---|---|---|---|
| 1 | Menu (`wa_inbound.greeting_state`), low chooses as high | >= 95% | 23 of 26 recorded messages | FAIL |
| 2 | WhatsApp reading (`wa_inbound.intent_table`) | >= 95% | 7 of 8 | FAIL (decides: stays high) |
| 3 | `wa_inbound.needs_a_person` | >= 95% | 8 of 8 | PASS (decides: stays high) |
| 4 | `inquiry_intake.trade` | >= 95% | 3 of 8; high answered 3 of 8 | FAIL |
| 5 | `inquiry_intake.exact_spec` | >= 95% | 1 of 7; high answered 1 of 7 | FAIL |
| 6 | Status lane at low: every must-carry reference, no ungrounded figure, not slower | all | 8 of 8 | PASS (conversation: stays medium) |
| 7 | `wa_inbound.problem_state` | >= 95% | no recorded input | NOT RUN |
| 8 | `support.case_match` | >= 95% | 0 of 28 cases had a summary when sampled | NOT RUN |
| 9 | `marketing_social.needs_a_person` | >= 95% | shares test 3's options | NOT RUN |
| 10 | Intake readings inside the 21.5 s turn clock at high | all | replay 0 of 22; production 10 of 18 held | FAIL |
| 11 | WhatsApp reading inside its 20 s clock at high | none set | replay 7 of 8; production 27 of 29 answered, longest 22.1 s | reported |
| 12 | No customer-facing turn over 40 s since go-live | 0 | 1 WhatsApp turn of 10; intake 0 of 20 over 30 s | 1 exception |
| 13 | Spend | <= USD 0.50 | USD 0.2201 | PASS |
| 14 | Nothing sent to a person or written to production state | 0 | 0 sent; 167 writes answered by a stub; 6 of 6 windows closed | PASS, see finding 4 |
| 15 | Anonymisation read before any paid call | no identity | 2 defects found and fixed first | PASS after fixes |
| 16 | Repo checks on touched files | no new failure | `deno check` exit 0, `deno lint` clean; 52 node tests, same 13 failures as main | PASS |

The caller's wait for the model, p50 / p95 in seconds, and USD per case:

| Surface | Low | Medium | High | USD low / high |
|---|---:|---:|---:|---:|
| menu (26 cases) | 10.3 / 18.5 | 13.0 / 19.3 | 14.6 / 29.4 | 0.00060 / 0.00117 |
| WhatsApp reading | 5.3 / 9.5 | not run | 11.9 / 27.3 | 0.00108 / 0.00112 |
| needs a person | 6.7 / 11.6 | not run | 18.5 / 27.3 | 0.00071 / 0.00127 |
| intake trade | 13.2 / 15.4 | 31.9 / 37.2 | 48.0 / 48.9 | 0.00119 / 0.00271 when it answered |
| intake spec reader | 17.9 / 18.9 | 37.9 / 48.5 | 48.0 / 49.0 | 0.00199 / 0.00336 the once it answered |
| status lane | 4.7 / 5.5 | 7.4 / 10.7 | 8.2 / 11.7 | 0.00036 / 0.00061 |

### Findings

**1. BLOCKER for customers (not suppliers): the intake's readings do not finish inside the turn at high.**
- Replay, spec reader (run `qd_run:evalefff2f6e4c90`): at high 6 of 7 calls were cut at the gateway's 47 s wall and the seventh took 37.5 s. Medium took 32.9 to 46.3 s. Low answered 7 of 7 in 16.0 to 18.9 s.
- Replay, trade (runs `evalefffe3428a49`, `evaleff0db35eb5c`): at high 4 of 12 answered, in 32.8 to 45.8 s. Low answered 12 of 12 in 10.9 to 15.4 s.
- Production, `seat_judgement` surface `inquiry_intake.exact_spec`: 55 readings with 4 held in the 7 days before; 18 with 10 held since 11 Nov 11:10 UTC (for example ids 17619 to 17623 and 17627, "model_failed: no reply" at 21 to 23 s).
- Production, `ai_cost_log` `customer_communication` from `inquiry_intake`: 8 of 59 calls failed before, 20 of 28 since.
- Intake turns: p50 11.0 s over 82 turns before, 17.1 s over 20 since. The longest was 29.1 s; the portal waits 30 s.
- The traffic since go-live is the audit's own fixture customers. No real customer has been affected yet.
- Root cause, read in code and measured: `effort_policy.ts` marks both surfaces `decides`, so `surfaceEffort` returns high (`_shared/reasoned_decisions.ts` lines 83 and 104). Both run under `inquiry_intake/turn_clock.ts` (24 s less a 2.5 s reserve). At high the model writes 4,000 to 5,600 tokens where low wrote 1,200 to 2,000.
- Smallest fix: the `onTurnClock` change above plus `effort_policy.test.ts`. The reader keeps its evidence guard. Medium is not an answer; it does not fit the clock either.
- The trade choice only runs when the interview call fails. It did not run in production in either period.

**2. MEDIUM: the WhatsApp reading at high sits close to its 20 s clock.**
- Replay: 1 of 8 high calls ran over 20 s (27.3 s).
- Production, `wa_inbound.intent_table`: 125 decisions before with p50 10.2 s and 16 held; 29 since with p50 11.8 s, longest 22.1 s, 2 held.
- If a reading is cut, the fallback needs-a-person check is also high: 4 of 8 ran over 20 s in the replay.
- No fix is needed to invite. If the held rate rises, raise `CLASSIFY_MS` in `wa_inbound/classification.ts`.

**3. MEDIUM: the supplier's document reading (`supplier_trade_choice`, fn `supplier_doc_trades`).**
- 231 calls before, 34 since. p50 10.3 to 15.9 s. 3 of 34 ran over 40 s (1 of 231 before).
- USD 0.00097 to 0.00215 a call. It runs behind the portal, not inside a request.

**4. LOW (mine): the untagged smoke.**
- `_shared/e2e_run.ts` installs the tag forwarder only if `SUPABASE_URL` is set when it is first imported. The replay imported it before `connect()`, so the spend guard read USD 0.
- Fixed: imports now follow the connection, the forwarder is asserted before the window opens, and a paid call that leaves no tagged row stops the run.

**5. LOW: the eval's anonymiser.**
- "I am not sure" became "I am ZZ DEMO Person" in 8 of 83 portal messages.
- It knew no company name: 5 of the 8 WhatsApp messages, and our replies, named a real supplier's two companies. No such file was sent or committed.

**6. LOW: the standalone menu reading is unstable on a one-word pick.** "Supplier" asked 6 times per arm: low chose the supplier option once, high twice. Production reads the menu inside the readings call, which this did not test.

### Spend by run tag (`ai_cost_log`)

| Run tag | USD |
|---|---:|
| `evalefffe3428a49` (six surfaces) | 0.130681 |
| `evalefff2f6e4c90` (spec reader, three arms) | 0.045217 |
| `evaleff0db35eb5c` (trade, three arms) | 0.019009 |
| `evaleff8f08ecc31` (one menu message, five times) | 0.013779 |
| `evaleff86c475004` (smoke) | 0.001716 |
| untagged (finding 4) | 0.009720 |

### Teardown
- Six rehearsal windows opened and closed, read back at 23:42 UTC.
- Left in production: the 6 window rows, 208 tagged cost rows and the 5 untagged ones.
- I deleted the raw samples and the scrub list from my scratch folder.
- Kept in `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/effort/`: the anonymised `cases.json` and `run1` to `run4/detail.json`.
- My worktree `/tmp/claude-0/effort` (178 MB) is still there.

### Not measured
- A weekly cost for the map: 12.5 hours of test traffic is not a week.
- A judge model on the status answers: code checked references and figures, and I read the 8.
- `deno fmt`: the new file follows the repo's style and fails `deno fmt --check`, as the two existing replays do. The repo has no format config.

Skills used: the repo conduct skills `quotesdone-session` and `quotesdone-organised-like-an-auditor-will-read-it`, and the memory index. I added the lessons to `.claude/memory/history-before-every-send-cases-and-effort-by-consequence.md` in the branch.
