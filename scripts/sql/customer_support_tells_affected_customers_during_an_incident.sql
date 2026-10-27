-- CUSTOMER SUPPORT TELLS AFFECTED CUSTOMERS DURING AN INCIDENT (19 Oct 2026). Assigned: customer_support (the message);
-- it_engineer records the incident and marks whether it affects customers. Founder ledger 1003 stage 2, contribution
-- CS-C12: "Tell customers proactively during a platform incident, in English and Arabic, coordinated with the IT engineer".
--
-- MEASURED 19 Oct 2026 (repo, read-only): public.it_incident (it_engineer's record: title, impact, started_at,
-- ended_at, cause, fix) says in free text who was affected, and nothing reads it for customers. No duty links an
-- incident to a holding message; incident communication depended on someone noticing.
--
-- WHAT THIS ADDS:
--   * it_incident.customer_impact: who the incident touches ('customers', 'suppliers', 'everyone'); null = internal
--     only (every incident recorded so far stays null, so applying this sends nothing). it_engineer sets it when the
--     incident is customer-facing; it_incident.customer_note_en / customer_note_ar optionally say what to tell people.
--   * customer_support.incident_notices, every 15 minutes, fn_customer_support_incident_notice_tick(). 27 Oct 2026
--     (founder_instruction 1339): the duty decides who is owed which notice and records it (fn_customer_support_voice_owe,
--     customer_support_writes_its_duty_updates_through_the_model.sql); the MODEL writes the words (_shared/duty_voice.ts,
--     one text per incident, side and language) and the sentences below are the draft, sent only on an OpenRouter
--     outage. The model is given only it_engineer's customer note (customer_note_en / _ar), never impact, cause or fix
--     (ledger 1338); the draft no longer falls back to the internal `impact` text either:
--       open incident (ended_at null) with customer_impact  ->  a HOLDING message, once per person, to everyone of
--         that side with a support conversation active in the last 14 days (the people who are mid-conversation with
--         us and would otherwise wait in silence): what is affected, that the IT engineer is on it, that their request
--         is safe and we will write again when it is fixed;
--       incident ended  ->  a RESOLVED message, once per person, to everyone who got the holding message.
--     English and Arabic by the person's case language (suppliers always English, founder ruling 28 Sep), through the
--     seat's one sending path (fn_customer_support_duty_send: once per (stage, key), suppression checked there).
--   WHAT IT DOES NOT DO: no public status page (none exists to update), no WhatsApp broadcast (outside a 24 h session
--   only an approved template may be sent, and none is approved for incidents yet).
-- qd.duty_fixtures = 'on' acts only on incidents titled 'ZZ DEMO%' and example.invalid addresses.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_tells_affected_customers_during_an_incident.sql --apply --ddl

alter table public.it_incident
  add column if not exists customer_impact  text,
  add column if not exists customer_note_en text,
  add column if not exists customer_note_ar text;
alter table public.it_incident drop constraint if exists it_incident_customer_impact_check;
alter table public.it_incident add constraint it_incident_customer_impact_check
  check (customer_impact is null or customer_impact in ('customers', 'suppliers', 'everyone'));
comment on column public.it_incident.customer_impact is
  'Who a customer-facing incident touches (customers | suppliers | everyone); null = internal. Set by it_engineer; customer_support.incident_notices writes the holding and resolved messages.';

create or replace function public.fn_customer_support_incident_notice_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  i public.it_incident; p record; v_ar boolean; v_what text; n_hold int := 0; n_res int := 0;
begin
  for i in select * from public.it_incident
            where customer_impact is not null and (coalesce(title, '') like 'ZZ DEMO%') = v_fx
              and (ended_at is null or ended_at > now() - interval '2 days')
              and coalesce(started_at, created_at) > now() - interval '14 days' order by id loop
    v_what := coalesce(nullif(btrim(i.customer_note_en), ''), 'part of the QuotesDone platform');   -- never the internal impact text (1338)
    if i.ended_at is null then
      for p in select distinct on (lower(pr.email)) lower(pr.email) email, coalesce(s.lang, 'en') lang, s.party_kind
                 from public.support_case s join public.support_customer_profile pr on pr.id = s.customer_profile_id
                where s.last_activity_at > now() - interval '14 days' and pr.email is not null
                  and public.fn_is_demo_email(pr.email) = v_fx
                  and (i.customer_impact = 'everyone' or (i.customer_impact = 'customers' and s.party_kind = 'customer')
                       or (i.customer_impact = 'suppliers' and s.party_kind = 'supplier'))
                order by lower(pr.email), s.last_activity_at desc loop
        v_ar := p.lang = 'ar' and p.party_kind <> 'supplier';
        if public.fn_customer_support_voice_owe('incident.holding', i.id || ':' || p.email,
          'incident.holding:' || i.id || ':' || case when v_ar then 'ar' else 'en' end || ':' || case when p.party_kind = 'supplier' then 'supplier' else 'customer' end,
          case when p.party_kind = 'supplier' then 'supplier' else 'customer' end, p.email, case when v_ar then 'ar' else 'en' end,
          case when v_ar then 'QuotesDone: نعمل على حل مشكلة مؤقتة' else 'QuotesDone: we are fixing a temporary problem' end,
          case when v_ar then
            'نودّ إعلامكم بوجود مشكلة مؤقتة تؤثر على: ' || coalesce(nullif(btrim(i.customer_note_ar), ''), 'جزء من منصة QuotesDone')
            || '. فريقنا التقني يعمل على حلّها الآن، وطلباتكم وبياناتكم محفوظة. سنراسلكم فور حلّها، ولا داعي لأي إجراء من جانبكم.'
            || chr(10) || chr(10) || 'نعتذر عن الإزعاج.' || chr(10) || 'فريق QuotesDone'
          else
            'We want to let you know about a temporary problem affecting ' || v_what
            || '. Our technical team is working on it now, and your requests and data are safe. We will write again as soon as it is fixed; there is nothing you need to do.'
            || chr(10) || chr(10) || 'We are sorry for the inconvenience.' || chr(10) || 'The QuotesDone team' end,
          'Write a short e-mail telling them about a temporary problem affecting what the facts name: our technical team is working on it now, their requests and data are safe, we will write again as soon as it is fixed, and there is nothing they need to do. Apologise for the inconvenience.',
          'WHAT IS AFFECTED: ' || case when v_ar then coalesce(nullif(btrim(i.customer_note_ar), ''), nullif(btrim(i.customer_note_en), ''), 'part of the QuotesDone platform') else v_what end,
          '{}') then n_hold := n_hold + 1; end if;
      end loop;
    else
      -- a holding notice still unwritten when the incident ends is never sent late; only those who got one hear it is fixed
      delete from public.customer_support_voice_owed
       where stage = 'incident.holding' and subject_key like i.id || ':%' and written_at is null;
      for p in select m.to_email email, m.subject_key from public.customer_support_duty_message m
                where m.stage = 'incident.holding' and m.subject_key like i.id || ':%' loop
        v_ar := exists (select 1 from public.support_case s join public.support_customer_profile pr on pr.id = s.customer_profile_id
                         where lower(pr.email) = p.email and s.lang = 'ar' and s.party_kind <> 'supplier');
        if public.fn_customer_support_voice_owe('incident.resolved', p.subject_key, 'incident.resolved:' || i.id || ':' || case when v_ar then 'ar' else 'en' end,
          'customer', p.email, case when v_ar then 'ar' else 'en' end,
          case when v_ar then 'QuotesDone: تم حل المشكلة' else 'QuotesDone: the problem is fixed' end,
          case when v_ar then 'تم حل المشكلة المؤقتة التي أبلغناكم بها، وكل شيء يعمل الآن كالمعتاد. شكرًا لصبركم.' || chr(10) || chr(10) || 'فريق QuotesDone'
          else 'The temporary problem we wrote to you about is fixed, and everything is working as normal. Thank you for your patience.'
               || chr(10) || chr(10) || 'The QuotesDone team' end,
          'Write a short e-mail telling them the temporary problem we wrote to them about is fixed and everything is working as normal, and thank them for their patience.',
          'WHAT WAS AFFECTED: ' || v_what || chr(10) || 'STATUS: fixed',
          '{}') then n_res := n_res + 1; end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'holding_owed', n_hold, 'resolved_owed', n_res);
end $fn$;
revoke execute on function public.fn_customer_support_incident_notice_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_incident_notice_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.incident_notices', 'customer_support', interval '15 minutes', 'fn_customer_support_incident_notice_tick',
   'CS-C12: a customer-facing IT incident (it_incident.customer_impact) gets a holding message to every affected person mid-conversation with us, and a resolved message when it ends, English and Arabic',
   'scripts/sql/customer_support_tells_affected_customers_during_an_incident.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
