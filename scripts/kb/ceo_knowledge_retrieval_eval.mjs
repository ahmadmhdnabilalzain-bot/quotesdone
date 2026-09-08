// DOES THE CEO'S RETRIEVAL FIND THE RIGHT GUIDANCE?
//
// The founder's requirement: "Compare performance with and without the added knowledge and
// playbooks. Keep changes that measurably improve results."
//
// WHAT THIS MEASURES, AND WHAT IT DOES NOT. It measures RETRIEVAL, not judgement. Each of the 32
// development scenarios in the pack names the modules a competent answer should draw on
// (`related_modules`). This harness asks the live retrieval for each scenario and checks whether
// those modules come back inside the top K. That is a real, repeatable number and it needs no model.
//
// It is NOT a model-in-the-loop evaluation. The pack's rubric scores problem diagnosis, evidence,
// alternatives, constraint handling and uncertainty -- all of which need a model to answer and a
// reviewer to score, and paid inference is held by founder order. Reporting a retrieval score as if
// it were a CEO competence score would be exactly the substitution the founder warned against.
//
// The scenarios are used ONLY as queries here. Their answers, rubrics and expected_math are never
// loaded into the knowledge store: feeding the answers into the search and then reporting a good
// score would be marking my own homework, and the pack says so in as many words.
//
//   node scripts/kb/ceo_knowledge_retrieval_eval.mjs --scenarios <path to scenarios.jsonl> [--k 8]

import { readFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const args = process.argv.slice(2);
const at = (f) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : null; };
const SCEN = at('--scenarios');
const K = Number(at('--k') || 8);
if (!SCEN) { console.error('--scenarios <scenarios.jsonl> is required'); process.exit(2); }

const scenarios = readFileSync(SCEN, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// The query is the scenario as a CEO would actually meet it: the situation and the request, not the
// answer. Trimmed to a length a real question would have.
const queryFor = (s) => (s.title + '. ' + (s.setup || '')).replace(/\s+/g, ' ').slice(0, 420);

const modulesOf = (recordId) => {
  const m = String(recordId).match(/ceokb\.module\.(\d+)\./);
  return m ? m[1].replace(/^0+/, '') : null;
};

let hit = 0, partial = 0, miss = 0, noCoverage = 0;
const detail = [];
for (const s of scenarios) {
  const want = (s.related_modules || []).map((x) => String(x).replace(/^0+/, ''));
  const rows = await sql(`select f.record_id, k.related_modules
    from public.fn_ceo_knowledge_search(${lit(queryFor(s))}, ${K}) f
    join public.ceo_knowledge k on k.record_id = f.record_id`);
  const got = new Set();
  for (const r of rows) {
    const m = modulesOf(r.record_id);
    if (m) got.add(m);
    for (const rm of (r.related_modules || [])) got.add(String(rm).replace(/^0+/, ''));
  }
  const found = want.filter((w) => got.has(w));
  let verdict;
  if (rows.length === 0) { verdict = 'NO_COVERAGE'; noCoverage++; }
  else if (want.length === 0) { verdict = 'NO_EXPECTATION'; }
  else if (found.length === want.length) { verdict = 'HIT'; hit++; }
  else if (found.length > 0) { verdict = 'PARTIAL'; partial++; }
  else { verdict = 'MISS'; miss++; }
  detail.push({ id: s.scenario_id, verdict, want: want.join(','), found: found.join(',') || '-', returned: rows.length });
}

const scored = hit + partial + miss + noCoverage;
console.log('CEO RETRIEVAL EVALUATION  ·  ' + scenarios.length + ' scenarios  ·  top-' + K);
console.log('  HIT (every expected module retrieved)   ' + hit);
console.log('  PARTIAL (some retrieved)                ' + partial);
console.log('  MISS (none retrieved, but rows came back) ' + miss);
console.log('  NO_COVERAGE (retrieval returned nothing) ' + noCoverage);
console.log('  scored: ' + scored + '  ·  full-hit rate: ' + (scored ? (100 * hit / scored).toFixed(1) : '0') + '%'
          + '  ·  any-hit rate: ' + (scored ? (100 * (hit + partial) / scored).toFixed(1) : '0') + '%');
console.log('\nfailures:');
for (const d of detail.filter((x) => x.verdict === 'MISS' || x.verdict === 'NO_COVERAGE'))
  console.log('  ' + d.id + '  ' + d.verdict.padEnd(12) + ' wanted ' + d.want + ' · returned ' + d.returned + ' row(s)');
process.exit(0);
