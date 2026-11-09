// Recover one applied migration verbatim, verified against a committed manifest.
//
//   node scripts/archive/recover_one.mjs <version>
//
// The expected name and SHA-256 are read from the manifests in supabase/migrations/, which are
// committed before this runs. The file is written as <applied version>_<name>.sql so that the
// filename IS the applied version: `supabase db push` then sees it as already applied instead of
// treating it as new work to run.
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const MIG = join(process.cwd(), 'supabase', 'migrations');
const version = process.argv[2];
if (!/^\d{14}$/.test(version || '')) { console.error('usage: node scripts/archive/recover_one.mjs <14-digit version>'); process.exit(2); }

const expected = readdirSync(MIG).filter(f => f.endsWith('.md'))
  .flatMap(f => readFileSync(join(MIG, f), 'utf8').split('\n'))
  .map(l => l.match(/^\|\s*\d+\s*\|\s*(\d{14})\s*\|\s*([a-z0-9_]+)\s*\|\s*`([0-9a-f]{64})`/))
  .filter(Boolean).map(m => ({ version: m[1], name: m[2], sha: m[3] }))
  .find(e => e.version === version);
if (!expected) { console.error(`${version} is not in any committed manifest. Add it there first.`); process.exit(2); }

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  console.error('No Supabase access token.'); process.exit(2);
}

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: `select version, name, array_to_string(statements, E';\\n') || ';' as sql
              from supabase_migrations.schema_migrations where version = '${version}'`,
  }),
});
if (!res.ok) { console.error(`Management API ${res.status}: ${await res.text()}`); process.exit(3); }
const [row] = await res.json();
if (!row) { console.error(`${version} is not applied in production`); process.exit(1); }
if (row.name !== expected.name) { console.error(`DRIFT: production name ${row.name}, manifest ${expected.name}`); process.exit(1); }

const sha = createHash('sha256').update(row.sql, 'utf8').digest('hex');
if (sha !== expected.sha) { console.error(`DRIFT: hashes ${sha}, manifest says ${expected.sha}`); process.exit(1); }

const file = `${row.version}_${row.name}.sql`;
const header =
  `-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.\n` +
  `-- Applied version: ${row.version}   name: ${row.name}\n` +
  `-- SHA-256 of the applied SQL: ${sha}\n` +
  `-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.\n` +
  `-- The body below is byte-for-byte as applied; only this header was added, and it is\n` +
  `-- excluded from the checksum.\n\n`;
writeFileSync(join(MIG, file), header + row.sql, 'utf8');
console.log(`${file}  ${sha}  ${row.sql.length} chars  - matches the manifest.`);
