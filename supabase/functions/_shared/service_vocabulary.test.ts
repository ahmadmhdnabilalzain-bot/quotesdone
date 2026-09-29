// serviceKeysOf — the services an INQUIRY names: exactly, or by meaning over the stored vectors, all or nothing.
// Seat: sales_engineer. 29 Sep 2026 (ruling 890, decision point 93).
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/service_vocabulary.test.ts
//
// The keys gate who receives a request, so the rule under test is the one that protects suppliers: a text read
// only in part gives NO keys (trade level, nobody dropped), never the keys of the part that was read. The vectors
// here are hand-made; the live gte-small reading is proved by
// scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { serviceKeysOf, type ServiceKeysDeps } from './service_vocabulary.ts';
import { MEANING_MAX_LINES } from './service_meaning.ts';

const SERVICES = [
  { trade_code: 'hvac', code: 'ducting', label_en: 'Ducting & ventilation', label_ar: 'مجاري الهواء والتهوية', aliases: ['ducting', 'ductwork'], vec: [1, 0, 0] },
  { trade_code: 'gypsum', code: 'false_ceiling', label_en: 'False ceilings', label_ar: 'الأسقف المعلقة', aliases: ['false ceiling'], vec: [0, 1, 0] },
  { trade_code: 'security_systems', code: 'cctv', label_en: 'CCTV', label_ar: 'كاميرات المراقبة', aliases: ['cctv'], vec: [0, 0, 1] },
];
const VEC: Record<string, number[]> = {
  'Supply and install ducting for the villa': [0.97, 0.1, 0.05],
  'Gold partner of leading brands': [0.95, 0.2, 0.1],     // near ducting, no head word: never accepted
};
const deps = (o: Partial<ServiceKeysDeps> = {}): ServiceKeysDeps => ({ services: SERVICES, embed: async (t) => VEC[t] ?? [0.3, 0.3, 0.3], ...o });

Deno.test('an alias word in a sentence names nothing by itself; the sentence is read by meaning', async () => {
  const noModel = await serviceKeysOf('Supply and install ducting for the villa', null, deps({ embed: async () => null }));
  assertEquals([noModel.keys, noModel.complete, noModel.state], [[], false, 'embedding_unavailable']);
  const read = await serviceKeysOf('Supply and install ducting for the villa', null, deps());
  assertEquals([read.keys, read.complete, read.state], [['hvac.ducting'], true, 'on']);
});

Deno.test('the exact path: a phrase that IS a service, from the brief and from every string of the BOQ', async () => {
  const r = await serviceKeysOf('CCTV', { boq: [{ description: 'False ceilings' }, { description: 'hvac.ducting' }] }, deps({ embed: async () => { throw new Error('not needed'); } }));
  assertEquals([r.keys, r.complete, r.state], [['gypsum.false_ceiling', 'hvac.ducting', 'security_systems.cctv'], true, 'exact']);
});

Deno.test('a nearest neighbour alone is not a service', async () => {
  const r = await serviceKeysOf('Gold partner of leading brands', null, deps());
  assertEquals([r.keys, r.complete], [[], true]);
});

Deno.test('ALL OR NOTHING: a text too long to read whole gives no keys, even the exact ones', async () => {
  const lines = ['CCTV', ...Array.from({ length: MEANING_MAX_LINES + 1 }, (_, k) => `zz demo item number ${k} for the site`)];
  const r = await serviceKeysOf(lines.join('\n'), null, deps());
  assertEquals([r.keys, r.complete, r.state], [[], false, 'too_long']);
});

Deno.test('a failed reading is never "names nothing": vectors missing or the model down give complete=false', async () => {
  const noVec = await serviceKeysOf('Supply and install ducting for the villa', null, deps({ services: SERVICES.map((s) => ({ ...s, vec: null })) }));
  assertEquals([noVec.complete, noVec.state], [false, 'service_vectors_missing']);
  const oneDown = await serviceKeysOf('Supply and install ducting for the villa, Gold partner of leading brands', null,
    deps({ embed: async (t) => (t.startsWith('Gold') ? null : VEC[t]) }));
  assertEquals([oneDown.keys, oneDown.complete], [[], false]);
});

Deno.test('nothing to read is a real, complete answer; glue is not read', async () => {
  const r = await serviceKeysOf('', null, deps());
  assertEquals([r.keys, r.complete, r.state], [[], true, 'nothing_to_read']);
  let asked = 0;
  const glue = await serviceKeysOf('Dubai, Abu Dhabi', null, deps({ embed: async () => { asked++; return null; } }));
  assertEquals([glue.complete, asked], [true, 0]);
  assert(glue.keys.length === 0);
});
