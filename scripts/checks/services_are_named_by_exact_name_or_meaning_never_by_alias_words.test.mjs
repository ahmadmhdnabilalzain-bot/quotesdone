// SERVICES ARE NAMED BY THEIR EXACT NAME OR BY MEANING, NEVER BY ALIAS WORDS
// (29 Sep 2026, sales_engineer; ruling 890, decision point 93 services.from_text).
//
// The supplier's Services-tab words and the customer's inquiry used to name services by alias words found inside
// them (service_rewrite.ts compileServices / hitsIn / servicesFromText). What fails if that returns:
//   * static: the alias index or servicesFromText is back; a caller names services from words; the inquiry side
//     stores a reading it could not finish as "names no service";
//   * live (token): production's stored service vectors and the real gte-small model (the free in-region
//     ai_gateway embed path, not OpenRouter) read ZZ DEMO inquiry text: a sentence is read by meaning, an exact
//     name exactly, a nearest neighbour alone is nothing, and a text too long to read whole gives no keys.
//     Read-only: nothing is written, nobody is contacted.
//
//   node --test scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const SHARED = join(ROOT, 'supabase', 'functions', '_shared');
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*\*)/.test(l)).map((l) => l.replace(/\s\/\/ .*$/, '')).join('\n');
const walk = (d, out = []) => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p, out); else if (/\.tsx?$/.test(n) && !/\.test\.tsx?$/.test(n)) out.push(p); } return out; };

test('no alias index and no word reader of services is left', () => {
  const rw = code(R('supabase/functions/_shared/service_rewrite.ts'));
  for (const gone of ['function compileServices(', 'function hitsIn(', 'function servicesFromText(', 'function leftovers(']) {
    assert.ok(!rw.includes(gone), `service_rewrite.ts: ${gone} is back`);
  }
  assert.match(rw, /export function exactService\(/);
  // servicePattern survives for one reader only: service_meaning.ts's corroboration (decision point 92).
  const users = walk(join(ROOT, 'supabase', 'functions')).filter((f) => /servicePattern\(|servicesFromText\(|compileServices\(/.test(code(readFileSync(f, 'utf8'))))
    .map((f) => relative(ROOT, f).replace(/\\/g, '/'));
  assert.deepEqual(users.sort(), ['supabase/functions/_shared/service_meaning.ts', 'supabase/functions/_shared/service_rewrite.ts'],
    'a new caller matches service aliases in words');
  const voc = code(R('supabase/functions/_shared/service_vocabulary.ts'));
  assert.match(voc, /proposeByMeaning\(/, 'the inquiry side does not read by meaning');
  assert.match(voc, /if \(pending\.length > MEANING_MAX_LINES\) return done\('too_long', false\);/, 'a partial reading could narrow who receives a request');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('production vectors + gte-small, ZZ DEMO inquiry text: meaning, exact, no neighbour, all or nothing', { skip: SKIP, timeout: 600_000 }, async () => {
  const { sql, PROJECT_REF } = await import('../lib/db.mjs');
  const { withRetry } = await import('../lib/retry.mjs');
  const { serviceKeysOf } = await import(pathToFileURL(join(SHARED, 'service_vocabulary.ts')).href);
  const { parseVec, MEANING_MAX_LINES } = await import(pathToFileURL(join(SHARED, 'service_meaning.ts')).href);
  const rows = await sql(`select trade_code, code, label_en, label_ar, aliases, embedding_gte::text as v from public.taxonomy_trade_service where active`);
  const services = rows.map(({ v, ...s }) => ({ ...s, vec: parseVec(v) }));
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  assert.ok(secret, 'no cred_fn_ai in app_secrets');
  const embed = async (text) => {
    const { r, j } = await withRetry(async () => {
      const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, fn: 'service_vocabulary', action: 'embed', text }),
      });
      const j = await r.json().catch(() => ({}));
      if (r.status === 503 && j.error === 'embed_failed') throw new Error('embed_failed (HTTP 503)');
      return { r, j };
    }, 3, 1000);
    assert.ok(r.status === 200 && j.ok === true && j.embedding, `the free embed path refused (HTTP ${r.status} ${j.error ?? ''})`);
    return JSON.parse(j.embedding);
  };
  const deps = { services, embed };
  const read = async (t) => { const r = await serviceKeysOf(t, null, deps); console.log(`  ${JSON.stringify(t).slice(0, 70)} -> ${JSON.stringify(r)}`); return r; };

  // A customer's sentence: an alias word inside it names nothing by itself; meaning reads it.
  const s1 = await read('ZZ DEMO villa: we need to supply and install ducting for the new majlis');
  assert.equal(s1.complete, true); assert.equal(s1.state, 'on');
  assert.ok(s1.keys.includes('hvac.ducting'), 'meaning did not read ducting from the sentence');
  // An exact name, and an exact key, need no model.
  const s2 = await read('False ceilings\ngypsum.partitions');
  assert.deepEqual([s2.keys, s2.state], [['gypsum.false_ceiling', 'gypsum.partitions'], 'exact']);
  // A nearest neighbour alone is nothing.
  const s3 = await read('ZZ DEMO: Gold partner of the leading brands since 1990');
  assert.deepEqual([s3.keys, s3.complete], [[], true]);
  // All or nothing: longer than the budget, no keys, not complete (never stored as "names nothing").
  const long = ['False ceilings', ...Array.from({ length: MEANING_MAX_LINES + 1 }, (_, k) => `ZZ DEMO line ${k} of the scope for the site`)].join('\n');
  const s4 = await serviceKeysOf(long, null, { services, embed: async () => { throw new Error('must not be asked'); } });
  assert.deepEqual([s4.keys, s4.complete, s4.state], [[], false, 'too_long']);
});
