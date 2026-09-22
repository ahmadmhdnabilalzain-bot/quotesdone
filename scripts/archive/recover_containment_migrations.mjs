// Recovers the applied p1c_* containment migrations from production into supabase/migrations/,
// byte-for-byte as they were applied, matching the repo's existing recovery convention.
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const REF = 'htdblwldjkcgjvmqkbeh';
const tok = process.env.SUPABASE_ACCESS_TOKEN?.trim()
  || (existsSync(join(homedir(), '.supabase', 'access-token'))
      ? readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim() : '');

const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: `select version, name, array_to_string(statements, ';' || chr(10)) as sql
              from supabase_migrations.schema_migrations
             where name like 'p1c\\_%' order by version`,
  }),
});
const rows = await res.json();
if (!Array.isArray(rows)) { console.error(JSON.stringify(rows).slice(0, 400)); process.exit(1); }

for (const r of rows) {
  const path = join('supabase', 'migrations', `${r.version}_${r.name}.sql`);
  const body = `-- Applied version: ${r.version}\n-- Recovered from production, byte-for-byte as applied.\n\n${r.sql};\n`;
  writeFileSync(path, body, 'utf8');
  console.log(`${path}  ${Buffer.byteLength(body)} bytes`);
}
console.log(`recovered ${rows.length} containment migrations`);
