import { sql } from '../scripts/lib/db.mjs';
const q = process.argv.slice(2).join(' ');
console.log(JSON.stringify(await sql(q), null, 1));
