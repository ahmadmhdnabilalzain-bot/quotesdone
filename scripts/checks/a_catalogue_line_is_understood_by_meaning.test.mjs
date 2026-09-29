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

const ROOT = new URL('../../', import.meta.url);
const SHARED = new URL('supabase/functions/_shared/', ROOT);
const NEW_SQL = new URL('scripts/sql/a_catalogue_is_read_as_a_catalogue_and_two_trades_join_the_taxonomy.sql', ROOT);

async function setup() {
  const { sql, PROJECT_REF } = await import('../lib/db.mjs');
  const { withRetry } = await import('../lib/retry.mjs');
  const { serviceEmbedText, proposeByMeaning, parseVec } = await import(new URL('service_meaning.ts', SHARED).href);
  const { readCatalogue } = await import(new URL('catalogue_read.ts', SHARED).href);
  const { PAGES } = await import(new URL('catalogue_fixtures/make_zz_demo_catalogue.mjs', SHARED).href);
  const ALIASES = JSON.parse(readFileSync(new URL('service_aliases.json', SHARED), 'utf8'));
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  assert.ok(secret, 'no cred_fn_ai in app_secrets');
  // 22 Sep 2026 (instruction 645): this failed once in a full run with "refused (HTTP 200)" -- the gateway
  // then answered ok:true over a null vector. It now answers 503 embed_failed, and ONLY a 503 is retried,
  // three attempts in all; any other status, and a 503 that outlasts the retries, fails as before.
  const embed = async (text) => {
    const { r, j } = await withRetry(async () => {
      const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, fn: 'embed_taxonomy_services', action: 'embed', text }),
      });
      const j = await r.json().catch(() => ({}));
      if (r.status === 503 && j.error === 'embed_failed') throw new Error('embed_failed (HTTP 503)');
      return { r, j };
    }, 3, 1000);
    assert.ok(r.status === 200 && j.ok === true && j.embedding, `the free embed path refused (HTTP ${r.status} ${j.error ?? ''})`);
    return JSON.parse(j.embedding);
  };
  // The live services, plus this change's ten if the SQL file is not applied yet (read from the file).
  // The services carry the vector production reads (taxonomy_trade_service.embedding_gte, stored by
  // embed_taxonomy_services.mjs; supplier_services.ts parses it with parseVec). Re-embedding all 1,047 through the
  // gateway one by one took 6-7 minutes and timed the file out (29 Sep 2026) while measuring a path production never
  // takes. Only a service with no stored vector is embedded here - and that is itself the production gap to fix.
  const rows = await sql(`select s.trade_code, s.code, s.label_en, s.label_ar, t.label, t.label_ar as trade_label_ar, s.embedding_gte::text as stored
    from public.taxonomy_trade_service s join public.taxonomy_trade t on t.code = s.trade_code where s.active`);
  const have = new Set(rows.map((r) => `${r.trade_code}.${r.code}`));
  const src = readFileSync(NEW_SQL, 'utf8');
  const tradeLabel = Object.fromEntries([...src.matchAll(/\('(office_equipment|pos_retail)', '([^']+)', '([^']+)',/g)].map((m) => [m[1], [m[2], m[3]]]));
  for (const m of src.matchAll(/\('(office_equipment|pos_retail)','([a-z_]+)','([^']+)','([^']+)',\d+\)/g)) {
    if (!have.has(`${m[1]}.${m[2]}`)) rows.push({ trade_code: m[1], code: m[2], label_en: m[3], label_ar: m[4], label: tradeLabel[m[1]][0], trade_label_ar: tradeLabel[m[1]][1] });
  }
  const services = [];
  for (const r of rows) {
    const a = ALIASES[`${r.trade_code}.${r.code}`];
    const { stored, ...row } = r;
    services.push({ ...row, aliases: a ? [...a.en, ...a.ar] : [], vec: parseVec(stored) ?? await embed(serviceEmbedText(r, { label: r.label, label_ar: r.trade_label_ar })) });
  }
  const meaning = async (lines, svc, opts) => proposeByMeaning(await Promise.all(lines.map(async (text) => ({ text, vec: await embed(text) }))), svc, opts);
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
