// The marketing senior contributions of ledger 1003 stage 2 (C03 C05 C07 C10 C11 C12 C13 C14 C15) are seat_duties that ACT.
// Seat: marketing. 19 Oct 2026: each was partial or missing on the marketing seat audit -- uncited GEO questions with no
// fix, a funnel of nulls that never read a delivered invitation, no publishing or inbox owner, 194 trends never decided,
// no KPI scorecard, no fact register, no paid-spend report. This reads the NEWEST definition of each routine (MANIFEST
// order, then files pending apply) and fails if a duty is unregistered or its routine stops writing what makes it act.
// C06 (the competitor watch) is scripts/checks/the_competitor_watch_reads_real_pages.test.mjs.
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

// contribution -> [duty, routine, what the routine must do for the duty to act]
const DUTIES = {
  C03: ['marketing.geo_fix', 'fn_marketing_geo_fix', /status = 'closed'[\s\S]*insert into public\.marketing_geo_fix/],
  C05: ['marketing.recruitment_funnel', 'fn_marketing_recruitment_funnel', /provider_status = 'delivered'[\s\S]*n\.type = 'supplier_invite'[\s\S]*coalesce\(sum\(pool\), 0\)/],
  C07: ['marketing.reputation', 'fn_marketing_reputation', /google_place_id[\s\S]*fn_customer_support_takes_delivery/],
  C10: ['marketing.social_publish', 'fn_marketing_social_publish', /fn_is_working_day[\s\S]*utm_source=[\s\S]*fn_ceo_task_open/],
  C11: ['marketing.social_inbox', 'fn_marketing_social_inbox', /social_inbox:overdue[\s\S]*signed_rejected[\s\S]*social_inbox:send_failed/],
  C12: ['marketing.trend_decision', 'fn_marketing_trend_decision', /seen_at < now\(\) - interval '48 hours'[\s\S]*insert into public\.marketing_duty_record/],
  C13: ['marketing.kpi_scorecard', 'fn_marketing_kpi_scorecard', /insert into public\.marketing_duty_record[\s\S]*fn_marketing_kpi_scorecard_for/],
  C14: ['marketing.fact_register', 'fn_marketing_fact_register', /fn_marketing_public_facts[\s\S]*net\._http_response[\s\S]*facts:surface_stale:[\s\S]*net\.http_get/],
  C15: ['marketing.paid_spend_report', 'fn_marketing_paid_spend_report', /fn_marketing_paid_allowed\(\)[\s\S]*paid:spend_without_budget/],
};
// C05 and C07 extend duties registered before this PR; the rest are registered by it.
const PRE_REGISTERED = new Set(['C05', 'C07']);

for (const [c, [duty, fn, acts]] of Object.entries(DUTIES)) {
  test(`${c}: ${duty} is registered on ${fn} and acts`, () => {
    if (!PRE_REGISTERED.has(c)) {
      const reg = new RegExp(String.raw`\('${duty.replace('.', '\\.')}',\s*'marketing',\s*interval '[^']+',\s*'${fn}'`);
      assert.match(all, reg, `${duty} is not registered as a marketing seat_duty running ${fn}`);
    }
    const { file, body } = newest(fn);
    assert.match(body, acts, `${file}: ${fn} no longer does what makes ${c} act`);
    assert.doesNotMatch(body, /fn_notify_founder|recipient_role/, `${file}: ${fn} must not reach the founder`);
  });
}

test('C15: nothing in the marketing duties switches paid media on', () => {
  for (const fn of Object.values(DUTIES).map((d) => d[1])) {
    const { file, body } = newest(fn);
    assert.doesNotMatch(body, /update\s+public\.ad_spend_policy|paid_allowed\s*:?=\s*true/i, `${file}: ${fn} touches the paid switch`);
  }
});
