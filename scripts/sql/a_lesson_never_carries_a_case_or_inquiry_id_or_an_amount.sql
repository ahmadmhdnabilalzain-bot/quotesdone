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
-- THE RULE (review of #1443): a lesson loses IDENTIFIERS, AMOUNTS and CONTACTS, and nothing else. A count in prose
-- stays: "3 suppliers reply within 2 days" is know-how and keeps both numbers. Precisely, removed are:
--   identifiers  a UUID; a QD- reference (QD-RF-…, QD-C-…, QD-8B287960-A); an rfq number in any position
--                ("rfq 158556", "RFQ-158556", "rfq_no=158556", "158556 rfq"); a number that FOLLOWS a record noun
--                (case, inquiry, quote, ticket, finding, lesson, judgement, handoff; Arabic حالة، طلب، عرض، رقم) —
--                the noun stays; a bare "#n";
--   amounts      a number beside a currency, either side: AED, Dhs, dirham(s), USD, $, درهم، دراهم، د.إ, with
--                k/m/thousand/million/ألف/مليون;
--   contacts     an e-mail; a phone number (+ or 00 then 8+ digits, or a UAE 0x number of 9-10 digits; a date is not one).
-- Arabic-Indic digits (٠-٩, ۰-۹) and the Arabic separators (٬ ٫) are read as 0-9 , . first, so every rule holds for them.
--
-- Measured with this file replayed (18 Oct 2026): all 7 approved lessons change under the rule, so all 7 get a version 2
-- held for the CEO; 0 candidate duplicates today (the collision path is proven by the probe).
--
-- What changes.
--   1. public.fn_lesson_scrub(text) applies the rule.
--   2. fn_reason_apply_learning__distil scrubs the answer before it is stored anywhere.
--   3. The rows already written, once:
--      - candidates are grouped by their scrubbed text. finding_sha is UNIQUE and generated, so two rows can never take
--        the same text: one row per group is kept (the one whose text is already clean, else the oldest) and takes the
--        clean text; every other row in the group is REJECTED as a duplicate of it, its clusters point at the kept row,
--        and its approved agent_knowledge lesson is retired (quarantined, valid_until today). Nothing can collide.
--      - an APPROVED lesson whose text changes is never edited in place: the original row is retired and kept as
--        history, a new row (version + 1, supersedes_id = the original) holds the clean text QUARANTINED, which every
--        reader skips, and the CEO seat is asked to re-approve it (ceo.lesson_reapproval, held for reasoning). Only the
--        CEO's 'approve' makes it live (fn_reason_apply_ceo__lesson_reapproval).
--      - seat_case_memory.lessons are case notes, not approved knowledge: scrubbed in place.
--
-- Prevented by: scripts/checks/a_lesson_never_carries_a_case_or_inquiry_id_or_an_amount.test.mjs (plants every
-- identifier kind through the real distil routine and the backfill in an aborted transaction).

create or replace function public.fn_lesson_scrub(p_text text)
returns text language sql immutable parallel safe set search_path to 'pg_catalog', 'pg_temp' as $fn$
  select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           translate(coalesce(p_text, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٬٫', '01234567890123456789,.'),
           -- identifiers: a UUID
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', 'a record', 'g'),
           -- identifiers: a QD- reference
           '\mQD-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*', 'a reference', 'gi'),
           -- identifiers: an rfq number, after or before the word, joined or not
           '\mrfq(?:_?no)?[\s#:=_-]*\d+', 'rfq', 'gi'),
           '\m\d+[\s#-]*rfq\M', 'rfq', 'gi'),
           -- identifiers: a number following a record noun ("cases 384 and 387", "Case #368, #369"); the noun stays
           '\m(cases?|inquir(?:y|ies)|quotes?|quotations?|tickets?|findings?|lessons?|judgements?|handoffs?)(\s*(?:no\.?|number)?\s*[#:]?\s*\d+(?:\s*(?:,|and|&|/)\s*#?\s*\d+)*)\M', '\1', 'gi'),
           '(حالة|الحالة|طلب|الطلب|عرض|العرض|رقم)\s*[#:]?\s*\d+(?:\s*(?:،|,|و)\s*\d+)*', '\1', 'g'),
           -- identifiers: a bare "#361"
           '#\s?\d+', '', 'g'),
           -- amounts: currency before the number
           '(?:\m(?:aed|dhs?|usd|dirhams?)|\$|دراهم|درهم|د\.إ\.?)\s?\d[\d,]*(?:\.\d+)?(?:\s?(?:k|m|thousand|million)\M|\s?(?:ألف|مليون))?', 'an amount', 'gi'),
           -- amounts: currency after the number
           '\m\d[\d,]*(?:\.\d+)?(?:\s?(?:k|m|thousand|million)\M|\s?(?:ألف|مليون))?\s?(?:(?:aed|dhs?|dirhams?|usd)\M|دراهم|درهم|د\.إ\.?)', 'an amount', 'gi'),
           -- contacts: an e-mail address
           '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', 'a contact', 'g'),
           -- contacts: a phone number (a date such as 2026-10-18 or a count is not one)
           '(?:\+|\m00)\d[\d\s-]{7,}\d|\m0[2-9]\d?[\s-]?\d{3}[\s-]?\d{4}\M', 'a contact', 'g'),
           '[ \t]+([,.;:)])', '\1', 'g'),
           '[ \t]{2,}', ' ', 'g'))
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

-- THE CEO RE-APPROVES A LESSON THAT WAS CHANGED (held surface ceo.lesson_reapproval; fn_reason_held_resolve calls this
-- by name). 'approve' makes the new version live and closes its candidate as approved; 'reject' keeps it quarantined
-- and rejects the candidate. The retired original stays as history either way.
create or replace function public.fn_reason_apply_ceo__lesson_reapproval(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text; v_ak bigint; v_cand bigint; v_n int;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  v_ak := nullif(r.subject->>'knowledge_id', '')::bigint;
  v_cand := nullif(r.subject->>'candidate_id', '')::bigint;
  if v_choice is null or v_choice not in ('approve', 'reject') or v_ak is null then
    return jsonb_build_object('applied', false, 'reason', 'no approve/reject for a lesson version in the answer');
  end if;
  if v_choice = 'approve' then
    update public.agent_knowledge set validation_status = 'author_verified', updated_at = now(),
           supporting_evidence = coalesce(supporting_evidence, '') || '; re-approved by the CEO seat (held ' || p_id || ')'
     where id = v_ak and validation_status = 'quarantined';
  else
    update public.agent_knowledge set valid_until = current_date, updated_at = now(),
           supporting_evidence = coalesce(supporting_evidence, '') || '; re-approval refused by the CEO seat (held ' || p_id || ')'
     where id = v_ak;
  end if;
  get diagnostics v_n = row_count;
  if v_cand is not null then
    update public.reasoning_knowledge_candidate
       set status = case when v_choice = 'approve' then 'approved' else 'rejected' end,
           reviewed_by = 'ceo:lesson_reapproval:' || p_id, reviewed_at = now()
     where id = v_cand and status = 'pending_review';
  end if;
  return jsonb_build_object('knowledge_id', v_ak, 'candidate_id', v_cand, 'choice', v_choice, 'rows', v_n);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__lesson_reapproval(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__lesson_reapproval(bigint, jsonb) to service_role;

-- A RE-APPROVAL NEVER LAPSES SILENTLY (review of #1443 at 21c19a8). A held question EXPIRES (14 days after its first
-- attempt with the model open, fn_reason_held_expire, which hands off only non-internal questions) or FAILS (3 attempts).
-- Either would leave the new version quarantined and the original retired with nobody told. Restoring the original is
-- not an option: it is the text that carries the identifiers. So the lapse is ESCALATED: a registered handoff to the CEO
-- seat (ceo.lesson_reapproval_overdue), whose handler asks the question again and closes once the CEO has decided.
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'ceo.lesson_reapproval_overdue', 'it_engineer', 'ceo',
       'A lesson version waiting for CEO re-approval lapsed (its held question expired or failed): the lesson stays withheld until the CEO approves or rejects it. The handler asks again and closes when the CEO has decided.',
       'fn_lesson_reapproval_overdue_act', interval '72 hours', false,
       'scripts/sql/a_lesson_never_carries_a_case_or_inquiry_id_or_an_amount.sql'
 where not exists (select 1 from public.seat_handoff_kind
                    where type = 'ceo.lesson_reapproval_overdue' and from_seat = 'it_engineer' and to_seat = 'ceo');

-- The handler: decided -> the handoff completes with the decision; otherwise the question is filed again (fn_reason_hold
-- reopens an expired row at once and a failed one after 24 hours) and the handoff waits on the CEO.
create or replace function public.fn_lesson_reapproval_overdue_act(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; q public.reasoning_held_question; v_again bigint;
begin
  select * into a from public.agent_actions where id = p_id;
  select * into q from public.reasoning_held_question where id = nullif(a.detail->>'held_id', '')::bigint;
  if q.id is null then return jsonb_build_object('closed', 'the held question is gone', 'held_id', a.detail->>'held_id'); end if;
  if q.status = 'applied' then
    return jsonb_build_object('decided', q.result->'decision'->>'choice', 'held_id', q.id, 'knowledge_id', q.subject->>'knowledge_id');
  end if;
  if q.status in ('expired', 'failed') then
    -- an expired or failed row stays closed by design (R3), so the question is filed afresh under its own key and the
    -- handoff follows it. A question that FAILED in the last 7 days is not re-asked (the 3-try limit holds across
    -- re-filings, fn_reason_hold returns the failed row): the handoff then stays pending with the CEO, which is the alert.
    v_again := public.fn_reason_hold(q.seat, q.surface, q.question, q.request, '{}'::jsonb, q.subject, 'overdue_reasked',
                                     split_part(q.dedupe_key, ':reask:', 1) || ':reask:' || to_char(now() at time zone 'utc', 'YYYYMMDDHH24MISS'));
    if v_again is not null and v_again <> q.id then
      update public.agent_actions set detail = detail || jsonb_build_object('held_id', v_again, 'reasked_from', q.id) where id = p_id;
      select * into q from public.reasoning_held_question where id = v_again;
    end if;
  end if;
  return jsonb_build_object('waiting', 'the CEO seat to approve or reject lesson version #' || (q.subject->>'knowledge_id')
                                       || ' (held question ' || q.id || ', ' || q.status || ')',
                            'held_id', q.id, 'held_status', q.status, 'reasked', q.status = 'held');
end $fn$;
revoke execute on function public.fn_lesson_reapproval_overdue_act(bigint) from public, anon, authenticated;
grant execute on function public.fn_lesson_reapproval_overdue_act(bigint) to service_role;

create or replace function public.fn_lesson_reapproval_lapse_escalates()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_seat_handoff('it_engineer', 'ceo', 'ceo.lesson_reapproval_overdue', 'agent_knowledge',
    -- one escalation per lapse: a second lapse after a re-ask is a new handoff, never deduplicated into a closed one
    coalesce(new.subject->>'knowledge_id', 'held:' || new.id) || ':lapsed:' || new.status || ':' || to_char(now() at time zone 'utc', 'YYYYMMDDHH24MISS'),
    jsonb_build_object('held_id', new.id, 'lapsed_as', new.status, 'question', left(new.question, 1500),
                       'knowledge_id', new.subject->>'knowledge_id', 'supersedes_id', new.subject->>'supersedes_id',
                       'waiting_for', 'the CEO seat to approve or reject the cleaned lesson; until then it is withheld'));
  return null;
end $fn$;
revoke execute on function public.fn_lesson_reapproval_lapse_escalates() from public, anon, authenticated;
drop trigger if exists lesson_reapproval_lapse_escalates on public.reasoning_held_question;
create trigger lesson_reapproval_lapse_escalates
  after update of status on public.reasoning_held_question
  for each row when (new.surface = 'ceo.lesson_reapproval' and new.status in ('expired', 'failed')
                     and old.status is distinct from new.status)
  execute function public.fn_lesson_reapproval_lapse_escalates();

-- THE ROWS ALREADY WRITTEN (measured 18 Oct 2026: 11 candidates, 7 approved lessons, 69 case rows; no batching needed).
create or replace function public.fn_lesson_scrub_backfill()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $backfill$
declare g record; k record; v_new bigint; v_req jsonb; v_dup int := 0; v_clean int := 0; v_versioned int := 0; v_cases int := 0;
  v_opts jsonb := jsonb_build_array(
  jsonb_build_object('id', 'approve', 'meaning', 'the cleaned lesson is still correct, general know-how: make it live'),
  jsonb_build_object('id', 'reject', 'meaning', 'the lesson is wrong, or meaningless without the removed identifiers: keep it out'));
begin
  -- 1. candidates, grouped by their scrubbed text: one kept per group, the rest rejected as its duplicate
  for g in
    with s as (select r.id, r.finding, r.finding_sha, left(public.fn_lesson_scrub(r.finding), 4000) as clean from public.reasoning_knowledge_candidate r),
         t as (select s.*, md5(lower(btrim(s.clean))) as clean_sha from s),
         grp as (select t.clean_sha, count(*) as n, bool_or(t.finding <> t.clean) as dirty from t group by t.clean_sha)
    select t.id, t.finding, t.clean, t.clean_sha,
           first_value(t.id) over (partition by t.clean_sha order by (t.finding_sha = t.clean_sha) desc, t.id) as keeper
      from t join grp using (clean_sha) where grp.dirty or grp.n > 1
  loop
    if g.id <> g.keeper then
      update public.reasoning_knowledge_candidate set status = 'rejected', reviewed_at = now(),
             reviewed_by = 'rule:lesson_scrub_duplicate_of:' || g.keeper where id = g.id;
      update public.seat_lesson_cluster set candidate_id = g.keeper where candidate_id = g.id;
      update public.agent_knowledge set validation_status = 'quarantined', valid_until = current_date, updated_at = now(),
             supporting_evidence = coalesce(supporting_evidence, '') || '; retired 18 Oct 2026: its candidate is a duplicate of lesson#' || g.keeper
       where source_ref = 'lesson:' || g.id and validation_status <> 'quarantined';
      v_dup := v_dup + 1;
    end if;
  end loop;
  for g in
    select r.id, left(public.fn_lesson_scrub(r.finding), 4000) as clean from public.reasoning_knowledge_candidate r
     where r.finding <> public.fn_lesson_scrub(r.finding)
       and coalesce(r.reviewed_by, '') not like 'rule:lesson_scrub_duplicate_of:%'   -- a duplicate keeps its text: its clean text is its keeper's
  loop
    update public.reasoning_knowledge_candidate set finding = g.clean, embedding_gte = null where id = g.id;
    v_clean := v_clean + 1;
  end loop;

  -- 2. an approved lesson whose text changes: original retired as history, version + 1 quarantined, CEO asked
  for k in
    select a.* from public.agent_knowledge a
     where a.source_ref like 'lesson:%' and a.validation_status <> 'quarantined' and a.content <> public.fn_lesson_scrub(a.content)
  loop
    insert into public.agent_knowledge (agent_key, topic, content, priority, layer, source_ref, owner_agent, version, confidence,
                                        validation_status, review_due, supersedes_id, supporting_evidence)
    values (k.agent_key, k.topic, left(public.fn_lesson_scrub(k.content), 4000), k.priority, k.layer, k.source_ref, k.owner_agent,
            coalesce(k.version, 1) + 1, k.confidence, 'quarantined', k.review_due, k.id,
            coalesce(k.supporting_evidence, '') || '; v' || (coalesce(k.version, 1) + 1)
              || ' 18 Oct 2026: case ids/amounts removed (fn_lesson_scrub), awaiting CEO re-approval')
    returning id into v_new;
    update public.agent_knowledge set validation_status = 'quarantined', valid_until = current_date, updated_at = now(),
           supporting_evidence = coalesce(supporting_evidence, '') || '; retired 18 Oct 2026: carried case ids/amounts; superseded by #' || v_new
     where id = k.id;
    update public.reasoning_knowledge_candidate set status = 'pending_review', reviewed_by = null, reviewed_at = null
     where id = nullif(substring(k.source_ref from '^lesson:(\d+)$'), '')::bigint and status = 'approved';
    v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.lesson_reapproval',
      'question', 'A ' || k.agent_key || ' lesson was approved, then found to carry case ids or amounts. They were removed. '
                  || 'Is the cleaned lesson still correct, general know-how that should be live? Lesson: ' || left(public.fn_lesson_scrub(k.content), 3000),
      'context', jsonb_build_object('audience', 'internal'),
      'decision', jsonb_build_object('name', 'reapproval', 'options', v_opts),
      'subject', jsonb_build_object('knowledge_id', v_new, 'supersedes_id', k.id,
                                    'candidate_id', nullif(substring(k.source_ref from '^lesson:(\d+)$'), '')::bigint),
      'dedupeKey', 'lesson_reapproval:' || v_new);
    -- the lesson is withheld only while the CEO is asked: no question filed, no backfill (review of #1443)
    if public.fn_reason_hold('ceo', 'ceo.lesson_reapproval', v_req->>'question', v_req, '{}'::jsonb, v_req->'subject',
                             'sql_caller', v_req->>'dedupeKey') is null then
      raise exception 'lesson % v%: the CEO re-approval question was not filed (fn_reason_hold returned no id); nothing is withheld unasked',
        k.id, coalesce(k.version, 1) + 1;
    end if;
    v_versioned := v_versioned + 1;
  end loop;

  -- 3. case notes: scrubbed in place
  update public.seat_case_memory m
     set lessons = array(select public.fn_lesson_scrub(x) from unnest(m.lessons) with ordinality u(x, n) order by n), updated_at = now()
   where cardinality(m.lessons) > 0
     and m.lessons <> array(select public.fn_lesson_scrub(x) from unnest(m.lessons) with ordinality u(x, n) order by n);
  get diagnostics v_cases = row_count;
  return jsonb_build_object('duplicates_rejected', v_dup, 'candidates_cleaned', v_clean, 'lessons_sent_for_reapproval', v_versioned, 'case_rows_cleaned', v_cases);
end $backfill$;
revoke execute on function public.fn_lesson_scrub_backfill() from public, anon, authenticated;
grant execute on function public.fn_lesson_scrub_backfill() to service_role;
select public.fn_lesson_scrub_backfill();
