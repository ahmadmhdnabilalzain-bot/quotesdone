import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const file = process.argv[2];
const q = fs.readFileSync(file, 'utf8');
try { const r = await sql(q); console.log('NO MARKER', JSON.stringify(r).slice(0,3000)); }
catch (e) {
  const m = String(e.message);
  const a = m.indexOf('PROBE<<');
  if (a >= 0) { let s = m.slice(a+7); const b = s.indexOf('>>'); console.log(b>=0? s.slice(0,b) : s + '  [[UNTERMINATED]]'); }
  else console.log('ERR ' + m.slice(0, 3000));
}
