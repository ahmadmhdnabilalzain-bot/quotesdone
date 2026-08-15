// Ad-hoc read against the one project, for measurement during Phase C.
//   node scripts/phase_c/q.mjs "select 1"
import { sql } from './lib/db.mjs';
const query = process.argv.slice(2).join(' ');
if (!query.trim()) { console.error('usage: node scripts/phase_c/q.mjs "<sql>"'); process.exit(2); }
console.log(JSON.stringify(await sql(query), null, 1));
