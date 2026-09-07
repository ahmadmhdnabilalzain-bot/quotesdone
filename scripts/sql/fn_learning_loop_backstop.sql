-- THE LEARNING LOOP HAD NO BACKSTOP, AND ITS ONE GRADE WAS A RUBBER STAMP.  6 Aug 2026, round 3.
--
-- Two findings, one file, because they are the same loop:
--
--   comp-13-task  "Every completed task enters the chain" — MISSING, 16 of 29.  Measured: the 13
--     uncovered tasks are all mode='delivered', decided_by='cos', updated between 1 and 6 Aug, and
--     every one of them was completed BEFORE cos_execute was wired to call fn_task_review (the
--     first review-written lesson lands at 2026-08-06 04:32:55; tasks 319-381 were finished at
--     :50 past the hour before that).  The live path is now correct, but nothing in the DATABASE
--     guarantees it: fn_task_review has ZERO callers in pg_proc and ZERO cron jobs, so the whole
--     claim rests on one edge function remembering.  A property that holds only while every
--     completion path remembers is not a property.
--
--   comp-13-lessons  "Performance -> Lessons is automatic" — MET on a bare `> 0`.  fn_task_review
--     calls fn_task_lesson inside `begin ... exception when others then null`, so a lesson that
--     fails to write is lost silently and permanently: nothing ever retries it.  Measured: 4 of
--     the 18 org_tasks reviewed in the last 7 days carry no lesson (49, 50, 51, 157 — reviewed
--     04:12-04:20, before the lesson call existed) and no mechanism will ever come back for them.
--
-- The backstop below closes both from the same query the checks use.  It does NOT reimplement the
-- review or the lesson — it calls the existing fn_task_review and fn_task_lesson, so a row it
-- produces is the real mechanism running late, not a row written to satisfy a gate.
--
-- FEEDBACK-LOOP CHECK, done before wiring and recorded here because the standing warning demands
-- it.  review_chain carries trg_event_review (AFTER INSERT, WHEN stage='published' OR decision in
-- reject/request_revision/hold_for_human/escalate) which emits company_event 'review.step';
-- knowledge_director subscribes to it, and 46 org_tasks have already been raised that way.  That
-- edge EXISTS TODAY and is not created here: every review cos_execute runs already feeds it.  The
-- sweep is bounded to the same 7-day window the requirement is scored over (13 rows today, not the
-- 95 unchained all-time) and to p_limit rows per run, so it can never stampede the bus with a
-- backlog.  fn_task_lesson writes only institutional_memory, which carries no trigger at all.

-- ---------------------------------------------------------------------------------------------
-- 1. THE GRADE COMES OFF THE ROW, NOT OFF THE BRANCH.
--
-- comp-12-successes was MET on a writer that could not record anything but success: the
-- p_outcome='event_closed' branch set v_what := 'success' with confidence 0.6 for EVERY closed
-- event-bus task, with no grading of any kind, and 58 of the 81 rows carrying the requirement were
-- exactly those stamps.  "Successes are recorded as successes" cannot be evidence of anything when
-- the recorder has one word.
--
-- Three signals, all already on the row, none of them new machinery: the reviewer's own verdict
-- where the task had a review, the executor's recorded error where it had one, and whether the
-- task closed having recorded anything at all.  Closing is not achieving — a task that finished
-- with an empty summary is 'no_change' at 0.4, below fn_agent_institutional_memory's 0.6 floor, so
-- it is kept for the audit trail and not served to anybody as a lesson.
--
-- Measured against production's 60 existing event lessons this grades all 60 the same way it found
-- them (every one is status='done' with a non-empty summary and mode='delivered', and the two that
-- were also reviewed were approved), which is the honest answer: today's closed event work really
-- did all succeed.  What changes is that tomorrow's does not have to.
create or replace function public.fn_task_lesson(p_task_id bigint, p_outcome text, p_review jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare
  t record; v_id bigint; v_kind text; v_conf numeric; v_detail text; v_what text;
  v_verdict text; v_result text; v_basis text;
begin
  select o.id, o.dept_key, o.title, o.action_class, o.tier, o.result, o.status from org_tasks o
    into t where o.id = p_task_id;
  if t.id is null then return null; end if;

  -- What the review actually found, in the review's own words. Violations first because a failure
  -- is the lesson; dissents next; otherwise the approval and who gave it.
  select string_agg(distinct (v->>'rule') || ' (' || (v->>'severity') || '): ' || coalesce(v->>'why',''), ' | ')
    into v_detail from jsonb_array_elements(coalesce(p_review->'violations','[]'::jsonb)) v;

  if v_detail is null or v_detail = '' then
    select string_agg((d->>'by') || ' ' || (d->>'stance') || ': ' || left(coalesce(d->>'reasoning',''), 300), ' | ')
      into v_detail from jsonb_array_elements(coalesce(p_review->'dissents','[]'::jsonb)) d;
  end if;

  if p_outcome = 'event_closed' then
    -- xos-10. The Knowledge OS captures what a DISPATCHED EVENT produced, GRADED against the row.
    select c.decision into v_verdict
      from review_chain c
     where c.subject_type = 'org_task' and c.subject_id = t.id::text
       and c.stage in ('published','cos_review','dept_review') and c.decision is not null
     order by c.created_at desc, c.id desc
     limit 1;

    v_result := coalesce(nullif(t.result->>'summary',''), '');
    v_kind   := 'lesson';

    if coalesce(v_verdict,'') in ('reject','request_revision','hold_for_human','escalate')
       or coalesce(t.result->'executed'->>'error','') <> ''
       or v_result ~* '^\s*executor error'
       or coalesce(t.status,'') not in ('done','closed') then
      v_kind  := 'lesson_learned';
      v_conf  := 0.85;   -- a failure is the most useful thing this loop can record
      v_what  := 'worse';
      v_basis := case when coalesce(v_verdict,'') <> '' then 'the review verdict "' || v_verdict || '"'
                      else 'the outcome the task itself recorded' end;
    elsif v_result = '' then
      v_conf  := 0.4;    -- below the 0.6 retrieval floor: nothing was recorded, so there is nothing to serve
      v_what  := 'no_change';
      v_basis := 'the absence of any recorded result';
    else
      v_conf  := 0.6;    -- the floor fn_agent_institutional_memory serves from
      v_what  := 'success';
      v_basis := case when coalesce(v_verdict,'') <> '' then 'the review verdict "' || v_verdict || '"'
                      else 'the result the task recorded on closing' end;
    end if;

    v_detail := 'Raised by ' || coalesce(p_review->>'event_type','a company event')
             || ' on the bus and closed by ' || t.dept_key || '. Result: '
             -- org_tasks.result is JSONB, not text: the OS writes {at, mode, brain, summary} and
             -- the summary is the part that is a lesson. `nullif(t.result,'')` casts '' to jsonb
             -- at CALL time — it survived a staging apply that had no closed tasks to iterate and
             -- failed on production's 58. ->> returns text and never has to cast.
             || left(coalesce(nullif(v_result,''), 'closed with no recorded result'), 600)
             || '. Correlation ' || coalesce(p_review->>'correlation_id','unknown')
             || '. Graded ' || v_what || ' on ' || v_basis || '.';
  elsif p_outcome = 'published' and (v_detail is null or v_detail = '') then
    v_kind   := 'lesson';
    v_conf   := 0.5;   -- recorded for the audit trail; below fn_agent_institutional_memory's 0.6 floor
    v_detail := 'Cleared the quality standard for a department deliverable on the first pass and was '
             || 'approved by ' || coalesce(p_review->>'reviewer','the department head') || ' and the Chief of Staff.';
    v_what   := 'success';
  elsif p_outcome = 'published' then
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;  -- shipped OVER a recorded objection: the most useful thing to remember
    v_detail := 'Approved and published despite a recorded objection. ' || v_detail;
    v_what   := 'success_over_dissent';
  else
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;
    v_detail := 'Returned by review (' || p_outcome || '). ' || coalesce(v_detail, 'see review_chain');
    v_what   := 'worse';
  end if;

  insert into institutional_memory
    (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence,
     evidence_ref, visible_to, occurred_at)
  values (v_kind, 'org_task', t.id::text,
          left(t.dept_key || ': ' || coalesce(t.title,'(untitled task)'), 200),
          left(v_detail, 2000), v_what, t.dept_key, v_conf,
          case when p_outcome = 'event_closed'
               then 'event_delivery:org_task:' || t.id
               else 'review_chain:org_task:' || t.id end,
          array[t.dept_key], now())
  returning id into v_id;

  return v_id;
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 2. THE BACKSTOP.  Two legs, both NOT EXISTS over the same population the requirement is scored
-- on, so the sweep cannot decline to handle a row the check will count.
--
--   LEG A  a completed deliverable with no review at all -> run the real review.
--   LEG B  a review with no lesson -> write the lesson the reviewer's own verdict implies.
--
-- Leg B exists because fn_task_review swallows a failing fn_task_lesson by design ("never let
-- recording the lesson fail the review itself") and nothing retried it.  The outcome it passes is
-- read back out of review_chain, so the lesson says what the reviewer said: a published+approve
-- chain replays as 'published', anything else replays as its own terminal decision, which
-- fn_task_lesson records as 'worse'.  Nothing is invented — a task with no review gets no lesson.
create or replace function public.fn_learning_loop_sweep(p_limit integer default 25)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; n_rev int := 0; n_les int := 0; n_err int := 0; v_lid bigint;
begin
  -- LEG A. Bounded to the seven days the requirement is scored over: reviewing a deliverable from
  -- June tells nobody anything and would put a backlog onto the event bus in one burst.
  for r in
    select o.id
      from org_tasks o
     where o.status = 'done'
       and coalesce(o.result->>'deliverable','') <> ''
       and o.updated_at > now() - interval '7 days'
       and not exists (select 1 from review_chain c
                        where c.subject_type = 'org_task' and c.subject_id = o.id::text)
     order by o.updated_at
     limit greatest(coalesce(p_limit, 25), 0)
  loop
    begin
      perform fn_task_review(r.id);
      n_rev := n_rev + 1;
    exception when others then
      -- One unreviewable task must not stop the sweep; it is counted, not swallowed.
      n_err := n_err + 1;
    end;
  end loop;

  -- LEG B. Sees leg A's own inserts (same transaction), so a review written above whose inline
  -- lesson threw is retried here rather than lost.
  --
  -- The population is the rows fn_review_submit/fn_task_review write — stage published, cos_review
  -- or dept_review.  stage='approval' is deliberately NOT in it: those rows are fn_task_approve
  -- routing a task ONTO an approval path before it is worked (it sets status='assigned'), not a
  -- verdict on completed work, and demanding a lesson for a task nobody has done yet is a
  -- requirement no future work could satisfy.
  for r in
    select s.sid,
           case when exists (select 1 from review_chain p
                              where p.subject_type = 'org_task' and p.subject_id = s.sid
                                and p.stage = 'published' and p.decision = 'approve')
                then 'published'
                else coalesce((select d.decision from review_chain d
                                where d.subject_type = 'org_task' and d.subject_id = s.sid
                                  and d.stage in ('cos_review','dept_review') and d.decision is not null
                                order by d.created_at desc, d.id desc limit 1), 'hold') end as outcome,
           coalesce((select jsonb_agg(jsonb_build_object(
                              'by', ch.reviewer_agent, 'stance', ch.decision,
                              'reasoning', left(coalesce(ch.reason,''), 300)))
                       from review_chain ch
                      where ch.subject_type = 'org_task' and ch.subject_id = s.sid
                        and ch.stage = 'challenge'), '[]'::jsonb) as dissents,
           coalesce((select rr.reviewer_agent from review_chain rr
                      where rr.subject_type = 'org_task' and rr.subject_id = s.sid
                        and rr.stage in ('cos_review','dept_review') and rr.reviewer_agent is not null
                      order by rr.created_at desc, rr.id desc limit 1), 'the department head') as reviewer
      from (select distinct c.subject_id as sid
              from review_chain c
             where c.subject_type = 'org_task'
               and c.stage in ('published','cos_review','dept_review')
               and c.created_at > now() - interval '7 days'
               and exists (select 1 from org_tasks o where o.id::text = c.subject_id)
               and not exists (select 1 from institutional_memory m
                                where m.subject_type = 'org_task' and m.subject_id = c.subject_id
                                  and m.evidence_ref = 'review_chain:org_task:' || m.subject_id)
             limit greatest(coalesce(p_limit, 25), 0)) s
  loop
    begin
      v_lid := fn_task_lesson(r.sid::bigint, r.outcome,
                 jsonb_build_object('violations', '[]'::jsonb,
                                    'dissents',   r.dissents,
                                    'reviewer',   r.reviewer));
      if v_lid is not null then n_les := n_les + 1; end if;
    exception when others then
      n_err := n_err + 1;
    end;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('learning_loop_sweep', now(), now(), case when n_err > 0 then 'partial' else 'ok' end,
          jsonb_build_object('reviews_run', n_rev, 'lessons_written', n_les, 'failed', n_err),
    'Learning-loop backstop: ' || n_rev || ' completed deliverable(s) that no path had reviewed '
    || 'entered the review chain, ' || n_les || ' review(s) whose lesson never landed had it '
    || 'written from the reviewer''s own verdict, ' || n_err || ' could not be processed.');

  return jsonb_build_object('reviews_run', n_rev, 'lessons_written', n_les, 'failed', n_err);
end
$function$;

comment on function public.fn_learning_loop_sweep(integer) is
  'Backstop for the learning loop. Reviews any completed deliverable of the last 7 days that no '
  'completion path put into review_chain, and writes the lesson for any review of the last 7 days '
  'whose inline fn_task_lesson call failed silently inside fn_task_review''s exception handler. '
  'Calls the real fn_task_review / fn_task_lesson; invents nothing.';

-- A backstop that never runs is the defect wearing a different hat. Hourly at :35, clear of
-- execution_run (:10), execution_sweep (:20) and event_consolidate (:25).
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
