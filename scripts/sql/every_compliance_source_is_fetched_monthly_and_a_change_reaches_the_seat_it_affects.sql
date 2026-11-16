-- EVERY COMPLIANCE SOURCE IS FETCHED MONTHLY, AND A CHANGE REACHES THE SEAT IT AFFECTS (16 Nov 2026). Seat: it_engineer
-- (the fetch), with ceo (what changed and whose it is). Agent: OPS_LOOPS (it_engineer + ceo builder, wave 2 of the real-company
-- holes; hole H6 of the COO hunt).
--
-- MEASURED (production, read-only SELECT, 16 Nov 2026): all 17 active compliance_sources (Dubai Civil Defence, DEWA, SIRA,
-- Dubai Municipality, Estidama, ADIBC, RTA, TDRA, SEWA, Trakhees, DHA, EtihadWE, DBC, DDA, DoH, MoIAT, Sharjah
-- Municipality) were last checked 10 Aug 2026. No routine writes last_checked_at (READ: grep of scripts/sql, supabase/functions
-- and the mirror); the watcher went with the pre-7-Sep estate. fn_ceo_register_review re-issues the CEO a directive per stale
-- source every month (18 escalated, re-issued twice); an open branch (ceo-an-order-is-a-conversation-until-its-outcome) moves
-- that to one monthly batch to the it_engineer, "If no fetch exists yet, build it". This is the fetch.
--
-- WHAT THIS ADDS
--   1. The it_engineer's daily step compliance_watch (resilience_ping later duties; it_duty_schedule, 1 day) asks
--      fn_compliance_sources_due for up to 6 active sources not checked in 30 days (oldest first; one that failed today waits
--      for tomorrow) and the ALLOWLIST: the hosts the registered sources live on. _shared/compliance_watch.ts fetches each
--      through safeFetch, every request and redirect hop held to that allowlist, and records it here.
--   2. fn_compliance_sources_record: a failed fetch is NOT a check (last_fetch_error, fetch_failures + 1; last_checked_at kept).
--      A page whose readable-text signature is unchanged is stamped checked. A changed page (or the first read since August,
--      whose signature was taken by the old watcher) is stamped checked AND asked of the CEO seat's MODEL
--      (ceo.compliance_change): the old summary, the new text, the authority and topic, the live seats. The model states what
--      changed in plain words and picks the seat it affects, or none (nothing material changed).
--   3. fn_reason_apply_ceo__compliance_change: a change for a seat sets last_summary and last_changed_at (which emits
--      regulation.changed to its subscribers through trg_emit_regulation_changed, emit_regulation_changed.sql) and files a
--      compliance_update action to that seat with the change and the source; 'none' records the model's reading only. Code
--      checks the seat is live; it never reads the page's meaning.
--   4. fn_compliance_watch_settle: a source whose fetch failed three days running is an it_engineer finding (fn_it_duty_settle
--      'compliance_watch'), closed by the next good fetch; the run is recorded (fn_it_duty_ran), which is what makes it due.
-- WHAT IT DOES NOT CHANGE: fn_ceo_register_review and its directives (met by the stamp: no active source older than 35 days),
-- the regulation.changed trigger, any source's URL.
--
-- Probe: scripts/sql/every_compliance_source_is_fetched_monthly_and_a_change_reaches_the_seat_it_affects_probe.sql (local PG16)
-- Pending: scripts/sql/pending/every_compliance_source_is_fetched_monthly_and_a_change_reaches_the_seat_it_affects.txt
-- prevented by: supabase/functions/_shared/compliance_watch.test.ts, the probe, and
-- scripts/checks/the_ops_loops_close_against_what_they_measure.test.mjs.
-- Deploy order: apply this file, THEN deploy resilience_ping (the step calls these routines; before the apply it records an error).
--   node scripts/apply_sql.mjs scripts/sql/every_compliance_source_is_fetched_monthly_and_a_change_reaches_the_seat_it_affects.sql --apply --ddl

set local lock_timeout = '3s';
alter table public.compliance_sources
  add column if not exists last_fetch_at timestamptz,
  add column if not exists last_fetch_error text,
  add column if not exists fetch_failures integer not null default 0,
  add column if not exists change_held_id bigint,
  add column if not exists last_review jsonb;
comment on column public.compliance_sources.last_checked_at is
  'When the source was last fetched and read (compliance_watch, daily, a source at most every 30 days). A failed fetch does not move it.';

insert into public.it_duty_schedule (duty, every, note, owner_seat) values
  ('compliance_watch', interval '1 day',
   'it_engineer: up to 6 active compliance sources not checked in 30 days fetched from their own allowlisted hosts; a change goes to the CEO seat''s model and on to the seat it affects (_shared/compliance_watch.ts)',
   'it_engineer')
on conflict (duty) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

create or replace function public.fn_compliance_sources_due(p_limit integer default 6)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'sources', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'authority', s.authority, 'topic', s.topic, 'url', s.url)
                                          order by s.last_checked_at nulls first, s.id)
                           from (select * from public.compliance_sources c
                                  where c.active and c.url ~* '^https?://'
                                    and coalesce(c.last_checked_at, 'epoch') < now() - interval '30 days'
                                    and coalesce(c.last_fetch_at, 'epoch') < now() - interval '20 hours'
                                  order by c.last_checked_at nulls first, c.id
                                  limit greatest(1, least(coalesce(p_limit, 6), 20))) s), '[]'::jsonb),
    -- the allowlist: the hosts of the registered sources, and nothing else
    'allowed_hosts', coalesce((select jsonb_agg(distinct lower(substring(c.url from '^https?://([^/:?#]+)')))
                                 from public.compliance_sources c where c.active and c.url ~* '^https?://'), '[]'::jsonb));
$fn$;
revoke execute on function public.fn_compliance_sources_due(integer) from public, anon, authenticated;

create or replace function public.fn_compliance_sources_record(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c public.compliance_sources; v_sig text := nullif(btrim(coalesce(p->>'signature', '')), ''); v_hid bigint; v_q text; v_seats jsonb;
begin
  select * into c from public.compliance_sources where id = nullif(p->>'id', '')::bigint and active for update;
  if not found then return jsonb_build_object('outcome', 'unknown_source'); end if;
  if coalesce((p->>'ok')::boolean, false) is not true or v_sig is null then
    update public.compliance_sources
       set last_fetch_at = now(), last_fetch_error = left(coalesce(p->>'error', 'no reading'), 500), fetch_failures = fetch_failures + 1
     where id = c.id;
    return jsonb_build_object('outcome', 'failed', 'failures', c.fetch_failures + 1);
  end if;
  if v_sig = c.last_signature then
    update public.compliance_sources
       set last_checked_at = now(), last_fetch_at = now(), last_fetch_error = null, fetch_failures = 0
     where id = c.id;
    return jsonb_build_object('outcome', 'unchanged');
  end if;

  -- changed, or the first read since the old watcher: checked now, and what changed is the CEO seat's model's to say
  select coalesce(jsonb_agg(jsonb_build_object('id', o.role_id, 'meaning', left(o.responsibilities, 300)) order by o.role_id), '[]'::jsonb)
           || jsonb_build_array(jsonb_build_object('id', 'none', 'meaning', 'nothing material changed for the company'))
    into v_seats from public.org_role o where o.status = 'active';
  v_q := format('The %s page on %s was read again today. Compared with what we last recorded about it, what changed that matters to '
                || 'QuotesDone (a UAE marketplace where customers get quotes from licensed suppliers and contractors), in two or three '
                || 'plain sentences? Then pick the seat it affects, or none if nothing material changed.', c.authority, c.topic);
  v_hid := public.fn_reason_hold('ceo', 'ceo.compliance_change', v_q,
    jsonb_build_object('seat', 'ceo', 'surface', 'ceo.compliance_change', 'research', false, 'stakes', 'normal', 'question', v_q,
      'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object(
        'authority', c.authority, 'topic', c.topic, 'url', c.url, 'final_url', p->>'final_url',
        'what_we_last_recorded', coalesce(c.last_summary, '(nothing recorded)'), 'last_recorded_change', c.last_changed_at,
        'last_checked_before', c.last_checked_at, 'page_text_today', left(coalesce(p->>'excerpt', ''), 6000),
        'first_read_since_the_old_watcher', coalesce(c.last_signature, '') not like 'v2:%')),
      'decision', jsonb_build_object('name', 'affected_seat', 'options', v_seats),
      'subject', jsonb_build_object('compliance_source_id', c.id), 'dedupeKey', 'compliance_change:' || c.id || ':' || left(v_sig, 19)),
    jsonb_build_object('filed_by', 'it_engineer.compliance_watch'), jsonb_build_object('compliance_source_id', c.id),
    'seat_duty', 'compliance_change:' || c.id || ':' || left(v_sig, 19));
  update public.compliance_sources
     set last_checked_at = now(), last_fetch_at = now(), last_fetch_error = null, fetch_failures = 0,
         last_signature = v_sig, change_held_id = coalesce(v_hid, change_held_id)
   where id = c.id;
  return jsonb_build_object('outcome', 'asked', 'held_id', v_hid);
end $fn$;
revoke execute on function public.fn_compliance_sources_record(jsonb) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__compliance_change(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; c public.compliance_sources; v_choice text := p_result->'decision'->>'choice';
        v_ans text := btrim(coalesce(p_result->>'answer', '')); v_act bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  select * into c from public.compliance_sources where id = nullif(r.subject->>'compliance_source_id', '')::bigint;
  if c.id is null or v_choice is null or v_ans = ''
     or (v_choice <> 'none' and not exists (select 1 from public.org_role o where o.role_id = v_choice and o.status = 'active')) then
    return null;                                   -- stays 'reasoned' for the CEO seat to read
  end if;
  if v_choice = 'none' then
    update public.compliance_sources
       set last_review = jsonb_build_object('reviewed_at', now(), 'by', 'ceo.compliance_change', 'model', p_result->>'model',
                                            'held_id', p_id, 'material_change', false, 'reading', left(v_ans, 2000)),
           last_summary = coalesce(last_summary, left(v_ans, 2000))
     where id = c.id;
    return jsonb_build_object('compliance_source_id', c.id, 'material_change', false);
  end if;
  update public.compliance_sources
     set last_summary = left(v_ans, 2000), last_changed_at = now(),
         last_review = jsonb_build_object('reviewed_at', now(), 'by', 'ceo.compliance_change', 'model', p_result->>'model',
                                          'held_id', p_id, 'material_change', true, 'seat', v_choice)
   where id = c.id;                                -- last_changed_at moving emits regulation.changed to its subscribers
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values (v_choice, 'compliance_update', 'pending', 'medium',
          left('A compliance source changed: ' || c.authority || ' (' || c.topic || ')', 200), left(v_ans, 2000),
          jsonb_build_object('compliance_source_id', c.id, 'authority', c.authority, 'topic', c.topic, 'url', c.url,
                             'what_changed', left(v_ans, 2000), 'held_id', p_id, 'routed_by', 'ceo.compliance_change',
                             'needed', 'read the change and update what this seat does or says about it; close this with what you changed'),
          'compliance_sources', c.id::text)
  returning id into v_act;
  return jsonb_build_object('compliance_source_id', c.id, 'material_change', true, 'seat', v_choice, 'action_id', v_act);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__compliance_change(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_compliance_watch_settle(p_counts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_items jsonb; v_res jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', 'source:' || c.id, 'owner_seat', 'it_engineer', 'subject', 'compliance_watch', 'blast', 'internal', 'affected', 1,
           'title', 'The ' || c.authority || ' compliance source could not be read ' || c.fetch_failures || ' days running ('
                    || left(coalesce(c.last_fetch_error, 'no reason recorded'), 120) || ')',
           'evidence', jsonb_build_object('id', c.id, 'url', c.url, 'last_checked_at', c.last_checked_at, 'last_fetch_at', c.last_fetch_at,
                                          'error', c.last_fetch_error, 'fix', 'correct the source URL (the authority moved the page) or record why it cannot be fetched')) order by c.id), '[]'::jsonb)
    into v_items from public.compliance_sources c where c.active and c.fetch_failures >= 3;
  v_res := jsonb_build_object('counts', coalesce(p_counts, '{}'::jsonb), 'failing_3_days', jsonb_array_length(v_items),
    'stale_35_days', (select count(*) from public.compliance_sources where active and coalesce(last_checked_at, 'epoch') < now() - interval '35 days'),
    'settle', public.fn_it_duty_settle('compliance_watch', v_items));
  perform public.fn_it_duty_ran('compliance_watch', v_res);
  return v_res;
end $fn$;
revoke execute on function public.fn_compliance_watch_settle(jsonb) from public, anon, authenticated;

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when not exists (select 1 from public.it_duty_schedule where duty = 'compliance_watch') then 'PROBE FAILED: compliance_watch is not scheduled'
  when has_function_privilege('anon', 'public.fn_compliance_sources_due(integer)', 'execute')
    or has_function_privilege('anon', 'public.fn_compliance_sources_record(jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_reason_apply_ceo__compliance_change(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_compliance_watch_settle(jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute a compliance routine'
  else 'PROBE OK' end as verdict;
