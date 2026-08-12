-- Schedule fn_rfq_redispatch_sweep, WITH its cron_registry row — 12 Aug 2026
--
-- Every cron.schedule needs a cron_registry row in the same change. Forgetting one dropped Row #3
-- from 127 to 126 on 12 Aug via s38-manual-always-current ("1 active cron job(s) are undocumented").
-- Both statements are in this one file for that reason.
--
-- Every 6 hours, offset off the busy :35 slot the hourly sweeps share. The sweep's own backoff is
-- also 6 hours, so each eligible RFQ is offered to the matcher at most once per run.

select cron.schedule(
  'rfq_redispatch_6h',
  '15 */6 * * *',
  $$select public.fn_rfq_redispatch_sweep(20);$$);

insert into public.cron_registry (jobname, human_name, category, purpose)
values (
  'rfq_redispatch_6h',
  'Retry RFQs that reached no supplier',
  'demand',
  'An RFQ created before a matching supplier existed was routed to nobody and, until 12 Aug 2026, '
  || 'could never be routed again: trg_autodispatch_inquiry fires once on the rfq_ready transition '
  || 'and dispatch_inquiry refused every later call as already_dispatched even when that dispatch '
  || 'reached zero suppliers. This offers those RFQs to the matcher again every six hours, because '
  || 'supply arrives after demand here — 20,470 leads are still to be onboarded. Only zero-fanout '
  || 'RFQs qualify, so no supplier can be notified twice, and each stops asking after 30 attempts.')
on conflict (jobname) do update
   set human_name = excluded.human_name,
       category   = excluded.category,
       purpose    = excluded.purpose;
