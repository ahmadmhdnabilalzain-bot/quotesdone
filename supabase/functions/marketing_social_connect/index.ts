// MARKETING_SOCIAL_CONNECT — the founder's one link per platform (marketing, 23 Sep 2026; instructions 919-920).
//
//   GET /marketing_social_connect/{youtube|linkedin}/start?t=<link token>
//       The link is minted by fn_marketing_social_connect_link (scripts/marketing/social_connect_link.mjs): 32 random
//       bytes, only its SHA-256 stored, valid 24 hours, usable ONCE (the claim below is one conditional UPDATE).
//       A fresh state (CSRF) and PKCE verifier are bound to the row; the state also goes into an HttpOnly,
//       Secure, SameSite=Lax cookie scoped to this function, then 302 to Google / LinkedIn consent.
//   GET /marketing_social_connect/{platform}/callback?code&state
//       The state must match the cookie AND an unfinished row of the same platform started in the
//       last 15 minutes; the row is closed in the same UPDATE that reads it, so a replayed callback finds nothing.
//       The code is exchanged, the account is read and must be QuotesDone's (marketing_social_oauth.ts pickYoutube:
//       exact title or the pinned id; verifyLinkedinOrg: the pinned page, proved by reading its posts) — otherwise nothing is stored and the page says why. On success the token set is sealed
//       (AES-GCM) into app_secrets.<platform>_oauth and the account id pinned.
// Deployed with verify_jwt = false: the founder's browser carries no Supabase JWT; the single-use link is the key.
// No token, code or secret is ever written to a page, a log or agent_runs.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { timedFetch } from '../_shared/timed_fetch.ts';
import {
  authorizeUrl, pickYoutube, pkceChallenge, randomToken, readYoutubeChannels, redirectUri, verifyLinkedinOrg,
  sameString, seal, SECRET_KEYS, sha256Hex, tokenRequest, type SocialPlatform, type TokenSet,
} from '../_shared/marketing_social_oauth.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const MASTER = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_, MASTER);
const COOKIE = 'qd_social_state';
const LABEL: Record<SocialPlatform, string> = { youtube: 'YouTube', linkedin: 'LinkedIn company page' };

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
function page(status: number, title: string, body: string, extra: Record<string, string> = {}) {
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title>`
    + `<body style="font-family:system-ui;max-width:560px;margin:48px auto;padding:0 16px;line-height:1.5"><h1 style="font-size:20px">${esc(title)}</h1><p>${esc(body)}</p></body>`,
    { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
      'X-Frame-Options': 'DENY', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'", ...extra } });
}
async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}
async function put(k: string, v: string) {
  const { error } = await admin.from('app_secrets').upsert({ key: k, value: v }, { onConflict: 'key' });
  if (error) throw new Error('app_secrets ' + k + ': ' + error.message);
}
const cookieOf = (req: Request) => (req.headers.get('cookie') || '').split(/;\s*/).find((c) => c.startsWith(COOKIE + '='))?.slice(COOKIE.length + 1) || '';
const cookiePath = '/functions/v1/marketing_social_connect';

async function start(p: SocialPlatform, url: URL): Promise<Response> {
  const t = url.searchParams.get('t') || '';
  const [id, secret, pinned] = await Promise.all([sec(SECRET_KEYS[p].id), sec(SECRET_KEYS[p].secret), sec(SECRET_KEYS[p].expected)]);
  if (!id || !secret || (p === 'linkedin' && !pinned)) return page(503, LABEL[p] + ' is not ready yet', 'The OAuth client (or, for LinkedIn, the QuotesDone page id) has not been stored. Nothing happened; the link is still valid.');
  if (!/^[A-Za-z0-9_-]{40,64}$/.test(t)) return page(400, 'This link is not valid', 'Ask for a new connect link.');
  const state = randomToken(), verifier = randomToken(48);
  const { data, error } = await admin.from('social_connect_link')
    .update({ started_at: new Date().toISOString(), state_hash: await sha256Hex(state), code_verifier: verifier })
    .eq('token_hash', await sha256Hex(t)).eq('platform', p).is('started_at', null).gt('expires_at', new Date().toISOString()).select('id');
  if (error) return page(500, 'Something failed', 'The link could not be checked. Try again in a minute.');
  if (!data?.length) return page(410, 'This link has expired or was already used', 'Each link works once, for 24 hours. Ask for a new one.');
  const location = authorizeUrl(p, id, redirectUri(URL_, p), state, await pkceChallenge(verifier));
  return new Response(null, { status: 302, headers: { Location: location, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
    'Set-Cookie': `${COOKIE}=${state}; Path=${cookiePath}; Max-Age=900; HttpOnly; Secure; SameSite=Lax` } });
}

async function callback(p: SocialPlatform, url: URL, req: Request): Promise<Response> {
  const clear = { 'Set-Cookie': `${COOKIE}=; Path=${cookiePath}; Max-Age=0; HttpOnly; Secure; SameSite=Lax` };
  const state = url.searchParams.get('state') || '', code = url.searchParams.get('code') || '';
  if (!state || !sameString(state, cookieOf(req))) return page(400, 'This sign-in cannot be accepted', 'It was not started from your connect link in this browser. Open the link again.', clear);
  const { data: rows, error } = await admin.from('social_connect_link')
    .update({ completed_at: new Date().toISOString() })
    .eq('state_hash', await sha256Hex(state)).eq('platform', p).is('completed_at', null)
    .gt('started_at', new Date(Date.now() - 15 * 60_000).toISOString()).select('id,code_verifier');
  if (error || !rows?.length) return page(410, 'This sign-in has expired or was already used', 'Open a new connect link.', clear);
  const row = rows[0];
  const finish = async (result: string) => { await admin.from('social_connect_link').update({ result, code_verifier: null }).eq('id', row.id); };
  if (url.searchParams.get('error') || !code) { await finish('declined'); return page(400, 'Nothing was connected', 'The consent screen was closed or declined. Open a new link to try again.', clear); }
  try {
    const [id, secret] = await Promise.all([sec(SECRET_KEYS[p].id), sec(SECRET_KEYS[p].secret)]);
    const body: Record<string, string> = { grant_type: 'authorization_code', code, redirect_uri: redirectUri(URL_, p), client_id: id!, client_secret: secret! };
    if (p === 'youtube') body.code_verifier = row.code_verifier;
    const { url: tu, init } = tokenRequest(p, body);
    const r = await timedFetch(tu, init);
    const j = await r.json().catch(() => ({})) as any;
    if (!r.ok || !j.access_token) { await finish('exchange_failed:' + r.status); return page(502, 'The sign-in could not be completed', LABEL[p] + ' refused the code (HTTP ' + r.status + '). Open a new link.', clear); }
    const granted = String(j.scope || '').split(/[ ,]+/).filter(Boolean);
    if (p === 'linkedin' && (!granted.length || !granted.every((s) => s === 'r_organization_social' || s === 'w_organization_social'))) {
      await finish('refused_scope'); return page(400, 'Nothing was stored', 'LinkedIn granted a scope beyond the company page. Nothing was kept.', clear);
    }
    const expected = (await sec(SECRET_KEYS[p].expected)) || null;
    const who = p === 'youtube' ? pickYoutube(await readYoutubeChannels(timedFetch, j.access_token), expected)
                                : await verifyLinkedinOrg(timedFetch, j.access_token, expected);
    if (!who.ok) { await finish('refused_identity'); return page(403, 'Nothing was connected', who.why!, clear); }
    if (p === 'youtube' && !j.refresh_token) { await finish('no_refresh_token'); return page(502, 'Nothing was stored', 'Google returned no refresh token. Open a new link and approve again.', clear); }
    const now = Date.now();
    const set: TokenSet = { platform: p, account_id: who.id!, account_name: who.name, access_token: j.access_token, expires_at: now + Number(j.expires_in || 3600) * 1000,
      refresh_token: j.refresh_token || null, refresh_expires_at: j.refresh_token_expires_in ? now + Number(j.refresh_token_expires_in) * 1000 : null,
      scope: granted.join(' '), connected_at: new Date(now).toISOString() };
    await put(SECRET_KEYS[p].token, await seal(MASTER, set));
    if (!expected) await put(SECRET_KEYS[p].expected, who.id!);
    await finish('connected:' + who.id);
    return page(200, LABEL[p] + ' connected', '"' + (who.name || who.id) + '" is connected. The marketing seat will read and answer its comments from its next run. You can close this page.', clear);
  } catch (e) {
    await finish('error');
    console.error('marketing_social_connect', p, String((e as Error)?.message || e).slice(0, 200));
    return page(502, 'The sign-in could not be completed', 'Nothing was stored. Open a new link.', clear);
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method !== 'GET') return page(405, 'Not allowed', 'Open the link in a browser.');
  const m = url.pathname.match(/\/(youtube|linkedin)\/(start|callback)\/?$/);
  if (!m) return page(404, 'Not found', 'Use the connect link you were sent.');
  const p = m[1] as SocialPlatform;
  return m[2] === 'start' ? await start(p, url) : await callback(p, url, req);
});
