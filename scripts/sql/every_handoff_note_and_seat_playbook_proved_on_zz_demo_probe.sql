-- PROBE: every handoff carries its note, and a recorded lesson rewrites the seat's playbook.
-- Seat: it_engineer. Founder instruction 1013, items 6 and 9, 29 Sep 2026.
--
-- A PURE PROBE: no DDL, one DO block, ends with raise exception 'CHK<<...>>' so NOTHING it writes
-- survives (the ZZ DEMO case, its handoff, its lesson, the playbook rebuild all roll back).
-- It cannot reach a person: the case is 'zz_demo_case#ZZ-DEMO-1013' (no such table, no customer, no
-- supplier), the handoff is written straight into public.agent_actions so NO handler runs, and the probe
-- asserts that not one public.notifications row was queued while it ran.
--
-- Proves, against the objects in
--   scripts/sql/every_handoff_carries_a_note_of_what_is_known_tried_and_needed.sql
--   scripts/sql/every_seat_keeps_a_living_playbook.sql
--   a. a handoff gains detail->'summary' with known / tried / needed / evidence, built from the case's rows
--      (the earlier ZZ DEMO action and case memory appear under tried, and in evidence)
--   b. a handoff that names no case is refused
--   c. a handoff row without a note is refused by the CHECK even with triggers off
--   d. the receiving seat's recall reads the note first (fn_seat_handoff_notes)
--   e. a lesson recorded on the seat's case memory rebuilds that seat's playbook, and the lesson is in it
do $probe$
declare
  k public.seat_handoff_kind; v_before int; v_after int; v_note jsonb; v_hid bigint; v_prior bigint; v_case bigint;
  v_notif bigint := coalesce((select max(id) from public.notifications), 0); v_refused text := 'NOT refused';
  v_check text := 'NOT refused'; v_notes jsonb; pb public.seat_playbook; v_fail text := '';
begin
  select * into k from public.seat_handoff_kind where to_seat = 'sales_engineer' order by type, from_seat limit 1;
  if k.type is null then raise exception 'CHK<<PROBE FAILED: no conversation is handed to sales_engineer>>'; end if;
  v_before := coalesce((select version from public.seat_playbook where seat = 'sales_engineer'), 0);

  -- The case's existing rows: one earlier action, one remembered case with a lesson (the learning loop).
  insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id)
  values ('sales_engineer', 'zz_demo_note', 'done', 'low', 'ZZ DEMO earlier attempt on the case', 'zz_demo_case', 'ZZ-DEMO-1013')
  returning id into v_prior;
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, situation, decision, lessons)
  values ('sales_engineer', 'zz_demo', 'zz_demo_case', 'ZZ-DEMO-1013', 'ZZ DEMO situation for probe 1013',
          'ZZ DEMO decision', array['ZZ DEMO lesson 1013: confirm the unit before quoting'])
  returning id into v_case;

  -- a. the handoff, shaped exactly as fn_seat_handoff writes it
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'ZZ DEMO handoff for probe 1013',
          jsonb_build_object('type', k.type, 'from', k.from_seat, 'from_name', k.from_seat, 'to', 'sales_engineer',
                             'subject_table', 'zz_demo_case', 'subject_id', 'ZZ-DEMO-1013', 'zz_fact', 'ZZ DEMO fact'),
          'zz_demo_case', k.type || ':ZZ-DEMO-1013')
  returning id, detail->'summary' into v_hid, v_note;
  if v_note is null or not (v_note ?& array['known','tried','needed','evidence']) then v_fail := v_fail || ' a:no-four-parts'; end if;
  if v_note->'known'->>'case' <> 'zz_demo_case#ZZ-DEMO-1013' then v_fail := v_fail || ' a:case'; end if;
  if v_note->'known'->'facts'->>'zz_fact' is distinct from 'ZZ DEMO fact' then v_fail := v_fail || ' a:facts'; end if;
  if not (v_note->'tried'->'actions') @> jsonb_build_array(jsonb_build_object('action_id', v_prior)) then v_fail := v_fail || ' a:tried-action'; end if;
  if not (v_note->'tried'->'case_memory') @> jsonb_build_array(jsonb_build_object('case_id', v_case)) then v_fail := v_fail || ' a:tried-case'; end if;
  if v_note->'needed'->>'ask' is distinct from k.meaning then v_fail := v_fail || ' a:needed'; end if;
  if not (v_note->'evidence') @> jsonb_build_array('public.agent_actions?id=eq.' || v_prior, 'public.seat_case_memory?id=eq.' || v_case) then v_fail := v_fail || ' a:evidence'; end if;

  -- b. no case, no handoff
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, detail)
    values ('sales_engineer', 'handoff', 'pending', 'low', 'ZZ DEMO handoff with no case', jsonb_build_object('type', k.type, 'from', k.from_seat));
  exception when others then v_refused := 'refused: ' || left(sqlerrm, 80);
  end;
  if v_refused like 'NOT%' then v_fail := v_fail || ' b'; end if;

  -- c. the CHECK holds with triggers off
  begin
    set local session_replication_role = replica;
    begin
      insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
      values ('sales_engineer', 'handoff', 'pending', 'low', 'ZZ DEMO handoff without a note', '{}'::jsonb, 'zz_demo_case', 'zz:ZZ-DEMO-1013-c');
    exception when check_violation then v_check := 'refused by agent_actions_handoff_carries_its_note';
    end;
    set local session_replication_role = origin;
  exception when insufficient_privilege then v_check := 'not measurable: session_replication_role not settable';
  end;
  if v_check like 'NOT%' then v_fail := v_fail || ' c'; end if;

  -- d. the recall reads it first
  v_notes := public.fn_seat_handoff_notes('sales_engineer', 'zz_demo_case', 'ZZ-DEMO-1013');
  if (v_notes->0->>'handoff_id')::bigint is distinct from v_hid or v_notes->0->'summary' is null then v_fail := v_fail || ' d'; end if;

  -- e. the lesson rewrote the playbook
  select * into pb from public.seat_playbook where seat = 'sales_engineer';
  v_after := coalesce(pb.version, 0);
  if v_after <= v_before then v_fail := v_fail || ' e:version'; end if;
  if position('ZZ DEMO lesson 1013' in coalesce(pb.markdown, '')) = 0 then v_fail := v_fail || ' e:lesson-missing'; end if;
  if pb.rebuilt_reason is distinct from 'lesson recorded on case #' || v_case then v_fail := v_fail || ' e:reason'; end if;

  -- nobody was reached
  if exists (select 1 from public.notifications where id > v_notif) then v_fail := v_fail || ' notified-someone'; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end,
    'handoff_id', v_hid, 'note', v_note, 'no_case', v_refused, 'check', v_check,
    'recall_first', v_notes->0->'handoff_id', 'playbook_version', jsonb_build_array(v_before, v_after),
    'rebuilt_reason', pb.rebuilt_reason)::text;
end $probe$;
