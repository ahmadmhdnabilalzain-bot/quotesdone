-- The RFQ that arrived before its supplier existed — 12 Aug 2026
--
-- dispatch_inquiry has exactly one caller: trg_autodispatch_inquiry, a trigger that fires on the
-- rfq_ready transition and only when routing->>'dispatched_at' is null. dispatch_inquiry writes
-- dispatched_at unconditionally, including on the run that fanned out to ZERO suppliers, and then
-- refused every later call with skip:'already_dispatched'.
--
-- So an RFQ created before a matching supplier existed was routed to nobody and could never be
-- routed again — not by the trigger (rfq_ready never transitions twice, and dispatched_at is now
-- set), not by a sweep (there was none), and not by the supplier's own registration (nothing
-- watches for that). It was dead the moment it was created, and nothing failed anywhere.
--
-- That is this company's normal case: demand arrives first, and suppliers are onboarded from
-- 20,470 leads afterwards. The journey test has been recording it as step 27 "supplier receives the
-- inquiry: inbox 0" while step 26 answered ok.
--
-- The guard is fixed in supabase/functions/dispatch_inquiry/index.ts (skip only when the previous
-- run actually reached someone). This is the retry that gives the fixed guard something to do.
--
-- SAFETY: only zero-fanout RFQs are retried, so no supplier can be notified twice — a zero-fanout
-- RFQ notified nobody, and the moment a retry reaches someone the row stops qualifying. Backoff is
-- 6 hours and attempts are capped at 30, so an RFQ nobody can serve stops asking after a week
-- instead of forever. Completed, cancelled and awarded RFQs are excluded.
--
-- PROMOTE-SAFE: the project ref is read from app_secrets, never hardcoded. trg_autodispatch_inquiry
-- hardcodes its own URL, which means its definition is NOT the same text on both projects; this
-- function deliberately does not repeat that mistake, using the same lookup fn_action_invoke_dispatch
-- already uses.

create or replace function public.fn_rfq_redispatch_sweep(p_limit int default 20)
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
    from public.inquiries i
   where i.rfq_ready is true
     and i.status in ('open', 'sent', 'split')
     and (i.routing->>'dispatched_at') is not null
     and coalesce((i.routing->>'fanout')::int, 0) = 0
     and i.created_at > now() - interval '90 days'
     and coalesce((i.routing->>'redispatch_count')::int, 0) < 30
     and coalesce((i.routing->>'redispatch_last')::timestamptz, 'epoch'::timestamptz)
           < now() - interval '6 hours';

  for r in
    select i.id
      from public.inquiries i
     where i.rfq_ready is true
       and i.status in ('open', 'sent', 'split')
       and (i.routing->>'dispatched_at') is not null
       and coalesce((i.routing->>'fanout')::int, 0) = 0
       and i.created_at > now() - interval '90 days'
       and coalesce((i.routing->>'redispatch_count')::int, 0) < 30
       and coalesce((i.routing->>'redispatch_last')::timestamptz, 'epoch'::timestamptz)
             < now() - interval '6 hours'
     order by i.created_at
     limit greatest(p_limit, 0)
  loop
    -- Stamped BEFORE the call, so a request that never comes back still consumes its attempt and
    -- the backoff holds. dispatched_at is left alone: it records a real historical event and the
    -- fixed guard no longer treats a zero-fanout run as a dispatch.
    update public.inquiries
       set routing = coalesce(routing, '{}'::jsonb)
                   || jsonb_build_object(
                        'redispatch_last', now(),
                        'redispatch_count', coalesce((routing->>'redispatch_count')::int, 0) + 1)
     where id = r.id;

    perform net.http_post(
      url     := 'https://' || v_ref || '.supabase.co/functions/v1/dispatch_inquiry',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body    := jsonb_build_object('__secret', v_secret, 'inquiry_id', r.id));

    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object(
    'ran_at', now(), 'eligible', v_eligible, 'retried', v_sent, 'limit', p_limit,
    'note', case when v_eligible = 0
                 then 'No RFQ is waiting on supply. Nothing to retry.'
                 else v_sent || ' of ' || v_eligible || ' RFQs that reached zero suppliers were '
                      || 'offered to the matcher again; supply may have arrived since they were created.'
            end);
end
$function$;

revoke all on function public.fn_rfq_redispatch_sweep(int) from public, anon, authenticated;
