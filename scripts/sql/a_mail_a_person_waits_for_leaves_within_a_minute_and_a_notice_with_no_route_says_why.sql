-- A MAIL A PERSON WAITS FOR LEAVES WITHIN A MINUTE, AND A NOTICE WITH NO ROUTE SAYS WHY (it_engineer, 12 Nov 2026).
-- Assigned: it_engineer (outbox scheduling). Founder ledger 1642 ("Proceed with fixes"); final audit 12 Nov 2026,
-- health F8 (fix O5); rewritten the same day on its independent review.
--
-- MEASURED (production, read-only, 12 Nov 2026):
--   * The real supplier's registration (lead 19398, 11 Nov): e-mails 139627 company_name_from_licence and 139630
--     registration_received were created 06:47:48-49Z and sent 07:00:59-07:01:06Z: 13 minutes. supplier_api queues them
--     (requestDelivery) and only resilience_ping's outbox step (the 15-minute heartbeat) drains e-mail. The sign-in code
--     is not on this path: login_otp sends it itself, at once.
--   * A seed batch is also queued supplier e-mail with no not_before (10 Nov: 258 invite_m365_seed rows), and every drain
--     sends up to M365_PER_RUN (5) of them, a pace built for one drain per 15 minutes. So the kick drains ONLY an
--     explicit allow-list of the kinds a person is waiting on right now; a kind not on it (every campaign, today and
--     later) keeps the heartbeat's pace by default.
--   * WhatsApp twins 139628 and 139631 are queued with last_error null; their template supplier_account_notice has
--     answered 404 at Twilio's Content API since 5 Oct (wa_template_registry status missing). send_whatsapp holds a
--     WhatsApp row after 24 h (send_whatsapp/index.ts), so nothing here cancels or fails a row: it is SAID.
--
-- CHANGE
--   1. fn_outbox_person_mail_kick(), pg_cron outbox_person_mail_kick every minute: when an e-mail of an allow-listed kind
--      (coalesce(kind, type) in fn_outbox_person_kinds()) was queued in the last 15 minutes with no not_before, it asks
--      send_outbox to drain THOSE KINDS ONLY (body.kinds; send_outbox claims them with fn_notifications_claim_kinds), so
--      no invitation is claimed by the kick. db.internal gains send_outbox in its scope (as it gained reveal_invoice in
--      every_confirmation_reaches_the_person_on_email_and_whatsapp.sql).
--   2. fn_notifications_claim_kinds(kinds[], limit): fn_notifications_claim's e-mail claim, restricted to those kinds.
--   3. fn_notice_without_a_route_sweep(), in the same job at :17 of each hour: every notice HELD over 24 h or QUEUED over
--      72 h (not_before passed) is the IT engineer's finding duty:notice_without_a_route:<channel>:<kind>:<status>, with the
--      rows' recipients (role, lead, inquiry) and latest reason, and for WhatsApp the registry rows of the templates that
--      are not approved. It changes no notification. Closed when no such row is left.
--   THE ALLOW-LIST is fn_outbox_person_kinds(), the one place: registration_received, company_name_from_licence,
--   supplier_approved (registration and account), supplier_mailbox_reply, new_message (a reply to his own message),
--   invoice_ready, reveal_receipt (a document he paid for). Add a kind there only for mail a person waits on.
-- ORDER: DEPLOY send_outbox FIRST (it must understand body.kinds; an older one would drain everything), then apply.
-- Revoked from public, anon, authenticated; fn_notifications_claim_kinds granted to service_role (send_outbox).
-- Prevented by: send_outbox/channels.test.ts (a named drain claims only its kinds) and the rolled-back probe
-- a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why_probe.sql.
--   node scripts/apply_sql.mjs scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql --apply --ddl

update public.internal_credential set scope = scope || array['send_outbox']
 where context = 'db.internal' and active and not ('send_outbox' = any (scope));

create or replace function public.fn_outbox_person_kinds()
returns text[] language sql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
  select array['registration_received', 'company_name_from_licence', 'supplier_approved',
               'supplier_mailbox_reply', 'new_message', 'invoice_ready', 'reveal_receipt']::text[]
$fn$;

revoke execute on function public.fn_outbox_person_kinds() from public, anon, authenticated;

create or replace function public.fn_notifications_claim_kinds(p_kinds text[], p_limit integer default 20)
returns setof public.notifications language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_lim int := greatest(1, least(coalesce(p_limit, 20), 50));
begin
  return query
    update public.notifications n
       set status = 'sending', claimed_at = now()
     where n.id in (
       select c.id from public.notifications c
        where (c.status in ('queued', 'pending') or c.status is null)
          and (c.channel is null or c.channel not in ('sms', 'whatsapp'))
          and (c.not_before is null or c.not_before <= now())
          and coalesce(c.kind, c.type) = any (coalesce(p_kinds, '{}'::text[]))
        order by c.created_at
        limit v_lim
        for update skip locked)
    returning n.*;
end $fn$;

revoke execute on function public.fn_notifications_claim_kinds(text[], integer) from public, anon, authenticated;
grant execute on function public.fn_notifications_claim_kinds(text[], integer) to service_role;

create or replace function public.fn_outbox_person_mail_kick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_n int; v_secret text; v_ref text; v_req bigint; v_kinds text[] := public.fn_outbox_person_kinds();
begin
  select count(*) into v_n from public.notifications
   where status = 'queued' and (channel is null or channel not in ('sms', 'whatsapp'))
     and coalesce(kind, type) = any (v_kinds)
     and not_before is null and created_at > now() - interval '15 minutes';
  if v_n = 0 then return jsonb_build_object('kicked', false); end if;
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  v_ref := public.qd_project_ref();
  if coalesce(v_secret, '') = '' or v_ref is null then
    return jsonb_build_object('kicked', false, 'waiting', v_n, 'reason', 'no db.internal credential or project ref');
  end if;
  select net.http_post('https://' || v_ref || '.supabase.co/functions/v1/send_outbox',
                       jsonb_build_object('__secret', v_secret, 'limit', 20, 'kinds', to_jsonb(v_kinds)), '{}'::jsonb,
                       '{"Content-Type":"application/json"}'::jsonb, 60000) into v_req;
  return jsonb_build_object('kicked', true, 'waiting', v_n, 'kinds', to_jsonb(v_kinds), 'request', v_req);
end $fn$;

revoke execute on function public.fn_outbox_person_mail_kick() from public, anon, authenticated;

create or replace function public.fn_notice_without_a_route_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', x.channel || ':' || x.k || ':' || x.status, 'owner_seat', 'it_engineer', 'subject', 'send_' || x.channel,
           'title', x.n || ' ' || x.channel || ' notice(s) of kind ' || x.k || ' ' || x.status || ' with no route for over '
                    || case x.status when 'held' then '24 h' else '72 h' end || ': ' || left(coalesce(x.why, 'no reason recorded'), 140),
           'blast', 'customer_facing', 'affected', x.n,
           'evidence', jsonb_build_object('rows', x.rows, 'latest_reason', x.why,
             'templates_not_approved', case when x.channel = 'whatsapp' then
               (select coalesce(jsonb_agg(jsonb_build_object('template', t.template_name, 'status', t.status, 'checked_at', t.checked_at)), '[]'::jsonb)
                  from public.wa_template_registry t where t.status <> 'approved') end))), '[]'::jsonb)
    into v_items
    from (select coalesce(n.channel, 'email') channel, coalesce(n.kind, n.type, '(none)') k, n.status, count(*) n,
                 (array_agg(n.last_error order by n.id desc))[1] why,
                 jsonb_agg(jsonb_build_object('id', n.id, 'to_role', n.to_role, 'lead_id', n.lead_id,
                                              'inquiry_id', n.inquiry_id, 'created_at', n.created_at) order by n.id desc) rows
            from public.notifications n
           where (n.status = 'held' and n.created_at < now() - interval '24 hours')
              or (n.status = 'queued' and n.created_at < now() - interval '72 hours'
                  and (n.not_before is null or n.not_before < now() - interval '72 hours'))
           group by 1, 2, 3) x;
  return jsonb_build_object('items', jsonb_array_length(v_items), 'settle', public.fn_it_duty_settle('notice_without_a_route', v_items));
end $fn$;

revoke execute on function public.fn_notice_without_a_route_sweep() from public, anon, authenticated;

select cron.schedule('outbox_person_mail_kick', '* * * * *',
  $CRON$set statement_timeout = '20s'; select public.fn_outbox_person_mail_kick(); select public.fn_notice_without_a_route_sweep() where extract(minute from now()) = 17;$CRON$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('outbox_person_mail_kick', 'Person-facing mail kick', 'Messaging',
   'Every minute: fn_outbox_person_mail_kick() asks send_outbox to drain only the kinds of mail a person is waiting for '
   || '(fn_outbox_person_kinds) when one was queued in the last 15 minutes; invitations keep the heartbeat''s pace. At :17 '
   || 'each hour, fn_notice_without_a_route_sweep() raises the IT engineer''s finding for notices held over 24 h or queued '
   || 'over 72 h. it_engineer, 12 Nov 2026 (final audit F8).')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'outbox_person_mail_kick', 'it_engineer',
   'Every minute: drains only the mail kinds a person waits on; hourly at :17 raises notices with no route.',
   'scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.prosecdef
              and p.proname in ('fn_outbox_person_mail_kick', 'fn_notice_without_a_route_sweep', 'fn_outbox_person_kinds', 'fn_notifications_claim_kinds')
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
     j as (select count(*) n from cron.job where jobname = 'outbox_person_mail_kick' and active),
     c as (select count(*) n from public.internal_credential where context = 'db.internal' and active and 'send_outbox' = any (scope))
select case when (select n from f) = 4 and (select n from j) = 1 and (select n from c) >= 1 then 'PROBE OK'
            else 'PROBE FAILED: routines ' || (select n from f) || ' of 4, job ' || (select n from j) || ', scope ' || (select n from c) end as verdict;
