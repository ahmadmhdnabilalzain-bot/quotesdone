// THE UNSUBSCRIBE LINK'S TOKEN, AND HOW IT IS COMPARED (it_engineer, 17 Nov 2026).
//
// The token is the first 20 hex characters (80 bits) of HMAC-SHA256(lower-cased address, signing key); send_outbox
// signs it with unsubscribe_signing_key, and unsubscribe_signing_key_legacy still verifies links delivered before
// 3 Aug 2026. The security audit of 17 Nov (finding 5) found the two compared with `===`, which stops at the first
// differing character, and a refused call costs nothing but an unsubscribe_refusal row. sameSecret hashes both sides
// and walks every byte, as supplier_ack already does for its token.
import { sameSecret } from '../stripe_setup/webhook_plan.ts';

export async function unsubscribeToken(email: string, key: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(email.toLowerCase()));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 20);
}

/** True when `t` is the token of `e` under any of the keys that is set. Every comparison is constant-time. */
export async function unsubscribeTokenMatches(e: string, t: string, keys: (string | undefined)[]): Promise<boolean> {
  if (!e || !t) return false;
  let ok = false;
  for (const key of keys) if (key && await sameSecret(t, await unsubscribeToken(e, key))) ok = true;
  return ok;
}
