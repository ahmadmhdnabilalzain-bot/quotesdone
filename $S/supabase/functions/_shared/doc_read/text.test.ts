// text — TXT encodings, RFC 4180 CSV and group-aware RTF.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/text.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { LIMITS } from './types.ts';
import { parseDelimited, readCsv, readRtf, readTxt } from './text.ts';
import { ARABIC_LINE, csvFixture, rtfFixture, txt1256Fixture, txtFixture, txtUtf16leFixture } from './text.fixtures.ts';

const ctx = { filename: 'f', depth: 0 };

Deno.test('txt: UTF-8, UTF-16LE with BOM, and windows-1256 fallback all come out as the same words', async () => {
  const a = await readTxt(await txtFixture(), ctx);
  assert(a.ok && a.text.includes('Porcelain tiles 600x600  120 sqm') && a.text.includes(ARABIC_LINE));
  const b = await readTxt(await txtUtf16leFixture(), ctx);
  assert(b.ok && b.text.includes(ARABIC_LINE));
  const c = await readTxt(await txt1256Fixture(), ctx);
  assert(c.ok);
  assert(c.text.includes('بلاط 40 sqm'), c.text);
  assert(c.notes.includes('decoded as windows-1256'));
});

Deno.test('txt: text past LIMITS.maxTextChars is capped with a note', async () => {
  const r = await readTxt(new TextEncoder().encode(('x'.repeat(999) + '\n').repeat(500)), ctx);
  assert(r.ok);
  assert(r.text.length <= LIMITS.maxTextChars);
  assert(r.notes.some((n) => n.startsWith('text stopped')));
});

Deno.test('csv: quotes, doubled quotes, CRLF and Arabic', async () => {
  const r = await readCsv(await csvFixture(), ctx);
  assert(r.ok);
  assertEquals(r.tables[0], [
    ['Description', 'Qty', 'Unit', 'Rate'],
    ['Porcelain tiles 600x600, matt', '120', 'sqm', '45.50'],
    ['Skirting "10cm" high', '85', 'lm', '12'],
    [ARABIC_LINE, '40', 'sqm', '38'],
  ]);
  assert(r.text.includes('Porcelain tiles 600x600, matt\t120\tsqm\t45.50'));
});

Deno.test('csv: delimiter chosen from line 1; quoted newlines stay in the field; rows capped', () => {
  assertEquals(parseDelimited('a;b;c\n1;"2,5";3'), [['a', 'b', 'c'], ['1', '2,5', '3']]);
  assertEquals(parseDelimited('a\tb\n"x\ny"\t2\n'), [['a', 'b'], ['x\ny', '2']]);
  assertEquals(parseDelimited('n\n'.repeat(LIMITS.maxTableRows + 50)).length, LIMITS.maxTableRows);
});

Deno.test('rtf: body text, Arabic by \\fcharset178 bytes and \\u, tables; header, info, fonts and field codes skipped', async () => {
  const r = await readRtf(await rtfFixture(), ctx);
  assert(r.ok);
  for (const want of ['Bill of quantities', 'Porcelain tiles 600x600\t120 sqm', 'بلاط سيراميك', 'After table', 'link text']) assert(r.text.includes(want), want);
  for (const never of ['ACME', 'Secret title', 'evil.example', 'Arial', 'Riched20']) assert(!r.text.includes(never), never);
  assertEquals(r.tables, [[['Description', 'Qty', 'Unit', 'Rate'], ['Porcelain tiles 600x600', '120', 'sqm', '45.50']]]);
});
