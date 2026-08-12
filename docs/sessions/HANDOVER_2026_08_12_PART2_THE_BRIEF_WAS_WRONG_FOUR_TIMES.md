# 12 Aug 2026, part 2 — the brief's diagnosis was wrong four times, and the counts were right every time

Continues `HANDOVER_2026_08_12_A_HUMAN_WALKED_THE_REGISTRATION.md`. PRs [#253](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/253), [#254](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/254), [#255](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/255) merged. Both projects, every change verified by execution.

---

## The pattern worth carrying forward

Your standing note says brief **counts** are reliable and brief **diagnoses** have been wrong twice. Today it was four more times, and in every case the count was exactly right:

| the brief said | measured |
|---|---|
| "513 decisions a week, 33 outcomes — add 3 columns to `decision_log`" | 1,584/1,603 rows are permission checks. `decision_log` needed nothing. The defect was 17 fabricated lessons from 4 readings. |
| "`agent_brain`'s split looks for three `# LAYER` markers the cap trims away" | Two of the three **have never existed**. And fixing the strings alone would have been worse than nothing — the prefix moved every call. |
| "most executors emit nothing to extract" | `action_worker` emits 254 of 254. It uses the word `outcome`; the extractor listened for three other words. |
| "~4,000 leads match no trade — grow the taxonomy or declare them out of scope" | 514 of them were lost to **a hyphen**. The taxonomy was already right. |

---

## What shipped in part 2

**The extractor learned the word its biggest producer speaks.** `fn_action_invoke_collect` filled `org_tasks.result.deliverable` — read by ten routines — from `recommendation`/`deliverable`/`note`. `action_worker` emits `outcome` and is the largest producer in the estate: 254 succeeded invocations in 7 days, **1** of which carried any of the three names. 204 of 556 were extractable; 254 more sat one key name away. Appended `outcome`/`summary`/`result` to the chain (never reordered, so nothing correct today changes), and backfilled from bodies already stored on `action_execution.response` — **18 recovered on production**, including `org_tasks` #1309, the AI-spend escalation the previous session named as the example of work buried in a stringified body. It now carries its full decision document.

**Two executors already had the sentence and kept it to themselves.** `kb_deepen` builds *"Deepened X: +N web-researched topic(s) [...]. Coverage A/B mapped topics."*, handed it to `logRun`, and left it out of the HTTP response — the only thing the collector can read. All 70 of its succeeded invocations closed their task with a NULL deliverable. `exec_agents` returned six counters and no prose while the officer's synthesis went to `exec_reports` and stopped there. Both now return it. Verified by invoking `kb_deepen` live: the response carries *"Deepened flooring-suppliers: +2 web-researched topic(s) [Ceramic & Porcelain Tiles, Natural Stone Installation]. Coverage 2/30 mapped topics."*

**514 suppliers lost to one character.** `fn_norm_trades` matches `taxonomy_trade.aliases` with a word-boundary regex; `building_materials` has carried the alias `building materials` since the taxonomy was created; the scraper writes `building-materials`. `\m` is a word boundary and `-` is not a word character, so the two-word alias could never span it. **The decision you asked me to make: the taxonomy does not grow.** Input normalisation was the fault — hyphens, underscores, slashes and dots are now the separators they are in a slug. Measured: `in_taxonomy_vocab` **16,445 → 16,964**, `no_trade` **4,026 → 3,507**, 1,041 rows renormalised. `swimming_pool → landscaping` came free. `events`, `garments`, `catering`, `visa-pro-services` (71) are out of scope; `contractor` (146) and `general` (3,104) stay unmatched because guessing a trade is worse than admitting we don't know one.

**`kb_embed`'s priority filter finally has a caller.** Built 11 Aug for `trade`/`regulation`/`material`; neither cron ever passed it. Added a third job. From 0 → **332 of 2,090** in the first hour; overall retrievable 53.6% → **55.1%** and rising.

---

## The number you asked for on invites

You said: *"Still >8% after the cull? That is a money decision — bring me a number."*

**The cull does not touch the observed bounces.** All five are role addresses on domains with **live MX**, and all five were flagged `email_verified` by the scrape:

```
info@cbce.ae · info@clgme.com · support@oscend.com · info@smecmarine.com · info@uiscllc.com
```

| | invited | bounced | rate |
|---|---|---|---|
| role addresses | 58 | 5 | **8.6%** |
| personal | 4 | 0 | n=4 — too small to compare, and I am not claiming otherwise |

The MX sweep removed 1,566 certain future bounces across 1,402 dead domains — real value — but zero of the five observed. These are mailbox-level failures; MX is a domain-level test. `leads.email_verified` is not evidence of deliverability.

So I deprioritised role addresses rather than deleting them, which is what you asked for (5,870 of 19,835 publish no other address). Probed on production with `invite_enabled` flipped inside an aborted transaction: the next run would queue **9 invitations, all 9 to named humans**, zero `info@`. Rolled back clean.

**`invite_enabled` stays false.** 8.6% against an 0.08 brake, nothing yet predicts the culled list's rate, and the 3-day brake window is empty (0 invited in 3 days) so auto-pause would not engage until 15 had gone. The cheap next test is an SMTP `RCPT TO` probe — free, but it connects to third-party mail servers and can cost sender reputation. That is a reputation decision, so it is yours.

---

## Row #3: the residue is mostly time, not code

I examined six of the 25 MISSING in detail. Most are not waiting on engineering:

- **`s24-board-before-major-decisions`** — already fixed. `fn_decide` invokes `fn_board_review` keyed by `subject_ref`; probed live, a new decision draws **7 of 7 advisors**. It fails on one historical row (decision 42, executed 6 Aug before that shipped, with no opinion). Clears **5 Sep** when it leaves the 30-day window. Running the board on it now would date opinions after execution and make "before a major decision" a lie.
- **`explain-knowledge-used`** — already fixed. All 29 uncited decisions are dated 5–6 Aug; nothing newer. Clears **13 Aug**.
- **`s33-replay-six-tracks`** — all six tracks have rows **today**, so it flips MET tonight when `company_snapshot_daily` runs at 23:55 — because I graded 17 outcomes today, not because anything was fabricated. It is a one-day pass: the next 49 outcomes are due **19 Aug**.
- **`s32-reputation-six-dimensions`** — blocked on the same thing as `employee-learning-progress`. `learning_speed` is NULL for all 93 *deliberately* ("scoring the ratio punishes employees for learning"), `correctness` was NULL because nothing had been graded before today, and `decision quality` has no column. Filling them with defaults would be `least(100, NULL)` again.
- **`s36-recommendation-seven-fields`** — 3 of 7 fields exist as columns (`confidence`, `evidence`, `risk`, all non-null). `assumptions`, `alternatives`, `expected impact`, `cost` have no column at all, across **41 writing routines**. Adding them with defaults would satisfy the letter and defeat the spec. Real multi-session work.
- **`s29-scan-five-questions`** — demand-blocked. "Rising keywords" needs external search-term data; 0 customers, 0 inquiries, Apify paused to ~Feb 2027. Building it from internal KB retrieval and calling it market demand would be exactly the wrong-subject defect I fixed four times today.

---

## Still open

- **The 67 unclassified workflow steps** (`org_task` #1394). Ten workflow definitions — `rfq_handling`, `payment`, `refund`, `complaint`, `supplier_onboarding`, `customer_registration`, `invoice_approval`, `employee_task`, `campaign_publishing`, `supplier_suspension` — carry no `action_class` on any step. The operating model is written down as workflows nothing can execute. Classifying them fires ~1,049 queued steps at once and `refund` reaches Stripe.
- **`prompt_cache_enabled`** — split now works (81.3% cacheable, byte-stable). Re-measure a week, then decide. Predicted hit rates: 58.5% at 5-min TTL, 89.0% at 1-hour.
- **Spec #3 UI** (item 6) and **BoQ fixtures** (item 7, blocked on drawings only you can supply) — not started.
- **The mobile-verification gate** — needs an SMS to a handset you hold.
