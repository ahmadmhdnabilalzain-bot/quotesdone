// Load the Step 3 IT/cybersecurity deep-knowledge snapshot into ops_knowledge (idempotent upsert).
//
// The delivery routines live in scripts/sql/it_cyber_deep_knowledge.sql. This loads the AUTHORED
// records (scripts/sql/seed/it_cyber_knowledge_seed.json) so a fresh deploy reproduces them. The
// snapshot is regenerated — kept current with the code — by re-running the workflow in
// docs/step3/regenerate_it_cyber_knowledge.workflow.js and rebuilding the seed from its output.
//
//   node scripts/seed_it_cyber_knowledge.mjs
//
// Auth: SUPABASE_ACCESS_TOKEN env, else ~/.supabase/access-token. Project: htdblwldjkcgjvmqkbeh.

import https from 'https';
import fs from 'fs';
import os from 'os';
import path from 'path';

const PROJECT = 'htdblwldjkcgjvmqkbeh';
const TOKEN = (process.env.SUPABASE_ACCESS_TOKEN
  || fs.readFileSync(path.join(os.homedir(), '.supabase', 'access-token'), 'utf8')).trim();
const SEED = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')),
  'sql', 'seed', 'it_cyber_knowledge_seed.json');

const q = (sql) => new Promise((res, rej) => {
  const d = JSON.stringify({ query: sql });
  const r = https.request(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,
    { method: 'POST', headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' } },
    x => { let b = ''; x.on('data', c => b += c); x.on('end', () => res({ status: x.statusCode, body: b })); });
  r.on('error', rej); r.write(d); r.end();
});

const rows = JSON.parse(fs.readFileSync(SEED, 'utf8'));
console.log(`loading ${rows.length} IT/cyber records into ops_knowledge`);
const BATCH = 20;
let done = 0;
for (let i = 0; i < rows.length; i += BATCH) {
  const chunk = rows.slice(i, i + BATCH);
  const sql = `select public.fn_it_security_knowledge_upsert(r.rid, r.dept, r.module, null, r.subdomain, r.title, r.content, r.kw, r.risk, r.source)
from jsonb_to_recordset($itsec$${JSON.stringify(chunk)}$itsec$::jsonb)
  as r(rid text, dept text, module text, subdomain text, title text, content text, kw text[], risk text, source text);`;
  const resp = await q(sql);
  if (resp.status >= 300) { console.error(`batch ${i} failed ${resp.status}: ${resp.body.slice(0, 300)}`); process.exit(1); }
  done += chunk.length;
  process.stdout.write(`\r loaded ${done}/${rows.length}`);
}
console.log(`\ndone: ${done} records`);
