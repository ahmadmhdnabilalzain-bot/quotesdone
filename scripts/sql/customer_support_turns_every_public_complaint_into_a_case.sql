-- CUSTOMER SUPPORT TURNS EVERY PUBLIC COMPLAINT INTO A CASE (19 Oct 2026). Assigned: customer_support (the case and its
-- answer); marketing reads the comments and raises the handoff. Founder ledger 1003 stage 2, contribution CS-C13:
-- "Monitor public reviews and social complaints and answer them within the service levels".
--
-- MEASURED 19 Oct 2026 (repo + production, read-only): marketing's comment inbox (the_marketing_seat_answers_comments_
-- on_every_channel.sql, _shared/marketing_social_*.ts) classifies every public comment and raises social.escalation
-- (marketing -> customer_support, reply_within 24 h) for a complaint, a dispute, a legal threat, a request for a person
-- or a draft that failed its guards. That handoff waited in the seat's inbox (fn_marketing_social_handoff_waits) and
-- nothing turned it into a support case: no case reference, no category, not in the weekly review, no clock.
-- marketing.reputation (fn_marketing_reputation) asks customers for public reviews and snapshots the rating; it reads
-- no public review text, so there is nothing of it to convert here (said so it is not assumed covered).
-- social_message holds 0 rows today: the path is built against the shape.
--
-- WHAT THIS ADDS:
--   * support_case.channel admits 'social' (a public comment is its own channel).
--   * customer_support.public_complaints, every 15 minutes, fn_customer_support_public_complaint_tick(). Code, no model:
--       open     every social.escalation in the seat's inbox without a case gets one: party unknown, party_id
--                social:<platform>:<handle>, category complaint when marketing classified it a complaint, topic tags
--                (social, platform, classification); the case reference is written back on the handoff;
--       answer   when the case is closed (a person or the seat answered it privately), the handoff gets answered_at
--                and the answer, which is what marketing's own closer (fn_marketing_social_handoffs_close) waits for;
--       clock    still unanswered 20 hours after it arrived (4 hours before the 24 h service level): the CEO is told
--                once (fn_support_report_to_ceo), never after the fact only.
-- qd.duty_fixtures = 'on' reads only handoffs whose text starts 'ZZ DEMO'.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_turns_every_public_complaint_into_a_case.sql --apply --ddl

alter table public.support_case drop constraint if exists support_case_channel_ck;
alter table public.support_case add constraint support_case_channel_ck
  check (channel is null or channel in ('whatsapp', 'email', 'widget', 'portal', 'phone', 'internal', 'social'));

create or replace function public.fn_customer_support_public_complaint_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  h record; v_ref text; c public.support_case; v_r jsonb; n_open int := 0; n_answered int := 0; n_ceo int := 0;
begin
  for h in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'pending'
              and a.detail->>'type' = 'social.escalation'
              and (coalesce(a.detail->>'text', '') like 'ZZ DEMO%') = v_fx
            order by a.id for update skip locked loop
    v_ref := h.detail->>'case_ref';
    if v_ref is null then
      v_ref := public.fn_support_case_new_ref();
      insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, owner_role_id,
                                       channel, category, topic_tags)
      values (v_ref, 'unknown', 'social:' || coalesce(h.detail->>'platform', '?') || ':' || coalesce(h.detail->>'handle', '?'),
              'Social (' || coalesce(h.detail->>'platform', '?') || '): ' || left(coalesce(h.detail->>'text', '(no text)'), 4000),
              'open', false, 'customer_support', 'social',
              case when h.detail->>'classification' = 'complaint' then 'complaint' end,
              array_remove(array['social', h.detail->>'platform', h.detail->>'classification'], null));
      update public.agent_actions set detail = detail || jsonb_build_object('case_ref', v_ref, 'case_opened_at', now()) where id = h.id;
      n_open := n_open + 1;
      continue;
    end if;

    select * into c from public.support_case where case_ref = v_ref;
    if c.state = 'closed' and not (h.detail ? 'answered_at') then
      update public.agent_actions
         set detail = detail || jsonb_build_object('answered_at', now(), 'answered_by', 'customer_support',
                                                   'answer', coalesce(c.resolution, c.close_reason))
       where id = h.id;
      n_answered := n_answered + 1;
    elsif not v_fx and c.state <> 'closed' and h.created_at < now() - interval '20 hours' then
      v_r := public.fn_support_report_to_ceo('public_complaint_due:' || v_ref, 'elevated',
        'A public ' || coalesce(h.detail->>'classification', 'complaint') || ' on ' || coalesce(h.detail->>'platform', 'social media')
          || ' is 4 hours from its 24 h service level unanswered (case ' || v_ref || ')',
        jsonb_build_object('case_ref', v_ref, 'handoff_id', h.id, 'platform', h.detail->>'platform', 'handle', h.detail->>'handle',
                           'text', left(coalesce(h.detail->>'text', ''), 1000), 'arrived_at', h.created_at),
        jsonb_build_array('case opened by customer_support', 'marketing acknowledged it publicly'),
        'Decide the private answer to this commenter and have customer_support give it before the 24 h service level.',
        p_case_ref => v_ref);
      if coalesce((v_r->>'ok')::boolean, false) and not coalesce((v_r->>'duplicate')::boolean, false) then n_ceo := n_ceo + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'cases_opened', n_open, 'answered', n_answered, 'ceo_told_before_lapse', n_ceo);
end $fn$;
revoke execute on function public.fn_customer_support_public_complaint_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_public_complaint_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.public_complaints', 'customer_support', interval '15 minutes', 'fn_customer_support_public_complaint_tick',
   'CS-C13: every public complaint marketing escalates (social.escalation) becomes a support case, its answer is written back for marketing to close, and the CEO is told before the 24 h service level lapses',
   'scripts/sql/customer_support_turns_every_public_complaint_into_a_case.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
