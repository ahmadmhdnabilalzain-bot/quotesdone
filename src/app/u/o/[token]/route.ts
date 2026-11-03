// /u/o/<token>.gif — the 1x1 image in a TRACKED supplier invitation (marketing, 3 Nov 2026; founder: "I want us to know
// when someone opened our invitation email"). send_outbox/open_tracking.ts puts it in the HTML twin of the plain text, on
// our own domain, for the share set in app_secrets.invite_open_tracking.
//
// It always answers the same transparent GIF, never cached, whatever happens, so a mail client sees nothing different
// between a recorded open, a refused token and a database that did not answer. A well-formed token is handed with the
// user agent and the client address to fn_email_open_record, which keeps a salted hash of the address and never the
// address itself, and classifies the load (machine_prefetch / likely_human / unknown). HEAD records nothing.
// The route's only secret is the service-role key, read as resilience-ping reads it (secret key first, legacy fallback).
// prevented by: scripts/checks/an_invitation_open_is_measured_on_a_tracked_share.test.mjs
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

import { SUPA_URL } from '@/lib/supaEnv';

const GIF = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');
const TOKEN = /^[0-9a-f]{32}$/;
const serviceKey = () => process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';

function gif(): Response {
  return new Response(new Uint8Array(GIF), {
    status: 200,
    headers: { 'Content-Type': 'image/gif', 'Content-Length': String(GIF.length), 'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0', 'X-Robots-Tag': 'noindex' },
  });
}

export async function GET(req: Request, ctx: { params: Promise<{ token: string }> }): Promise<Response> {
  const token = String((await ctx.params).token || '').replace(/\.gif$/i, '');
  const key = serviceKey();
  if (TOKEN.test(token) && key && SUPA_URL) {
    await fetch(`${SUPA_URL}/rest/v1/rpc/fn_email_open_record`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_token: token, p_user_agent: req.headers.get('user-agent') || '', p_ip: req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || '' }),
      signal: AbortSignal.timeout(3000), cache: 'no-store',
    }).catch(() => null);
  }
  return gif();
}

export async function HEAD(): Promise<Response> {
  return gif();
}
