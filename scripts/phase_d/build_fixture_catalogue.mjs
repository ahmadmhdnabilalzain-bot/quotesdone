// PHASE D DELIVERABLE — PHASE_D_FIXTURE_CATALOGUE.csv
//
// The committed mirror of public.phase_d_fixture_catalogue. The founder's section B requires the
// catalogue to be COMMITTED, and this estate has a rule about that: a row added to a register
// without its artefact is a row nobody can review. The check that compares the two is
// scripts/checks/phase_d_fixture_catalogue_matches_the_file.test.mjs, and it fails in both
// directions.
//
//   node scripts/phase_d/build_fixture_catalogue.mjs
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../lib/db.mjs';

const cols = ['fixture_id','fixture_version','workflow_id','step_id','scope','field_key','value',
  'value_kind','currency','expected_schema','expected_result','prohibited_external_use',
  'marker_exemption','checksum'];
const rows = await sql(`select ${cols.join(', ')} from public.phase_d_fixture_catalogue order by fixture_id`);
const board = await sql('select check_name, actual, ok from public.fn_phase_d_fixture_catalogue_state()');

const cell = (v) => `"${(v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v)).replace(/"/g, '""')}"`;
const csv = provenance({
  command: 'node scripts/phase_d/build_fixture_catalogue.mjs',
  numerator: rows.length, denominator: rows.length,
  of: 'rows of public.phase_d_fixture_catalogue, the committed Phase D content catalogue',
  attribution: 'read straight from the table; the checksum column is computed by a10_phase_d_fixture_catalogue_checksum over the canonical serialisation and is never accepted from a caller',
}) + cols.join(',') + '\n'
  + rows.map(r => cols.map(c => cell(r[c])).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_FIXTURE_CATALOGUE.csv'), csv);
console.log(`${rows.length} catalogue rows`);
for (const b of board) console.log(`  ${b.ok ? 'ok  ' : 'RED '} ${b.check_name}: ${String(b.actual).slice(0,90)}`);
if (board.some(b => !b.ok)) process.exit(1);
