import { readFileSync, writeFileSync } from 'node:fs';
const f = 'docs/phase-d/PHASE_D_HANDOVER_2026-08-23_R2.md';
let s = readFileSync(f, 'utf8');

const OLD = [
  '`iban_doc_path`, which no watch list of that trigger names — measured in an aborted transaction:',
  '`iban_doc_path` registers no document, `license_doc_path` registers one. The two stray `documents`',
  'rows, the two `company_event` rows and the three `agent_runs` error rows were deleted by hand; the',
  'backups of the four real documents in that sweep succeeded and are untouched.',
].join('\n');

const NEW = [
  '`iban_doc_path`, which no watch list of that trigger names — measured in an aborted transaction:',
  '`iban_doc_path` registers no document, `license_doc_path` registers one.',
  '',
  '**And the document row was not the end of the chain.** Deleting the two `documents` rows did not',
  'stop the sweep. `public.documents` feeds `fn_enqueue_doc_backups`, which writes',
  '`public.doc_backups`, and THAT is the queue cron job 88 drains: it retries a row five times and',
  'outlives the document that produced it. Rows 46209 and 46210 were still queued at attempts 4 of 5,',
  'error "download Object not found", long after their documents were gone, and they kept the sweep',
  'failing at 17:15 and again at 17:30. Cleaning the table you happened to write is not cleaning up.',
  '',
  'The full count of what this cost, all removed by hand and all verified back at their watermark:',
  '**2 `documents` rows, 2 `doc_backups` rows, 4 `company_event` rows and 4 `agent_runs` error rows.**',
  'The queue is now deleted in the §8 cleanup and COUNTED in its zero-effect assertion, so a survivor',
  'is a stop rather than something a later run discovers. The backups of the real documents in those',
  'sweeps succeeded and are untouched.',
].join('\n');

if (!s.includes(OLD)) throw new Error('anchor not found');
s = s.split(OLD).join(NEW);

s = s.split('`company_event` 1526 (baseline)')
     .join('`company_event` 1526 (baseline, re-verified after the last cleanup)');

// And say what was NOT run, rather than let a reader assume the whole sweep was done.
const OLDS = '## Exact remaining blockers';
const NEWS = [
  '## End-of-session sweep',
  '',
  '| check | result |',
  '|---|---|',
  '| GitHub Actions on `main` | 3 of 3 workflows success |',
  '| Vercel | deployment completed |',
  '| Row #3 scorer, run to completion | **105 / 152 (69%)** — unchanged; this session touched no executive-UI surface |',
  '| `fn_os_portals_gates()` | 21 of 23 met. The two unmet are consequences of the founder\'s own holds, not of this session: "model calls include task class…" is *0 of 0* `ai_cost_log` rows in 7 days because paid inference is held at zero, and "monitoring and alerts configured" reports 23 of 206 cron jobs active with `watch_failed_runs_hourly` INACTIVE, which is the stand-down |',
  '| canonical routine engine | 0 findings, both drift directions |',
  '| schema export byte-identical | yes, 79,077 lines |',
  '| `node scripts/verify_deploy_parity.mjs --all` | **202 functions** carry the repository\'s current code |',
  '| `anon_cannot_execute_security_definer` | 7 of 7 |',
  '| Phase A / Phase B drift | 0 / 0 |',
  '',
  '**Not run, and why:** the knowledge-pack scorecard. `node scripts/kb/pack_scorecard.mjs` requires',
  '`--packs=<extracted packs dir>`, which is not in this repository and was not supplied. Nothing is',
  'claimed about the packs either way.',
  '',
  '## Exact remaining blockers',
].join('\n');
if (!s.includes(OLDS)) throw new Error('sweep anchor not found');
s = s.split(OLDS).join(NEWS);

writeFileSync(f, s);
console.log('ok');
