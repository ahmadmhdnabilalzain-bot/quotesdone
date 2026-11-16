-- THE COMPANY RUNS ITS OWN WEEKLY SEAT EXAM (it_engineer, 16 Nov 2026). Founder ledgers 1084, 1443 (and 893/894/1200,
-- which wait on this exam). Agent: L7_JOBS.
--
-- THE FOUNDER. 1084 (30 Sep): "No reason to run knowledge tests without the LLM. The exam must test the real answer with the
-- model on, and a mistake must lead to an actual fix, not just a record. Questions are never asked in the same wording."
-- 1443 (1 Nov): "Why is the project burning so many tokens on Claude; last week the weekly limit was reached in almost 24 hours."
--
-- MEASURED (production SELECT, 16 Nov 2026 19:00Z): the exam runs only inside the Claude scheduled task "QuotesDone weekly jobs"
-- (trig_01BcP2XDg4qE472q1Dknfwqn, Sundays 07:37 Dubai since ledger 1693): a session on the founder's subscription writes the
-- wordings and judges the misses (scripts/eval/seat_exam_llm_on.mjs). seat_exam_asked: 61 rows, 27 Oct-1 Nov, none since;
-- the 9 Nov run finished in 21 s. seat_exam_fix: 7 open, none ever made (kind and fix_ref null on all 7). The seat duty
-- it_engineer.knowledge_exam is disabled; its routine fn_it_engineer_duty_knowledge_exam (md5 5803e0bd5d798c474393221753f3c051)
-- returns {"asked":0,"retired":...}. ai_cost_log fn knowledge_exam: AED 10.3 on 27 Oct, AED 6.1 on 1 Nov (6 items a seat).
--
-- THE CHANGE. The same duty, it_engineer.knowledge_exam, now runs fn_it_engineer_seat_exam_tick every 10 minutes:
--   * once a week (decision_policy seat_exam_weekly: Sunday from 08:00 Dubai) it opens ONE run, public.seat_exam_run, its
--     own result row, with the items chosen here (fn_seat_exam_plan: an item with an open fix first, then the least
--     recently asked; per_seat a seat);
--   * it posts the run to the it_engineer function (action seat_exam, supabase/functions/it_engineer/seat_exam.ts) until every
--     planned item is asked, one post in flight at a time; each post asks one item (two when the first is quick): a fresh wording by the model, the
--     seat's real answer through think(), graded by code then by the model judge, recorded by fn_seat_exam_record;
--   * A MISS IS FIXED: fn_seat_exam_fix_lesson writes the item's canon into the seat's own knowledge (agent_knowledge,
--     agent_key = the seat; fn_reason_retrieve gives a seat its own rows for an internal audience only) and sets the fix's
--     fix_ref; the next run asks that item first in a new wording and a pass closes the fix;
--   * the run stops at the week's AED cap (week_aed_cap, model spend of fn knowledge_exam since the run opened, read from
--     ai_cost_log before every post) and is closed 'capped', 'failed' (max_failed_posts posts answered other than 200) or 'done';
--   * THE ALARM, the IT engineer's findings duty:seat_exam:* (fn_it_duty_settle): a run capped or failed; a run not finished
--     deadline_hours after it opened; a fix that did not hold (the
--     lesson is in the seat's knowledge and the seat missed the item again); a run whose wordings mostly failed. A duty
--     that stops running or fails is fn_seat_duty_health's, as for every seat duty.
-- graded_by gains 'model' (the in-company judge); 'claude' stays for the rows a session judged.
-- Revoked from public, anon, authenticated; search_path pinned; the table has RLS and a service-role-only policy.
-- DEPLOY: it_engineer (seat_exam.ts + the action) BEFORE this apply, or the first post answers unknown_action (a failed post,
-- three of which close the run 'failed' and raise the finding: loud, not silent).
-- prevented by: supabase/functions/it_engineer/seat_exam.test.ts (the batch), the verdict row of the probe
--   scripts/sql/the_company_runs_its_own_weekly_seat_exam_probe.sql (local Postgres), and the verdict row at the end of this file.
set local lock_timeout = '3s';

-- ── 1. The policy, held as data ──────────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('seat_exam_weekly', jsonb_build_object('per_seat', 3, 'week_aed_cap', 10, 'dow', 0, 'hour_dubai', 8, 'deadline_hours', 30,
                                          'max_failed_posts', 3),
   'The weekly model-on seat exam (ledger 1084; scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql): items per seat, '
   || 'the week''s AED cap on fn knowledge_exam model spend, the Dubai day (0 = Sunday) and hour it opens, the hours it has to finish, '
   || 'and how many failed posts close it.')
on conflict (key) do nothing;

-- ── 2. The judge the company uses is the model ───────────────────────────────────────────────────────────────────────
alter table public.seat_exam_asked drop constraint if exists seat_exam_asked_graded_by_check;
alter table public.seat_exam_asked add constraint seat_exam_asked_graded_by_check check (graded_by = any (array['code', 'claude', 'model']));

-- ── 3. The run: one row a week, its own result ───────────────────────────────────────────────────────────────────────
create table if not exists public.seat_exam_run (
  id bigserial primary key,
  week date not null unique,                 -- the Dubai date of the run's week (its exam day)
  run_tag text not null unique,              -- seat_exam_asked.run_tag of every ask of this run
  planned jsonb not null,                    -- [{item_id, seat, open_fix}] in the order they are asked
  status text not null default 'open' check (status in ('open', 'done', 'capped', 'failed')),
  cap_aed numeric not null,
  spent_aed numeric not null default 0,
  asked int not null default 0, passed int not null default 0, missed int not null default 0,
  no_wording int not null default 0, lessons int not null default 0,
  posts int not null default 0, failed_posts int not null default 0,
  request_id bigint, http_status int, http_error text, posted_at timestamptz,
  created_at timestamptz not null default now(), finished_at timestamptz, note text);
comment on table public.seat_exam_run is 'One row per weekly model-on seat exam the company runs itself (ledger 1084): what was planned, asked, passed and missed, the lessons written, the AED spent and how it ended. scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql.';
alter table public.seat_exam_run enable row level security;
drop policy if exists seat_exam_run_service_role_only on public.seat_exam_run;
create policy seat_exam_run_service_role_only on public.seat_exam_run as permissive for all to public using (false) with check (false);
revoke all on public.seat_exam_run from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('seat_exam_run', true, 'it_engineer',
   'One row per weekly seat exam the company runs (ledger 1084): planned items, results, lessons, AED spent; the asks are in seat_exam_asked.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

-- ── 4. Which items a run asks ────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_exam_plan(p_per_seat integer default 3)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with last as (select item_id, max(asked_at) at from public.seat_exam_asked group by item_id),
  open as (select distinct item_id from public.seat_exam_fix where status = 'open'),
  ranked as (
    select i.seat, i.item_id, (o.item_id is not null) open_fix,
           row_number() over (partition by i.seat order by (o.item_id is not null) desc, l.at nulls first, i.item_id) rn,
           count(o.item_id) over (partition by i.seat) n_open
      from public.seat_exam_item i
      left join last l on l.item_id = i.item_id
      left join open o on o.item_id = i.item_id
     where coalesce(array_length(i.expected_facts, 1), 0) > 0)
  -- every open fix of a seat is re-asked, up to twice the per-seat count; then the least recently asked
  select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'seat', seat, 'open_fix', open_fix) order by seat, rn), '[]'::jsonb)
    from ranked
   where rn <= least(greatest(greatest(p_per_seat, 1), n_open), 2 * greatest(p_per_seat, 1));
$fn$;
revoke execute on function public.fn_seat_exam_plan(integer) from public, anon, authenticated;

-- What the run has spent: every model call of fn knowledge_exam since it opened.
create or replace function public.fn_seat_exam_spent(p_since timestamptz)
returns numeric language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(sum(cost_aed), 0)::numeric(12, 4) from public.ai_cost_log where fn = 'knowledge_exam' and occurred_at >= p_since;
$fn$;
revoke execute on function public.fn_seat_exam_spent(timestamptz) from public, anon, authenticated;

-- ── 5. What the it_engineer function asks next ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_exam_next(p_run_id bigint, p_n integer default 1)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.seat_exam_run; v_items jsonb;
begin
  select * into r from public.seat_exam_run where id = p_run_id;
  if not found then return jsonb_build_object('items', '[]'::jsonb, 'stop', 'no_such_run'); end if;
  if r.status <> 'open' then return jsonb_build_object('items', '[]'::jsonb, 'stop', 'run_' || r.status); end if;
  if public.fn_seat_exam_spent(r.created_at) >= r.cap_aed then
    return jsonb_build_object('items', '[]'::jsonb, 'stop', 'week_cap');
  end if;
  select coalesce(jsonb_agg(x.j order by x.ord), '[]'::jsonb) into v_items from (
    select p.ord, jsonb_build_object('item_id', i.item_id, 'seat', i.seat, 'q_en', i.q_en, 'expected_facts', to_jsonb(i.expected_facts),
             'used_wordings', coalesce((select jsonb_agg(a.wording order by a.asked_at) from public.seat_exam_asked a
                                         where a.item_id = i.item_id and coalesce(a.wording, '') <> ''), '[]'::jsonb),
             'fix_id', f.id, 'fix_ref', f.fix_ref) j
      from jsonb_array_elements(r.planned) with ordinality p(e, ord)
      join public.seat_exam_item i on i.item_id = p.e->>'item_id' and i.seat = p.e->>'seat'
      left join public.seat_exam_fix f on f.item_id = i.item_id and f.status = 'open'
     where not exists (select 1 from public.seat_exam_asked a where a.run_tag = r.run_tag and a.item_id = i.item_id)
     order by p.ord limit greatest(coalesce(p_n, 1), 1)) x;
  return jsonb_build_object('items', v_items, 'stop', null);
end $fn$;
revoke execute on function public.fn_seat_exam_next(bigint, integer) from public, anon, authenticated;

-- ── 6. One ask recorded; a miss opens a fix, a pass closes a fix that was made ───────────────────────────────────────
create or replace function public.fn_seat_exam_record(p_run_id bigint, p_item_id text, p_seat text, p_wording text, p_answer text,
  p_model text, p_status text, p_pass boolean, p_graded_by text, p_missing text[])
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.seat_exam_run; f public.seat_exam_fix; v_asked bigint; v_fix bigint; v_lesson boolean := false;
        v_miss boolean := not coalesce(p_pass, false) and p_status <> 'no_wording';
begin
  select * into r from public.seat_exam_run where id = p_run_id for update;
  if not found then raise exception 'fn_seat_exam_record: no seat_exam_run %', p_run_id; end if;
  if not exists (select 1 from jsonb_array_elements(r.planned) e where e->>'item_id' = p_item_id and e->>'seat' = p_seat) then
    raise exception 'fn_seat_exam_record: % (%) is not planned in run %', p_item_id, p_seat, p_run_id;
  end if;
  if exists (select 1 from public.seat_exam_asked where run_tag = r.run_tag and item_id = p_item_id) then
    raise exception 'fn_seat_exam_record: % was already asked in run %', p_item_id, p_run_id;
  end if;
  select * into f from public.seat_exam_fix where item_id = p_item_id and status = 'open' order by id limit 1;
  insert into public.seat_exam_asked (run_tag, seat, item_id, wording, answer, model, status, pass, graded_by, missing, fix_id)
  values (r.run_tag, p_seat, p_item_id, coalesce(p_wording, ''), coalesce(p_answer, ''), p_model, p_status, coalesce(p_pass, false),
          p_graded_by, coalesce(p_missing, '{}'::text[]), f.id)
  returning id into v_asked;
  v_fix := f.id;
  if v_miss and f.id is null then
    insert into public.seat_exam_fix (seat, item_id, opened_run) values (p_seat, p_item_id, r.run_tag) returning id into v_fix;
    v_lesson := true;
  elsif v_miss and f.fix_ref is null then
    v_lesson := true;                                   -- the fix was never made: make it now
  elsif coalesce(p_pass, false) and f.fix_ref is not null then
    update public.seat_exam_fix set status = 'closed', closed_at = now(), closed_by_asked_id = v_asked where id = f.id;
  end if;
  update public.seat_exam_run set asked = asked + 1, passed = passed + (case when coalesce(p_pass, false) then 1 else 0 end),
         missed = missed + (case when v_miss then 1 else 0 end), no_wording = no_wording + (case when p_status = 'no_wording' then 1 else 0 end)
   where id = r.id;
  return jsonb_build_object('asked_id', v_asked, 'fix_id', v_fix, 'lesson_needed', v_lesson);
end $fn$;
revoke execute on function public.fn_seat_exam_record(bigint, text, text, text, text, text, text, boolean, text, text[]) from public, anon, authenticated;

-- ── 7. The fix: the item's canon into the seat's own knowledge ───────────────────────────────────────────────────────
create or replace function public.fn_seat_exam_fix_lesson(p_fix_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.seat_exam_fix; i public.seat_exam_item; v_id bigint; v_content text;
begin
  select * into f from public.seat_exam_fix where id = p_fix_id for update;
  if not found or f.status <> 'open' then raise exception 'fn_seat_exam_fix_lesson: no open fix %', p_fix_id; end if;
  select * into i from public.seat_exam_item where item_id = f.item_id and seat = f.seat;
  if not found then raise exception 'fn_seat_exam_fix_lesson: fix % names item % that is not loaded', p_fix_id, f.item_id; end if;
  v_content := 'Question: ' || i.q_en || E'\n'
            || 'A correct answer states: ' || array_to_string(i.expected_facts, '; ') || '.' || E'\n'
            || 'Source: ' || coalesce(nullif(array_to_string(i.expected_entry_ids, ', '), ''), 'the seat''s exam') || ' ('
            || coalesce(i.source_file, 'knowledge/exams') || ').';
  select id into v_id from public.agent_knowledge where source_ref = 'seat_exam_fix:' || f.id;
  if v_id is null then
    insert into public.agent_knowledge (agent_key, topic, content, priority, layer, source_ref, owner_agent, validation_status, supporting_evidence)
    values (f.seat, 'Exam lesson: ' || left(i.q_en, 180), v_content, 7, 'profession', 'seat_exam_fix:' || f.id, 'it_engineer', 'author_verified',
            'The seat missed exam item ' || f.item_id || ' (run ' || f.opened_run || '); the canon is the reviewed exam in '
            || coalesce(i.source_file, 'knowledge/exams') || '.')
    returning id into v_id;
  end if;
  update public.seat_exam_fix set kind = 'knowledge_ingest', fix_ref = 'agent_knowledge:' || v_id where id = f.id;
  update public.seat_exam_run set lessons = lessons + 1
   where id = (select id from public.seat_exam_run where status = 'open' order by week desc limit 1);
  return jsonb_build_object('knowledge_id', v_id, 'content', v_content, 'fix_id', f.id);
end $fn$;
revoke execute on function public.fn_seat_exam_fix_lesson(bigint) from public, anon, authenticated;

-- ── 8. The duty: open the week's run, post it until done, and say when it is not ─────────────────────────────────────
create or replace function public.fn_it_engineer_seat_exam_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare pol jsonb := coalesce((select value from public.decision_policy where key = 'seat_exam_weekly'), '{}'::jsonb);
        v_dow int := coalesce((pol->>'dow')::int, 0); v_hour int := coalesce((pol->>'hour_dubai')::int, 8);
        v_deadline interval := make_interval(hours => coalesce((pol->>'deadline_hours')::int, 30));
        v_max_failed int := coalesce((pol->>'max_failed_posts')::int, 3);
        v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
        v_week date; v_due timestamptz; r public.seat_exam_run; v_plan jsonb; v_ref text; v_key text; v_cred text; v_req bigint;
        v_items jsonb := '[]'::jsonb; v_action text := 'idle'; v_remaining int; x record;
begin
  if not pg_try_advisory_xact_lock(hashtext('qd.seat_exam_tick')) then
    return jsonb_build_object('busy', true);
  end if;
  -- 1. the answer of the last post
  update public.seat_exam_run s
     set http_status = coalesce(h.status_code, 0),
         http_error = case when h.status_code = 200 then null else left(coalesce(h.error_msg, h.content::text, 'no answer'), 500) end,
         failed_posts = case when h.status_code = 200 then 0 else s.failed_posts + 1 end
    from net._http_response h
   where h.id = s.request_id and s.http_status is null;
  -- a post with no answer after 10 minutes is a failed post
  update public.seat_exam_run set http_status = 0, http_error = 'no answer within 10 minutes', failed_posts = failed_posts + 1
   where status = 'open' and request_id is not null and http_status is null and posted_at < now() - interval '10 minutes';

  -- 2. this week's run: the exam day's date, due at its hour (Dubai)
  v_week := (v_now_dxb::date - ((extract(dow from v_now_dxb)::int - v_dow + 7) % 7));
  v_due := (v_week + make_interval(hours => v_hour)) at time zone 'Asia/Dubai';
  if now() >= v_due and not exists (select 1 from public.seat_exam_run where week = v_week) then
    -- a run of an earlier week still open is closed: a week's exam belongs to its week
    update public.seat_exam_run set status = 'failed', finished_at = now(), note = 'not finished within its week'
     where status = 'open' and week < v_week;
    v_plan := public.fn_seat_exam_plan(coalesce((pol->>'per_seat')::int, 3));
    insert into public.seat_exam_run (week, run_tag, planned, cap_aed, status, finished_at, note)
    values (v_week, 'exam:' || to_char(v_week, 'YYYY-MM-DD'), v_plan, coalesce((pol->>'week_aed_cap')::numeric, 10),
            case when jsonb_array_length(v_plan) = 0 then 'done' else 'open' end,
            case when jsonb_array_length(v_plan) = 0 then now() end,
            case when jsonb_array_length(v_plan) = 0 then 'no exam item is loaded' end);
    v_action := 'opened';
  end if;

  -- 3. the open run: finished, capped, failed, waiting on its post, or posted again
  select * into r from public.seat_exam_run where status = 'open' order by week desc limit 1;
  if found then
    v_remaining := jsonb_array_length(r.planned)
                   - (select count(*) from public.seat_exam_asked a where a.run_tag = r.run_tag
                        and exists (select 1 from jsonb_array_elements(r.planned) e where e->>'item_id' = a.item_id));
    update public.seat_exam_run set spent_aed = public.fn_seat_exam_spent(r.created_at) where id = r.id returning * into r;
    if v_remaining <= 0 then
      update public.seat_exam_run set status = 'done', finished_at = now() where id = r.id;   v_action := 'done';
    elsif r.spent_aed >= r.cap_aed then
      update public.seat_exam_run set status = 'capped', finished_at = now(),
             note = format('stopped at AED %s of its AED %s cap with %s item(s) unasked', r.spent_aed, r.cap_aed, v_remaining)
       where id = r.id;   v_action := 'capped';
    elsif r.failed_posts >= v_max_failed then
      update public.seat_exam_run set status = 'failed', finished_at = now(),
             note = format('%s posts running answered other than 200: %s', r.failed_posts, coalesce(r.http_error, '?'))
       where id = r.id;   v_action := 'failed';
    elsif r.request_id is not null and r.http_status is null then
      v_action := 'waiting';
    else
      select value into v_ref from public.app_secrets where key = 'project_ref';
      v_key := public.fn_gateway_client_key();
      select value into v_cred from public.app_secrets where key = 'cred_fn_it_engineer';
      if coalesce(v_ref, '') = '' or coalesce(v_key, '') = '' or coalesce(v_cred, '') = '' then
        -- a duty that cannot post has failed: fn_seat_duty_health shows it red
        raise exception 'fn_it_engineer_seat_exam_tick: project_ref, the gateway key or cred_fn_it_engineer is missing from app_secrets';
      end if;
      v_req := net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/it_engineer',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key),
        body := jsonb_build_object('__secret', v_cred, 'action', 'seat_exam', 'run_id', r.id),
        timeout_milliseconds := 150000);
      update public.seat_exam_run set request_id = v_req, http_status = null, http_error = null, posted_at = now(), posts = posts + 1
       where id = r.id;
      v_action := 'posted';
    end if;
  end if;

  -- 4. the alarm
  for x in select * from public.seat_exam_run where week >= v_week - 7 order by week loop
    if x.status in ('capped', 'failed') then
      v_items := v_items || jsonb_build_object('item', 'run:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ' ended ' || x.status || ': ' || coalesce(x.note, '?'),
        'evidence', jsonb_build_object('run_id', x.id, 'asked', x.asked, 'planned', jsonb_array_length(x.planned), 'spent_aed', x.spent_aed,
                                       'cap_aed', x.cap_aed, 'http_error', x.http_error));
    elsif x.status = 'open' and x.created_at < now() - v_deadline then
      v_items := v_items || jsonb_build_object('item', 'late:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ' is not finished ' || extract(hour from v_deadline) || ' hours after it opened ('
                 || x.asked || ' of ' || jsonb_array_length(x.planned) || ' asked)',
        'evidence', jsonb_build_object('run_id', x.id, 'posts', x.posts, 'failed_posts', x.failed_posts, 'http_error', x.http_error));
    elsif x.status = 'done' and x.no_wording * 2 > greatest(x.asked, 1) then
      v_items := v_items || jsonb_build_object('item', 'wording:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ' could not word ' || x.no_wording || ' of ' || x.asked || ' questions',
        'evidence', jsonb_build_object('run_id', x.id, 'look_at', 'ai_cost_log fn knowledge_exam task routine_employee_reasoning'));
    end if;
  end loop;
  -- a fix that did not hold: the lesson is in the seat's knowledge and a later ask of the item still missed
  for x in select f.id, f.seat, f.item_id, f.fix_ref, k.created_at made_at
             from public.seat_exam_fix f
             join public.agent_knowledge k on 'agent_knowledge:' || k.id = f.fix_ref
            where f.status = 'open'
              and exists (select 1 from public.seat_exam_asked a where a.item_id = f.item_id and a.asked_at > k.created_at
                            and not a.pass and a.status <> 'no_wording') loop
    v_items := v_items || jsonb_build_object('item', 'fix_did_not_hold:' || x.item_id, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
      'title', 'The ' || x.seat || ' seat missed exam item ' || x.item_id || ' again after its lesson was written: the knowledge is there and '
               || 'the seat does not use it (retrieval or the prompt, an engineer session)',
      'evidence', jsonb_build_object('fix_id', x.id, 'fix_ref', x.fix_ref, 'lesson_written_at', x.made_at));
  end loop;
  return jsonb_build_object('action', v_action, 'week', v_week, 'run', (select to_jsonb(s) - 'planned' from public.seat_exam_run s where s.week = v_week),
                            'settle', public.fn_it_duty_settle('seat_exam', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_seat_exam_tick() from public, anon, authenticated;

-- The duty that held the retired exam is the one that runs it now (one subject, one duty).
update public.seat_duty set routine = 'fn_it_engineer_seat_exam_tick', every = interval '10 minutes', enabled = true, failures = 0,
       last_error = null, owner_file = 'scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql',
       what = 'Weekly, the company''s own model-on seat exam (ledger 1084): a run in seat_exam_run, fresh wordings, the seat''s real answer '
           || 'through think(), graded by code then the model, a miss fixed in the seat''s own knowledge and re-asked the next week; '
           || 'capped in AED by decision_policy seat_exam_weekly; findings duty:seat_exam:* when a run fails, is late or a fix does not hold.'
 where duty = 'it_engineer.knowledge_exam';
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
select 'it_engineer.knowledge_exam', 'it_engineer', interval '10 minutes', 'fn_it_engineer_seat_exam_tick',
       'Weekly, the company''s own model-on seat exam (ledger 1084); see scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql.',
       'scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql'
 where not exists (select 1 from public.seat_duty where duty = 'it_engineer.knowledge_exam');

-- verdict (read-only)
select case
  when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prosecdef
           and p.proname in ('fn_seat_exam_plan', 'fn_seat_exam_spent', 'fn_seat_exam_next', 'fn_seat_exam_record', 'fn_seat_exam_fix_lesson',
                             'fn_it_engineer_seat_exam_tick')
           and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
           and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) <> 6
    then 'PROBE FAILED: a routine is missing, open or unpinned'
  when not exists (select 1 from public.seat_duty where duty = 'it_engineer.knowledge_exam' and enabled and routine = 'fn_it_engineer_seat_exam_tick')
    then 'PROBE FAILED: the duty does not run the exam'
  when not (select relrowsecurity from pg_class where oid = 'public.seat_exam_run'::regclass)
    or has_table_privilege('anon', 'public.seat_exam_run', 'select') or has_table_privilege('authenticated', 'public.seat_exam_run', 'select')
    then 'PROBE FAILED: seat_exam_run is readable outside the service role'
  else 'PROBE OK' end as verdict;
