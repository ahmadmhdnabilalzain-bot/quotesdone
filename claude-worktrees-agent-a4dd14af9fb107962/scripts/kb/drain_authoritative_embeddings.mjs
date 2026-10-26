// Drain the embedding backlog for the AUTHORITATIVE source kinds first.
//
// Measured on production 11 Aug 2026: kb_chunks 42.6% embedded and rising, but `trade` 0/1,993,
// `regulation` 0/45 and `material` 0/3. They arrived after the 115,148-row pack import, and
// kb_embed is strictly oldest-first, so UAE regulations sit ~56 hours behind a queue of pack
// chunks. Batch size is capped at 5 by the edge worker (6+ returns HTTP 546 — measured 28 Jul), so
// throughput comes from invocations, never from a bigger batch.
//
//   node scripts/kb/drain_authoritative_embeddings.mjs [--kinds=trade,regulation,material] [--max=600]
import { readFileSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh';
const arg = (n, d) => (process.argv.find(a => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
const KINDS = arg('kinds', 'trade,regulation,material').split(',').filter(Boolean);
const MAX = Number(arg('max', 600));
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const q = async (sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) throw new Error(`${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};
const remaining = async () => Number((await q(
  `select count(*) n from public.kb_chunks where embedding_gte is null
    and source_kind in (${KINDS.map(k => `'${k.replace(/'/g, "''")}'`).join(',')})`))[0].n);

const secret = (await q(`select value from public.app_secrets where key='cred_cron_knowledge'`))[0].value;

let before = await remaining();
console.log(`unembedded in [${KINDS.join(', ')}]: ${before}`);
let calls = 0, e546 = 0;
while (calls < MAX) {
  const left = await remaining();
  if (left === 0) break;
  const r = await fetch(`https://${PROD}.supabase.co/functions/v1/kb_embed`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, limit: 5, source_kinds: KINDS }),
  });
  calls++;
  if (r.status === 546) { e546++; await new Promise(s => setTimeout(s, 3000)); continue; }
  if (calls % 20 === 0) console.log(`  ${calls} invocations, ${left} still unembedded`);
  await new Promise(s => setTimeout(s, 300));
}
const after = await remaining();
console.log(`DONE: ${before} -> ${after} unembedded after ${calls} invocation(s) (${e546} x HTTP 546)`);
const cov = await q(`select coalesce(source_kind,'(null)') k, count(*) n,
                            count(*) filter (where embedding_gte is not null) e
                       from public.kb_chunks group by 1 order by 2 desc`);
for (const r of cov) console.log(`  ${String(r.k).padEnd(12)} ${String(r.e).padStart(7)} / ${String(r.n).padEnd(7)} ${(100 * r.e / r.n).toFixed(1)}%`);
