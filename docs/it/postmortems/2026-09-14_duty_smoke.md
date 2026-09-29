# Postmortem: `duty:smoke` — the post-deploy smoke failed after a merge

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `duty:smoke:*` — 28 distinct step keys |
| Handoffs covered | **73** (all high, 0 critical) |
| First / last | 14 Sep 2026 19:15Z / 24 Sep 2026 13:31Z |
| Answering seats | ceo, sales_engineer |

## Impact
Customer-facing by subject (the smoke drives the customer and supplier portals after each deploy to `main`). The
smoke runs on ZZ DEMO fixtures, so no real customer saw a failed step; what a real customer would have seen is the
same slow or broken page.

## Timeline (key, handoffs)
- `a customer: overview data under 2.5 s` in four locales: ar-mobile 10, ar-desktop 10, en-desktop 7, en-mobile 7 (15 Sep → 24 Sep).
- `run: fixture setup failed` 6 (14 Sep → 24 Sep) — **the same key is open again** since 24 Sep 15:09Z (after merge 252f400).
- `cleanup: zero leftovers` 4, `cleanup: teardown` 3.
- `c comparison` (quotation/comparison PDF and CSV in Arabic, deep links) 10 across 8 keys, 14 Sep → 24 Sep.
- `b supplier` 11 keys, 1–2 each, almost all at 18 Sep 05:00Z after merge e8e0990 (one bad run, many steps).

## Root cause
1. **Overview latency (34 of 73).** Measured by the journey on 18 Sep: data settles in 3,031 ms; six portal reads issued
   from a React effect queue behind the client bundle (`IT_FAILURES_18_21_SEP_2026.md` cause 7). A real front-end
   defect owned by the sales_engineer.
2. **One failed run fans out into many keys.** The 18 Sep 05:00Z `b supplier` burst and the 14 Sep 20:02Z burst are each
   one run whose early step failed; every later assertion is raised as its own key.
3. **Fixture setup / teardown** (13): the harness could not create or remove its ZZ DEMO fixtures. Cause **not
   determined** here; the open finding is the place to read it.

## Detection
`it_engineer.smoke` duty, raised minutes after each deploy. Worked; the per-step fan-out overstates the number of faults.

## Fix (found in git)
- `0df19fc` (#663): the smoke can see the deploy it waits for. `670a222` / `d9af10e` (#671): smoke expectations follow the product.
- `6e5ea2b`: `the_it_engineer_holds_the_portals_to_their_latency_budget.sql` (latency budget as a duty).
- `0e34dab`: post-deploy smoke measures the model hold.
- The 2.5 s overview latency: **no front-end fix identified in git**; the class closed as "the smoke duty no longer finds it".

## Action items
1. **sales_engineer** — confirm the customer overview settles under 2.5 s in all four locales, with the measurement.
2. **it_engineer** — diagnose the open `duty:smoke:run:fixture_setup_failed` (and its twin `duty:journey:run:fixture_setup_failed`).
3. **it_engineer** — when the first step of a run fails, raise one finding for the run, not one per downstream assertion.

## Handoff ids covered
`duty:smoke` (73): 19802, 19803, 20756, 20757, 20758, 20760, 20763, 21159, 26137, 26661, 26662, 26950, 27180, 27302, 27303, 27388, 27389, 27390, 28589, 28636, 31676, 32949, 32950, 32951, 33312, 33313, 33314, 34103, 35769, 35770, 35771, 35772, 35774, 35775, 35776, 35777, 35778, 35779, 35780, 35781, 35782, 38346, 39846, 39936, 40022, 40023, 40126, 40659, 41934, 42507, 43340, 43341, 52050, 56008, 58879, 67082, 77602, 79726, 79727, 80603, 81400, 83588, 83589, 84593, 84594, 87688, 93015, 93448, 93449, 93450, 97754, 98075, 98076.
