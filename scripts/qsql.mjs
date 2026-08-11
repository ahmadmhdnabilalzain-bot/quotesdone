// Run a .sql file against the production database via the Supabase Management API
// and print the JSON result.  Read-only by convention: the caller is responsible
// for wrapping anything destructive in an aborted transaction.
//
//   node scripts/qsql.mjs path/to/file.sql              # production (default)
//   node scripts/qsql.mjs path/to/file.sql --ref=<ref>  # any project, e.g. staging
//
// The --ref form exists because "verify by measurement" means BOTH projects, and this reader was
// production-only: staging could only be read through qd_guard from inside another script.
//
// Token: %USERPROFILE%\.supabase\access-token or SUPABASE_ACCESS_TOKEN.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const args = process.argv.slice(2);
const PROJECT_REF = (args.find(a => a.startsWith('--ref='))|| '').slice(6) || 'htdblwldjkcgjvmqkbeh';
const file = args.find(a => !a.startsWith('--'));
if (!file) { console.error('usage: node scripts/qsql.mjs <file.sql> [--ref=<ref>]'); process.exit(2); }

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  console.error('No Supabase access token.'); process.exit(2);
}

const query = readFileSync(file, 'utf8');
// The management API rate-limits hard after a heavy session. Without backoff a read fails with a
// bare 429 that reads exactly like a broken query, which is how a throttle gets misdiagnosed as a
// defect in the SQL. qd_guard has had this for weeks; this path did not.
async function run(attempt = 0) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if ((res.status === 429 || res.status >= 500) && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.error(`-- ${res.status}; retrying in ${wait / 1000}s (attempt ${attempt + 1}/7)`);
    await new Promise(r => setTimeout(r, wait));
    return run(attempt + 1);
  }
  return { res, text };
}
const { res, text } = await run();
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
