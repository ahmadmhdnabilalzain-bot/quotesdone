// The one Dropbox HTTP client dropbox_backup uses (owner: it_engineer, 14 Sep 2026).
//
// The founder, 14 Sep 2026: "we need to eliminate all other causes with fixes. unless its a server
// issue from dropbox or supabase then i see no reason for any failures". An expired access token is
// not a Dropbox outage, so it must never become a failed backup:
//   * any 401 is answered by one new token and one repeat of the same call.
//   * v2 (15 Sep 2026): the access token is SHARED between runs. Measured 15 Sep 07:20-07:24Z: the
//     2,840-row export drained through ~20 concurrent chain links, every run refreshed (counts.refreshes
//     = 1 on every agent_runs row), dozens of refreshes a minute, and two runs (07:22:02Z, 07:22:05Z)
//     got a refused refresh. The old refresh returned null for ANY non-200, so a throttled or failed
//     token call became 'no_dropbox_auth', the document was marked failed, and the loop stopped with
//     the rest of its claim left 'processing' for 10 minutes. Now:
//       - the token and its expiry are kept in app_secrets ('dropbox_access_token', fn_security_audit
//         redacts the value) and reused until 10 minutes before expiry (Dropbox: expires_in 14400);
//       - one link refreshes at a time: a lease written by compare-and-set on the stored value, the
//         others wait for the new token instead of stampeding the token endpoint;
//       - a 429, 5xx or network failure of the refresh is retried with backoff inside a budget and
//         then thrown as AuthUnavailable ('oauth2/token <status>' - health.ts classes it rate_limit,
//         provider_outage or network), never as 'no_dropbox_auth';
//       - only a refusal (invalid_grant, invalid_client, any other 4xx) or missing credentials throws
//         'no_dropbox_auth' - the one auth failure only the founder can fix, raised as before.

// Dropbox-API-Arg is an HTTP header: everything outside ASCII must be \u-escaped (Arabic, emoji -
// each UTF-16 unit separately, which is what Dropbox expects for a surrogate pair).
export function apiArg(o: unknown): string {
  return Array.from(JSON.stringify(o).split(''), (c) => {
    const n = c.charCodeAt(0);
    return n > 0x7e ? '\\u' + n.toString(16).padStart(4, '0') : c;
  }).join('');
}

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

// The token endpoint could not be reached or asked us to wait: a provider-side, passing condition.
export class AuthUnavailable extends Error { override name = 'AuthUnavailable'; }
// true for the two auth failures that make every further Dropbox call in this run fail the same way
export const isAuthStop = (e: unknown) => e instanceof AuthUnavailable || (e as Error)?.message === 'no_dropbox_auth';

export type Refreshed = { token: string; expiresIn: number };

// One refresh-token grant. Returns the token, or throws 'no_dropbox_auth' (refused: permanent) or
// AuthUnavailable (throttled, 5xx, network, timeout: transient). No secret and no response body is
// ever put in a message; only Dropbox's error code is logged.
export async function refreshAccessToken(rt: string, key: string, secret: string, f: Fetch = fetch): Promise<Refreshed> {
  if (!rt || !key || !secret) throw new Error('no_dropbox_auth');
  let r: Response;
  try {
    r = await f('https://api.dropboxapi.com/oauth2/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: rt, client_id: key, client_secret: secret }),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (e) {
    throw new AuthUnavailable('oauth2/token network ' + String((e as Error)?.name || 'Error'));
  }
  if (r.status === 429 || r.status >= 500) { await r.body?.cancel(); throw new AuthUnavailable('oauth2/token ' + r.status); }
  if (!r.ok) {
    const code = String((await r.json().catch(() => ({})))?.error ?? '').replace(/[^a-z_]/gi, '').slice(0, 40);
    console.error('dropbox token refresh refused:', r.status, code || '(no error code)');
    throw new Error('no_dropbox_auth');
  }
  const j = await r.json().catch(() => null);
  if (!j?.access_token) throw new AuthUnavailable('oauth2/token 200 without an access_token');
  return { token: String(j.access_token), expiresIn: Number(j.expires_in) || 14400 };
}

// Where the shared token lives. `get` answers the stored text (null: no row); `cas` writes `next`
// only if the stored text is still `prev` (null: insert only if absent) and says whether it did.
export interface TokenStore { get(): Promise<string | null>; cas(prev: string | null, next: string): Promise<boolean> }

export function memoryStore(): TokenStore {
  let v: string | null = null;
  return { get: () => Promise.resolve(v), cas: (p, n) => { if (v !== p) return Promise.resolve(false); v = n; return Promise.resolve(true); } };
}

// Stored as "<expires ms>|<lease-until ms>|<token>". A Dropbox token is [A-Za-z0-9._-], so '|' is safe.
type Entry = { exp: number; lease: number; token: string };
const parse = (s: string | null): Entry => {
  const [a, b, ...t] = String(s ?? '').split('|');
  return { exp: Number(a) || 0, lease: Number(b) || 0, token: t.join('|') };
};
const fmt = (e: Entry) => `${e.exp}|${e.lease}|${e.token}`;

export type CacheOpts = {
  now?: () => number; sleep?: (ms: number) => Promise<void>;
  deadline?: number;       // the run's wall clock: never wait or retry past it
  budgetMs?: number;       // how long one token() may spend waiting and retrying (default 30 s)
  marginMs?: number;       // refresh this long before expiry (default 10 min)
  leaseMs?: number;        // how long a refresher holds the lease (default 20 s, > the 10 s fetch timeout)
};

export class TokenCache {
  refreshes = 0; reused = 0; waits = 0;
  private mine: Entry | null = null;
  constructor(private store: TokenStore, private refresh: () => Promise<Refreshed>, private o: CacheOpts = {}) {}

  // A usable token. `rejected` is a token Dropbox just answered 401 to: it is never handed back.
  async token(rejected: string | null = null): Promise<string> {
    const now = this.o.now ?? Date.now, sleep = this.o.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
    const margin = this.o.marginMs ?? 600_000, leaseMs = this.o.leaseMs ?? 20_000;
    const usable = (e: Entry | null) => !!e && !!e.token && e.token !== rejected && e.exp - now() > margin;
    if (usable(this.mine)) return this.mine!.token;
    const until = Math.min(now() + (this.o.budgetMs ?? 30_000), this.o.deadline ?? Infinity);
    let fails = 0; let last: unknown = null;
    for (;;) {
      if (now() >= until) throw new AuthUnavailable('oauth2/token no shared token settled within the wait budget' + (last ? ': ' + (last as Error).message : ''));
      const raw = await this.store.get(); const e = parse(raw);
      if (usable(e)) { this.mine = e; this.reused++; return e.token; }
      if (e.lease > now()) {                        // another link is refreshing: wait for its token
        this.waits++; await sleep(250 + Math.floor(Math.random() * 500)); continue;
      }
      const leased = fmt({ ...e, lease: now() + leaseMs });
      if (!(await this.store.cas(raw, leased))) continue;   // someone moved first: read again
      let got: Refreshed;
      try { this.refreshes++; got = await this.refresh(); } catch (err) {
        await this.store.cas(leased, fmt({ ...e, lease: 0 })).catch(() => false);   // give the lease back
        if (!(err instanceof AuthUnavailable)) throw err;   // refused: 'no_dropbox_auth', loud, no retry
        last = err; fails++;
        const wait = Math.min(1000 * 2 ** (fails - 1), 8000) + Math.floor(Math.random() * 250);
        if (now() + wait >= until) throw new AuthUnavailable(`${(last as Error).message} (token refresh failed ${fails} time(s))`);
        await sleep(wait); continue;
      }
      const fresh: Entry = { exp: now() + got.expiresIn * 1000, lease: 0, token: got.token };
      await this.store.cas(leased, fmt(fresh)).catch(() => false);   // lost lease: the token is still good
      this.mine = fresh; return fresh.token;
    }
  }
}

export class DropboxClient {
  private token: string | null = null;
  constructor(readonly tokens: Pick<TokenCache, 'token' | 'refreshes' | 'reused'>, private f: Fetch = fetch) {}
  get refreshes() { return this.tokens.refreshes; }

  // host 'api': JSON arguments in the body. host 'content': arguments in Dropbox-API-Arg, bytes in the body.
  async call(host: 'api' | 'content', endpoint: string, arg: unknown, bytes?: Uint8Array): Promise<Response> {
    for (let attempt = 0; ; attempt++) {
      const token = this.token = this.token && attempt === 0 ? this.token : await this.tokens.token(attempt ? this.token : null);
      const init: RequestInit = host === 'api'
        // an endpoint with no arguments still takes the JSON body "null": an empty body is refused
        // (users/get_space_usage answered 500 to it, measured 15 Sep 2026)
        ? { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: apiArg(arg) }
        : { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': apiArg(arg) }, body: (bytes ?? new Uint8Array(0)) as BodyInit };
      const r = await this.f(`https://${host}.dropboxapi.com/2/${endpoint}`, init);
      if (r.status !== 401 || attempt > 0) return r;
      await r.body?.cancel();
    }
  }
}
