-- The supplier the matcher could not see — 12 Aug 2026
--
-- Second instance today of the same shape as the RFQ dispatch defect. trg_enrich_capability fires
-- only when approval_status BECOMES 'approved' and capability_enriched_at is null. It calls the
-- enrich_capability edge function over net.http_post and nothing checks the result. If that call
-- fails, times out, or the function errors, capability_enriched_at stays null — and approval_status
-- will never transition again, so nothing ever retries.
--
-- The consequence is quiet and total: an approved supplier with no capability record is invisible to
-- fn_match_capability, therefore invisible to route_inquiry, therefore invisible to every RFQ, for
-- ever. Nothing fails. The supplier waits in their portal for work that structurally cannot arrive.
--
-- MEASURED BEFORE BUILDING, and the measurement changed the design:
--   production  1 approved lead, 0 stuck  (lead 30466, enriched, matchable — verified against
--               fn_match_capability with the founder's own HVAC brief)
--   staging     50 approved with capability_enriched_at null — and ALL 50 are demo fixtures on
--               @example.* addresses with claimed_by null. They were seeded as approved rather than
--               transitioning into it, so the trigger never had a transition to fire on. They are
--               not 50 failures, and a sweep that woke them would spend model money enriching
--               companies that never asked to be on the platform.
--
-- So the sweep requires a CLAIMED lead. Capability enrichment describes what a company can do so
-- RFQs can reach it; a lead nobody has claimed is a scraped company, not a supplier. That single
-- condition excludes all 50 fixtures without teaching a production routine about the demo
-- convention — though the convention is excluded explicitly too, because both statements are true
-- and the cheaper one should not be the only guard.
--
-- Conservative on purpose: enrichment costs model spend, so 10 per run, 12-hour backoff, and a cap
-- of 8 attempts. A supplier whose enrichment cannot succeed stops asking after four days and is left
-- for a human, rather than billing indefinitely.
--
-- PROMOTE-SAFE: reads app_secrets.project_ref, never a literal. trg_enrich_capability itself is one
-- of the eighteen routines still carrying a hardcoded ref and must not be promoted as it stands.

alter table public.leads add column if not exists enrich_retry jsonb;

comment on column public.leads.enrich_retry is
  'Backoff state for fn_capability_enrich_sweep: {last, count}. Records that enrichment was ASKED '
  'for, never that it succeeded — capability_enriched_at is the success marker and is set by '
  'enrich_capability itself.';

create or replace function public.fn_capability_enrich_sweep(p_limit int default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  v_ref text; v_secret text;
  v_sent int := 0; v_eligible int := 0;
begin
  select value into v_secret from app_secrets where key = 'cred_db_internal';
  if v_secret is null then
    return jsonb_build_object('error', 'cred_db_internal missing', 'ran_at', now());
  end if;

  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then
    return jsonb_build_object('error', 'cannot determine project ref', 'ran_at', now());
  end if;

  select count(*) into v_eligible
    from public.leads l
   where l.approval_status = 'approved'
     and l.capability_enriched_at is null
     and l.claimed_by is not null
     and l.claimed_by not ilike '%@example.%'
     and coalesce(l.company_name,'') not ilike 'ZZ DEMO%'
     and coalesce((l.enrich_retry->>'count')::int, 0) < 8
     and coalesce((l.enrich_retry->>'last')::timestamptz, 'epoch'::timestamptz) < now() - interval '12 hours';

  for r in
    select l.id
      from public.leads l
     where l.approval_status = 'approved'
       and l.capability_enriched_at is null
       and l.claimed_by is not null
       and l.claimed_by not ilike '%@example.%'
       and coalesce(l.company_name,'') not ilike 'ZZ DEMO%'
       and coalesce((l.enrich_retry->>'count')::int, 0) < 8
       and coalesce((l.enrich_retry->>'last')::timestamptz, 'epoch'::timestamptz) < now() - interval '12 hours'
     order by l.id
     limit greatest(p_limit, 0)
  loop
    -- Stamped BEFORE the call so a request that never returns still consumes its attempt and the
    -- backoff holds. capability_enriched_at is left for enrich_capability to set: this routine
    -- records that it ASKED, never that the work was done.
    update public.leads
       set enrich_retry = coalesce(enrich_retry, '{}'::jsonb)
                        || jsonb_build_object(
                             'last', now(),
                             'count', coalesce((enrich_retry->>'count')::int, 0) + 1)
     where id = r.id;

    perform net.http_post(
      url     := 'https://' || v_ref || '.supabase.co/functions/v1/enrich_capability',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body    := jsonb_build_object('__secret', v_secret, 'lead_id', r.id));

    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object(
    'ran_at', now(), 'eligible', v_eligible, 'retried', v_sent, 'limit', p_limit,
    'note', case when v_eligible = 0
                 then 'Every claimed, approved supplier has a capability record. Nothing to retry.'
                 else v_sent || ' approved supplier(s) had no capability record and were re-sent to '
                      || 'enrich_capability; without one they are invisible to the matcher and to every RFQ.'
            end);
end
$function$;

revoke all on function public.fn_capability_enrich_sweep(int) from public, anon, authenticated;
