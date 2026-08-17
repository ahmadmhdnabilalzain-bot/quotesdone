// Rehearse ONE committed migration inside an ABORTED production transaction, with an assertion
// block of your choosing appended.
//
//   node scripts/phase_c/rehearse_one.mjs scripts/sql/<file>.sql scripts/sql/<file>.assert.sql
//
// The migration's own `begin;`/`commit;` are stripped so the whole thing runs as one statement
// batch; the assert block ends in a `raise exception`, which aborts everything. It refuses to
// report success if nothing raised — a rehearsal that committed is not a rehearsal.
import { readFileSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const [file, assertFile] = process.argv.slice(2);
if (!file || !assertFile) { console.error('usage: rehearse_one.mjs <migration.sql> <assert.sql>'); process.exit(2); }

const body = readFileSync(file, 'utf8')
  .replace(/^\s*begin\s*;\s*$/gim, '')
  .replace(/^\s*commit\s*;\s*$/gim, '');
const asserts = readFileSync(assertFile, 'utf8');

try {
  await sql(`${body}\n\n${asserts}\n`);
  console.error('REHEARSAL DID NOT RAISE — it may have committed. Treat as FAILED.');
  process.exit(1);
} catch (e) {
  const m = String(e.message);
  const rehearsal = m.match(/REHEARSAL[\s\S]*?(?=\\nCONTEXT|\\nQUERY|"\}|$)/);
  console.log(rehearsal ? rehearsal[0].replace(/\\n/g, '\n') : m.slice(0, 4000));
  process.exit(m.includes('REHEARSAL') ? 0 : 1);
}
