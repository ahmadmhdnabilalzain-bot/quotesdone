import { sql } from '../lib/db.mjs';
const q = process.argv.slice(2).join(' ');
const r = await sql(q);
for (const row of r) {
  for (const [k,v] of Object.entries(row)) console.log(`${k}: ${typeof v === 'object' ? JSON.stringify(v) : v}`);
  console.log('---');
}
