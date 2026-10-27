// STORE THE PUBLISHABLE KEY IN app_secrets.publishable_key (it_engineer, 27 Oct 2026). Assigned: it_engineer.
//
// The data half of scripts/sql/the_lead_sourcing_kick_sends_the_publishable_key_not_the_legacy_anon_jwt.sql
// (docs/reports/security/SECURITY_HARDENING_27_OCT.md item 3, consumer A4). That file makes fn_lead_sourcing_kick()
// send app_secrets.publishable_key, falling back to the legacy anon_key while the row is absent. No key value is
// ever committed, so the row is written here, from the Management API's own listing, at release time.
//
//   node scripts/it/store_the_publishable_key_in_app_secrets.mjs           # DRY RUN: reads, compares, writes nothing
//   node scripts/it/store_the_publishable_key_in_app_secrets.mjs --apply   # writes the row, then reads it back
//
// It takes ONLY the key of type 'publishable' named 'default' (never the legacy anon JWT, never 'quotesdone2'),
// and refuses anything that does not look like an sb_publishable_ key. It prints no value: the read-back compares
// sha256 digests, computed on each side, and only "match" or "mismatch" is printed. Every error is redacted
// before it is shown, in case the database echoes the statement.
import { createHash } from 'node:crypto';
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { sql, lit, PROJECT_REF } from '../lib/db.mjs';

const APPLY = process.argv.includes('--apply');
const REDACT = /eyJ[A-Za-z0-9_.-]{10,}|sb_(publishable|secret)_[A-Za-z0-9_-]{6,}/g;
const say = (s) => console.log(String(s).replace(REDACT, '<key>'));
const sha = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

try {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/api-keys?reveal=true`,
    { headers: { Authorization: 'Bearer ' + supabaseAccessToken() } });
  const keys = await r.json().catch(() => null);
  if (!Array.isArray(keys)) throw new Error(`the Management API did not list the api keys (HTTP ${r.status})`);
  const pub = keys.find((k) => k?.type === 'publishable' && k?.name === 'default')?.api_key;
  if (typeof pub !== 'string' || !/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(pub)) {
    throw new Error("no usable publishable key named 'default' is listed; nothing written");
  }
  const want = sha(pub);
  const [row] = await sql(`select encode(sha256(convert_to(value, 'UTF8')), 'hex') d from public.app_secrets where key = 'publishable_key'`, { readOnly: true });
  say(`app_secrets.publishable_key: ${row ? (row.d === want ? 'present, matches the listed key' : 'present, DIFFERS from the listed key') : 'absent'}`);
  if (!APPLY) { say('dry run: nothing written (pass --apply)'); process.exit(0); }
  if (row?.d === want) { say('nothing to do'); process.exit(0); }
  await sql(`insert into public.app_secrets(key, value) values ('publishable_key', ${lit(pub)})
             on conflict (key) do update set value = excluded.value, updated_at = now()`, { retry: false });
  const [back] = await sql(`select encode(sha256(convert_to(value, 'UTF8')), 'hex') d from public.app_secrets where key = 'publishable_key'`, { readOnly: true });
  if (back?.d !== want) throw new Error('read-back mismatch: app_secrets.publishable_key is not the listed key');
  say('written; read-back digest matches the listed publishable key');
} catch (e) {
  say('FAILED: ' + (e?.message || e));
  process.exit(1);
}
