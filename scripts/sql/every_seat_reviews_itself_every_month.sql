-- EVERY SEAT REVIEWS ITSELF EVERY MONTH.
-- Seat: ceo (the standard applies to every seat; each seat's duty is its own). 29 Sep 2026. Founder instruction 1009,
-- item (2): "A monthly self-review for EVERY seat: each seat re-runs its qualification exam (knowledge/exams) and its
-- senior-hire checklist, records the score and trend, and opens its own improvement task for anything that slipped.
-- Schedule it as a seat duty."
--
-- ══ MEASURED BEFORE WRITING (29 Sep 2026) ═══════════════════════════════════════════════════════════════
--   * knowledge/exams/<seat>.json exists for accountant, customer_support and it_engineer. ceo, marketing and
--     sales_engineer have NO exam file. Every item names its senior-hire checklist line ("checklist": "ACC-01" ...)
--     from the seat's job description, the expected pack entry ids and the facts the answer must carry.
--   * scripts/eval/seat_qualification_exam.mjs grades it: the English question is embedded (free gte-small) and put to
--     public.fn_reason_retrieve(seat, vector, 6) -- the routine the seat calls at decision time. PASS = an expected
--     entry is in the first 5 AND its 1,200-character excerpt carries every expected fact. It ran only by hand, and
--     nothing kept a score, a trend, or turned a slip into work.
--   * Postgres cannot embed a question, so the questions are stored WITH their vector: seat_exam_item, loaded from
--     knowledge/exams by `node scripts/eval/seat_qualification_exam.mjs --load` (the same embedder). A question is
--     embedded once; the retrieval it is graded against is re-run every month, so the score moves when the KNOWLEDGE
--     moves -- which is what a self-review measures.
--
-- ══ WHAT THIS ADDS ═══════════════════════════════════════════════════════════════════════════════════════
--   seat_exam_item          the exam, per seat, with the question's vector.
--   fn_seat_exam_grade(s)   the grader in SQL, the same rule as grade() in seat_qualification_exam.mjs.
--   seat_self_review        one row per month and seat: exam score, senior-hire checklist score (a checklist line
--                           passes when EVERY item under it passes), last month's scores, the trend, what slipped.
--   fn_seat_self_review(p_month, p_seat)  once per month and seat. SLIPPED is any of: an item that passed last month
--       and fails now; a checklist line that passed and fails now; the exam score or the checklist score below last
--       month's; either under 80 % (the senior bar the quarterly audit uses); no exam on file; an item not embedded.
--       Anything slipped -> the seat opens ITS OWN improvement (ceo_improvement, source self_review: a task and a
--       handoff to the seat) naming each slip, due the 5th of next month, closed by next month's self-review when
--       nothing slipped. Earlier open self_review improvements of the seat close the same way.
--   Duty: <seat>.self_review for every active seat, every day, idempotent by month (it runs on the first tick of the
--   month and answers already:true after).
--
-- Needs the_ceo_weekly_review_acts_on_every_missed_target.sql first (the 'self_review' source kind, due_on and
-- close_check on ceo_improvement). Pending: scripts/sql/pending/every_seat_reviews_itself_every_month.txt.
--   node scripts/apply_sql.mjs scripts/sql/every_seat_reviews_itself_every_month.sql --apply --ddl --seat ceo
--   node scripts/eval/seat_qualification_exam.mjs --load

create table if not exists public.seat_exam_item (
  seat               text not null references public.org_role (role_id),
  item_id            text not null,
  checklist          text not null,
  q_en               text not null,
  expected_entry_ids text[] not null check (cardinality(expected_entry_ids) > 0),
  expected_facts     text[] not null check (cardinality(expected_facts) > 0),
  q_vec              vector,                       -- gte-small, written by the loader; null = not embedded (fails)
  source_file        text not null,
  loaded_at          timestamptz not null default now(),
  primary key (seat, item_id)
);
alter table public.seat_exam_item enable row level security;
drop policy if exists seat_exam_item_service_role_only on public.seat_exam_item;
create policy seat_exam_item_service_role_only on public.seat_exam_item as permissive for all to public using (false) with check (false);
revoke all on public.seat_exam_item from anon, authenticated;

create table if not exists public.seat_self_review (
  month               date not null,               -- first day of the month, Asia/Dubai
  seat                text not null references public.org_role (role_id),
  items               int not null,
  passed              int not null,
  rate                numeric,
  checklist_lines     int not null,
  checklist_passed    int not null,
  checklist_rate      numeric,
  prev_rate           numeric,
  prev_checklist_rate numeric,
  trend               text not null check (trend in ('first', 'up', 'flat', 'down', 'no_exam')),
  passed_items        text[] not null default '{}',
  passed_lines        text[] not null default '{}',
  failing             jsonb not null default '[]'::jsonb,
  slipped             text[] not null default '{}',
  improvement_id      bigint,
  closed_improvements bigint[] not null default '{}',
  created_at          timestamptz not null default now(),
  primary key (month, seat)
);
alter table public.seat_self_review enable row level security;
drop policy if exists seat_self_review_service_role_only on public.seat_self_review;
create policy seat_self_review_service_role_only on public.seat_self_review as permissive for all to public using (false) with check (false);
revoke all on public.seat_self_review from anon, authenticated;

-- The grader: grade() of scripts/eval/seat_qualification_exam.mjs, in SQL. Top 5 of fn_reason_retrieve(seat, vec, 6);
-- pass when an expected id is among them and ITS excerpt carries every expected fact (case-insensitive).
create or replace function public.fn_seat_exam_grade(p_seat text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare e public.seat_exam_item; v_top jsonb; v_hit jsonb; v_pass boolean; v_found boolean; v_missing text[];
  v_out jsonb := '[]'::jsonb;
begin
  for e in select * from public.seat_exam_item where seat = p_seat order by item_id loop
    v_pass := false; v_found := false; v_missing := '{}';
    if e.q_vec is not null then
      select coalesce(jsonb_agg(x order by n), '[]'::jsonb) into v_top
        from jsonb_array_elements(public.fn_reason_retrieve(e.seat, e.q_vec, 6)) with ordinality t(x, n) where n <= 5;
      for v_hit in select x from jsonb_array_elements(v_top) x where x->>'id' = any(e.expected_entry_ids) loop
        if not v_found then   -- the facts reported missing are the first hit's, as in grade()
          v_missing := array(select f from unnest(e.expected_facts) f where strpos(lower(coalesce(v_hit->>'excerpt', '')), lower(f)) = 0);
        end if;
        v_found := true;
        if not exists (select 1 from unnest(e.expected_facts) f where strpos(lower(coalesce(v_hit->>'excerpt', '')), lower(f)) = 0) then
          v_pass := true;
        end if;
      end loop;
    end if;
    v_out := v_out || jsonb_build_object('id', e.item_id, 'checklist', e.checklist, 'pass', v_pass, 'found', v_found,
      'reason', case when v_pass then null
                     when e.q_vec is null then 'not embedded: run seat_qualification_exam.mjs --load'
                     when not v_found then 'expected entry not in the top 5'
                     else 'facts missing: ' || array_to_string(v_missing, ' | ') end);
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_seat_exam_grade(text) from public, anon, authenticated;
grant execute on function public.fn_seat_exam_grade(text) to service_role;

create or replace function public.fn_seat_self_review(p_month date, p_seat text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m date := date_trunc('month', p_month)::date; g jsonb; prev public.seat_self_review;
  v_items int; v_pass int; v_rate numeric; v_lines int; v_lpass int; v_lrate numeric;
  v_pitems text[]; v_plines text[]; v_slip text[] := '{}'; v_trend text; v_imp bigint; v_closed bigint[] := '{}'; r record;
begin
  if exists (select 1 from public.seat_self_review where month = v_m and seat = p_seat) then
    return jsonb_build_object('ok', true, 'seat', p_seat, 'month', v_m, 'already', true);
  end if;
  if not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return jsonb_build_object('ok', false, 'error', p_seat || ' is not an active seat');
  end if;

  g := public.fn_seat_exam_grade(p_seat);
  v_items := jsonb_array_length(g);
  v_pass := (select count(*) from jsonb_array_elements(g) x where (x->>'pass')::boolean);
  v_pitems := array(select x->>'id' from jsonb_array_elements(g) x where (x->>'pass')::boolean order by 1);
  -- a senior-hire checklist line passes when every exam item under it passes
  select count(*), count(*) filter (where ok), coalesce(array_agg(line order by line) filter (where ok), '{}')
    into v_lines, v_lpass, v_plines
    from (select x->>'checklist' as line, bool_and((x->>'pass')::boolean) as ok from jsonb_array_elements(g) x group by 1) c;
  v_rate := case when v_items > 0 then round(v_pass::numeric / v_items, 3) end;
  v_lrate := case when v_lines > 0 then round(v_lpass::numeric / v_lines, 3) end;

  select * into prev from public.seat_self_review where seat = p_seat and month < v_m order by month desc limit 1;

  if v_items = 0 then
    v_trend := 'no_exam';
    v_slip := v_slip || format('no qualification exam on file: write knowledge/exams/%s.json against the job description''s senior-hire checklist and load it (seat_qualification_exam.mjs --load)', p_seat);
  else
    v_trend := case when prev.month is null or prev.rate is null then 'first'
                    when v_rate > prev.rate then 'up' when v_rate < prev.rate then 'down' else 'flat' end;
    if prev.month is not null then
      v_slip := v_slip || array(select format('exam item %s passed in %s and fails now (%s)', x->>'id', to_char(prev.month, 'Mon YYYY'), x->>'reason')
                                  from jsonb_array_elements(g) x where not (x->>'pass')::boolean and x->>'id' = any(prev.passed_items) order by 1);
      v_slip := v_slip || array(select format('checklist line %s passed in %s and fails now', l, to_char(prev.month, 'Mon YYYY'))
                                  from unnest(prev.passed_lines) l where not (l = any(v_plines)) order by 1);
      if prev.rate is not null and v_rate < prev.rate then
        v_slip := v_slip || format('exam score fell from %s%% to %s%%', round(prev.rate * 100), round(v_rate * 100));
      end if;
      if prev.checklist_rate is not null and v_lrate < prev.checklist_rate then
        v_slip := v_slip || format('checklist score fell from %s%% to %s%%', round(prev.checklist_rate * 100), round(v_lrate * 100));
      end if;
    end if;
    if v_rate < 0.80 then v_slip := v_slip || format('exam score %s%% (%s of %s) is under the 80%% senior bar', round(v_rate * 100), v_pass, v_items); end if;
    if v_lrate < 0.80 then v_slip := v_slip || format('checklist score %s%% (%s of %s lines) is under the 80%% senior bar', round(v_lrate * 100), v_lpass, v_lines); end if;
    if exists (select 1 from jsonb_array_elements(g) x where x->>'reason' like 'not embedded%') then
      v_slip := v_slip || 'exam items not embedded: run seat_qualification_exam.mjs --load'::text;
    end if;
  end if;

  -- earlier self-review improvements of the seat close when nothing slipped this month
  if cardinality(v_slip) = 0 then
    for r in select id from public.ceo_improvement where source_kind = 'self_review' and seat = p_seat and status in ('open', 'assigned') loop
      perform public.fn_ceo_improvement_close(r.id, format('%s self-review of %s: nothing slipped (exam %s%%, checklist %s%%).',
        p_seat, to_char(v_m, 'Mon YYYY'), round(v_rate * 100), round(v_lrate * 100)));
      v_closed := v_closed || r.id;
    end loop;
  else
    v_imp := public.fn_ceo_improvement_open('self_review', p_seat || ':' || v_m, p_seat,
      format('%s self-review of %s, opened by the seat itself: %s. Due %s.', p_seat, to_char(v_m, 'Mon YYYY'),
             array_to_string(v_slip, '; '), to_char((v_m + interval '1 month')::date + 4, 'DD Mon YYYY')),
      jsonb_build_object('month', v_m, 'slipped', to_jsonb(v_slip), 'rate', v_rate, 'checklist_rate', v_lrate,
                         'failing', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(g) x where not (x->>'pass')::boolean)));
    if v_imp is not null then
      update public.ceo_improvement set due_on = (v_m + interval '1 month')::date + 4,
             close_check = 'Closes when next month''s self-review finds nothing slipped.'
       where id = v_imp;
    end if;
  end if;

  insert into public.seat_self_review (month, seat, items, passed, rate, checklist_lines, checklist_passed, checklist_rate,
    prev_rate, prev_checklist_rate, trend, passed_items, passed_lines, failing, slipped, improvement_id, closed_improvements)
  values (v_m, p_seat, v_items, v_pass, v_rate, coalesce(v_lines, 0), coalesce(v_lpass, 0), v_lrate,
    prev.rate, prev.checklist_rate, v_trend, v_pitems, v_plines,
    (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(g) x where not (x->>'pass')::boolean),
    v_slip, v_imp, v_closed);
  return jsonb_build_object('ok', true, 'seat', p_seat, 'month', v_m, 'items', v_items, 'passed', v_pass, 'rate', v_rate,
    'checklist_rate', v_lrate, 'trend', v_trend, 'slipped', cardinality(v_slip), 'improvement_id', v_imp, 'closed', cardinality(v_closed));
end $fn$;
revoke execute on function public.fn_seat_self_review(date, text) from public, anon, authenticated;
grant execute on function public.fn_seat_self_review(date, text) to service_role;

-- One duty per seat: fn_seat_duties_tick calls a routine with no arguments, so each seat's duty has its own door.
create or replace function public.fn_accountant_self_review() returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'accountant') $fn$;
revoke execute on function public.fn_accountant_self_review() from public, anon, authenticated;
create or replace function public.fn_ceo_self_review() returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'ceo') $fn$;
revoke execute on function public.fn_ceo_self_review() from public, anon, authenticated;
create or replace function public.fn_customer_support_self_review() returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'customer_support') $fn$;
revoke execute on function public.fn_customer_support_self_review() from public, anon, authenticated;
create or replace function public.fn_it_engineer_self_review() returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'it_engineer') $fn$;
revoke execute on function public.fn_it_engineer_self_review() from public, anon, authenticated;
create or replace function public.fn_marketing_self_review() returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'marketing') $fn$;
revoke execute on function public.fn_marketing_self_review() from public, anon, authenticated;
create or replace function public.fn_sales_engineer_self_review() returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'sales_engineer') $fn$;
revoke execute on function public.fn_sales_engineer_self_review() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
select s || '.self_review', s, interval '1 day', 'fn_' || s || '_self_review',
       'Monthly self-review: re-run the qualification exam (knowledge/exams) and the senior-hire checklist, record the score and trend, and open the seat''s own improvement for anything that slipped.',
       'scripts/sql/every_seat_reviews_itself_every_month.sql'
  from unnest(array['accountant', 'ceo', 'customer_support', 'it_engineer', 'marketing', 'sales_engineer']) s
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

