-- EVERY REAL OUTCOME LANDS ON THE SEAT THAT DECIDED IT, WITH ITS REASON. Seat: it_engineer (shared platform,
-- every seat). 29 Sep 2026, founder_instruction 1009 upgrade 3 ("learning from outcomes"). Builds on #1004
-- (a_decision_names_the_recalled_case_it_followed.sql) and every_judgement_learns_from_its_outcome.sql; it
-- does not duplicate either.
--
-- WHAT WAS ALREADY WIRED (every_judgement_learns_from_its_outcome.sql, trg_judgement_outcome): a quote won or
-- lost at reveal, an inquiry converted or abandoned, a complaint answered, a supplier who stayed silent after a
-- reveal (supplier_response_watch), a post's 7-day engagement against the median.
--
-- WHAT WAS MISSING (read from the schema mirror, 29 Sep 2026):
--   * a CUSTOMER RATING (public.reviews) reached no judgement and no case at all;
--   * a COMPLAINT only closed its own ticket as "resolved" (correct); it never counted against the decision the
--     customer was complaining about;
--   * a SUPPLIER WHO LEFT (an unsubscribe in email_suppressions for a supplier's address) reached nothing;
--   * a CAMPAIGN'S CONVERSION (marketing_first_touch: a lead whose first touch was one of the campaign's posts)
--     reached nothing; only engagement did;
--   * a wrong outcome on an EXISTING case wrote its outcome text and nothing else, so recall showed the case
--     as a plain "outcome:" line with no lesson. The reason never became a lesson.
--
-- WHAT THIS CHANGES
--   1. seat_judgement.outcome_kind and outcome_reason: what happened (rating, complaint, supplier_left,
--      campaign_converted, campaign_not_converted, ...) and why, separate from the free outcome text.
--   2. fn_outcome_record(table, id, kind, correct, reason, default_seat, case_kind, situation): lays the outcome
--      through the existing fn_judgement_outcome (so seat_learning_daily counts it), names the seat that
--      DECIDED (the latest judgement's seat on that subject; the default only when no judgement exists), and,
--      when the outcome went wrong, appends "Outcome <kind>: <reason>" to the case's lessons. precedentBlock
--      (case_recall.ts) prints lessons, so the next similar case recalls it. Callable by a seat (service_role)
--      for an outcome no trigger sees, e.g. a refund decision later reversed.
--   3. trg_outcome_learning on reviews, complaint_tickets, email_suppressions, marketing_first_touch and the
--      7-day marketing_post_metric: the four missing outcomes above. A failure is written to
--      seat_case_memory_miss and never fails the write that caused it.
--
-- WHAT IT DOES NOT CHANGE. trg_judgement_outcome, fn_judgement_outcome and fn_judgement_decided are untouched.
-- A complaint is laid on a decision ONLY when the complainant has exactly one inquiry in the 90 days before it:
-- the ticket carries an e-mail and no subject, and a guess across two inquiries would teach the wrong one.
-- ponytail: that 90-day single-inquiry rule; a complaint form that names its inquiry replaces it.
--
-- Pending: scripts/sql/pending/every_real_outcome_lands_on_the_seat_that_decided_it_with_its_reason.txt.
-- Proved by: scripts/eval/outcomes_and_cross_seat_challenge_proof.mjs (one aborted transaction, ZZ DEMO rows).
-- Prevented by: scripts/checks/every_real_outcome_lands_on_the_seat_that_decided_it.test.mjs.

alter table public.seat_judgement add column if not exists outcome_kind text;
alter table public.seat_judgement add column if not exists outcome_reason text;
comment on column public.seat_judgement.outcome_kind is 'What happened to the decision: rating, complaint, supplier_left, campaign_converted, campaign_not_converted, or a seat''s own kind (fn_outcome_record).';
comment on column public.seat_judgement.outcome_reason is 'Why the outcome is what it is, in words a later recall can learn from.';

create or replace function public.fn_outcome_record(p_table text, p_id text, p_kind text, p_correct boolean, p_reason text,
  p_default_seat text default null, p_case_kind text default null, p_situation text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_seat text; v_n integer; v_lesson text;
begin
  if coalesce(btrim(p_kind), '') = '' or coalesce(btrim(p_reason), '') = '' then
    raise exception 'an outcome names its kind and its reason' using errcode = '22023';
  end if;
  -- THE SEAT THAT DECIDED: the latest judgement on this subject. The default only opens a case where none decided.
  select j.seat into v_seat from public.seat_judgement j
   where j.subject_table = p_table and j.subject_id = p_id order by j.id desc limit 1;
  v_seat := coalesce(v_seat, p_default_seat);
  v_n := public.fn_judgement_outcome(p_table, p_id, p_kind || ': ' || p_reason, p_correct, true, v_seat, p_case_kind, p_situation);
  update public.seat_judgement set outcome_kind = p_kind, outcome_reason = left(p_reason, 1000)
   where subject_table = p_table and subject_id = p_id;
  if p_correct is false then
    v_lesson := left('Outcome ' || p_kind || ': ' || p_reason, 500);
    update public.seat_case_memory
       set lessons = case when v_lesson = any (lessons) then lessons else lessons || v_lesson end, updated_at = now()
     where source_table = p_table and source_id = p_id;
  end if;
  return jsonb_build_object('judgements', v_n, 'seat', v_seat, 'kind', p_kind, 'correct', p_correct);
end $fn$;
revoke execute on function public.fn_outcome_record(text, text, text, boolean, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_outcome_record(text, text, text, boolean, text, text, text, text) to service_role;

create or replace function public.trg_outcome_learning()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  n jsonb := to_jsonb(new);
  v_inq uuid; v_cnt integer; v_camp public.marketing_campaign; v_leads integer; v_posts integer; v_reason text; v_ok boolean;
  q record; l record;
begin
  begin
    if tg_table_name = 'reviews' then
      -- A CUSTOMER RATING: 4-5 right, 1-2 wrong, 3 recorded without a verdict. It lands on the inquiry (the match),
      -- the rated supplier's quote on it, and the supplier.
      v_ok := case when (n->>'rating')::int >= 4 then true when (n->>'rating')::int <= 2 then false end;
      v_reason := 'rated ' || (n->>'rating') || '/5' || coalesce(': ' || left(nullif(btrim(n->>'comment'), ''), 300), '');
      if n->>'inquiry_id' is not null then
        perform public.fn_outcome_record('inquiries', n->>'inquiry_id', 'rating', v_ok, v_reason, 'sales_engineer', 'inquiry', null);
        for q in select id from public.quotes where inquiry_id::text = n->>'inquiry_id' and supplier_id::text = n->>'supplier_id' loop
          perform public.fn_outcome_record('quotes', q.id::text, 'rating', v_ok, v_reason, 'sales_engineer', 'quote', null);
        end loop;
      end if;
      if n->>'supplier_id' is not null then
        perform public.fn_outcome_record('leads', n->>'supplier_id', 'rating', v_ok, v_reason, 'sales_engineer', 'supplier', null);
      end if;

    elsif tg_table_name = 'complaint_tickets' then
      -- A COMPLAINT counts against the decision it is about, only when that decision is unambiguous.
      select count(*), min(i.id::text)::uuid into v_cnt, v_inq
        from public.inquiries i join public.customers u on u.id = i.customer_id
       where lower(u.email) = lower(n->>'email') and i.created_at > (n->>'created_at')::timestamptz - interval '90 days'
         and i.created_at <= (n->>'created_at')::timestamptz;
      if v_cnt = 1 then
        perform public.fn_outcome_record('inquiries', v_inq::text, 'complaint', false,
          'complaint ' || (n->>'ticket_no') || ': ' || left(n->>'message', 400), 'sales_engineer', 'inquiry', null);
      end if;

    elsif tg_table_name = 'email_suppressions' then
      -- A SUPPLIER WHO LEFT: his address unsubscribed. Every decision about him learns it.
      for l in select id from public.leads where lower(email) = lower(n->>'email') loop
        perform public.fn_outcome_record('leads', l.id::text, 'supplier_left', false,
          'unsubscribed (' || coalesce(n->>'reason', 'unsubscribe') || coalesce(', ' || (n->>'source'), '') || ')',
          'sales_engineer', 'supplier', 'supplier ' || l.id || ' stopped receiving our messages');
      end loop;

    elsif tg_table_name = 'marketing_first_touch' then
      -- A CAMPAIGN THAT CONVERTED: a lead's first touch was one of its posts.
      select c.* into v_camp from public.marketing_campaign c join public.marketing_post p on p.campaign_id = c.id
       where p.id = (n->>'post_id')::bigint and not p.is_demo and not c.is_demo;
      if v_camp.id is not null then
        select count(*) into v_leads from public.marketing_first_touch f join public.marketing_post p on p.id = f.post_id
         where p.campaign_id = v_camp.id;
        perform public.fn_outcome_record('marketing_campaign', v_camp.id::text, 'campaign_converted', true,
          v_leads || ' lead(s) first touched its posts, latest lead ' || (n->>'lead_id') || ' via post ' || (n->>'post_id')
          || coalesce(' (' || (n->>'utm_source') || ')', ''), 'marketing', 'campaign',
          concat_ws(' | ', v_camp.campaign_key, v_camp.theme, v_camp.title));
      end if;

    elsif tg_table_name = 'marketing_post_metric' then
      -- A CAMPAIGN THAT DID NOT CONVERT: seven days after one of its posts, still no lead from any of them.
      -- A first touch later replaces it with campaign_converted.
      if n->>'checkpoint' = '7d' and n->>'metric' = 'engagement_rate_by_followers' then
        select c.* into v_camp from public.marketing_campaign c join public.marketing_post p on p.campaign_id = c.id
         where p.id = (n->>'post_id')::bigint and not p.is_demo and not c.is_demo;
        if v_camp.id is not null and not exists (select 1 from public.marketing_first_touch f join public.marketing_post p on p.id = f.post_id
                                                  where p.campaign_id = v_camp.id) then
          select count(*) into v_posts from public.marketing_post p where p.campaign_id = v_camp.id and p.published_at is not null;
          perform public.fn_outcome_record('marketing_campaign', v_camp.id::text, 'campaign_not_converted', false,
            'no lead first touched any of its ' || v_posts || ' published post(s) seven days after post ' || (n->>'post_id'),
            'marketing', 'campaign', concat_ws(' | ', v_camp.campaign_key, v_camp.theme, v_camp.title));
        end if;
      end if;
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error)
    values (tg_table_name, coalesce(n->>'id', n->>'email', n->>'post_id'), 'outcome learning: ' || sqlerrm);
  end;
  return null;
end $fn$;
revoke execute on function public.trg_outcome_learning() from public, anon, authenticated;

drop trigger if exists z92_outcome_learning on public.reviews;
create trigger z92_outcome_learning after insert on public.reviews for each row execute function public.trg_outcome_learning();
drop trigger if exists z92_outcome_learning on public.complaint_tickets;
create trigger z92_outcome_learning after insert on public.complaint_tickets for each row execute function public.trg_outcome_learning();
drop trigger if exists z92_outcome_learning on public.email_suppressions;
create trigger z92_outcome_learning after insert on public.email_suppressions for each row execute function public.trg_outcome_learning();
drop trigger if exists z92_outcome_learning on public.marketing_first_touch;
create trigger z92_outcome_learning after insert on public.marketing_first_touch for each row execute function public.trg_outcome_learning();
drop trigger if exists z92_outcome_learning on public.marketing_post_metric;
create trigger z92_outcome_learning after insert on public.marketing_post_metric for each row execute function public.trg_outcome_learning();
