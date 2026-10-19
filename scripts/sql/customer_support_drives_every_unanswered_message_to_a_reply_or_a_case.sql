-- CUSTOMER SUPPORT DRIVES EVERY UNANSWERED MESSAGE TO A REPLY OR A CASE (19 Oct 2026). Assigned: customer_support.
-- Founder ledger 1003 stage 2: the seat's senior contributions become working duties. Contribution CS-C01 (knowledge/
-- standards/customer_support.json): "Answer every chat, WhatsApp and email question in the same reply".
--
-- GAP, as the standard records it: the channels run as edge functions with no seat duty measuring in-week SLA
-- breaches; the 30 Sep audit found 4 of 4 inbound emails unanswered in a week, and nothing routed an unanswered
-- email to a reply or a case within the SLA. fn_support_reply_watch_tick (seatClocks, every 30 min) RAISES a finding
-- after 24 h and does nothing else: a finding is a record, not the act (quotesdone-session 1d).
--
-- WHAT THIS ADDS: customer_support.unanswered_inbound, every 15 minutes, fn_customer_support_unanswered_inbound_tick().
-- Code, no model. For each inbound still without a reply after decision_policy support_unanswered_drive_hours (2):
--   email     a support case is opened or continued through the one case door (fn_support_touch); the sender gets a
--             written acknowledgement with the case reference and the 24 h answer promise, in their language
--             (Arabic when they wrote Arabic), through the seat's one sending path (fn_customer_support_duty_send:
--             once per message, sendability and suppression checked there); the case is put in the seat's inbox as
--             support.case_open (the existing handoff, 24 h reply_within) so a person or the reasoned reply answers it.
--   whatsapp  the case and the support.case_open handoff. No free-text acknowledgement: outside WhatsApp's 24 h
--             session only an approved template may be sent, and the reply itself is what is owed.
--   chat      not driven here: a widget visitor has no address to answer, and every unanswered chat question is
--             already filed as a knowledge request (fn_customer_support_case_review_tick) and closed by
--             customer_support.knowledge_request_deadline.
-- Each message is acted on once (customer_support_inbound_drive). When the message is answered (inbound_messages.
-- replied_at, or a sent WhatsApp reply), the tick completes its support.case_open handoff with that evidence.
-- Scope is the case review's: customers only (fn_support_email_is_a_customer_contact for email; the founder's numbers
-- excluded for WhatsApp). qd.duty_fixtures = 'on' reads ONLY ZZ DEMO / example.invalid rows.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_drives_every_unanswered_message_to_a_reply_or_a_case.sql --apply --ddl

insert into public.decision_policy (key, value, description) values
  ('support_unanswered_drive_hours', '2'::jsonb,
   'fn_customer_support_unanswered_inbound_tick: an inbound email or WhatsApp message still without a reply after this many hours is put into a support case (and an email is acknowledged with the case reference). Must stay well under support_first_reply_sla_hours (24).')
on conflict (key) do nothing;

create table if not exists public.customer_support_inbound_drive (
  channel     text not null check (channel in ('email', 'whatsapp')),
  message_id  bigint not null,
  case_ref    text,
  acknowledged boolean not null default false,
  handoff_id  bigint,
  outcome     text,
  acted_at    timestamptz not null default now(),
  answered_at timestamptz,
  fixture     boolean not null default false,
  primary key (channel, message_id)
);
comment on table public.customer_support_inbound_drive is
  'customer_support.unanswered_inbound: one row per inbound email or WhatsApp message the seat drove to a case (and, for email, an acknowledgement), and when it was answered.';
alter table public.customer_support_inbound_drive enable row level security;
drop policy if exists customer_support_inbound_drive_service_role_only on public.customer_support_inbound_drive;
create policy customer_support_inbound_drive_service_role_only on public.customer_support_inbound_drive
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_inbound_drive from anon, authenticated;

create or replace function public.fn_customer_support_unanswered_inbound_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_cut timestamptz := now() - make_interval(hours => greatest(1, public.fn_seat_clock_policy('support_unanswered_drive_hours', 2)::int));
  v_sla int := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24)::int;
  v_founder text[]; m record; w record; d record; v_t jsonb; v_ref text; v_h bigint; v_s jsonb; v_ar boolean;
  n_email int := 0; n_ack int := 0; n_wa int := 0; n_answered int := 0; n_noid int := 0;
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- 1. answered since: complete the case handoff with what answered it
  for d in select i.* from public.customer_support_inbound_drive i where i.answered_at is null and i.fixture = v_fx loop
    if (d.channel = 'email' and exists (select 1 from public.inbound_messages x where x.id = d.message_id and x.replied_at is not null))
       or (d.channel = 'whatsapp' and exists (select 1 from public.wa_messages x where x.id = d.message_id and x.reply is not null and coalesce(x.sent, false))) then
      update public.customer_support_inbound_drive set answered_at = now() where channel = d.channel and message_id = d.message_id;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = d.handoff_id and a.status not in ('done', 'failed')) then
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('answered', true, 'channel', d.channel, 'message_id', d.message_id));
      end if;
      n_answered := n_answered + 1;
    end if;
  end loop;

  -- 2. email still unanswered past the drive threshold
  for m in select x.* from public.inbound_messages x
            where x.replied_at is null and x.created_at < v_cut and x.created_at > now() - interval '30 days'
              and public.fn_support_email_is_a_customer_contact(x.from_email, x.to_email, x.owner_role, x.subject, v_fx)
              and not exists (select 1 from public.customer_support_inbound_drive i where i.channel = 'email' and i.message_id = x.id)
            order by x.id limit 50 loop
    v_t := public.fn_support_touch('email', 'in', 'unknown', null, m.from_email, null,
                                   coalesce(m.subject, '') || ' ' || left(coalesce(m.body, ''), 1000));
    v_ref := v_t->>'case_ref';
    if v_ref is null then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture) values ('email', m.id, 'no identity: ' || coalesce(v_t->>'reason', '?'), v_fx);
      n_noid := n_noid + 1; continue;
    end if;
    v_ar := coalesce(m.subject, '') || coalesce(m.body, '') ~ '[؀-ۿ]';
    v_s := public.fn_customer_support_duty_send('inbound.ack', 'email:' || m.id, 'customer', m.from_email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'استلمنا رسالتكم - المرجع ' || v_ref else 'We have your message - reference ' || v_ref end,
      case when v_ar then
        'شكرًا لتواصلكم مع QuotesDone. استلمنا رسالتكم وسجّلناها تحت المرجع ' || v_ref || '. سيرد عليكم أحد أعضاء فريقنا خلال ' || v_sla
        || ' ساعة. إذا كتبتم إلينا مرة أخرى، يُرجى ذكر هذا المرجع.' || chr(10) || chr(10) || 'فريق QuotesDone'
      else
        'Thank you for contacting QuotesDone. We have your message and logged it under reference ' || v_ref
        || '. A member of our team will answer within ' || v_sla || ' hours. If you write again, please quote this reference.'
        || chr(10) || chr(10) || 'The QuotesDone team' end);
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_ref,
      jsonb_build_object('case_ref', v_ref, 'channel', 'email', 'message_id', m.id,
                         'waiting_for', 'an answer to email #' || m.id || ' (case ' || v_ref || '), owed within ' || v_sla || ' h of ' || m.created_at));
    insert into public.customer_support_inbound_drive (channel, message_id, case_ref, acknowledged, handoff_id, outcome, fixture)
    values ('email', m.id, v_ref, coalesce((v_s->>'sent')::boolean, false), v_h, coalesce(v_s->>'reason', 'acknowledged'), v_fx);
    n_email := n_email + 1;
    if coalesce((v_s->>'sent')::boolean, false) then n_ack := n_ack + 1; end if;
  end loop;

  -- 3. WhatsApp still unanswered past the drive threshold
  for w in select x.* from public.wa_messages x
            where x.created_at < v_cut and x.created_at > now() - interval '30 days'
              and coalesce(btrim(x.inbound), '') <> '' and (x.reply is null or not coalesce(x.sent, false))
              and not (right(regexp_replace(coalesce(x.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
              and (coalesce(x.profile_name, '') like 'ZZ DEMO%') = v_fx
              and not exists (select 1 from public.customer_support_inbound_drive i where i.channel = 'whatsapp' and i.message_id = x.id)
            order by x.id limit 50 loop
    v_t := public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, w.wa_from, w.inbound);
    v_ref := v_t->>'case_ref';
    if v_ref is null then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture) values ('whatsapp', w.id, 'no identity: ' || coalesce(v_t->>'reason', '?'), v_fx);
      n_noid := n_noid + 1; continue;
    end if;
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_ref,
      jsonb_build_object('case_ref', v_ref, 'channel', 'whatsapp', 'message_id', w.id,
                         'waiting_for', 'an answer to WhatsApp #' || w.id || ' (case ' || v_ref || '), owed within ' || v_sla || ' h of ' || w.created_at));
    insert into public.customer_support_inbound_drive (channel, message_id, case_ref, handoff_id, outcome, fixture)
    values ('whatsapp', w.id, v_ref, v_h, 'case opened', v_fx);
    n_wa := n_wa + 1;
  end loop;

  return jsonb_build_object('ok', true, 'fixture', v_fx, 'email_driven', n_email, 'email_acknowledged', n_ack,
                            'whatsapp_driven', n_wa, 'answered_since', n_answered, 'no_identity', n_noid);
end $fn$;
revoke execute on function public.fn_customer_support_unanswered_inbound_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_unanswered_inbound_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.unanswered_inbound', 'customer_support', interval '15 minutes', 'fn_customer_support_unanswered_inbound_tick',
   'CS-C01: every inbound email or WhatsApp message still unanswered after support_unanswered_drive_hours is put into a support case and the seat''s inbox; an email is acknowledged with its case reference; the handoff closes when the message is answered',
   'scripts/sql/customer_support_drives_every_unanswered_message_to_a_reply_or_a_case.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- the new table is in the daily table export (backups), like every other seat record
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_support_inbound_drive', true, 'customer_support', 'Each inbound email or WhatsApp message customer_support drove to a case and acknowledgement (CS-C01).', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;
