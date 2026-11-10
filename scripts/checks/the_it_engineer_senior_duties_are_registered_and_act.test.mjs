// The five IT senior contributions of ledger 1003 stage 2 (IT-C02 C06 C13 C15 C16) are seat_duties that ACT.
// Seat: it_engineer. 19 Oct 2026: latency (10) and model-spend (41) findings had no deadline and nothing acted when
// they outlived one; the 15 perimeter checks recorded no last success; nothing audited .github/workflows; no load
// test or ceiling existed. This reads the NEWEST definition of each routine (MANIFEST order, then files pending apply)
// and fails if a duty is unregistered or its routine stops writing what makes it act. It also runs the workflow audit
// on planted workflows.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { auditWorkflow, auditDir } from '../it/workflow_audit.mjs';

const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
const pending = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt') && !f.endsWith('_probe.txt'))
  .map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
const files = [...manifest, ...pending].filter(existsSync);
const all = files.map((f) => readFileSync(f, 'utf8')).join('\n');

function newest(fn) {
  const def = new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${fn}\s*\(`, 'i');
  const file = files.filter((f) => def.test(readFileSync(f, 'utf8'))).pop();
  assert.ok(file, `no file defines ${fn}`);
  return { file, body: readFileSync(file, 'utf8').split(def).pop().split(/\$(?:function|fn)\$;/)[0] };
}

// contribution -> [duty, routine, what the routine must write for the duty to act]
const DUTIES = {
  'IT-C02': ['it_engineer.latency_closure', 'fn_it_engineer_latency_closure', /fn_it_engineer_finding_closure\('latency_slo'/],
  'IT-C06': ['it_engineer.model_spend_closure', 'fn_it_engineer_model_spend_closure', /fn_it_engineer_finding_closure\('model_spend'[\s\S]*'cost_watch'/],
  'IT-C13': ['it_engineer.perimeter_freshness', 'fn_it_engineer_perimeter_freshness', /last_ok_at[\s\S]*fn_it_duty_settle\('perimeter_freshness'/],
  'IT-C15': ['it_engineer.advisory_triage', 'fn_it_engineer_advisory_triage', /workflow_audit[\s\S]*security_advisor_baseline[\s\S]*fn_it_duty_settle\('advisory_triage'/],
  'IT-C16': ['it_engineer.load_test', 'fn_it_engineer_load_test', /fn_inquiry_is_demo[\s\S]*fn_quote_is_demo[\s\S]*errcode = 'QDLT0'[\s\S]*insert into public\.it_load_test_run[\s\S]*fn_it_duty_settle\('load_test'/],
};

for (const [c, [duty, fn, acts]] of Object.entries(DUTIES)) {
  test(`${c}: ${duty} is registered on ${fn} and acts`, () => {
    const reg = new RegExp(String.raw`\('${duty.replace('.', '\\.')}',\s*'it_engineer',\s*interval '[^']+',\s*'${fn}'`);
    assert.match(all, reg, `${duty} is not registered as an it_engineer seat_duty running ${fn}`);
    const { file, body } = newest(fn);
    assert.match(body, acts, `${file}: ${fn} no longer writes what makes ${c} act`);
    assert.doesNotMatch(body, /fn_notify_founder|recipient_role/, `${file}: ${fn} must not reach the founder`);
  });
}

test('IT-C02/C06: the closure gives a deadline, closes, reopens and hands an overdue finding on, never a cap or a hold', () => {
  const { body } = newest('fn_it_engineer_finding_closure');
  for (const re of [/deadline/, /reopen_count = reopen_count \+ 1/, /reading_at_close/,
    /fn_seat_handoff\('it_engineer', v_to, 'it\.finding'/, /no OpenRouter cap, no hold/]) assert.match(body, re);
  assert.doesNotMatch(body, /fn_notify_founder|recipient_role|update public\.model_/i);
});

test('ruling 1254: no dependency advisory is emailed to the founder; high and critical go to the CEO seat', () => {
  const { body } = newest('fn_it_dependency_ingest');
  assert.match(body, /'no_founder_email', true\)/);
  assert.match(body, /when v_hot or e->>'ecosystem' = 'app' then 'ceo'/);
});

test('IT-C13: every perimeter run stamps its schedule row', () => {
  assert.match(newest('fn_it_duty_ran').body, /update public\.it_duty_schedule set last_ok_at = now\(\)/);
});

test('IT-C15: the workflow audit catches each rule on a planted workflow and passes a clean one', () => {
  const bad = auditWorkflow('bad.yml', ['on: push', 'permissions: write-all', 'jobs:', '  a:', '    runs-on: self-hosted',
    '    steps:', '      - uses: actions/checkout@v4', '      - run: echo ${{ secrets.TOKEN }}'].join('\n'));
  assert.deepEqual(bad.map((v) => v.rule).sort(), ['runner', 'secret_in_log', 'unpinned_action', 'write_all']);
  const good = auditWorkflow('good.yml', ['on: push', 'permissions:', '  contents: read', 'jobs:', '  a:',
    "    runs-on: ${{ vars.RUNNER || 'ubicloud-standard-2' }}", '    steps:',
    '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1', '      - uses: ./local-action'].join('\n'));
  assert.deepEqual(good, []);
  // the slowest CI jobs run on ubicloud-standard-8 since #1293; a bare Ubicloud label without vars.RUNNER is still caught
  assert.deepEqual(auditWorkflow('sizes.yml', ['permissions:', '  contents: read', 'jobs:', '  a:', "    runs-on: ${{ vars.RUNNER || 'ubicloud-standard-8' }}",
    '  b:', '    runs-on: ubicloud-standard-2'].join('\n')).map((v) => [v.rule, v.lines]), [['runner', [7]]]);

  // ledger 1410: ubuntu-latest is the house runner now and must not be reported
  assert.deepEqual(auditWorkflow('house.yml', ['permissions:', '  contents: read', 'jobs:', '  a:', '    runs-on: ubuntu-latest'].join('\n')), []);

  assert.ok(auditDir().files > 0, 'the repository has workflows to audit');
  assert.match(readFileSync('.github/workflows/it-weekly-readings.yml', 'utf8'), /node scripts\/it\/workflow_audit\.mjs/);
});
