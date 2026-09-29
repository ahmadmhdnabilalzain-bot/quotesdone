// SERVICES ARE NAMED BY THEIR EXACT NAME OR BY MEANING, NEVER BY ALIAS WORDS
// (29 Sep 2026, sales_engineer; ruling 890, decision point 93 services.from_text).
//
// The supplier's Services-tab words and the customer's inquiry used to name services by alias words found inside
// them (service_rewrite.ts compileServices / hitsIn / servicesFromText). What fails if that returns:
//   * static: the alias index or servicesFromText is back; a caller names services from words; the inquiry side
//     stores a reading it could not finish as "names no service";
//   * live (token): the service vectors as production reads them after the release backfill (stored when current,
//     otherwise computed in memory by scripts/lib/service_vectors.mjs) and embed_ml (gte-small for English, the
//     multilingual e5 for Arabic; free, in-region, not OpenRouter) read ZZ DEMO inquiry text: a sentence clause by
//     clause, an exact name, key or curated alias exactly, Arabic in its own space, a nearest neighbour alone is
//     nothing, and a text too long to read whole gives no keys. Read-only: nothing is written, nobody is contacted.
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

test('production vectors + embed_ml, ZZ DEMO inquiry text: exact names, meaning by clause in both languages, no neighbour, all or nothing', { skip: SKIP, timeout: 900_000 }, async () => {
  const { sql, PROJECT_REF } = await import('../lib/db.mjs');
  const { liveServices } = await import('../lib/service_vectors.mjs');
  const { serviceKeysOf } = await import(pathToFileURL(join(SHARED, 'service_vocabulary.ts')).href);
  const { MEANING_MAX_LINES } = await import(pathToFileURL(join(SHARED, 'service_meaning.ts')).href);
  // The services as production reads them once the release backfill has run (scripts/lib/service_vectors.mjs).
  const { services, embed, stats } = await liveServices({ sql, PROJECT_REF, caller: 'services_are_named_by_exact_name_or_meaning' });
  console.log('  service vectors:', JSON.stringify(stats));
  assert.equal(stats.failed, 0, 'a service vector could not be computed');
  const deps = { services, embed };
  const read = async (t) => { const r = await serviceKeysOf(t, null, deps); console.log(`  ${JSON.stringify(t).slice(0, 70)} -> ${JSON.stringify(r)}`); return r; };

  // A customer's sentence: an alias word inside it names nothing by itself; meaning reads it clause by clause.
  const s1 = await read('ZZ DEMO villa: we need to supply and install ducting for the new majlis');
  assert.equal(s1.complete, true); assert.equal(s1.state, 'on');
  assert.ok(s1.keys.includes('hvac.ducting'), 'meaning did not read ducting from the sentence');
  // An exact name, an exact key and an exact curated alias need no model.
  const s2 = await read('False ceilings\ngypsum.partitions\nCable tray');
  assert.deepEqual([s2.keys, s2.state], [['electrical.cable_tray', 'gypsum.false_ceiling', 'gypsum.partitions'], 'exact']);
  // A nearest neighbour alone is nothing, in English and in Arabic.
  const s3 = await read('ZZ DEMO: Gold partner of the leading brands since 1990');
  assert.deepEqual([s3.keys, s3.complete], [[], true]);
  const s3ar = await read('نحن شركة رائدة لدينا خبرة طويلة، اتصل بنا اليوم');
  assert.deepEqual([s3ar.keys, s3ar.complete], [[], true]);
  // Arabic, in the multilingual space: the 21 Sep audit's sentence (finding 8) names its false ceilings by meaning.
  const s5 = await read('نقوم بأعمال الجبس والأسقف المستعارة والدهانات');
  assert.equal(s5.complete, true);
  assert.ok(s5.keys.includes('gypsum.false_ceiling'), 'the Arabic false ceilings were not read by meaning');
  assert.ok(s5.keys.every((k) => k.startsWith('gypsum.') || k.startsWith('painting.')), 'an Arabic clause was read as another trade: ' + s5.keys);
  // All or nothing: longer than the budget, no keys, not complete (never stored as "names nothing").
  // (MEANING_MAX_LINES + 2 clauses, two per line: splitPhrases reads at most 40 phrases.)
  const long = ['False ceilings', ...Array.from({ length: Math.ceil(MEANING_MAX_LINES / 2) + 1 }, (_, k) => `ZZ DEMO works ${k} and ZZ DEMO scope ${k}`)].join('\n');
  const s4 = await serviceKeysOf(long, null, { services, embed: async () => { throw new Error('must not be asked'); } });
  assert.deepEqual([s4.keys, s4.complete, s4.state], [[], false, 'too_long']);
});
