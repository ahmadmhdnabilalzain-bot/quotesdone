// Turns a paid run of run.mjs into the recording the offline test replays at USD 0 (sales_engineer, 12 Nov 2026; ruling 1647):
//   node scripts/e2e/services_hard_profiles/record.mjs <run.json> [--runs 1]   -> recorded.json beside this file
// Kept per profile: the documents as the reader was given them (code's text of the ZZ DEMO PDFs, with the licence's activities) and
// every model answer, keyed by the sha256 of the text it answered (the prompts are not stored: they are the code's). The catalogue
// read in the same run (run.json's .catalogue.json) is kept too, so the replay maps against the catalogue the answers were given.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = dirname(fileURLToPath(import.meta.url));
const [file] = process.argv.slice(2);
if (!file) { console.error('usage: record.mjs <run.json>'); process.exit(2); }
const rows = JSON.parse(readFileSync(file, 'utf8'));
const cat = JSON.parse(readFileSync(file.replace(/\.json$/, '') + '.catalogue.json', 'utf8'));
const sha = (t) => createHash('sha256').update(t).digest('hex');
const spend = (() => { try { return JSON.parse(readFileSync(file.replace(/\.json$/, '') + '.spend.json', 'utf8')); } catch { return null; } })();
const profiles = [];
for (const r of rows) for (const [i, u] of r.runs.entries()) {
  if (!u.ok || !u.recorded?.length) { console.error(`${r.id} run ${i + 1}: no reading recorded (${u.error ?? u.why}); not kept`); continue; }
  profiles.push({ id: r.id, run: i + 1, company: r.company, ms: u.ms, times: u.times, docs: u.given_docs.map(({ activities: _a, ...d }) => d),
    licence_activities: u.given_docs.find((d) => d.kind === 'licence')?.activities ?? [],
    calls: u.recorded.map((c) => ({ step: c.step, text_sha256: sha(c.text), ms: c.ms, content: c.content })) });
}
const out = { note: 'ZZ DEMO only: invented companies (profiles_def.mjs). Recorded model answers of a paid run, replayed offline by the_hard_profiles_are_read_offline.test.ts.',
  run_tag: spend?.run_tag ?? null, spend_usd: spend?.usd ?? null, recorded_from: file.split('/').pop(), taxonomy: cat.taxonomy, implications: cat.implications, profiles };
writeFileSync(join(HERE, 'recorded.json'), JSON.stringify(out) + '\n');
console.log(`recorded ${profiles.length} readings (${profiles.reduce((n, p) => n + p.calls.length, 0)} answers) -> recorded.json`);
