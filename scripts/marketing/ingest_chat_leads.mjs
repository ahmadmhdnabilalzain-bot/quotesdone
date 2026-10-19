// INGEST THE MONTHLY CHAT LEAD LIST (marketing, 19 Oct 2026).
//
// Founder ruling 1205: supplier lead finding is done by Claude in chat once a month on the subscription and
// ingested into the leads, not by the paid daily lead_sourcing job. This is that ingest door. It does no
// research and calls no paid API: it checks each email's domain has MX (DNS-over-HTTPS, free), then hands the
// list to public.fn_lead_sourcing_record, the same routine the automated job used, so dedupe (domain, email,
// phone, name), suppression, PDPL-erasure and completeness rules are the database's, not this script's.
//
//   node scripts/marketing/ingest_chat_leads.mjs leads.json [--dry]
//
// leads.json: [{company_name, website, domain, email, phone_e164, contact_name, contact_title, emirate,
//               trade_code, source_urls[]}]  -- public business listings only; every field required.
// --dry runs the whole thing in a transaction that is rolled back and prints what WOULD be promoted.
import { readFileSync } from 'node:fs';

const REF = 'htdblwldjkcgjvmqkbeh';
const [file, flag] = process.argv.slice(2);
if (!file) { console.error('usage: node scripts/marketing/ingest_chat_leads.mjs leads.json [--dry]'); process.exit(2); }
const dry = flag === '--dry';
const unesc = (s) => String(s ?? '').replace(/&amp;/g, '&').trim();

async function mx(domain) {
  for (const type of ['MX', 'A']) {
    const r = await fetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(domain)}&type=${type}`, { headers: { accept: 'application/dns-json' } }).catch(() => null);
    const j = await r?.json().catch(() => null);
    if (j?.Status === 3) return 'nxdomain';
    if (j?.Answer?.length) return 'mx_ok';
  }
  return 'no_mx';
}

const now = new Date().toISOString();
const prospects = [];
for (const raw of JSON.parse(readFileSync(file, 'utf8'))) {
  const p = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, Array.isArray(v) ? v : unesc(v)]));
  const emailDomain = p.email.split('@')[1] || '';
  prospects.push({
    ...p, email: p.email.toLowerCase(), domain: p.domain.toLowerCase().replace(/^www\./, ''),
    email_status: await mx(emailDomain), query: 'claude_chat_monthly (ruling 1205)',
    field_sources: { all: p.source_urls || [], collected_at: now, method: 'public business listing, read in chat' },
  });
}
const run = { kind: 'batch', emirate: 'UAE', trades: [...new Set(prospects.map((p) => p.trade_code))], queries: 0, serper_credits: 0, model_calls: 0, llm_cost_usd: 0 };

const tag = '$qd' + Math.random().toString(36).slice(2, 8) + '$';
const expr = `public.fn_lead_sourcing_record(${tag}${JSON.stringify(run)}${tag}::jsonb, ${tag}${JSON.stringify(prospects)}${tag}::jsonb)`;
// A dry run raises with the result so the transaction, and every row it wrote, rolls back.
const query = dry
  ? `do $d$ declare r jsonb; begin r := ${expr}; raise exception 'DRY<<%>>', r; end $d$;`
  : `select ${expr} r`;

const mgmt = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
  method: 'POST', headers: { Authorization: 'Bearer ' + mgmt, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
});
const out = await res.text();
const m = out.match(/DRY<<(.*)>>/s);
console.log(m ? 'DRY RUN (rolled back): ' + m[1].replace(/\\"/g, '"') : out);
console.log('mx:', prospects.map((p) => `${p.domain}=${p.email_status}`).join(' '));
