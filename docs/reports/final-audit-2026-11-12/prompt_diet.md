# Final audit, workstream `prompt_diet`: the prompt diet's paid round and the Haiku side-by-side

Seat: it_engineer (auditor). Run 11 Nov 2026 22:43 UTC to 12 Nov 00:25 UTC. Rulings 1619 and 1618.
Branch with the harness fixes, the results and the memory note: `it_engineer-prompt-diet-eval-run` (commit `0e947efe5`, pushed, no PR).

## VERDICT: GO WITH FIXES

Nothing in this workstream is in front of a supplier or a customer: every content switch is OFF, Claude Haiku 5.5 is not
registered, and I changed nothing in production except the eval's own cost rows. So it does not block the invitations.

**No content switch passed. All three stay OFF. Haiku 5.5 stays unrouted.** The one PASS (Haiku as the reviewer of short
chat drafts) is too narrow to route on by itself. The fixes are internal: the eval has to be redesigned before a second
round (it fails an unchanged prompt), and the independent reviewer on production does not answer in the time it is given.

## What was tested

| # | what | pass bar (report section 5) | measured | result |
|---|---|---|---|---|
| plan | `prompt_diet_eval.mjs plan`, offline | total at most USD 1.50 | USD 1.34 expected, exit 0 | PASS |
| sample | read-only, anonymised, refuses to write in the repo | no e-mail, phone, person or party name leaves | refusal exit 2. No real e-mail, no phone, 0 hits against 20,884 customer, supplier and lead names (14 name columns). Public text did leave: see finding L3 | PASS with a note |
| guard | window, tagged rows, guardSpend before every call | stops before the cap | USD 0.007 cap: 7 calls, USD 0.0011, stopped itself, window closed | PASS |
| P1 | `retrieval_keeps_the_top_rows_above_a_floor` (Luna Pro, the class's high effort) | 16 of 16 not worse, zero violations | 7 of 16 run. Judge with the case in view: NEW worse in 2, violations in 3. Figure check 0 of 7. Decision differs in 4 of 5 | **FAIL, stays OFF** (9 cases NOT RUN) |
| P2 | `a_trend_relevance_choice_plans_and_retrieves_nothing` (Luna Pro, model-default effort) | 16 of 16 same choice and not worse, zero violations | same choice 15 of 16; judge 11 equivalent, 2 NEW better, 1 OLD better, 2 unread | **FAIL, stays OFF** |
| P3 | `the_reviewer_reads_the_cited_sources_only` (Qwen 3.8 Flash, high effort) | verdicts agree on at least 95%, no seeded defect missed | agree on 4 of 6; seeded missed by the cut 0 | **FAIL, stays OFF** |
| P4 | Haiku 5.5 vs Sonnet 5.5, reviewer of 60 constructed drafts (medium effort) | at least 28 of 30 defects, at most 3 of 30 clean, 0 unread, within 1 of Sonnet | Haiku 30, 2, 0. Sonnet 30, 1, 0 | **PASS** (short chat drafts only) |
| P5 | Haiku 5.5 vs Sonnet 5.5, fallback of internal answers (high effort) | 3 of 3 not worse, zero violations | 6 cases. Haiku answered 6 of 6, Sonnet usable on 3 of 6. On the 4 readable pairs Haiku not worse on 3, worse on 1, violations on 2 | **FAIL, not routed** |
| control | P1 with both arms on the SAME prompt (added by me) | not a verdict | fails the pass rule in 2 of 4, decision changes in 3 of 4 | see H1 |

P2 ran before I found that the replay sent no reasoning effort (M4, item 5). It was not re-run at production's high effort:
a FAIL keeps the switch OFF either way and the budget went to P1, P3 and P5 at production's effort.

## Per switch and per model

| item | verdict | saving a week at today's volume if it were on | what the main session does |
|---|---|---|---|
| `retrieval_keeps_the_top_rows_above_a_floor` | FAIL, OFF | 6.7M prompt tokens, USD 0.67 (AED 2.5): the answer's prompt fell from 81,649 to 54,237 tokens (n 7) across 244 internal answers a week | nothing |
| `a_trend_relevance_choice_plans_and_retrieves_nothing` | FAIL, OFF | 11.0M prompt tokens, USD 0.69 to 1.07 (AED 2.5 to 3.9): 110,373 to 34,348 tokens a headline (n 16) across 145 headlines a week | nothing |
| `the_reviewer_reads_the_cited_sources_only` | FAIL, OFF | 0.06M to 0.34M tokens, USD 0.01 to 0.06: 24,633 to 12,071 tokens a review across 5 to 27 reviews a week | nothing |
| Haiku 5.5 as reviewer | PASS on short drafts | USD 0.00016 a draft against Sonnet's 0.00163. NOT measured on a think()-sized review | do not route yet |
| Haiku 5.5 as fallback | FAIL | USD 0.0043 an answer against Sonnet's 0.0653 (n 6 each). USD 0 today: no internal Sonnet fallback call this week | do not route |

The token figures are measured here. The USD figures are those tokens at list prices and production's 7-day call counts
(to 11 Nov 23:00 UTC); they are not measured on production.

**If a switch passes a later round**, the change is one row, no deploy, live within a minute. It goes in its own SQL file
with a MANIFEST line, applied with `node scripts/apply_sql.mjs <file> --apply --seat it_engineer`:

```sql
insert into public.decision_policy(key, value) values ('prompt_diet', '{"<switch name>": true}'::jsonb)
on conflict (key) do update set value = public.decision_policy.value || excluded.value, updated_at = now();
```

No `prompt_diet` row exists today (measured). Never flip a default in `_shared/prompt_diet.ts`.

**Haiku 5.5.** The registration file is corrected on the branch with the catalogue values its pending note asked for
(read 11 Nov 22:34 UTC: USD 0.10 and 0.50 as planned, cache read 0.01, cache write 0.125, context 1,000,000, vision yes).
Applying it routes nothing: `node scripts/apply_sql.mjs scripts/sql/claude_haiku_5_5_is_registered_unapproved_until_its_side_by_side_passes.sql --apply --ddl --seat it_engineer`,
then delete the pending note, append the file as the last MANIFEST line and add it to `OWNING_SQLS`. No routing file
exists and none should be written from this round.

## Findings

### H1 (HIGH). The eval cannot certify any switch: it fails an unchanged prompt.
- Evidence: `--control`, run tags `evaldietf88b23f1`, `evaldiet3dc0a601`, `evaldiet9969932e`. The same plan, the same 53 to
  56 rows, the same model and effort, asked twice: judged worse with 2 violations (experiment approval, reject then revise);
  decision reversed the other way (revise then reject); 1 violation (root cause, supply_short then instrumentation); equal
  (experiment verdict). The rule fails in 2 of 4 and the decision changes in 3 of 4.
- The cut arm did no worse: worse or in violation in 3 of 7, decision differs in 4 of 5. NEW read 15 rows where OLD read 47,
  and in those 3 pairs, as in 6 of 7, it was given every row OLD cited.
- The judge reversed its own verdict on 2 of 6 pairs it read twice (run `evaldiete61eaad4`).
- Root cause (verified): each arm is asked once at temperature 0.2 with reasoning, and the rule needs every case equal
  with zero violations.
- Smallest correct fix: keep the switches OFF. Before a second round: ask each arm three times and compare decisions, run
  the control beside every part and read the cut against it, judge by a majority of three. The `--control` flag and a
  context-aware judge are on the branch. Do not read the three FAILs as "the cut lowered quality".

### H2 (HIGH, production, internal). The independent reviewer does not answer in the time think() gives it.
- Evidence, production (`ai_cost_log`, knowledge_validation on Qwen 3.8 Flash since it became the reviewer on 10 Nov):
  7 attempts, 2 verdicts (25 and 26 s), 3 with no output at 34 to 46 s, 2 failed within 10 s; then a Sonnet review at
  USD 0.042 on 11 Nov 06:17.
- Evidence, this run: 53 review calls in production's shape, p50 53 s, p90 104 s, max 139 s; 31 over 45 s; 3 spent the
  whole 8,600-token budget reasoning and returned nothing.
- Root cause (verified in code): `think/deps.ts` gives a call `timeoutMs ?? 45_000` and the review in `think/engine.ts`
  passes none. A review that does not run leaves a high-stakes internal answer `verified: not_run`.
- Smallest correct fix: give the review call a timeout that fits its reviewer inside the replay budget, or move the
  review to a faster model after a side-by-side on think()-sized reviews. Haiku answered 24k-token prompts in 18 s here.

### M1 (MEDIUM, production, belongs to the effort workstream). At high effort the internal answer takes about a minute.
- This run: 47 answer calls on Luna Pro at the class's effort averaged 7,723 output tokens and 62 s; 35 were over 45 s.
- Production after ruling 1630 went live (about 20:00 UTC 11 Nov): 2 of 6 internal answers returned nothing at 46.7 and
  46.8 s (marketing, 22:17 and 22:47 UTC), one succeeded at 46.1 s. Six calls is a small sample.

### M2 (MEDIUM). The same internal question gets a different decision on Luna Pro.
- The control above: 3 of 4 decisions changed, and one of the two experiment-approval answers broke the rule that a test
  must be incapable of reaching a real person. The reviewer agreed with one asking and disagreed with the other in 3 of 4.
- The CEO's own judgement runs on Opus in production; this was measured on the Luna Pro route the other seats use.

### M3 (MEDIUM, not verified through ai_gateway). Sonnet 5.5, today's fallback, gave no usable answer to 3 of 6 prompts.
- Runs `evaldiet503f50ad` and `evaldiete6282405`: one answer was "See above", two replies were markdown with no JSON
  object, at high effort with `response_format: json_object`, called directly. If the gateway path behaves the same, a
  Luna Pro outage holds about half of the internal answers.

### M4 (MEDIUM, harness). Nine defects in the merged harness; do not run main's copy.
Each was measured before it was changed. All are fixed on the branch (the list heads `scripts/eval/prompt_diet/replay.ts`).
1. All 16 P1 questions were held `fixture_no_spend` with 0 model calls (proved offline), so P3 and P5 had nothing to read.
2. Every call was booked as knowledge_validation with Luna Pro as counterpart. Each author row would have been flagged
   SAME_FAMILY_REVIEW, and `no_review_class_can_route_to_its_authors_family.test.mjs` fails on any such row for 30 days.
   There were 0 such rows before and 0 after this run.
3. A cost row loses its tag once its window closes; the cap reads spend by tag.
4. No answer was kept, so nobody could read OLD against NEW.
5. The replay sent no reasoning effort; the gateway has sent the class's (high) since ruling 1630.
6. The judge returned nothing at high effort (3 of 3) and on 2 of 16 pairs at the model's default.
7. The judge was not shown the case context, the decision or the sources the answer was given.
8. One provider error failed a whole part; a thrown call ended the run unbooked.
9. Nothing measured the same prompt against itself.

Also fixed: the anonymiser replaced every ISO date with a phone number (752 of 752 replacements, none a phone); the newest
16 headlines were all search terms production judges relevant 5 times in 211, so the sample is now half headlines
production judged relevant; the in-repo refusal came after the production read.

### L1 (LOW). Two cost rows lost their tag, by my own stop.
- `ai_cost_log` ids 103034 and 103037, USD 0.0034 and 0.0049, tier `eval`, untagged. I closed two windows while a plan
  call was in flight; the harness caught it and stopped. They count as production spend until re-tagged:
  `update public.ai_cost_log set e2e_run_tag = 'evaldiet8d0e23a7' where id = 103034;` and `'evaldietecf2853f'` for 103037.

### L2 (LOW). Haiku 5.5 costs five times more from 100,000 prompt tokens.
- OpenRouter catalogue: USD 0.50 and 2.50 above that size. The registry row cannot carry it; the file's header now says so.

### L3 (LOW, a judgement call I made). Public names left the machine.
- The cases held the public home pages of two competitors (Urban Company, Renov.at), as recorded by the
  `marketing.competitor_change` duty, and public news headlines. Production sends the same text to the same provider.
- One headline named a private individual; I swapped it for another before any paid call. No customer, supplier, lead
  or staff name, e-mail or phone left. If the rule was meant to cover public text too, this breaks it.

## Where the judge and I differ

- P5, `ceo.experiment_verdict`: judge "OLD better". Both say keep; both say restart the clock; the judge lists two
  violations on each side. Sonnet: "the 90-day clock should restart from the first real quoted request". Haiku: "the
  clock should restart at customer launch; and the experiment has no owner seat, so one must be assigned". I read them as
  equivalent.
- P1, `ceo.experiment_verdict`: the judge said "NEW better", then "OLD better" on the same pair. OLD: "Keep it this
  week... follow consent rules for any customer contact". NEW: "Iterate... replace the live-buyer follow-up experiment with
  non-live validation". NEW applies the rule OLD cites and does not apply; I side with the first reading.
- P2, ids 2780 and 2735: the judge says OLD "invents exact UAE National Day holiday dates". OLD cites a retrieved row
  (`marketing_knowledge:marketing:national-day-campaign-norms`) the judge was never shown. Not established as invented.
- P1, `sales_engineer.root_cause` (first reading): the judge lists "0 verified suppliers, 145 expected, 8 Nov" as
  unsupported in NEW. Those figures are in the case the question came with, which the judge was not given.

## Not measured, and why

- P1 cases 8 to 16: stopped by hand once the rule had failed, to keep the budget for P3, P5 and the control.
- P2 and P4 at production's high effort; a control for P2 and P3: budget.
- Haiku on a think()-sized review; the Sonnet fallback through ai_gateway: no part does it.
- The CEO's Opus route: 10 of the 16 sampled P1 questions are CEO surfaces, replayed on Luna Pro.
- USD savings on production: computed from measured tokens, not observed.

## Spend and teardown

USD 1.388 against a cap of USD 1.50 (hard stop 1.45): 358 tagged calls, USD 1.3795, plus the 2 untagged rows, USD 0.0084.

| run tag | part | USD |
|---|---|---:|
| evaldietaf13d1af | guard rehearsal | 0.0011 |
| evaldietd541f387 | P4 | 0.1073 |
| evaldietb85982c3 | P2 | 0.1418 |
| evaldiet923bd932 | P1, stopped by hand (no effort sent) | 0.0328 |
| evaldiet560ed447, evaldietc20cf399 | P1, stopped by hand (judge starved) | 0.0713, 0.0756 |
| evaldietecf2853f, evaldiet8d0e23a7 | P1, the 7 cases counted | 0.1268, 0.1293 |
| evaldiete61eaad4, evaldiet847584cb | re-judge of P1 and P5 pairs | 0.0299, 0.0045 |
| evaldiet503f50ad, evaldiete6282405 | P5, two batches of 3 | 0.2069, 0.2225 |
| evaldiet7cb38ed4 | P3 | 0.0654 |
| evaldietf88b23f1, evaldiet3dc0a601, evaldiet9969932e | control | 0.0387, 0.0432, 0.0824 |

USD 0.18 of it went on three P1 starts I stopped for harness reasons.

Teardown, read back from production at 00:26 UTC: 16 rehearsal windows, all ended with `models_allowed` false; 0 spend
reservations; 0 `review_violation` rows in 30 days; 0 fixture rows in `reasoning_held_question`; no `prompt_diet` row; no
Haiku 5.5 registry row. Left behind on purpose: the 358 tagged cost rows. Left behind by accident: the 2 rows in L1.
No person was messaged; the harness has no path to one.

## Files

- Raw results: `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/prompt_diet/results/`
  (one folder per run; `cost_rows.json` is every tagged row; `teardown_and_spend.json` is the read-back).
- Cases as sent: `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/prompt_diet/cases/`
- In the repo, on the branch: `docs/reports/2026-11-11-prompt-diet.md` section 8, `docs/reports/prompt-diet-2026-11-11/`,
  `scripts/eval/prompt_diet/replay.ts`, `scripts/eval/prompt_diet_eval.mjs`, the guard test, the Haiku registration file
  and its pending note, `.claude/memory/the-prompt-diet-switches-and-where-the-tokens-go.md`.
