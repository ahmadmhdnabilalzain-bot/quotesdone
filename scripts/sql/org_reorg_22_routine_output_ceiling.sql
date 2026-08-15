-- REORGANISING THE AGENT COMPANY - 22: the output ceiling I introduced, measured and corrected.
--
-- org_reorg_20 routed the 23 operations_specialist roles to model_policy
-- 'routine_employee_reasoning', which carries the pack's max_tokens = 1000. Gate B of the Agent
-- Runtime Connection Blueprint then ran 30 cases across every department and FAILED its truncation
-- criterion, which requires zero truncated successful outputs:
--
--   83 calls, 0 failed, AED 2.19 of an AED 11.02 (USD 3) ceiling
--   12 of them finished with finish_reason = 'length'
--
-- Measured on the 60 calls that used the routed model, google/gemini-3.5-flash:
--
--   min 46 · p50 307 · avg 444 · p90 996 · max 996 · 12 of 60 (20%) at the ceiling
--
-- p50 307 against p90 996 is the signature of a CENSORED distribution: p90 is not 996 because the
-- work needs 996, it is 996 because that is where the answer was cut off. The true shape above
-- 1000 cannot be seen from inside the limit that created it, so the honest reading is "at least 20%
-- of these answers were longer than the ceiling", not "p90 is 996".
--
-- 2000 rather than a bigger number, and rather than reverting to 8000:
--   * the uncensored medium-tier history over seven days had p95 900 and max 6,988, so 2000 clears
--     p95 with room while still refusing the long tail rather than paying for it blindly;
--   * it stays 4x below the large tier's 8000 reservation, which is what made these calls
--     affordable at all while OpenRouter refuses the large tier on credit;
--   * llm.ts already writes an 'output_truncated' auth-log row on finish_reason = length, so what
--     remains above 2000 stays VISIBLE instead of being silently accepted.
--
-- This is a regression this session introduced, found by the gate that was written to find it, and
-- corrected from the measurement rather than from a guess. The cheap-tier routing itself is not
-- reverted: 20% truncation is a reason to raise a ceiling, not a reason to pay 4x on every call.

begin;

update model_policy
   set max_tokens = 2000
 where task_class = 'routine_employee_reasoning'
   and active
   and max_tokens < 2000;

commit;
