// quote_review_corpus.ts — prints the before -> after table for the sales engineer's review and the generaliser over
// the 24-trade synthetic corpus (supabase/functions/_shared/quote_review.fixture.ts). Seat: sales_engineer.
// 10 Nov 2026, founder ledger 1588-1590. No database, no model, USD 0.
//   deno run --no-lock --allow-read scripts/e2e/quote_review_corpus.ts            # the table, per group
//   deno run --no-lock --allow-read scripts/e2e/quote_review_corpus.ts --detail   # every leak, miss and extra flag
// The gate's version of the same measurement, with its thresholds, is _shared/quote_review_corpus.test.ts.
import { measureCorpus } from '../../supabase/functions/_shared/quote_review_corpus.ts';

const rows = measureCorpus();
const detail = Deno.args.includes('--detail');
const groups = [...new Set(rows.map((r) => r.group))];
const sum = (rs: typeof rows, f: (r: (typeof rows)[number]) => number) => rs.reduce((s, r) => s + f(r), 0);
const line = (name: string, rs: typeof rows) => {
  const ids = sum(rs, (r) => r.before.deviant.ids + r.before.control.ids);
  const lb = sum(rs, (r) => r.before.deviant.leaks + r.before.control.leaks), la = sum(rs, (r) => r.after.deviant.leaks + r.after.control.leaks);
  const pl = sum(rs, (r) => r.planted);
  return `| ${name.padEnd(32)} | ${String(lb).padStart(3)} -> ${String(la).padEnd(3)} of ${String(ids).padEnd(4)} | ${String(sum(rs, (r) => r.before.caught)).padStart(3)} -> ${String(sum(rs, (r) => r.after.caught)).padEnd(3)} of ${String(pl).padEnd(4)} | ${String(sum(rs, (r) => r.before.false_flags)).padStart(2)} -> ${String(sum(rs, (r) => r.after.false_flags)).padEnd(2)} | ${String(sum(rs, (r) => r.after.over_redacted.length)).padStart(3)} |`;
};
console.log('| group                            | identity leaks (planted) | deviations caught (planted) | false flags | over-redacted |');
console.log('|---|---|---|---|---|');
for (const g of groups) console.log(line(g, rows.filter((r) => r.group === g)));
console.log(line('ALL 24 TRADES', rows));
if (detail) for (const r of rows) {
  const bits = [r.after.deviant.leaked.length ? 'LEAK ' + r.after.deviant.leaked.join(', ') : '', r.after.control.leaked.length ? 'CONTROL LEAK ' + r.after.control.leaked.join(', ') : '',
    r.after.missed.length ? 'MISSED ' + r.after.missed.join(', ') : '', r.after.extra.length ? 'EXTRA ' + r.after.extra.join(' | ') : '', r.after.over_redacted.length ? 'OVER ' + r.after.over_redacted.join(', ') : ''].filter(Boolean);
  console.log(`${r.code}: before leaks ${r.before.deviant.leaked.join(', ')} | ${bits.join(' ; ') || 'clean'}`);
}
