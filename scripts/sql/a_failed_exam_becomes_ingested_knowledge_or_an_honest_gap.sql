-- A FAILED EXAM BECOMES INGESTED KNOWLEDGE OR AN HONEST GAP (7 Sep 2026).
--
-- The founder's ruling of 6 Sep: "create a list of the top certificates for every position we have
-- in the company and then test all agents. if they dont pass them all, then their knowledge is
-- simply not enough." The list, the banks and the deterministic sitter
-- (fn_certification_exam_sit / _sit_all / _summary) already exist. This file closes the loop from a
-- failed exam back to knowledge, deterministically, with no paid model:
--
--   public.certification_knowledge_gap        one row per (agent, certification, syllabus area) the
--                                             employee failed or abstained on; history is kept
--                                             (status open -> ingested -> closed, never a delete).
--   public.fn_certification_gaps_refresh()    rewrites the open gaps from the NEWEST result per
--                                             (agent, certification). It reads only what the sitter
--                                             measured, so it can never invent a gap; an area that
--                                             is now fully correct is closed, not removed.
--   public.fn_certification_gap_sources(...)  what the estate actually holds for one area: the
--                                             ops_knowledge records the employee's department can
--                                             reach (via fn_ops_knowledge_search — reused, not
--                                             re-implemented), the employee's own agent_knowledge,
--                                             and kb_chunks. Every candidate must additionally match
--                                             a plainto_tsquery (AND) of the syllabus area, so a
--                                             company-wide record that merely shares a common word
--                                             is not counted as teaching the area. A nearest
--                                             neighbour is always found; a corroborated one is not.
--   public.fn_certification_ingestion_plan()  the founder-facing plan, rank-1 certifications first.
--                                             An area with no corroborated source is returned with
--                                             the finding 'nothing here teaches this' — that is the
--                                             material the company has to buy or write, and it is
--                                             reported, never papered over.
--   public.fn_certification_gap_ingest(...)   promotes the material the estate DOES hold into that
--                                             employee's own agent_knowledge (layer 'profession'),
--                                             recording the source record ids as provenance, and
--                                             marks the gap 'ingested'. It RAISES when the area has
--                                             no source: knowledge is never invented to pass an exam.
--   public.fn_certification_resit(...)        sits again and returns before/after score and which
--                                             areas moved. It changes no question, no key and no
--                                             pass mark; scripts/checks/an_exam_is_not_edited_to_be_passed.test.mjs
--                                             proves that by hashing the bank and the pass marks
--                                             either side of a re-sit inside an aborted transaction.
--
--   node scripts/apply_sql.mjs scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql --apply --ddl

create table if not exists public.certification_knowledge_gap (
  id                  bigserial primary key,
  agent_key           text        not null,
  certification       text        not null,
  syllabus_area       text        not null,
  asked               integer     not null,
  correct             integer     not null,
  score_pct           numeric     not null,
  missed_question_ids bigint[]    not null default '{}',
  first_seen          timestamptz not null default now(),
  last_seen           timestamptz not null default now(),
  status              text        not null default 'open'
                      check (status in ('open','ingested','closed')),
  ingested_at         timestamptz,
  closed_at           timestamptz,
  unique (agent_key, certification, syllabus_area)
);
create index if not exists certification_knowledge_gap_open_idx
  on public.certification_knowledge_gap (status, agent_key);

CREATE OR REPLACE FUNCTION public.fn_certification_gaps_refresh()
 RETURNS TABLE(opened integer, updated integer, closed integer, open_total integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_opened int := 0; v_updated int := 0; v_closed int := 0;
begin
  -- the newest sitting per (agent, certification), one row per syllabus area it measured
  drop table if exists _cert_area;
  create temporary table _cert_area on commit drop as
  with latest as (
    select distinct on (r.agent_key, r.certification) r.*
      from public.certification_exam_result r
     order by r.agent_key, r.certification, r.sat_at desc, r.id desc
  )
  select l.agent_key, l.certification,
         coalesce(e->>'syllabus_area','(unstated)')            as syllabus_area,
         count(*)::int                                          as asked,
         count(*) filter (where (e->>'correct')::boolean)::int  as correct,
         array_remove(array_agg(case when not (e->>'correct')::boolean
                                     then (e->>'question_id')::bigint end
                                order by (e->>'question_id')::bigint), null) as missed
    from latest l, jsonb_array_elements(l.answers) e
   group by 1,2,3;

  with up as (
    insert into public.certification_knowledge_gap
      (agent_key, certification, syllabus_area, asked, correct, score_pct, missed_question_ids, status, last_seen)
    select a.agent_key, a.certification, a.syllabus_area, a.asked, a.correct,
           round(100.0 * a.correct / greatest(a.asked,1), 2), a.missed, 'open', now()
      from _cert_area a
     where a.correct < a.asked                       -- failed or abstained: measured, never invented
    on conflict (agent_key, certification, syllabus_area) do update set
      asked = excluded.asked, correct = excluded.correct, score_pct = excluded.score_pct,
      missed_question_ids = excluded.missed_question_ids, last_seen = now(),
      status = 'open',                               -- still missed: it re-opens, history is kept
      closed_at = null
    returning (xmax = 0) as inserted
  )
  select coalesce(count(*) filter (where inserted),0)::int,
         coalesce(count(*) filter (where not inserted),0)::int
    into v_opened, v_updated from up;

  with cl as (
    update public.certification_knowledge_gap g
       set status = 'closed', closed_at = now(), last_seen = now(),
           asked = a.asked, correct = a.correct,
           score_pct = round(100.0 * a.correct / greatest(a.asked,1), 2),
           missed_question_ids = '{}'
      from _cert_area a
     where a.agent_key = g.agent_key and a.certification = g.certification
       and a.syllabus_area = g.syllabus_area
       and a.correct = a.asked and g.status <> 'closed'
    returning 1
  )
  select coalesce(count(*),0)::int into v_closed from cl;

  return query
    select v_opened, v_updated, v_closed,
           (select count(*)::int from public.certification_knowledge_gap where status = 'open');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_certification_gap_sources(p_agent text, p_certification text, p_area text)
 RETURNS TABLE(source_kind text, source_id text, title text, content text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_dept text; v_area tsquery;
begin
  select a.department into v_dept from public.org_agents a where a.agent_key = p_agent and a.active;
  begin v_area := plainto_tsquery('english', coalesce(p_area,'')); exception when others then return; end;
  if v_area is null or v_area::text = '' then return; end if;   -- no terms to corroborate against

  return query
  with ops as (
    select 'ops_knowledge'::text as sk, k.record_id::text as sid, k.title as ti, k.content as co
      from public.fn_ops_knowledge_search(v_dept, concat_ws(' ', p_area, p_certification), 20) k
     where to_tsvector('english', concat_ws(' ', k.title, k.content)) @@ v_area
  ), own as (
    select 'agent_knowledge'::text, ak.id::text, ak.topic, ak.content
      from public.agent_knowledge ak
     where ak.agent_key = p_agent
       and coalesce(ak.topic,'') not like 'certification gap:%'   -- never feed on its own ingestion
       and to_tsvector('english', concat_ws(' ', ak.topic, ak.content)) @@ v_area
     order by ak.priority desc nulls last, ak.id
     limit 5
  ), kb as (
    select 'kb_chunks'::text, c.id::text, c.title, c.content
      from public.kb_chunks c
     where c.fts @@ v_area
     order by c.id
     limit 5
  )
  select * from ops union all select * from own union all select * from kb;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_certification_ingestion_plan()
 RETURNS TABLE(agent_key text, department text, certification text, cert_rank smallint,
               pass_mark_pct numeric, score_pct numeric, syllabus_area text,
               asked integer, missed integer, source_count integer, source_ids text[], finding text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with latest as (
    select distinct on (r.agent_key, r.certification) r.*
      from public.certification_exam_result r
     order by r.agent_key, r.certification, r.sat_at desc, r.id desc
  ), g as (
    select gg.*, rc.rank as cert_rank, rc.pass_mark_pct as pass_mark, l.score_pct as exam_score,
           a.department as dept
      from public.certification_knowledge_gap gg
      join public.role_certification rc
        on rc.agent_key = gg.agent_key and rc.certification = gg.certification
      join public.org_agents a on a.agent_key = gg.agent_key and a.active
      left join latest l on l.agent_key = gg.agent_key and l.certification = gg.certification
     where gg.status = 'open'
  ), s as (
    select g.*, src.sid
      from g
      left join lateral (
        select array_agg(x.source_kind || ':' || x.source_id order by x.source_kind, x.source_id) as sid
          from public.fn_certification_gap_sources(g.agent_key, g.certification, g.syllabus_area) x
      ) src on true
  )
  select s.agent_key, s.dept, s.certification, s.cert_rank, s.pass_mark, s.exam_score,
         s.syllabus_area, s.asked, (s.asked - s.correct)::int,
         coalesce(array_length(s.sid,1),0)::int, coalesce(s.sid,'{}'::text[]),
         case when coalesce(array_length(s.sid,1),0) = 0
              then 'nothing here teaches this — buy or write it'
              else 'ingestible from the estate' end
    from s
   order by s.cert_rank, (s.asked - s.correct) desc, s.agent_key, s.certification, s.syllabus_area;
$function$;

CREATE OR REPLACE FUNCTION public.fn_certification_gap_ingest(p_agent text, p_certification text, p_area text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gap public.certification_knowledge_gap; v_body text; v_ids text[]; v_id bigint;
begin
  select * into v_gap from public.certification_knowledge_gap
   where agent_key = p_agent and certification = p_certification and syllabus_area = p_area;
  if v_gap.id is null then
    raise exception 'fn_certification_gap_ingest: no gap for % / % / %', p_agent, p_certification, p_area;
  end if;

  select string_agg('• ' || coalesce(s.title,'(untitled)') || ' [' || s.source_kind || ':' || s.source_id || '] — '
                    || left(regexp_replace(coalesce(s.content,''), '\s+', ' ', 'g'), 1200),
                    E'\n' order by s.source_kind, s.source_id),
         array_agg(s.source_kind || ':' || s.source_id order by s.source_kind, s.source_id)
    into v_body, v_ids
    from public.fn_certification_gap_sources(p_agent, p_certification, p_area) s;

  if v_ids is null or array_length(v_ids,1) = 0 then
    -- the honest refusal: the estate holds nothing that teaches this area, and an exam is never
    -- passed by inventing the material.
    raise exception 'fn_certification_gap_ingest: nothing in the estate teaches % / % for % — buy or write it',
      p_certification, p_area, p_agent;
  end if;

  insert into public.agent_knowledge
    (agent_key, topic, content, priority, layer, source_ref, owner_agent, confidence, validation_status)
  values
    (p_agent,
     'certification gap: ' || p_certification || ' — ' || p_area,
     format('%s syllabus area "%s". The employee missed %s of %s questions here. What the company already holds:%s%s',
            p_certification, p_area, v_gap.asked - v_gap.correct, v_gap.asked, E'\n', v_body),
     90, 'profession', array_to_string(v_ids, ','), p_agent, 0.80, 'ingested_from_estate')
  returning id into v_id;

  update public.certification_knowledge_gap
     set status = 'ingested', ingested_at = now()
   where id = v_gap.id;

  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_certification_resit(p_agent text, p_certification text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_before public.certification_exam_result; v_after public.certification_exam_result; v_moved jsonb;
begin
  select * into v_before from public.certification_exam_result
   where agent_key = p_agent and certification = p_certification
   order by sat_at desc, id desc limit 1;

  v_after := public.fn_certification_exam_sit(p_agent, p_certification);

  select coalesce(jsonb_agg(jsonb_build_object(
           'syllabus_area', a.area, 'asked', a.asked,
           'correct_before', b.ok, 'correct_after', a.ok, 'moved', a.ok - coalesce(b.ok, a.ok))
           order by (a.ok - coalesce(b.ok, a.ok)) desc, a.area), '[]'::jsonb)
    into v_moved
    from (select w->>'syllabus_area' as area, (w->>'asked')::int asked, (w->>'correct')::int ok
            from jsonb_array_elements(v_after.weakest_areas) w) a
    left join (select w->>'syllabus_area' as area, (w->>'correct')::int ok
                 from jsonb_array_elements(coalesce(v_before.weakest_areas,'[]'::jsonb)) w) b
      on b.area = a.area
   where a.ok is distinct from b.ok;

  return jsonb_build_object(
    'agent_key', p_agent, 'certification', p_certification,
    'pass_mark_pct', v_after.pass_mark_pct,
    'score_before', v_before.score_pct, 'passed_before', v_before.passed,
    'score_after',  v_after.score_pct,  'passed_after',  v_after.passed,
    'areas_moved', v_moved);
end $function$;

revoke execute on function public.fn_certification_gaps_refresh() from public, anon, authenticated;
revoke execute on function public.fn_certification_gap_sources(text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_certification_ingestion_plan() from public, anon, authenticated;
revoke execute on function public.fn_certification_gap_ingest(text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_certification_resit(text, text) from public, anon, authenticated;
revoke all on public.certification_knowledge_gap from public, anon, authenticated;

insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification, recorded_at)
values
  ('public','fn_certification_gaps_refresh','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql (7 Sep 2026)','MANIFEST','scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql',null,now()),
  ('public','fn_certification_gap_sources','p_agent text, p_certification text, p_area text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql (7 Sep 2026)','MANIFEST','scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql',null,now()),
  ('public','fn_certification_ingestion_plan','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql (7 Sep 2026)','MANIFEST','scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql',null,now()),
  ('public','fn_certification_gap_ingest','p_agent text, p_certification text, p_area text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql (7 Sep 2026)','MANIFEST','scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql',null,now()),
  ('public','fn_certification_resit','p_agent text, p_certification text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql (7 Sep 2026)','MANIFEST','scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql',null,now())
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  recorded_at = now();
