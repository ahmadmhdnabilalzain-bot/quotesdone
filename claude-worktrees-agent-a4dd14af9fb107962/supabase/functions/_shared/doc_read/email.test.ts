// email.test — the .eml reader proved on fixtures: real content out, attachments handed on, caps hold.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readEml, MAX_PARTS } from './email.ts';
import { ARABIC_LINE, BOQ_CSV, BOQ_LINE, SUBJECT, emlFixture, emlNestedFixture } from './email.fixtures.ts';
import { empty, ok, type ReadContext, type ReadResult } from './types.ts';

function stub(depth = 0) {
  const calls: { bytes: Uint8Array; name: string; depth: number }[] = [];
  const ctx: ReadContext = { filename: 'x.eml', depth, readChild: (bytes, name, d) => { calls.push({ bytes, name, depth: d }); return Promise.resolve(ok(empty('csv'))); } };
  return { calls, ctx };
}
const must = (r: ReadResult) => { if (!r.ok) throw new Error(`${r.error}: ${r.detail}`); return r; };

Deno.test('eml: subject, body, quoted-printable Arabic and the CSV attachment', async () => {
  const { calls, ctx } = stub();
  const r = must(await readEml(emlFixture(), ctx));
  assertEquals(r.kind, 'eml');
  assert(r.text.includes(`Subject: ${SUBJECT}`), r.text);
  assert(r.text.includes('From: ZZ DEMO Buyer <buyer@example.invalid>'));
  assert(r.text.includes(BOQ_LINE));
  assert(r.text.includes(ARABIC_LINE), r.text);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].name, 'boq.csv');
  assertEquals(calls[0].depth, 1);
  assertEquals(calls[0].bytes, BOQ_CSV);
  assertEquals(r.children.map((c) => c.name), ['boq.csv']);
});

Deno.test('eml: an attached eml is read as an eml child, its attachment one level deeper', async () => {
  const { calls, ctx } = stub();
  const r = must(await readEml(emlNestedFixture(), ctx));
  assert(r.text.includes('See the attached request.'));
  assertEquals(r.children[0].name, 'inner.eml');
  assertEquals(r.children[0].doc.kind, 'eml');
  assert(r.children[0].doc.text.includes(BOQ_LINE));
  assertEquals(calls.map((c) => [c.name, c.depth]), [['boq.csv', 2]]);
  assertEquals(calls[0].bytes, BOQ_CSV);
});

Deno.test('eml: nesting past LIMITS.maxDepth is refused with a note', async () => {
  const { calls, ctx } = stub(1); // outer at 1 -> inner eml at 2 -> its csv would be 3
  const r = must(await readEml(emlNestedFixture(), ctx));
  assertEquals(calls.length, 0);
  assert(r.children[0].doc.notes.some((n) => n.includes('levels deep')), JSON.stringify(r.children[0].doc.notes));
});

Deno.test('eml: more than MAX_PARTS parts stops with a note', async () => {
  const parts = Array.from({ length: MAX_PARTS + 5 }, (_, i) => `--b\r\nContent-Type: text/plain\r\n\r\nline ${i}\r\n`).join('');
  const { ctx } = stub();
  const r = must(await readEml(new TextEncoder().encode(`Subject: many\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n${parts}--b--\r\n`), ctx));
  assert(r.notes.some((n) => n.includes(`first ${MAX_PARTS} MIME parts`)));
  assert(r.text.includes('line 0') && !r.text.includes(`line ${MAX_PARTS + 4}`));
});

Deno.test('eml: HTML-only body is stripped, script content dropped', async () => {
  const { ctx } = stub();
  const html = '<html><head><style>p{}</style></head><body><script>alert(1)</script><p>Gypsum&nbsp;ceiling 85 sqm</p></body></html>';
  const r = must(await readEml(new TextEncoder().encode(`Subject: h\r\nContent-Type: text/html; charset=utf-8\r\n\r\n${html}`), ctx));
  assert(r.text.includes('Gypsum ceiling 85 sqm'));
  assert(!r.text.includes('alert') && !r.text.includes('p{}'));
});

Deno.test('eml: bytes with no headers are refused', async () => {
  const r = await readEml(new TextEncoder().encode('just some words\nand more'), stub().ctx);
  assertEquals(r.ok, false);
});
