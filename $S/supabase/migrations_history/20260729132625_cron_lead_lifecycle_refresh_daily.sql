-- WHY: the contacted -> no_response transition happens with the passage of time, not on a write,
-- so the BEFORE trigger cannot catch it. This nightly pass re-derives every drifted row using the
-- same function the trigger uses, guaranteeing lifecycle_stage cannot silently go stale.
-- 01:25 UTC = 05:25 Asia/Dubai: no other cron job occupies this minute.
select cron.schedule('lead_lifecycle_refresh_daily', '25 1 * * *', $$select public.fn_refresh_lead_lifecycle();$$);
