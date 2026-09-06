// ad-hoc read helper (management API). CLI branch only fires when run directly.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const REF = 'htdblwldjkcgjvmqkbeh';
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token','utf8')).trim();
export async function q(sql, attempt=0){
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`,{
    method:'POST', headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
    body: JSON.stringify({query: sql})});
  const b = await r.text();
  if ((r.status===429||r.status>=500) && attempt<7){ await new Promise(s=>setTimeout(s, 2000*(attempt+1))); return q(sql, attempt+1); }
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${b.slice(0,4000)}`);
  try { return JSON.parse(b); } catch { return b; }
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const sql = process.argv[2] === '-' ? readFileSync(0,'utf8') : process.argv[2];
  q(sql).then(r=>console.log(JSON.stringify(r,null,1))).catch(e=>{console.error(String(e)); process.exit(1);});
}
