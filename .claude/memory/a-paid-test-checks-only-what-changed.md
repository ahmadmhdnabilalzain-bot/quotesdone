---
name: a-paid-test-checks-only-what-changed
description: "Founder ruling 1660, 12 Nov 2026: the paid-test cap is NOT raised; OpenRouter has cost over USD 1,000 since the start, all of it testing, with no revenue. A thing already proven is never paid for again; a paid model call is made only to check the one thing that was wrong and has changed, on the smallest input. No full re-certification, no second run 'for reproducibility'."
metadata:
  type: feedback
  modified: 2026-11-12
---

**The founder, 12 Nov 2026 (ledger 1660):** *"it seems like it's too much on the wallet... more than maybe $1,000 since we
started. And it's all just testing... If there are some stuff that are done, then we don't really need to do them over and
over again. We test what is wrong exactly, and if it's fixed or not."* He was answering a request to raise the USD 10 cap
of ruling 1608 so the registration certification could run twice. He did not raise it.

**What the cost log says (read 12 Nov 2026, `ai_cost_log.cost_usd_reported`; USD is recorded from October only):**
October USD 182; 1 to 12 November USD 147, of which USD 100 on 2 and 3 November alone (whole-system sweeps). On days with
no test (5 to 9 November) the company runs itself for USD 0.40 to 2.30 a day. The fix round of 11 to 12 November cost
about USD 10 for twenty-three merged pull requests (paid testing about USD 9.75; all model spend on those two days USD 10.40). The money goes on sweeps that re-prove everything, not on single checks.

**The rule from now on:**
1. Proven once, with its evidence kept in `docs/reports/`, is proven. It is not run again unless code it depends on changed.
2. A paid call checks ONE changed thing on the SMALLEST input: one company's reading costs about USD 0.012; a full
   certification run costs USD 0.07 to 0.20 and re-proves nine things nobody touched.
3. Free first, always: the recorded answers replayed (the sixteen hard profiles), the models-off browser run against
   production, unit tests, a stubbed page. Paid only for behaviour that only the live model can show AND that changed.
4. Quote the cost before spending ([[quote-the-cost-before-spending]]) and tag every call, so the spend can be read by tag.
5. Never ask to raise a cap in order to repeat something. "Twice, to prove it repeats" is not a reason he accepts.
6. A certification is met by accumulated evidence per journey: each journey passes once, its report is kept, and only a
   journey a change touched is run again.

**Raised by USD 1 the same evening (ledger 1667, 12 Nov 2026):** *"Fine, there's balance. You can proceed."* The session had
asked for USD 11 in place of USD 10, for the small paid checks that prove the LLM-first fixes of rulings 1663, 1664 and 1666.
The cap is USD 11, not open; everything above still holds: one changed thing, the smallest input, quoted before it is run.
