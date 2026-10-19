-- PROBE: a ZZ DEMO case crosses customer_support -> sales_engineer -> accountant -> customer_support; every
-- handoff carries a note with context / decision / open_asks / deadline, and each receiver's next action
-- cites the note it was handed. Seat: ceo. Founder ledger row 1013.
--
-- A PURE PROBE: no DDL of its own, one DO block ending in raise exception 'CHK<<...>>', so NOTHING survives.
-- Before apply it is read with the pending file in front of it, in ONE transaction:
--   cat <the .sql below> <this probe> > combined.sql && node scripts/qsql.mjs combined.sql
-- (the raise rolls back the DDL with the probe). After apply it is read on its own.
--
-- It cannot reach a person: the case is 'zz_demo_case#ZZ-DEMO-1013-HANDOVER' (no such table, no customer,
-- no supplier), the people in it are 'ZZ DEMO ...' at @example.invalid, the handoffs are written straight
-- into public.agent_actions so NO handler runs, and it asserts not one public.notifications row was queued.
--
-- Proves, against scripts/sql/every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.sql
--   a. each of the three handoffs gains a note with all four fields, deadline from the right source
--      (refund.requested: its 1 h reply window; spec.not_sure: its 24 h window; fraud.money_held, which has
--      no window: the deadline the accountant set)
--   b. each receiver's next action (fn_seat_handoff_complete, every way a handoff closes) cites the note
--   c. fn_handoff_citation_gaps counts all three cited, none uncited
--   d. a handoff row whose note lacks the four fields is refused by the CHECK even with triggers off
--   e. no e-mail address or phone number reaches any note (the case's facts carry both)
--   f. an UPDATE of an older handoff row never fails: a real legacy row (no four-field note) and a ZZ DEMO row
--      the builder cannot read both update, and gain the four fields (rolled back with everything else)
do $probe$
declare
  v_case text := 'ZZ-DEMO-1013-HANDOVER';
  v_notif bigint := coalesce((select max(id) from public.notifications), 0);
  v_t0 timestamptz := now();  -- decided_at is now(), the transaction's start
  v_ids bigint[] := '{}'; v_id bigint; v_note jsonb; v_ev jsonb; v_out jsonb := '[]'::jsonb; v_fail text := '';
  v_check text := 'NOT refused'; v_gaps jsonb; r record; v_legacy bigint; v_legacy_out text;
begin
  for r in select * from (values
      (1, 'customer_support', 'sales_engineer', 'spec.not_sure',    jsonb_build_object('customer_name', 'ZZ DEMO Customer 1013', 'customer_email', 'zz-demo-1013@example.invalid', 'customer_phone', '+971 50 123 4567', 'remark', 'ZZ DEMO: reach me at zz-demo-1013@example.invalid or +971 50 123 4567', 'question', 'ZZ DEMO: is 2.5 mm2 cable acceptable?')),
      (2, 'sales_engineer',   'accountant',     'refund.requested', jsonb_build_object('customer_email', 'zz-demo-1013@example.invalid', 'decision', 'ZZ DEMO: the spec cannot be met, refund the reveal', 'amount_aed', 15)),
      (3, 'accountant',       'customer_support','fraud.money_held', jsonb_build_object('customer_email', 'zz-demo-1013@example.invalid', 'deadline', (now() + interval '6 hours')::text))
    ) as t(n, f, t_seat, typ, payload) order by n
  loop
    if not exists (select 1 from public.seat_handoff_kind k where k.type = r.typ and k.from_seat = r.f and k.to_seat = r.t_seat) then
      v_fail := v_fail || ' unregistered:' || r.typ;
      continue;
    end if;
    -- shaped exactly as fn_seat_handoff writes it (fn_seat_handoff itself files nothing for a demo row, ruling 1199)
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values (r.t_seat, 'handoff', 'pending', 'low', left(r.typ || ' from ' || r.f || ' about zz_demo_case ' || v_case, 200),
            r.payload || jsonb_build_object('type', r.typ, 'from', r.f, 'from_name', r.f, 'to', r.t_seat,
                                            'subject_table', 'zz_demo_case', 'subject_id', v_case),
            'zz_demo_case', r.typ || ':' || v_case)
    returning id, detail->'summary' into v_id, v_note;
    v_ids := v_ids || v_id;

    -- a. four fields
    if not (v_note ?& array['context','decision','open_asks','deadline']) then v_fail := v_fail || format(' a%s:fields', r.n); end if;
    if jsonb_array_length(coalesce(v_note->'open_asks', '[]')) = 0 then v_fail := v_fail || format(' a%s:asks', r.n); end if;
    if r.n = 1 and v_note->>'deadline_source' not like 'reply window of spec.not_sure%' then v_fail := v_fail || ' a1:deadline'; end if;
    if r.n = 1 and not (v_note->'open_asks') ? 'ZZ DEMO: is 2.5 mm2 cable acceptable?' then v_fail := v_fail || ' a1:question'; end if;
    if r.n = 2 and v_note->>'deadline_source' not like 'reply window of refund.requested%' then v_fail := v_fail || ' a2:deadline'; end if;
    if r.n = 2 and v_note->>'decision' <> 'ZZ DEMO: the spec cannot be met, refund the reveal' then v_fail := v_fail || ' a2:decision'; end if;
    if r.n = 3 and v_note->>'deadline_source' <> 'set by accountant' then v_fail := v_fail || ' a3:deadline'; end if;
    -- the case's history grows as it crosses seats: the third note sees the first two handoffs
    if r.n = 3 and jsonb_array_length(v_note->'tried'->'actions') < 2 then v_fail := v_fail || ' a3:tried'; end if;

    -- e. redaction
    if v_note::text ~ '@example.invalid' or v_note::text ~ '971' then v_fail := v_fail || format(' e%s:contact-leaked', r.n); end if;

    -- b. the receiver's next action closes it; the answer must cite the note
    perform set_config('qd.handoff_closer', r.f, true);
    perform public.fn_seat_handoff_complete(v_id, jsonb_build_object('action', 'ZZ DEMO ' || r.t_seat || ' acted on ' || r.typ));
    select evidence into v_ev from public.agent_actions where id = v_id;
    if (v_ev->'cites_note'->>'handoff_id') is distinct from v_id::text then v_fail := v_fail || format(' b%s:no-citation', r.n); end if;
    if (v_ev->'cites_note'->'open_asks') is distinct from v_note->'open_asks' then v_fail := v_fail || format(' b%s:asks', r.n); end if;

    v_out := v_out || jsonb_build_object('handoff', v_id, 'from', r.f, 'to', r.t_seat, 'type', r.typ,
      'context', left(v_note->>'context', 160), 'decision', left(v_note->>'decision', 120), 'open_asks', v_note->'open_asks',
      'deadline', v_note->>'deadline', 'deadline_source', v_note->>'deadline_source', 'cites_note', v_ev->'cites_note');
  end loop;

  -- c. measured
  v_gaps := public.fn_handoff_citation_gaps(v_t0);
  if exists (select 1 from jsonb_array_elements_text(v_gaps->'uncited_ids') u where u::bigint = any(v_ids)) then v_fail := v_fail || ' c'; end if;

  -- d. a note without the four fields, triggers off
  begin
    set local session_replication_role = replica;
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('accountant', 'handoff', 'pending', 'low', 'ZZ DEMO bare note',
            jsonb_build_object('type', 'refund.requested', 'from', 'sales_engineer', 'subject_table', 'zz_demo_case', 'subject_id', v_case,
                               'summary', jsonb_build_object('known', '{}'::jsonb, 'tried', '{}'::jsonb, 'needed', '{}'::jsonb, 'evidence', '[]'::jsonb)),
            'zz_demo_case', 'zz:' || v_case);
  exception when check_violation then v_check := 'refused: ' || left(sqlerrm, 90);
  end;
  set local session_replication_role = origin;
  if v_check like 'NOT%' then v_fail := v_fail || ' d'; end if;

  -- f. legacy UPDATE never fails
  select id into v_legacy from public.agent_actions
   where kind = 'handoff' and not coalesce(detail->'summary', '{}'::jsonb) ? 'deadline' order by id desc limit 1;
  begin
    update public.agent_actions set risk = risk where id = v_legacy;
    if not (select detail->'summary' ?& array['context','decision','open_asks','deadline'] from public.agent_actions where id = v_legacy)
      then v_fail := v_fail || ' f1:no-fields'; end if;
    v_legacy_out := 'real legacy row ' || v_legacy || ' updated';
  exception when others then v_fail := v_fail || ' f1:raised'; v_legacy_out := 'real legacy row ' || v_legacy || ' RAISED: ' || left(sqlerrm, 80);
  end;
  insert into public.agent_actions (agent, kind, status, risk, title) values ('accountant', 'zz_demo_legacy', 'pending', 'low', 'ZZ DEMO row with no case')
  returning id into v_id;
  begin
    update public.agent_actions set kind = 'handoff' where id = v_id;
    if not (select (detail->'summary'->>'legacy')::boolean from public.agent_actions where id = v_id) then v_fail := v_fail || ' f2:not-legacy'; end if;
    v_legacy_out := v_legacy_out || '; unreadable ZZ DEMO row updated with a legacy note';
  exception when others then v_fail := v_fail || ' f2:raised'; v_legacy_out := v_legacy_out || '; unreadable row RAISED: ' || left(sqlerrm, 80);
  end;

  if exists (select 1 from public.notifications where id > v_notif) then v_fail := v_fail || ' NOTIFICATION-QUEUED'; end if;
  if array_length(v_ids, 1) is distinct from 3 then v_fail := v_fail || ' count'; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end,
    'handoffs', v_out, 'citation_gaps_for_probe', jsonb_build_object('cited', v_gaps->'cited', 'closed_with_note', v_gaps->'closed_with_note'),
    'bare_note', v_check, 'legacy_updates', v_legacy_out)::text;
end $probe$;
