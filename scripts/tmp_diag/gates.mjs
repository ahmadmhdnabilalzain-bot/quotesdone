import { sql } from '../lib/db.mjs';
const r = await sql(`select * from public.fn_os_portals_gates()`);
const met = r.filter(x => x.met === true || x.state === 'MET' || x.ok === true).length;
console.log('rows ' + r.length);
for (const x of r) console.log(JSON.stringify(x).slice(0, 220));
