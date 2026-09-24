-- EVERY SERIOUS INCIDENT GETS A POSTMORTEM: ITS ROOT CAUSE AND A CHECK THAT FAILS IF IT RETURNS.
-- Seat: it_engineer. 24 Sep 2026, seat audit (GAPS.md IT gap 7; founder_instruction 573; ledger 983). Needs
-- every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql (it_incident, it_playbook,
-- fn_it_incident_open) and seat_duty.
--
-- WHAT WAS MEASURED (production, 24 Sep 2026): it_incident holds 216 records, opened only when a finding went up to
--   the founder as a new bug. Of 701 it.finding handoffs of severity critical or high that were CLOSED, 516 have no
--   incident record at all, so no cause and no regression check was ever written for them.
--
-- WHAT THIS ADDS: seat_duty it_engineer.postmortem (1 hour).
--   1. Every critical/high it.finding handoff closed AFTER this duty was registered gets an incident record
--      (fn_it_incident_open). The 516 historical ones are NOT back-filled: re-asking a model about 516 closed
--      faults is exactly the credit spend the founder ruled out (24 Sep, routine work is code); they are counted
--      in the result so the number is visible.
--   2. Deterministic first: when the issue key belongs to a known failure class (it_playbook), the postmortem is
--      written from the playbook — cause = its typical cause, regression check = its check — with no model.
--   3. Only a class the playbook has never seen is judgement: its root cause is asked of think() once, in the
--      it_engineer's own queue (surface it_engineer.postmortem, at most 3 new questions a run), and the answer is
--      written into the incident by fn_reason_apply_it_engineer__postmortem.
--   4. A postmortem still without its cause or regression check 72 hours after the fault closed is one finding
--      duty:postmortem:incomplete for the it_engineer: a new class needs a check written into the repository,
--      which is engineering, and saying so is the honest end of what the duty can do alone.
--
--   node scripts/apply_sql.mjs scripts/sql/every_serious_incident_gets_a_postmortem.sql --apply --ddl

create or replace function public.fn_it_engineer_postmortem()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h record; v_inc bigint; p public.it_playbook; v_since timestamptz; n_open int := 0; n_play int := 0; n_asked int := 0;
        v_hist int; v_late int; v_ids jsonb; v_items jsonb := '[]'::jsonb; f public.it_engineer_finding;
begin
  select created_at into v_since from public.seat_duty where duty = 'it_engineer.postmortem';
  v_since := coalesce(v_since, now());

  for h in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
       and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
       and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
     order by a.id limit 50
  loop
    v_inc := public.fn_it_incident_open(h.id);
    n_open := n_open + 1;
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, h.decided_at, now()),
           fix = coalesce(fix, 'Closed: ' || coalesce(f.close_note, 'the ' || h.agent || ' answered and the finding cleared')),
           updated_at = now() where id = v_inc;
    select * into p from public.it_playbook where (h.detail->>'issue_key') like issue_prefix || '%'
     order by length(issue_prefix) desc limit 1;
    if found then
      update public.it_incident set playbook_class = p.failure_class,
             cause = coalesce(cause, p.typical_cause, 'Known failure class ' || p.failure_class || ': ' || coalesce(p.remedy, p.not_automatable_reason)),
             regression_check = coalesce(regression_check, p.regression_check), recorded_by = 'it_engineer.postmortem', updated_at = now()
       where id = v_inc;
      n_play := n_play + 1;
    elsif n_asked < 3 then
      perform public.fn_reason_hold('it_engineer', 'it_engineer.postmortem',
        'Postmortem: what was the root cause of this fault, in two or three sentences? ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
        jsonb_build_object('seat', 'it_engineer', 'surface', 'it_engineer.postmortem', 'research', false, 'stakes', 'normal',
          'question', 'Root cause of: ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
          'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('handoff', h.detail, 'answer', h.evidence,
            'finding', to_jsonb(f) - 'evidence')),
          'subject', jsonb_build_object('incident_id', v_inc), 'dedupeKey', 'postmortem:' || v_inc),
        jsonb_build_object('filed_by', 'it_engineer.postmortem'), jsonb_build_object('incident_id', v_inc), 'seat_duty', 'postmortem:' || v_inc);
      n_asked := n_asked + 1;
    end if;
  end loop;

  select count(*) into v_hist from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.detail->>'severity' in ('critical', 'high')
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id);

  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]') into v_late, v_ids
    from (select i.id, row_number() over (order by i.id) rn from public.it_incident i
           where i.ended_at < now() - interval '72 hours' and i.created_at >= v_since
             and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.regression_check), '') = '')) z;
  if v_late > 0 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'incomplete', 'owner_seat', 'it_engineer', 'blast', 'internal', 'affected', v_late,
      'title', v_late || ' closed incident(s) have no root cause or no regression check 72 hours after they closed',
      'evidence', jsonb_build_object('incident_ids', v_ids)));
  end if;

  return jsonb_build_object('opened', n_open, 'from_playbook', n_play, 'asked', n_asked,
                            'historical_without_postmortem', v_hist, 'settled', public.fn_it_duty_settle('postmortem', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_postmortem() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_postmortem() to service_role;

-- The reasoned root cause lands on the incident. A later run never overwrites a cause already written.
create or replace function public.fn_reason_apply_it_engineer__postmortem(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_inc bigint; v_ans text := btrim(coalesce(p_result->>'answer', ''));
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_inc := (r.subject->>'incident_id')::bigint;
  if v_ans = '' then raise exception 'EMPTY_ANSWER: postmortem question % came back empty', p_id; end if;
  update public.it_incident set cause = coalesce(nullif(btrim(cause), ''), left(v_ans, 2000)),
         recorded_by = coalesce(recorded_by, 'it_engineer.postmortem (' || coalesce(p_result->>'model', 'model') || ')'), updated_at = now()
   where id = v_inc;
  return jsonb_build_object('applied', found, 'incident_id', v_inc);
end $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__postmortem(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_it_engineer__postmortem(bigint, jsonb) to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.postmortem', 'it_engineer', interval '1 hour', 'fn_it_engineer_postmortem',
   'Every closed critical/high fault gets an incident record with its root cause (playbook first, think() only for a new class) and a regression check.',
   'scripts/sql/every_serious_incident_gets_a_postmortem.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

select case when to_regprocedure('public.fn_it_engineer_postmortem()') is not null
             and to_regprocedure('public.fn_reason_apply_it_engineer__postmortem(bigint,jsonb)') is not null
             and exists (select 1 from public.seat_duty where duty = 'it_engineer.postmortem')
            then 'PROBE OK' else 'PROBE FAILED: the postmortem duty is not registered' end as verdict;
