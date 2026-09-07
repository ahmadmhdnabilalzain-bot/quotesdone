// DOES SUPPORT'S RETRIEVAL FIND ANYTHING FOR THE SITUATIONS IT WILL ACTUALLY MEET?
//
// WHAT THIS MEASURES, AND WHAT IT DOES NOT — stated first, because the value of this number
// depends entirely on knowing which question it answers.
//
// It measures COVERAGE and LEAKAGE, not judgement:
//   COVERAGE  for each of the 48 disclosed development scenarios, does the live retrieval return
//             anything at all? A scenario with zero hits is a situation the agent will meet with
//             no guidance behind it — and it will still answer, fluently, from nothing.
//   LEAKAGE   do any returned records come from the pack's evaluation directory? They must not.
//             Feeding the answers into the search and then reporting a good score is marking my
//             own homework, and the pack says so in as many words.
//
// It does NOT measure whether the retrieved guidance is the RIGHT guidance. The CEO pack ships
// `related_modules` on every scenario, which makes a precision measure possible there; the support
// scenarios ship none, so there is no ground truth to score against. Inventing one — deciding by
// hand which record ought to win each query and then measuring against my own guesses — would be
// a number that measures my expectations, not the retrieval. It is left unmeasured and said so.
//
// The scenarios are used ONLY as queries. Their must_do, must_not and rubric fields never reach
// the knowledge store.
//
//   node scripts/kb/support_knowledge_retrieval_eval.mjs --scenarios <path to scenarios.jsonl> [--k 8]

import { readFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const args = process.argv.slice(2);
const at = (f) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : null; };
const SCEN = at('--scenarios');
const K = Number(at('--k') || 8);
if (!SCEN) { console.error('--scenarios <scenarios.jsonl> is required'); process.exit(2); }

const scenarios = readFileSync(SCEN, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// The query is the situation as support would actually meet it — the title and the setup — not the
// expected answer. Trimmed to the length a real question has.
const queryFor = (s) => (s.title + '. ' + (s.setup || '')).replace(/\s+/g, ' ').slice(0, 420);

let covered = 0, empty = 0, leaked = 0;
const emptyOnes = [];
const howMatched = {};

for (const s of scenarios) {
  const rows = await sql(`select f.record_id, coalesce(f.matched_how, 'unknown') matched_how,
                                 coalesce(k.source_path,'') source_path
    from public.fn_support_knowledge_search(${lit(queryFor(s))}, ${K}, null) f
    join public.support_knowledge k on k.record_id = f.record_id`);

  if (rows.length === 0) { empty++; emptyOnes.push(s.scenario_id + '  ' + s.title); }
  else covered++;

  for (const r of rows) {
    howMatched[r.matched_how] = (howMatched[r.matched_how] || 0) + 1;
    if (/evaluation|scenarios\.jsonl|rubric/i.test(r.source_path)) leaked++;
  }
}

const pct = (n) => ((n / scenarios.length) * 100).toFixed(0);
console.log(`\nSUPPORT KNOWLEDGE RETRIEVAL — ${scenarios.length} disclosed development scenarios, top ${K}\n`);
console.log(`  coverage        ${covered}/${scenarios.length}  (${pct(covered)}%) returned at least one record`);
console.log(`  no coverage     ${empty}  scenario(s) the agent would meet with nothing behind it`);
console.log(`  evaluation leak ${leaked}  record(s) from the pack's evaluation directory (must be 0)`);
console.log(`  matched how     ${JSON.stringify(howMatched)}`);

if (emptyOnes.length) {
  console.log('\nSCENARIOS WITH NO RETRIEVAL — these are the gaps, kept rather than rounded away:');
  for (const e of emptyOnes) console.log('  ' + e);
}

console.log('\nNOT MEASURED: whether the retrieved guidance is the RIGHT guidance. The support');
console.log('scenarios carry no related_modules, so there is no ground truth to score precision');
console.log('against, and inventing one would measure my expectations rather than the retrieval.');

// Leakage is a release blocker; a coverage gap is a finding to work on, not a broken build.
process.exit(leaked === 0 ? 0 : 1);
