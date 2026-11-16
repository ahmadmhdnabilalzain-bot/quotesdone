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
  // servicePattern was kept for one reader, service_meaning.ts's corroboration (decision point 92); both were removed with
  // proposeByMeaning on 16 Nov 2026 (ruling 1627), so no file may define or call an alias pattern of a service again.
  const users = walk(join(ROOT, 'supabase', 'functions')).filter((f) => /servicePattern\(|servicesFromText\(|compileServices\(/.test(code(readFileSync(f, 'utf8'))))
    .map((f) => relative(ROOT, f).replace(/\\/g, '/'));
  assert.deepEqual(users.sort(), [],
    'a new caller matches service aliases in words');
  // THE INQUIRY SIDE READS NO WORDS AT ALL (11 Nov 2026, customer_support; founder rulings 1627 and 1628): serviceKeysOf, which read an
  // inquiry's prose by exact names and meaning, is deleted. An inquiry's keys are the intake model's or the customer's choice.
  const voc = code(R('supabase/functions/_shared/service_vocabulary.ts'));
  assert.ok(!/export (async )?function serviceKeysOf\(|export function keysInTrades\(/.test(voc), 'the prose reader of an inquiry is back');
  const callers = walk(join(ROOT, 'supabase', 'functions')).filter((f) => /\bserviceKeysOf\(|\bkeysInTrades\(/.test(code(readFileSync(f, 'utf8'))))
    .map((f) => relative(ROOT, f).replace(/\\/g, '/'));
  assert.deepEqual(callers, [], 'an inquiry is read for service keys by code again');
});

// THE CODE MEANING MATCHER IS GONE (16 Nov 2026, it_engineer; simplification wave A, DUP item 5; ruling 1627: a service is
// understood by the model reading the documents, never by code). proposeByMeaning, its candidate / clause / head-word / floor
// helpers, the second remote-embed client meaning_embed.ts and the three trade vocabulary readers had no runtime caller. What
// stays in service_meaning.ts is what the stored vectors need: serviceEmbedText / serviceMlText / textSha
// (scripts/kb/embed_taxonomy_services.mjs) and parseVec / MeaningService (service_vocabulary.serviceVocab).
test('no code meaning matcher is left: a service is named by the model or by its exact name', () => {
  assert.ok(!existsSync(join(SHARED, 'meaning_embed.ts')), 'meaning_embed.ts, the second remote-embed client, is back');
  const m = code(R('supabase/functions/_shared/service_meaning.ts'));
  for (const gone of ['proposeByMeaning', 'meaningCandidates', 'meaningClauses', 'corroborate', 'headWords', 'MEANING_FLOOR', 'ML_FLOOR', 'MEANING_MAX_LINES']) {
    assert.ok(!new RegExp(`export (const|function|async function) ${gone}\\b`).test(m), `service_meaning.ts exports ${gone} again`);
  }
  const voc = code(R('supabase/functions/_shared/service_vocabulary.ts'));
  for (const gone of ['tradeLabelVocab', 'tradeAliasVocab', 'tradeArNameVocab']) assert.ok(!voc.includes(gone), `service_vocabulary.ts: ${gone} is back`);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// The live reading of ZZ DEMO inquiry text by serviceKeysOf (production vectors + embed_ml) was deleted with serviceKeysOf on 11 Nov 2026
// (rulings 1627 and 1628): an inquiry's service keys are named by the intake model, so there is no code reading of its text to prove.
