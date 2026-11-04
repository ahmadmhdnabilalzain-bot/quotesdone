#!/usr/bin/env node
// A WHOLE SQL FILE, REHEARSED ON PRODUCTION AND ROLLED BACK (it_engineer, 2 Nov 2026, founder ledger 1458).
// Pieces pasted by hand kept passing while the file itself had never parsed. This sends the file exactly as committed,
// with its probe if it has one, through safe_replay, which refuses transaction control and proves production unchanged.
//   node scripts/ci/rehearse_sql.mjs scripts/sql/x.sql [scripts/sql/x_probe.sql]
// Exit 0: the file ran, and the probe (if any) answered PROBE OK. Anything else exits 1.
// rehearse() is the same rule for a caller that rehearses text it assembled (rehearse_this_prs_manifest_lines.mjs).
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

/** 'PROBE OK' or 'REHEARSED' when the text ran and its probe (if any) passed; throws with the reason otherwise. */
export async function rehearse(sqlText, probeText, label) {
  const text = sqlText + '\n' + (probeText ?? 'select 1 as rehearsed;');
  try {
    await replaySql(text, { label, rows: probeText == null });
    if (probeText != null) throw new Error('the probe returned without its verdict');
    return 'REHEARSED';
  } catch (e) {
    const message = String(e?.body ?? e?.message ?? e);
    if (probeText != null && message.includes('PROBE OK') && !message.includes('PROBE FAILED')) return 'PROBE OK';
    throw new Error(message.slice(0, 4000));
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [file, probe] = process.argv.slice(2);
  if (!file) { console.error('usage: rehearse_sql.mjs <file.sql> [probe.sql]'); process.exit(2); }
  try {
    const verdict = await rehearse(readFileSync(file, 'utf8'), probe ? readFileSync(probe, 'utf8') : null, file);
    console.log(`${verdict}, rolled back: ${file}`);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
