// NO KEYLESS SEARCH SCRAPE IS LIVE.
//
// Founder ledger 1118 addendum (5 Oct 2026): "remove [the keyless search engine] totally". The keyless scrape was refused by a
// bot-check on every datacenter call, and its outage reached him as a decision he could not make
// (notifications#84149). The seats search through Serper (supabase/functions/_shared/web_search.ts).
//
// Fails if the engine's name appears, in any case, in supabase/functions (the runtime) or in a live routine body
// (supabase/schema/full_schema, the mirror kept equal to production on every PR). Applied historical SQL files
// and docs are exempt: they are the record of what was, not what runs. The name is assembled below rather than
// spelled, so this file cannot match itself.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const NAME = new RegExp(['duck', 'duck', 'go'].join(''), 'i');

function* files(dir) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) { if (e !== 'node_modules') yield* files(p); } else yield p;
  }
}

test('no runtime file names the keyless search scrape', () => {
  const hits = [...files('supabase/functions')].filter((p) => NAME.test(readFileSync(p, 'utf8')));
  assert.deepEqual(hits, [], 'remove it: ' + hits.join(', '));
});

test('no live routine body names the keyless search scrape', () => {
  const lines = readSchemaMirror().split('\n').filter((l) => NAME.test(l)).map((l) => l.trim().slice(0, 160));
  assert.deepEqual(lines, [], 'a live routine still names it; replace it through a new canonical SQL file');
});
