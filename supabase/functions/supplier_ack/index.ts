// supplier_ack v3 — one-click 'I have contacted the customer' from the nudge email.
// GET ?tx=<transaction_id>&token=<ack_token> -> sets transactions.supplier_ack_at, stops nudges.
//
// v2 (14 Sep 2026) printed every answer in English and Arabic. v3 (10 Nov 2026, customer_support, supplier-journey
// audit): English only. Suppliers are always English, on every channel (founder ruling 1008, 28 Sep 2026); this page
// was missed because nothing imports it, so the supplier-Arabic check's import walk never reached it. It is named in
// that check's entries now. Behaviour is unchanged. Prevented by scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { requestDelivery } from '../_shared/deliver.ts';
import { sameSecret } from '../stripe_setup/webhook_plan.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const NAVY = '#0c2330';
type Msg = { title: string; msg: string };
const COPY: Record<string, { en: Msg; ok: boolean }> = {
  invalid: { ok: false,
    en: { title: 'Link not valid', msg: 'This confirmation link is incomplete or has expired. Please use the link from your latest QuotesDone reminder email.' } },
  nomatch: { ok: false,
    en: { title: 'Link not valid', msg: 'We could not match this confirmation link. Please use the link from your latest QuotesDone reminder email.' } },
  done: { ok: true,
    en: { title: 'Thank you — noted', msg: 'We have recorded that you have contacted this customer. You will not receive further reminders for this request. Please continue the conversation with the customer to win the job.' } },
  error: { ok: false,
    en: { title: 'Something went wrong', msg: 'We could not record your confirmation right now. Please try again shortly, or reply to the reminder email.' } },
};
function page(key: keyof typeof COPY) {
  const c = COPY[key];
  const block = (m: Msg) => `<div style="font-size:17px;font-weight:600;margin-bottom:6px">${m.title}</div><div>${m.msg}</div>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${c.en.title} · QuotesDone</title>
<style>body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,Tahoma,sans-serif;background:#0a1a24;color:#eaf2f6;display:flex;min-height:100vh;align-items:center;justify-content:center}
.card{max-width:460px;margin:20px;background:#0f2735;border:1px solid #1d3a4a;border-radius:16px;overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.45)}
.hd{background:${NAVY};padding:22px 26px;border-bottom:2px solid #17b3a6}.hd b{font-size:19px;letter-spacing:.3px}
.bd{padding:24px 26px;line-height:1.6}.ic{font-size:40px;margin-bottom:8px}.mut{color:#9fb4c0;font-size:13px;margin-top:16px}
a{color:#2DD4BF}</style></head><body><main class="card"><div class="hd"><b>QuotesDone</b></div>
<div class="bd"><div class="ic" aria-hidden="true">${c.ok ? '✅' : '⚠️'}</div>${block(c.en)}
<div class="mut">If you have any issue, email <a href="mailto:supplier@quotesdone.com">supplier@quotesdone.com</a>.</div></div></main></body></html>`;
}
Deno.serve(observe('supplier_ack', async (req) => {
  const url = new URL(req.url);
  const tx = (url.searchParams.get('tx') || '').trim();
  const token = (url.searchParams.get('token') || '').trim();
  const H = { 'Content-Type': 'text/html; charset=utf-8' };
  const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRe.test(tx) || !uuidRe.test(token)) return new Response(page('invalid'), { status: 400, headers: H });
  try {
    const { data: t } = await admin.from('transactions').select('id,supplier_ack_at,ack_token,inquiry_id').eq('id', tx).maybeSingle();
    // Constant-time (security checklist audit 10 Nov 2026; the last plain comparison of a token named in the 9 Nov
    // launch checklist, row 40). Prevented by ./token.test.ts.
    if (!t || !(await sameSecret(token, String(t.ack_token || '')))) return new Response(page('nomatch'), { status: 404, headers: H });
    if (!t.supplier_ack_at) {
      await admin.from('transactions').update({ supplier_ack_at: new Date().toISOString() }).eq('id', tx);
      try { await requestDelivery(admin, { type:'supplier_ack', to_role:'admin', inquiry_id: t.inquiry_id, subject:'Supplier confirmed they contacted the customer', body:'A supplier clicked the confirmation link for a revealed inquiry, confirming they have contacted the paying customer. No further nudges will be sent for this reveal.' }); } catch(_e) {}
    }
    return new Response(page('done'), { headers: H });
  } catch (_e) {
    return new Response(page('error'), { status: 500, headers: H });
  }
}));
