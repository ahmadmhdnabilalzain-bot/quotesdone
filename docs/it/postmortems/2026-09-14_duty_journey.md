# Postmortem: `duty:journey` — the nightly full journey failed

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `duty:journey:*` — 17 distinct step keys |
| Handoffs covered | **17** (all high) |
| First / last | 14 Sep 2026 14:51Z (1) ; 18 Sep 2026 04:02Z (16, one run) |
| Answering seats | accountant, sales_engineer |

## Impact
Customer-facing by subject (customer portal pages in en/ar, desktop/mobile), measured on ZZ DEMO fixtures.
16 of the 17 handoffs come from **one** nightly run on 18 Sep 04:02Z.

## Root cause
- 12 `f crawl` keys (customer en-desktop pages: Documents, Messages, Overview, Projects, Orders, Account …) and
  `no console errors`: the crawl failed across every page in one run. `IT_FAILURES_18_21_SEP_2026.md` cause 8 records
  them as transient — each closed on the next nightly run. Not re-measured beyond the ledger.
- 3 `overview data under 2.5 s` (ar-desktop, ar-mobile, en-mobile): the real front-end latency defect, same root cause
  as the smoke class (`2026-09-14_duty_smoke.md`, cause 1).
- 1 `d payment: ZZ DEMO reveal payment` (14 Sep): the harness reached Stripe's hosted checkout and did not return
  (cause 9 in the same document). **Not diagnosed** (needs the run's screenshots).

## Detection
`it_engineer.journey` duty. Worked; one broken run fanned out into 16 findings.

## Fix (found in git)
- `1bfbcf2`: the journey suite was measuring the wrong tab, starting an LLM interview, and stopping two thirds of the way through.
- `368841e` (#728): the nightly journey reports even when it runs long.
- `582f52a`: the journey presses the buttons the 21 Sep audit pressed.
- `de0199c` (#847), `4c96db8` (#957): the remaining journey findings measured and fixed by the sales_engineer.

## Action items
1. **it_engineer** — `duty:journey:run:fixture_setup_failed` is open since 25 Sep 00:16Z; diagnose with the smoke twin.
2. **sales_engineer** — the overview latency (shared with the smoke class).

## Handoff ids covered
`duty:journey` (17): 13390, 35265, 35266, 35267, 35268, 35269, 35270, 35271, 35272, 35273, 35275, 35276, 35277, 35278, 35279, 35280, 35281.
