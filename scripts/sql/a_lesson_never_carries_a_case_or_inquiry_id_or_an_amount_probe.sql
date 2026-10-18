-- PROBE: a lesson never carries a case or inquiry id or an amount. Pure probe, no DDL: run AFTER its .sql in the SAME
-- query; it always ends in raise exception CHK<<...>>, so nothing survives. Contacts no one.
-- PROBE OK only if:
--   1. the real fn_reason_apply_learning__distil, given an approved lesson that plants a UUID, case/inquiry/rfq/quote
--      numbers, a bare #n, amounts on either side of the currency, an e-mail and a phone, stores none of them in
--      reasoning_knowledge_candidate.finding, agent_knowledge.content or seat_case_memory.lessons;
--   2. the know-how in the lesson survives (its words are still there), and a date is not mistaken for a phone;
--   3. after the backfill no candidate, approved lesson or case lesson still matches the identifier pattern.
do $probe$
declare
  v_fail text := ''; v_ids bigint[]; v jsonb; v_find text; v_ak text; v_les text; v_left int;
  v_planted text := 'ZZ DEMO probe lesson: in case 16269 and cases 384 and 387, Case #368, rfq 158556, quote 12 and inquiry '
    || '474a37be-4dd5-47ec-be6a-a12f1800d20c, the supplier priced AED 3,728.30 then 118,500 AED (Dhs26.99, USD 1.2k); '
    || 'contact zz.demo@example.invalid or +971 50 123 4567 or 0501234567. Confirm the delivery window in writing '
    || 'before 2026-10-18 and attach the measured drawing.';
  v_pat text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|#\s?\d|\m(aed|dhs?|usd|dirhams?)\s?\d|\d[\d,]*(\.\d+)?\s?(k|m)?\s?(aed|dhs?|dirhams?|usd)\M'
    || '|\m(cases?|inquir(y|ies)|rfqs?|quotes?)\s+#?\d|@|\+971|0501234567';
begin
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
  if v_find ~* v_pat then v_fail := v_fail || ' candidate keeps an identifier: ' || coalesce((regexp_match(v_find, v_pat, 'i'))[1], substring(v_find from 1 for 120)) || ';'; end if;
  if v_ak ~* v_pat then v_fail := v_fail || ' approved lesson keeps an identifier;'; end if;
  if v_les ~* v_pat then v_fail := v_fail || ' case lesson keeps an identifier;'; end if;
  if v_find !~ 'Confirm the delivery window in writing before 2026-10-18 and attach the measured drawing' then v_fail := v_fail || ' the know-how or the date was lost: ' || coalesce(v_find, '') || ';'; end if;

  select count(*) into v_left from (
    select finding t from public.reasoning_knowledge_candidate where status <> 'rejected'
    union all select content from public.agent_knowledge where source_ref like 'lesson:%'
    union all select l from public.seat_case_memory m, unnest(m.lessons) l) x where t ~* v_pat;
  if v_left > 0 then v_fail := v_fail || ' ' || v_left || ' stored lesson(s) still carry an identifier after the backfill;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK | stored: ' || left(v_find, 400) else 'PROBE FAIL:' || v_fail end;
end $probe$;
