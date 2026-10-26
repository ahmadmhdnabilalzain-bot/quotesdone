-- Schedule fn_capability_enrich_sweep, WITH its cron_registry row — 12 Aug 2026
--
-- Same file for both statements, for the same reason as rfq_redispatch_6h: a cron.schedule without
-- a cron_registry row makes s38-manual-always-current report an undocumented job, which dropped
-- Row #3 from 127 to 126 earlier today.
--
-- :45 to stay clear of the :15 rfq_redispatch slot and the :35 hourly sweeps. Every 6 hours against
-- a 12-hour per-supplier backoff, so each eligible supplier is asked at most once per backoff
-- window and the schedule can be tightened later without changing the retry rate.

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

insert into public.cron_registry (jobname, human_name, category, purpose)
values (
  'capability_enrich_retry_6h',
  'Retry capability enrichment for approved suppliers',
  'supply',
  'trg_enrich_capability fires only when approval_status BECOMES approved and capability_enriched_at '
  || 'is null. If that one HTTP call to enrich_capability fails, the marker stays null and '
  || 'approval_status never transitions again, so nothing retries — and an approved supplier with no '
  || 'capability record is invisible to fn_match_capability, to route_inquiry and therefore to every '
  || 'RFQ, permanently, without anything failing. This retries claimed, non-fixture suppliers every '
  || '6 hours, 10 per run, 12-hour backoff, capped at 8 attempts because enrichment costs model spend.')
on conflict (jobname) do update
   set human_name = excluded.human_name,
       category   = excluded.category,
       purpose    = excluded.purpose;
