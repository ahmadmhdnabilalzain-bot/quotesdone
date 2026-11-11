// RETIRED 11 Nov 2026 (customer_support) WITH ITS SUBJECT, not softened to green. Founder ruling 1627: catalogue_read.readCatalogue
// (the Services tab's "Read my uploaded catalogue": exact names, then gte-small meaning over its headings) is deleted; a catalogue's
// services are understood by the reader model with the supplier's other documents (supplier_doc_trades.readTogether).
// A CATALOGUE LINE IS UNDERSTOOD BY MEANING, ON THE LIVE MODEL. Seat: sales_engineer. 21 Sep 2026.
//
// supabase/functions/_shared/service_meaning.test.ts proves the RULES on hand-made vectors. This proves
// what the real gte-small model does with real lines: the service names are embedded exactly as
// scripts/kb/embed_taxonomy_services.mjs embeds them (serviceEmbedText), through the free in-region
// ai_gateway {action:'embed'} path (not OpenRouter), and the lines are embedded the same way. Nothing is
// written; nobody is contacted. Skipped without a Supabase management token (CI has none).
//
//   node --test scripts/checks/a_catalogue_line_is_understood_by_meaning.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const ROOT = new URL('../../../', import.meta.url);
const SHARED = new URL('supabase/functions/_shared/', ROOT);

async function setup() {
  const { sql, PROJECT_REF } = await import('../../lib/db.mjs');
  const { liveServices } = await import('../../lib/service_vectors.mjs');
  const { proposeByMeaning, meaningCandidates, meaningClauses, meaningSpace } = await import(new URL('service_meaning.ts', SHARED).href);
  const { readCatalogue } = await import(new URL('catalogue_read.ts', SHARED).href);
  const { PAGES } = await import(new URL('catalogue_fixtures/make_zz_demo_catalogue.mjs', SHARED).href);
  // The services as production reads them once the release backfill has run (29 Sep 2026, decision point 93 (b)):
  // a stored vector whose text sha is current is used as stored; any other is embedded in memory through embed_ml,
  // exactly as scripts/kb/embed_taxonomy_services.mjs stores it (scripts/lib/service_vectors.mjs says how many).
  const { services, embed, stats } = await liveServices({ sql, PROJECT_REF, caller: 'a_catalogue_line_is_understood_by_meaning' });
  console.log('   service vectors:', JSON.stringify(stats));
  assert.equal(stats.failed, 0, 'a service vector could not be computed');
  // The lines read the way production reads them (supplier_services.meaningFor): clause by clause, each in its own
  // space, meaningCandidates' order and MEANING_MAX_LINES; a proposal's evidence is the supplier's whole line.
  const meaning = async (lines, svc, opts) => {
    const origin = new Map();
    for (const l of [...new Set(lines)]) for (const c of meaningClauses(l)) if (!origin.has(c)) origin.set(c, l);
    const read = await Promise.all(meaningCandidates([...origin.keys()], svc).map(async (text) => ({ text, space: meaningSpace(text), vec: await embed(text, meaningSpace(text)) })));
    assert.ok(read.every((l) => l.vec), 'embed_ml refused a line');
    return proposeByMeaning(read, svc, opts).map((p) => ({ ...p, lines: [...new Set(p.lines.map((c) => origin.get(c) ?? c))] }));
  };
  return { services, meaning, readCatalogue, PAGES };
}
let ctx;
const get = async () => (ctx ||= await setup());

test('the ZZ DEMO catalogue, words and meaning together, names what it sells and none of the false hits', { skip: SKIP, timeout: 600_000 }, async () => {
  const { services, meaning, readCatalogue, PAGES } = await get();
  const text = PAGES.map((p) => p.map(([l]) => l).join('\n')).join('\n');
  const c = readCatalogue(text, services);
  assert.equal(c.supply_only, true);
  const unnamed = c.rewrite.items.filter((i) => i.kind === 'unmatched').map((i) => i.text);
  const props = await meaning([...unnamed, ...c.lines.statements], services, { stated: c.rewrite.service_keys, supplyOnly: true });
  const keys = new Set([...c.rewrite.service_keys, ...props.map((p) => p.key)]);
  console.log('   meaning proposed:', JSON.stringify(props.map((p) => [p.key, p.similarity, p.because, p.word, p.lines[0]])));
  for (const k of ['it_services.hardware_supply', 'office_equipment.printers_mfp', 'office_equipment.photocopiers', 'office_equipment.toners_cartridges',
    'pos_retail.pos_terminals', 'pos_retail.receipt_printers', 'security_systems.cctv', 'power_generators.ups', 'av_it.audio_visual']) {
    assert.ok(keys.has(k), `missing ${k}`);
  }
  for (const k of ['electrical.wiring_install', 'logistics_moving.storage', 'electrical.lighting', 'it_services.network_install',
    'it_services.structured_cabling', 'security_systems.intruder_alarm']) assert.ok(!keys.has(k), `false hit ${k}`);
});

test('"we distribute office printers and copiers" is office equipment by meaning, with no alias to lean on', { skip: SKIP, timeout: 600_000 }, async () => {
  const { services, meaning } = await get();
  const bare = services.map((s) => ({ ...s, aliases: [] }));   // no keyword list: labels and vectors only
  const props = await meaning(['we distribute office printers and copiers'], bare, {});
  assert.equal(props.length, 1, JSON.stringify(props));
  assert.equal(props[0].trade, 'office_equipment');
  assert.equal(props[0].because, 'head_word');
});

test('"DVR Storage Upto 6TB" is never warehousing: a spec row to the reader, and no proposal to meaning', { skip: SKIP, timeout: 600_000 }, async () => {
  const { services, meaning, readCatalogue } = await get();
  const c = readCatalogue('CCTV KITS\nDVR Storage Upto 6TB', services);
  assert.equal(c.lines.spec_rows, 1);
  assert.ok(!c.rewrite.service_keys.includes('logistics_moving.storage'));
  // Even fed straight to the meaning layer, the line does not become storage.
  const props = await meaning(['DVR Storage Upto 6TB'], services, {});
  assert.ok(!props.some((p) => p.key === 'logistics_moving.storage'), JSON.stringify(props));
});
