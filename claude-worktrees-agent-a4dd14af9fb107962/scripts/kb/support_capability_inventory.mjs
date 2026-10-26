// WHAT THE SUPPORT AGENT CAN ACTUALLY STAND ON
//
// The build spec is explicit: "Record each capability as verified_ready, exists_but_unverified,
// missing, disabled or incompatible. Do not infer readiness from a historical report."
//
// Today that warning has teeth. The organisation, every workflow and 234 of 235 scheduled jobs were
// deleted a few hours ago, so any report written before this afternoon describes a company that no
// longer exists. Every line below is read from the live database, the live cron table or the files
// on disk in this run.
//
// The distinction that matters most here is between EXISTS and WORKS. A routine that is present is
// exists_but_unverified: it has a body, and nothing in this inventory proves it does what its name
// says. Only a capability driven end to end in this session earns verified_ready, and this script
// does not drive anything -- it reads. So it reports at most exists_but_unverified, on purpose.
//
//   node scripts/kb/support_capability_inventory.mjs

import { existsSync, readdirSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const tables = new Set((await sql(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','v','m')`)).map((x) => x.relname));
const routines = new Set((await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'`)).map((x) => x.proname));
const edge = existsSync('supabase/functions')
  ? new Set(readdirSync('supabase/functions', { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name))
  : new Set();
const jobs = await sql(`select jobname, active from cron.job`);
const secrets = new Set((await sql(`select key from public.app_secrets`)).map((x) => x.key));

const rows = async (t) => {
  if (!tables.has(t)) return null;
  try { const r = await sql(`select count(*) n from public.${t}`); return Number(r[0].n); } catch { return null; }
};

const CAPS = [
  { name: 'the new CEO agent', t: ['org_role', 'org_agents'], probe: async () => {
      const r = await sql(`select role_id from public.org_role where role_id='ceo'`);
      return r.length ? 'exists_but_unverified' : 'missing'; } },
  { name: 'the customer support seat', probe: async () => {
      const r = await sql(`select role_id from public.org_role where role_id='customer_support'`);
      return r.length ? 'exists_but_unverified' : 'missing'; } },
  { name: 'CEO task / report interface', probe: async () => {
      const have = ['ceo_decision', 'ceo_decision_log'].filter((t) => tables.has(t));
      return have.length === 2 ? 'exists_but_unverified' : 'missing'; } },
  { name: 'customer records', t: ['customers'] },
  { name: 'supplier records', t: ['leads'] },
  { name: 'inquiry records', t: ['inquiries'] },
  { name: 'quotation records', t: ['quotes'] },
  { name: 'company knowledge retrieval', fn: ['fn_faq_answer'], t: ['company_faq', 'kb_chunks'] },
  { name: 'CEO knowledge retrieval', fn: ['fn_ceo_knowledge_search', 'fn_ceo_context'] },
  { name: 'OpenRouter gateway', edge: ['ai_gateway'], secret: ['cred_fn_ai'] },
  { name: 'Twilio WhatsApp sender', edge: ['wa_inbound'], secret: ['twilio_wa_from', 'wa_autoreply_enabled'] },
  { name: 'WhatsApp brain (route / turn / facts)', fn: ['fn_wa_route', 'fn_wa_record_turn', 'fn_wa_fact_pack'] },
  { name: 'WhatsApp approved templates', t: ['wa_template_registry'] },
  { name: 'email sending', edge: ['email_cron', 'send_outbox'] },
  { name: 'email receiving (inbound)', edge: ['resend_inbound'] },
  { name: 'notification outbox', t: ['notifications'] },
  { name: 'payments / transactions', t: ['transactions', 'stripe_events'] },
  { name: 'invoices', t: ['reveal_invoices'] },
  { name: 'comparison report generator', fn: ['fn_quote_compare'], edge: ['quote_compare'] },
  { name: 'report / document export', edge: ['fn_wa_pdf', 'documents'] },
  { name: 'licence verification', fn: ['fn_licence_expiry_sweep', 'fn_supplier_licence_gate'] },
  { name: 'licence renewal intake', t: ['licence_renewal_ask', 'wa_document_intake'] },
  { name: 'supplier / customer portal', edge: ['supplier_portal', 'supplier_api', 'os_api'] },
  { name: 'scheduled delivery (cron)', probe: async () => (jobs.length ? 'disabled' : 'missing') },
];

console.log('CAPABILITY INVENTORY  ·  read live, ' + new Date().toISOString().slice(0, 10));
console.log('(nothing here can read verified_ready: this script reads, it does not drive)\n');
const missing = [];
for (const c of CAPS) {
  let status, detail = [];
  if (c.probe) {
    status = await c.probe();
  } else {
    const haveT = (c.t || []).filter((t) => tables.has(t));
    const haveF = (c.fn || []).filter((f) => routines.has(f));
    const haveE = (c.edge || []).filter((e) => edge.has(e));
    const haveS = (c.secret || []).filter((s) => secrets.has(s));
    const wantN = (c.t || []).length + (c.fn || []).length + (c.edge || []).length + (c.secret || []).length;
    const haveN = haveT.length + haveF.length + haveE.length + haveS.length;
    status = haveN === 0 ? 'missing' : haveN < wantN ? 'exists_but_unverified (partial)' : 'exists_but_unverified';
    for (const t of (c.t || [])) { const n = await rows(t); detail.push(t + (n === null ? ' MISSING' : ' ' + n + ' rows')); }
    for (const f of (c.fn || [])) detail.push(f + (routines.has(f) ? '()' : ' MISSING'));
    for (const e of (c.edge || [])) detail.push(e + (edge.has(e) ? '/' : ' MISSING'));
    for (const s of (c.secret || [])) detail.push(s + (secrets.has(s) ? '=set' : ' MISSING'));
  }
  if (status.startsWith('missing')) missing.push(c.name);
  console.log('  ' + status.padEnd(32) + c.name + (detail.length ? '  [' + detail.join(', ') + ']' : ''));
}
console.log('\nscheduled jobs: ' + jobs.length + ' (' + jobs.filter((j) => j.active).length + ' active) — the estate is on hold');
if (missing.length) console.log('MISSING: ' + missing.join(', '));
process.exit(0);
