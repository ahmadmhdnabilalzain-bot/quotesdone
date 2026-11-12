-- A MAIL A PERSON WAITS FOR LEAVES WITHIN A MINUTE, AND A NOTICE WITH NO ROUTE SAYS WHY (it_engineer, 12 Nov 2026).
-- Assigned: it_engineer (outbox scheduling). Founder ledger 1642 ("Proceed with fixes"); final audit 12 Nov 2026,
-- health F8 (fix O5).
--
-- MEASURED (production, read-only, 12 Nov 2026):
--   * The real supplier's registration (lead 19398, 11 Nov): notifications 139627 company_name_from_licence and 139630
--     registration_received, e-mail, created 06:47:48-49Z, sent 07:00:59-07:01:06Z: 13 minutes. They are queued by
--     supplier_api/actions/profile.ts through requestDelivery and nothing drains them until resilience_ping's outbox step
--     (the 15-minute heartbeat; no pg_cron job drains e-mail). The sign-in code is not on this path: login_otp sends it
--     itself, at once. A quote notice is fast because quote_acceptance.ts kicks send_outbox after queueing it.
--   * Their WhatsApp twins 139628 and 139631 are still queued after 16 h with last_error null. Both types map to the
--     template supplier_account_notice (send_whatsapp/templates.ts), whose two registry rows
--     (quotesdone_supplier_account_notice_en_mu6esqkz, _ar_mu6est8z) read "missing": Twilio's Content API answered 404 on
--     5 Oct 2026. Both e-mail twins read provider_status delivered.
--
-- CHANGE
--   1. fn_outbox_person_mail_kick(), pg_cron outbox_person_mail_kick every minute: when an e-mail to a supplier or a
--      customer was queued in the last 15 minutes with no not_before (a mail a person is waiting for, not a scheduled
--      batch: the daily invitations carry not_before), it asks send_outbox to drain once (limit 20) through pg_net.
--      send_outbox claims its rows (channels.ts claimQueue), so a kick racing the heartbeat's drain sends nothing twice.
--      The db.internal credential the database already holds gains send_outbox in its scope (as it gained
--      reveal_invoice in every_confirmation_reaches_the_person_on_email_and_whatsapp.sql). Cost: one indexed count a
--      minute; a kick only when such a mail exists.
--   2. fn_notice_without_a_route_sweep(), in the same job at minute :17 of each hour: a WhatsApp notice queued over 24 h
--      whose e-mail twin (same type and person, created within 10 s) was delivered is CANCELLED with that reason; any
--      other notice queued over 72 h with no not_before ahead is FAILED with its reason. Every type swept in the last
--      7 days is the IT engineer's finding duty:notice_without_a_route:<channel>:<type> (fn_it_duty_settle), closed once
--      no swept notice of that type is under 7 days old.
--   APPLYING THIS FILE CANCELS 139628 AND 139631 (the real supplier's WhatsApp copies; their e-mails were delivered) at
--   the first :17. The main session decides; to keep them queued, apply after the template is registered.
-- Revoked from public, anon, authenticated; search_path pinned. Deploy nothing: send_outbox is unchanged.
-- Prevented by: the rolled-back probe a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why_probe.sql.
--   node scripts/apply_sql.mjs scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql --apply --ddl

update public.internal_credential set scope = scope || array['send_outbox']
 where context = 'db.internal' and active and not ('send_outbox' = any (scope));

create or replace function public.fn_outbox_person_mail_kick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_n int; v_secret text; v_ref text; v_req bigint;
begin
  select count(*) into v_n from public.notifications
   where status = 'queued' and channel = 'email' and to_role in ('supplier', 'customer')
     and not_before is null and created_at > now() - interval '15 minutes';
  if v_n = 0 then return jsonb_build_object('kicked', false); end if;
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  v_ref := public.qd_project_ref();
  if coalesce(v_secret, '') = '' or v_ref is null then
    return jsonb_build_object('kicked', false, 'waiting', v_n, 'reason', 'no db.internal credential or project ref');
  end if;
  select net.http_post('https://' || v_ref || '.supabase.co/functions/v1/send_outbox',
                       jsonb_build_object('__secret', v_secret, 'limit', 20), '{}'::jsonb,
                       '{"Content-Type":"application/json"}'::jsonb, 60000) into v_req;
  return jsonb_build_object('kicked', true, 'waiting', v_n, 'request', v_req);
end $fn$;

revoke execute on function public.fn_outbox_person_mail_kick() from public, anon, authenticated;

create or replace function public.fn_notice_without_a_route_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n_twin int; n_old int; v_items jsonb;
begin
  -- a WhatsApp copy whose e-mail twin already reached the person
  with t as (
    update public.notifications w
       set status = 'cancelled',
           last_error = left('no WhatsApp route for 24 h (' || coalesce(nullif(w.last_error, ''), 'no template or sender answered')
                             || '); the e-mail twin ' || e.id || ' was delivered, so this copy is cancelled', 500)
      from public.notifications e
     where w.status = 'queued' and w.channel = 'whatsapp' and w.created_at < now() - interval '24 hours'
       and (w.not_before is null or w.not_before < now())
       and e.channel = 'email' and e.type = w.type and e.provider_status in ('delivered', 'read')
       and e.created_at between w.created_at - interval '10 seconds' and w.created_at + interval '10 seconds'
       and (e.lead_id is not distinct from w.lead_id) and (e.inquiry_id is not distinct from w.inquiry_id)
       and (e.quote_id is not distinct from w.quote_id)
    returning w.id)
  select count(*) into n_twin from t;
  -- anything else that has had no route for three days
  with t as (
    update public.notifications n
       set status = 'failed',
           last_error = left('no route for 72 h: ' || coalesce(nullif(n.last_error, ''), 'nothing claimed or answered it'), 500)
     where n.status = 'queued' and n.created_at < now() - interval '72 hours'
       and (n.not_before is null or n.not_before < now() - interval '72 hours')
    returning n.id)
  select count(*) into n_old from t;
  -- what was swept is the IT engineer's, by channel and type, while any such notice is under 7 days old (the row keeps no
  -- sweep time, so the window is on created_at: a swept row is 1 to 3 days old when swept)
  select coalesce(jsonb_agg(jsonb_build_object('item', x.channel || ':' || x.type, 'owner_seat', 'it_engineer',
           'subject', 'send_' || x.channel,
           'title', x.n || ' ' || x.channel || ' notice(s) of type ' || x.type || ' had no route and were ' || x.how
                    || ' (created in the last 7 days)',
           'blast', 'customer_facing', 'affected', x.n,
           'evidence', jsonb_build_object('ids', to_jsonb(x.ids), 'latest_reason', x.why))), '[]'::jsonb)
    into v_items
    from (select channel, coalesce(type, '(none)') type, count(*) n, (array_agg(id order by id desc))[1:10] ids,
                 string_agg(distinct status, '/') how, (array_agg(last_error order by id desc))[1] why
            from public.notifications
           where status in ('cancelled', 'failed') and created_at > now() - interval '7 days'
             and (last_error like 'no WhatsApp route for 24 h%' or last_error like 'no route for 72 h:%')
           group by 1, 2) x;
  return jsonb_build_object('whatsapp_cancelled_twin_delivered', n_twin, 'failed_no_route', n_old,
                            'settle', public.fn_it_duty_settle('notice_without_a_route', v_items));
end $fn$;

revoke execute on function public.fn_notice_without_a_route_sweep() from public, anon, authenticated;

select cron.schedule('outbox_person_mail_kick', '* * * * *',
  $CRON$set statement_timeout = '20s'; select public.fn_outbox_person_mail_kick(); select public.fn_notice_without_a_route_sweep() where extract(minute from now()) = 17;$CRON$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('outbox_person_mail_kick', 'Person-facing mail kick', 'Messaging',
   'Every minute: fn_outbox_person_mail_kick() asks send_outbox to drain when an e-mail to a supplier or customer was '
   || 'queued in the last 15 minutes (a registration mail left 13 minutes late on 11 Nov). At :17 each hour, '
   || 'fn_notice_without_a_route_sweep() cancels a WhatsApp copy whose e-mail was delivered after 24 h, fails anything else '
   || 'queued for 72 h, and raises the IT engineer''s finding. it_engineer, 12 Nov 2026 (final audit F8).')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'outbox_person_mail_kick', 'it_engineer',
   'Every minute: kicks send_outbox for a mail a person is waiting for; hourly at :17 sweeps notices with no route.',
   'scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.prosecdef
              and p.proname in ('fn_outbox_person_mail_kick', 'fn_notice_without_a_route_sweep')
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
     j as (select count(*) n from cron.job where jobname = 'outbox_person_mail_kick' and active),
     c as (select count(*) n from public.internal_credential where context = 'db.internal' and active and 'send_outbox' = any (scope))
select case when (select n from f) = 2 and (select n from j) = 1 and (select n from c) >= 1 then 'PROBE OK'
            else 'PROBE FAILED: routines ' || (select n from f) || ' of 2, job ' || (select n from j) || ', scope ' || (select n from c) end as verdict;
