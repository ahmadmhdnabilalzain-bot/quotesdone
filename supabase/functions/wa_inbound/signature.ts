// Which URL Twilio signed, and whether the signature over it is ours (customer_support, 22 Sep 2026).
//
// MEASURED 22 Sep 2026. Only two inbound WhatsApps ever reached wa_messages (10 Sep "Test" and
// 22 Sep "Hi", both the founder's) and both were refused "signature mismatch", so nothing was ever
// answered and nobody was told for twelve days. The cause is the URL, not the token:
//   - Twilio POSTed to https://<ref>.supabase.co/functions/v1/wa_inbound (function_edge_logs,
//     request.url, 12:19:39Z) and signs exactly that string;
//   - inside the edge runtime the same request's pathname is /wa_inbound — the platform strips the
//     /functions/v1 prefix (agent_runs fn:wa_inbound counts.path = '/wa_inbound', 2 rows, both 403);
//   - wa_inbound rebuilt the URL as proto + host + pathname, so it hashed
//     https://<ref>.supabase.co/wa_inbound, which Twilio never signs. Every genuine webhook failed.
// The stored twilio_auth_token authenticates against the account (GET of the 22 Sep message with
// account_sid:auth_token returned 200), so the key was never the problem.
//
// THE FIX. The URL Twilio was given is the public one: SUPABASE_URL + /functions/v1/<slug>, plus
// whatever query string arrived. That form is tried first; the forwarded-host form with the prefix
// restored, and the old literal form, are kept as equivalents so a platform change in either
// direction cannot silence the channel again. A signature is accepted only if it matches one of
// them exactly — a genuinely bad signature still fails closed.
import { verifyTwilioSignature } from '../_shared/twilio_status.ts';

/** Every URL Twilio could have signed for this request, most likely first, no duplicates. */
export function signedUrlCandidates(reqUrl: string, headers: Headers, supabaseUrl: string, slug = 'wa_inbound'): string[] {
  let u: URL | null = null;
  try { u = new URL(reqUrl); } catch (_e) { u = null; }
  const qs = u?.search || '';
  const out: string[] = [];
  const base = String(supabaseUrl || '').replace(/\/+$/, '');
  if (base) out.push(base + '/functions/v1/' + slug + qs);
  if (u) {
    const proto = headers.get('x-forwarded-proto') || 'https';
    const host = headers.get('x-forwarded-host') || headers.get('host') || u.host;
    const path = u.pathname.startsWith('/functions/v1/') ? u.pathname : '/functions/v1' + u.pathname;
    out.push(proto + '://' + host + path + qs);
    out.push(proto + '://' + host + u.pathname + qs);
  }
  return [...new Set(out)];
}

/** Valid if the presented signature matches ANY candidate URL; each comparison is constant-time. */
export async function verifyInboundSignature(authToken: string, candidates: string[], params: Record<string, string>,
  presented: string | null): Promise<{ valid: boolean; reason: string; url_form: number | null }> {
  if (!presented) return { valid: false, reason: 'no X-Twilio-Signature header', url_form: null };
  for (let i = 0; i < candidates.length; i++) {
    const r = await verifyTwilioSignature(authToken, candidates[i], params, presented);
    if (r.valid) return { valid: true, reason: 'signature valid', url_form: i };
  }
  return { valid: false, reason: 'signature mismatch over every URL Twilio could have signed', url_form: null };
}

/** An inbound "from" our own sender is an echo; answering it would talk to ourselves. */
export function isOwnNumber(from: string, ourFrom: string): boolean {
  const d = (s: string) => String(s || '').replace(/[^0-9]/g, '');
  return d(ourFrom).length >= 7 && d(from) === d(ourFrom);
}
