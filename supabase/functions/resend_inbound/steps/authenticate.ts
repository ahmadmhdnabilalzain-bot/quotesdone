// resend_inbound step: the query token and the Svix signature: nothing below runs for a caller who fails either. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import { J, sec, logRun } from '../lib/runtime.ts';
import { verifySvix } from '../lib/verify_svix.ts';

export async function authenticate(ctx: { req: Request }) {
    const { req } = ctx;
    const url = new URL(req.url);
    const s = url.searchParams.get('s');
    const ibs = await sec('inbound_secret'); const rit = await sec('resend_inbound_token');
    // 28 Sep 2026: two refusals at 12:37 UTC could not be attributed - the row said nothing about the
    // caller. A genuine Resend delivery always carries svix-* headers; record whether this one did, the
    // user agent, and the token's length only (never its value), so the next refusal names its source.
    if (!s || (s !== ibs && s !== rit)) { await logRun('error', { authorised: 0, stage: 'query_token',
        token_len: s ? s.length : 0, svix_headers: !!(req.headers.get('svix-id') || req.headers.get('webhook-id')),
        user_agent: (req.headers.get('user-agent') || '').slice(0, 120), method: req.method },'resend_inbound rejected a caller with a bad or missing ?s token. No inbound email was processed - if this was genuine Resend traffic, a supplier document or forwarded receipt has been dropped.'); return J({ error: 'forbidden' }, 403); }
    // AUDIT 9.5 (3 Aug 2026) - THE INSTRUMENT, not the fix. This endpoint accepts the omnipotent
    // shared secret as a ?s= query token, and the shared secret is due to be withdrawn on 10 Aug.
    // Whether that breaks inbound email depends entirely on which value Resend's configured webhook
    // URL actually carries, and that cannot be read from here. So: say so, loudly, every time the
    // shared secret is the value that authorised. Seven days of silence means Resend is on the
    // dedicated token and withdrawal is safe; a single one of these means it is not, and the URL
    // must be re-issued with resend_inbound_token BEFORE the secret is withdrawn.
    if (ibs && s === ibs && s !== rit) {
      await logRun('error', { authorised: 1, stage: 'query_token', via: 'legacy_shared_secret' },
        'resend_inbound was authorised by the SHARED SECRET, not by resend_inbound_token. When the shared secret is withdrawn this endpoint will start refusing genuine Resend deliveries and inbound supplier email will silently stop. Re-issue the Resend inbound webhook URL with resend_inbound_token before withdrawal.');
    }

    // Read the body ONCE as raw text - the Svix signature covers the exact bytes.
    const raw = await req.text();
    const signingSecret = await sec('resend_inbound_signing_secret');
    if (!signingSecret) { await logRun('error', { authorised: 0, stage: 'no_signing_secret' }, 'resend_inbound could not read resend_inbound_signing_secret from app_secrets, so it cannot confirm this email really came from Resend. The delivery was REJECTED rather than trusted on the query token alone. Inbound receipts and supplier documents are paused until the secret is restored.'); return J({ error: 'signing secret unavailable' }, 503); }
    const v = await verifySvix(signingSecret, raw, req.headers);
    if (!v.ok) { await logRun('error', { authorised: 0, stage: 'signature', reason: v.reason }, 'resend_inbound REJECTED a delivery that failed Svix signature verification (' + v.reason + '). Until 19 Jul 2026 a leaked ?s token alone was enough to book fake expenses and overwrite supplier licence data. If this fires on genuine Resend traffic, check the signing secret in app_secrets matches the endpoint in the Resend dashboard.'); return J({ error: 'invalid signature' }, 401); }
    return { ...ctx, raw };
}
export type Out = Exclude<Awaited<ReturnType<typeof authenticate>>, Response>;
