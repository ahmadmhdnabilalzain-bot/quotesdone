-- CUSTOMER SUPPORT WATCHES DELIVERY HEALTH EVERY DAY AND NEVER LOSES AN OPT-OUT (19 Oct 2026). Assigned: customer_support.
-- Founder ledger 1003 stage 2, contribution CS-C09: "Watch delivery health daily: bounces, suppressions, WhatsApp
-- failures, template approval, unsubscribe endpoint".
--
-- MEASURED 19 Oct 2026 (repo, production and edge logs, read-only):
--   * wa_templates_watch 403 on 314 of 352 runs (30 Sep audit): the auth gate (requireInternal) refused the caller's
--     credential, out_of_scope, 24-28 Sep. Already fixed (resilience_ping sends cred_cron_notifications;
--     the_template_watcher_is_called_with_a_credential_scoped_to_it.sql); agent_runs fn:wa_templates_watch reads 'ok'
--     since 28 Sep (12 of 12 in the last 3 days). Nothing watched it, so the next such run of failures would again go
--     unseen: this duty watches it.
--   * unsubscribe 400 on 125 of 146 calls: the only 400 path is a token that does not verify. The edge logs of 29 Sep
--     show 71 of them are our own check's 'check-only' probe on zz-demo@example.invalid, plus deliberate bad-token
--     probes, bare-URL walks and two link-scanner rewrites of inbox-testing addresses (glockapps, userflowhq) whose
--     local part had been changed. Signing (send_outbox unsubTok) and verifying (unsubscribe tok) match. Days checked
--     with no refused real address: 24, 28, 29 Sep; 5, 6, 13 Oct (12 Oct: the log service errored). No lost opt-out
--     was found; but nothing in the database kept the address of a refused attempt, so one could not even be looked for.
--
-- WHAT THIS ADDS:
--   1. public.unsubscribe_refusal: supabase/functions/unsubscribe now writes every refused attempt that names an address.
--   2. customer_support.delivery_health, daily, fn_customer_support_delivery_health_tick(). Code, no model:
--      * a refused opt-out from an address we actually mailed (a sent notification to it) and not yet suppressed is
--        RECORDED as an opt-out (email_suppressions reason 'unsubscribe', source 'recovered_refused_link'), which stops
--        marketing only (fn_opt_out_types), never transactional mail. The person meant to leave; a mangled link is ours
--        to absorb. example.invalid probes never count;
--      * the day's health, by class, each its own finding owned by customer_support (opened over threshold, closed when
--        back): delivery_health:send_failures (failed or bounced share of the last 24 h's sends over 5%, 20 sends or
--        more), delivery_health:whatsapp_failures (the same for the WhatsApp channel), delivery_health:template_watch
--        (any wa_templates_watch run in 24 h not 'ok', or none at all), delivery_health:unsubscribe_refusals (refusals
--        from real addresses in 24 h; recovered ones listed). Suppressions added in 24 h are reported in the result.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge (deploy the unsubscribe function in the same release):
--   node scripts/apply_sql.mjs scripts/sql/customer_support_watches_delivery_health_every_day_and_never_loses_an_opt_out.sql --apply --ddl

create table if not exists public.unsubscribe_refusal (
  id            bigint generated always as identity primary key,
  at            timestamptz not null default now(),
  email         text not null,
  method        text,
  token_present boolean not null default false,
  user_agent    text,
  recovered_at  timestamptz,
  outcome       text
);
comment on table public.unsubscribe_refusal is
  'Every unsubscribe attempt the endpoint refused (token did not verify), with the address it named. fn_customer_support_delivery_health_tick records the ones from addresses we mailed as opt-outs.';
create index if not exists unsubscribe_refusal_open on public.unsubscribe_refusal (at) where recovered_at is null;
alter table public.unsubscribe_refusal enable row level security;
drop policy if exists unsubscribe_refusal_service_role_only on public.unsubscribe_refusal;
create policy unsubscribe_refusal_service_role_only on public.unsubscribe_refusal
  as permissive for all to public using (false) with check (false);
revoke all on public.unsubscribe_refusal from anon, authenticated;

create or replace function public.fn_customer_support_delivery_health_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v_rec int := 0; v_sends int; v_bad int; v_wa int; v_wa_bad int; v_tpl_ok int; v_tpl_bad int; v_ref int;
  v_sup int; v_out jsonb; v_cls text; v_on boolean; v_ev jsonb;
begin
  -- 1. refused opt-outs from addresses we mailed become opt-outs (a fixture run sees only example.invalid rows)
  for r in select u.* from public.unsubscribe_refusal u
            where u.recovered_at is null and (lower(u.email) like '%@example.invalid') = v_fx
            order by u.id limit 200 loop
    if exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(r.email))) then
      update public.unsubscribe_refusal set recovered_at = now(), outcome = 'already suppressed' where id = r.id;
    elsif exists (select 1 from public.notifications n where lower(btrim(n.to_email)) = lower(btrim(r.email))
                    and (n.status = 'sent' or n.sent_at is not null)) then
      insert into public.email_suppressions (email, reason, source) values (lower(btrim(r.email)), 'unsubscribe', 'recovered_refused_link')
      on conflict (email) do nothing;
      update public.unsubscribe_refusal set recovered_at = now(), outcome = 'opt-out recorded (we had mailed this address)' where id = r.id;
      v_rec := v_rec + 1;
    elsif r.at < now() - interval '1 day' then
      update public.unsubscribe_refusal set recovered_at = now(), outcome = 'not an address we mailed: not an opt-out of ours' where id = r.id;
    end if;
  end loop;

  -- 2. the day's health
  select count(*), count(*) filter (where n.status in ('failed', 'bounced', 'error')),
         count(*) filter (where n.channel = 'whatsapp'), count(*) filter (where n.channel = 'whatsapp' and n.status in ('failed', 'bounced', 'error'))
    into v_sends, v_bad, v_wa, v_wa_bad
    from public.notifications n
   where n.created_at > now() - interval '24 hours' and n.status not in ('pending', 'queued', 'suppressed')
     and (lower(coalesce(n.to_email, '')) like '%@example.invalid') = v_fx;
  select count(*) filter (where status = 'ok'), count(*) filter (where status is distinct from 'ok')
    into v_tpl_ok, v_tpl_bad
    from public.agent_runs where agent = 'fn:wa_templates_watch' and started_at > now() - interval '24 hours';
  select count(*) into v_ref from public.unsubscribe_refusal u
   where u.at > now() - interval '24 hours' and (lower(u.email) like '%@example.invalid') = v_fx;
  select count(*) into v_sup from public.email_suppressions s where s.created_at > now() - interval '24 hours';

  v_out := jsonb_build_object('sends_24h', v_sends, 'failed_or_bounced_24h', v_bad, 'whatsapp_24h', v_wa, 'whatsapp_failed_24h', v_wa_bad,
                              'template_watch_ok_24h', v_tpl_ok, 'template_watch_not_ok_24h', v_tpl_bad,
                              'unsubscribe_refusals_24h', v_ref, 'opt_outs_recovered', v_rec, 'suppressions_added_24h', v_sup);
  if not v_fx then
    foreach v_cls in array array['send_failures', 'whatsapp_failures', 'template_watch', 'unsubscribe_refusals'] loop
      v_on := case v_cls
                when 'send_failures' then v_sends >= 20 and v_bad::numeric / v_sends > 0.05
                when 'whatsapp_failures' then v_wa >= 20 and v_wa_bad::numeric / v_wa > 0.05
                when 'template_watch' then v_tpl_bad > 0 or v_tpl_ok = 0
                else v_ref > 0 end;
      if v_on then
        perform public.fn_it_engineer_finding_upsert('delivery_health:' || v_cls,
          'Delivery health: ' || replace(v_cls, '_', ' ') || ' in the last 24 h ' || v_out::text,
          'customer_support daily delivery health (fn_customer_support_delivery_health_tick)', 'customer_facing',
          greatest(v_bad, v_wa_bad, v_tpl_bad, v_ref, 1), v_out || jsonb_build_object('owner_seat', 'customer_support', 'duty', 'delivery_health'),
          '{}'::text[], array['the provider error behind the failures'], 'customer_support');
      elsif exists (select 1 from public.it_engineer_finding f where f.issue_key = 'delivery_health:' || v_cls and f.closed_at is null) then
        perform public.fn_it_engineer_finding_close('delivery_health:' || v_cls, 'back within threshold for 24 hours');
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'fixture', v_fx) || v_out;
end $fn$;
revoke execute on function public.fn_customer_support_delivery_health_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_delivery_health_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.delivery_health', 'customer_support', interval '1 day', 'fn_customer_support_delivery_health_tick',
   'CS-C09: daily delivery health (send and WhatsApp failures, the template watcher, unsubscribe refusals, suppressions), each a finding the seat owns; a refused opt-out from an address we mailed is recorded as an opt-out, never lost',
   'scripts/sql/customer_support_watches_delivery_health_every_day_and_never_loses_an_opt_out.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
