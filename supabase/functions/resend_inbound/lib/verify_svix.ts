// resend_inbound: webhook authenticity: the Svix signature check. Moved out of index.ts unchanged (9 Nov 2026).


// Webhook authenticity ------------------------------------------------------
export function timingSafeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
// Svix/Standard-Webhooks: base64(HMAC-SHA256(secret, "<id>.<timestamp>.<rawBody>")).
export async function verifySvix(secret: string, rawBody: string, h: Headers): Promise<{ ok: boolean; reason: string }> {
  const id = h.get('svix-id') || h.get('webhook-id');
  const ts = h.get('svix-timestamp') || h.get('webhook-timestamp');
  const sigHeader = h.get('svix-signature') || h.get('webhook-signature');
  if (!id || !ts || !sigHeader) return { ok: false, reason: 'missing svix-id / svix-timestamp / svix-signature headers - not a genuine Resend delivery' };
  const skew = Math.abs(Date.now() / 1000 - Number(ts));
  if (!Number.isFinite(skew)) return { ok: false, reason: 'unparseable svix-timestamp' };
  if (skew > 300) return { ok: false, reason: 'timestamp is ' + Math.round(skew) + 's from now, outside the 5 minute replay window' };
  try {
    const b64 = secret.startsWith('whsec_') ? secret.slice(6) : secret;
    const keyBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const mac = new Uint8Array(await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(id + '.' + ts + '.' + rawBody)));
    const expected = btoa(String.fromCharCode(...mac));
    for (const part of sigHeader.split(' ')) {
      const candidate = part.includes(',') ? part.split(',')[1] : part;
      if (candidate && timingSafeEq(candidate, expected)) return { ok: true, reason: 'ok' };
    }
    return { ok: false, reason: 'signature mismatch - payload was not signed with our endpoint secret' };
  } catch (e) { return { ok: false, reason: 'verification error: ' + String((e as Error)?.message || e).slice(0, 120) }; }
}
