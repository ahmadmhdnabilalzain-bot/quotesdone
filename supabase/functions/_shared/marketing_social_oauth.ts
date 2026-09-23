// OUR OWN OAUTH FOR YOUTUBE AND THE LINKEDIN COMPANY PAGE (marketing, 23 Sep 2026; founder instructions 919-920).
//
// Postiz posts to both but its public API reads and answers no comment (measured 23 Sep, PR #871). The founder:
// "give me a direct link to click and then I will connect you." This module is the pure half of that flow;
// supabase/functions/marketing_social_connect/ is the HTTP half and marketing/duties.ts the user of the tokens.
//
// SCOPES — the minimum that reads and answers comments on OUR channel / page, nothing about a person:
//   youtube   https://www.googleapis.com/auth/youtube.force-ssl  (commentThreads.list, comments.insert,
//             comments.setModerationStatus, channels.update for the description)
//   linkedin  r_organization_social w_organization_social        (Community Management API: posts, comments)
// A personal-profile scope (openid, profile, email, r_liteprofile, r_basicprofile, r_emailaddress,
// w_member_social, r_member_social) is NEVER requested — founder rule; scopesAreCompanyOnly() refuses it and
// scripts/checks/linkedin_is_never_automated.test.mjs fails the build if one is written here.
//
// TOKENS AT REST: app_secrets.<platform>_oauth holds 'v1.' + base64(iv | AES-256-GCM ciphertext) of the JSON token
// set. The key is HKDF-SHA256 of the function's SUPABASE_SERVICE_ROLE_KEY environment variable, which lives in
// the edge runtime, not in the database: a reader of app_secrets alone (a leaked export, a SQL grant mistake)
// gets ciphertext. Rotating the service-role key makes the stored tokens undecryptable; the duty then says
// "not connected" and a fresh link (scripts/marketing/social_connect_link.mjs) reconnects.
export type SocialPlatform = 'youtube' | 'linkedin';
export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

export const SCOPES: Record<SocialPlatform, string[]> = {
  youtube: ['https://www.googleapis.com/auth/youtube.force-ssl'],
  linkedin: ['r_organization_social', 'w_organization_social'],
};
const PERSONAL = /^(openid|profile|email|r_liteprofile|r_basicprofile|r_fullprofile|r_emailaddress|w_member_social|r_member_social|r_1st_connections\w*)$/;
export const scopesAreCompanyOnly = (scopes: string[]) => scopes.length > 0 && scopes.every((s) => !PERSONAL.test(s));

export const SECRET_KEYS: Record<SocialPlatform, { id: string; secret: string; token: string; expected: string }> = {
  youtube: { id: 'google_oauth_client_id', secret: 'google_oauth_client_secret', token: 'youtube_oauth', expected: 'youtube_channel_id' },
  linkedin: { id: 'linkedin_oauth_client_id', secret: 'linkedin_oauth_client_secret', token: 'linkedin_oauth', expected: 'linkedin_organization_id' },
};
export const LINKEDIN_VERSION = '202509';
export const LI_REST = 'https://api.linkedin.com/rest/';
const LI = LI_REST;
export const liHeaders = (token: string) => ({ Authorization: 'Bearer ' + token, 'LinkedIn-Version': LINKEDIN_VERSION, 'X-Restli-Protocol-Version': '2.0.0' });

export function redirectUri(supabaseUrl: string, p: SocialPlatform): string {
  return supabaseUrl.replace(/\/$/, '') + '/functions/v1/marketing_social_connect/' + p + '/callback';
}

export function authorizeUrl(p: SocialPlatform, clientId: string, redirect: string, state: string, codeChallenge: string): string {
  if (!scopesAreCompanyOnly(SCOPES[p])) throw new Error('refused: a personal scope');
  const q = new URLSearchParams({ response_type: 'code', client_id: clientId, redirect_uri: redirect, state, scope: SCOPES[p].join(' ') });
  if (p === 'youtube') {
    // offline + consent: Google returns a refresh token every time, so a reconnect always replaces a dead one.
    q.set('access_type', 'offline'); q.set('prompt', 'consent'); q.set('include_granted_scopes', 'false');
    q.set('code_challenge', codeChallenge); q.set('code_challenge_method', 'S256');
    return 'https://accounts.google.com/o/oauth2/v2/auth?' + q;
  }
  return 'https://www.linkedin.com/oauth/v2/authorization?' + q;
}

export function tokenRequest(p: SocialPlatform, body: Record<string, string>): { url: string; init: RequestInit } {
  return { url: p === 'youtube' ? 'https://oauth2.googleapis.com/token' : 'https://www.linkedin.com/oauth/v2/accessToken',
    init: { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(body).toString() } };
}

// ── random, hashing, PKCE ─────────────────────────────────────────────────────────────────────────
const b64u = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
export const randomToken = (n = 32) => b64u(crypto.getRandomValues(new Uint8Array(n)));
export async function sha256Hex(s: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  return [...d].map((x) => x.toString(16).padStart(2, '0')).join('');
}
export async function pkceChallenge(verifier: string): Promise<string> {
  return b64u(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
}
/** Constant-time string comparison (the state cookie against the stored state). */
export function sameString(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// ── encryption at rest ──────────────────────────────────────────────────────────────────────────
async function key(master: string): Promise<CryptoKey> {
  if (!master || master.length < 20) throw new Error('no key material');
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(master), 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: new TextEncoder().encode('quotesdone.social_oauth'), info: new TextEncoder().encode('v1') },
    base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}
export async function seal(master: string, value: unknown): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(master), new TextEncoder().encode(JSON.stringify(value))));
  const all = new Uint8Array(12 + ct.length); all.set(iv); all.set(ct, 12);
  return 'v1.' + btoa(String.fromCharCode(...all));
}
export async function open<T = Record<string, unknown>>(master: string, sealed: string): Promise<T | null> {
  if (!sealed?.startsWith('v1.')) return null;
  try {
    const all = Uint8Array.from(atob(sealed.slice(3)), (c) => c.charCodeAt(0));
    const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: all.slice(0, 12) }, await key(master), all.slice(12));
    return JSON.parse(new TextDecoder().decode(pt)) as T;
  } catch { return null; }   // wrong key or tampered: treated as not connected
}

// ── WHO did the founder connect? It must be QuotesDone's, or nothing is stored ──────────────────────
// expected: the id pinned in app_secrets (youtube_channel_id / linkedin_organization_id). With no pin, the name
// must read "QuotesDone"; the first accepted id is then pinned, so a later link can only reconnect THAT one.
const OURS = /quotes\s*done/i;
export interface Identity { ok: boolean; id?: string; name?: string; why?: string }
export function pickYoutube(channels: Array<{ id: string; snippet?: { title?: string; customUrl?: string } }>, expected: string | null): Identity {
  if (!channels.length) return { ok: false, why: 'This Google account has no YouTube channel. Sign in with the account that owns the QuotesDone channel (for a brand channel, choose it on Google\'s account picker).' };
  const c = expected ? channels.find((x) => x.id === expected) : channels.find((x) => OURS.test(x.snippet?.title || '') || OURS.test(x.snippet?.customUrl || ''));
  if (!c) return { ok: false, why: 'The channel you chose (' + channels.map((x) => x.snippet?.title || x.id).join(', ') + ') is not the QuotesDone channel' + (expected ? ' (' + expected + ')' : '') + '. Nothing was stored. Open a new link and pick the QuotesDone channel.' };
  return { ok: true, id: c.id, name: c.snippet?.title };
}
export function pickLinkedin(orgs: Array<{ id: string; name: string }>, expected: string | null): Identity {
  if (!orgs.length) return { ok: false, why: 'This LinkedIn member is not an approved administrator of any company page. Sign in as an admin of the QuotesDone page.' };
  const o = expected ? orgs.find((x) => x.id === expected) : orgs.find((x) => OURS.test(x.name));
  if (!o) return { ok: false, why: 'None of the pages you administer (' + orgs.map((x) => x.name || x.id).join(', ') + ') is the QuotesDone company page. Nothing was stored.' };
  return { ok: true, id: o.id, name: o.name };
}

export async function readYoutubeChannels(f: Fetch, token: string) {
  const r = await f('https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true', { headers: { Authorization: 'Bearer ' + token } });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok) throw new Error('YouTube channels HTTP ' + r.status + ': ' + String(j?.error?.message || '').slice(0, 160));
  return (j.items || []) as Array<{ id: string; snippet?: { title?: string; customUrl?: string } }>;
}
/** The company pages this token may act for: approved ADMINISTRATOR roles only, each named. */
export async function readLinkedinOrgs(f: Fetch, token: string) {
  const r = await f(LI + 'organizationAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED', { headers: liHeaders(token) });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok) throw new Error('LinkedIn organizationAcls HTTP ' + r.status + ': ' + String(j?.message || '').slice(0, 160));
  const out: Array<{ id: string; name: string }> = [];
  for (const e of j.elements || []) {
    const id = String(e.organization || e.organizationTarget || '').split(':').pop() || '';
    if (!id) continue;
    const o = await f(LI + 'organizations/' + encodeURIComponent(id), { headers: liHeaders(token) });
    const oj = await o.json().catch(() => ({})) as any;
    out.push({ id, name: String(oj?.localizedName || oj?.vanityName || '') });
  }
  return out;
}

// ── the stored token set, and a fresh access token from it ───────────────────────────────────────
export interface TokenSet { platform: SocialPlatform; account_id: string; account_name?: string; access_token: string; expires_at: number;
  refresh_token?: string | null; refresh_expires_at?: number | null; scope?: string; connected_at: string }

/** An access token valid for at least 2 more minutes, refreshing (and re-sealing) when needed. null = not connected. */
export async function accessToken(f: Fetch, p: SocialPlatform, master: string,
  sec: (k: string) => Promise<string | undefined>, save: (k: string, v: string) => Promise<void>, now = Date.now()): Promise<TokenSet | null> {
  const sealed = await sec(SECRET_KEYS[p].token);
  const t = sealed ? await open<TokenSet>(master, sealed) : null;
  if (!t) return null;
  if (t.expires_at - 120_000 > now) return t;
  if (!t.refresh_token) return null;   // LinkedIn issues refresh tokens only to approved apps; a lapsed token needs a new link
  const [id, secret] = await Promise.all([sec(SECRET_KEYS[p].id), sec(SECRET_KEYS[p].secret)]);
  if (!id || !secret) return null;
  const { url, init } = tokenRequest(p, { grant_type: 'refresh_token', refresh_token: t.refresh_token, client_id: id, client_secret: secret });
  const r = await f(url, init);
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok || !j.access_token) throw new Error(p + ' token refresh HTTP ' + r.status + ': ' + String(j?.error_description || j?.error || '').slice(0, 120));
  const next: TokenSet = { ...t, access_token: j.access_token, expires_at: now + Number(j.expires_in || 3600) * 1000,
    refresh_token: j.refresh_token || t.refresh_token, refresh_expires_at: j.refresh_token_expires_in ? now + Number(j.refresh_token_expires_in) * 1000 : t.refresh_expires_at };
  await save(SECRET_KEYS[p].token, await seal(master, next));
  return next;
}
