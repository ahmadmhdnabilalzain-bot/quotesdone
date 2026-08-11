-- =================================================================================================
-- PROVIDER-SIDE PROMPT CACHING OFF. IT IS NOT MARGINAL, IT IS LOSING MONEY.
--
-- ai_gateway already carries the switch and the arithmetic, in its own comment:
--     "below a 22% same-prefix hit rate the 1.25x write premium costs more than the 10x read
--      discount saves."
-- so this is a policy row and not a deploy, exactly as that design intended.
--
-- MEASURED on production over the 7 days to 2026-08-11, 1,642 calls:
--     cache_write_tokens   85,342
--     cached_in_tokens      9,851
--     read/write ratio     0.1154   against a 0.22 break-even
--
-- Every 1,000 tokens written costs 1.25x to store and returns 115 tokens at a 10x discount. The
-- write premium is being paid in full and roughly half the break-even is coming back.
--
-- WHY THE PREVIOUS READING WAS DIFFERENT. A 10-hour window on 11 Aug measured 0.216 and was
-- recorded as "roughly break-even". Over the full 7 days it is 0.1154 - a short window sampled
-- shortly after a burst of similar prompts reads high, because the writes that paid for those
-- reads fall outside it. The longer window is the honest one.
--
-- THIS IS NOT THE END OF THE MATTER. Prompt caching pays when the prefix is byte-stable, and the
-- deeper fix is to make it so - sys_stable exists for exactly that and most callers do not pass it.
-- Turning the switch off stops the bleed today without pretending the mechanism is worthless.
-- Re-enable by setting this row back to true once same-prefix hits are above 22%, and re-measure
-- with the query at the bottom of this file rather than by eye over a few hours.
-- =================================================================================================

insert into public.decision_policy (key, value)
values ('prompt_cache_enabled', 'false'::jsonb)
on conflict (key) do update set value = excluded.value;

-- The re-measurement query. Run this, not a spot check, before switching it back on.
--
--   select sum(cache_write_tokens) w, sum(cached_in_tokens) r,
--          round(sum(cached_in_tokens)::numeric / nullif(sum(cache_write_tokens),0), 4) ratio
--     from ai_cost_log where occurred_at > now() - interval '7 days';
--
-- Above 0.22 it pays. Below, it does not.
