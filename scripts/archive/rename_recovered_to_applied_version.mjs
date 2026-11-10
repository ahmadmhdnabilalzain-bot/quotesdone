// The recovered files were first written with a repository sequence number
// (2026080222NN / 2026080223NN) rather than their applied version. Two problems:
//
//   1. Filename order was inverted against applied order - Stage B.6 (22NN) sorted before
//      Stage A/B/B.5 (23NN), which is the reverse of how they ran.
//   2. Those names are 12 digits, not 14, and none of them exists in schema_migrations. A
//      `supabase db push` would therefore treat all 44 as NEW migrations and try to apply an
//      already-applied Stage A on top of itself.
//
// Renaming each file to <applied version>_<name>.sql fixes both: order becomes applied order, and
// push sees them as already applied. The applied version is read from each file's own header, so
// the rename cannot invent one.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const MIG = join(process.cwd(), 'supabase', 'migrations');
const files = readdirSync(MIG).filter(f => /^2026080222\d{2}_|^2026080223\d{2}_/.test(f) && f.endsWith('.sql')).sort();
let n = 0;
for (const f of files) {
  const raw = readFileSync(join(MIG, f), 'utf8');
  const m = raw.match(/^-- Applied version: (\d{14})   name: ([a-z0-9_]+)$/m);
  if (!m) { console.error(`${f}: no applied-version header, refusing to rename`); process.exit(1); }
  const target = `${m[1]}_${m[2]}.sql`;
  if (target === f) continue;
  execFileSync('git', ['mv', `supabase/migrations/${f}`, `supabase/migrations/${target}`], { stdio: 'inherit' });
  n++;
}
console.log(`renamed ${n} of ${files.length}`);
