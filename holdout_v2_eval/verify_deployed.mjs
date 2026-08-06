// Verifies the DEPLOYED edge-function artefact (not the repo copy) carries the containment gate,
// and that verify_jwt was preserved. Prints booleans and counts only.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
const REF = 'htdblwldjkcgjvmqkbeh';
const tok = process.env.SUPABASE_ACCESS_TOKEN?.trim()
  || (existsSync(join(homedir(), '.supabase', 'access-token')) ? readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim() : '');
const H = { Authorization: `Bearer ${tok}` };

for (const [slug, marker] of [['os_ops', 'containment_mutations_disabled'], ['refunds_api', 'containment_control_mode_required']]) {
  const meta = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/${slug}`, { headers: H })).json();
  const bodyRes = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/${slug}/body`, { headers: H });
  const body = await bodyRes.text();
  const hasGate = body.includes(marker);
  const hasBanner = body.includes('PHASE 1 EMERGENCY CONTAINMENT');
  console.log(`${slug}: version=${meta.version} status=${meta.status} verify_jwt=${meta.verify_jwt} `
    + `deployed_bytes=${body.length} gate_present=${hasGate} banner_present=${hasBanner}`);
  if (slug === 'os_ops') {
    const ro = /const READONLY = new Set\(\[([^\]]*)\]\)/.exec(body);
    console.log(`  os_ops READONLY allow-list size = ${ro ? ro[1].split(',').length : 'NOT FOUND'}`);
    console.log(`  gate is 'if (!READONLY.has(action))' -> ${body.includes("if (!READONLY.has(action)) {\n      return J({ error: 'containment_mutations_disabled'")}`);
  }
}
