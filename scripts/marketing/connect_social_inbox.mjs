// CONNECT THE SOCIAL INBOX — subscribes our Meta app and Page to the marketing seat's webhook.
//
// Seat: marketing. 22 Sep 2026. Measured by the coordinator (read-only): app_secrets.meta_access_token is a
// non-expiring system-user token with every messaging scope; me/accounts lists page QuotesDone (MESSAGING,
// MODERATE) and its Instagram business account; debug_token returns the app id. The ONE missing secret is
// meta_app_secret. With it stored, this script does the rest:
//   a. stores app_secrets.meta_webhook_verify_token (random) if it is absent;
//   b. POST /{app_id}/subscriptions for object=page and object=instagram (callback, verify token, fields)
//      with the app token app_id|app_secret — Meta calls the callback's GET handshake before accepting,
//      so marketing_social_inbox must be DEPLOYED first;
//   c. POST /{page_id}/subscribed_apps with the page token: messages, message_echoes, feed;
//   d. reads both back and prints a pass/fail table.
// Subscribing is safe while app_secrets.social_send_enabled is off: messages are received, stored and
// answered into the table as held_switch_off, and nothing is sent. This script never changes that switch.
// It prints no secret: tokens travel only in request bodies/URLs to graph.facebook.com and the Management API.
//
//   node scripts/marketing/connect_social_inbox.mjs            # all four steps
//   node scripts/marketing/connect_social_inbox.mjs --check    # d only (reads; writes nothing)
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { PROD_REF } from '../lib/qd_guard.mjs';

const CHECK_ONLY = process.argv.includes('--check');
const G = 'https://graph.facebook.com/v21.0/';
const CALLBACK = `https://${PROD_REF}.supabase.co/functions/v1/marketing_social_inbox`;
const PAGE_FIELDS = ['messages', 'message_echoes', 'feed'];
const IG_FIELDS = ['messages', 'comments'];

const mgmt = supabaseAccessToken();
async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmt, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  });
  const t = await r.text();
  if (!r.ok) throw new Error('management API ' + r.status + ': ' + t.slice(0, 200));
  return JSON.parse(t);
}
const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";
async function secret(key) {
  const rows = await sql(`select value from public.app_secrets where key = ${lit(key)}`);
  const v = String(rows[0]?.value ?? '').trim();
  return v || null;
}
async function graph(method, path, params) {
  const url = new URL(G + path);
  const body = new URLSearchParams(params);
  const r = method === 'GET'
    ? await fetch(url + '?' + body.toString())
    : await fetch(url, { method, body });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) throw new Error(`${method} ${path}: ${j?.error?.message || r.status}`); // the message never echoes a token
  return j;
}

const results = [];
const row = (step, ok, detail) => results.push({ step, result: ok ? 'PASS' : 'FAIL', detail });

const sys = await secret('meta_access_token');
const appSecret = await secret('meta_app_secret');
if (!sys) { console.error('app_secrets.meta_access_token is absent — nothing to derive the page from.'); process.exit(1); }
if (!appSecret) { console.error('app_secrets.meta_app_secret is absent. Store it first (the only missing secret), then re-run.'); process.exit(1); }

const dbg = await graph('GET', 'debug_token', { input_token: sys, access_token: sys });
const appId = String(dbg?.data?.app_id || '');
if (!appId) { console.error('debug_token returned no app_id.'); process.exit(1); }
const appToken = `${appId}|${appSecret}`;
const accounts = await graph('GET', 'me/accounts', { fields: 'id,name,access_token,instagram_business_account', access_token: sys });
const page = (accounts.data || []).find((a) => a.access_token);
if (!page) { console.error('me/accounts lists no page with a token.'); process.exit(1); }
const igId = page.instagram_business_account?.id || null;

if (!CHECK_ONLY) {
  // a. the verify token
  let verify = await secret('meta_webhook_verify_token');
  if (!verify) {
    verify = randomBytes(24).toString('hex');
    await sql(`insert into public.app_secrets (key, value) values ('meta_webhook_verify_token', ${lit(verify)}) on conflict (key) do nothing`);
    verify = await secret('meta_webhook_verify_token');   // what is stored wins if two runs raced
    row('a. verify token', !!verify, 'generated and stored');
  } else row('a. verify token', true, 'already stored');

  // b. the app's webhook subscriptions (Meta runs the GET handshake against the callback now)
  for (const [object, fields] of [['page', PAGE_FIELDS], ['instagram', IG_FIELDS]]) {
    try {
      await graph('POST', `${appId}/subscriptions`, { object, callback_url: CALLBACK, verify_token: verify, fields: fields.join(','), include_values: 'true', access_token: appToken });
      row(`b. app subscription ${object}`, true, fields.join(','));
    } catch (e) { row(`b. app subscription ${object}`, false, e.message); }
  }

  // c. the page subscribes the app
  try {
    await graph('POST', `${page.id}/subscribed_apps`, { subscribed_fields: PAGE_FIELDS.join(','), access_token: page.access_token });
    row('c. page subscribed_apps', true, `page ${page.name || page.id}`);
  } catch (e) { row('c. page subscribed_apps', false, e.message); }
}

// d. read back
try {
  const subs = (await graph('GET', `${appId}/subscriptions`, { access_token: appToken })).data || [];
  for (const [object, fields] of [['page', PAGE_FIELDS], ['instagram', IG_FIELDS]]) {
    const s = subs.find((x) => x.object === object);
    const have = new Set((s?.fields || []).map((f) => f.name));
    const missing = fields.filter((f) => !have.has(f));
    row(`d. app subscription ${object}`, !!s && s.active !== false && s.callback_url === CALLBACK && !missing.length,
      !s ? 'absent' : `callback ${s.callback_url === CALLBACK ? 'ours' : 'OTHER: ' + s.callback_url}; missing: ${missing.join(',') || 'none'}`);
  }
} catch (e) { row('d. app subscriptions', false, e.message); }
try {
  const apps = (await graph('GET', `${page.id}/subscribed_apps`, { access_token: page.access_token })).data || [];
  const ours = apps.find((a) => String(a.id) === appId);
  const have = new Set(ours?.subscribed_fields || []);
  const missing = PAGE_FIELDS.filter((f) => !have.has(f));
  row('d. page subscribed_apps', !!ours && !missing.length, !ours ? 'app not subscribed' : `missing: ${missing.join(',') || 'none'}`);
} catch (e) { row('d. page subscribed_apps', false, e.message); }

console.log(`app ${appId} · page ${page.name || ''} (${page.id}) · instagram ${igId || '(none linked)'} · callback ${CALLBACK}`);
console.table(results);
const send = await secret('social_send_enabled');
console.log(`social_send_enabled = ${send === 'on' ? 'on' : 'off'} (unchanged by this script)`);
process.exit(results.every((r) => r.result === 'PASS') ? 0 : 1);
