-- A LESSON NEVER CARRIES A CASE OR INQUIRY ID OR AN AMOUNT (it_engineer, 18 Oct 2026; release operator follow-up of #1441).
--
-- Why. fn_reason_apply_learning__distil writes the model's lesson verbatim into reasoning_knowledge_candidate.finding,
-- agent_knowledge.content (approved lessons, retrievable by meaning into a seat's prompts) and seat_case_memory.lessons.
-- The model that writes it reads the raw cases, and copies their identifiers. Measured on production 18 Oct 2026:
-- 10 of 11 candidates carry a case number ("case 16269", "cases 384 and 387") or an amount ("AED 3,728.30",
-- "AED 26.99"); 5 of 7 approved lessons in agent_knowledge do; 69 of 863 seat_case_memory rows with lessons do.
-- A lesson is general know-how. A case number points at one party's case and an amount is one party's price;
-- neither teaches anything, and #1441 showed that a case's text in a prompt is read back to the wrong person.
--
-- What changes.
--   1. public.fn_lesson_scrub(text): UUIDs, "case/inquiry/rfq/quote/ticket/finding <n>[, <n> and <n>]", a bare "#<n>",
--      amounts in AED/Dhs/dirhams/USD/$ (either side, with k/m/thousand/million), e-mails and phone numbers are
--      removed. The noun stays ("in two cases" reads "in cases"), so the sentence still reads.
--   2. fn_reason_apply_learning__distil scrubs the answer before it is stored anywhere.
--   3. The rows already written are scrubbed once. A changed candidate and its agent_knowledge row lose their vector
--      so fn_lesson_unembedded re-embeds the clean text. A candidate whose scrubbed text equals another candidate's
--      (finding_sha is UNIQUE and generated) keeps its text and is marked rejected: the same lesson already exists.
--
-- Prevented by: scripts/checks/a_lesson_never_carries_a_case_or_inquiry_id_or_an_amount.test.mjs (plants every
-- identifier kind through the real distil routine in an aborted transaction and asserts none is stored).

create or replace function public.fn_lesson_scrub(p_text text)
returns text language sql immutable parallel safe set search_path to 'pg_catalog', 'pg_temp' as $fn$
  select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p_text, ''),
           -- a UUID (inquiry, quote, customer, supplier ids)
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', 'a record', 'g'),
           -- "case 361", "cases 384 and 387", "Case #368, #369", "rfq 158556", "quote 12": the noun stays, the numbers go
           '\m(cases?|inquir(?:y|ies)|rfqs?|rfq_no|quotes?|tickets?|findings?|lessons?|judgements?|handoffs?)(\s*(?:no\.?|number)?\s*#?\s*\d+(?:\s*(?:,|and|&|/)\s*#?\s*\d+)*)', '\1', 'gi'),
           -- a bare "#361"
           '#\s?\d+', '', 'g'),
           -- an amount with its currency before it: "AED 3,728.30", "Dhs26.99", "USD 1.2k", "$400"
           '(\m(aed|dhs?|usd|dirhams?)|\$)\s?\d[\d,]*(\.\d+)?\s?(k|m|thousand|million)?\M', 'an amount', 'gi'),
           -- an amount with its currency after it: "118,500 AED", "26.99 dirhams"
           '\m\d[\d,]*(\.\d+)?\s?(k|m|thousand|million)?\s?(aed|dhs?|dirhams?|usd)\M', 'an amount', 'gi'),
           -- an e-mail address
           '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', 'a contact', 'g'),
           -- a phone number: international (+ or 00 then 8+ digits) or a UAE mobile/landline (05x / 0x, 9-10 digits).
           -- A date (2026-10-18) or a plain count is not one.
           '(\+|\m00)\d[\d\s-]{7,}\d|\m0[2-9]\d?[\s-]?\d{3}[\s-]?\d{4}\M', 'a contact', 'g'),
           '\s{2,}', ' ', 'g'))
$fn$;
revoke execute on function public.fn_lesson_scrub(text) from public, anon, authenticated;
grant execute on function public.fn_lesson_scrub(text) to service_role;

create or replace function public.fn_reason_apply_learning__distil(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_subject jsonb; c public.seat_lesson_cluster; v_answer text; v_ver text; v_by text; v_status text; v_cand bigint; v_ak bigint;
begin
  select subject into v_subject from public.reasoning_held_question where id = p_id;
  v_subject := coalesce(v_subject, p_result->'subject');
  select * into c from public.seat_lesson_cluster where cluster_key = v_subject->>'cluster_key';
  if c.cluster_key is null then return jsonb_build_object('applied', false, 'reason', 'no such cluster'); end if;
  -- A lesson is know-how, never a pointer to one party's case or price (18 Oct 2026, follow-up of #1441).
  v_answer := public.fn_lesson_scrub(btrim(coalesce(p_result->>'answer', '')));
  if v_answer = '' or p_result->>'status' <> 'answered' then return jsonb_build_object('applied', false, 'reason', 'no lesson'); end if;
  v_ver := coalesce(p_result->'verified'->>'status', 'not_run');
  v_by := p_result->'verified'->>'by';
  v_status := case when v_ver = 'agreed' and v_by is not null then 'approved' when v_ver = 'disagreed' then 'rejected' else 'pending_review' end;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values (c.seat, 'What do ' || cardinality(c.case_ids) || ' similar ' || c.seat || ' cases with known outcomes teach?', left(v_answer, 4000),
          (select jsonb_agg(jsonb_build_object('kind', 'case', 'case_id', x, 'cluster_key', c.cluster_key)) from unnest(c.case_ids) x),
          v_status, case when v_status <> 'pending_review' then 'cross_family:' || coalesce(v_by, 'unknown') end,
          case when v_status <> 'pending_review' then now() end)
  on conflict (finding_sha) do nothing
  returning id into v_cand;
  -- The same lesson text from another group is the same lesson: link this group to it, never to nothing.
  if v_cand is null then
    select id into v_cand from public.reasoning_knowledge_candidate where finding_sha = md5(lower(btrim(left(v_answer, 4000))));
  end if;
  update public.seat_lesson_cluster set candidate_id = v_cand, verdict = v_ver where cluster_key = c.cluster_key;
  if v_status = 'approved' and v_cand is not null
     and not exists (select 1 from public.agent_knowledge a where a.source_ref = 'lesson:' || v_cand) then
    insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
    values (c.seat, 'Lesson from ' || cardinality(c.case_ids) || ' cases [lesson#' || v_cand || ']', left(v_answer, 4000), 'experience',
            'lesson:' || v_cand, c.seat, 1, 'author_verified',
            'Distilled from cases ' || array_to_string(c.case_ids, ', ') || '; verified by a model of another family (' || v_by || ')')
    returning id into v_ak;
    update public.seat_case_memory set lessons = lessons || left(v_answer, 600), updated_at = now()
     where id = any(c.case_ids) and not (left(v_answer, 600) = any(lessons));
  end if;
  return jsonb_build_object('applied', true, 'candidate_id', v_cand, 'status', v_status, 'agent_knowledge_id', v_ak);
end $fn$;

-- THE ROWS ALREADY WRITTEN (measured 18 Oct 2026: 11 candidates, 7 lessons, 69 case rows; no batching needed).
-- A candidate whose clean text collides with another's is the same lesson: it keeps its text and is rejected.
update public.reasoning_knowledge_candidate r
   set status = 'rejected', reviewed_by = 'rule:lesson_scrub_duplicate', reviewed_at = now()
 where r.finding <> public.fn_lesson_scrub(r.finding)
   and exists (select 1 from public.reasoning_knowledge_candidate o
                where o.id <> r.id and o.finding_sha = md5(lower(btrim(left(public.fn_lesson_scrub(r.finding), 4000)))));
update public.reasoning_knowledge_candidate r
   set finding = left(public.fn_lesson_scrub(r.finding), 4000), embedding_gte = null
 where r.finding <> public.fn_lesson_scrub(r.finding) and r.reviewed_by is distinct from 'rule:lesson_scrub_duplicate';
update public.agent_knowledge a
   set content = left(public.fn_lesson_scrub(a.content), 4000), embedding_gte = null, updated_at = now()
 where a.source_ref like 'lesson:%' and a.content <> public.fn_lesson_scrub(a.content);
update public.seat_case_memory m
   set lessons = array(select public.fn_lesson_scrub(x) from unnest(m.lessons) with ordinality u(x, n) order by n), updated_at = now()
 where cardinality(m.lessons) > 0
   and m.lessons <> array(select public.fn_lesson_scrub(x) from unnest(m.lessons) with ordinality u(x, n) order by n);
