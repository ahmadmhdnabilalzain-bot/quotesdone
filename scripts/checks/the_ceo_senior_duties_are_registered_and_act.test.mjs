// The eight CEO senior contributions of ledger 1003 stage 2 (C03 C04 C05 C06 C08 C09 C13 C14) are seat_duties that ACT.
// Seat: ceo. 19 Oct 2026: each was partial or missing on the CEO seat audit -- directives never re-decided after a
// miss, September never closed, an AT_RISK forecast with no counter-action, improvements opened as fast as closed,
// no pricing evidence table, three experiments 'proposed' since 24 Sep with nobody approving them, no refund metric,
// no register review. This reads the NEWEST definition of each routine (MANIFEST order, then files pending apply) and
// fails if a duty is unregistered or its routine stops writing what makes it act.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

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
  C03: ['ceo.directive_review', 'fn_ceo_directive_review', /insert into public\.ceo_directive[\s\S]*'reason'/],
  C04: ['ceo.month_close', 'fn_ceo_month_close', /insert into public\.ceo_month_close[\s\S]*insert into public\.ceo_month_report/],
  C05: ['ceo.forecast_counter_action', 'fn_ceo_forecast_counter_action', /fn_ceo_directive_issue\(v_seat, 'forecast_at_risk'/],
  C06: ['ceo.improvement_burn_down', 'fn_ceo_improvement_burn_down', /fn_ceo_directive_issue\(i\.seat, 'improvement_backlog'/],
  C08: ['ceo.pricing_evidence', 'fn_ceo_pricing_evidence', /insert into public\.ceo_pricing_evidence/],
  C09: ['ceo.experiment_month', 'fn_ceo_experiment_month', /insert into public\.ceo_experiment_verdict[\s\S]*status = 'running'[\s\S]*fn_ceo_directive_issue/],
  C13: ['ceo.refund_decision_metric', 'fn_ceo_refund_decision_metric', /insert into public\.ceo_refund_decision_metric[\s\S]*fn_ceo_task_open/],
  C14: ['ceo.register_review', 'fn_ceo_register_review', /risk_register[\s\S]*compliance_sources[\s\S]*v_company_subscriptions[\s\S]*fn_ceo_directive_issue/],
};

for (const [c, [duty, fn, acts]] of Object.entries(DUTIES)) {
  test(`${c}: ${duty} is registered on ${fn} and acts`, () => {
    const reg = new RegExp(String.raw`\('${duty.replace('.', '\\.')}',\s*'ceo',\s*interval '[^']+',\s*'${fn}'`);
    assert.match(all, reg, `${duty} is not registered as a ceo seat_duty running ${fn}`);
    const { file, body } = newest(fn);
    assert.match(body, acts, `${file}: ${fn} no longer writes what makes ${c} act`);
    assert.doesNotMatch(body, /fn_notify_founder|recipient_role/, `${file}: ${fn} must not reach the founder`);
  });
}

test('the directive kinds the duties issue are allowed by ceo_directive', () => {
  const chk = [...all.matchAll(/add constraint ceo_directive_source_kind_check check \(source_kind in\s*\(([^)]*)\)/g)].pop();
  assert.ok(chk, 'no file widens ceo_directive.source_kind');
  for (const k of ['forecast_at_risk', 'improvement_backlog', 'experiment', 'register_review', 'target_miss', 'seat_audit']) {
    assert.ok(chk[1].includes(`'${k}'`), `ceo_directive.source_kind does not allow ${k}`);
  }
});
