// THE LEAD SOURCING KICK SENDS THE PUBLISHABLE KEY, NOT THE LEGACY ANON JWT (it_engineer, 27 Oct 2026).
// docs/reports/security/SECURITY_HARDENING_27_OCT.md item 3, consumer A4: fn_lead_sourcing_kick() was the one
// routine body that sent the legacy anon JWT (app_secrets.anon_key) through the gateway.
//   1. static: the file's kick reads its key only through fn_gateway_client_key(), which prefers
//      app_secrets.publishable_key; the file carries no key value; the file has a pending note until it is applied
//      and the probe has a probe note for ever.
//   2. production (with a management token): the file and its probe, replayed in ONE transaction that always rolls
//      back, answer PROBE OK. The kick's request is queued and removed with the transaction, so nothing is sent.
//
//   node --test scripts/checks/the_lead_sourcing_kick_sends_the_publishable_key.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'the_lead_sourcing_kick_sends_the_publishable_key_not_the_legacy_anon_jwt';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const body = (src, fn) => {
  const i = src.search(new RegExp(`function public\\.${fn}\\(`, 'i'));
  if (i < 0) return null;
  const tag = src.slice(i).match(/as (\$[a-z_]*\$)/i)[1];
  const a = src.indexOf(tag, i) + tag.length;
  return code(src.slice(a, src.indexOf(tag, a)));
};

test('the kick reads its key through fn_gateway_client_key, which prefers the publishable key', () => {
  const src = R(FILE);
  const kick = body(src, 'fn_lead_sourcing_kick');
  assert.ok(kick, 'fn_lead_sourcing_kick is missing from the file');
  assert.match(kick, /v_anon := public\.fn_gateway_client_key\(\)/, 'the kick no longer reads its key through the helper');
  assert.doesNotMatch(kick, /key = 'anon_key'/, 'the kick reads app_secrets.anon_key directly again');
  const helper = body(src, 'fn_gateway_client_key');
  assert.ok(helper, 'fn_gateway_client_key is missing from the file');
  const pub = helper.indexOf("key = 'publishable_key'"); const legacy = helper.indexOf("key = 'anon_key'");
  assert.ok(pub > 0 && legacy > pub, 'the helper must try publishable_key first and anon_key only after it');
  for (const fn of ['fn_gateway_client_key', 'fn_lead_sourcing_kick']) {
    assert.match(src, new RegExp(`revoke execute on function public\\.${fn}\\(\\) from public, anon, authenticated`), `${fn} is not revoked`);
  }
  assert.doesNotMatch(src + R(PROBE), /eyJ[A-Za-z0-9_-]{10,}\.|sb_(publishable|secret)_[A-Za-z0-9]{20,}/, 'a key value is in the SQL');
});

test('the file waits in pending/ with a reason until it is applied; the probe is never applied', () => {
  const notes = pendingNotes();
  const listed = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(notes.has(FILE) !== listed.includes(FILE), 'the file needs exactly one of a pending note or a MANIFEST line');
  if (notes.has(FILE)) assert.ok(notes.get(FILE).length > 40, 'the pending note must say why and what moves it');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back: fallback to anon_key, new key sent as apikey and Bearer, nothing sent, nothing kept',
  { skip: hasToken ? false : 'no Supabase management token in this environment', timeout: 180000 }, async () => {
    const { sql } = await import('../lib/db.mjs');
    const before = await sql(`select count(*)::int n from public.app_secrets where key in ('publishable_key', 'anon_key', 'lead_sourcing_daily_quota')`);
    // While the change is pending, its file runs first in the same transaction; the probe's raise rolls both back.
    const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
    let msg = '';
    try { await replaySql(pre + R(PROBE), { retry: false }); msg = 'the probe did not raise'; } catch (e) { msg = String(e.message || e); }
    const m = msg.replace(/\\"/g, '"').match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 600));
    console.log('  ' + m[1]);
    assert.match(m[1], /^PROBE OK/, m[1]);
    const after = await sql(`select count(*)::int n from public.app_secrets where key in ('publishable_key', 'anon_key', 'lead_sourcing_daily_quota')`);
    assert.deepEqual(after, before, 'the probe changed app_secrets');
  });
