// EVERY POSITION HOLDS CERTIFICATIONS, EVERY CERTIFICATION HAS A REAL BANK, AND THE SITTER IS
// DETERMINISTIC.
//
// The founder, 6 Sep 2026: "create a list of the top certificates for every position we have in the
// company and then test all agents. if they dont pass them all, then their knowledge is simply not
// enough."
//
// Read that sentence carefully: the FAILING EXAM IS THE FINDING, not the defect. So this check draws
// the line between the machinery and the result.
//
//   ASSERTED (the machinery must be sound):
//     1. every active employee in org_agents has at least one role_certification row;
//     2. every certification named in role_certification has a bank of >= 40 questions — the length
//        the real bodies publish; a shorter bank is a shorter exam and would flatter every score;
//     3. every question has exactly one key and four distinct, non-empty options;
//     4. the sitter is deterministic — one employee is sat TWICE inside a transaction that is then
//        aborted, and the two answer sets must be identical, question by question. An exam whose
//        answers move between sittings measures the roll of a die, not the knowledge.
//
//   REPORTED, NEVER ASSERTED (the result belongs to the founder, not to the gate):
//     5. the current pass/fail table per employee.
//
// Why 5 is not an assertion, in both directions:
//   * this check MUST NOT go green by lowering the bar. The pass marks are the bodies' own
//     (CPA 75, PMP 61, CISSP 70 …) and live in role_certification; nothing here relaxes them, and
//     nothing here re-scores a failure as a pass.
//   * this check MUST NOT go red because an employee's knowledge is simply not there yet. That is
//     precisely the founder's finding — the answer to it is more knowledge in ops_knowledge, not a
//     red build. A red here would mean the mapping, the banks or the sitter is broken.
//
//   node --test scripts/checks/every_position_sits_its_certifications.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sql } from '../lib/db.mjs';

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

test('every active employee holds at least one certification', { skip: SKIP }, async () => {
  const missing = await sql(`
    select a.agent_key, a.department from public.org_agents a
     where a.active and not exists (select 1 from public.role_certification rc where rc.agent_key = a.agent_key)
     order by 1`);
  assert.equal(missing.length, 0,
    `employees with no certification: ${missing.map(m => m.agent_key).join(', ')}`);
  const [n] = await sql(`select count(*)::int rows, count(distinct agent_key)::int agents,
                                count(distinct certification)::int certs from public.role_certification`);
  console.log(`  role_certification: ${n.rows} rows, ${n.agents} employees, ${n.certs} certifications`);
});

test('every certification named in role_certification has a bank of >= 40 questions', { skip: SKIP }, async () => {
  const short = await sql(`
    select rc.certification,
           (select count(*)::int from public.certification_exam_question q
             where q.certification = rc.certification) as questions
      from (select distinct certification from public.role_certification) rc
     where (select count(*) from public.certification_exam_question q
             where q.certification = rc.certification) < 40
     order by 2, 1`);
  assert.equal(short.length, 0,
    `certifications with fewer than 40 questions:\n` +
    short.map(s => `    ${s.questions.toString().padStart(3)}  ${s.certification}`).join('\n'));
});

test('every question has one key and four distinct non-empty options', { skip: SKIP }, async () => {
  const bad = await sql(`
    select id, certification, 'bad key or option' as why
      from public.certification_exam_question
     where correct_option not in ('A','B','C','D')
        or coalesce(btrim(option_a),'') = '' or coalesce(btrim(option_b),'') = ''
        or coalesce(btrim(option_c),'') = '' or coalesce(btrim(option_d),'') = ''
        or coalesce(btrim(question),'') = ''
        or cardinality(array(select distinct unnest(array[btrim(option_a),btrim(option_b),btrim(option_c),btrim(option_d)]))) <> 4
     order by id limit 25`);
  assert.equal(bad.length, 0, `malformed questions: ${JSON.stringify(bad)}`);
});

test('the sitter is deterministic: two sittings inside an aborted transaction agree', { skip: SKIP }, async () => {
  const [pair] = await sql(`
    select rc.agent_key, rc.certification from public.role_certification rc
     where (select count(*) from public.certification_exam_question q
             where q.certification = rc.certification) >= 40
     order by rc.agent_key, rc.certification limit 1`);
  if (!pair) {
    console.log('  SKIPPED — no certification has a bank of 40 questions yet, so nothing can be sat.');
    return;
  }
  // The two sittings and their comparison happen inside a DO block that always raises, so the two
  // certification_exam_result rows they write are rolled back: measuring the company must not also
  // change it.
  const probe = `do $$
    declare r1 public.certification_exam_result; r2 public.certification_exam_result;
    begin
      r1 := public.fn_certification_exam_sit(${lit(pair.agent_key)}, ${lit(pair.certification)});
      r2 := public.fn_certification_exam_sit(${lit(pair.agent_key)}, ${lit(pair.certification)});
      raise exception 'DETERMINISM identical=% questions=% correct=% score=% pass_mark=% passed=%',
        (r1.answers = r2.answers), r1.questions, r1.correct, r1.score_pct, r1.pass_mark_pct, r1.passed;
    end $$;`;
  let message = '';
  try { await sql(probe); } catch (e) { message = String(e.message || e); }
  assert.match(message, /DETERMINISM identical=t /,
    `two sittings of ${pair.agent_key} / ${pair.certification} disagreed: ${message}`);
  console.log('  ' + (message.match(/DETERMINISM [^\\]*/) || [''])[0].trim());
});

test('REPORT ONLY: the pass/fail table the founder asked for', { skip: SKIP }, async () => {
  const rows = await sql(`
    select agent_key, department, assigned, sat, passed, failed,
           coalesce(array_to_string(worst_areas, ' | '), '') as worst
      from public.fn_certification_exam_summary()`);
  const sat = rows.reduce((a, r) => a + Number(r.sat), 0);
  const passed = rows.reduce((a, r) => a + Number(r.passed), 0);
  console.log(`  employees ${rows.length} · certifications assigned ` +
    `${rows.reduce((a, r) => a + Number(r.assigned), 0)} · sittings ${sat} · passed ${passed} · failed ${sat - passed}`);
  for (const r of rows) {
    console.log(`  ${r.department.padEnd(20)} ${r.agent_key.padEnd(26)} assigned ${r.assigned} ` +
      `sat ${r.sat} passed ${r.passed} failed ${r.failed}${r.worst ? '  weakest: ' + r.worst : ''}`);
  }
  if (sat === 0) console.log('  (no sittings on record yet — the banks are still being authored)');
  // Deliberately no assertion. See the header.
});

function lit(s) { return `'${String(s).replace(/'/g, "''")}'`; }
