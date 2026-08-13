// Attaching a document to the WRONG conversation looks exactly like attaching it to the right one,
// so the rule is executed here rather than only rendered.
//
//   node --test src/components/portal/comms/link.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { linkDocuments, documentCount, threadKey, isChannelThread } from './link.ts';

const T1 = { inquiry_id: 'inq-a', supplier_id: 7 };
const T2 = { inquiry_id: 'inq-b', supplier_id: 7 };   // SAME supplier, different RFQ
const T3 = { inquiry_id: 'inq-a', supplier_id: 9 };   // same RFQ, different supplier

const drawing = { id: 1, ref_table: 'inquiries', ref_id: 'inq-a' };
const licence = { id: 2, ref_table: 'leads', ref_id: '7' };
const quoteFile = { id: 3, ref_table: 'quotes', ref_id: 'quote-xyz' };
const otherRfq = { id: 4, ref_table: 'inquiries', ref_id: 'inq-b' };

test('a document filed against an RFQ reaches only the conversations about THAT RFQ', () => {
  const { byThread } = linkDocuments([T1, T2, T3], [drawing]);
  assert.deepEqual(byThread[threadKey(T1)].rfq.map((d) => d.id), [1]);
  assert.deepEqual(byThread[threadKey(T3)].rfq.map((d) => d.id), [1]); // same RFQ, other supplier
  assert.deepEqual(byThread[threadKey(T2)].rfq, []);                   // different RFQ
});

test("a supplier's own document reaches every conversation with that supplier, and no other", () => {
  const { byThread } = linkDocuments([T1, T2, T3], [licence]);
  assert.deepEqual(byThread[threadKey(T1)].supplier.map((d) => d.id), [2]);
  assert.deepEqual(byThread[threadKey(T2)].supplier.map((d) => d.id), [2]);
  assert.deepEqual(byThread[threadKey(T3)].supplier, []);
});

test('supplier ids compare across the number/string boundary the two endpoints disagree on', () => {
  // messages_api returns supplier_id as a NUMBER; documents.ref_id is TEXT. A === here would file
  // every supplier document under "unlinkable" and the vault would look empty on every thread.
  const { byThread, unlinkable } = linkDocuments([{ inquiry_id: 'inq-a', supplier_id: 7 }], [licence]);
  assert.equal(documentCount(byThread['chat:inq-a:7']), 1);
  assert.deepEqual(unlinkable, []);
});

// ── THE COLLISION THAT OPENED THE WRONG CONVERSATION ───────────────────────────────────────────
// Measured 13 Aug 2026 in the browser, signed in as a real customer: messages_api returned a
// WhatsApp row and an e-mail row, both with inquiry_id: null and supplier_id: null. Under the old
// key both were the string "null:null", React logged a duplicate-key error, and clicking the row
// with the unread badge opened the OTHER one.
const WA = { channel: 'whatsapp', inquiry_id: null, supplier_id: null };
const EMAIL = { channel: 'email', inquiry_id: null, supplier_id: null };
const CALL = { channel: 'call', inquiry_id: null, supplier_id: null };

test('two channel rows with null ids do not share a key', () => {
  assert.notEqual(threadKey(WA), threadKey(EMAIL));
  assert.notEqual(threadKey(EMAIL), threadKey(CALL));
  assert.equal(new Set([WA, EMAIL, CALL].map(threadKey)).size, 3);
});

test('finding a thread by its key returns that thread, not the first null-id row', () => {
  const threads = [WA, EMAIL, CALL];
  const found = threads.find((t) => threadKey(t) === threadKey(EMAIL));
  assert.equal(found.channel, 'email');
});

test('a chat row keeps a key of its own and is not a channel row', () => {
  assert.equal(threadKey(T1), 'chat:inq-a:7');
  assert.equal(isChannelThread(T1), false);          // no channel field at all
  assert.equal(isChannelThread({ ...T1, channel: 'chat' }), false);
  assert.equal(isChannelThread(WA), true);
});

test('a document never attaches to a channel row', () => {
  // wa_messages and inbound_messages are not filed against an RFQ or a supplier, so nothing in the
  // vault can prove it belongs to one. The drawing must stay unlinkable rather than land there.
  const { byThread, unlinkable } = linkDocuments([WA, EMAIL], [drawing, licence]);
  assert.equal(documentCount(byThread[threadKey(WA)]), 0);
  assert.equal(documentCount(byThread[threadKey(EMAIL)]), 0);
  assert.deepEqual(unlinkable.map((d) => d.id), [1, 2]);
});

test('a quotation file is reported as unlinkable, never guessed onto a conversation', () => {
  // ref_id is the QUOTE id and neither payload maps a quote back to its RFQ. Guessing by supplier
  // name would file this under whichever of T1/T2 sorted first — both are supplier 7.
  const { byThread, unlinkable } = linkDocuments([T1, T2], [quoteFile]);
  assert.equal(documentCount(byThread[threadKey(T1)]), 0);
  assert.equal(documentCount(byThread[threadKey(T2)]), 0);
  assert.deepEqual(unlinkable.map((d) => d.id), [3]);
});

test('every thread gets a bucket, so an empty conversation renders as empty and not as undefined', () => {
  const { byThread } = linkDocuments([T1, T2], []);
  assert.deepEqual(byThread[threadKey(T1)], { rfq: [], supplier: [] });
  assert.equal(documentCount(byThread[threadKey(T2)]), 0);
  assert.equal(documentCount(byThread['no-such-thread']), 0);
});

test('a document reaching two conversations is not consumed by the first', () => {
  const { byThread, unlinkable } = linkDocuments([T1, T2], [licence, drawing, otherRfq, quoteFile]);
  assert.equal(documentCount(byThread[threadKey(T1)]), 2); // licence + inq-a drawing
  assert.equal(documentCount(byThread[threadKey(T2)]), 2); // licence + inq-b document
  assert.deepEqual(unlinkable.map((d) => d.id), [3]);
});

test('null refs and empty inputs do not throw', () => {
  assert.deepEqual(linkDocuments([], []), { byThread: {}, unlinkable: [] });
  assert.deepEqual(linkDocuments(null, null), { byThread: {}, unlinkable: [] });
  const { unlinkable } = linkDocuments([T1], [{ id: 9, ref_table: 'inquiries', ref_id: null }]);
  assert.deepEqual(unlinkable.map((d) => d.id), [9]);
});
