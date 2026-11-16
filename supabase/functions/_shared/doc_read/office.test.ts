// office — docx / pptx / odt / ods / xlsx content, and the macro and encryption refusals.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/office.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocx, readOdf, readPptx, readWorkbook } from './office.ts';
import './workbook_local.ts'; // the SheetJS engine, as every function but supplier_api registers it (workbook_engine.ts)
import { docmFixture, docxFixture, odsFixture, odtFixture, pptxFixture, xlsxFixture } from './office.fixtures.ts';
import { ARABIC_LINE } from './text.fixtures.ts';

const ctx = { filename: 'f', depth: 0 };
const HEAD = ['Description', 'Qty', 'Unit', 'Rate'];

Deno.test('docx: paragraphs with tab and break, Arabic, table, header and footnote; deleted text dropped', async () => {
  const r = await readDocx(await docxFixture(), ctx);
  assert(r.ok);
  for (const want of ['Bill of Quantities\n', 'Porcelain tiles 600x600\t120 sqm', 'Line one\nLine two', ARABIC_LINE, 'Project: Villa 12', 'Rates exclude VAT.']) assert(r.text.includes(want), want);
  assert(!r.text.includes('deleted words'));
  assert(!r.text.startsWith('\t'));
  assertEquals(r.tables, [[HEAD, ['Porcelain tiles 600x600', '120', 'sqm', '45.50']]]);
});

Deno.test('pptx: slides in numeric order (2 before 10), text and table', async () => {
  const r = await readPptx(await pptxFixture(), ctx);
  assert(r.ok);
  const i1 = r.text.indexOf('# Slide 1\n'), i2 = r.text.indexOf('# Slide 2\n'), i10 = r.text.indexOf('# Slide 10\n');
  assert(i1 >= 0 && i1 < i2 && i2 < i10, r.text);
  assert(r.text.includes('Porcelain tiles 600x600  120 sqm') && r.text.includes(ARABIC_LINE));
  assertEquals(r.tables[0][0], HEAD);
});

Deno.test('odt: headings, text:s and text:tab, Arabic, typed table cells', async () => {
  const r = await readOdf(await odtFixture(), ctx);
  assert(r.ok);
  assertEquals(r.kind, 'odt');
  assert(r.text.includes('Porcelain tiles 600x600\t120 sqm') && r.text.includes(ARABIC_LINE));
  assertEquals(r.tables, [[HEAD, ['Porcelain tiles 600x600', 120, 'sqm', 45.5]]]);
});

Deno.test('ods: 16,380 repeated blank columns and 1,048,574 repeated blank rows do not become cells', async () => {
  const r = await readOdf(await odsFixture(), ctx);
  assert(r.ok);
  assertEquals(r.kind, 'ods');
  assertEquals(r.tables[0].length, 2);
  assertEquals(r.tables[0][0].length, 4);
});

Deno.test('xlsx: every sheet, cached formula values, never the formula', async () => {
  const r = await readWorkbook(await xlsxFixture(), ctx);
  assert(r.ok);
  assertEquals(r.kind, 'xlsx');
  assertEquals(r.tables[0][1], ['Porcelain tiles 600x600', 120, 'sqm', 45.5, 5460]);
  assert(r.text.includes(ARABIC_LINE) && r.text.includes('# Summary'));
  assert(!r.text.includes('B2*D2'));
});

Deno.test('ods through SheetJS gives the same table', async () => {
  const r = await readWorkbook(await odsFixture(), ctx);
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.kind, 'ods');
  assertEquals(r.tables[0][1].slice(0, 4), ['Porcelain tiles 600x600', 120, 'sqm', 45.5]);
});

Deno.test('a vbaProject.bin part is refused by the Word and the workbook readers', async () => {
  const b = await docmFixture();
  for (const r of [await readDocx(b, ctx), await readWorkbook(b, ctx)]) {
    assert(!r.ok);
    assertEquals(r.error, 'unsafe_file_content');
  }
});

Deno.test('a password-protected OOXML (OLE2 EncryptedPackage) is refused as encrypted', async () => {
  const name = 'EncryptedPackage';
  const b = new Uint8Array(512);
  b.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  for (let i = 0; i < name.length; i++) b[100 + i * 2] = name.charCodeAt(i);
  for (const r of [await readDocx(b, ctx), await readWorkbook(b, ctx)]) {
    assert(!r.ok);
    assertEquals(r.error, 'encrypted');
  }
});
