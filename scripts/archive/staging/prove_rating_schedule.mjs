// PROVE THE RATING CLOCK: the parser, and the selector, without back-dating anything.
//
//   node scripts/archive/staging/prove_rating_schedule.mjs <ref>
//
// The schedule is `revealed_at + the revealed quote's own lead_time`, so the two things worth
// asserting are (1) the parser reads a duration the way a human would and REFUSES what it cannot
// read, and (2) the selector's answer changes with the moment it is asked about — which is why
// fn_rating_due takes p_now as a parameter instead of calling now(). Asking "what would be due in
// two hours" is a question; editing revealed_at so something looks due is falsifying the record.
// 23 Sep 2026: this imported the guard by absolute file:// url into one person's checkout, so it
// ran nowhere else and no path-rewriting sweep could see it. Relative, like every other importer.
import { mgmtRead } from '../../lib/qd_guard.mjs';

const ref = process.argv[2];
if (!ref) { console.error('usage: prove_rating_schedule.mjs <ref>'); process.exit(2); }

// [input, expected interval or null]. The nulls are the point: an unreadable lead time must not
// become a default, because a default schedules a real message to a real customer.
const CASES = [
  ['1 hour', '01:00:00'], ['2 hours', '02:00:00'], ['48 hrs', '48:00:00'],
  ['3 days', '3 days'], ['1 day', '1 day'],
  ['7 working days', '10 days'],          // 7 * 7/5 = 9.8 -> 10 calendar days
  ['10 business days', '14 days'],
  ['2 weeks', '14 days'], ['1 week', '7 days'],
  ['3 months', '3 mons'],
  ['', null], ['asap', null], ['to be confirmed', null], ['12', null], ['negotiable', null],
];
const vals = CASES.map(([s]) => `(${s === '' ? `''` : `'${s.replace(/'/g, "''")}'`})`).join(',');
const rows = await mgmtRead(ref, `select v.s, public.fn_lead_time_interval(v.s)::text iv
  from (values ${vals}) v(s)`);

let bad = 0;
console.log('PARSER');
for (const [input, want] of CASES) {
  const got = rows.find((r) => (r.s ?? '') === input)?.iv ?? null;
  const ok = (want === null) ? (got === null) : String(got) === want;
  if (!ok) bad++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${JSON.stringify(input).padEnd(20)} -> ${JSON.stringify(got)}${ok ? '' : `  expected ${JSON.stringify(want)}`}`);
}

// The selector, asked about three different moments against the SAME unmodified rows.
console.log('\nSELECTOR (same data, three different questions)');
for (const [label, expr] of [['now', 'now()'], ['+2 hours', "now() + interval '2 hours'"], ['+40 days', "now() + interval '40 days'"]]) {
  const r = await mgmtRead(ref, `select public.fn_rating_due(${expr}) d`);
  const d = r[0].d;
  console.log(`  as at ${label.padEnd(8)} due=${(d.due || []).length} not_yet=${(d.not_yet || []).length} ` +
    `unschedulable=${(d.unschedulable || []).length} population=${JSON.stringify(d.population)}`);
  for (const u of d.unschedulable || []) console.log(`      unschedulable: ${u.why}`);
  for (const x of d.due || []) console.log(`      DUE: lead_time="${x.lead_time}" revealed ${x.revealed_at} -> due ${x.due_at}`);
}

if (bad) { console.log(`\nFAILED: ${bad} parser case(s) wrong`); process.exit(1); }
console.log('\nPASS: durations parsed as a human would read them, unreadable ones refused rather than defaulted.');
