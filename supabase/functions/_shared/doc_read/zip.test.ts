// zip — archive listing, streamed inflation and the bomb / encryption / depth refusals.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/zip.test.ts
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { LIMITS, type ReadContext, type ReadResult } from './types.ts';
import { readCsv, readTxt } from './text.ts';
import { listZip, readZip, readZipEntry } from './zip.ts';
import { encryptedZipFixture, zipBombFixture, zipFixture } from './zip.fixtures.ts';
import { ARABIC_LINE, csvFixture } from './text.fixtures.ts';

const dispatch = (b: Uint8Array, filename: string, depth: number): Promise<ReadResult> => {
  const ctx: ReadContext = { filename, depth, readChild: dispatch };
  return filename.endsWith('.zip') ? readZip(b, ctx) : filename.endsWith('.csv') ? readCsv(b, ctx) : readTxt(b, ctx);
};

Deno.test('reads stored and deflated entries through the dispatcher, skipping directories, __MACOSX and dotfiles', async () => {
  const z = await zipFixture([
    { name: 'boq/', data: '', store: true },
    { name: 'boq/notes.txt', data: `Porcelain tiles 600x600  120 sqm\n${ARABIC_LINE}`, store: true },
    { name: 'boq/boq.csv', data: await csvFixture() },
    { name: '__MACOSX/boq/._boq.csv', data: 'junk' },
    { name: 'boq/.DS_Store', data: 'junk' },
  ]);
  const r = await dispatch(z, 'drawings.zip', 0);
  assert(r.ok);
  assertEquals(r.children.map((c) => c.name), ['boq/notes.txt', 'boq/boq.csv']);
  assert(r.children[0].doc.text.includes(ARABIC_LINE));
  assertEquals(r.children[1].doc.tables[0][1], ['Porcelain tiles 600x600, matt', '120', 'sqm', '45.50']);
});

Deno.test('a zip bomb is refused from the directory, before any entry is inflated', async () => {
  let calls = 0;
  const r = await readZip(await zipBombFixture(), { filename: 'b.zip', depth: 0, readChild: async (b, f, d) => { calls++; return dispatch(b, f, d); } });
  assert(!r.ok);
  assertEquals(r.error, 'zip_expands_too_far');
  assertEquals(calls, 0);
});

Deno.test('an encrypted entry refuses the archive', async () => {
  const r = listZip(await encryptedZipFixture());
  assert(!r.ok);
  assertEquals(r.error, 'encrypted');
});

Deno.test('nesting stops at LIMITS.maxDepth and is noted, not followed', async () => {
  const inner = await zipFixture([{ name: 'a.txt', data: 'Gypsum ceiling 85 sqm' }]);
  assertEquals((await readZip(inner, { filename: 'x.zip', depth: LIMITS.maxDepth }) as { error: string }).error, 'too_deep');
  const outer = await zipFixture([{ name: 'inner.zip', data: inner }]);
  const r = await dispatch(outer, 'outer.zip', LIMITS.maxDepth - 1);
  assert(r.ok);
  assertEquals(r.children.length, 0);
  assert(r.notes.some((n) => n.includes('too_deep')));
});

Deno.test('inflation aborts past the cap even when the directory under-declares the size', async () => {
  // Pseudo-random bytes: 100 KB of one letter deflates ~600:1 and is (rightly) refused as a bomb first.
  const noise = new Uint8Array(100_000);
  for (let i = 0, s = 7; i < noise.length; i++) { s = (s * 1103515245 + 12345) >>> 0; noise[i] = s >>> 24; }
  const z = await zipFixture([{ name: 'big.txt', data: noise }]);
  const l = listZip(z);
  assert(l.ok);
  await assertRejects(() => readZipEntry(z, { ...l.entries[0], size: 10 }, 1000), Error, 'inflates past');
  assertEquals((await readZipEntry(z, l.entries[0], 200_000)).length, 100_000);
});
