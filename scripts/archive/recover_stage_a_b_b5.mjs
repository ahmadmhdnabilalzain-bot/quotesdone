// Recover the Stage A / B / B.5 migrations verbatim from
// supabase_migrations.schema_migrations into supabase/migrations/.
//
// The expected version, name and SHA-256 are read from the COMMITTED manifest
// supabase/migrations/STAGE_A_B_B5_RECOVERY_MANIFEST.md, which landed before this script ran.
// Nothing here can quietly widen what counts as acceptable.
//
//   node scripts/archive/recover_stage_a_b_b5.mjs
//
// Requires a Supabase personal access token at %USERPROFILE%\.supabase\access-token
// or SUPABASE_ACCESS_TOKEN. The token is read, used, and never written anywhere.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const MIG_DIR = join(process.cwd(), 'supabase', 'migrations');
const MANIFEST = join(MIG_DIR, 'STAGE_A_B_B5_RECOVERY_MANIFEST.md');

// | 1 | 20260802165328 | name | `sha` | 14,711 |
const EXPECTED = readFileSync(MANIFEST, 'utf8')
  .split('\n')
  .map(l => l.match(/^\|\s*(\d+)\s*\|\s*(\d{14})\s*\|\s*([a-z0-9_]+)\s*\|\s*`([0-9a-f]{64})`/))
  .filter(Boolean)
  .map(m => ({ idx: +m[1], version: m[2], name: m[3], sha: m[4] }))
  .sort((a, b) => a.idx - b.idx);

if (EXPECTED.length === 0) { console.error('manifest parsed to zero rows'); process.exit(2); }
console.log(`manifest: ${EXPECTED.length} migrations expected`);

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
              from supabase_migrations.schema_migrations
             where version in (${EXPECTED.map(e => `'${e.version}'`).join(',')})
             order by version`,
  }),
});
if (!res.ok) { console.error(`Management API ${res.status}: ${await res.text()}`); process.exit(3); }
const rows = await res.json();

if (!existsSync(MIG_DIR)) mkdirSync(MIG_DIR, { recursive: true });

let ok = 0, bad = 0;
console.log('idx  repo file                                                             sha256   bytes');
EXPECTED.forEach((exp, i) => {
  const r = rows.find(x => x.version === exp.version);
  if (!r) { console.error(`MISSING in production: ${exp.version} ${exp.name}`); bad++; return; }
  if (r.name !== exp.name) {
    console.error(`DRIFT: ${exp.version} is named ${r.name}, manifest says ${exp.name}`); bad++; return;
  }
  const sha = createHash('sha256').update(r.sql, 'utf8').digest('hex');
  if (sha !== exp.sha) {
    console.error(`DRIFT: ${r.name} hashes ${sha}, manifest says ${exp.sha}`); bad++; return;
  }
  // filename IS the applied version, so `supabase db push` sees these as already applied
  const file = `${r.version}_${r.name}.sql`;
  const header =
    `-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.\n` +
    `-- Applied version: ${r.version}   name: ${r.name}\n` +
    `-- SHA-256 of the applied SQL: ${sha}\n` +
    `-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.\n` +
    `-- The body below is byte-for-byte as applied; only this header was added, and it is\n` +
    `-- excluded from the checksum.\n\n`;
  writeFileSync(join(MIG_DIR, file), header + r.sql, 'utf8');
  console.log(`${String(i + 1).padStart(2, '0')}   ${file.padEnd(68)} ${sha.slice(0, 8)} ${r.sql.length}`);
  ok++;
});

const extra = rows.filter(r => !EXPECTED.some(e => e.version === r.version));
for (const r of extra) { console.error(`UNEXPECTED in production: ${r.version} ${r.name}`); bad++; }

console.log(`\n${ok} recovered and checksum-verified, ${bad} drifted or missing, ${rows.length} returned.`);
if (bad > 0 || ok !== EXPECTED.length) {
  console.error('RECOVERY INCOMPLETE - do not commit. Report the drift above.'); process.exit(1);
}
console.log(`All ${ok} match the manifest. Safe to commit.`);
