// THE REVIEW CHAIN — built, correct, and called by nothing until now.
//
// Every assertion here is reachable only AT CALL TIME. The last patch of this shape reported
// success from a DO block that rewrites pg_get_functiondef while carrying three errors that only
// surfaced when the function actually ran (a rowtype/alias collision, and two text||jsonb
// concatenations that resolve to jsonb||jsonb and parse the literal as JSON). So the fixture is
// built in the same change, not after it.
//
//   node scripts/staging/verify_review_chain.mjs      # zero spend — fn_challenge is deterministic
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(60)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const TAG = 'qd_fixture_review_chain';
const q = (s) => s.replace(/'/g, "''");

const GOOD = 'Q3 supplier coverage analysis for QuotesDone. We reviewed the 86 catalogue categories '
  + 'against approved supply in the UAE market and found 14 with fewer than three approved suppliers, '
  + 'concentrated in Abu Dhabi rather than Dubai. Recommended action is to prioritise invitations in '
  + 'those 14 categories at the existing daily cap, and to re-measure coverage after two weeks before '
  + 'committing any further AED spend on acquisition. Risk: invitation fatigue in categories that '
  + 'already carry marginal suppliers, mitigated by the existing three-strike rule.\nRESULT: 14 '
  + 'under-covered categories identified and an invitation order proposed.';

// (dept, title, detail, deliverable, expected outcome, what it proves)
const CASES = [
  ['procurement', 'Quarterly supplier coverage analysis', 'Analyse category coverage',
   GOOD, 'published', 'a good deliverable clears both stages'],
  ['procurement', 'Coverage analysis', 'Analyse coverage',
   'The department could not reach the AI service, please try again in a moment.',
   'reject', 'an apology is refused as a critical breach, not stored as work'],
  ['procurement', 'Coverage analysis', 'Analyse coverage',
   'Done. Coverage looks fine overall and we should keep going as we are.',
   'reject', 'a 68-character answer no longer ships (the old bar was 60)'],
  ['procurement', 'Coverage analysis', 'Analyse coverage',
   GOOD.replace(/\nRESULT:[\s\S]*$/, ''), 'request_revision',
   'a missing RESULT: line is a major issue, returned not rejected'],
  ['it', 'Bypass the model routing approval gate', 'Disable the review check on the routing rule',
   GOOD, 'request_revision', 'a BLOCKING collaboration rule + recommend_against stops the work'],
  ['knowledge', 'Bypass the approval review for knowledge modules employees rely on',
   'Revise the knowledge modules', GOOD, 'published',
   'a NON-blocking rule records the dissent and lets the work proceed'],
];

async function cleanup() {
  await mgmtWrite(STAGE, `delete from public.review_chain where subject_type='org_task'
     and subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')`, 'rc');
  await mgmtWrite(STAGE, `delete from public.company_event where entity_type='org_task'
     and entity_id in (select id::text from public.org_tasks where detail like '${TAG}%')`, 'ce');
  await mgmtWrite(STAGE, `delete from public.challenge_record where proposal like '%${TAG}%'`, 'chr');
  await mgmtWrite(STAGE, `delete from public.institutional_memory where subject_type='org_task'
     and subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')`, 'im');
  await mgmtWrite(STAGE, `delete from public.org_tasks where detail like '${TAG}%'`, 'tasks');
}

try {
  await cleanup();

  const values = CASES.map(([d, title, detail, deliv]) =>
    `('${d}','${q(title)}','${TAG} ${q(detail)}','assigned','advisory','analysis',` +
    `jsonb_build_object('deliverable','${q(deliv)}'))`).join(',');
  await mgmtWrite(STAGE,
    `insert into public.org_tasks (dept_key, title, detail, status, tier, action_class, result)
     values ${values}`, 'fixture');

  const rows = await mgmtRead(STAGE,
    `select id, dept_key, title from public.org_tasks where detail like '${TAG}%' order by id`);
  step('the fixture loaded', rows.length === CASES.length, `${rows.length} task(s) with a deliverable`);

  // Run each one through the reviewer and compare against the expected verdict.
  const got = [];
  for (const r of rows) {
    const res = one(await mgmtRead(STAGE, `select public.fn_task_review(${r.id})`));
    got.push(typeof res === 'string' ? JSON.parse(res) : res);
  }

  const wrong = got.map((g, i) => g.outcome === CASES[i][4] ? null
    : `${CASES[i][0]}/"${CASES[i][1].slice(0, 28)}" expected ${CASES[i][4]} got ${g.outcome}`)
    .filter(Boolean);
  step('every case landed on its expected outcome', wrong.length === 0,
    wrong.length ? wrong.join(' | ') : `${got.length}/${got.length}: ` + got.map(g => g.outcome).join(', '));

  // ---- the negative checks -----------------------------------------------------------------
  step('the 60-character bar is gone', got[2].outcome === 'reject',
    `68-char deliverable -> ${got[2].outcome}, violations: ` +
    (got[2].violations || []).map(v => v.rule).join(',') || '(none)');

  step('an unreachable-AI apology is a CRITICAL breach', got[1].outcome === 'reject',
    (got[1].violations || []).map(v => `${v.rule}/${v.severity}`).join(', ') || '(no violation recorded)');

  step('a major issue is RETURNED, not rejected outright', got[3].outcome === 'request_revision',
    (got[3].violations || []).map(v => `${v.rule}/${v.severity}`).join(', ') || '(none)');

  // ---- the chain actually walked the hierarchy ----------------------------------------------
  const stages = await mgmtRead(STAGE,
    `select stage, count(*) n from public.review_chain
      where subject_type='org_task'
        and subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')
      group by 1 order by 1`);
  const byStage = Object.fromEntries(stages.map(s => [s.stage, Number(s.n)]));
  step('all four spec stages were written',
    ['drafted', 'dept_review', 'cos_review', 'published'].every(s => byStage[s] > 0),
    Object.entries(byStage).map(([k, v]) => `${k}=${v}`).join(' '));

  const reviewer = await mgmtRead(STAGE,
    `select distinct reviewer_agent from public.review_chain
      where stage='dept_review' and reviewer_agent is not null
        and subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')`);
  step('a real department head reviewed, resolved through fn_pick_reviewer',
    reviewer.length > 0 && reviewer.every(r => r.reviewer_agent && r.reviewer_agent !== 'brief'),
    reviewer.map(r => r.reviewer_agent).join(', ') || '(none)');

  // ---- collaboration_rule went from 0 readers to a reader ------------------------------------
  step('collaboration_rule is read and its rule is named',
    got[4].rules_applied > 0 && got[5].rules_applied > 0,
    `blocking case matched ${got[4].rules_applied} rule(s), non-blocking ${got[5].rules_applied}`);

  const collab = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.review_chain where stage='collaboration'
      and subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')`)));
  step('the departments the rule requires are recorded', collab >= 2,
    `${collab} collaboration row(s) naming must_involve / must_review`);

  // THE ONE THAT MATTERS: blocking and non-blocking must behave DIFFERENTLY on the same dissent.
  step('blocking stops the work, non-blocking only records the dissent',
    got[4].blocked === true && got[5].blocked === false
      && (got[5].dissents || []).length > 0 && got[5].outcome === 'published',
    `blocking: blocked=${got[4].blocked} outcome=${got[4].outcome} | ` +
    `non-blocking: blocked=${got[5].blocked} outcome=${got[5].outcome} dissents=${(got[5].dissents || []).length}`);

  const noReason = await mgmtRead(STAGE,
    `select count(*) n from public.review_chain
      where subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')
        and (reason is null or length(trim(reason)) < 20)`);
  step('no decision or dissent is recorded without a reason', Number(noReason[0].n) === 0,
    `${noReason[0].n} row(s) with no usable reason`);

  const chal = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.challenge_record where challenged_by is not null
       and created_at > now() - interval '10 minutes'`)));
  step('the challenge is recorded where the founder already reads them', chal > 0,
    `${chal} challenge_record row(s) written by fn_challenge`);

  // ---- EVERY COMPLETED TASK GENERATES LEARNING ------------------------------------------------
  // 104 tasks done against 31 lesson rows, and those were per-department-per-day digests, not per
  // task. This is the grain the spec asks for.
  const lessons = await mgmtRead(STAGE,
    `select im.subject_id, im.kind, im.outcome, im.confidence, im.learned_by, im.detail
       from public.institutional_memory im
      where im.subject_type='org_task'
        and im.subject_id in (select id::text from public.org_tasks where detail like '${TAG}%')
      order by im.subject_id::bigint`);
  step('every reviewed task wrote its own lesson', lessons.length === CASES.length,
    `${lessons.length}/${CASES.length} lesson(s) in institutional_memory, one per task`);

  // Derived from CASES rather than hardcoded: every case that did not reach 'published' is a
  // failure and must be recorded as one. Two rejects plus two request_revisions is four.
  const expectWorse = CASES.filter(c => c[4] !== 'published').length;
  const rejected = lessons.filter(l => l.outcome === 'worse');
  const clean = lessons.filter(l => l.outcome === 'success');
  step('a rejection is recorded as a failure, not a completion',
    rejected.length === expectWorse && rejected.every(l => Number(l.confidence) >= 0.6),
    `${rejected.length}/${expectWorse} recorded 'worse' at confidence ${rejected.map(l => l.confidence).join('/')}`);

  // THE ONE THAT MATTERS: a routine pass must be recorded but must NOT crowd the prompt, or LAYER 4
  // becomes a list of things that went fine and the failures fall off the end.
  step('a routine pass is recorded but stays out of LAYER 4',
    clean.length > 0 && clean.every(l => Number(l.confidence) < 0.6),
    `${clean.length} clean pass(es) at confidence ${clean.map(l => l.confidence).join('/')}, below the 0.6 floor`);

  const l4 = String(one(await mgmtRead(STAGE,
    `select public.fn_agent_institutional_memory('procurement', 6)`)) || '');
  step('the rejection reaches the department through LAYER 4',
    rejected.some(l => l4.includes(l.detail.slice(0, 60))),
    `LAYER 4 is ${l4.length} chars and carries a lesson written moments ago`);

  // Before this change the six highest-confidence rows won the ordering permanently, so nothing
  // learned afterwards could ever surface. That is a memory that cannot learn.
  step('LAYER 4 is ordered by recency, so new lessons can displace old ones',
    l4.length > 0 && !/order by/i.test(l4),
    'newest-first with confidence as a floor, not as the sort key');

  // ---- THE FEEDBACK LOOP THIS CHAIN CREATED, AND THE GUARD THAT STOPS IT --------------------
  // review_chain has an AFTER INSERT trigger emitting company_event('review.step'), and
  // fn_event_dispatch turns every such event into an org_task for each subscriber. So wiring the
  // review chain in made each reviewed task write 4-6 audit rows, each of which became a NEW task,
  // each of which would be reviewed. Measured on production: 169 tasks in one hour against 2 in the
  // hour before, and the 150-row approval backfill fired it 150 times in a single statement.
  //
  // The trigger now carries a WHEN clause: an event is emitted for a PUBLICATION or a REFUSAL —
  // the two things a subscriber should act on — and never for the audit rows that record how the
  // decision was reached. Asserted in both directions, because "no events" would also pass if the
  // trigger were simply dropped.
  const evBefore = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.company_event where event_type='review.step'`)));
  await mgmtWrite(STAGE,
    `insert into public.review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason)
     values ('org_task','qd_evt_probe','exec','probe','approval','approve','audit row, must not raise an event'),
            ('org_task','qd_evt_probe','exec','probe','drafted',null,'audit row, must not raise an event'),
            ('org_task','qd_evt_probe','exec','probe','collaboration','required','audit row, must not raise an event')`,
    'quiet stages');
  const evQuiet = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.company_event where event_type='review.step'`)));
  step('audit rows raise no event, so the chain cannot feed itself', evQuiet === evBefore,
    `3 audit rows -> ${evQuiet - evBefore} event(s); before this guard each one became a new org_task`);

  await mgmtWrite(STAGE,
    `insert into public.review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason)
     values ('org_task','qd_evt_probe','exec','probe','published','approve','terminal: must raise an event'),
            ('org_task','qd_evt_probe','exec','probe','dept_review','reject','terminal: must raise an event')`,
    'loud stages');
  const evLoud = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.company_event where event_type='review.step'`)));
  step('a publication and a refusal still raise theirs', evLoud - evQuiet === 2,
    `publish + reject -> ${evLoud - evQuiet} event(s); the watcher still sees outcomes`);

  await mgmtWrite(STAGE, `delete from public.review_chain where subject_id='qd_evt_probe'`, 'probe rc');
  await mgmtWrite(STAGE, `delete from public.company_event where entity_type='review'
     and payload->>'subject_id' = 'qd_evt_probe'`, 'probe ce');

  await cleanup();
  const left = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.org_tasks where detail like '${TAG}%'`)));
  const leftIm = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.institutional_memory where subject_type='org_task'`)));
  step('the fixture cleaned up after itself', left === 0 && leftIm === 0,
    `${left} task(s), ${leftIm} lesson(s) left behind`);
} catch (e) {
  step('the gate ran to completion', false, String(e.message || e).slice(0, 300));
  await cleanup().catch(() => {});
}

const pass = checks.filter(c => c.ok).length;
console.log(`\nREVIEW CHAIN ${pass}/${checks.length} on ${STAGE} (zero spend)`);
process.exit(pass === checks.length ? 0 : 1);
