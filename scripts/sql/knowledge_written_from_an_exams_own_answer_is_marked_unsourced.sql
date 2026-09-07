-- KNOWLEDGE WRITTEN FROM AN EXAM'S OWN ANSWER IS MARKED UNSOURCED (7 Sep 2026).
--
-- THE FOUNDER'S QUESTION, 7 Sep 2026: "so the knowledge missing is just the correct answers?" The answer
-- for the new certification exam is no, and scripts/checks/an_exam_answer_never_becomes_knowledge.test.mjs
-- keeps it that way. But the question sent me to look at what was already there, and the older
-- knowledge_exam loop in this estate did exactly that: when an employee missed a question, it wrote the
-- exam's own reference answer into agent_knowledge as a new fact.
--
-- MEASURED on production before this file: 557 agent_knowledge rows across 110 agent keys, 927,386
-- characters carry an 'exam:' topic. 397 of them (700,042 characters, 84 agents) had already been
-- quarantined by earlier work and reach no head. The 160 that remain live are the subject of this file,
-- and 122 of those carry validation_status 'author_verified' — an exam's own answer labelled as though
-- a person had checked it, which is the worst of the three states. 61 of the 160 sit in the profession
-- and state layers that build LAYER 2 of every head. Their content matches the reference answers in
-- knowledge_exam_questions 3,046 times. The Visual Design Specialist is the clearest case — nine knowledge rows, of which exactly one
-- is about design (684 characters) and eight came from that autofill, about marketing economics and
-- package manifests.
--
-- WHAT THIS FILE DOES, AND WHAT IT DELIBERATELY DOES NOT DO. It does not delete them: the text is mostly
-- true professional content and deleting 927 kB would make the company worse today without making it
-- more honest. It marks them 'unsourced' with their provenance, so that:
--   * every head that carries one prefixes it with a warning, through fn_knowledge_staleness_tag, so no
--     employee treats it as authority;
--   * the certification exam stops counting it as evidence — an exam must measure sourced knowledge, or
--     it is scoring material an exam wrote;
--   * the ingestion plan can target them for replacement from primary sources.
-- 'unsourced' is a new status, not 'quarantined': quarantined rows are hidden from every head, and hiding
-- these would empty most employees on the day the company is being examined.
--
--   node scripts/apply_sql.mjs scripts/sql/knowledge_written_from_an_exams_own_answer_is_marked_unsourced.sql --apply --ddl

begin;

update public.agent_knowledge
   set validation_status = 'unsourced',
       source_ref = coalesce(nullif(source_ref, ''), 'knowledge_exam autofill (before 7 Sep 2026): written from the exam''s own reference answer, not from a primary source')
 where topic like 'exam:%'
   and coalesce(validation_status, '') <> 'quarantined';

-- the tag every head prints in front of such a row
CREATE OR REPLACE FUNCTION public.fn_knowledge_staleness_tag(p_review_due date, p_validation_status text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when coalesce(p_validation_status,'') = 'unsourced'
      then '[UNSOURCED - written from an exam''s own answer, not a primary source; verify before relying on it] '
    when coalesce(p_validation_status,'') = 'stale' or (p_review_due is not null and p_review_due < current_date)
      then '[STALE - review was due '||coalesce(p_review_due::text,'(undated)')||'; verify before relying on it] '
    else '' end;
$function$;

do $$
declare n_marked int; n_tagged int;
begin
  select count(*) into n_marked from public.agent_knowledge where validation_status = 'unsourced';
  if n_marked <> 160 then raise exception 'expected 160 live exam-autofill rows to be marked, found %', n_marked; end if;
  select count(*) into n_tagged from public.agent_knowledge
   where validation_status = 'unsourced'
     and public.fn_knowledge_staleness_tag(review_due, validation_status) like '[UNSOURCED%';
  if n_tagged <> n_marked then raise exception 'only % of % unsourced rows carry the warning', n_tagged, n_marked; end if;
  raise notice 'marked % agent_knowledge row(s) unsourced; every one now prints the warning in the head', n_marked;
end $$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/knowledge_written_from_an_exams_own_answer_is_marked_unsourced.sql',
       evidence = 'the unsourced tag for knowledge an exam wrote about itself (7 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_knowledge_staleness_tag';

commit;
