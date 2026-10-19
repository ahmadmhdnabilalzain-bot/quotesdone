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
  v_e bigint; v_ak_e bigint; v_held_e bigint; v_k_e bigint; v_k_c bigint; v_reasks int; v_broken bigint; v_other bigint; i int;
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
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values ('it_engineer', 'ZZ DEMO probe', 'ZZ DEMO probe lapse E: confirm site access before the visit (quote 555).', '[{"kind":"probe"}]', 'approved', 'probe', now())
  returning id into v_e;
  insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
  values ('it_engineer', 'ZZ DEMO probe lesson E', 'ZZ DEMO probe lapse E: confirm site access before the visit (quote 555).', 'experience', 'lesson:' || v_e, 'it_engineer', 1, 'author_verified', 'probe')
  returning id into v_ak_e;

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

  -- 4b. A LAPSE IS ESCALATED ONCE, NEVER SILENT, NEVER MULTIPLIED (reviews 2 and 3 of #1443).
  --   C: expires through the real fn_reason_held_expire, then every re-asked copy expires too, 4 times in all:
  --      exactly ONE handoff for C's version the whole time, re-asked at most 3 times, then left pending (the alert);
  --      the CEO then decides directly and the same handoff closes as done.
  --   D: fails: one pending handoff; the 3-try limit refuses a re-ask, so it is not counted as asked.
  --   E: the CEO's answer is neither approve nor reject: the question ends 'applied' with nothing applied; the lesson is
  --      undecided, so it is escalated and asked again.
  select h.id into v_held_c from public.reasoning_held_question h join public.agent_knowledge k on k.id = (h.subject->>'knowledge_id')::bigint
   where h.surface = 'ceo.lesson_reapproval' and k.supersedes_id = v_ak_c;
  select h.id into v_held_d from public.reasoning_held_question h join public.agent_knowledge k on k.id = (h.subject->>'knowledge_id')::bigint
   where h.surface = 'ceo.lesson_reapproval' and k.supersedes_id = v_ak_d;
  select h.id, (h.subject->>'knowledge_id')::bigint into v_held_e, v_k_e from public.reasoning_held_question h
    join public.agent_knowledge k on k.id = (h.subject->>'knowledge_id')::bigint
   where h.surface = 'ceo.lesson_reapproval' and k.supersedes_id = v_ak_e;
  if v_held_c is null or v_held_d is null or v_held_e is null then v_fail := v_fail || ' lapse lessons C/D/E were not held for the CEO;';
  else
    select (subject->>'knowledge_id')::bigint into v_k_c from public.reasoning_held_question where id = v_held_c;
    for i in 1..4 loop
      perform public.fn_reason_held_expire(array[v_held_c], 'probe', 'ZZ DEMO probe: 14 days passed (' || i || ')');
      select count(*), max(id) into v_n, v_hand_c from public.agent_actions
       where kind = 'handoff' and detail->>'type' = 'ceo.lesson_reapproval_overdue' and detail->>'knowledge_id' = v_k_c::text;
      if v_n <> 1 then v_fail := v_fail || ' lapse ' || i || ' of C left ' || v_n || ' handoffs (one per version);'; exit; end if;
      select (detail->>'held_id')::bigint, coalesce((detail->>'reasks')::int, 0) into v_held_c, v_reasks from public.agent_actions where id = v_hand_c;
      if v_reasks <> least(i, 3) then v_fail := v_fail || ' lapse ' || i || ' of C: re-asked ' || v_reasks || ' times, expected ' || least(i, 3) || ';'; end if;
      if i <= 3 and not exists (select 1 from public.reasoning_held_question where id = v_held_c and status = 'held') then
        v_fail := v_fail || ' lapse ' || i || ' of C was not asked again;'; end if;
      if i = 4 and exists (select 1 from public.reasoning_held_question where id = v_held_c and status = 'held') then
        v_fail := v_fail || ' C was asked a 4th time past the cap;'; end if;
    end loop;
    if not exists (select 1 from public.agent_actions where id = v_hand_c and status = 'pending' and detail->>'awaiting' ~ 'cap is reached') then
      v_fail := v_fail || ' past the cap the handoff does not stay pending and say so;'; end if;
    perform public.fn_reason_apply_ceo__lesson_reapproval(v_held_c, jsonb_build_object('decision', jsonb_build_object('choice', 'reject')));
    v := public.fn_seat_handoff_act(v_hand_c);
    if not exists (select 1 from public.agent_actions where id = v_hand_c and status = 'done') then
      v_fail := v_fail || ' the escalation did not close once the CEO decided: ' || coalesce(v::text, 'null') || ';'; end if;

    update public.reasoning_held_question set status = 'failed', attempts = 3 where id = v_held_d;
    select count(*) into v_n from public.agent_actions where kind = 'handoff' and agent = 'ceo' and status = 'pending'
       and detail->>'type' = 'ceo.lesson_reapproval_overdue' and (detail->>'held_id')::bigint = v_held_d
       and coalesce((detail->>'reasks')::int, 0) = 0;
    if v_n <> 1 then v_fail := v_fail || ' a failed re-approval did not leave exactly one pending, un-re-asked handoff (' || v_n || ');'; end if;

    perform public.fn_reason_held_resolve(v_held_e, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO probe: unsure',
                                                                       'decision', jsonb_build_object('choice', 'maybe')));
    if public.fn_lesson_reapproval_decided(v_k_e) is not null then v_fail := v_fail || ' an answer with no decision decided E;'; end if;
    if not exists (select 1 from public.agent_actions a join public.reasoning_held_question h on h.id = (a.detail->>'held_id')::bigint
                    where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.lesson_reapproval_overdue'
                      and a.detail->>'knowledge_id' = v_k_e::text and h.status = 'held') then
      v_fail := v_fail || ' a question that ended without a decision was not escalated and asked again;'; end if;
  end if;

  -- 4c. AN ESCALATION ERROR NEVER BLOCKS EXPIRY. A ceo.lesson_reapproval row whose subject breaks the trigger (a
  --     knowledge_id that is not a number) expires in ONE statement with another surface's row: both expire, the
  --     error is logged as an it_engineer finding, and nothing aborts.
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('ceo', 'ceo.lesson_reapproval', 'ZZ DEMO probe broken subject', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('knowledge_id', 'zz-not-a-number'), 'probe', 'zz_demo_probe:broken:' || clock_timestamp())
  returning id into v_broken;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('it_engineer', 'zz_demo_probe.other_surface', 'ZZ DEMO probe other surface', '{}'::jsonb, '{}'::jsonb,
          '{}'::jsonb, 'probe', 'zz_demo_probe:other:' || clock_timestamp())
  returning id into v_other;
  begin
    perform public.fn_reason_held_expire(array[v_broken, v_other], 'probe', 'ZZ DEMO probe: expiry with a broken subject');
  exception when others then
    v_fail := v_fail || ' an escalation error aborted the expiry: ' || sqlerrm || ';';
  end;
  select count(*) into v_n from public.reasoning_held_question where id in (v_broken, v_other) and status = 'expired';
  if v_n <> 2 then v_fail := v_fail || ' an escalation error blocked expiry (' || v_n || ' of 2 expired);'; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'monitor:lesson_reapproval_escalation_failed:zz-not-a-number') then
    v_fail := v_fail || ' the escalation error was not logged as a finding;'; end if;

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
