// RETIRED 9 September 2026 — its subject was deleted on 7 September 2026.
//
// WHAT WAS DROPPED. This check compared the knowledge body against an independently authored
// certification question bank. Every table and routine it names is gone from production
// htdblwldjkcgjvmqkbeh, measured 9 Sep 2026:
//   select to_regclass('public.certification_exam_question')  ->  null
//   select to_regclass('public.certification_knowledge_gap')  ->  null
//   select to_regclass('public.role_certification')           ->  null
//   fn_certification_gap_ingest                               ->  absent from pg_proc
// The only surviving public functions whose name contains 'certification' or 'exam' are
// fn_supplier_certifications, fn_knowledge_exam_summary and fn_exam_revert.
//
// WHY IT IS NOT RE-POINTED AT THE SURVIVING BANK. public.knowledge_exam_questions (1,530 rows) and
// public.knowledge_exam_results (0 rows) did survive, and every knowledge store this check scanned is
// alive (agent_knowledge 2,556 rows, ops_knowledge 9,139, kb_chunks 2,686,026). But the premise of
// this check is that the bank is authored INDEPENDENTLY of the knowledge, so that any overlap is
// leakage. That premise is false for knowledge_exam_questions, measured 9 Sep 2026:
//   * 858 of its 1,530 rows carry a document path as their topic, and 703 carry a reference_answer of
//     exactly 700 characters — a truncated slice of a knowledge document. Question 749's "answer" is
//     the opening 700 characters of an ops_knowledge document
//     (QD_AGENT_KNOWLEDGE_03_MARKETPLACE_CATEGORY_EXPERTS .../01_SPECIALIST_EXPERTISE_V2.md).
//   * probing the surviving bank exactly as this file probes — 40 characters of the question or of the
//     model answer, against every knowledge row written since the bank was born — already returns
//     hits: 25 distinct questions match kb_chunks content verbatim, with reference answers ranging
//     from 43 to 700 characters. The oldest-first created_at window this file relies on to separate
//     "written after the bank" from "written before it" buys nothing here either: the surviving bank
//     was born 2026-07-26, so 2,684,295 of the 2,686,026 kb_chunks rows fall inside the window.
// A re-pointed check would therefore be red on the day it was written, and red for the machine
// working as designed rather than for the defect it names. Tuning the probe until it passed is the
// one thing the founder forbids outright.
//
// AND THE LEAK IT WOULD HAVE FOUND IS ALREADY ADJUDICATED. The older knowledge_exam loop did write
// reference answers into agent_knowledge. That was measured on 7 Sep 2026 (557 rows across 110 agent
// keys, 3,046 content matches against knowledge_exam_questions) and settled by
// scripts/sql/knowledge_written_from_an_exams_own_answer_is_marked_unsourced.sql, which is applied on
// production: those 557 rows stand today at 397 'quarantined' and 160 'unsourced'.
//
// RECOMMENDATION, DELIBERATELY NOT BUILT HERE. The property is still worth guarding over the loop the
// founder kept, but in a form that fits it: no agent_knowledge row written by the knowledge_exam loop
// may carry its own question's reference answer, and no row already marked 'unsourced' may be
// re-promoted to 'author_verified'. That is a new check against a surviving machine, so building it
// is the founder's call, not this session's.
//
// The original file follows, unchanged.
//
// AN EXAM ANSWER NEVER BECOMES KNOWLEDGE.
//
// The founder asked the only question that matters about a certification exam whose failures drive an
// ingestion plan: "so the knowledge missing is just the correct answers?" If the loop were ever allowed
// to answer yes, every employee would pass and none of them would know anything, and the company would
// have manufactured its own evidence — the thing the standing rules forbid above all others.
//
// The rule this file enforces: the exam's questions, its options, its keys and its rationales are
// EVIDENCE ABOUT the employees, never MATERIAL FOR them. Nothing an employee can read may be derived
// from the bank. What a failure licenses is the professional material behind the syllabus area — the
// revenue standard, the audit sampling method, the sanctions list — which the company either already
// holds or must obtain, and which exists independently of any exam.
//
// It asserts four things against production:
//   1. no knowledge row an employee can read is text from the bank (question, option or rationale);
//   2. fn_certification_gap_ingest's own definition never reads certification_exam_question — an
//      ingester that can see the bank can leak it, however carefully it is written today;
//   3. no knowledge row cites a certification_exam_question id as its provenance;
//   4. every gap the loop records names a syllabus AREA, not a question.
//
//   node --test scripts/checks/an_exam_answer_never_becomes_knowledge.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const REF = 'htdblwldjkcgjvmqkbeh';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const token = () => (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();

const sql = async (query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await r.text();
  assert.ok(r.ok, `the management query failed (${r.status}): ${body.slice(0, 400)}`);
  return JSON.parse(body);
};

// A question stem is long and distinctive; forty characters of one appearing verbatim inside a
// knowledge record is not a coincidence, and a shorter probe would fire on ordinary shared phrasing.
test('no knowledge an employee reads is text from the question bank', { skip: SKIP }, async () => {
  // Only a record written AFTER the bank existed could carry its words, and that is also the only
  // window the ingestion loop writes in. The comparison itself runs HERE, not in SQL: 2,080 probes
  // against every knowledge row is a cross join the database cancelled at 120 s twice, while the same
  // work in memory is two small reads and a substring scan.
  const [probes, cands] = await Promise.all([
    sql(`select id, left(question, 40) as stem, left(rationale, 40) as why
           from public.certification_exam_question
          where length(question) >= 40 and length(rationale) >= 40`),
    sql(`with born as (select min(created_at) as t from public.certification_exam_question)
         select 'agent_knowledge' as store, k.id::text as row_id, k.content
           from public.agent_knowledge k, born b where k.updated_at >= b.t
         union all
         select 'ops_knowledge', o.record_id, o.content
           from public.ops_knowledge o, born b where o.effective_date >= b.t::date
         union all
         select 'kb_chunks', c.id::text, c.content
           from public.kb_chunks c, born b where c.created_at >= b.t`),
  ]);
  const rows = [];
  for (const c of cands) {
    const text = c.content || '';
    for (const p of probes) {
      if (text.includes(p.stem) || text.includes(p.why)) {
        rows.push({ store: c.store, row_id: c.row_id, question_id: p.id });
        break;
      }
    }
    if (rows.length >= 20) break;
  }
  console.log(`scanned ${cands.length} knowledge row(s) written since the bank against ${probes.length} question(s)`);
  assert.deepEqual(rows, [],
    'a knowledge record carries the exam\'s own words: the loop is teaching the test, which makes every '
    + 'score meaningless. Remove the record and ingest the professional material for the syllabus area instead.');
});

test('the ingester cannot see the question bank', { skip: SKIP }, async () => {
  const [fn] = await sql(`
    select coalesce(pg_get_functiondef(p.oid), '') as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'fn_certification_gap_ingest'`);
  assert.ok(fn && fn.def, 'fn_certification_gap_ingest does not exist on production');
  assert.doesNotMatch(fn.def, /certification_exam_question/,
    'the ingester reads the question bank. It must draw only on the estate\'s own material for the '
    + 'failed syllabus area; an ingester that can see the bank can copy it.');
});

test('no knowledge cites a question as its source', { skip: SKIP }, async () => {
  const rows = await sql(`
    select k.id::text as row_id, k.agent_key
      from public.agent_knowledge k
     where k.content ~* 'certification_exam_question|exam question #|answer key'
     limit 20`);
  assert.deepEqual(rows, [],
    'a knowledge record names the exam as its provenance; knowledge must come from the subject, not the test');
});

test('a recorded gap names a syllabus area, never a question', { skip: SKIP }, async () => {
  const [cols] = await sql(`
    select coalesce(string_agg(column_name, ','), '(table absent)') as c
      from information_schema.columns
     where table_schema = 'public' and table_name = 'certification_knowledge_gap'`);
  if (cols.c === '(table absent)') return;    // the loop is not built yet; nothing to assert
  assert.match(cols.c, /syllabus_area/, 'certification_knowledge_gap does not record a syllabus area');
  const [bad] = await sql(`
    select count(*)::int as n from public.certification_knowledge_gap
     where coalesce(syllabus_area, '') = ''`);
  assert.equal(bad.n, 0, 'a gap row carries no syllabus area, so nothing tells the company what to teach');
});
