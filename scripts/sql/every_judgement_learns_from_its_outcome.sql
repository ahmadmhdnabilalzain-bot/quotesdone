-- EVERY JUDGEMENT LEARNS FROM ITS OUTCOME — the learning loop, closed. Seat: it_engineer (shared
-- platform, for all six seats). 23 Sep 2026.
--
-- WHAT WAS MEASURED (readiness audit, 23 Sep 2026; the founder's top priority is six seats that
-- measurably improve over three months). The loop scored 1/5:
--   * seat_case_memory held 460 rows, mostly it_engineer findings and accountant classifications;
--     sales_engineer had 13 cases with 0 outcomes, customer_support and marketing none.
--   * fn_case_recall existed and nothing on main called it (PR #889 wires it; this file builds on #889).
--   * outcome_record, reasoning_knowledge_candidate and knowledge_exam_results were empty.
--   * Nothing recorded WHICH judgement a seat made, so no outcome could be laid against it and no
--     accuracy could be measured.
--
-- WHAT THIS FILE BUILDS, one section per part of the loop:
--   1. public.seat_judgement — every judgement, opened BY THE RECALL (case_recall.ts recallCases, which
--      think() and every deterministic decision path call) with the memory it recalled (`recall`), closed
--      by think() with what it decided (fn_judgement_decided), and given its real outcome by:
--   2. OUTCOME WRITE-BACK — one trigger function (trg_judgement_outcome), one mapping block per table where
--      an outcome lands: a quote won or lost at reveal, an inquiry converted or abandoned, a complaint
--      resolved, a card dispute won or lost, a message delivered or failed, a supplier who responded or
--      stayed silent, a forecast that held or missed, a post that beat or fell short of the seat's median,
--      an expense re-classified, an IT finding resolved or reopened. The outcome lands on the judgement AND
--      on the case memory, so the next recall carries it.
--   3. LESSONS — fn_lesson_clusters groups a seat's cases that have outcomes BY VECTOR DISTANCE (gte-small,
--      the 0.84 floor case memory measured), never by words; _shared/learning_loop.ts asks think() what each
--      group teaches, at high stakes so a model of ANOTHER family verifies it (#877). The verdict decides:
--      agreed -> the candidate is approved and promoted into agent_knowledge (the seat's own knowledge,
--      layer 'experience') and onto the cases' lessons; disagreed -> rejected; no reviewer -> pending.
--      Under the model hold the question is held and reasoned when the hold lifts; nothing is distilled
--      from words.
--   4. THE METRIC — seat_learning_daily: per seat, per day, trailing-30-day decision accuracy against
--      outcomes, recall coverage and lessons approved. A fall of 10 points week on week, on at least 10
--      outcomes each side, opens an it_engineer finding; recovery closes it.
--   5. THE CEO SEES IT — the weekly report carries a LEARNING section and figures.learning.
--
-- WHAT THIS FILE DOES NOT DO. outcome_record is KPI-shaped (expected metric, baseline, due date) and is
-- left as it is: a judgement's outcome is not a KPI movement. knowledge_exam_results is not written here.
-- A message's outcome is laid on judgements whose subject IS that notification, and a failed message
-- becomes a customer_support case; a reply produced from a held question is not traced back to its
-- notification row (the delivery does not record the notification id on the held row).
--
-- Follows every_seat_remembers_its_cases_and_recalls_them_by_meaning.sql and every_seat_reasons_before_it_answers.sql.
-- Pending: scripts/sql/pending/every_judgement_learns_from_its_outcome.txt.
-- Proved by: node --test scripts/checks/every_judgement_carries_its_recall_and_its_outcome.test.mjs
-- (offline wiring + an aborted-transaction probe against production with ZZ DEMO subjects).

-- ── 1. THE JUDGEMENT LEDGER ─────────────────────────────────────────────────────────────────────
create table if not exists public.seat_judgement (
  id              bigint generated always as identity primary key,
  seat            text not null check (seat in ('ceo','customer_support','sales_engineer','accountant','it_engineer','marketing')),
  surface         text not null check (btrim(surface) <> ''),
  subject         jsonb,
  subject_table   text,
  subject_id      text,
  question        text,
  -- The recall record: what case memory returned before the seat decided (case_recall.ts recallTrace).
  -- Nullable ON PURPOSE: a writer that bypasses fn_judgement_record leaves it null, and
  -- fn_judgement_without_recall() counts exactly those rows. A NOT NULL here would make the check
  -- unfailable, which is not the same as the rule holding.
  recall          jsonb,
  status          text not null default 'recalled' check (status in ('recalled','answered','held')),
  decision        text,
  confidence      numeric,
  model           text,
  decided_at      timestamptz,
  outcome         text,
  outcome_correct boolean,
  finalised       boolean not null default false,
  outcome_at      timestamptz,
  made_at         timestamptz not null default now()
);
create index if not exists seat_judgement_subject_idx on public.seat_judgement (subject_table, subject_id) where subject_table is not null;
create index if not exists seat_judgement_seat_outcome_idx on public.seat_judgement (seat, outcome_at);
alter table public.seat_judgement enable row level security;
drop policy if exists seat_judgement_service_role_only on public.seat_judgement;
create policy seat_judgement_service_role_only on public.seat_judgement as permissive for all to public using (false) with check (false);
revoke all on public.seat_judgement from anon, authenticated;
comment on table public.seat_judgement is
  'Every judgement a seat makes, opened by its recall (what case memory returned), closed with its decision, and given its real outcome by trg_judgement_outcome. The learning loop measures accuracy from it.';

-- What a subject is about, as (table, id). The keys are the ones the think() callers already pass.
create or replace function public.fn_judgement_subject(p jsonb, out t text, out i text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when p ? 'table' and p ? 'id' then p->>'table'
              when p ? 'quote_id' then 'quotes'
              when p ? 'inquiry_id' then 'inquiries'
              when p ? 'intake_id' then 'inquiry_intake'
              when p ? 'command_id' then 'ceo_command'
              when p ? 'notification_id' then 'notifications'
              when p ? 'expense_id' then 'expense_entries'
              when p ? 'issue_key' then 'it_engineer_finding'
              when p ? 'message_id' then 'social_message' end,
         coalesce(p->>'id', p->>'quote_id', p->>'inquiry_id', p->>'intake_id', p->>'command_id',
                  p->>'notification_id', p->>'expense_id', p->>'issue_key', p->>'message_id')
   where p is not null and jsonb_typeof(p) = 'object'
$fn$;
revoke execute on function public.fn_judgement_subject(jsonb) from public, anon, authenticated;

create or replace function public.fn_judgement_record(p_seat text, p_surface text, p_subject jsonb, p_question text, p_recall jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; s record;
begin
  if p_recall is null or jsonb_typeof(p_recall) <> 'object' or not (p_recall ? 'available') then
    raise exception 'a judgement is recorded with its recall, or not at all' using errcode = '22023';
  end if;
  select * into s from public.fn_judgement_subject(p_subject);
  insert into public.seat_judgement (seat, surface, subject, subject_table, subject_id, question, recall)
  values (p_seat, p_surface, p_subject, s.t, s.i, left(p_question, 2000), p_recall)
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_judgement_record(text, text, jsonb, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_judgement_record(text, text, jsonb, text, jsonb) to service_role;

create or replace function public.fn_judgement_decided(p_id bigint, p_status text, p_decision text, p_confidence numeric, p_model text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.seat_judgement
     set status = p_status, decision = left(p_decision, 2000), confidence = p_confidence, model = p_model, decided_at = now()
   where id = p_id and p_status in ('answered','held');
  return found;
end $fn$;
revoke execute on function public.fn_judgement_decided(bigint, text, text, numeric, text) from public, anon, authenticated;
grant execute on function public.fn_judgement_decided(bigint, text, text, numeric, text) to service_role;

-- The production probe for the rule "no judgement without its recall record". 0 is the only pass.
create or replace function public.fn_judgement_without_recall()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'judgements', count(*),
    'without_recall', count(*) filter (where recall is null or jsonb_typeof(recall) <> 'object' or not (recall ? 'available')),
    'recall_unavailable', count(*) filter (where recall ? 'available' and (recall->>'available')::boolean is false),
    'ids', coalesce((jsonb_agg(id order by id) filter (where recall is null or jsonb_typeof(recall) <> 'object' or not (recall ? 'available'))), '[]'::jsonb))
  from public.seat_judgement
$fn$;
revoke execute on function public.fn_judgement_without_recall() from public, anon, authenticated;
grant execute on function public.fn_judgement_without_recall() to service_role;

-- ── 2. OUTCOME WRITE-BACK ───────────────────────────────────────────────────────────────────────
-- Lays an outcome on every judgement about (table, id), and on the case memory: an existing case gets
-- the outcome; with p_seat given and no case yet, one is opened (a judgement case). p_seat null means
-- the source already has its own case mapping (fn_case_from_*), which keeps its outcome text.
create or replace function public.fn_judgement_outcome(p_table text, p_id text, p_outcome text, p_correct boolean,
  p_finalised boolean default true, p_seat text default null, p_kind text default null, p_situation text default null)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n integer;
begin
  update public.seat_judgement
     set outcome = left(p_outcome, 1000), outcome_correct = p_correct, finalised = finalised or coalesce(p_finalised, true), outcome_at = now()
   where subject_table = p_table and subject_id = p_id;
  get diagnostics n = row_count;
  if p_seat is not null then
    update public.seat_case_memory
       set outcome = left(p_outcome, 1000), finalised = finalised or coalesce(p_finalised, true),
           finalised_at = coalesce(finalised_at, case when p_finalised then now() end), updated_at = now()
     where source_table = p_table and source_id = p_id;
    if not found and p_situation is not null then
      perform public.fn_case_remember(p_seat, coalesce(p_kind, p_table), p_table, p_id, null, p_situation,
        null, null, p_outcome, coalesce(p_finalised, true), '{}', null,
        case when p_correct is false then 'Went wrong: ' || p_outcome end);
    end if;
  end if;
  return n;
end $fn$;
revoke execute on function public.fn_judgement_outcome(text, text, text, boolean, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_judgement_outcome(text, text, text, boolean, boolean, text, text, text) to service_role;

create or replace function public.trg_judgement_outcome()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  n jsonb := to_jsonb(new);
  o jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  changed boolean;
  v_prev public.target_verdict; v_median numeric; v_seat text; v_fail boolean; v_ok boolean;
begin
  begin
    if tg_table_name = 'quotes' then
      -- A quote won or lost at reveal (sales_engineer matched it).
      if n->>'status' is distinct from o->>'status' then
        if n->>'status' in ('revealed','won','accepted') then
          perform public.fn_judgement_outcome('quotes', n->>'id', 'won: ' || (n->>'status'), true, true, 'sales_engineer', 'quote',
            concat_ws(' | ', 'quote AED ' || (n->>'quote_amount'), 'for inquiry ' || (n->>'inquiry_id'), left(n->>'scope', 300)));
        elsif n->>'status' in ('lost','rejected','not_selected','declined','expired','withdrawn') then
          perform public.fn_judgement_outcome('quotes', n->>'id', 'lost: ' || (n->>'status'), false, true, 'sales_engineer', 'quote',
            concat_ws(' | ', 'quote AED ' || (n->>'quote_amount'), 'for inquiry ' || (n->>'inquiry_id'), left(n->>'scope', 300)));
        end if;
      end if;

    elsif tg_table_name = 'inquiries' then
      if n->>'status' is distinct from o->>'status' then
        if n->>'status' in ('revealed','won','completed','closed') then
          perform public.fn_judgement_outcome('inquiries', n->>'id', 'converted: ' || (n->>'status'), true, true, 'sales_engineer', 'inquiry', null);
          -- At reveal every other quote on the inquiry lost.
          if n->>'status' = 'revealed' then
            perform public.fn_judgement_outcome('quotes', q.id::text, 'lost at reveal', false, true, 'sales_engineer', 'quote',
                      concat_ws(' | ', 'quote AED ' || q.quote_amount, 'for inquiry ' || q.inquiry_id, left(q.scope, 300)))
               from public.quotes q
              where q.inquiry_id::text = n->>'id' and coalesce(q.status, '') not in ('revealed','won','accepted');
          end if;
        elsif n->>'status' in ('expired','cancelled','canceled','abandoned','lost') then
          perform public.fn_judgement_outcome('inquiries', n->>'id', 'abandoned: ' || (n->>'status') || coalesce('; ' || (n->>'lost_reason'), ''), false, true, 'sales_engineer', 'inquiry', null);
        end if;
      end if;

    elsif tg_table_name = 'complaint_tickets' then
      if n->>'final_response_at' is not null and o->>'final_response_at' is null then
        perform public.fn_judgement_outcome('complaint_tickets', n->>'id', 'resolved: ' || left(coalesce(n->>'final_response', ''), 400), true, true, null);
      end if;

    elsif tg_table_name = 'stripe_dispute' then
      if n->>'status' is distinct from o->>'status' and n->>'status' in ('won','lost') then
        perform public.fn_judgement_outcome('stripe_dispute', n->>'id', 'dispute ' || (n->>'status') || coalesce(': ' || (n->>'outcome'), ''),
          n->>'status' = 'won', true, 'accountant', 'dispute',
          concat_ws(' | ', 'card dispute ' || coalesce(n->>'reason', 'no reason'), (n->>'currency') || ' ' || ((n->>'amount_fils')::numeric / 100)));
      end if;

    elsif tg_table_name = 'notifications' then
      changed := n->>'status' is distinct from o->>'status' or n->>'provider_status' is distinct from o->>'provider_status';
      v_fail := n->>'status' in ('failed','bounced') or n->>'provider_status' in ('undelivered','failed','bounced');
      v_ok := n->>'provider_status' in ('delivered','read');
      v_seat := case when n->>'sender' in ('ceo','customer_support','sales_engineer','accountant','it_engineer','marketing') then n->>'sender' else 'customer_support' end;
      if changed and (v_fail or v_ok) then
        -- A failure becomes a case (a lesson source); a delivery only closes its judgements.
        perform public.fn_judgement_outcome('notifications', n->>'id',
          case when v_fail then 'failed: ' || coalesce(n->>'provider_status', n->>'status') || coalesce(' ' || (n->>'provider_error_code'), '') || coalesce(' ' || left(n->>'last_error', 200), '')
               else 'delivered: ' || (n->>'provider_status') end,
          not v_fail, true, case when v_fail then v_seat end, 'message',
          concat_ws(' | ', coalesce(n->>'channel', 'email') || ' message', 'type ' || (n->>'type'), 'kind ' || (n->>'kind'), 'to ' || (n->>'to_role')));
      end if;

    elsif tg_table_name = 'supplier_response_watch' then
      if n->>'first_response_at' is not null and o->>'first_response_at' is null then
        perform public.fn_judgement_outcome('supplier_response_watch', n->>'id', 'supplier responded via ' || coalesce(n->>'response_channel', 'unknown'), true, true,
          'customer_support', 'supplier_response', 'supplier chased after a reveal; ' || jsonb_array_length(coalesce(n->'attempts', '[]'::jsonb)) || ' attempt(s)');
      elsif n->>'closed_at' is not null and o->>'closed_at' is null and n->>'first_response_at' is null then
        perform public.fn_judgement_outcome('supplier_response_watch', n->>'id', 'supplier stayed silent: ' || coalesce(n->>'close_reason', 'closed'), false, true,
          'customer_support', 'supplier_response', 'supplier chased after a reveal; ' || jsonb_array_length(coalesce(n->'attempts', '[]'::jsonb)) || ' attempt(s)');
      end if;

    elsif tg_table_name = 'target_verdict' then
      -- A forecast is judged by the next one: the earlier verdict held (hit) or changed (miss).
      select * into v_prev from public.target_verdict
       where contract_id = (n->>'contract_id')::bigint and id < (n->>'id')::bigint order by id desc limit 1;
      if v_prev.id is not null and v_prev.verdict <> 'CANNOT_ASSESS' and n->>'verdict' <> 'CANNOT_ASSESS' then
        perform public.fn_judgement_outcome('target_verdict', v_prev.id::text,
          case when v_prev.verdict = n->>'verdict' then 'forecast held: ' else 'forecast missed: ' end || v_prev.verdict || ' -> ' || (n->>'verdict'),
          v_prev.verdict = n->>'verdict', true, 'ceo', 'forecast',
          concat_ws(' | ', 'target contract ' || v_prev.contract_id || ' forecast ' || v_prev.verdict, left(v_prev.verdict_reason, 400),
                    'base scenario ' || v_prev.scenario_base, 'binding stage ' || v_prev.binding_stage));
      end if;

    elsif tg_table_name = 'marketing_post_metric' then
      -- A post's performance, judged at seven days against the seat's own median of earlier posts.
      if n->>'checkpoint' = '7d' and n->>'metric' = 'engagement_rate_by_followers' and n->>'value' is not null
         and not exists (select 1 from public.marketing_post p where p.id = (n->>'post_id')::bigint and p.is_demo) then
        select percentile_cont(0.5) within group (order by m.value) into v_median
          from public.marketing_post_metric m join public.marketing_post p on p.id = m.post_id
         where m.checkpoint = '7d' and m.metric = 'engagement_rate_by_followers' and m.value is not null
           and not p.is_demo and m.post_id <> (n->>'post_id')::bigint;
        perform public.fn_judgement_outcome('marketing_post', n->>'post_id',
          'engagement ' || (n->>'value') || ' at 7d on ' || (n->>'platform') || coalesce(' vs median ' || round(v_median, 4), ' (first measured post)'),
          case when v_median is null then null else (n->>'value')::numeric >= v_median end, true, 'marketing', 'post_performance',
          (select concat_ws(' | ', p.title, left(p.text_en, 400), 'channels ' || array_to_string(p.channels, ','), p.rationale)
             from public.marketing_post p where p.id = (n->>'post_id')::bigint));
      end if;

    elsif tg_table_name = 'expense_entries' then
      if o->>'category' is not null and n->>'category' is distinct from o->>'category' then
        perform public.fn_judgement_outcome('expense_entries', n->>'id',
          'corrected: re-classified from ' || (o->>'category') || ' to ' || coalesce(n->>'category', 'unclassified'), false, true, null);
      end if;

    elsif tg_table_name = 'it_engineer_finding' then
      if n->>'closed_at' is not null and o->>'closed_at' is null then
        perform public.fn_judgement_outcome('it_engineer_finding', n->>'issue_key', 'resolved: ' || coalesce(n->>'close_note', 'closed'), true, true, null);
      elsif n->>'closed_at' is null and o->>'closed_at' is not null then
        perform public.fn_judgement_outcome('it_engineer_finding', n->>'issue_key', 'reopened: the fix did not hold', false, true, null);
      end if;
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error)
    values (tg_table_name, coalesce(n->>'id', n->>'issue_key'), 'judgement outcome: ' || sqlerrm);
  end;
  return null;
end $fn$;
revoke execute on function public.trg_judgement_outcome() from public, anon, authenticated;

drop trigger if exists z91_judgement_outcome on public.quotes;
create trigger z91_judgement_outcome after update of status on public.quotes for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.inquiries;
create trigger z91_judgement_outcome after update of status on public.inquiries for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.complaint_tickets;
create trigger z91_judgement_outcome after update of final_response_at on public.complaint_tickets for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.stripe_dispute;
create trigger z91_judgement_outcome after update of status on public.stripe_dispute for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.notifications;
create trigger z91_judgement_outcome after update of status, provider_status on public.notifications for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.supplier_response_watch;
create trigger z91_judgement_outcome after update of first_response_at, closed_at on public.supplier_response_watch for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.target_verdict;
create trigger z91_judgement_outcome after insert on public.target_verdict for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.marketing_post_metric;
create trigger z91_judgement_outcome after insert on public.marketing_post_metric for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.expense_entries;
create trigger z91_judgement_outcome after update of category on public.expense_entries for each row execute function public.trg_judgement_outcome();
drop trigger if exists z91_judgement_outcome on public.it_engineer_finding;
create trigger z91_judgement_outcome after update of closed_at on public.it_engineer_finding for each row execute function public.trg_judgement_outcome();

-- ── 3. LESSONS ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.seat_lesson_cluster (
  cluster_key  text primary key,
  seat         text not null,
  case_ids     bigint[] not null check (cardinality(case_ids) >= 3),
  filed_at     timestamptz not null default now(),
  candidate_id bigint references public.reasoning_knowledge_candidate(id),
  verdict      text
);
alter table public.seat_lesson_cluster enable row level security;
drop policy if exists seat_lesson_cluster_service_role_only on public.seat_lesson_cluster;
create policy seat_lesson_cluster_service_role_only on public.seat_lesson_cluster as permissive for all to public using (false) with check (false);
revoke all on public.seat_lesson_cluster from anon, authenticated;
comment on table public.seat_lesson_cluster is
  'A group of a seat''s cases with outcomes, near each other by meaning (gte-small, >= 0.84), filed once for distillation into a lesson.';

-- Groups by VECTOR distance only. Greedy: the newest case with an outcome seeds a group of its nearest
-- same-seat neighbours above the floor; three or more make a group. Each case is filed once. Claims
-- what it returns (the insert), so two ticks never distil the same group. p_limit is PER SEAT.
-- ponytail: greedy seeds, newest first, 200 per seat; a proper clustering pass if a seat's cases outgrow it.
create or replace function public.fn_lesson_clusters(p_limit integer default 6, p_floor real default 0.84)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_seat text; seed record; v_ids bigint[]; v_used bigint[] := '{}'; v_out jsonb := '[]'::jsonb; v_key text; v_n int := 0;
begin
  select coalesce(array_agg(x), '{}') into v_used from public.seat_lesson_cluster c, unnest(c.case_ids) x;
  foreach v_seat in array array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing'] loop
    v_n := 0;   -- per seat: one busy seat never starves the others of their lessons
    for seed in
      select m.id, m.embedding from public.seat_case_memory m
       where m.seat = v_seat and m.outcome is not null and m.embedding is not null
         and m.updated_at > now() - interval '90 days' and m.id <> all(v_used)
       order by m.updated_at desc limit 200
    loop
      exit when v_n >= greatest(1, least(p_limit, 20));
      continue when seed.id = any(v_used);
      select array_agg(id) into v_ids from (
        select m.id from public.seat_case_memory m
         where m.seat = v_seat and m.outcome is not null and m.embedding is not null and m.id <> all(v_used)
           and 1 - (m.embedding <=> seed.embedding) >= p_floor
         order by m.embedding <=> seed.embedding limit 12) t;
      if cardinality(v_ids) >= 3 then
        v_key := v_seat || ':' || md5(array_to_string((select array_agg(x order by x) from unnest(v_ids) x), ','));
        insert into public.seat_lesson_cluster (cluster_key, seat, case_ids) values (v_key, v_seat, v_ids) on conflict do nothing;
        v_used := v_used || v_ids;
        v_n := v_n + 1;
        v_out := v_out || jsonb_build_object('seat', v_seat, 'cluster_key', v_key, 'cases',
          (select jsonb_agg(jsonb_build_object('case_id', m.id, 'case_kind', m.case_kind, 'situation', left(m.situation, 500),
                   'decision', left(m.decision, 300), 'outcome', left(m.outcome, 300), 'finalised', m.finalised,
                   'correction', m.correction) order by m.id)
             from public.seat_case_memory m where m.id = any(v_ids)));
      end if;
    end loop;
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_lesson_clusters(integer, real) from public, anon, authenticated;
grant execute on function public.fn_lesson_clusters(integer, real) to service_role;

-- The effect of a reasoned 'learning.distil' question (called by fn_reason_held_resolve after a replay,
-- and directly by learning_loop.ts when the model answered at once, with p_id null and the subject in
-- p_result). The cross-family verdict decides the candidate's status; approval promotes it.
create or replace function public.fn_reason_apply_learning__distil(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_subject jsonb; c public.seat_lesson_cluster; v_answer text; v_ver text; v_by text; v_status text; v_cand bigint; v_ak bigint;
begin
  select subject into v_subject from public.reasoning_held_question where id = p_id;
  v_subject := coalesce(v_subject, p_result->'subject');
  select * into c from public.seat_lesson_cluster where cluster_key = v_subject->>'cluster_key';
  if c.cluster_key is null then return jsonb_build_object('applied', false, 'reason', 'no such cluster'); end if;
  v_answer := btrim(coalesce(p_result->>'answer', ''));
  if v_answer = '' or p_result->>'status' <> 'answered' then return jsonb_build_object('applied', false, 'reason', 'no lesson'); end if;
  v_ver := coalesce(p_result->'verified'->>'status', 'not_run');
  v_by := p_result->'verified'->>'by';
  v_status := case when v_ver = 'agreed' and v_by is not null then 'approved' when v_ver = 'disagreed' then 'rejected' else 'pending_review' end;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values (c.seat, 'What do ' || cardinality(c.case_ids) || ' similar ' || c.seat || ' cases with known outcomes teach?', left(v_answer, 4000),
          (select jsonb_agg(jsonb_build_object('kind', 'case', 'case_id', x, 'cluster_key', c.cluster_key)) from unnest(c.case_ids) x),
          v_status, case when v_status <> 'pending_review' then 'cross_family:' || coalesce(v_by, 'unknown') end,
          case when v_status <> 'pending_review' then now() end)
  on conflict (finding_sha) do nothing
  returning id into v_cand;
  -- The same lesson text from another group is the same lesson: link this group to it, never to nothing.
  if v_cand is null then
    select id into v_cand from public.reasoning_knowledge_candidate where finding_sha = md5(lower(btrim(left(v_answer, 4000))));
  end if;
  update public.seat_lesson_cluster set candidate_id = v_cand, verdict = v_ver where cluster_key = c.cluster_key;
  if v_status = 'approved' and v_cand is not null
     and not exists (select 1 from public.agent_knowledge a where a.source_ref = 'lesson:' || v_cand) then
    insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
    values (c.seat, 'Lesson from ' || cardinality(c.case_ids) || ' cases [lesson#' || v_cand || ']', left(v_answer, 4000), 'experience',
            'lesson:' || v_cand, c.seat, 1, 'author_verified',
            'Distilled from cases ' || array_to_string(c.case_ids, ', ') || '; verified by a model of another family (' || v_by || ')')
    returning id into v_ak;
    update public.seat_case_memory set lessons = lessons || left(v_answer, 600), updated_at = now()
     where id = any(c.case_ids) and not (left(v_answer, 600) = any(lessons));
  end if;
  return jsonb_build_object('applied', true, 'candidate_id', v_cand, 'status', v_status, 'agent_knowledge_id', v_ak);
end $fn$;
revoke execute on function public.fn_reason_apply_learning__distil(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_learning__distil(bigint, jsonb) to service_role;

-- A lesson is retrievable by meaning once it has a vector; learning_loop.ts embeds it (gte-small).
create or replace function public.fn_lesson_unembedded(p_limit integer default 8)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'finding', r.finding)), '[]'::jsonb)
    from (select r.id, r.finding from public.reasoning_knowledge_candidate r
           join public.seat_lesson_cluster c on c.candidate_id = r.id
          where r.embedding_gte is null and r.status <> 'rejected' order by r.id limit greatest(1, least(p_limit, 20))) r
$fn$;
revoke execute on function public.fn_lesson_unembedded(integer) from public, anon, authenticated;
grant execute on function public.fn_lesson_unembedded(integer) to service_role;

create or replace function public.fn_lesson_embed_write(p_id bigint, p_embedding vector(384))
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.reasoning_knowledge_candidate set embedding_gte = p_embedding where id = p_id and embedding_gte is null;
  update public.agent_knowledge set embedding_gte = p_embedding, updated_at = now() where source_ref = 'lesson:' || p_id and embedding_gte is null;
  return true;
end $fn$;
revoke execute on function public.fn_lesson_embed_write(bigint, vector) from public, anon, authenticated;
grant execute on function public.fn_lesson_embed_write(bigint, vector) to service_role;

-- ── 4. THE METRIC ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.seat_learning_daily (
  seat               text not null,
  day                date not null,
  judgements_30d     integer not null,
  outcomes_30d       integer not null,
  correct_30d        integer not null,
  accuracy_30d       numeric,            -- null below one outcome: no accuracy is claimed from nothing
  recall_available_30d integer not null,
  cases_total        integer not null,
  cases_with_outcome integer not null,
  lessons_approved   integer not null,
  measured_at        timestamptz not null default now(),
  primary key (seat, day)
);
alter table public.seat_learning_daily enable row level security;
drop policy if exists seat_learning_daily_service_role_only on public.seat_learning_daily;
create policy seat_learning_daily_service_role_only on public.seat_learning_daily as permissive for all to public using (false) with check (false);
revoke all on public.seat_learning_daily from anon, authenticated;
comment on table public.seat_learning_daily is
  'Per seat, per day: trailing-30-day decision accuracy against real outcomes (seat_judgement), recall coverage, cases and approved lessons. The proof a seat is improving, or the finding that it is not.';

-- 10 points on at least 10 outcomes each side: below that a single outcome swings the figure by more
-- than the threshold, and a finding would be noise. A 'held' row is not counted: it is an attempt the
-- model could not complete (a held question replayed three times opens three rows, and only the attempt
-- that answered is a decision — independent review of this PR).
create or replace function public.fn_seat_learning_measure(p_day date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_day date := coalesce(p_day, (now() at time zone 'Asia/Dubai')::date); r public.seat_learning_daily; p public.seat_learning_daily;
  v_out jsonb := '[]'::jsonb; v_fell boolean;
begin
  insert into public.seat_learning_daily as d (seat, day, judgements_30d, outcomes_30d, correct_30d, accuracy_30d,
         recall_available_30d, cases_total, cases_with_outcome, lessons_approved)
  select s.seat, v_day,
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.made_at >= v_day - 30 and j.made_at < v_day + 1),
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.outcome_correct is not null and j.outcome_at >= v_day - 30 and j.outcome_at < v_day + 1),
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.outcome_correct and j.outcome_at >= v_day - 30 and j.outcome_at < v_day + 1),
         (select round(avg(case when j.outcome_correct then 1.0 else 0.0 end), 4) from public.seat_judgement j
           where j.seat = s.seat and j.status <> 'held' and j.outcome_correct is not null and j.outcome_at >= v_day - 30 and j.outcome_at < v_day + 1),
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and (j.recall->>'available')::boolean and j.made_at >= v_day - 30 and j.made_at < v_day + 1),
         (select count(*) from public.seat_case_memory m where m.seat = s.seat),
         (select count(*) from public.seat_case_memory m where m.seat = s.seat and m.outcome is not null),
         (select count(*) from public.reasoning_knowledge_candidate k join public.seat_lesson_cluster c on c.candidate_id = k.id
           where k.seat = s.seat and k.status = 'approved')
    from unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) s(seat)
  on conflict (seat, day) do update set judgements_30d = excluded.judgements_30d, outcomes_30d = excluded.outcomes_30d,
     correct_30d = excluded.correct_30d, accuracy_30d = excluded.accuracy_30d, recall_available_30d = excluded.recall_available_30d,
     cases_total = excluded.cases_total, cases_with_outcome = excluded.cases_with_outcome,
     lessons_approved = excluded.lessons_approved, measured_at = now();

  for r in select * from public.seat_learning_daily where day = v_day loop
    select * into p from public.seat_learning_daily where seat = r.seat and day = v_day - 7;
    v_fell := p.seat is not null and r.outcomes_30d >= 10 and p.outcomes_30d >= 10
              and r.accuracy_30d is not null and p.accuracy_30d is not null and r.accuracy_30d <= p.accuracy_30d - 0.10;
    if v_fell then
      perform public.fn_it_engineer_finding_upsert('learning_accuracy_fell:' || r.seat,
        'The ' || r.seat || ' seat''s decision accuracy fell from ' || round(p.accuracy_30d * 100) || '% to ' || round(r.accuracy_30d * 100) || '% in a week',
        'public.seat_learning_daily (' || r.seat || ')', 'agent_facing', r.outcomes_30d,
        jsonb_build_object('seat', r.seat, 'day', v_day, 'accuracy_now', r.accuracy_30d, 'accuracy_week_ago', p.accuracy_30d,
                           'outcomes_now', r.outcomes_30d, 'outcomes_week_ago', p.outcomes_30d),
        '{}'::text[], array['which judgements turned wrong: read seat_judgement where seat = ''' || r.seat || ''' and outcome_correct is false'], 'it_engineer');
    elsif exists (select 1 from public.it_engineer_finding f where f.issue_key = 'learning_accuracy_fell:' || r.seat and f.closed_at is null)
          and (p.seat is null or r.accuracy_30d is null or p.accuracy_30d is null or r.accuracy_30d > p.accuracy_30d - 0.10) then
      perform public.fn_it_engineer_finding_close('learning_accuracy_fell:' || r.seat,
        'Recovered: ' || r.seat || ' accuracy ' || coalesce(round(r.accuracy_30d * 100) || '%', 'not measurable') || ' on ' || v_day);
    end if;
    v_out := v_out || jsonb_build_object('seat', r.seat, 'accuracy_30d', r.accuracy_30d, 'outcomes_30d', r.outcomes_30d, 'fell', coalesce(v_fell, false));
  end loop;
  return jsonb_build_object('ok', true, 'day', v_day, 'seats', v_out);
end $fn$;
revoke execute on function public.fn_seat_learning_measure(date) from public, anon, authenticated;
grant execute on function public.fn_seat_learning_measure(date) to service_role;

-- ── 5. THE CEO SEES THE TREND ───────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_learning_trend(p_to date default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with d as (select coalesce(p_to, (now() at time zone 'Asia/Dubai')::date) as t)
  select coalesce(jsonb_object_agg(s.seat, jsonb_build_object(
    'accuracy_now',      (select x.accuracy_30d from public.seat_learning_daily x where x.seat = s.seat and x.day <= d.t order by x.day desc limit 1),
    'accuracy_week_ago', (select x.accuracy_30d from public.seat_learning_daily x where x.seat = s.seat and x.day <= d.t - 7 order by x.day desc limit 1),
    'accuracy_4w_ago',   (select x.accuracy_30d from public.seat_learning_daily x where x.seat = s.seat and x.day <= d.t - 28 order by x.day desc limit 1),
    'judgements_week',   (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.made_at >= d.t - 6),
    'outcomes_week',     (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.outcome_at >= d.t - 6),
    'cases_with_outcome',(select count(*) from public.seat_case_memory m where m.seat = s.seat and m.outcome is not null),
    'lessons_approved_week', (select count(*) from public.reasoning_knowledge_candidate k join public.seat_lesson_cluster c on c.candidate_id = k.id
                               where k.seat = s.seat and k.status = 'approved' and k.reviewed_at >= d.t - 6),
    'lessons_pending',   (select count(*) from public.reasoning_knowledge_candidate k join public.seat_lesson_cluster c on c.candidate_id = k.id
                               where k.seat = s.seat and k.status = 'pending_review'))), '{}'::jsonb)
  from d, unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) s(seat)
$fn$;
revoke execute on function public.fn_seat_learning_trend(date) from public, anon, authenticated;
grant execute on function public.fn_seat_learning_trend(date) to service_role;

-- The weekly report (fn_ceo_weekly_report, the_ceo_writes_the_whole_company_report...) is not copied
-- here: a second definition of that routine would make the MANIFEST decide which one is real. The
-- section is added as the row is written, once (the marker stops a re-generation appending it twice).
create or replace function public.trg_ceo_weekly_report_learning()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb; v_txt text;
begin
  if coalesce(new.body, '') like '%THE SEATS, LEARNING%' then return new; end if;
  v := public.fn_seat_learning_trend(new.week_end);
  select string_agg(format('  %-17s accuracy %s (a week earlier %s, four weeks earlier %s); %s judgements and %s outcomes this week; %s lesson(s) approved, %s pending',
           k, coalesce(round((x->>'accuracy_now')::numeric * 100) || '%', 'not yet measurable'),
           coalesce(round((x->>'accuracy_week_ago')::numeric * 100) || '%', '-'),
           coalesce(round((x->>'accuracy_4w_ago')::numeric * 100) || '%', '-'),
           x->>'judgements_week', x->>'outcomes_week', x->>'lessons_approved_week', x->>'lessons_pending'), E'\n' order by k)
    into v_txt from jsonb_each(v) t(k, x);
  new.body := coalesce(new.body, '') || E'\n\n' || 'THE SEATS, LEARNING' || E'\n' || coalesce(v_txt, '  no seat has a measured judgement yet') || E'\n' ||
              '  Accuracy is the share of judgements whose real outcome proved them right, over the trailing 30 days.';
  new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('learning', v);
  return new;
end $fn$;
revoke execute on function public.trg_ceo_weekly_report_learning() from public, anon, authenticated;
drop trigger if exists z50_learning_section on public.ceo_weekly_report;
create trigger z50_learning_section before insert or update of body on public.ceo_weekly_report
  for each row execute function public.trg_ceo_weekly_report_learning();

-- ── ON THE HEARTBEAT ────────────────────────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('learningMeasure', interval '1 day', 3000, 'plan', 0,
   'seat_learning_daily: per-seat decision accuracy against real outcomes, stored daily; a 10-point weekly fall opens an it_engineer finding',
   'it_engineer'),
  ('learningDistil', interval '7 days', 20000, 'plan', 0,
   'weekly: cases with outcomes grouped by meaning are distilled into lessons by think(), verified by another model family, and promoted into the seat''s knowledge (held under the model hold)',
   'it_engineer')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note, owner_seat = excluded.owner_seat;

-- The first measurement, so the trend has a day zero.
select public.fn_seat_learning_measure();

select case when to_regclass('public.seat_judgement') is not null
             and (select count(*) from pg_trigger where tgname = 'z91_judgement_outcome' and not tgisinternal) = 10
             and exists (select 1 from public.seat_learning_daily)
            then 'PROBE OK: judgement ledger, 10 outcome triggers, first learning measurement'
            else 'PROBE FAILED: ' || (select count(*) from pg_trigger where tgname = 'z91_judgement_outcome' and not tgisinternal) || ' outcome triggers' end as verdict;
