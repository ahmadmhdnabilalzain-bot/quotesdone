// doc_extract's two workbook-engine ops (read_workbook, read_compound_file), as the handler answers them — no server.
// deno test --no-lock --node-modules-dir=none supabase/functions/doc_extract/workbook_op.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { encodeBase64 } from 'jsr:@std/encoding@1/base64';
import { workbookOp } from './workbook_op.ts';
import { REMOTE_READ_MAX_BYTES, type WorkbookEngine } from '../_shared/doc_read/workbook_engine.ts';
import { xlsxFixture } from '../_shared/doc_read/office.fixtures.ts';
import { docFixture } from '../_shared/doc_read/ole.fixtures.ts';

Deno.test('a body with no engine op is not this handler\'s (null: doc_extract carries on with its document queue)', async () => {
  assertEquals(await workbookOp({}), null);
  assertEquals(await workbookOp({ document_id: 7 }), null);
  assertEquals(await workbookOp({ op: 'something_else' }), null);
});

Deno.test('read_workbook answers the sheet names and rows the local SheetJS engine reads', async () => {
  const r = await workbookOp({ op: 'read_workbook', b64: encodeBase64(await xlsxFixture()) });
  assert(r);
  assertEquals(r.status, 200);
  assertEquals(r.body.ok, true);
  const names = r.body.names as string[], rows = r.body.rows as unknown[][][];
  assertEquals(names.length, rows.length);
  assert(names.includes('Summary'), JSON.stringify(names));
  assertEquals(rows[0][1], ['Porcelain tiles 600x600', 120, 'sqm', 45.5, 5460]);
});

Deno.test('read_compound_file answers every stream as [path, base64]; bytes that are no compound file answer null', async () => {
  const r = await workbookOp({ op: 'read_compound_file', b64: encodeBase64(docFixture()) });
  assert(r);
  assertEquals(r.status, 200);
  const entries = r.body.entries as [string, string][];
  assert(entries.some(([p]) => p === 'worddocument'), JSON.stringify(entries.map(([p]) => p)));
  const n = await workbookOp({ op: 'read_compound_file', b64: encodeBase64(new TextEncoder().encode('ZZ DEMO not a compound file')) });
  assertEquals(n?.body, { ok: true, entries: null });
});

Deno.test('a reader error is answered as {ok:false, message} with 422, never thrown', async () => {
  const failing: WorkbookEngine = { where: 'local', sheets: () => Promise.reject(new Error('File is password-protected')), compoundFile: () => Promise.resolve(null) };
  const r = await workbookOp({ op: 'read_workbook', b64: encodeBase64(new Uint8Array([1, 2, 3])) }, failing);
  assertEquals(r, { status: 422, body: { ok: false, error: 'unreadable', message: 'File is password-protected' } });
});

Deno.test('no bytes, bad base64 and too many bytes are refused before any read', async () => {
  let reads = 0;
  const counting: WorkbookEngine = { where: 'local', sheets: () => { reads++; return Promise.resolve({ names: [], rows: [] }); }, compoundFile: () => { reads++; return Promise.resolve(null); } };
  assertEquals((await workbookOp({ op: 'read_workbook' }, counting))?.status, 400);
  assertEquals((await workbookOp({ op: 'read_workbook', b64: '%%% not base64' }, counting))?.status, 400);
  const big = 'A'.repeat(Math.ceil((REMOTE_READ_MAX_BYTES + 3) / 3) * 4);
  const r = await workbookOp({ op: 'read_compound_file', b64: big }, counting);
  assertEquals(r?.status, 413);
  assertEquals(reads, 0);
});
