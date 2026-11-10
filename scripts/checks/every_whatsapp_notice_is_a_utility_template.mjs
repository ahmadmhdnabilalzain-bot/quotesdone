// EVERY WHATSAPP NOTICE IS A UTILITY TEMPLATE — owner: customer_support
//
//   node scripts/checks/every_whatsapp_notice_is_a_utility_template.mjs            # check, exit 1 on a fault
//   node scripts/checks/every_whatsapp_notice_is_a_utility_template.mjs --switch   # also swap in approved replacements
//
// Needs the Supabase management token (~/.supabase/access-token); reads the Twilio key from
// public.app_secrets inside this process and never prints it.
//
// WHY. Measured 15 Sep 2026 via Twilio's ContentAndApprovals: Meta approved three of the SIDs that
// app_secrets.wa_template_sids sends as MARKETING, while their language twins were UTILITY —
// customer_new_quote/ar, supplier_doc_expiry/ar, supplier_new_inquiry/en. Marketing costs more and
// WhatsApp may withhold it from users who opted out of promotions, so an account notice could go
// undelivered. send_whatsapp's ledger (messaging_template) only asks "approved?", never "which
// category?", so nothing noticed.
//
// WHAT IS CHECKED. The notice kinds are the keys send_whatsapp's tmplKey() can return, read from the
// source so a new kind is covered the day it is added. For every language registered for a kind in
// wa_template_sids, Twilio must say status=approved AND category=UTILITY. A kind with no SID yet is
// reported, not failed: send_whatsapp holds those rows queued and the email twin goes. Templates
// Twilio Verify creates for itself (friendly_name verify_*, AUTHENTICATION) are skipped; they are
// Verify's, not a notice.
//
// --switch. A corrected template is recorded in messaging_template with a note "replacement for
// <old sid>". When Twilio reports it approved as UTILITY, --switch writes it into wa_template_sids.
// Until then the old approved SID stays live, so nothing stops sending while Meta reviews.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { sql, lit } from '../lib/db.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const SWITCH = process.argv.includes('--switch');
const src = functionSource('send_whatsapp');
const fn = src.slice(src.indexOf('function tmplKey('), src.indexOf('function shortSummary('));
const KINDS = [...new Set([...fn.matchAll(/return '([a-z_]+)'/g)].map(m => m[1]))];
if (KINDS.length < 5) { console.error(`FAIL: read only ${KINDS.length} kinds from tmplKey(); the parser no longer matches send_whatsapp`); process.exit(1); }

const sec = Object.fromEntries((await sql(`select key, value from public.app_secrets
  where key in ('twilio_api_key_sid','twilio_api_key_secret','wa_template_sids')`)).map(r => [r.key, r.value]));
const auth = 'Basic ' + Buffer.from(`${sec.twilio_api_key_sid}:${sec.twilio_api_key_secret}`).toString('base64');
const twilio = new Map();
for (let url = 'https://content.twilio.com/v1/ContentAndApprovals?PageSize=200'; url; ) {
  const r = await fetch(url, { headers: { Authorization: auth } });
  if (!r.ok) { console.error(`FAIL: Twilio ContentAndApprovals HTTP ${r.status}`); process.exit(1); }
  const j = await r.json();
  for (const c of j.contents || []) twilio.set(c.sid, { name: c.friendly_name, ...(c.approval_requests || {}) });
  url = j.meta?.next_page_url;
}
const isUtility = t => t && t.status === 'approved' && t.category === 'UTILITY';
const isVerifys = t => t && t.category === 'AUTHENTICATION' && /^verify_/.test(t.name || '');

const sids = JSON.parse(sec.wa_template_sids || '{}');
const replacements = await sql(`select sid, template_key, lang, note from public.messaging_template
  where channel = 'whatsapp' and note like '%replacement for HX%'`);
let faults = 0;
for (const kind of KINDS) {
  const langs = sids[kind] || {};
  if (!Object.keys(langs).length) { console.log(`--   ${kind}: no SID registered (rows stay queued; email carries the notice; registering one needs the founder's Meta submission)`); continue; }
  for (const [lang, sid] of Object.entries(langs)) {
    const t = twilio.get(sid);
    if (isVerifys(t)) { console.log(`skip ${kind}/${lang} ${sid}: Verify's own authentication template`); continue; }
    if (isUtility(t)) { console.log(`ok   ${kind}/${lang} ${sid}`); continue; }
    const repl = replacements.find(r => r.template_key === kind && r.lang === lang && r.note.includes(sid));
    const rt = repl && twilio.get(repl.sid);
    if (SWITCH && isUtility(rt)) {
      await sql(`update public.app_secrets set value = jsonb_set(value::jsonb, ${lit(`{${kind},${lang}}`)}, ${lit(JSON.stringify(repl.sid))}::jsonb)::text
                 where key = 'wa_template_sids' and value::jsonb #>> ${lit(`{${kind},${lang}}`)} = ${lit(sid)}`);
      await sql(`update public.messaging_template set status = 'approved', approved_at = coalesce(approved_at, now()), last_checked_at = now() where sid = ${lit(repl.sid)}`);
      console.log(`SWITCHED ${kind}/${lang}: ${sid} -> ${repl.sid} (approved UTILITY)`);
      continue;
    }
    faults++;
    console.log(`FAIL ${kind}/${lang} ${sid}: ${t ? `${t.status} ${t.category || 'no category'}` : 'not found at Twilio'}`
      + (repl ? `; replacement ${repl.sid} is ${rt ? `${rt.status} ${rt.category}` : 'not found at Twilio'}` : '; no replacement submitted'));
  }
}
for (const key of Object.keys(sids).filter(k => !KINDS.includes(k)))
  console.log(`note ${key}: registered in wa_template_sids but send_whatsapp never sends it`);
console.log(faults ? `\n${faults} WhatsApp notice template(s) are not approved UTILITY.` : '\nEvery WhatsApp notice template is approved UTILITY.');
process.exit(faults ? 1 : 0);
