// Read-only SQL reader for Phase B scripts.  One project: htdblwldjkcgjvmqkbeh.
//
// Every Phase B check must verify by execution, so the validators talk to the live
// database rather than to a cached dump.  The 429 backoff is here for the same
// reason it is in scripts/qsql.mjs: a bare throttle reads exactly like a broken
// query, and that has been misdiagnosed as a defect before.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

export const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('No Supabase access token (SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token).');
}

export async function sql(query, { ref = PROJECT_REF } = {}) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const text = await res.text();
    if ((res.status === 429 || res.status >= 500) && attempt < 7) {
      const wait = Math.min(2000 * 2 ** attempt, 60000);
      process.stderr.write(`-- ${res.status}; retry in ${wait / 1000}s (${attempt + 1}/7)\n`);
      await new Promise(r => setTimeout(r, wait));
      continue;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 2000)}`);
    try { return JSON.parse(text); } catch { return text; }
  }
}

/** Quote a JS string as a SQL literal. */
export const lit = s => `'${String(s).replace(/'/g, "''")}'`;

/** Build a `values (...),(...)` list; every cell is quoted as text. */
export const valuesOf = rows => rows.map(r => `(${r.map(lit).join(',')})`).join(',');
