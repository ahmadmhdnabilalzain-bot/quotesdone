-- THE AUTOSWITCH READ OUR OWN TIMEOUTS AS MODEL FAILURE AND BOUGHT A SLOWER MODEL.
--
-- MEASURED ON PRODUCTION, 14 Aug 2026. fn_model_autoswitch() fired at 04:35 and left its own
-- org_task saying exactly what it did:
--
--   "Model auto-switched for chief_of_staff_decision.
--    Was: anthropic/claude-sonnet-5 at 75.4% success over 65 runs. Now: anthropic/claude-opus-4.8"
--
-- The 24.6% that failed, all 65 runs over 14 days, split by ok:
--
--   ok=true   49 calls   9,329-43,732 ms   avg 6,986 prompt / 1,597 output tokens
--   ok=false  16 calls  27,036-55,052 ms   prompt_tokens 0 and output_tokens 0, EVERY ONE
--
-- Zero tokens in BOTH directions on all sixteen. The model never produced anything, so it cannot
-- have produced anything wrong. And the minimum, 27,036 ms, is ai_gateway's wall to the
-- millisecond: dept_plan set no timeoutMs, took makeLlm's 25s default, llm.ts declares
-- dTo + 5000 = 30,000, and the gateway sets its wall to declared - 3000 = 27,000. Those sixteen
-- rows are OUR OWN abort, recorded as the model's failure.
--
-- SO THE LOOP PAID FOR A TIMEOUT. It promoted the class to the next dearer approved model —
-- opus-4.8, roughly 2.3x per call measured on dept_plan (AED 0.188 against 0.082) — and opus is
-- SLOWER, so it meets the same wall at least as often. The loop would then find opus failing too
-- and, finding nothing dearer, stop; leaving the company permanently on its most expensive model
-- for a class that was never failing on quality. A cost-increasing loop driven by the wrong signal.
--
-- TWO CHANGES, AND THE ORDER MATTERS.
--
-- 1. THE SIGNAL. Only calls that actually reached the model may judge it. A row with no prompt
--    tokens and no output tokens never got there — that is an infrastructure fault and belongs to
--    latency, not to model selection. This is the same lesson already recorded for LLM error
--    strings: check latency and tokens before believing any failure text.
--
--    Deliberately NOT silent: the excluded rows are counted and reported in the founder_alerts
--    row, so "this class is timing out" surfaces as itself rather than as a model downgrade. An
--    exclusion nobody can see would just be a quieter version of the same defect.
--
-- 2. THE PROMOTION IT ALREADY MADE. Reverted to sonnet-5 primary with opus-4.8 as fallback, which
--    is what staging still carries and what every other large-tier row in this table uses. It is
--    not a blind undo: the 49 calls that DID reach sonnet-5 succeeded, and the failing sixteen are
--    now understood. Opus stays as the fallback, so a genuinely hard arbitration still escalates.
--
-- The caller's timeout is fixed in the same change — supabase/functions/dept_plan/index.ts goes
-- from the 25s default to 60s, above the 43.7s worst observed success. Fixing the signal without
-- fixing the wall would leave the calls still failing, just no longer mispriced.

do $mig$
declare src text; before text;
  a_where constant text := '      and o.model_used is not null';
begin
  src := pg_get_functiondef('public.fn_model_autoswitch()'::regprocedure);

  before := src;
  src := replace(src, a_where, a_where || E'\n'
    || '      -- ONLY CALLS THAT REACHED THE MODEL MAY JUDGE IT (14 Aug 2026). A row with no prompt' || E'\n'
    || '      -- tokens and no output tokens never got there: it is our own client/gateway abort and' || E'\n'
    || '      -- belongs to latency, not to model selection. Sixteen such rows scored' || E'\n'
    || '      -- chief_of_staff_decision at 75.4%% and bought opus-4.8 at ~2.3x — a slower model, to' || E'\n'
    || '      -- answer a timeout. See scripts/sql/the_autoswitch_repriced_our_own_timeouts.sql.' || E'\n'
    || '      and (coalesce(o.prompt_tokens,0) > 0 or coalesce(o.output_tokens,0) > 0)');
  if src = before then raise exception 'anchor (model_used filter) not found in fn_model_autoswitch — refusing to apply a partial patch'; end if;

  execute src;
end $mig$;

-- The promotion this loop already made, on a signal that was not real.
update model_policy
   set model_primary  = 'anthropic/claude-sonnet-5',
       model_fallback = 'anthropic/claude-opus-4.8'
 where task_class = 'chief_of_staff_decision'
   and model_primary = 'anthropic/claude-opus-4.8';
