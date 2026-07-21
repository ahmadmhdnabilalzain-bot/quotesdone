// supplier_ack v1 — one-click 'I have contacted the customer' from the nudge email.
// GET ?tx=<transaction_id>&token=<ack_token> -> sets transactions.supplier_ack_at, stops nudges.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const NAVY = '#0c2330';
function page(title: string, msg: string, ok: boolean){
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} · QuotesDone</title>
<style>body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;background:#0a1a24;color:#eaf2f6;display:flex;min-height:100vh;align-items:center;justify-content:center}
.card{max-width:460px;margin:20px;background:#0f2735;border:1px solid #1d3a4a;border-radius:16px;overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.45)}
.hd{background:${NAVY};padding:22px 26px;border-bottom:2px solid #17b3a6}.hd b{font-size:19px;letter-spacing:.3px}
.bd{padding:24px 26px;line-height:1.6}.ic{font-size:40px;margin-bottom:8px}.mut{color:#9fb4c0;font-size:13px;margin-top:16px}
a{color:#2DD4BF}</style></head><body><div class="card"><div class="hd"><b>QuotesDone</b></div>
<div class="bd"><div class="ic">${ok?'✅':'⚠️'}</div><div style="font-size:17px;font-weight:600;margin-bottom:6px">${title}</div><div>${msg}</div>
<div class="mut">If you have any issue, email <a href="mailto:supplier@quotesdone.com">supplier@quotesdone.com</a>.</div></div></div></body></html>`;
}
Deno.serve(async (req) => {
  const url = new URL(req.url);
  const tx = (url.searchParams.get('tx') || '').trim();
  const token = (url.searchParams.get('token') || '').trim();
  const H = { 'Content-Type': 'text/html; charset=utf-8' };
  const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!tx || !uuidRe.test(token)) return new Response(page('Link not valid','This confirmation link is incomplete or has expired. Please use the link from your latest QuotesDone reminder email.',false), { status: 400, headers: H });
  try {
    const { data: t } = await admin.from('transactions').select('id,supplier_ack_at,ack_token,inquiry_id').eq('id', tx).maybeSingle();
    if (!t || String(t.ack_token) !== token) return new Response(page('Link not valid','We could not match this confirmation link. Please use the link from your latest QuotesDone reminder email.',false), { status: 404, headers: H });
    if (!t.supplier_ack_at) {
      await admin.from('transactions').update({ supplier_ack_at: new Date().toISOString() }).eq('id', tx);
      try { await admin.from('notifications').insert({ type:'supplier_ack', to_role:'admin', inquiry_id: t.inquiry_id, subject:'Supplier confirmed they contacted the customer', body:'A supplier clicked the confirmation link for a revealed inquiry, confirming they have contacted the paying customer. No further nudges will be sent for this reveal.' }); } catch(_e) {}
    }
    return new Response(page('Thank you — noted','We have recorded that you have contacted this customer. You will not receive further reminders for this inquiry. Please continue the conversation with the customer to win the job.',true), { headers: H });
  } catch (_e) {
    return new Response(page('Something went wrong','We could not record your confirmation right now. Please try again shortly, or reply to the reminder email.',false), { status: 500, headers: H });
  }
});
