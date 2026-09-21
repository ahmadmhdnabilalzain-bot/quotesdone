#!/usr/bin/env node
// RETIRED 9 September 2026 — its subject was deleted on 7 September 2026, the day it was written.
//
// WHAT WAS DROPPED. Every table and routine both legs drive is gone from production
// htdblwldjkcgjvmqkbeh, measured 9 Sep 2026:
//   select to_regclass('public.role_certification')            ->  null
//   select to_regclass('public.certification_exam_question')   ->  null
//   select to_regclass('public.certification_exam_result')     ->  null
//   fn_certification_gaps_refresh, fn_certification_ingestion_plan, fn_certification_gap_ingest,
//   fn_certification_resit                                     ->  all absent from pg_proc
// The SQL this file names as the loop it guards,
// scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql, has no live routine left.
//
// WHY THE PROPERTY HAS NO SUBJECT. "An exam is not edited to be passed" needs a pass to be edited
// into. This check's entire apparatus measures that pass: the 52 issuing-body pass marks (CPA 75,
// PMP 61, CISSP 70 …) it asserts against role_certification.pass_mark_pct, the per-certification hash
// over id/syllabus_area/stem/four options/correct_option, and the xmin identity hash over the bank.
// The surviving exam machinery has none of it. public.knowledge_exam_questions (1,530 rows) carries
// only id, agent_key, question, reference_answer, topic, difficulty — no options, no key, no
// certification, no pass mark. public.knowledge_exam_results (0 rows) grades by verdict, converged
// and gap_fact, not against a mark. There is no pass/fail threshold anywhere in the surviving loop,
// so there is nothing an edit could move a score across.
//
// A re-point would not be a re-point. It would be a new check of a different property — that a
// document-derived question bank is not mutated — against a machine whose cron job
// 'knowledge_exam_loop' no longer exists (cron.job holds 1 job, 0 active). Building that is the
// founder's call, not this session's.
//
// CORRECTION, 9 Sep 2026. An earlier draft of this header said the loop's ingester is the edge
// function supabase/functions/knowledge_exam rather than a database routine. Both halves are false
// and it is corrected rather than left standing: there is NO supabase/functions/knowledge_exam in
// this repository, and THREE live routines name public.knowledge_exam_results — fn_exam_revert,
// fn_knowledge_exam_summary and fn_ws_agent_ops. None of them INSERTs into it, which is why the
// table stands at 0 rows: they read and summarise a result the loop has never produced.
//
// The retirement verdict is UNCHANGED, and now rests on a measurement rather than on that claim:
// no routine whose body mentions knowledge_exam names a pass mark, threshold or comparison against
// one. There is still no score for an edit to move.
//
// The original file follows, unchanged.
//
// AN EXAM IS NOT EDITED TO BE PASSED (7 Sep 2026).
//
// The knowledge loop (scripts/sql/a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql)
// may only move the employee's knowledge. If it could touch a question, a key or a pass mark, every
// later "passed" would measure the harness instead of the employee. This check proves it against
// production in aborted transactions:
//
//   LEG A (asserted, always runs). In one transaction: seed the sitting the loop consumes from the
//     REAL bank (in the first two syllabus areas the first question is missed — two gaps, because
//     each one costs the plan a real corpus search and the transport caps a statement at 120 s), run
//     fn_certification_gaps_refresh(), fn_certification_ingestion_plan() and
//     fn_certification_gap_ingest() — the entire write path this loop performs — with the bank
//     hashed per certification (id, syllabus area, stem, four options, key), every
//     role_certification pass mark hashed, and the bank's row identities hashed (id, xmin;
//     Postgres bumps xmin on any UPDATE, so an edited row cannot keep its identity) before and
//     after. All three must be identical.
//   LEG B (the re-sit). fn_certification_resit() runs the real sitter twice over. One sitting
//     scores 40 questions against the whole reachable estate and does NOT finish inside the
//     management API's hard 120 s statement cap (measured 7 Sep 2026: 121 s, cancelled, and
//     set_config('statement_timeout') does not lift it). When that cap cancels the leg the check
//     says so and proves nothing about it, rather than reporting a green it did not measure; from a
//     session without that cap the leg asserts the same three hashes across the re-sit.
//   Both legs also assert role_certification.pass_mark_pct equals the mark the issuing body
//   publishes, for every row, from the list in the author's brief of 6 Sep 2026.
//
// Every transaction ends in a raise, so nothing this check writes survives it.
//
// Boundary, stated because it cannot be measured otherwise: certification_exam_question has no
// updated_at column and this database runs with track_commit_timestamp = off, so "no row was
// updated after its created_at" cannot be read per row from the tuple. The xmin identity hash is
// the measurable form of the same claim across the window the check holds open.
//
//   node scripts/checks/an_exam_is_not_edited_to_be_passed.test.mjs

// A REPO-RELATIVE IMPORT. This was an absolute file:///C:/Users/... URL, which resolves on one
// laptop and on no CI runner anywhere.
import { sql } from '../../lib/db.mjs';

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// A MISSING CREDENTIAL IS NOT A FAILING EXAM. This check reads production, and the job that runs
// npm test has no management token. Without this guard it threw "No Supabase access token" and
// reported six red tests that had asserted nothing at all -- which is the same defect in reverse as
// a check that passes while the thing it checks is broken. It SKIPS where it cannot measure, and it
// is named in the kernel-gate job, which has the token, so it still runs for real every push.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// This file is a SCRIPT, not a node:test suite -- it drives two legs and exits. So the skip has to
// be an exit, taken before the first read, and it has to be exit 0: a check that could not measure
// is not a check that failed.
if (!hasToken) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token, so production cannot be');
  console.log('read. This gate proves an exam answer cannot be edited into a pass; it asserts nothing');
  console.log('here. It is named in the kernel-gate job, which holds the token, and runs there.');
  process.exit(0);
}

// the marks the issuing bodies publish, from the author's brief of 6 Sep 2026
const MARKS = [
  ['CPA (Certified Public Accountant)', 75], ['CMA (Certified Management Accountant)', 72],
  ['ACCA (Association of Chartered Certified Accountants)', 50], ['APS (Accredited Payables Specialist)', 70],
  ['CICM Level 3 Diploma in Credit Management', 50], ['CCE (Certified Credit Executive)', 70],
  ['CTP (Certified Treasury Professional)', 70], ['CAMS (Certified Anti-Money Laundering Specialist)', 75],
  ['CCXP (Certified Customer Experience Professional)', 68], ['CCSM (Certified Customer Success Manager)', 80],
  ['HDI-CSR (HDI Customer Service Representative)', 75], ['HDI-SCA (HDI Support Center Analyst)', 75],
  ['ITIL 4 Foundation', 65], ['Braze Certified Marketer', 75],
  ['CIPS Level 4 Diploma in Procurement and Supply', 50],
  ['CIPS Level 5 Advanced Diploma in Procurement and Supply', 50],
  ['MCIPS (CIPS Level 6 Professional Diploma)', 50], ['CPSM (Certified Professional in Supply Management)', 70],
  ['CSCP (Certified Supply Chain Professional)', 70], ['CFE (Certified Fraud Examiner)', 75],
  ['CSAP (Certified Strategic Alliance Professional)', 70], ['CSP (Certified Sales Professional)', 80],
  ['CIP (Certified Information Professional)', 70], ['CIM Level 6 Diploma in Professional Marketing', 50],
  ['Google Analytics 4 Certification', 80], ['CDMP-DMI (Certified Digital Marketing Professional)', 60],
  ['Meta Certified Digital Marketing Associate', 70], ['Adobe Certified Professional in Visual Design', 70],
  ['CXL Conversion Optimization Minidegree', 80],
  ['CIPP/E (Certified Information Privacy Professional/Europe)', 70],
  ['CIPM (Certified Information Privacy Manager)', 70],
  ['ICA International Diploma in Governance, Risk and Compliance', 50],
  ['AWS Certified Solutions Architect - Professional', 75], ['AWS Certified Developer - Associate', 72],
  ['TOGAF 9 Certified', 60], ['EDB PostgreSQL 12+ Professional', 70], ['CompTIA Linux+', 80],
  ['Google Professional Cloud DevOps Engineer', 70],
  ['CISSP (Certified Information Systems Security Professional)', 70],
  ['CEH (Certified Ethical Hacker)', 70], ['ISTQB Advanced Level Test Manager', 65],
  ['CAP (Certified Analytics Professional)', 70], ['CDMP (Certified Data Management Professional)', 60],
  ['Google Professional Data Engineer', 70], ['Microsoft PL-300 Power BI Data Analyst', 70],
  ['CKM (Certified Knowledge Manager)', 70],
  ['MRS Advanced Certificate in Market and Social Research Practice', 50],
  ['CSSBB (Six Sigma Black Belt)', 73], ['PMP (Project Management Professional)', 61],
  ['CPTD (Certified Professional in Talent Development)', 70],
  ['SHRM-SCP (SHRM Senior Certified Professional)', 70], ['SHRM-CP (SHRM Certified Professional)', 70],
];
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const marksValues = MARKS.map(([c, m]) => `(${q(c)}, ${m})`).join(',\n    ');

// an employee whose rank-1 certification already has a bank; everything below is rolled back
const pick = await sql(`
  select rc.agent_key, rc.certification
    from public.role_certification rc
    join public.org_agents a on a.agent_key = rc.agent_key and a.active
   where rc.rank = 1
     and exists (select 1 from public.certification_exam_question q where q.certification = rc.certification)
   order by rc.agent_key
   limit 1`);
if (!pick.length) { console.error('FAIL: no active employee holds a rank-1 certification with a bank'); process.exit(1); }
const { agent_key: AGENT, certification: CERT } = pick[0];
console.log(`${AGENT} / ${CERT}, in aborted transactions`);

const HASHES = `
  select md5(string_agg(t.h, '|' order by t.h)) into %H% from (
    select certification || ':' || md5(string_agg(
             id || E'\\u0001' || coalesce(syllabus_area,'') || E'\\u0001' || question || E'\\u0001' ||
             option_a || E'\\u0001' || option_b || E'\\u0001' || option_c || E'\\u0001' || option_d ||
             E'\\u0001' || correct_option, E'\\u0002' order by id)) as h
      from public.certification_exam_question group by certification) t;
  select md5(string_agg(agent_key || ':' || certification || ':' || pass_mark_pct, '|' order by agent_key, certification))
    into %P% from public.role_certification;
  select md5(string_agg(id || ':' || xmin::text, '|' order by id))
    into %X% from public.certification_exam_question;
`;
const hashes = (h, p, x) => HASHES.replace('%H%', h).replace('%P%', p).replace('%X%', x);

const MARKS_ASSERT = `
  with published(certification, mark) as (values
    ${marksValues}
  )
  select count(*) filter (where pub.mark is not null and rc.pass_mark_pct <> pub.mark),
         count(*) filter (where pub.mark is null)
    into v_bad, v_missing
    from public.role_certification rc left join published pub on pub.certification = rc.certification;
  if v_bad > 0 then
    raise exception 'FAIL % role_certification row(s) carry a pass mark the issuing body does not publish', v_bad;
  end if;
  if v_missing > 0 then
    raise exception 'FAIL % role_certification row(s) name a certification absent from the published list', v_missing;
  end if;
`;

const COMPARE = (what) => `
  if h1 is distinct from h2 then raise exception 'FAIL question bank changed across ${what}: % -> %', h1, h2; end if;
  if p1 is distinct from p2 then raise exception 'FAIL pass marks changed across ${what}: % -> %', p1, p2; end if;
  if x1 is distinct from x2 then raise exception 'FAIL a question row was updated during ${what} (xmin moved): % -> %', x1, x2; end if;
`;

// LEG A — the loop's real write path, over a sitting seeded from the real bank
const legA = `
do $check$
declare
  h1 text; h2 text; p1 text; p2 text; x1 text; x2 text;
  v_bad int; v_missing int; v_area text; v_id bigint; v_ref record; v_rep text := '';
begin
${hashes('h1', 'p1', 'x1')}

  -- the sitting the loop consumes, built from the REAL bank: in the first two syllabus areas the
  -- first question is missed. It never leaves this transaction; it exists so the write path has input.
  insert into public.certification_exam_result
    (agent_key, certification, questions, correct, score_pct, pass_mark_pct, passed, weakest_areas, answers)
  select ${q(AGENT)}, ${q(CERT)}, count(*)::int, count(*) filter (where a.ok)::int,
         round(100.0 * count(*) filter (where a.ok) / count(*), 2),
         (select pass_mark_pct from public.role_certification where agent_key = ${q(AGENT)} and certification = ${q(CERT)}),
         false,
         (select coalesce(jsonb_agg(jsonb_build_object('syllabus_area', z.area, 'asked', z.n, 'correct', z.ok)), '[]'::jsonb)
            from (select a2.area, count(*) n, count(*) filter (where a2.ok) ok
                    from (select coalesce(syllabus_area,'(unstated)') area,
                                 (row_number() over (partition by coalesce(syllabus_area,'(unstated)') order by id) > 1
                                  or dense_rank() over (order by coalesce(syllabus_area,'(unstated)')) > 2) ok
                            from public.certification_exam_question where certification = ${q(CERT)}) a2
                   group by 1) z),
         jsonb_agg(jsonb_build_object('question_id', a.id, 'syllabus_area', a.area,
                                      'chosen', case when a.ok then a.key else null end,
                                      'key', a.key, 'correct', a.ok, 'abstained', not a.ok) order by a.id)
    from (select id, coalesce(syllabus_area,'(unstated)') area, correct_option key,
                 (row_number() over (partition by coalesce(syllabus_area,'(unstated)') order by id) > 1
                                  or dense_rank() over (order by coalesce(syllabus_area,'(unstated)')) > 2) ok
            from public.certification_exam_question where certification = ${q(CERT)}) a;

  select * into v_ref from public.fn_certification_gaps_refresh();
  v_rep := v_rep || format(E'GAPS opened=%s updated=%s closed=%s open_total=%s\\n',
                           v_ref.opened, v_ref.updated, v_ref.closed, v_ref.open_total);
  create temporary table _plan on commit drop as
    select * from public.fn_certification_ingestion_plan();       -- one pass: the search is the cost
  v_rep := v_rep || format(E'PLAN rows=%s with_source=%s without_source=%s\\n',
    (select count(*) from _plan),
    (select count(*) from _plan where source_count > 0),
    (select count(*) from _plan where source_count = 0));

  select syllabus_area into v_area from _plan
   where agent_key = ${q(AGENT)} and source_count > 0 limit 1;
  if v_area is not null then
    v_id := public.fn_certification_gap_ingest(${q(AGENT)}, ${q(CERT)}, v_area);
    v_rep := v_rep || format(E'INGEST %s -> agent_knowledge %s\\n', v_area, v_id);
  else
    v_rep := v_rep || E'INGEST skipped: no open gap of this employee has a corroborated source\\n';
  end if;

${hashes('h2', 'p2', 'x2')}
${COMPARE('the loop write path')}
${MARKS_ASSERT}

  raise exception E'CHECK_REPORT\\n%PASS bank hash % unchanged\\nPASS pass-mark hash % unchanged\\nPASS bank xmin hash % unchanged\\nPASS every pass mark equals the published mark (% rows, % certifications)',
    v_rep, h1, p1, x1,
    (select count(*) from public.role_certification),
    (select count(distinct certification) from public.role_certification);
end $check$;
`;

// LEG B — the same three hashes across a real re-sit
const legB = `
do $check$
declare h1 text; h2 text; p1 text; p2 text; x1 text; x2 text; v_res jsonb;
begin
${hashes('h1', 'p1', 'x1')}
  v_res := public.fn_certification_resit(${q(AGENT)}, ${q(CERT)});
${hashes('h2', 'p2', 'x2')}
${COMPARE('the re-sit')}
  raise exception E'CHECK_REPORT\\nPASS bank, pass-mark and xmin hashes unchanged across the re-sit\\nRESIT %', v_res::text;
end $check$;
`;

const report = (msg) => console.log(msg.slice(msg.indexOf('CHECK_REPORT')).split('CONTEXT')[0].trim());

let legBmeasured = false;
try {
  await sql(legA);
  console.error('FAIL: leg A did not abort — nothing was proved');
  process.exit(1);
} catch (e) {
  const msg = String(e.message || e).replace(/\\n/g, '\n');
  if (!msg.includes('CHECK_REPORT')) { console.error('LEG A ' + msg); process.exit(1); }
  console.log('--- LEG A: the loop write path (rolled back)');
  report(msg);
}

try {
  await sql(legB);
  console.error('FAIL: leg B did not abort — nothing was proved');
  process.exit(1);
} catch (e) {
  const msg = String(e.message || e).replace(/\\n/g, '\n');
  console.log('--- LEG B: a real re-sit');
  if (msg.includes('CHECK_REPORT')) { report(msg); legBmeasured = true; }
  else if (/57014|statement timeout/.test(msg)) {
    console.log('NOT MEASURED: the sitter did not finish inside the management API\'s 120 s statement cap.');
    console.log('This leg proves nothing here; run it from a session without that cap.');
  } else { console.error('LEG B ' + msg); process.exit(1); }
}

console.log(`OK an exam is not edited to be passed — write path asserted, re-sit ${legBmeasured ? 'asserted' : 'not measured'}`);
process.exit(0);
