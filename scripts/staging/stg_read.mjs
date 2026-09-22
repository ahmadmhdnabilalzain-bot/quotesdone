// Read-only probe against STAGING. Mirrors scripts/qsql.mjs (which is production-only) so a change
// can be shape-checked on staging before it is applied there.
//   node scripts/staging/stg_read.mjs <file.sql>
import { readFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';
const rows = await mgmtRead(STAGE, readFileSync(process.argv[2], 'utf8'));
for (const r of rows) {
  const v = Object.values(r);
  console.log(v.length === 1 ? String(v[0]) : JSON.stringify(r));
}
console.log(`-- rows: ${rows.length} (staging ${STAGE})`);
