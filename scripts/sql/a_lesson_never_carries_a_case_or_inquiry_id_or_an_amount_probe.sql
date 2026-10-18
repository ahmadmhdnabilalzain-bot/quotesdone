-- PROBE: a lesson never carries a case or inquiry id or an amount. Pure probe, no DDL: run AFTER its .sql in the SAME
-- query; it always ends in raise exception CHK<<...>>, so nothing survives. Contacts no one.
-- PROBE OK only if:
--   1. THE RULE: fn_lesson_scrub removes every identifier, amount and contact kind (English and Arabic, Arabic-Indic
--      digits included) and keeps every count in prose ("3 suppliers reply within 2 days", "٣ موردين", a date);
--   2. the real fn_reason_apply_learning__distil stores none of the planted identifiers in its three stores;
--   3. COLLISIONS: two approved candidates that scrub to the same text do not abort the backfill; one is kept with the
--      clean text, the other is rejected as its duplicate and its approved lesson is retired;
--   4. VERSIONING: the kept candidate's approved lesson is not edited in place: the original is retired and kept, a
--      version + 1 (supersedes_id = original) waits quarantined, the CEO seat holds a ceo.lesson_reapproval question,
--      and only the CEO's 'approve' makes the new version live;
--   5. after the backfill no live lesson, no open candidate and no case lesson still carries an identifier.
do $probe$
declare
  v_fail text := ''; v_ids bigint[]; v jsonb; v_find text; v_ak text; v_les text; v_left int; v_bf jsonb;
  t record; v_out text; v_a bigint; v_b bigint; v_ak_a bigint; v_ak_b bigint; v_new record; v_held bigint; v_n int;
  v_c bigint; v_d bigint; v_ak_c bigint; v_ak_d bigint; v_held_c bigint; v_held_d bigint; v_hand_c bigint;
  v_planted text := 'ZZ DEMO probe lesson: in case 16269 and cases 384 and 387, Case #368, rfq 158556, RFQ-158557, 158558 rfq, '
    || 'quote 12, QD-RF-ZZ1 and inquiry 474a37be-4dd5-47ec-be6a-a12f1800d20c, the supplier priced AED 3,728.30 then 118,500 AED '
    || '(Dhs26.99, USD 1.2k, بسعر ٣٬٧٢٨ درهم, طلب ١٥٨٥٥٦); contact zz.demo@example.invalid or +971 50 123 4567 or 0501234567. '
    || 'Usually 3 suppliers reply within 2 days, ٣ موردين; confirm the delivery window in writing before 2026-10-18.';
  -- what must never be stored: any identifier, amount or contact the rule names (digits already ASCII after the scrub)
  v_pat text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|#\s?\d|\mQD-|\m(aed|dhs?|usd|dirhams?)\s?\d|\d[\d,]*(\.\d+)?\s?(k|m)?\s?(aed|dhs?|dirhams?|usd)\M'
    || '|\m(cases?|inquir(y|ies)|quotes?)\s+#?\d|rfq[\s#:=_-]*\d|\d[\s-]*rfq|(درهم|دراهم)\s*\d|\d\s*(درهم|دراهم)|(طلب|حالة|رقم)\s*\d|@|\+971|0501234567'
    || '|[٠-٩]';
begin
  -- 1. THE RULE, case by case
  for t in select * from (values
      ('case 16269 failed', 'case failed', null),
      ('cases 384 and 387 and #368', 'cases', null),
      ('rfq 158556 / RFQ-158557 / rfq_no=9 / 158558 rfq / RFQ158559', 'rfq / rfq / rfq / rfq / rfq', null),
      ('see QD-RF-ZZ1 and QD-8B287960-A', 'see a reference and a reference', null),
      ('priced AED 3,728.30, then 118,500 AED, Dhs26.99, USD 1.2k, $400', 'priced an amount, then an amount, an amount, an amount, an amount', null),
      ('بسعر ٣٬٧٢٨ درهم أو د.إ 500 أو 2 ألف درهم', 'بسعر an amount أو an amount أو an amount', null),
      ('طلب ١٥٨٥٥٦ و حالة 12', 'طلب و حالة', null),
      ('call +971 50 123 4567, 0501234567 or zz@example.invalid', 'call a contact, a contact or a contact', null),
      ('3 suppliers reply within 2 days; 40 windows in 10 working days', '3 suppliers reply within 2 days; 40 windows in 10 working days', null),
      ('٣ موردين خلال ٢ يوم', '3 موردين خلال 2 يوم', null),
      ('before 2026-10-18, in 2 cases out of 12 quotes', 'before 2026-10-18, in 2 cases out of 12 quotes', null)
    ) as x(input, expected, _)
  loop
    v_out := public.fn_lesson_scrub(t.input);
    if v_out is distinct from t.expected then v_fail := v_fail || format(' scrub(%s)=%s, expected %s;', t.input, v_out, t.expected); end if;
  end loop;

  -- 2. the real distil routine
  select array_agg(id) into v_ids from (select id from public.seat_case_memory where seat = 'it_engineer' order by id limit 3) s;   -- a cluster holds at least 3 cases (seat_lesson_cluster_case_ids_check)
  insert into public.seat_lesson_cluster (cluster_key, seat, case_ids) values ('zz_demo_probe_lesson_scrub', 'it_engineer', v_ids);
  v := public.fn_reason_apply_learning__distil(-1, jsonb_build_object(
         'subject', jsonb_build_object('cluster_key', 'zz_demo_probe_lesson_scrub'), 'status', 'answered', 'answer', v_planted,
         'verified', jsonb_build_object('status', 'agreed', 'by', 'probe/other-family')));
  if coalesce((v->>'applied')::boolean, false) is not true or v->>'status' <> 'approved' then v_fail := v_fail || ' distil did not apply as approved: ' || v::text || ';'; end if;
  select finding into v_find from public.reasoning_knowledge_candidate where id = (v->>'candidate_id')::bigint;
  select content into v_ak from public.agent_knowledge where source_ref = 'lesson:' || (v->>'candidate_id');
  select string_agg(l, ' ') into v_les from public.seat_case_memory m, unnest(m.lessons) l where m.id = any(v_ids) and l like 'ZZ DEMO probe lesson%';
  if v_find is null or v_ak is null or v_les is null then v_fail := v_fail || ' a store was not written (candidate/knowledge/case);'; end if;
  if v_find ~* v_pat then v_fail := v_fail || ' candidate keeps an identifier: ' || coalesce((regexp_match(v_find, v_pat, 'i'))[1], left(v_find, 160)) || ';'; end if;
  if v_ak ~* v_pat then v_fail := v_fail || ' approved lesson keeps an identifier;'; end if;
  if v_les ~* v_pat then v_fail := v_fail || ' case lesson keeps an identifier;'; end if;
  if v_find !~ 'Usually 3 suppliers reply within 2 days, 3 موردين; confirm the delivery window in writing before 2026-10-18\.' then
    v_fail := v_fail || ' the know-how, a count or the date was lost: ' || coalesce(v_find, '') || ';'; end if;

  -- 3 + 4. two approved candidates that scrub to one text, each with an approved lesson
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values ('it_engineer', 'ZZ DEMO probe', 'ZZ DEMO probe dup: chase the supplier on day 2 (case 111).', '[{"kind":"probe"}]', 'approved', 'probe', now())
  returning id into v_a;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values ('it_engineer', 'ZZ DEMO probe', 'ZZ DEMO probe dup: chase the supplier on day 2 (case 222).', '[{"kind":"probe"}]', 'approved', 'probe', now())
  returning id into v_b;
  insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
  values ('it_engineer', 'ZZ DEMO probe lesson A', 'ZZ DEMO probe dup: chase the supplier on day 2 (case 111).', 'experience', 'lesson:' || v_a, 'it_engineer', 1, 'author_verified', 'probe')
  returning id into v_ak_a;
  insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
  values ('it_engineer', 'ZZ DEMO probe lesson B', 'ZZ DEMO probe dup: chase the supplier on day 2 (case 222).', 'experience', 'lesson:' || v_b, 'it_engineer', 1, 'author_verified', 'probe')
  returning id into v_ak_b;

  -- two more approved lessons whose re-approval will lapse: C expires, D fails
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values ('it_engineer', 'ZZ DEMO probe', 'ZZ DEMO probe lapse C: escalate a silent supplier after 48 hours (case 333).', '[{"kind":"probe"}]', 'approved', 'probe', now())
  returning id into v_c;
  insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
  values ('it_engineer', 'ZZ DEMO probe lesson C', 'ZZ DEMO probe lapse C: escalate a silent supplier after 48 hours (case 333).', 'experience', 'lesson:' || v_c, 'it_engineer', 1, 'author_verified', 'probe')
  returning id into v_ak_c;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values ('it_engineer', 'ZZ DEMO probe', 'ZZ DEMO probe lapse D: re-read the drawing before pricing (rfq 444).', '[{"kind":"probe"}]', 'approved', 'probe', now())
  returning id into v_d;
  insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
  values ('it_engineer', 'ZZ DEMO probe lesson D', 'ZZ DEMO probe lapse D: re-read the drawing before pricing (rfq 444).', 'experience', 'lesson:' || v_d, 'it_engineer', 1, 'author_verified', 'probe')
  returning id into v_ak_d;

  begin
    v_bf := public.fn_lesson_scrub_backfill();
  exception when others then
    v_fail := v_fail || ' the backfill aborted on a collision: ' || sqlerrm || ';';
  end;
  select count(*) into v_n from public.reasoning_knowledge_candidate where id = v_a and finding = 'ZZ DEMO probe dup: chase the supplier on day 2 (case).';
  if v_n <> 1 then v_fail := v_fail || ' the kept candidate (older) did not take the clean text;'; end if;
  select count(*) into v_n from public.reasoning_knowledge_candidate where id = v_b and status = 'rejected' and reviewed_by = 'rule:lesson_scrub_duplicate_of:' || v_a;
  if v_n <> 1 then v_fail := v_fail || ' the duplicate candidate was not rejected as a duplicate of the kept one;'; end if;
  select count(*) into v_n from public.agent_knowledge where id = v_ak_b and validation_status = 'quarantined' and valid_until = current_date;
  if v_n <> 1 then v_fail := v_fail || ' the duplicate''s approved lesson was not retired;'; end if;

  select count(*) into v_n from public.agent_knowledge where id = v_ak_a and validation_status = 'quarantined'
     and content = 'ZZ DEMO probe dup: chase the supplier on day 2 (case 111).';
  if v_n <> 1 then v_fail := v_fail || ' the original approved lesson was edited in place or not retired;'; end if;
  select * into v_new from public.agent_knowledge where supersedes_id = v_ak_a;
  if v_new.id is null or v_new.version <> 2 or v_new.validation_status <> 'quarantined'
     or v_new.content <> 'ZZ DEMO probe dup: chase the supplier on day 2 (case).' then
    v_fail := v_fail || ' no quarantined version 2 superseding the original;'; end if;
  select id into v_held from public.reasoning_held_question where surface = 'ceo.lesson_reapproval' and seat = 'ceo'
     and (subject->>'knowledge_id')::bigint = v_new.id;
  if v_held is null then v_fail := v_fail || ' the CEO seat was not asked to re-approve;';
  else
    if exists (select 1 from public.reasoning_knowledge_candidate where id = v_a and status <> 'pending_review') then
      v_fail := v_fail || ' the kept candidate was not sent back to pending review;'; end if;
    v := public.fn_reason_apply_ceo__lesson_reapproval(v_held, jsonb_build_object('decision', jsonb_build_object('choice', 'approve')));
    if not exists (select 1 from public.agent_knowledge where id = v_new.id and validation_status = 'author_verified') then
      v_fail := v_fail || ' the CEO''s approve did not make version 2 live: ' || v::text || ';'; end if;
    if not exists (select 1 from public.reasoning_knowledge_candidate where id = v_a and status = 'approved' and reviewed_by like 'ceo:lesson_reapproval:%') then
      v_fail := v_fail || ' the CEO''s approve did not close the candidate;'; end if;
  end if;

  -- 4b. A LAPSE IS ESCALATED, NEVER SILENT. C's question expires through the real expiry routine (internal: it files no
  --     handoff itself); D's fails. Each must open a pending ceo.lesson_reapproval_overdue handoff to the CEO seat. Acting
  --     on C's re-asks the question and waits; once the CEO has decided, acting again completes it.
  select h.id into v_held_c from public.reasoning_held_question h join public.agent_knowledge k on k.id = (h.subject->>'knowledge_id')::bigint
   where h.surface = 'ceo.lesson_reapproval' and k.supersedes_id = v_ak_c;
  select h.id into v_held_d from public.reasoning_held_question h join public.agent_knowledge k on k.id = (h.subject->>'knowledge_id')::bigint
   where h.surface = 'ceo.lesson_reapproval' and k.supersedes_id = v_ak_d;
  if v_held_c is null or v_held_d is null then v_fail := v_fail || ' lapse lessons C/D were not held for the CEO;';
  else
    perform public.fn_reason_held_expire(array[v_held_c], 'probe', 'ZZ DEMO probe: 14 days passed');
    update public.reasoning_held_question set status = 'failed', attempts = 3 where id = v_held_d;
    select id into v_hand_c from public.agent_actions where kind = 'handoff' and agent = 'ceo' and status = 'pending'
       and detail->>'type' = 'ceo.lesson_reapproval_overdue'
       and v_held_c in ((detail->>'held_id')::bigint, (detail->>'reasked_from')::bigint);   -- the handler may already have re-asked
    if v_hand_c is null then v_fail := v_fail || ' an expired re-approval was not escalated to the CEO: held ' || v_held_c || ' status ' || (select status from public.reasoning_held_question where id = v_held_c) || ', held rows ' || (select string_agg(h.id || '=' || h.status || '/k' || (h.subject->>'knowledge_id') || '/sup' || (h.subject->>'supersedes_id'), ' ') from public.reasoning_held_question h where h.surface = 'ceo.lesson_reapproval') || ' akc ' || v_ak_c || ' akd ' || v_ak_d || ', handoffs ' || coalesce((select string_agg(status || '/' || (detail->>'held_id') || '/' || coalesce(detail->>'error',''), ', ') from public.agent_actions where kind = 'handoff' and detail->>'type' = 'ceo.lesson_reapproval_overdue'), 'none') || ';'; end if;
    if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'ceo' and status = 'pending'
                    and detail->>'type' = 'ceo.lesson_reapproval_overdue' and (detail->>'held_id')::bigint = v_held_d) then
      v_fail := v_fail || ' a failed re-approval was not escalated to the CEO;'; end if;
    if v_hand_c is not null then
      v := public.fn_seat_handoff_act(v_hand_c);
      select (detail->>'held_id')::bigint into v_held_c from public.agent_actions where id = v_hand_c;   -- the re-filed question
      if not exists (select 1 from public.reasoning_held_question where id = v_held_c and status = 'held' and surface = 'ceo.lesson_reapproval')
         or not (v ? 'waiting') then
        v_fail := v_fail || ' acting on the escalation did not ask the CEO again: ' || coalesce(v::text, 'null') || ';'; end if;
      perform public.fn_reason_held_resolve(v_held_c, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO probe',
                                                                         'decision', jsonb_build_object('choice', 'reject')));
      v := public.fn_seat_handoff_act(v_hand_c);
      if not exists (select 1 from public.agent_actions where id = v_hand_c and status = 'done') then
        v_fail := v_fail || ' the escalation did not close once the CEO decided: ' || coalesce(v::text, 'null') || ';'; end if;
    end if;
  end if;

  -- 5. nothing live still carries one
  select count(*) into v_left from (
    select finding as txt from public.reasoning_knowledge_candidate where status <> 'rejected'
    union all select content from public.agent_knowledge where source_ref like 'lesson:%' and validation_status <> 'quarantined'
    union all select l from public.seat_case_memory m, unnest(m.lessons) l) x where x.txt ~* v_pat;
  if v_left > 0 then v_fail := v_fail || ' ' || v_left || ' live lesson(s) still carry an identifier after the backfill;'; end if;
  select count(*) into v_n from public.reasoning_held_question where surface = 'ceo.lesson_reapproval';

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK | held for CEO re-approval: ' || v_n || ' | stored: ' || left(v_find, 300)
                                   else 'PROBE FAIL:' || v_fail end;
end $probe$;
