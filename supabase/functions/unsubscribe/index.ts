import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
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
function esc(s: string) { return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
// UNSUBSCRIBE ON GET 27 Jul 2026 -----------------------------------------------------------------
// This endpoint suppressed the address on ANY request - there was no method check at all. Every link
// prefetcher, corporate URL scanner, antivirus proxy and "safe links" rewriter that walks the footer
// link in a supplier email issues a plain GET, and each one permanently unsubscribed a real supplier
// who never clicked anything. GET must be safe; the destructive step now requires a POST. RFC 8058
// one-click unsubscribe (the List-Unsubscribe-Post header send_outbox sets) genuinely sends a POST,
// so that path still works on the first hit with no confirmation screen - only GET asks first.
function btn(href: string, label: string, colour: string) {
  return `<form method="post" action="${esc(href)}" style="margin:18px 0 0"><button type="submit" style="background:${colour};color:#fff;border:0;border-radius:10px;padding:12px 22px;font-size:15px;font-weight:700;cursor:pointer">${esc(label)}</button></form>`;
}
Deno.serve(observe('unsubscribe', async (req) => {
  const url = new URL(req.url);
  const e = (url.searchParams.get('e') || '').toLowerCase().trim();
  const t = url.searchParams.get('t') || '';
  const a = (url.searchParams.get('a') || '').toLowerCase();
  const H = { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' };
  // Query-only relative reference: it resolves against the browser's current URL and so keeps the
  // /functions/v1 prefix. url.pathname inside the edge runtime is only '/unsubscribe' and would have
  // posted the form to the wrong host path.
  const link = (act: string) => '?e=' + encodeURIComponent(e) + '&t=' + encodeURIComponent(t) + (act ? '&a=' + act : '');
  try {
    // AUDIT 9.5 (3 Aug 2026): unsubscribe links are signed with their OWN long-lived key now, not
    // the omnipotent shared secret. `unsubscribe_signing_key_legacy` is a verify-only copy of the
    // value that signed every link delivered before today, so withdrawing inbound_secret cannot
    // break a link already sitting in someone's inbox. Only the first key ever signs; see
    // send_outbox. Neither is inbound_secret, so this path no longer depends on it at all.
    const [signKey, legacyKey] = await Promise.all([
      sec('unsubscribe_signing_key'), sec('unsubscribe_signing_key_legacy'),
    ]);
    const tokenOk = !!e && !!t && (
      (!!signKey   && t === (await tok(e, signKey))) ||
      (!!legacyKey && t === (await tok(e, legacyKey)))
    );
    if (!tokenOk) {
      // A REFUSED OPT-OUT IS RECORDED, NEVER LOST (19 Oct 2026, customer_support, CS-C09). The 30 Sep audit counted 125
      // refusals in 146 calls and nothing kept the address of any of them, so a real person's opt-out on a rewritten
      // link could not even be looked for. Every refusal that names an address is kept (throttled at the table); the
      // daily delivery-health duty (fn_customer_support_delivery_health_tick) sends an address we mailed a freshly signed
      // link and records the opt-out ONLY on proof of ownership. A refusal alone never unsubscribes anyone. A failed write
      // never changes the page.
      if (e) {
        await admin.from('unsubscribe_refusal').insert({ email: e.slice(0, 320), method: req.method, token_present: !!t,
          user_agent: (req.headers.get('user-agent') || '').slice(0, 300) }).then(() => {}, () => {});
      }
      return new Response(page('Invalid link', 'This unsubscribe link is invalid or has expired. If you keep receiving emails, write to unsubscribe@mail.quotesdone.com from that address and it is removed automatically.'), { status: 400, headers: H });
    }
    const { data: cur } = await admin.from('email_suppressions').select('email,reason,source').eq('email', e).maybeSingle();
    if (req.method !== 'POST') {
      if (!cur) return new Response(page('Unsubscribe', `Please confirm you want to stop receiving invitations and reminders at <b>${esc(e)}</b>.` + btn(link(''), 'Unsubscribe me', '#b91c1c')), { status: 200, headers: H });
      if (cur.reason === 'unsubscribe') return new Response(page('Already unsubscribed', `<b>${esc(e)}</b> is already unsubscribed and receives no invitations or reminders from QuotesDone.<br><br>Changed your mind? You can put yourself back on the list right here.` + btn(link('resub'), 'Resubscribe me', '#0d9488')), { status: 200, headers: H });
      return new Response(page('Not currently emailed', `We are not sending anything to <b>${esc(e)}</b>. Mail to this address was rejected or reported, so we stopped automatically - that was not an unsubscribe you made, and it is not something this page can undo. If the mailbox works now, email info@quotesdone.com and we will restore it.`), { status: 200, headers: H });
    }
    // NO WAY BACK 27 Jul 2026 - nothing anywhere in the codebase could DELETE from email_suppressions,
    // yet this page told suppliers we would "add you back". That promise was impossible to keep, so
    // here is the path that keeps it. Resubscribe is scoped to a preference row (reason 'unsubscribe', from this
    // link or, since 22 Sep 2026, from an unsubscribe email; the signed token proves the address). A hard bounce or spam complaint recorded by resend_webhook is a deliverability
    // fact rather than a preference - un-suppressing one from a link would re-mail a dead box and
    // damage the sending domain for every other supplier - so those say so honestly instead.
    // Authorisation is the same signed token that authorises the unsubscribe; no new secret.
    if (a === 'resub') {
      const { data: del } = await admin.from('email_suppressions').delete().eq('email', e).eq('reason', 'unsubscribe').select('email');
      if (del && del.length) return new Response(page('Resubscribed', `<b>${esc(e)}</b> is back on the list and will receive invitations and reminders again.<br><br>You can unsubscribe again at any time from the link in any of our emails.`), { status: 200, headers: H });
      return new Response(page('Nothing to restore', `<b>${esc(e)}</b> was not removed by an unsubscribe link, so this page cannot restore it. If mail to this address bounced and the mailbox works now, email info@quotesdone.com and we will put you back.`), { status: 200, headers: H });
    }
    await admin.from('email_suppressions').upsert({ email: e, reason: 'unsubscribe', source: 'link' }, { onConflict: 'email' });
    return new Response(page('Unsubscribed', `<b>${esc(e)}</b> has been removed.<br><br>You will no longer receive invitations or reminders from QuotesDone. Sign-in codes and messages about requests and quotes you are part of still reach you. Sorry to see you go — if this was a mistake, use the button below or reply to any earlier email.` + btn(link('resub'), 'Resubscribe me', '#0d9488')), { status: 200, headers: H });
  } catch (_e) {
    return new Response(page('Something went wrong', 'We could not process that right now. Please write to unsubscribe@mail.quotesdone.com from that address and it is removed automatically.'), { status: 200, headers: H });
  }
}));
