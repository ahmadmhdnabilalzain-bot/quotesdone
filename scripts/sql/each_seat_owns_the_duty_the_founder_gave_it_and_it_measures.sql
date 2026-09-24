-- EACH SEAT OWNS THE DUTY THE FOUNDER GAVE IT; THE IT ENGINEER MEASURES.
-- Seats: sales_engineer (licence watch, supplier documents), customer_support (WhatsApp delivery), ceo (acting on a
-- knowledge pass-rate drop); it_engineer (measurement, unchanged). 24 Sep 2026, seat audit GAPS.md IT gap 9, the
-- founder's seat map of 24 Sep (memory seat-ownership-map-24-sep) and the 9 Sep ruling that licences are sales'.
--
-- WHAT WAS MEASURED (production, 24 Sep 2026):
--   * seat_duty 'it_engineer.licence_expiry_watch' asks suppliers to renew and pauses the expired ones: supplier work,
--     sat on the IT seat.
--   * it_duty_schedule 'supplier_docs' (fn_sales_engineer_supplier_documents_tick) and 'whatsapp_delivery' carried
--     owner_seat it_engineer. The WhatsApp findings were already handed to customer_support
--     (every_whatsapp_says_whether_it_arrived.sql, owner_seat), but the duty row said IT owned the fix-and-resend.
--   * fn_it_engineer_knowledge_pass_rate handed a seat's own drop to that seat. Measuring is IT's; holding a seat to
--     the bar is the CEO's ("holding every seat accountable", seat map).
--
-- WHAT THIS CHANGES
--   1. The duty becomes sales_engineer.licence_expiry_watch, run by fn_sales_engineer_licence_expiry_watch. The
--      invariant check inside it (no expired supplier matchable, re-measured after the pause) stays the IT engineer's
--      routine fn_it_engineer_licence_expiry_watch, called from here: the sales engineer does the work, IT measures.
--   2. it_duty_schedule owner_seat: supplier_docs -> sales_engineer, whatsapp_delivery -> customer_support. The IT
--      heartbeat still runs them (resilience_ping itlater); the owner column says whose work it is.
--   3. fn_it_engineer_knowledge_pass_rate: the finding and its it.finding handoff go to the CEO. The missed items are
--      still re-filed for research in the seat's own queue (routine work, code). Body otherwise verbatim from
--      the_it_engineer_watches_licences_and_every_seats_knowledge.sql (MANIFEST 1723).
--   NOT CHANGED: credential rotation stays (instr 324, later than 23, wins; GAPS IT gap 10).
--
--   node scripts/apply_sql.mjs scripts/sql/each_seat_owns_the_duty_the_founder_gave_it_and_it_measures.sql --apply --ddl

create or replace function public.fn_sales_engineer_licence_expiry_watch()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_licence_expiry_watch() $fn$;
revoke execute on function public.fn_sales_engineer_licence_expiry_watch() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_licence_expiry_watch() to service_role;

delete from public.seat_duty where duty = 'it_engineer.licence_expiry_watch';
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.licence_expiry_watch', 'sales_engineer', interval '1 day', 'fn_sales_engineer_licence_expiry_watch',
   'Renewal asks at 30/14/7 days; no expired approved supplier stays matchable (paused and told); IT re-measures the invariant.',
   'scripts/sql/each_seat_owns_the_duty_the_founder_gave_it_and_it_measures.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

update public.it_duty_schedule set owner_seat = 'sales_engineer' where duty = 'supplier_docs';
update public.it_duty_schedule set owner_seat = 'customer_support' where duty = 'whatsapp_delivery';

create or replace function public.fn_it_engineer_knowledge_pass_rate()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s record; v_out jsonb := '[]'::jsonb; v_raised int := 0; v_refiled int := 0; e record; v_gate jsonb; v_open boolean;
begin
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  v_open := coalesce(v_gate->>'rule', '') not in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state');
  for s in
    select seat,
           count(*) filter (where graded_at > now() - interval '30 days') as n30,
           count(*) filter (where graded_at > now() - interval '30 days' and verdict = 'correct') as ok30,
           count(*) filter (where graded_at <= now() - interval '30 days' and graded_at > now() - interval '60 days') as nprev,
           count(*) filter (where graded_at <= now() - interval '30 days' and graded_at > now() - interval '60 days' and verdict = 'correct') as okprev,
           count(*) filter (where graded_at is null and asked_at < now() - interval '7 days') as ungraded_week
      from public.seat_knowledge_exam group by seat
  loop
    declare r30 numeric := case when s.n30 > 0 then round(s.ok30::numeric / s.n30, 3) end;
            rprev numeric := case when s.nprev > 0 then round(s.okprev::numeric / s.nprev, 3) end;
            v_bad boolean;
    begin
      v_bad := s.n30 >= 5 and (r30 < 0.70 or (rprev is not null and s.nprev >= 5 and rprev - r30 >= 0.10));
      v_out := v_out || jsonb_build_object('seat', s.seat, 'rate_30d', r30, 'graded_30d', s.n30, 'rate_prev_30d', rprev, 'raised', v_bad);
      if v_bad then
        v_raised := v_raised + 1;
        perform public.fn_it_engineer_finding_upsert('knowledge_pass_rate:' || s.seat,
          'The ' || s.seat || ' seat''s knowledge pass rate is ' || round(r30 * 100) || '% over the last 30 days'
            || case when rprev is not null then ' (was ' || round(rprev * 100) || '%)' else '' end,
          'public.seat_knowledge_exam', 'agent_facing', (s.n30 - s.ok30)::int,
          jsonb_build_object('seat', s.seat, 'rate_30d', r30, 'rate_prev_30d', rprev, 'graded_30d', s.n30, 'owner_seat', 'ceo'),
          '{}'::text[], array['which items it answered wrong and why'], 'it_engineer');
        perform public.fn_seat_handoff('it_engineer', 'ceo', 'it.finding', 'seat_knowledge_exam',
          'knowledge_pass_rate:' || s.seat || ':' || to_char(now(), 'IYYY-IW'),
          jsonb_build_object('duty', 'knowledge_pass_rate', 'issue_key', 'knowledge_pass_rate:' || s.seat, 'subject', s.seat || ' knowledge',
                             'title', 'The ' || replace(s.seat, '_', ' ') || ' seat''s knowledge pass rate dropped to ' || round(r30 * 100) || '%; its missed items are filed for re-research in its queue, and holding the seat to the bar is yours'));
        -- THE SEAT ACTS: every item it missed in the window is re-researched in its own queue.
        for e in select * from public.seat_knowledge_exam
                  where seat = s.seat and verdict in ('wrong', 'partial', 'not_covered') and graded_at > now() - interval '30 days' and refiled_at is null loop
          perform public.fn_reason_hold(e.seat, e.seat || '.knowledge_refresh',
            'Re-research and correct our knowledge on: ' || e.question || ' — the answer given was graded ' || e.verdict || '.',
            jsonb_build_object('seat', e.seat, 'surface', e.seat || '.knowledge_refresh',
              'question', 'Re-research and correct our knowledge on: ' || e.question, 'research', true, 'stakes', 'high',
              'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('reference', left(e.reference, 2000), 'grade', e.grade_reason)),
              'subject', jsonb_build_object('item_key', e.item_key, 'exam_id', e.id), 'dedupeKey', 'krefile:' || e.id),
            jsonb_build_object('filed_by', 'it_engineer.knowledge_pass_rate'), jsonb_build_object('item_key', e.item_key, 'exam_id', e.id),
            'seat_duty', 'krefile:' || e.id);
          update public.seat_knowledge_exam set refiled_at = now() where id = e.id;
          v_refiled := v_refiled + 1;
        end loop;
      else
        update public.it_engineer_finding set closed_at = now(), close_note = 'pass rate back within bounds (knowledge_pass_rate)'
         where issue_key = 'knowledge_pass_rate:' || s.seat and closed_at is null;
      end if;
      -- An exam nobody could grade for a week WHILE a model can reason is a broken monitor, not a quiet one.
      if v_open and s.ungraded_week > 0 then
        perform public.fn_it_engineer_finding_upsert('knowledge_pass_rate:unmeasured:' || s.seat,
          s.ungraded_week || ' knowledge exam(s) of ' || s.seat || ' asked over a week ago are still ungraded while the model gate is open',
          'public.seat_knowledge_exam / reasoning_held_question', 'agent_facing', s.ungraded_week::int,
          jsonb_build_object('seat', s.seat), '{}'::text[], array['whether the replay or the apply fails'], 'it_engineer');
      else
        update public.it_engineer_finding set closed_at = now(), close_note = 'exams are being graded (or the model hold explains it)'
         where issue_key = 'knowledge_pass_rate:unmeasured:' || s.seat and closed_at is null;
      end if;
    end;
  end loop;
  return jsonb_build_object('seats', v_out, 'raised', v_raised, 'refiled', v_refiled, 'model_gate_open', v_open);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_pass_rate() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_pass_rate() to service_role;

select case when exists (select 1 from public.seat_duty where duty = 'sales_engineer.licence_expiry_watch')
             and not exists (select 1 from public.seat_duty where duty = 'it_engineer.licence_expiry_watch')
             and (select owner_seat from public.it_duty_schedule where duty = 'supplier_docs') = 'sales_engineer'
             and (select owner_seat from public.it_duty_schedule where duty = 'whatsapp_delivery') = 'customer_support'
             and position('fn_seat_handoff(''it_engineer'', ''ceo''' in (select prosrc from pg_proc where oid = 'public.fn_it_engineer_knowledge_pass_rate()'::regprocedure)) > 0
            then 'PROBE OK' else 'PROBE FAILED: an ownership move did not land' end as verdict;
