// Record an already-executed statement in supabase_migrations.schema_migrations so the applied
// record and the repository stay in step. This is what `supabase db push` does; the Management API
// executes SQL without recording it, so recording is a separate, explicit act.
//
//   node scripts/record_migration.mjs <version> <name> <path-to-sql>
//
// Prints the version, name, SHA-256 and character count of what was recorded, in the same form the
// recovery manifests use, so the manifest entry can be written from real values.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const [version, name, file] = process.argv.slice(2);
if (!version || !name || !file) {
  console.error('usage: node scripts/record_migration.mjs <version> <name> <file.sql>'); process.exit(2);
}
if (!/^\d{14}$/.test(version)) { console.error('version must be 14 digits'); process.exit(2); }

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  console.error('No Supabase access token.'); process.exit(2);
}

const body = readFileSync(file, 'utf8');
const tag = `$mig_${version}$`;
if (body.includes(tag)) { console.error('dollar-quote tag collides with the body'); process.exit(2); }

async function run(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) { console.error(`Management API ${res.status}: ${text}`); process.exit(3); }
  return JSON.parse(text);
}

await run(`insert into supabase_migrations.schema_migrations (version, name, statements)
           values ('${version}', '${name}', array[${tag}${body}${tag}])
           on conflict (version) do nothing`);

const rows = await run(`select version, name, array_length(statements,1) as n,
       encode(extensions.digest(array_to_string(statements, E';\\n') || ';', 'sha256'),'hex') as sha,
       length(array_to_string(statements, E';\\n')) as chars
  from supabase_migrations.schema_migrations where version = '${version}'`);
if (rows.length !== 1) { console.error('not recorded'); process.exit(1); }
const r = rows[0];
console.log(`| ${r.version} | ${r.name} | \`${r.sha}\` | ${Number(r.chars).toLocaleString('en-US')} |`);
console.log(`statements array length: ${r.n}`);
