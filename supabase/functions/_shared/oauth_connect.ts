// OAUTH_CONNECT — the pure half of the founder's three consent links (it_engineer, 28 Sep 2026).
// supabase/functions/oauth_connect/ is the HTTP half. Readers of the stored tokens: PR #961 (Postmaster digest)
// and PR #966 (daily seed-inbox placement check). No token, code or secret ever reaches a page or a log.
//
// STATE: '<provider>.<expiry ms>.<nonce>.<HMAC-SHA256>' keyed by a label + the runtime's SUPABASE_SERVICE_ROLE_KEY
// (never in the database). It is bound to the provider, expires in 10 minutes, and is also set as an HttpOnly
// cookie so a callback is accepted only in the browser that started it. The PKCE verifier is derived from the
// same key and the nonce, so nothing has to be stored between start and callback.
export type Provider = 'google_postmaster' | 'gmail_seed' | 'ms_graph_seed';
export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export const PROVIDERS: Provider[] = ['google_postmaster', 'gmail_seed', 'ms_graph_seed'];
export const STATE_TTL_MS = 10 * 60_000;

export const SPEC: Record<Provider, { label: string; scope: string; token_key: string; client: 'google' | 'ms' }> = {
  google_postmaster: { label: 'Gmail Postmaster Tools', scope: 'https://www.googleapis.com/auth/postmaster.readonly', token_key: 'google_postmaster_refresh_token', client: 'google' },
  gmail_seed: { label: 'Gmail seed inbox', scope: 'https://www.googleapis.com/auth/gmail.readonly', token_key: 'gmail_seed_refresh_token', client: 'google' },
  // User.Read is what lets GET /me prove whose mailbox this is (PR #966 reads /me too); Mail.Read cannot.
  ms_graph_seed: { label: 'Outlook seed inbox', scope: 'https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/User.Read offline_access', token_key: 'ms_graph_seed_refresh_token', client: 'ms' },
};
export const SEED_GMAIL = 'ahmadmhdnabilalzain@gmail.com';
export const SEED_OUTLOOK = 'management@doratajewelries.com';
export const POSTMASTER_DOMAIN = 'quotesdone.com';

const enc = new TextEncoder();
const b64u = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
async function hmac(key: string, msg: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', enc.encode('oauth_connect|' + key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64u(await crypto.subtle.sign('HMAC', k, enc.encode(msg)));
}
export function sameString(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
export const isProvider = (p: string | null): p is Provider => !!p && (PROVIDERS as string[]).includes(p);

export async function signState(key: string, p: Provider, now = Date.now()): Promise<string> {
  const body = `${p}.${now + STATE_TTL_MS}.${b64u(crypto.getRandomValues(new Uint8Array(24)))}`;
  return body + '.' + await hmac(key, 'state|' + body);
}
export async function verifyState(key: string, state: string, now = Date.now()): Promise<{ provider: Provider; nonce: string } | null> {
  const m = state.match(/^([a-z_]+)\.(\d{13})\.([A-Za-z0-9_-]{32})\.([A-Za-z0-9_-]{43})$/);
  if (!m || !isProvider(m[1])) return null;
  const body = `${m[1]}.${m[2]}.${m[3]}`;
  if (!sameString(m[4], await hmac(key, 'state|' + body))) return null;
  if (Number(m[2]) < now || Number(m[2]) > now + STATE_TTL_MS) return null;
  return { provider: m[1], nonce: m[3] };
}
export const pkceVerifier = (key: string, nonce: string) => hmac(key, 'pkce|' + nonce);
export async function pkceChallenge(verifier: string) { return b64u(await crypto.subtle.digest('SHA-256', enc.encode(verifier))); }

export function redirectUri(supabaseUrl: string): string { return supabaseUrl.replace(/\/$/, '') + '/functions/v1/oauth_connect/callback'; }
const msBase = (tenant: string) => `https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/`;

export function authorizeUrl(p: Provider, clientId: string, redirect: string, state: string, challenge: string, tenant = ''): string {
  const q = new URLSearchParams({ response_type: 'code', client_id: clientId, redirect_uri: redirect, state, scope: SPEC[p].scope,
    code_challenge: challenge, code_challenge_method: 'S256', prompt: 'consent' });
  if (SPEC[p].client === 'ms') { q.set('response_mode', 'query'); q.set('login_hint', SEED_OUTLOOK); return msBase(tenant) + 'authorize?' + q; }
  q.set('access_type', 'offline'); q.set('include_granted_scopes', 'false');
  if (p === 'gmail_seed') q.set('login_hint', SEED_GMAIL);
  return 'https://accounts.google.com/o/oauth2/v2/auth?' + q;
}
// PUBLIC CLIENT (ms_graph_seed, 28 Sep 2026): the Microsoft app is a "Public client/native" registration, so no
// client secret exists. PKCE is then the only proof of possession: the verifier is HMAC(service key, nonce) and the
// nonce is inside the signed, 10-minute state, so it never leaves the server and cannot be forged or replayed after
// expiry. A confidential client (secret present) sends both the secret and the verifier. Google always has a secret.
export const isPublicClient = (p: Provider, secret: string) => SPEC[p].client === 'ms' && !secret;
export function tokenBody(code: string, redirect: string, clientId: string, secret: string, verifier: string): URLSearchParams {
  const b = new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: redirect, client_id: clientId, code_verifier: verifier });
  if (secret) b.set('client_secret', secret);
  return b;
}
export function tokenUrl(p: Provider, tenant = ''): string {
  return SPEC[p].client === 'ms' ? msBase(tenant) + 'token' : 'https://oauth2.googleapis.com/token';
}

// The account behind the access token must be the allowlisted one. Only the verdict leaves this function.
export async function checkIdentity(f: Fetch, p: Provider, access: string): Promise<{ ok: boolean; why?: string }> {
  const get = async (u: string) => { const r = await f(u, { headers: { Authorization: 'Bearer ' + access } }); return r.ok ? await r.json().catch(() => ({})) : null; };
  if (p === 'gmail_seed') {
    const j = await get('https://gmail.googleapis.com/gmail/v1/users/me/profile');
    return String(j?.emailAddress || '').toLowerCase() === SEED_GMAIL ? { ok: true } : { ok: false, why: 'Sign in as the Gmail seed mailbox, not another account.' };
  }
  if (p === 'ms_graph_seed') {
    const j = await get('https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName');
    const ids = [j?.mail, j?.userPrincipalName].map((v) => String(v || '').toLowerCase());
    return ids.includes(SEED_OUTLOOK) ? { ok: true } : { ok: false, why: 'Sign in as the Outlook seed mailbox, not another account.' };
  }
  const j = await get('https://gmailpostmastertools.googleapis.com/v1/domains');
  const names = Array.isArray(j?.domains) ? j.domains.map((d: { name?: string }) => String(d?.name || '').toLowerCase()) : [];
  return names.includes('domains/' + POSTMASTER_DOMAIN) ? { ok: true } : { ok: false, why: 'This Google account cannot see ' + POSTMASTER_DOMAIN + ' in Postmaster Tools.' };
}
