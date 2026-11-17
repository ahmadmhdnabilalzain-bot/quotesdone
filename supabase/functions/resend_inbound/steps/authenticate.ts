// resend_inbound step: the query token (resend_inbound_token only) and the Svix signature: nothing below runs for a caller who fails either. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import { J, sec, logRun } from '../lib/runtime.ts';
import { verifySvix } from '../lib/verify_svix.ts';
import { sameSecret } from '../../stripe_setup/webhook_plan.ts';

export async function authenticate(ctx: { req: Request }) {
    const { req } = ctx;
    const url = new URL(req.url);
    const s = url.searchParams.get('s');
    // ONLY resend_inbound_token (17 Nov 2026, security audit finding 6). The retired shared inbound_secret was also
    // accepted here, with an alarm row whenever it was the value that authorised. SELECT on agent_runs, 17 Nov: 0 such
    // rows ever, against 1,258 runs in the 7 days before; every caller in the repository (Resend's configured URL, the
    // e2e stage2 and invitation_reply probes) sends resend_inbound_token, and the ?drain=1 kick is authorised above
    // this step by an internal credential. A Svix signature is still required after the token.
    const rit = await sec('resend_inbound_token');
    // 28 Sep 2026: two refusals at 12:37 UTC could not be attributed - the row said nothing about the
    // caller. A genuine Resend delivery always carries svix-* headers; record whether this one did, the
    // user agent, and the token's length only (never its value), so the next refusal names its source.
    if (!s || !rit || !(await sameSecret(s, rit))) { await logRun('error', { authorised: 0, stage: 'query_token',
        token_len: s ? s.length : 0, svix_headers: !!(req.headers.get('svix-id') || req.headers.get('webhook-id')),
        user_agent: (req.headers.get('user-agent') || '').slice(0, 120), method: req.method },'resend_inbound rejected a caller with a bad or missing ?s token. No inbound email was processed - if this was genuine Resend traffic, a supplier document or forwarded receipt has been dropped.'); return J({ error: 'forbidden' }, 403); }
    // Read the body ONCE as raw text - the Svix signature covers the exact bytes.
    const raw = await req.text();
    const signingSecret = await sec('resend_inbound_signing_secret');
    if (!signingSecret) { await logRun('error', { authorised: 0, stage: 'no_signing_secret' }, 'resend_inbound could not read resend_inbound_signing_secret from app_secrets, so it cannot confirm this email really came from Resend. The delivery was REJECTED rather than trusted on the query token alone. Inbound receipts and supplier documents are paused until the secret is restored.'); return J({ error: 'signing secret unavailable' }, 503); }
    const v = await verifySvix(signingSecret, raw, req.headers);
    if (!v.ok) { await logRun('error', { authorised: 0, stage: 'signature', reason: v.reason }, 'resend_inbound REJECTED a delivery that failed Svix signature verification (' + v.reason + '). Until 19 Jul 2026 a leaked ?s token alone was enough to book fake expenses and overwrite supplier licence data. If this fires on genuine Resend traffic, check the signing secret in app_secrets matches the endpoint in the Resend dashboard.'); return J({ error: 'invalid signature' }, 401); }
    return { ...ctx, raw };
}
export type Out = Exclude<Awaited<ReturnType<typeof authenticate>>, Response>;
