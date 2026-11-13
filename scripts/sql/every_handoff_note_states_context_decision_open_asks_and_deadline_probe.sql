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
--   g. fn_handoff_redact on its own (13 Nov 2026, review 3, item 4): object KEYS and string values are redacted at any
--      depth, in nested objects and arrays; numbers (135.000000000000000000 among them, which once raised 22P02),
--      booleans, null and numeric strings come back exactly as they went in
do $probe$
declare
  v_case text := 'ZZ-DEMO-1013-HANDOVER';
  v_notif bigint := coalesce((select max(id) from public.notifications), 0);
  v_t0 timestamptz := now();  -- decided_at is now(), the transaction's start
  v_ids bigint[] := '{}'; v_id bigint; v_note jsonb; v_ev jsonb; v_out jsonb := '[]'::jsonb; v_fail text := '';
  v_check text := 'NOT refused'; v_gaps jsonb; r record; v_legacy bigint; v_legacy_out text; v_in jsonb; v_red jsonb;
begin
  -- a lesson on the case carrying all four phone forms (redaction must reach copied lessons too)
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, situation, decision, lessons)
  values ('sales_engineer', 'zz_demo', 'zz_demo_case', v_case, 'ZZ DEMO situation 1013 handover', 'ZZ DEMO decision',
          array['ZZ DEMO lesson: call +971 50 123 4567, 00971 4 765 4321, 050 123 4567 or 04 765 4321']);
  for r in select * from (values
      (1, 'customer_support', 'sales_engineer', 'spec.not_sure',    jsonb_build_object('customer_name', 'ZZ DEMO Customer 1013', 'customer_email', 'zz-demo-1013@example.invalid', 'customer_phone', '+971 50 123 4567', 'remark', 'ZZ DEMO: reach me at zz-demo-1013@example.invalid or +971 50 123 4567 or 00971 4 765 4321 or 050 123 4567 or 04 765 4321', 'control', 'ZZ DEMO control: id 1013, case 263443, date 2026-10-09, 09-10-2026, AED 0.50, AED 05.00, ref 0123', 'question', 'ZZ DEMO: is 2.5 mm2 cable acceptable?')),
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
    if v_note::text ~ '@example.invalid' or v_note::text ~ '971|123 4567|765 4321' then v_fail := v_fail || format(' e%s:contact-leaked', r.n); end if;
    if v_note->'tried'->'case_memory'->0->'lessons'->>0 is distinct from 'ZZ DEMO lesson: call [phone], [phone], [phone] or [phone]' then v_fail := v_fail || format(' e%s:lesson', r.n); end if;
    if r.n = 1 and v_note->'known'->'facts'->>'control' is distinct from 'ZZ DEMO control: id 1013, case 263443, date 2026-10-09, 09-10-2026, AED 0.50, AED 05.00, ref 0123'
      then v_fail := v_fail || ' e1:control-eaten:' || coalesce(v_note->'known'->'facts'->>'control', 'null'); end if;
    if r.n = 1 and v_note->'known'->'facts'->>'remark' is distinct from 'ZZ DEMO: reach me at [email] or [phone] or [phone] or [phone] or [phone]'
      then v_fail := v_fail || ' e1:remark:' || coalesce(v_note->'known'->'facts'->>'remark', 'null'); end if;

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

  -- g. the redaction itself: keys, nesting, arrays, numbers, numeric strings
  v_in := jsonb_build_object(
    'zz-demo-key@example.invalid', 'an e-mail as a key',
    '+971 50 123 4567', 'a phone as a key',
    'nested', jsonb_build_object('deeper', jsonb_build_object('mail', 'write to zz-demo-1013@example.invalid', 'tel', '050 123 4567')),
    'list', jsonb_build_array('00971 4 765 4321', 1, 135.000000000000000000, jsonb_build_object('04 765 4321', true), null, false),
    'amount', 135.000000000000000000, 'big', 100000000000000000000, 'fils', 3877, 'ratio', 0.0000001, 'negative', -0.0050,
    'amount_text', '135.000000000000000000', 'rate_text', '0.0501234567', 'aed_text', 'AED 1,000.0000000 paid', 'ref', '1013000000000',
    'pi', 'pi_3Q0000000000000000000000', 'date', '2026-11-13T00:00:00.000000+00:00');
  begin
    v_red := public.fn_handoff_redact(v_in);
  exception when others then v_fail := v_fail || ' g:raised:' || left(sqlerrm, 80);
  end;
  if v_red is not null then
    if v_red::text ~ '@example.invalid|971|123 4567|765 4321' then v_fail := v_fail || ' g:contact-leaked:' || left(v_red::text, 300); end if;
    if not (v_red ? '[email]' and v_red ? '[phone]') then v_fail := v_fail || ' g:keys-not-redacted'; end if;
    if v_red->'nested'->'deeper'->>'mail' is distinct from 'write to [email]' or v_red->'nested'->'deeper'->>'tel' is distinct from '[phone]' then
      v_fail := v_fail || ' g:nested:' || coalesce(v_red->>'nested', 'null'); end if;
    if v_red->'list' is distinct from jsonb_build_array('[phone]', 1, 135.000000000000000000, jsonb_build_object('[phone]', true), null, false) then
      v_fail := v_fail || ' g:array:' || coalesce(v_red->>'list', 'null'); end if;
    if (v_red - '[email]' - '[phone]' - 'nested' - 'list') is distinct from (v_in - 'zz-demo-key@example.invalid' - '+971 50 123 4567' - 'nested' - 'list') then
      v_fail := v_fail || ' g:numbers-or-numeric-strings-changed:' || left((v_red - '[email]' - '[phone]' - 'nested' - 'list')::text, 300); end if;
    if (v_red->>'amount') is distinct from '135.000000000000000000' then v_fail := v_fail || ' g:scale-lost'; end if;
  end if;
  -- g2 (review 4, item 6d): colliding keys keep both values; "00 971 ..." is a phone; "PO 0012345678" is not; a phone
  -- stored as a JSON number is redacted, under a contact key or by its shape; amounts, ids and a time in ms are not
  begin
    v_red := public.fn_handoff_redact(jsonb_build_object('zz-a@example.invalid', 'first', 'zz-b@example.invalid', 'second',
      'spaced', 'call 00 971 50 123 4567 today', 'po', 'PO 0012345678', 'phone', 971501234567, 'n', 971501234567,
      'contact', jsonb_build_object('mobile', 501234567), 'fils', 77760, 'id', 263443, 'ms', 1731500000000, 'aed', 777.60));
    if (select count(*) from jsonb_object_keys(v_red) k where k like '[email]%') <> 2
       or not (v_red->>'[email]' in ('first', 'second') and v_red->>'[email] (2)' in ('first', 'second')) then
      v_fail := v_fail || ' g2:keys-collapsed:' || left(v_red::text, 200); end if;
    if v_red->>'spaced' is distinct from 'call [phone] today' then v_fail := v_fail || ' g2:00-spaced:' || coalesce(v_red->>'spaced', 'null'); end if;
    if v_red->>'po' is distinct from 'PO 0012345678' then v_fail := v_fail || ' g2:po-redacted:' || coalesce(v_red->>'po', 'null'); end if;
    if v_red->>'phone' is distinct from '[phone]' or v_red->>'n' is distinct from '[phone]' or v_red->'contact'->>'mobile' is distinct from '[phone]' then
      v_fail := v_fail || ' g2:phone-number-kept:' || left(v_red::text, 200); end if;
    if v_red->'fils' <> '77760'::jsonb or v_red->'id' <> '263443'::jsonb or v_red->'ms' <> '1731500000000'::jsonb or v_red->'aed' <> '777.60'::jsonb then
      v_fail := v_fail || ' g2:numbers-changed:' || left(v_red::text, 200); end if;
  exception when others then v_fail := v_fail || ' g2:raised:' || left(sqlerrm, 80);
  end;

  if exists (select 1 from public.notifications where id > v_notif) then v_fail := v_fail || ' NOTIFICATION-QUEUED'; end if;
  if array_length(v_ids, 1) is distinct from 3 then v_fail := v_fail || ' count'; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end,
    'handoffs', v_out, 'citation_gaps_for_probe', jsonb_build_object('cited', v_gaps->'cited', 'closed_with_note', v_gaps->'closed_with_note'),
    'bare_note', v_check, 'legacy_updates', v_legacy_out, 'redacted', v_red)::text;
end $probe$;
