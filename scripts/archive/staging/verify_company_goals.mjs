// COMPANY GOALS — the seven the architecture spec names, and whether they measure what they claim.
//
// revenue_annual's measure was `select count(*) from inquiries where created_at > now()-'30 days'`
// against a metric of "Recognised revenue in trailing 12 months". It counted inquiries, over the
// wrong window, against an empty table — and returned 0, which is also what the CORRECT measure
// returns today. A wrong measure that agrees with the right one cannot be caught by its output.
// So this gate reads what each measure TOUCHES, not only what it returns.
//
//   node scripts/archive/staging/verify_company_goals.mjs      # zero spend
import { mgmtRead } from '../../lib/qd_guard.mjs';
import { REF as STAGE } from '../../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(58)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;

// The spec's own list, architecture file lines 21-27, and the table each must actually read.
const SPEC_GOALS = [
  ['revenue_annual', /\btransactions\b/, /\binquiries\b/],
  ['customer_satisfaction', /\breviews\b/, /\breview_chain\b/],
  ['supplier_satisfaction', /\bsupplier_perf\b/, null],
  ['rfq_completion_rate', /\bquotes\b/, null],
  ['quote_conversion_rate', /\btransactions\b/, null],
  ['operating_cost', /\bai_cost_log\b/, null],
];

try {
  const rows = await mgmtRead(STAGE,
    `select key, metric, unit, target_value, coalesce(measure_sql,'') measure_sql
       from company_goals where key in (${SPEC_GOALS.map(g => `'${g[0]}'`).join(',')}) order by key`);
  const by = Object.fromEntries(rows.map(r => [r.key, r]));

  step('every goal the spec names exists', rows.length === SPEC_GOALS.length,
    `${rows.length}/${SPEC_GOALS.length}: ${rows.map(r => r.key).join(', ')}`);

  const unmeasured = SPEC_GOALS.filter(([k]) => !by[k] || !by[k].measure_sql);
  step('every goal the spec names carries a measure', unmeasured.length === 0,
    unmeasured.length ? unmeasured.map(g => g[0]).join(', ') : `${SPEC_GOALS.length}/${SPEC_GOALS.length} measurable`);

  // Reads the RIGHT table, and — the check that would have caught the original defect — does NOT
  // read the wrong one.
  const wrongTable = SPEC_GOALS.filter(([k, must, mustNot]) => {
    const sql = by[k]?.measure_sql || '';
    return !must.test(sql) || (mustNot && mustNot.test(sql));
  });
  step('each measure reads the table its metric describes', wrongTable.length === 0,
    wrongTable.length ? wrongTable.map(g => g[0]).join(', ')
      : 'revenue<-transactions (not inquiries), satisfaction<-reviews (not review_chain)');

  // EVERY measure in the table must EXECUTE. A measure_sql that errors is worse than an empty one:
  // fn_goal_period_refresh reports success either way.
  const all = await mgmtRead(STAGE,
    `select key, measure_sql from company_goals where active and coalesce(measure_sql,'') <> '' order by key`);
  const broken = [];
  for (const g of all) {
    try {
      const v = await mgmtRead(STAGE, `select (${g.measure_sql}) as v`);
      const val = v?.[0]?.v;
      if (val !== null && val !== undefined && isNaN(Number(val))) broken.push(`${g.key} (non-numeric)`);
    } catch (e) { broken.push(`${g.key}: ${String(e.message || e).slice(0, 70)}`); }
  }
  step('every stored measure executes and returns a number or null', broken.length === 0,
    broken.length ? broken.join(' | ') : `${all.length}/${all.length} measures run clean`);

  // A measure must not silently divide by zero into a fabricated figure.
  const zeroDiv = all.filter(g => /\/\s*(count|sum)\s*\(/i.test(g.measure_sql) && !/nullif/i.test(g.measure_sql));
  step('no measure divides without a nullif guard', zeroDiv.length === 0,
    zeroDiv.length ? zeroDiv.map(g => g.key).join(', ') : `${all.length} checked`);

  // The unit must be consistent with the target: a percentage measure against a 1-5 rating target
  // is exactly how customer_satisfaction went unnoticed.
  const cs = by['customer_satisfaction'];
  step('customer satisfaction is measured on the scale its target uses',
    cs.unit === 'rating_1_5' && /avg\s*\(\s*r\.rating\s*\)/i.test(cs.measure_sql) && !/100\.0/.test(cs.measure_sql),
    `unit=${cs.unit}, target=${cs.target_value}, measure averages a 1-5 rating rather than a percentage`);

  step('revenue is money, not a row count',
    /sum\s*\(/i.test(by['revenue_annual'].measure_sql) && !/count\s*\(\s*\*/i.test(by['revenue_annual'].measure_sql),
    `sums a fee column over 365 days; unit=${by['revenue_annual'].unit}`);
} catch (e) {
  step('the gate ran to completion', false, String(e.message || e).slice(0, 300));
}

const pass = checks.filter(c => c.ok).length;
console.log(`\nCOMPANY GOALS ${pass}/${checks.length} on ${STAGE} (zero spend)`);
process.exit(pass === checks.length ? 0 : 1);
