// wa_template_setup - manages the WhatsApp Content template used for document-expiry notices:
// create it, submit it for Meta approval, register the SID in app_secrets, and inspect delivery.
//
// WHY THIS IS A FUNCTION RATHER THAN A SCRIPT: the Twilio API key lives in app_secrets. Running
// server-side means the credential is read and used inside the platform and never leaves it.
// Every response returns status and SIDs only - no secret is ever echoed.
//
// META TEMPLATE RULE LEARNED THE HARD WAY: the first submission was rejected with
//   "Variables can't be at the start or end of the template."
// because the body finished with {{2}}. Both bodies below open AND close with literal text.
// Keep that shape if you edit the copy.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string | undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

const KEY = 'supplier_doc_expiry';

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'wa_template_setup');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    const acct = await sec('twilio_account_sid');
    const ks = await sec('twilio_api_key_sid');
    const kk = await sec('twilio_api_key_secret');
    if (!ks || !kk) return J({ error: 'twilio_not_configured' }, 503);
    const auth = 'Basic ' + btoa(ks + ':' + kk);
    const action = String(body.action || 'status');

    // Delivery inspection. Used to confirm where a message actually ended up - an API-level
    // success only means Twilio accepted it, not that anyone received it.
    if (action === 'msg_check') {
      const to = String(body.to || '');
      const url = 'https://api.twilio.com/2010-04-01/Accounts/' + acct + '/Messages.json?To=' + encodeURIComponent('whatsapp:' + to) + '&PageSize=5';
      const r = await fetch(url, { headers: { 'Authorization': auth } });
      const j = await r.json().catch(() => ({}));
      const msgs = (j?.messages || []).map((m: any) => ({
        sid: m.sid, to: m.to, status: m.status, error_code: m.error_code, error_message: m.error_message,
        date_sent: m.date_sent, num_segments: m.num_segments, price: m.price }));
      return J({ ok: r.ok, http: r.status, count: msgs.length, messages: msgs });
    }

    if (action === 'delete') {
      const sid = String(body.content_sid || '');
      if (!/^HX[0-9a-f]{32}$/i.test(sid)) return J({ error: 'bad_sid' }, 400);
      const r = await fetch('https://content.twilio.com/v1/Content/' + sid, { method: 'DELETE', headers: { 'Authorization': auth } });
      return J({ ok: r.ok, http: r.status, deleted: sid });
    }

    if (action === 'create') {
      const lang = String(body.language || 'en');
      const isAr = lang === 'ar';
      // {{1}} = what is expiring, including the date.  {{2}} = where to fix it.
      const text = isAr
        ? 'تذكير من QuotesDone: {{1}}. يُرجى تجديدها للاستمرار في استقبال طلبات العملاء. حدّثها هنا: {{2}} شكرًا لك.'
        : 'QuotesDone reminder: {{1}}. Please renew it to keep receiving customer requests. You can update it here: {{2}} Thank you.';
      const sample1 = isAr ? 'تنتهي رخصتك التجارية في 2026-08-01' : 'your trade licence expires on 2026-08-01';
      const stamp = Date.now().toString(36);

      const createRes = await fetch('https://content.twilio.com/v1/Content', {
        method: 'POST', headers: { 'Authorization': auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ friendly_name: 'quotesdone_' + KEY + '_' + lang + '_' + stamp, language: lang,
          variables: { '1': sample1, '2': 'https://quotesdone.com/portal' },
          types: { 'twilio/text': { body: text } } }) });
      const created = await createRes.json().catch(() => ({}));
      if (!createRes.ok) return J({ step: 'create', ok: false, http: createRes.status, error: created?.message || created }, 502);
      const sid = String(created?.sid || '');
      if (!sid) return J({ step: 'create', ok: false, error: 'no sid returned', raw: created }, 502);

      // UTILITY is correct: a transactional notice about the recipient's own account, not marketing.
      const apprName = ('quotesdone_' + KEY + '_' + lang + '_' + stamp).toLowerCase().replace(/[^a-z0-9_]/g, '_');
      const apprRes = await fetch('https://content.twilio.com/v1/Content/' + sid + '/ApprovalRequests/whatsapp', {
        method: 'POST', headers: { 'Authorization': auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: apprName, category: 'UTILITY' }) });
      const appr = await apprRes.json().catch(() => ({}));

      let registered = false; let sids: Record<string, any> = {};
      try {
        sids = JSON.parse((await sec('wa_template_sids')) || '{}');
        sids[KEY] = { ...(sids[KEY] || {}), [lang]: sid };
        const { error } = await admin.from('app_secrets').update({ value: JSON.stringify(sids) }).eq('key', 'wa_template_sids');
        registered = !error;
      } catch (_e) { /* reported below */ }

      return J({ step: 'create', ok: true, language: lang, content_sid: sid, approval_name: apprName,
        approval_http: apprRes.status, approval_status: appr?.status || appr?.whatsapp?.status || null,
        approval_error: apprRes.ok ? null : (appr?.message || appr),
        registered_in_app_secrets: registered, template_keys_now: Object.keys(sids) });
    }

    if (action === 'status') {
      const sids = JSON.parse((await sec('wa_template_sids')) || '{}');
      const entry = sids[KEY] || {};
      const out: Record<string, unknown> = {};
      for (const [lang, sid] of Object.entries(entry)) {
        const r = await fetch('https://content.twilio.com/v1/Content/' + sid + '/ApprovalRequests', { headers: { 'Authorization': auth } });
        const j = await r.json().catch(() => ({}));
        out[lang] = { sid, http: r.status, status: j?.whatsapp?.status || j?.status || null, rejection_reason: j?.whatsapp?.rejection_reason || null };
      }
      return J({ ok: true, key: KEY, registered_languages: Object.keys(entry), approvals: out });
    }

    return J({ error: 'unknown action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
