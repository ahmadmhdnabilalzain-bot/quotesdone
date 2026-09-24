-- THE IT ENGINEER READS EVERY PROVIDER'S STATUS PAGE AND THE SITE'S FIREWALL, HOURLY.
-- Seat: it_engineer. 24 Sep 2026, seat audit (GAPS.md, IT gaps 3 and 5; founder_instruction 8 and 324; ledger 983).
--
-- WHAT WAS MEASURED (production, 24 Sep 2026): no routine, step or duty read the status page of Stripe, Resend,
--   Twilio, Vercel, Supabase or Dropbox, and none read the Vercel firewall mode or attack status. The same morning
--   Twilio and Supabase both published indicator 'minor', and nothing in the estate knew.
--
-- WHAT THIS ADDS: it_duty_schedule 'provider_status' (1 hour). resilience_ping's itlater step takes the readings
--   (supabase/functions/_shared/it_provider_readings.ts) and fn_it_provider_watch decides, through fn_it_duty_settle:
--     * a provider at 'major' or 'critical' is a finding duty:provider_status:<provider> with the provider's own
--       words, so an error storm in the same hour reads as THEIR outage, not our bug. 'minor' is recorded only:
--       Twilio publishes 'minor' most days and paging on it would be the noise instruction 642 forbids;
--     * the Vercel firewall switched off, or an active attack, is a security finding;
--     * a reading that could not be taken is a configuration item (held once, never re-raised every hour).
--   The seat does not act on a provider's outage (there is nothing inside the company to fix); the finding is the
--   record that stops the CEO and the seats chasing a bug that is not ours, and it closes itself when the page
--   clears. A firewall found OFF is raised, not switched on: changing the firewall is a configuration change the
--   founder reserved ([deploy] in org_role.forbidden_decisions).
--
-- WHAT THIS DOES NOT DO: it does not watch integration disconnects or re-authorisation (ledger 979, separate build),
--   and it does not read OpenRouter (no public status JSON; its key is read by the openrouter step).
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_reads_provider_status_pages_and_the_firewall.sql --apply --ddl
--   then deploy resilience_ping.

insert into public.it_duty_schedule (duty, every, note, owner_seat) values
  ('provider_status', interval '1 hour',
   'status pages of stripe, resend, twilio, vercel, supabase, dropbox and the Vercel firewall (fn_it_provider_watch)', 'it_engineer')
on conflict (duty) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

create or replace function public.fn_it_provider_watch(p_r jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x jsonb; v_items jsonb := '[]'::jsonb; fw jsonb := coalesce(p_r->'firewall', '{}'::jsonb); v_res jsonb;
begin
  for x in select e from jsonb_array_elements(coalesce(p_r->'providers', '[]'::jsonb)) e loop
    if x->>'basis' = 'unavailable' then
      v_items := v_items || jsonb_build_object('item', 'unreadable:' || (x->>'provider'), 'config', true, 'owner_seat', 'it_engineer',
        'title', 'The ' || (x->>'provider') || ' status page could not be read: ' || coalesce(x->>'reason', '?'), 'blast', 'monitor',
        'subject', x->>'provider', 'evidence', x);
    elsif x->>'indicator' in ('major', 'critical') then
      v_items := v_items || jsonb_build_object('item', x->>'provider', 'owner_seat', 'it_engineer', 'subject', x->>'provider',
        'title', initcap(x->>'provider') || ' reports a ' || (x->>'indicator') || ' incident on its status page: ' || coalesce(x->>'description', ''),
        'blast', case when x->>'provider' = 'dropbox' then 'internal' else 'customer_facing' end, 'evidence', x);
    end if;
  end loop;

  if fw->>'basis' = 'unavailable' or fw->'config'->>'basis' = 'unavailable' then
    v_items := v_items || jsonb_build_object('item', 'firewall:unreadable', 'config', true, 'owner_seat', 'it_engineer', 'blast', 'monitor',
      'title', 'The Vercel firewall could not be read: ' || coalesce(fw->>'reason', fw->'config'->>'reason', '?'), 'evidence', fw);
  elsif (fw->'config'->>'enabled')::boolean is false then
    v_items := v_items || jsonb_build_object('item', 'firewall:off', 'owner_seat', 'it_engineer', 'blast', 'security',
      'title', 'The Vercel firewall is switched off for the site', 'evidence', fw);
  end if;
  if fw->'attack'->>'basis' = 'measured' and (fw->'attack'->>'under_attack')::boolean then
    v_items := v_items || jsonb_build_object('item', 'firewall:attack', 'owner_seat', 'it_engineer', 'blast', 'security',
      'title', 'Vercel reports an active attack on the site', 'evidence', fw);
  end if;

  v_res := public.fn_it_duty_settle('provider_status', v_items);
  perform public.fn_it_duty_ran('provider_status', v_res);
  return v_res;
end $fn$;
revoke execute on function public.fn_it_provider_watch(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_provider_watch(jsonb) to service_role;

select case when to_regprocedure('public.fn_it_provider_watch(jsonb)') is not null
             and exists (select 1 from public.it_duty_schedule where duty = 'provider_status')
            then 'PROBE OK' else 'PROBE FAILED: fn_it_provider_watch or its schedule row is missing' end as verdict;
