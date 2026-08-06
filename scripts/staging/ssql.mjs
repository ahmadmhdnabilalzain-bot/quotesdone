// Read STAGING via the management API. Mirror of scripts/qsql.mjs, which reads production only.
import { readFileSync } from 'node:fs';
import { mgmtRead } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';
const f = process.argv[2];
if (!f) { console.error('usage: node scripts/staging/ssql.mjs <file.sql>'); process.exit(2); }
const rows = await mgmtRead(STAGE, readFileSync(f, 'utf8'), 'ssql');
for (const r of rows) console.log(JSON.stringify(r));
console.log(`-- rows: ${rows.length}`);
