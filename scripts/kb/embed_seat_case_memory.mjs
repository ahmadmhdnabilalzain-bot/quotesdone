// DRAIN THE CASE MEMORY'S EMBED QUEUE. Seat: it_engineer. 23 Sep 2026.
//
// The heartbeat (resilience_ping caseMemory step) embeds eight cases per 15-minute tick. The day-one
// backfill is ~430 rows (343 IT findings, 54 expense classifications, the CEO's decisions, three
// inquiries), which the tick would take about 14 hours to reach. This drains it now, the same way:
// claim with a lease (fn_case_embed_claim), embed through ai_gateway {action:'embed'} — the free
// in-region gte-small session, NOT OpenRouter — and write back only if the text is unchanged
// (fn_case_embed_write). Safe to re-run; safe alongside the tick (leases are disjoint).
//
//   node scripts/kb/embed_seat_case_memory.mjs
import { sql, PROJECT_REF } from '../lib/db.mjs';

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";

let embedded = 0, failed = 0;
for (;;) {
  const rows = await sql(`select * from public.fn_case_embed_claim(50)`);
  if (!rows.length) break;
  for (const r of rows) {
    const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'embed_seat_case_memory', action: 'embed', text: r.text }),
    });
    const j = res.ok ? await res.json() : null;
    const v = j?.embedding ? (typeof j.embedding === 'string' ? j.embedding : JSON.stringify(j.embedding)) : null;
    if (!v) { failed++; continue; }
    const w = await sql(`select public.fn_case_embed_write(${r.id}, ${q(v)}::vector(384), ${q(r.hash)}) as ok`);
    if (w[0]?.ok) embedded++;
  }
  if (failed > 20 && embedded === 0) break;   // the gateway is down: stop, do not spin on leases
}
const left = (await sql(`select count(*)::int n from public.seat_case_memory where embedding is null`))[0].n;
console.log(JSON.stringify({ embedded, failed, still_unembedded: left }));
process.exit(failed && !embedded ? 1 : 0);
