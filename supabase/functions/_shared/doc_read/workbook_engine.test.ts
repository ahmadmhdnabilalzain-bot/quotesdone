// workbook_engine — readWorkbook, readDoc and readMsg take their parsed sheets / compound-file streams from the
// REGISTERED engine, and keep every safety check of their own in front of it.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/workbook_engine.test.ts
//
// No SheetJS engine is registered here on purpose: the stub engines below are plain data, so what is tested is
// office.ts / ole.ts around the engine, not SheetJS. (office.test.ts and ole.test.ts run the real local engine.)
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readWorkbook } from './office.ts';
import { readDoc, readMsg } from './ole.ts';
import { NO_WORKBOOK_READER, registerWorkbookEngine, SHEET_LIMITS, type WorkbookEngine } from './workbook_engine.ts';
import { docmFixture, xlsxFixture } from './office.fixtures.ts';
import { docFixture, msgFixture } from './ole.fixtures.ts';
import { LIMITS } from './types.ts';

const ctx = { filename: 'f', depth: 0, readChild: () => Promise.reject(new Error('not used')) };

function stub(over: Partial<WorkbookEngine> = {}): WorkbookEngine & { calls: number } {
  const e = {
    where: 'local' as const,
    calls: 0,
    sheets() { e.calls++; return Promise.resolve({ names: ['ZZ DEMO BOQ'], rows: [[['Description', 'Qty'], ['ZZ DEMO tiles', 12]]] }); },
    compoundFile() { e.calls++; return Promise.resolve(null); },
    ...over,
  };
  return e;
}

Deno.test('no engine registered: a workbook is refused as unreadable, never read as empty', async () => {
  registerWorkbookEngine(null);
  const r = await readWorkbook(await xlsxFixture(), ctx);
  assert(!r.ok);
  assertEquals(r.error, 'unreadable');
  assertEquals(r.detail, NO_WORKBOOK_READER);
});

Deno.test('no engine registered: a .doc and a .msg are refused the same way', async () => {
  registerWorkbookEngine(null);
  for (const r of [await readDoc(docFixture(), ctx), await readMsg(msgFixture(), ctx)]) {
    assert(!r.ok);
    assertEquals(r.error, 'unreadable');
    assertEquals(r.detail, NO_WORKBOOK_READER);
  }
});

Deno.test('the macro refusal comes before the engine: a vbaProject.bin workbook never reaches it', async () => {
  const e = stub();
  registerWorkbookEngine(e);
  const r = await readWorkbook(await docmFixture(), ctx);
  assert(!r.ok);
  assertEquals(r.error, 'unsafe_file_content');
  assertEquals(e.calls, 0);
});

Deno.test('the encrypted-OLE2 refusal comes before the engine', async () => {
  const e = stub();
  registerWorkbookEngine(e);
  const name = 'EncryptedPackage';
  const b = new Uint8Array(512);
  b.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  for (let i = 0; i < name.length; i++) b[100 + i * 2] = name.charCodeAt(i);
  const r = await readWorkbook(b, ctx);
  assert(!r.ok);
  assertEquals(r.error, 'encrypted');
  assertEquals(e.calls, 0);
});

Deno.test('the engine\'s sheets become the same text and tables; the 20-sheet note and the row cap stay in office.ts', async () => {
  const long = Array.from({ length: LIMITS.maxTableRows + 1 }, (_, i) => [`ZZ DEMO row ${i}`, i]);
  const names = Array.from({ length: 22 }, (_, i) => `S${i + 1}`);
  const rows = names.slice(0, SHEET_LIMITS.maxSheets).map((_, i) => (i === 0 ? long : i === 1 ? null : i === 2 ? [] : [['ZZ DEMO', i]]));
  registerWorkbookEngine(stub({ sheets: () => Promise.resolve({ names, rows }) }));
  const r = await readWorkbook(await xlsxFixture(), ctx);
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.kind, 'xlsx');
  assertEquals(r.tables[0].length, LIMITS.maxTableRows);
  assertEquals(r.tables.length, 1 + 17); // S1 capped, S2 missing, S3 empty, S4..S20 one row each; S21, S22 unread
  assert(r.notes.includes('22 sheets; only the first 20 were read'), JSON.stringify(r.notes));
  assert(r.notes.includes(`a table of ${LIMITS.maxTableRows + 1} rows stopped at ${LIMITS.maxTableRows}`));
  assert(r.text.startsWith('# S1\nZZ DEMO row 0\t0'));
  assert(!r.text.includes('# S2\n') && !r.text.includes('# S3\n') && !r.text.includes('# S21'));
});

Deno.test('an engine failure is a refusal, never a throw: password -> encrypted, anything else -> unreadable', async () => {
  registerWorkbookEngine(stub({ sheets: () => Promise.reject(new Error('File is password-protected')) }));
  const a = await readWorkbook(await xlsxFixture(), ctx);
  assert(!a.ok);
  assertEquals(a.error, 'encrypted');
  registerWorkbookEngine(stub({ sheets: () => Promise.reject(new Error('the workbook reader answered 503')) }));
  const b = await readWorkbook(await xlsxFixture(), ctx);
  assert(!b.ok);
  assertEquals(b.error, 'unreadable');
  assertEquals(b.detail, 'the workbook could not be read: the workbook reader answered 503');
});

Deno.test('a compound-file engine failure is a refusal; an engine that finds no compound file keeps the old answer', async () => {
  registerWorkbookEngine(stub({ compoundFile: () => Promise.reject(new Error('the workbook reader answered 403')) }));
  const a = await readDoc(docFixture(), ctx);
  assert(!a.ok);
  assertEquals(a.error, 'unreadable');
  assertEquals(a.detail, 'the compound file could not be read: the workbook reader answered 403');
  registerWorkbookEngine(stub());
  const b = await readMsg(msgFixture(), ctx);
  assert(!b.ok);
  assertEquals(b.error, 'unreadable_file');
  assertEquals(b.detail, 'not an OLE2 compound file');
  registerWorkbookEngine(null);
});
