// THE SERVICE VOCABULARY IS READ WHOLE. Seat: sales_engineer. 29 Sep 2026.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/service_vocabulary.test.ts
//
// The tests of serviceKeysOf (an inquiry's prose read for service keys by exact names and meaning) were deleted with it on
// 11 Nov 2026 (customer_support; founder rulings 1627 and 1628): an inquiry's keys are the intake model's, matched in code.
import { assert, assertEquals } from 'jsr:@std/assert@1';

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
