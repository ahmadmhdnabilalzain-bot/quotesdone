// THE APPROVAL PATH — 129 advisory tasks had no way to reach 'done', and now they do.
//
// The checks that matter here are the NEGATIVE ones. "Tasks got promoted" is trivially satisfied by
// a function that promotes everything, and that function would auto-clear supplier approvals, legal
// reviews and production incident fixes. So this gate spends most of its assertions proving what
// does NOT move, and proving that each refusal names its own cause.
//
//   node scripts/archive/staging/verify_approval_path.mjs        # zero spend, cleans up after itself
import { mgmtRead, mgmtWrite } from '../../lib/qd_guard.mjs';
import { REF as STAGE } from '../../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(58)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const TAG = 'qd_fixture_approval_path';

// Each case is (dept, class, stored tier, needs_founder, expected verdict, why we expect it).
const CASES = [
  ['procurement', 'knowledge_acquire',      'advisory',   false, 'approve', 'advisory grant, no gate'],
  ['exec',        'recommend',              'advisory',   false, 'approve', 'advisory grant, no gate'],
  ['procurement', 'supplier_approve_clean', 'autonomous', false, 'hold',    'outside AUTONOMOUS_CEILING'],
  ['legal',       'legal_review',           'gated',      true,  'hold',    'hard gate legal_commitment'],
  ['it',          'incident_fix',           'advisory',   false, 'hold',    'hard gate production_deploy'],
  ['evolution',   'recommend',              'advisory',   false, 'hold',    'no org_authority row'],
  ['sales',       'outreach_draft',         'gated',      true,  'hold',    'needs_founder tightens'],
];

async function cleanup() {
  await mgmtWrite(STAGE, `delete from public.review_chain where subject_type='org_task'
     and subject_id in (select id::text from public.org_tasks where detail = '${TAG}')`, 'cleanup rc');
  await mgmtWrite(STAGE, `delete from public.org_tasks where detail = '${TAG}'`, 'cleanup tasks');
}

try {
  await cleanup();
  const pre = Number(one(await mgmtRead(STAGE, `select count(*) from public.org_tasks`)));

  const values = CASES.map(([d, c, t, nf]) =>
    `('${d}','${c}','${t}',${nf},'proposed','${TAG}','fixture: ${d}/${c}')`).join(',');
  await mgmtWrite(STAGE,
    `insert into public.org_tasks (dept_key, action_class, tier, needs_founder, status, detail, title)
     values ${values}`, 'fixture');

  const ids = await mgmtRead(STAGE,
    `select id, dept_key, action_class, tier, needs_founder from public.org_tasks
      where detail='${TAG}' order by id`);
  step('the fixture loaded', ids.length === CASES.length, `${ids.length} of ${CASES.length} task(s) at status=proposed`);

  // ---- 1. DRY RUN MOVES NOTHING -----------------------------------------------------------------
  const dry = one(await mgmtRead(STAGE, `select public.fn_task_approve(true)`));
  const dryObj = typeof dry === 'string' ? JSON.parse(dry) : (dry || {});
  const stillProposed = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.org_tasks where detail='${TAG}' and status='proposed'`)));
  step('a dry run changes nothing', stillProposed === CASES.length,
    `${stillProposed}/${CASES.length} still proposed; dry run reported ${dryObj.approved} approve / ${dryObj.held_for_founder} hold`);
  const dryRc = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.review_chain where subject_type='org_task' and stage='approval'`)));
  step('a dry run writes no audit rows either', dryRc === 0, `${dryRc} review_chain approval row(s)`);

  // ---- 2. THE LIVE RUN, PER CASE ----------------------------------------------------------------
  await mgmtRead(STAGE, `select 1`); // no-op: keep the read/write alternation explicit
  await mgmtWrite(STAGE, `select public.fn_task_approve(false)`, 'live run');

  const after = await mgmtRead(STAGE,
    `select t.id, t.dept_key, t.action_class, t.status, t.tier, t.needs_founder,
            rc.decision, rc.reason
       from public.org_tasks t
       left join public.review_chain rc
         on rc.subject_type='org_task' and rc.subject_id = t.id::text and rc.stage='approval'
      where t.detail='${TAG}' order by t.id`);

  let wrong = [];
  after.forEach((row, i) => {
    const [dept, cls, , , expect] = CASES[i];
    const got = row.status === 'assigned' ? 'approve' : 'hold';
    if (got !== expect || row.decision !== expect) wrong.push(`${dept}/${cls} expected ${expect} got ${got}/${row.decision}`);
  });
  step('every case landed on its expected verdict', wrong.length === 0,
    wrong.length ? wrong.join(' | ') : `${after.length}/${after.length} correct`);

  // THE ONE THAT MATTERS. A function that promotes everything passes every positive check above.
  const dangerous = after.filter(r =>
    ['supplier_approve_clean', 'legal_review', 'incident_fix', 'outreach_draft'].includes(r.action_class));
  step('nothing the authority model gates was promoted',
    dangerous.every(r => r.status === 'proposed'),
    `${dangerous.filter(r => r.status === 'proposed').length}/${dangerous.length} held: ` +
    dangerous.map(r => `${r.dept_key}/${r.action_class}=${r.status}`).join(', '));

  // ---- 3. EVERY DISPOSITION CARRIES A REASON ----------------------------------------------------
  const noReason = after.filter(r => !r.reason || r.reason.trim().length < 40);
  step('every disposition records a reason', noReason.length === 0,
    noReason.length ? `${noReason.length} row(s) with no usable reason` : `${after.length}/${after.length} carry one`);

  // The three hold causes are genuinely different problems and must not collapse into one sentence:
  // a hard gate is permanent, a missing org_authority row is a config gap someone should close, and
  // a ceiling clamp is a deliberate refusal to widen autonomy from a file.
  const holds = after.filter(r => r.decision === 'hold');
  const causes = {
    hard_gate: holds.some(r => /hard gate/i.test(r.reason || '')),
    no_row: holds.some(r => /no org_authority row/i.test(r.reason || '')),
    ceiling: holds.some(r => /AUTONOMOUS_CEILING/.test(r.reason || '')),
    needs_founder: holds.some(r => /needs_founder can only tighten/i.test(r.reason || '')),
  };
  step('each hold names its actual cause, not a generic one',
    Object.values(causes).every(Boolean),
    Object.entries(causes).map(([k, v]) => `${k}=${v ? 'yes' : 'NO'}`).join(' '));

  // ---- 4. THE PROMOTED TIER IS THE MODEL'S, NOT THE STORED ONE ----------------------------------
  const tierOk = await mgmtRead(STAGE,
    `select count(*) n from public.org_tasks t
      where t.detail='${TAG}' and t.status='assigned'
        and t.tier is distinct from coalesce(nullif(public.fn_dept_authority(t.dept_key,t.action_class)->>'tier',''),'gated')`);
  step('a promoted task carries the tier the model resolved', Number(tierOk[0].n) === 0,
    `${tierOk[0].n} promoted task(s) disagree with fn_dept_authority`);

  // ---- 5. IDEMPOTENCE — an hourly cron must not restate the same verdict 24 times a day ----------
  const rcBefore = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.review_chain where subject_type='org_task' and stage='approval'`)));
  await mgmtWrite(STAGE, `select public.fn_task_approve(false)`, 'second run');
  const rcAfter = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.review_chain where subject_type='org_task' and stage='approval'`)));
  step('a second run adds no duplicate audit rows', rcBefore === rcAfter,
    `${rcBefore} → ${rcAfter} approval row(s)`);

  const movedAgain = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.org_tasks where detail='${TAG}' and status='assigned'`)));
  step('a second run promotes nothing further',
    movedAgain === after.filter(r => r.status === 'assigned').length,
    `${movedAgain} assigned, unchanged`);

  // ---- 6. NO COLLATERAL DAMAGE ------------------------------------------------------------------
  const post = Number(one(await mgmtRead(STAGE, `select count(*) from public.org_tasks`)));
  step('no task outside the fixture was touched', post === pre + CASES.length,
    `org_tasks ${pre} → ${post} (fixture ${CASES.length})`);

  await cleanup();
  const left = Number(one(await mgmtRead(STAGE, `select count(*) from public.org_tasks where detail='${TAG}'`)));
  step('the fixture cleaned up after itself', left === 0 && Number(one(await mgmtRead(STAGE, `select count(*) from public.org_tasks`))) === pre,
    `${left} fixture row(s) left behind`);
} catch (e) {
  step('the gate ran to completion', false, String(e.message || e).slice(0, 200));
  await cleanup().catch(() => {});
}

const pass = checks.filter(c => c.ok).length;
console.log(`\nAPPROVAL PATH ${pass}/${checks.length} on ${STAGE} (zero spend)`);
process.exit(pass === checks.length ? 0 : 1);
