// One read-only reading of how full the company Dropbox is (it_engineer, 15 Sep 2026).
//
//   deno run --allow-net --allow-env --allow-read scripts/it/dropbox_space_reading.ts
//
// Uses dropbox_backup's own DropboxClient and refresh. Calls only users/get_space_usage and
// users/get_current_account, which change nothing. Prints numbers and the plan name only: no token,
// no secret and no response body is ever written out, including on failure.
import { DropboxClient, memoryStore, refreshAccessToken, TokenCache } from '../../supabase/functions/dropbox_backup/dropbox.ts';

const REF = 'htdblwldjkcgjvmqkbeh';
const fail = (stage: string, status?: number) => { console.log(JSON.stringify({ ok: false, stage, status })); Deno.exit(1); };

const home = Deno.env.get('USERPROFILE') ?? Deno.env.get('HOME') ?? '';
const mgmt = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? await Deno.readTextFile(home + '/.supabase/access-token')).trim();
const q = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
  method: 'POST', headers: { Authorization: 'Bearer ' + mgmt, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: "select key, value from public.app_secrets where key in ('dropbox_refresh_token', 'dropbox_app_key', 'dropbox_app_secret')" }),
});
if (!q.ok) { await q.body?.cancel(); fail('read app_secrets', q.status); }
const s: Record<string, string> = Object.fromEntries(((await q.json()) as { key: string; value: string }[]).map((r) => [r.key, r.value]));

try {
  // an in-memory store: this read-only script never writes the shared token back to app_secrets
  const dbx = new DropboxClient(new TokenCache(memoryStore(), () => refreshAccessToken(s.dropbox_refresh_token, s.dropbox_app_key, s.dropbox_app_secret)));
  const u = await dbx.call('api', 'users/get_space_usage', null);
  if (!u.ok) { await u.body?.cancel(); fail('get_space_usage', u.status); }
  const j = await u.json();
  const a = await dbx.call('api', 'users/get_current_account', null);
  const plan = a.ok ? String((await a.json()).account_type?.['.tag'] ?? '') : 'unknown';
  const used = Number(j.used), allocated = Number(j.allocation?.allocated ?? 0);
  console.log(JSON.stringify({
    ok: true, read_at: new Date().toISOString(), plan, allocation: j.allocation?.['.tag'],
    used_gb: +(used / 1e9).toFixed(2), allocated_gb: +(allocated / 1e9).toFixed(2),
    pct_used: allocated > 0 ? +(used * 100 / allocated).toFixed(1) : null,
  }));
} catch (e) {
  // DropboxClient's own errors carry no secret ('no_dropbox_auth'); anything else is reduced to its name
  const m = String((e as Error)?.message || e);
  fail(m === 'no_dropbox_auth' ? 'no_dropbox_auth' : 'exception ' + ((e as Error)?.name ?? 'Error'));
}
