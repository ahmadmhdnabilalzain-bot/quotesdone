// Run a .sql file against the production database via the Supabase Management API
// and print the JSON result.  Read-only by convention: the caller is responsible
// for wrapping anything destructive in an aborted transaction.
//
//   node scripts/qsql.mjs path/to/file.sql
//
// Token: %USERPROFILE%\.supabase\access-token or SUPABASE_ACCESS_TOKEN.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const file = process.argv[2];
if (!file) { console.error('usage: node scripts/qsql.mjs <file.sql>'); process.exit(2); }

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  console.error('No Supabase access token.'); process.exit(2);
}

const query = readFileSync(file, 'utf8');
const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query }),
});
const text = await res.text();
if (!res.ok) { console.error(`HTTP ${res.status}`); console.error(text); process.exit(1); }
let rows;
try { rows = JSON.parse(text); } catch { console.log(text); process.exit(0); }
if (Array.isArray(rows)) {
  for (const r of rows) {
    const vals = Object.values(r);
    if (vals.length === 1 && typeof vals[0] === 'string') console.log(vals[0]);
    else console.log(JSON.stringify(r));
  }
  console.log(`-- rows: ${rows.length}`);
} else {
  console.log(JSON.stringify(rows, null, 2));
}
