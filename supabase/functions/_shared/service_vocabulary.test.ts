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
  'install ducting': [0.97, 0.1, 0.05],        // the clause meaning reads (meaningClauses cuts at 'and' and 'for')
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
  const lines = ['CCTV', ...Array.from({ length: Math.ceil(MEANING_MAX_LINES / 2) + 1 }, (_, k) => `zz demo item ${k} and zz demo part ${k}`)];   // two clauses a line: splitPhrases reads 40 phrases
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

// ── 29 Sep 2026: the vocabulary is read WHOLE, past PostgREST's max-rows ─────────────────────────────────────
// Measured on production the same day: an unpaged select of taxonomy_trade_service answered `0-999/1047`, so 47
// active services were invisible to exact and meaning matching. The stub below caps every read at 1,000 rows the
// way PostgREST does (and honours .range()); the vocabulary must still see all 1,500.
import { activeServiceRows, serviceVocab } from './service_vocabulary.ts';

function cappedAdmin(n: number, cap = 1000, failFrom = -1) {
  const rows = Array.from({ length: n }, (_, i) => ({
    trade_code: `t${String(i % 37).padStart(2, '0')}`, code: `s${String(i).padStart(4, '0')}`, sort: i % 5,
    label_en: `Service ${i}`, label_ar: 'خدمة', aliases: [], embedding_gte: '[1,0]', embedding_ml: '[0,1]',
  }));
  let reads = 0;
  const admin = {
    from: (_t: string) => {
      let lo = 0, hi = Infinity;
      const b = {
        select: () => b, eq: () => b, order: () => b,
        range: (a: number, z: number) => { lo = a; hi = z; return b; },
        then: (ok: (r: unknown) => void) => {
          reads++;
          if (failFrom >= 0 && lo >= failFrom) return ok({ data: null, error: { message: 'page failed' } });
          const sorted = [...rows].sort((x, y) => x.trade_code.localeCompare(y.trade_code) || x.sort - y.sort || x.code.localeCompare(y.code));
          ok({ data: sorted.slice(lo, Math.min(hi + 1, lo + cap)), error: null });
        },
      };
      return b;
    },
  };
  return { admin, reads: () => reads };
}

Deno.test('the whole vocabulary is read past a 1,000-row cap: 1,500 rows in, 1,500 services out, each once', async () => {
  const unpaged = cappedAdmin(1500);
  const one = await new Promise<unknown>((ok) => unpaged.admin.from('x').select().eq().order().then(ok)) as { data: unknown[] };
  assertEquals(one.data.length, 1000, 'the stub caps an unpaged read, as PostgREST does');

  const { admin } = cappedAdmin(1500);
  const v = await serviceVocab(admin);
  assertEquals(v.length, 1500);
  assertEquals(new Set(v.map((s) => `${s.trade_code}.${s.code}`)).size, 1500, 'no row skipped or repeated across pages');
  assert(v.every((s) => s.vec && s.vec_ml), 'every service carries both vectors, the multilingual one included');

  // A lower cap than the page size still reads everything (the loop advances by what each page returned).
  const low = await activeServiceRows(cappedAdmin(1500, 400).admin, 'trade_code,code');
  assertEquals(low.data.length, 1500);
});

Deno.test('a failed page is a failed read, never a partial vocabulary', async () => {
  assertEquals(await serviceVocab(cappedAdmin(1500, 1000, 1000).admin), []);
  const r = await activeServiceRows(cappedAdmin(1500, 1000, 1000).admin, 'trade_code,code');
  assertEquals([r.data.length, !!r.error], [0, true]);
  // A server that ignores .range() answers the first page for ever: a bounded, failed read, not an endless loop.
  const deaf = { from: () => { const b: Record<string, unknown> = {}; const c = () => b;
    Object.assign(b, { select: c, eq: c, order: c, range: c, then: (ok: (r: unknown) => void) => ok({ data: [{ trade_code: 'a', code: 'b' }], error: null }) });
    return b; } };
  const d = await activeServiceRows(deaf, 'trade_code,code');
  assertEquals([d.data.length, !!d.error], [0, true]);
});
