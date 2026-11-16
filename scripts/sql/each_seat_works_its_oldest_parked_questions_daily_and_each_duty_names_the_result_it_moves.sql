-- EACH SEAT WORKS ITS OLDEST PARKED QUESTIONS EVERY DAY, AND EACH DUTY NAMES THE RESULT IT MOVES (16 Nov 2026).
-- Seat: ceo (the backlog and the weekly verdict), with it_engineer for the IT queue. Agent: OPS_LOOPS (it_engineer + ceo
-- builder, wave 2 of the real-company holes; holes H4 and H5 of the COO hunt).
--
-- MEASURED (production, read-only SELECT, 16 Nov 2026):
--   * 387 agent_actions kind held_question are pending ("a question held ... needs you"): 80% older than 7 days, the oldest
--     51 days. it_engineer.postmortem 196 (every one's question failed after its tries), knowledge_refresh 65, ceo_revision
--     28, marketing_social 34, accountant.document_kind 15, wa_inbound.unwritten_reply 11 (person-facing). fn_reason_held_escalate
--     files a row once; fn_held_questions_settle closes it only when its question was applied, superseded or expired
--     internal. A failed question is never asked again, so the row waits for ever and the seat's queue only grows.
--   * The CEO's weekly senior verdict counts a duty live when last_ok_at falls inside twice its clock
--     (the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql:251). It cannot see that dropbox_backup ran
--     'ok' 676 times uploading nothing, case_idle_close ran hourly and closed 0, or register_review ran 'ok' while every
--     compliance source was 98 days stale.
--
-- WHAT THIS ADDS
--   A. THE DAILY BACKLOG REVIEW (duty ceo.backlog_review, daily). For each live seat, its oldest overdue parked questions (up
--      to 8: overdue = flagged overdue, older than 7 days, or raised to it) go to THAT SEAT'S MODEL in one held question
--      (<seat>.backlog_review) with each item's current facts: the question, its state, tries, the last failure, its age,
--      whether a person is waiting, whether the same question was asked again later, whether it was already retried. The
--      model decides, per item: answer (and gives it), retry (and why it will work now), close (with the reason), or raise
--      to the CEO (with what the CEO must decide). fn_seat_backlog_apply carries each decision out:
--        answer  the parked row closes 'done' with the answer; an internal question that asked for words (no decision
--                options) is resolved with it, so its own surface applies it (a postmortem writes its cause). A person-facing
--                question's answer is recorded only: a days-old reply never reaches a person unreviewed.
--        retry   the question is put back to 'held' with fresh tries and 14 days (once: a second retry is a raise).
--        close   the parked row closes with the seat's reason; a still-held question is expired through
--                fn_reason_held_expire, which keeps a person-facing one for its seat.
--        raise   the item moves to the CEO's queue, due at once; the CEO's own raise marks it needs_founder.
--      Code only reads the model's verb (one of four) and refuses a second retry; it never decides what an item means.
--   B. EACH DUTY NAMES THE RESULT IT MOVES. public.seat_duty_result: per duty, a measure, a target and a direction, written
--      every day by fn_seat_duty_results_measure (duty ceo.duty_results) from statically written queries (no stored SQL is
--      executed). Eleven duties to start, the ones the hunt names: customer_support.case_idle_close, .unanswered_inbound,
--      .case_review, .complaint_deadlines; ceo.queue_work, .register_review, .backlog_review, .calendar_horizon;
--      it_engineer.backup_objectives, .postmortem, .incident_impact.
--      fn_ceo_seat_senior_verdict (redefined here; the rest of its body is the live one, read back from the mirror
--      16 Nov 2026 and identical to the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql) counts a duty
--      on its clock only when it ran on time AND its result is met (a measurement older than 2 days counts as missed:
--      no measurement is never a pass), a senior contribution live only on the same terms, and lists every missed result
--      as a shortfall with its number.
-- WHAT IT DOES NOT CHANGE: fn_reason_held_escalate, fn_held_questions_settle (they keep filing and settling), ceo_task
-- (246 open: a separate queue, not in this review), any duty's routine.
--
-- Probe: scripts/sql/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves_probe.sql
-- Pending: scripts/sql/pending/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves.txt
-- prevented by: scripts/checks/the_ops_loops_close_against_what_they_measure.test.mjs and the probe (local PG16, twice).
--   node scripts/apply_sql.mjs scripts/sql/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves.sql --apply --ddl

-- ── A. the daily backlog review ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_backlog_review(p_per_seat integer default 8)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s record; v_items jsonb; v_fields jsonb; v_ids bigint[]; v_hid bigint; v_q text; v_out jsonb := '{}'::jsonb; n_released int;
begin
  for s in select o.role_id from public.org_role o where o.status = 'active' order by o.role_id loop
    -- an item whose review question the model could not answer is offered again
    update public.agent_actions x set detail = x.detail - 'backlog_held_id'
     where x.kind = 'held_question' and x.status = 'pending' and x.agent = s.role_id and x.detail ? 'backlog_held_id'
       and exists (select 1 from public.reasoning_held_question q where q.id = (x.detail->>'backlog_held_id')::bigint and q.status in ('failed', 'expired'));
    get diagnostics n_released = row_count;
    select array_agg(z.id order by z.created_at),
           jsonb_agg(jsonb_build_object('item', z.id, 'surface', z.surface, 'question', z.question, 'question_state', z.rstatus,
             'tries', z.attempts, 'last_failure', z.last_failure, 'parked_days', z.days, 'a_person_is_waiting', z.person,
             'asked_again_later', z.later, 'already_retried', z.retried, 'raised_by', z.raised_by, 'raised_reason', z.raised_reason)
             order by z.created_at),
           jsonb_agg(jsonb_build_object('key', 'item_' || z.id, 'question',
             'Item ' || z.id || ': answer "answer: <the answer>", "retry: <why it will work now>", "close: <reason>" or "raise: <what the CEO must decide>"')
             order by z.created_at)
      into v_ids, v_items, v_fields
      from (select x.id, x.created_at, x.detail->>'surface' surface, left(coalesce(x.detail->>'question', x.title), 700) question,
                   coalesce(r.status, 'gone') rstatus, r.attempts,
                   left(coalesce(r.result->>'reason', r.result->>'error', r.result->>'why'), 300) last_failure,
                   round(extract(epoch from now() - x.created_at) / 86400)::int days,
                   public.fn_held_question_is_person_facing(x.detail->>'surface') person,
                   exists (select 1 from public.reasoning_held_question r2 where r2.seat = x.agent and r2.surface = r.surface
                            and r2.subject is not distinct from r.subject and r2.created_at > r.created_at and r2.id <> r.id) later,
                   coalesce(r.result ? 'backlog_retried_at', false) retried,
                   x.detail->>'raised_by' raised_by, x.detail->>'raised_reason' raised_reason
              from public.agent_actions x
              left join public.reasoning_held_question r on r.id = (x.detail->>'held_id')::bigint
             where x.kind = 'held_question' and x.status = 'pending' and x.agent = s.role_id
               and not x.detail ? 'backlog_held_id' and not coalesce((x.detail->>'needs_founder')::boolean, false)
               and (x.detail ? 'overdue_at' or x.detail ? 'raised_by' or x.created_at < now() - interval '7 days')
             order by x.created_at
             limit greatest(1, least(coalesce(p_per_seat, 8), 20))) z;
    continue when v_ids is null;
    v_q := 'These are the oldest questions parked in the ' || s.role_id || ' seat''s queue, each with its facts today. For each, '
        || 'decide as the seat''s senior would: answer it now (and give the answer), retry it (only if something changed so it '
        || 'can be answered now; say what), close it (with the reason: the moment passed, it was superseded, it was test traffic, '
        || 'nothing would apply it), or raise it to the CEO (say exactly what the CEO must decide). A person who is waiting is '
        || 'never closed silently.';
    v_hid := public.fn_reason_hold(s.role_id, s.role_id || '.backlog_review', v_q,
      jsonb_build_object('seat', s.role_id, 'surface', s.role_id || '.backlog_review', 'research', false, 'stakes', 'normal', 'question', v_q,
        'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('today', current_date, 'items', v_items)),
        'decision', jsonb_build_object('name', 'backlog_review', 'fields', v_fields),
        'subject', jsonb_build_object('action_ids', to_jsonb(v_ids)), 'dedupeKey', 'backlog_review:' || s.role_id || ':' || v_ids[1] || ':' || current_date),
      jsonb_build_object('filed_by', 'ceo.backlog_review'), jsonb_build_object('action_ids', to_jsonb(v_ids), 'seat', s.role_id),
      'seat_duty', 'backlog_review:' || s.role_id || ':' || v_ids[1] || ':' || current_date);
    if v_hid is not null then
      update public.agent_actions set detail = detail || jsonb_build_object('backlog_held_id', v_hid, 'backlog_offered_at', now())
       where id = any(v_ids);
    end if;
    v_out := v_out || jsonb_build_object(s.role_id, jsonb_build_object('offered', case when v_hid is null then 0 else cardinality(v_ids) end,
                                                                        'held_id', v_hid, 'released', n_released));
  end loop;
  return jsonb_build_object('seats', v_out,
    'parked_overdue_now', (select count(*) from public.agent_actions where kind = 'held_question' and status = 'pending' and created_at < now() - interval '7 days'));
end $fn$;
revoke execute on function public.fn_seat_backlog_review(integer) from public, anon, authenticated;

create or replace function public.fn_seat_backlog_review_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_review(8) $fn$;
revoke execute on function public.fn_seat_backlog_review_now() from public, anon, authenticated;

create or replace function public.fn_seat_backlog_apply(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.reasoning_held_question; x bigint; a public.agent_actions; h public.reasoning_held_question;
  v text; v_verb text; v_txt text; v_applied jsonb; v_new bigint; v_by text;
  n jsonb := jsonb_build_object('answer', 0, 'retry', 0, 'close', 0, 'raise', 0, 'unclear', 0);
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_by := r.seat || '.backlog_review (' || coalesce(p_result->>'model', 'model') || ')';
  for x in select (e #>> '{}')::bigint from jsonb_array_elements(coalesce(r.subject->'action_ids', '[]'::jsonb)) e loop
    select * into a from public.agent_actions where id = x and kind = 'held_question' and status = 'pending' and agent = r.seat for update;
    continue when not found;
    h := null;
    select * into h from public.reasoning_held_question where id = nullif(a.detail->>'held_id', '')::bigint;
    v := btrim(coalesce(p_result->'decision'->'fields'->('item_' || x)->>'value', ''));
    v_verb := lower(btrim(split_part(v, ':', 1)));
    v_txt := case when position(':' in v) > 0 then btrim(substr(v, position(':' in v) + 1)) else '' end;
    -- code only reads the verb: one of four, with words; anything else is offered again tomorrow
    if v_verb not in ('answer', 'retry', 'close', 'raise') or v_txt = '' then
      update public.agent_actions set detail = detail - 'backlog_held_id' where id = x;
      n := jsonb_set(n, '{unclear}', to_jsonb((n->>'unclear')::int + 1));
      continue;
    end if;
    if v_verb = 'retry' and (h.id is null or coalesce(h.result ? 'backlog_retried_at', false)) then
      v_verb := 'raise';
      v_txt := case when h.id is null then 'the question no longer exists to retry; ' else 'already retried once on '
                 || coalesce(h.result->>'backlog_retried_at', '?') || ' and it failed again; ' end || v_txt;
    end if;

    if v_verb = 'answer' then
      v_applied := null;
      if h.id is not null and h.status in ('failed', 'held', 'reasoned') and not coalesce(h.request ? 'decision', false)
         and not public.fn_held_question_is_person_facing(h.surface) then
        begin
          v_applied := public.fn_reason_held_resolve(h.id, jsonb_build_object('status', 'answered', 'answer', v_txt,
                         'model', p_result->>'model', 'by', v_by, 'decision', null));
        exception when others then
          v_applied := jsonb_build_object('error', left(sqlerrm, 300));
        end;
      end if;
      update public.agent_actions
         set status = 'done', decided_at = now(), decided_by = v_by,
             evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('verdict', 'answered by the seat in its daily backlog review',
                          'answer', left(v_txt, 4000), 'applied', v_applied, 'review_held_id', p_id, 'settled_at', now())
       where id = x;
    elsif v_verb = 'retry' then
      update public.reasoning_held_question
         set status = 'held', attempts = 0, escalated_at = null, expires_at = now() + interval '14 days',
             result = coalesce(result, '{}'::jsonb) || jsonb_build_object('backlog_retried_at', now(), 'retried_by', v_by, 'why', left(v_txt, 500))
       where id = h.id;
      update public.agent_actions
         set status = 'dismissed', decided_at = now(), decided_by = v_by,
             evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('verdict', 'asked again by the seat''s backlog review: ' || left(v_txt, 500),
                          'held_id', h.id, 'review_held_id', p_id, 'settled_at', now())
       where id = x;
    elsif v_verb = 'close' then
      if h.id is not null and h.status = 'held' then
        perform public.fn_reason_held_expire(array[h.id], v_by, left(v_txt, 500));
      end if;
      update public.agent_actions
         set status = 'dismissed', decided_at = now(), decided_by = v_by,
             evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('verdict', 'closed by the seat: ' || left(v_txt, 1000),
                          'review_held_id', p_id, 'settled_at', now())
       where id = x;
    else   -- raise
      if r.seat = 'ceo' then
        update public.agent_actions
           set detail = (detail - 'backlog_held_id') || jsonb_build_object('needs_founder', true, 'raised_reason', left(v_txt, 1000), 'raised_at', now())
         where id = x;
      else
        insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
        values ('ceo', 'held_question', 'pending', a.risk, left('Raised by ' || r.seat || ': ' || coalesce(a.title, 'a parked question'), 200),
                (a.detail - 'backlog_held_id' - 'backlog_offered_at') || jsonb_build_object('raised_by', r.seat, 'raised_from', a.id,
                  'raised_reason', left(v_txt, 1000), 'overdue_at', now(), 'owner_seat', 'ceo', 'due_at', (now() + interval '1 day')::text),
                a.target_table, a.target_id)
        returning id into v_new;
        update public.agent_actions
           set status = 'dismissed', decided_at = now(), decided_by = v_by,
               evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('verdict', 'raised to the CEO as action ' || v_new || ': ' || left(v_txt, 500),
                            'raised_to', v_new, 'review_held_id', p_id, 'settled_at', now())
         where id = x;
      end if;
    end if;
    n := jsonb_set(n, array[v_verb], to_jsonb((n->>v_verb)::int + 1));
  end loop;
  return jsonb_build_object('seat', r.seat, 'decided', n);
end $fn$;
revoke execute on function public.fn_seat_backlog_apply(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__backlog_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__backlog_review(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_it_engineer__backlog_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__backlog_review(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_sales_engineer__backlog_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__backlog_review(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_marketing__backlog_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_marketing__backlog_review(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_accountant__backlog_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_accountant__backlog_review(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_customer_support__backlog_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_backlog_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_customer_support__backlog_review(bigint, jsonb) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('ceo.backlog_review', 'ceo', interval '1 day', 'fn_seat_backlog_review_now',
        'Once a day each live seat''s model takes its oldest overdue parked questions with their facts and decides answer, retry (once), close with a reason, or raise to the CEO; each decision is carried out on the queue.',
        'scripts/sql/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── B. each duty names the result it moves ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.seat_duty_result (
  duty text primary key references public.seat_duty (duty),
  measure text not null check (length(btrim(measure)) >= 10),
  direction text not null check (direction in ('at_most', 'at_least')),
  target numeric not null,
  value numeric,
  previous_value numeric,
  met boolean,
  detail jsonb not null default '{}'::jsonb,
  measured_at timestamptz
);
comment on table public.seat_duty_result is
  'The result each duty exists to move (a queue that must fall, a register that must be current), measured daily by fn_seat_duty_results_measure; the CEO''s weekly verdict counts a duty on its clock only while its result is met.';
alter table public.seat_duty_result enable row level security;
drop policy if exists seat_duty_result_service_role_only on public.seat_duty_result;
create policy seat_duty_result_service_role_only on public.seat_duty_result
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_duty_result from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('seat_duty_result', false, 'measurement', 'A daily measurement of each duty''s result, rewritten in place; the history is the CEO''s weekly verdict rows.', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_seat_duty_result_missed(p_duty text, p_at timestamptz default now())
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- true when the duty names a result and that result is not met, or was not measured in the last 2 days
  select exists (select 1 from public.seat_duty_result r
                  where r.duty = p_duty and (r.met is not true or r.measured_at is null or r.measured_at < p_at - interval '2 days'));
$fn$;
revoke execute on function public.fn_seat_duty_result_missed(text, timestamptz) from public, anon, authenticated;

create or replace function public.fn_seat_duty_result_record(p_duty text, p_measure text, p_direction text, p_target numeric, p_value numeric, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if not exists (select 1 from public.seat_duty where duty = p_duty) then return; end if;   -- a duty not on this database: nothing to judge
  insert into public.seat_duty_result as r (duty, measure, direction, target, value, met, detail, measured_at)
  values (p_duty, p_measure, p_direction, p_target, p_value,
          case when p_value is null then null when p_direction = 'at_most' then p_value <= p_target else p_value >= p_target end,
          coalesce(p_detail, '{}'::jsonb), now())
  on conflict (duty) do update set measure = excluded.measure, direction = excluded.direction, target = excluded.target,
    previous_value = r.value, value = excluded.value, met = excluded.met, detail = excluded.detail, measured_at = excluded.measured_at;
end $fn$;
revoke execute on function public.fn_seat_duty_result_record(text, text, text, numeric, numeric, jsonb) from public, anon, authenticated;

create or replace function public.fn_seat_duty_results_measure()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v numeric;
begin
  -- customer_support: every contact answered or closed by its owner, in time (demo parties never counted)
  select count(*) into v from public.support_case s join public.support_customer_profile pr on pr.id = s.customer_profile_id
   where s.state <> 'closed' and coalesce(s.last_activity_at, s.opened_at) < now() - interval '7 days' and not public.fn_is_demo_email(coalesce(pr.email, ''));
  perform public.fn_seat_duty_result_record('customer_support.case_idle_close', 'open support cases idle for more than 7 days', 'at_most', 0, v);
  select count(*) into v from public.customer_support_inbound_drive d
   where not d.fixture and d.answered_at is null and d.acted_at < now() - interval '24 hours';
  perform public.fn_seat_duty_result_record('customer_support.unanswered_inbound', 'inbound messages unanswered 24 hours after support took them', 'at_most', 0, v);
  select count(*) into v from public.support_case s join public.support_customer_profile pr on pr.id = s.customer_profile_id
   where s.state <> 'closed' and s.first_reply_at is null and s.opened_at < now() - interval '24 hours' and not public.fn_is_demo_email(coalesce(pr.email, ''));
  perform public.fn_seat_duty_result_record('customer_support.case_review', 'open support cases never answered 24 hours after they opened', 'at_most', 0, v);
  select count(*) into v from public.complaint_tickets t
   where t.final_response_at is null and t.respond_due < now() and not public.fn_is_demo_email(t.email);
  perform public.fn_seat_duty_result_record('customer_support.complaint_deadlines', 'complaints past their response due date with no final response', 'at_most', 0, v);

  -- ceo: the queues it owns fall, the registers it owns are current
  select count(*) into v from public.ceo_task where state = 'open' and created_at < now() - interval '7 days';
  perform public.fn_seat_duty_result_record('ceo.queue_work', 'CEO tasks open for more than 7 days', 'at_most', 0, v);
  select count(*) into v from public.compliance_sources where active and coalesce(last_checked_at, 'epoch') < now() - interval '35 days';
  perform public.fn_seat_duty_result_record('ceo.register_review', 'active compliance sources not checked in 35 days', 'at_most', 0, v);
  select count(*) into v from public.agent_actions where kind = 'held_question' and status = 'pending' and created_at < now() - interval '14 days'
     and not coalesce((detail->>'needs_founder')::boolean, false);
  perform public.fn_seat_duty_result_record('ceo.backlog_review', 'parked model questions older than 14 days (not waiting on the founder)', 'at_most', 0, v);
  select count(*) into v from public.company_calendar_plan where status = 'asked' and created_at < now() - interval '7 days';
  perform public.fn_seat_duty_result_record('ceo.calendar_horizon', 'calendar entries a seat was given 7 days ago with no plan recorded', 'at_most', 0, v);

  -- it_engineer: the backup is complete, every incident has its cause, every customer-facing one its judgement
  select count(*) into v from public.doc_backups d
   where d.status <> 'done' and d.entity <> 'zz_demo' and d.status not in ('prune_pending', 'pruning', 'pruned')
     and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%') and coalesce(d.requeued_at, d.created_at) < now() - interval '48 hours';
  perform public.fn_seat_duty_result_record('it_engineer.backup_objectives', 'documents queued for Dropbox and not there after 48 hours', 'at_most', 0, v);
  select count(*) into v from public.it_incident i
   where i.ended_at < now() - interval '72 hours' and i.created_at > now() - interval '30 days' and coalesce(btrim(i.cause), '') = ''
     and coalesce(i.title, '') not like 'ZZ DEMO%';
  perform public.fn_seat_duty_result_record('it_engineer.postmortem', 'incidents closed 72 hours ago with no root cause (30 days)', 'at_most', 0, v);
  select count(*) into v from public.it_incident i join public.agent_actions a on a.id = i.handoff_id
   where i.same_cause_as is null and i.impact_judged_at is null and i.cause_key is not null and i.created_at < now() - interval '2 hours'
     and i.created_at > now() - interval '7 days' and coalesce(i.title, '') not like 'ZZ DEMO%'
     and (coalesce((a.detail->'finding_evidence'->>'public_surface')::boolean, false) or a.detail->>'severity' = 'critical');
  perform public.fn_seat_duty_result_record('it_engineer.incident_impact', 'customer-facing incidents with no judgement of who they reach 2 hours after opening', 'at_most', 0, v);

  return jsonb_build_object('measured', (select count(*) from public.seat_duty_result where measured_at > now() - interval '1 minute'),
    'missed', (select coalesce(jsonb_agg(duty order by duty), '[]'::jsonb) from public.seat_duty_result where met is not true));
end $fn$;
revoke execute on function public.fn_seat_duty_results_measure() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('ceo.duty_results', 'ceo', interval '1 day', 'fn_seat_duty_results_measure',
        'H5: the result each duty exists to move (a queue falling, a register current) measured daily into seat_duty_result; the weekly senior verdict counts a duty on its clock only while that result is met.',
        'scripts/sql/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── the weekly verdict reads the result, not only the clock ───────────────────────────────────────────────────────────
-- fn_ceo_seat_senior_verdict: the live body (mirror, 16 Nov 2026), with only the lines marked '16 Nov 2026 (H5)' and the
-- duty_results_missed reading added.
create or replace function public.fn_ceo_seat_senior_verdict(p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c_senior_exam  constant numeric := 0.95;   -- SENIOR_BAR in scripts/eval/seat_senior_audit.mjs
  c_mid_exam     constant numeric := 0.80;   -- mid-level exam bar in seat_senior_audit.mjs
  c_mid_contrib  constant numeric := 0.90;   -- mid-level contribution bar
  c_on_clock     constant numeric := 0.95;
  c_on_time      constant numeric := 0.90;
  c_judged_min   constant int     := 20;
  c_judged_bar   constant numeric := 0.80;
  v_week date := date_trunc('week', p_at at time zone 'Asia/Dubai')::date;
  s record; v_s1 jsonb; v_s2 jsonb; v_short text[]; v_level text; v_prev text; v_id bigint;
  v_exam numeric; v_items int; v_passed int; v_judged_n int; v_judged_ok numeric;
  v_contrib int; v_live int; v_not_live jsonb; v_duties int; v_on_clock int; v_missed jsonb; v_missed_n int;
  v_win int; v_in_time int; v_late_open int; v_own int; v_sent int; v_owed int;
  n_seats int := 0; n_fell int := 0; v_levels jsonb := '{}'::jsonb;
begin
  for s in select role_id from public.org_role where status = 'active' order by role_id loop
    n_seats := n_seats + 1;

    -- STAGE 1: qualification
    select e.items, e.passed into v_items, v_passed from public.seat_senior_exam e
     where e.seat = s.role_id order by e.judged_on desc limit 1;
    v_exam := case when v_items > 0 then round(v_passed::numeric / v_items, 3) end;
    select count(*), round(avg(j.outcome_correct::int), 3) into v_judged_n, v_judged_ok
      from public.seat_judgement j
     where j.seat = s.role_id and j.outcome_correct is not null and j.made_at > p_at - interval '90 days';
    v_s1 := jsonb_build_object(
      'exam_items', v_items, 'exam_passed', v_passed, 'exam_rate', v_exam,
      'judged_outcomes_90d', v_judged_n, 'judged_correct_rate', v_judged_ok,
      'recall', (select jsonb_build_object('day', r.day, 'questions', r.questions, 'en', r.recall_en, 'ar', r.recall_ar)
                   from public.seat_knowledge_recall r where r.seat = s.role_id order by r.day desc limit 1));

    -- STAGE 2: contribution
    with c as (
      select sc.contribution_id, sc.what, sc.duties,
             cardinality(sc.duties) > 0 and not exists (
               select 1 from unnest(sc.duties) k
                where not exists (select 1 from public.seat_duty d
                                   where d.duty = k and d.enabled and d.last_ok_at is not null
                                     and d.last_ok_at >= p_at - (d.every * 2 + interval '1 day')
                                     -- 16 Nov 2026 (H5): ran on time is not enough when the duty names the result it moves
                                     and not public.fn_seat_duty_result_missed(d.duty, p_at))) as live
        from public.seat_senior_contribution sc where sc.seat = s.role_id)
    select count(*), count(*) filter (where live),
           coalesce(jsonb_agg(contribution_id || ' ' || left(what, 120) order by contribution_id) filter (where not live), '[]'::jsonb)
      into v_contrib, v_live, v_not_live from c;
    -- A DUTY IS ON ITS CLOCK WHEN IT RAN ON TIME AND MOVED ITS RESULT (16 Nov 2026, H5 of the COO hunt): dropbox_backup
    -- ran 'ok' 676 times uploading nothing, case_idle_close closed 0 hourly, register_review ran while every source was 98
    -- days stale. A duty that names its result in seat_duty_result is counted only while that result is met.
    select count(*), count(*) filter (where d.last_ok_at >= p_at - (d.every * 2 + interval '1 day') and not public.fn_seat_duty_result_missed(d.duty, p_at))
      into v_duties, v_on_clock from public.seat_duty d where d.owner_seat = s.role_id and d.enabled;
    select count(*), coalesce(jsonb_agg(format('%s: %s %s, target %s %s', r.duty, r.measure, trim_scale(r.value),
                                               replace(r.direction, '_', ' '), trim_scale(r.target)) order by r.duty), '[]'::jsonb)
      into v_missed_n, v_missed
      from public.seat_duty_result r join public.seat_duty d on d.duty = r.duty
     where d.owner_seat = s.role_id and d.enabled and public.fn_seat_duty_result_missed(r.duty, p_at);
    -- THE RECEIVER'S ANSWER, not the close. Measured 27 Oct 2026: on a kind the originator closes, decided_at is the
    -- originator's re-verification and detail.replied_at is the receiver's reply; sales_engineer's it.finding handoffs
    -- (4-hour window) were replied in time 414 of 414 and closed in time 21 of 414. A handoff already answered and
    -- waiting for its originator is not late on the receiver.
    select count(*) filter (where a.status = 'done' or a.detail ? 'replied_at'),
           count(*) filter (where (a.status = 'done' or a.detail ? 'replied_at')
                              and coalesce((a.detail->>'replied_at')::timestamptz, a.decided_at) <= a.created_at + k.reply_within),
           count(*) filter (where a.status = 'pending' and not a.detail ? 'replied_at' and a.created_at < p_at - k.reply_within)
      into v_win, v_in_time, v_late_open
      from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = s.role_id and k.reply_within is not null
       and a.created_at > p_at - interval '30 days' and coalesce(a.title, '') not like '%ZZ DEMO%';
    -- The other half of a loop (nothing is one-way): handoffs THIS seat sent, answered, and still waiting for this seat to
    -- re-verify and close, past one more reply window. Informational: an it.finding legitimately waits on its fix.
    select count(*) into v_owed
      from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = s.role_id and k.originator_closes
       and k.reply_within is not null and a.detail ? 'replied_at'
       and (a.detail->>'replied_at')::timestamptz < p_at - k.reply_within and coalesce(a.title, '') not like '%ZZ DEMO%';
    select count(*) filter (where a.agent = s.role_id and a.kind <> 'handoff'),
           count(*) filter (where a.kind = 'handoff' and a.detail->>'from' = s.role_id and a.agent <> s.role_id)
      into v_own, v_sent
      from public.agent_actions a where a.created_at > p_at - interval '30 days';
    v_s2 := jsonb_build_object(
      'contributions', v_contrib, 'contributions_live', v_live,
      'contributions_live_rate', case when v_contrib > 0 then round(v_live::numeric / v_contrib, 3) end,
      'contributions_not_live', v_not_live,
      'duties', v_duties, 'duties_on_clock', v_on_clock, 'duty_results_missed', v_missed,
      'duties_on_clock_rate', case when v_duties > 0 then round(v_on_clock::numeric / v_duties, 3) end,
      'windowed_handoffs_answered_30d', v_win, 'answered_in_window_30d', v_in_time,
      'answered_in_window_rate', case when v_win > 0 then round(v_in_time::numeric / v_win, 3) end,
      'handoffs_unanswered_past_window_now', v_late_open, 'closes_owed_past_window_now', v_owed,
      'own_actions_30d', v_own, 'handoffs_sent_30d', v_sent);

    -- THE LEVEL, and every shortfall with its number. No measurement is never a pass.
    v_short := '{}';
    if v_exam is null then v_short := v_short || 'stage 1: no judged exam'::text;
    elsif v_exam < c_senior_exam then
      v_short := v_short || format('stage 1: exam %s%% (%s of %s) below the senior 95%%', round(v_exam * 100, 1), v_passed, v_items);
    end if;
    if v_judged_n >= c_judged_min and v_judged_ok < c_judged_bar then
      v_short := v_short || format('stage 1: %s%% of %s graded judgements right (bar 80%%)', round(v_judged_ok * 100), v_judged_n);
    end if;
    if v_contrib = 0 then v_short := v_short || 'stage 2: no senior contributions defined'::text;
    elsif v_live < v_contrib then
      v_short := v_short || format('stage 2: %s of %s senior contributions live', v_live, v_contrib);
    end if;
    if v_duties = 0 or v_on_clock::numeric / v_duties < c_on_clock then
      v_short := v_short || format('stage 2: %s of %s duties on their clock', v_on_clock, v_duties);
    end if;
    if v_missed_n > 0 then
      v_short := v_short || format('stage 2: %s duties ran but did not move their result (%s)', v_missed_n,
                                   (select string_agg(x, '; ') from jsonb_array_elements_text(v_missed) x));
    end if;
    if v_win > 0 and v_in_time::numeric / v_win < c_on_time then
      v_short := v_short || format('stage 2: %s of %s windowed handoffs answered within their window in 30 days', v_in_time, v_win);
    end if;
    if v_late_open > 0 then v_short := v_short || format('stage 2: %s handoffs unanswered past their window now', v_late_open); end if;

    v_level := case
      when cardinality(v_short) = 0 then 'senior'
      when v_exam >= c_mid_exam and v_contrib > 0 and v_live::numeric / v_contrib >= c_mid_contrib then 'mid'
      else 'junior' end;

    -- a level that FELL since the last verdict is the CEO's to act on, once
    select v.level into v_prev from public.seat_senior_verdict v where v.seat = s.role_id and v.week < v_week order by v.week desc limit 1;
    v_id := null;
    if v_prev is not null and array_position(array['junior', 'mid', 'senior'], v_level) < array_position(array['junior', 'mid', 'senior'], v_prev) then
      v_id := public.fn_ceo_improvement_open('seat_audit', 'senior:' || s.role_id || ':' || v_week, s.role_id,
        format('Senior verdict for %s fell from %s to %s in the week of %s. ', s.role_id, v_prev, v_level, to_char(v_week, 'DD Mon YYYY'))
          || array_to_string(v_short, '; ') || '. Restore each measure that fell before the next weekly verdict.',
        jsonb_build_object('week', v_week, 'stage1', v_s1, 'stage2', v_s2, 'from', v_prev, 'to', v_level));
      n_fell := n_fell + 1;
    end if;

    insert into public.seat_senior_verdict (week, seat, stage1, stage2, level, shortfalls, improvement_id, measured_at)
    values (v_week, s.role_id, v_s1, v_s2, v_level, v_short, v_id, now())
    on conflict (week, seat) do update set stage1 = excluded.stage1, stage2 = excluded.stage2, level = excluded.level,
      shortfalls = excluded.shortfalls, improvement_id = coalesce(public.seat_senior_verdict.improvement_id, excluded.improvement_id),
      measured_at = excluded.measured_at;
    v_levels := v_levels || jsonb_build_object(s.role_id, v_level);
  end loop;
  return jsonb_build_object('week', v_week, 'seats', n_seats, 'levels', v_levels, 'fell', n_fell);
end $fn$;

revoke execute on function public.fn_ceo_seat_senior_verdict(timestamptz) from public, anon, authenticated;

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when to_regclass('public.seat_duty_result') is null then 'PROBE FAILED: no seat_duty_result'
  when has_function_privilege('anon', 'public.fn_seat_backlog_review(integer)', 'execute')
    or has_function_privilege('anon', 'public.fn_seat_backlog_apply(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_seat_duty_results_measure()', 'execute')
    or has_function_privilege('anon', 'public.fn_seat_duty_result_missed(text, timestamptz)', 'execute')
    or has_function_privilege('anon', 'public.fn_reason_apply_it_engineer__backlog_review(bigint, jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute a backlog or result routine'
  when position('fn_seat_duty_result_missed' in (select prosrc from pg_proc where oid = 'public.fn_ceo_seat_senior_verdict(timestamptz)'::regprocedure)) = 0
    then 'PROBE FAILED: the weekly verdict does not read the duty results'
  when (select count(*) from public.seat_duty where duty in ('ceo.backlog_review', 'ceo.duty_results') and enabled) <> 2
    then 'PROBE FAILED: the backlog or result duty is not registered'
  else 'PROBE OK' end as verdict;
