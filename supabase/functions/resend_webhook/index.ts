// resend_webhook v4 - receives Resend delivery events. Hard bounce or spam complaint => add the recipient
// to email_suppressions so we never email them again (protects sender reputation + PDPL).
//
// SECURITY FIX 19 Jul 2026 ---------------------------------------------------------------------
// v3 authenticated ONLY on a shared secret in the QUERY STRING (?key=...). That is weak proof of
// origin: the full URL including the secret is stored in the Resend dashboard, appears in browser
// history and referrer headers, and is written to any proxy or access log that records request
// lines. Anyone who obtained it could forge bounce/complaint events and add ARBITRARY addresses to
// email_suppressions - permanently blocking real suppliers and customers from ever receiving mail
// from us, silently.
//
// v4 verifies the SVIX SIGNATURE that Resend actually signs each delivery with (svix-id,
// svix-timestamp, svix-signature), using the endpoint's signing secret now stored in
// app_secrets.resend_webhook_signing_secret. This is real cryptographic proof of origin and cannot
// be replayed outside a 5-minute window. The ?key= check is KEPT as a second factor, so both must
// pass - the query secret alone is no longer sufficient.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'resend_webhook', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the webhook */ }
}
function emailsOf(d: any): string[] {
  const out = new Set<string>();
  const push = (v: any) => { if (typeof v === 'string' && /@/.test(v)) out.add(v.toLowerCase().trim()); };
  if (d) { push(d.to); if (Array.isArray(d.to)) d.to.forEach(push); push(d.email); push(d.recipient); if (Array.isArray(d.recipients)) d.recipients.forEach(push); }
  return [...out];
}

// Constant-time string compare so a forger cannot time-probe toward a valid signature.
function timingSafeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// Svix/Standard-Webhooks verification: base64(HMAC-SHA256(secret, "<id>.<timestamp>.<rawBody>")).
async function verifySvix(secret: string, rawBody: string, h: Headers): Promise<{ ok: boolean; reason: string }> {
  const id = h.get('svix-id') || h.get('webhook-id');
  const ts = h.get('svix-timestamp') || h.get('webhook-timestamp');
  const sigHeader = h.get('svix-signature') || h.get('webhook-signature');
  if (!id || !ts || !sigHeader) return { ok: false, reason: 'missing svix-id / svix-timestamp / svix-signature headers - not a genuine Resend delivery' };
  const skew = Math.abs(Date.now() / 1000 - Number(ts));
  if (!Number.isFinite(skew)) return { ok: false, reason: 'unparseable svix-timestamp' };
  if (skew > 300) return { ok: false, reason: 'timestamp is ' + Math.round(skew) + 's away from now, outside the 5 minute replay window' };
  try {
    const b64 = secret.startsWith('whsec_') ? secret.slice(6) : secret;
    const keyBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const mac = new Uint8Array(await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(id + '.' + ts + '.' + rawBody)));
    const expected = btoa(String.fromCharCode(...mac));
    // Header is a space-separated list of "v1,<base64sig>" - any one matching is valid (key rotation).
    for (const part of sigHeader.split(' ')) {
      const candidate = part.includes(',') ? part.split(',')[1] : part;
      if (candidate && timingSafeEq(candidate, expected)) return { ok: true, reason: 'ok' };
    }
    return { ok: false, reason: 'signature mismatch - payload was not signed with our endpoint secret' };
  } catch (e) { return { ok: false, reason: 'verification error: ' + String((e as Error)?.message || e).slice(0, 120) }; }
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const key = url.searchParams.get('key') || '';
    const wk = await sec('resend_webhook_key'); const ib = await sec('inbound_secret');
    if (!key || (key !== wk && key !== ib)) { await logRun('error', { authorised: 0, stage: 'query_key' }, 'resend_webhook rejected a caller whose ?key= did not match. No bounce or complaint was processed, so a genuine suppression may have been missed if this was a misconfigured endpoint URL.'); return J({ error: 'forbidden' }, 403); }

    // Read the body ONCE as text - the signature is over the exact bytes, so re-parsing is not enough.
    const raw = await req.text();

    const signingSecret = await sec('resend_webhook_signing_secret');
    if (!signingSecret) {
      await logRun('error', { authorised: 0, stage: 'no_signing_secret' }, 'resend_webhook could not read resend_webhook_signing_secret from app_secrets, so it cannot verify that this event genuinely came from Resend. The event was REJECTED rather than trusted on the query key alone. Bounce and complaint suppression is paused until the secret is restored.');
      return J({ error: 'signing secret unavailable' }, 503);
    }
    const v = await verifySvix(signingSecret, raw, req.headers);
    if (!v.ok) {
      await logRun('error', { authorised: 0, stage: 'signature', reason: v.reason }, 'resend_webhook REJECTED an event that failed Svix signature verification (' + v.reason + '). Until 19 Jul 2026 this endpoint trusted a secret in the query string alone, so a forged event could suppress any email address permanently. If this fires on genuine Resend traffic, check that the signing secret in app_secrets matches the one on the endpoint in the Resend dashboard.');
      return J({ error: 'invalid signature' }, 401);
    }

    let body: any = {}; try { body = JSON.parse(raw); } catch (_e) { body = {}; }
    const type = String(body?.type || body?.event || '').toLowerCase();
    const data = body?.data || body;
    const emails = emailsOf(data);
    let suppressed = 0;
    const isComplaint = type.includes('complain');
    const bounceType = String(data?.bounce?.type || data?.bounce_type || '').toLowerCase();
    const isHardBounce = type.includes('bounce') && bounceType !== 'transient' && bounceType !== 'soft';
    if ((isComplaint || isHardBounce) && emails.length) {
      const reason = isComplaint ? 'spam_complaint' : ('hard_bounce' + (bounceType ? ':' + bounceType : ''));
      for (const e of emails) {
        try { await admin.from('email_suppressions').upsert({ email: e, reason, source: 'resend_webhook' }, { onConflict: 'email' }); suppressed++; } catch (_e) {}
        try { await admin.from('leads').update({ invite_status: 'bounced' }).eq('email', e).is('invite_status', null); } catch (_e) {}
      }
      try { await admin.from('error_events').insert({ source: 'resend_webhook', kind: reason, severity: 'low', detail: { emails, type } }); } catch (_e) {}
    }
    await logRun('ok', { authorised: 1, type, suppressed, signature_verified: 1 }, suppressed > 0 ? ('Verified Resend event "' + type + '" suppressed ' + suppressed + ' address(es) so we stop mailing them.') : ('Verified Resend event "' + type + '" required no suppression.'));
    return J({ ok: true, type, suppressed });
  } catch (e) {
    await logRun('error', { unhandled_exception: 1 }, 'resend_webhook threw an unhandled exception: ' + String((e as Error)?.message || e).slice(0, 200) + ' - a bounce or complaint may not have been suppressed, so we could keep emailing a dead address and damage sender reputation.');
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});
