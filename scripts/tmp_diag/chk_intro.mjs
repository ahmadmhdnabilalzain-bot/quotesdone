import { existsSync, readFileSync } from 'node:fs';
import { FILES, introducedBy } from '../phase_d/build_migration_rollback_classification.mjs';
const bad = [];
for (const f of FILES) {
  const intro = introducedBy(f);
  if (!intro.length) continue;
  const d = 'scripts/sql/down/' + f.replace(/\.sql$/, '') + '_down.sql';
  if (!existsSync(d)) { bad.push(f + ' NO DOWN'); continue; }
  const t = readFileSync(d, 'utf8');
  for (const r of intro) if (!t.includes(r.name)) bad.push(f + ' misses ' + r.name);
}
console.log('violations:', bad.length);
bad.slice(0, 30).forEach(b => console.log(' ', b));
