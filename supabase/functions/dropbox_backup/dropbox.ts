// The one Dropbox HTTP client dropbox_backup uses (owner: it_engineer, 14 Sep 2026).
//
// The founder, 14 Sep 2026: "we need to eliminate all other causes with fixes. unless its a server
// issue from dropbox or supabase then i see no reason for any failures". An expired access token is
// not a Dropbox outage, so it must never become a failed backup:
//   * a fresh access token is taken from the offline refresh token at the start of every run
//     (Dropbox access tokens live 4 hours: expires_in 14400, measured 14 Sep 2026);
//   * any 401 is answered by refreshing once and repeating the same call once.
// A refresh that itself fails throws 'no_dropbox_auth' - the one auth failure only the founder can
// fix (the app's access was revoked), which the IT engineer classifies and emails.

// Dropbox-API-Arg is an HTTP header: everything outside ASCII must be \u-escaped (Arabic, emoji -
// each UTF-16 unit separately, which is what Dropbox expects for a surrogate pair).
export function apiArg(o: unknown): string {
  return Array.from(JSON.stringify(o).split(''), (c) => {
    const n = c.charCodeAt(0);
    return n > 0x7e ? '\\u' + n.toString(16).padStart(4, '0') : c;
  }).join('');
}

export type Fetch = (url: string, init: RequestInit) => Promise<Response>;

export class DropboxClient {
  private token: string | null = null;
  refreshes = 0;
  constructor(private refresh: () => Promise<string | null>, private f: Fetch = fetch) {}

  private async fresh(): Promise<string> {
    this.refreshes++;
    this.token = await this.refresh();
    if (!this.token) throw new Error('no_dropbox_auth');
    return this.token;
  }

  // host 'api': JSON arguments in the body. host 'content': arguments in Dropbox-API-Arg, bytes in the body.
  async call(host: 'api' | 'content', endpoint: string, arg: unknown, bytes?: Uint8Array): Promise<Response> {
    for (let attempt = 0; ; attempt++) {
      const token = this.token && attempt === 0 ? this.token : await this.fresh();
      const init: RequestInit = host === 'api'
        ? { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: arg === null ? undefined : apiArg(arg) }
        : { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': apiArg(arg) }, body: (bytes ?? new Uint8Array(0)) as BodyInit };
      const r = await this.f(`https://${host}.dropboxapi.com/2/${endpoint}`, init);
      if (r.status !== 401 || attempt > 0) return r;
      await r.body?.cancel();
    }
  }
}

export async function refreshAccessToken(rt: string, key: string, secret: string, f: Fetch = fetch): Promise<string | null> {
  if (!rt || !key || !secret) return null;
  const r = await f('https://api.dropboxapi.com/oauth2/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: rt, client_id: key, client_secret: secret }),
  });
  if (!r.ok) { await r.body?.cancel(); return null; }
  return (await r.json())?.access_token || null;
}
