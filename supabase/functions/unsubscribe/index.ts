import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function tok(email: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(email.toLowerCase()));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 20);
}
function page(title: string, msg: string) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body style="margin:0;background:#f6f7f9;font-family:Arial,Helvetica,sans-serif;color:#1f2937"><div style="max-width:480px;margin:60px auto;padding:24px"><div style="background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:28px;text-align:center"><div style="font-weight:800;font-size:20px;color:#0d9488;margin-bottom:14px">Quotes<span style="color:#111827">Done</span></div><div style="font-size:15px;line-height:1.6">${msg}</div></div><div style="text-align:center;color:#9ca3af;font-size:12px;margin-top:14px">QuotesDone — UAE sourcing marketplace</div></div></body></html>`;
}
Deno.serve(async (req) => {
  const url = new URL(req.url);
  const e = (url.searchParams.get('e') || '').toLowerCase().trim();
  const t = url.searchParams.get('t') || '';
  const H = { 'Content-Type': 'text/html; charset=utf-8' };
  try {
    const secret = await sec('inbound_secret');
    if (!e || !t || !secret || t !== (await tok(e, secret))) {
      return new Response(page('Invalid link', 'This unsubscribe link is invalid or has expired. If you keep receiving emails, reply to any of them and we will remove you.'), { status: 400, headers: H });
    }
    await admin.from('email_suppressions').upsert({ email: e, reason: 'unsubscribe', source: 'link' }, { onConflict: 'email' });
    return new Response(page('Unsubscribed', `<b>${e}</b> has been removed.<br><br>You will no longer receive sourcing requests from QuotesDone. Sorry to see you go — if this was a mistake, just reply to any earlier email and we'll add you back.`), { status: 200, headers: H });
  } catch (_e) {
    return new Response(page('Something went wrong', 'We could not process that right now. Please reply to any of our emails and we will remove you manually.'), { status: 200, headers: H });
  }
});
