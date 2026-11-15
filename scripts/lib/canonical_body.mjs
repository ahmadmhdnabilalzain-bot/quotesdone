// THE CANONICAL BODY OF ONE ROUTINE, AND A ROLLED-BACK REHEARSAL OF A FILE CHAIN WITH ITS PROBE (ceo, 10 Nov 2026).
// Several checks inlined the same two helpers: "the last MANIFEST (or pending) file that defines fn_x, and the text
// between its dollar quotes", and "replay these files and this probe on production, rolled back, and read the probe's
// CHK<<...>> verdict out of the error". They live here once.
//   canonicalBody('fn_x')            -> { file, body }   (throws when no applied or pending file defines it)
//   rehearseChain([files], probe)    -> the probe's message: 'PROBE OK ...' / 'PROBE FAILED ...'
//   productionSkip()                 -> false, or the reason a production replay cannot run here
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from './pending_sql.mjs';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const read = (p) => readFileSync(join(ROOT, p), 'utf8');

export function canonicalBody(fn) {
  const re = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');
  const file = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(read(f)));
  if (!file) throw new Error(`no applied or pending file defines ${fn}`);
  const src = read(file).slice(read(file).search(re));
  const tag = src.match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  return { file, body: src.split(tag)[1] || '' };
}

export function productionSkip() {
  if (process.env.QD_OFFLINE === '1') return 'QD_OFFLINE=1: no production replay';
  const token = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
  return token ? false : 'no Supabase management token in this environment';
}

export async function rehearseChain(files, probe) {
  const { replaySql } = await import('./safe_replay.mjs');
  const text = "set local lock_timeout = '1s';\nset local statement_timeout = '120s';\n" + [...files, probe].map(read).join('\n;\n');
  try { await replaySql(text, { retry: false }); } catch (e) {
    const msg = String(e?.body ?? e?.message ?? e);
    const m = msg.match(/(PROBE (?:OK|FAILED)[^\n]*)/);
    if (m) return m[1];
    throw new Error('the rehearsal failed before its probe could report: ' + msg.slice(0, 1500));
  }
  throw new Error('the probe returned without raising: it would have committed');
}
