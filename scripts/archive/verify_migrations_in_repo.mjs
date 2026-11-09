// Confirm every migration applied to the database has a file in supabase/migrations/.
// Matching is by NAME, because the repo assigns its own timestamps.
//   node scripts/archive/verify_migrations_in_repo.mjs
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const tok = process.env.SUPABASE_ACCESS_TOKEN?.trim()
  ?? readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim();

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: `select version, name from supabase_migrations.schema_migrations order by version` }),
});
if (!res.ok) { console.error(await res.text()); process.exit(3); }
const applied = await res.json();

const dir = join(process.cwd(), 'supabase', 'migrations');
const files = readdirSync(dir).filter(f => f.endsWith('.sql'));
const fileNames = new Set(files.map(f => f.replace(/^\d+_/, '').replace(/\.sql$/, '')));

const missing = applied.filter(m => !fileNames.has(m.name));
console.log(`applied migrations: ${applied.length}`);
console.log(`repo migration files: ${files.length}`);
console.log(`applied but NOT in repo: ${missing.length}`);
for (const m of missing) console.log(`  MISSING  ${m.version}  ${m.name}`);

// Everything from the Phase 2 work must be present; older history predates this repo convention.
const p2Missing = missing.filter(m => /^(p2_|p1|p2_c1|ops_|kb_)/.test(m.name) && m.version >= '20260802112720');
console.log(`\nphase-2-era applied but not in repo: ${p2Missing.length}`);
for (const m of p2Missing) console.log(`  MISSING  ${m.version}  ${m.name}`);
process.exit(p2Missing.length === 0 ? 0 : 1);
