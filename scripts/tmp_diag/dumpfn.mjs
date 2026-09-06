import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';
const r = await q(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='${process.argv[2]}'`);
writeFileSync(process.argv[3], r[0].prosrc);
console.log('bytes', r[0].prosrc.length);
