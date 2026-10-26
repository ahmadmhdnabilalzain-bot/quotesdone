// ole.test — the .doc and .msg readers proved on in-memory fixtures, plus every refusal and cap.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDoc, readMsg } from './ole.ts';
import { MAX_ATTACHMENTS } from './email.ts';
import { docFixture, docMacroFixture, msgFixture, MSG_SUBJECT } from './ole.fixtures.ts';
import { ARABIC_LINE, BOQ_CSV, BOQ_LINE } from './email.fixtures.ts';
import { empty, ok, type ReadContext, type ReadResult } from './types.ts';

function stub(depth = 0) {
  const calls: { bytes: Uint8Array; name: string; depth: number }[] = [];
  const ctx: ReadContext = { filename: 'x', depth, readChild: (bytes, name, d) => { calls.push({ bytes, name, depth: d }); return Promise.resolve(ok(empty('csv'))); } };
  return { calls, ctx };
}
const must = (r: ReadResult) => { if (!r.ok) throw new Error(`${r.error}: ${r.detail}`); return r; };

Deno.test('doc: both pieces, the table, and a field result without its code', async () => {
  const r = must(await readDoc(docFixture(), stub().ctx));
  assertEquals(r.kind, 'doc');
  assert(r.text.includes(BOQ_LINE), r.text);
  assert(r.text.includes(ARABIC_LINE), r.text);
  assert(r.text.includes('See the drawing for sizes.'), r.text);
  assert(!r.text.includes('HYPERLINK'));
  assertEquals(r.tables, [[['Item', 'Qty'], ['Paint', '50']]]);
  assert(r.text.includes('Item\tQty\nPaint\t50'));
  assertEquals(r.notes, []);
});

Deno.test('doc: an unreadable piece table falls back to printable runs, marked approximate', async () => {
  const r = must(await readDoc(docFixture({ brokenClx: true }), stub().ctx));
  assert(r.text.includes(BOQ_LINE));
  assert(r.notes.some((n) => n.includes('approximate')));
});

Deno.test('doc: a macro project is refused', async () => {
  const r = await readDoc(docMacroFixture(), stub().ctx);
  assertEquals(r.ok ? 'ok' : r.error, 'unsafe_file_content');
});

Deno.test('doc: an encrypted document is refused', async () => {
  const r = await readDoc(docFixture({ encrypted: true }), stub().ctx);
  assertEquals(r.ok ? 'ok' : r.error, 'encrypted');
});

Deno.test('doc: bytes that are not OLE2 are refused', async () => {
  const r = await readDoc(new TextEncoder().encode('not a compound file at all'), stub().ctx);
  assertEquals(r.ok, false);
});

Deno.test('msg: subject, sender, body and the CSV attachment handed to readChild', async () => {
  const { calls, ctx } = stub();
  const r = must(await readMsg(msgFixture(), ctx));
  assertEquals(r.kind, 'msg');
  assert(r.text.startsWith(`Subject: ${MSG_SUBJECT}\nFrom: ZZ DEMO Buyer <buyer@example.invalid>\n\n`), r.text);
  assert(r.text.includes(BOQ_LINE));
  assertEquals(calls.length, 1);
  assertEquals([calls[0].name, calls[0].depth], ['boq.csv', 1]);
  assertEquals(calls[0].bytes, BOQ_CSV);
  assertEquals(r.children.map((c) => c.name), ['boq.csv']);
});

Deno.test('msg: attachments at LIMITS.maxDepth are not read', async () => {
  const { calls, ctx } = stub(2);
  const r = must(await readMsg(msgFixture(), ctx));
  assertEquals(calls.length, 0);
  assert(r.notes.some((n) => n.includes('levels deep')));
});

Deno.test('msg: attachment count is capped', async () => {
  const { calls, ctx } = stub();
  const r = must(await readMsg(msgFixture(MAX_ATTACHMENTS + 2), ctx));
  assertEquals(calls.length, MAX_ATTACHMENTS);
  assert(r.notes.some((n) => n.includes(`first ${MAX_ATTACHMENTS} attachments`)));
});
