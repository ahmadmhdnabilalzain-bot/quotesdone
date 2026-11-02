#!/usr/bin/env node
// A WHOLE SQL FILE, REHEARSED ON PRODUCTION AND ROLLED BACK (it_engineer, 2 Nov 2026, founder ledger 1458).
// Pieces pasted by hand kept passing while the file itself had never parsed. This sends the file exactly as committed,
// with its probe if it has one, through safe_replay, which refuses transaction control and proves production unchanged.
//   node scripts/ci/rehearse_sql.mjs scripts/sql/x.sql [scripts/sql/x_probe.sql]
// Exit 0: the file ran, and the probe (if any) answered PROBE OK. Anything else exits 1.
import { readFileSync } from 'node:fs';
import { replaySql } from '../lib/safe_replay.mjs';

const [file, probe] = process.argv.slice(2);
if (!file) { console.error('usage: rehearse_sql.mjs <file.sql> [probe.sql]'); process.exit(2); }
const text = readFileSync(file, 'utf8') + '\n' + (probe ? readFileSync(probe, 'utf8') : 'select 1 as rehearsed;');
try {
  await replaySql(text, { label: file, rows: !probe });
  if (probe) throw new Error('the probe returned without its verdict');
  console.log('REHEARSED, rolled back: ' + file);
} catch (e) {
  const message = String(e?.body ?? e?.message ?? e);
  if (probe && message.includes('PROBE OK') && !message.includes('PROBE FAILED')) {
    console.log('PROBE OK, rolled back: ' + file);
    process.exit(0);
  }
  console.error(message.slice(0, 4000));
  process.exit(1);
}
