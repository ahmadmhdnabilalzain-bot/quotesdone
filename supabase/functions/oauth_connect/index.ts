// OAUTH_CONNECT — the founder grants three consents by clicking a link; nobody ever sees a token (it_engineer, 28 Sep 2026).
//
//   GET /oauth_connect/start?provider=google_postmaster|gmail_seed|ms_graph_seed
//       302 to Google / Microsoft consent with the minimum read scope, offline access, prompt=consent, PKCE and a
//       signed state (_shared/oauth_connect.ts: HMAC, 10 minutes, bound to the provider, echoed in an HttpOnly cookie).
//   GET /oauth_connect/callback?code&state
//       The state must verify AND equal the cookie. The code is exchanged server-side, the account is checked against
//       the allowlist (Gmail/Outlook seed mailbox; Postmaster: can list quotesdone.com), and only then the refresh token
//       is written to app_secrets.<google_postmaster|gmail_seed|ms_graph_seed>_refresh_token — the names PRs #961 and
//       #966 read. The page says "Connected: <provider> ✓" or why nothing was stored.
// Deployed with verify_jwt = false (config.toml): the founder's browser carries no Supabase JWT; the signed state is the
// key, and the allowlist decides whose token may be stored. No token, code or secret is written to a page or a log.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { timedFetch } from '../_shared/timed_fetch.ts';
import {
  authorizeUrl, checkIdentity, isProvider, pkceChallenge, pkceVerifier, redirectUri, sameString, signState, SPEC,
  STATE_TTL_MS, tokenUrl, verifyState, type Provider,
} from '../_shared/oauth_connect.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_, KEY);
const COOKIE = 'qd_oauth_state';
const PATH = '/functions/v1/oauth_connect';

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
function page(status: number, title: string, body = '', extra: Record<string, string> = {}) {
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title>`
    + `<body style="font-family:system-ui;max-width:560px;margin:48px auto;padding:0 16px;line-height:1.5"><h1 style="font-size:20px">${esc(title)}</h1><p>${esc(body)}</p></body>`,
    { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
      'X-Frame-Options': 'DENY', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'", ...extra } });
}
async function sec(k: string): Promise<string> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return String(data?.value || '');
}
async function client(p: Provider) {
  if (SPEC[p].client === 'google') return { id: await sec('google_oauth_client_id'), secret: await sec('google_oauth_client_secret'), tenant: '' };
  return { id: await sec('ms_graph_client_id'), secret: await sec('ms_graph_client_secret'), tenant: await sec('ms_graph_tenant_id') };
}
const cookieOf = (req: Request) => (req.headers.get('cookie') || '').split(/;\s*/).find((c) => c.startsWith(COOKIE + '='))?.slice(COOKIE.length + 1) || '';
const clear = { 'Set-Cookie': `${COOKIE}=; Path=${PATH}; Max-Age=0; HttpOnly; Secure; SameSite=Lax` };

async function start(url: URL): Promise<Response> {
  const p = url.searchParams.get('provider');
  if (!isProvider(p)) return page(400, 'Unknown provider', 'Use provider=google_postmaster, gmail_seed or ms_graph_seed.');
  const c = await client(p);
  if (!c.id || !c.secret || (SPEC[p].client === 'ms' && !c.tenant)) return page(503, SPEC[p].label + ' is not ready yet', 'The OAuth client has not been stored. Nothing happened.');
  const state = await signState(KEY, p);
  const nonce = state.split('.')[2];
  const location = authorizeUrl(p, c.id, redirectUri(URL_), state, await pkceChallenge(await pkceVerifier(KEY, nonce)), c.tenant);
  return new Response(null, { status: 302, headers: { Location: location, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
    'Set-Cookie': `${COOKIE}=${state}; Path=${PATH}; Max-Age=${STATE_TTL_MS / 1000}; HttpOnly; Secure; SameSite=Lax` } });
}

async function callback(url: URL, req: Request): Promise<Response> {
  const state = url.searchParams.get('state') || '', code = url.searchParams.get('code') || '';
  const v = await verifyState(KEY, state);
  if (!v || !sameString(state, cookieOf(req))) return page(400, 'This sign-in cannot be accepted', 'It expired or was not started in this browser. Open the start link again.', clear);
  const p = v.provider;
  if (url.searchParams.get('error') || !code) return page(400, 'Nothing was connected', 'The consent screen was closed or declined.', clear);
  try {
    const c = await client(p);
    const r = await timedFetch(tokenUrl(p, c.tenant), { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: redirectUri(URL_), client_id: c.id, client_secret: c.secret,
        code_verifier: await pkceVerifier(KEY, v.nonce) }).toString() });
    const j = await r.json().catch(() => ({})) as { access_token?: string; refresh_token?: string };
    if (!r.ok || !j.access_token) return page(502, 'Nothing was connected', 'The provider refused the code (HTTP ' + r.status + '). Open the start link again.', clear);
    const who = await checkIdentity(timedFetch, p, j.access_token);
    if (!who.ok) return page(403, 'Nothing was connected', who.why!, clear);
    if (!j.refresh_token) return page(502, 'Nothing was connected', 'No refresh token was returned. Open the start link again and approve.', clear);
    // Replacing an earlier token is deliberate: only the allowlisted account can reach this line (reconnect = new link).
    const { error } = await admin.from('app_secrets').upsert({ key: SPEC[p].token_key, value: j.refresh_token }, { onConflict: 'key' });
    if (error) throw new Error('app_secrets write failed');
    return page(200, 'Connected: ' + p + ' ✓', SPEC[p].label + ' is connected. You can close this page.', clear);
  } catch (e) {
    console.error('oauth_connect', p, String((e as Error)?.message || e).slice(0, 120));
    return page(502, 'Nothing was connected', 'Something failed; nothing was stored. Open the start link again.', clear);
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method !== 'GET') return page(405, 'Not allowed', 'Open the link in a browser.');
  if (/\/start\/?$/.test(url.pathname)) return await start(url);
  if (/\/callback\/?$/.test(url.pathname)) return await callback(url, req);
  return page(404, 'Not found');
});
