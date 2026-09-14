// boq_from_sheet — a customer's BOQ spreadsheet read with no model.
// deno test --no-lock supabase/functions/drawing_boq/boq_from_sheet.test.ts
//
// Both files are built HERE: an English CSV and an Arabic XLSX, each with a title block, a section
// heading, item lines, a rate column and a total row. The items must come back in drawing_boq's
// shape; the heading must become a section, not an item; the total and every price must be absent;
// an email in a cell must be scrubbed; and a formula must yield its CACHED value, never a computed one.
import { assert, assertEquals } from 'jsr:@std/assert@1';
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';
import { boqFromSheet, MAX_SHEET_BYTES } from './boq_from_sheet.ts';
import { SHEET_FIXTURES } from './boq_from_sheet.fixtures.ts';

const SHAPE = ['drawing_type', 'category', 'summary', 'scale_detected', 'total_area_sqm', 'boq', 'keywords', 'assumptions', 'missing_info', 'confidence'];

Deno.test('an English CSV BOQ becomes drawing_boq-shaped lines, without prices, totals or identity', () => {
  const csv = [
    'Villa fit-out BOQ,,,,,',
    ',,,,,',
    'Item,Description,Qty,Unit,Rate,Amount',
    'A,Flooring works,,,,',
    'A.1,Porcelain tiles 600x600 supplied and fixed,120.5,sqm,85,10242.50',
    'A.2,"Skirting, 100mm high",45,m,20,900',
    'A.3,Grout - samples from info@acme.ae,10,bags,15,150',
    ',Total,,,,11292.50',
  ].join('\r\n');
  const r = boqFromSheet(new TextEncoder().encode(csv), 'text/csv', 'boq.csv', 'villa');
  assert(r.ok, JSON.stringify(r));
  for (const k of SHAPE) assert(k in r.boq, `missing ${k}`);
  assertEquals(r.boq.boq.length, 3);
  assertEquals(r.boq.boq[0], { section: 'Flooring works', item: 'A.1', description: 'Porcelain tiles 600x600 supplied and fixed', qty: 120.5, unit: 'sqm', basis: 'CSV, row 5', confidence: 'medium' });
  assertEquals(r.boq.boq[1].description, 'Skirting, 100mm high');
  const all = JSON.stringify(r.boq);
  assert(!all.includes('acme'), 'email reached the BOQ');
  assert(!all.includes('10242') && !all.includes('11292'), 'a price or total reached the BOQ');
  assertEquals(r.boq.confidence, 'medium');
});

Deno.test('an Arabic XLSX BOQ is read by its Arabic headers; a formula gives its cached value', () => {
  const ws = XLSX.utils.aoa_to_sheet([
    ['جدول الكميات'],
    [],
    ['البند', 'الوصف', 'الكمية', 'الوحدة', 'السعر'],
    ['1', 'أعمال البلاط', '', '', ''],
    ['1.1', 'بلاط بورسلين 60×60', 80, 'م2', 50],
    ['1.2', 'دهان جدران', '٢٥٠', 'م2', 10],
    // Cached value 12, formula that would compute 999: the reader must say 12.
    ['1.3', 'عزل مائي', { t: 'n', v: 12, f: '999' }, 'م2', 30],
    ['', 'الإجمالي', '', '', 4500],
  ]);
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'BOQ');
  const bytes = new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
  const r = boqFromSheet(bytes, '', 'boq.xlsx');
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.boq.boq.map((b) => [b.section, b.item, b.qty, b.unit]), [
    ['أعمال البلاط', '1.1', 80, 'م2'],
    ['أعمال البلاط', '1.2', 250, 'م2'],
    ['أعمال البلاط', '1.3', 12, 'م2'],
  ]);
  assert(!JSON.stringify(r.boq).includes('4500'));
});

// ---- one fixture per bill convention (boq_from_sheet.fixtures.ts) ----------------------------------
const read = (k: keyof typeof SHEET_FIXTURES) => {
  const f = SHEET_FIXTURES[k];
  const r = boqFromSheet(f.bytes(), f.mime, f.filename);
  assert(r.ok, JSON.stringify(r));
  return r.boq;
};
const lines = (b: ReturnType<typeof read>) => b.boq.map((x) => [x.section, x.item, x.qty, x.unit]);
const noPrices = (b: ReturnType<typeof read>, ...p: string[]) => { const s = JSON.stringify(b.boq); for (const x of p) assert(!s.includes(x), `price or total ${x} reached the BOQ`); };

Deno.test('NRM bill: element heading is the section; page total, to collection and collection are skipped', () => {
  const b = read('nrm');
  assertEquals(b.layout, 'nrm');
  assertEquals(lines(b), [
    ['Element 2.1 – Excavation', 'A', 250, 'm2'],
    ['Element 2.1 – Excavation', 'B', 75, 'm3'],
    ['Element 2.1 – Excavation', 'C', 1, 'item'],               // "Collection and disposal ..." is work, not a collection row
  ]);
  noPrices(b, '1125', '3075');
});

Deno.test('FIDIC bill: Bill No. names the section; carried forward and carried to summary are skipped', () => {
  const b = read('fidic');
  assertEquals(b.layout, 'fidic');
  assertEquals(lines(b), [['Bill 2 CONCRETE WORKS', '2.1', 12.5, 'm3'], ['Bill 2 CONCRETE WORKS', '2.2', 48, 'm3']]);
  noPrices(b, '4375', '57600', '61975');
});

Deno.test('MasterFormat: division headings in the Section column; the section code is the item', () => {
  const b = read('masterformat');
  assertEquals(b.layout, 'masterformat');
  assertEquals(lines(b), [
    ['Division 03 – Concrete', '03 30 00', 85, 'cy'],
    ['Division 03 – Concrete', '03 20 00', 4.2, 'ton'],
    ['Division 09 – Finishes', '09 91 23', 1200, 'sf'],
  ]);
  noPrices(b, '15300', '22920');
});

Deno.test('DIN 276 export: German decimals, Kostengruppe as section, EP/GP never read', () => {
  const b = read('din276');
  assertEquals(b.layout, 'din276');
  assertEquals(lines(b), [['KG 330', '01.0010', 125.5, 'm2'], ['KG 350', '01.0020', 1250.5, 'm3']]);
  noPrices(b, '5.647', '262.605', '268.252');
});

Deno.test('Arabic bill: المجموع المرحل / مرحل / الإجمالي skipped, "المرحلة الثانية" stays a heading', () => {
  const b = read('arabic');
  assertEquals(b.layout, 'generic');
  assertEquals(lines(b), [
    ['أعمال الخرسانة', '1.1', 40, 'م3'],
    ['أعمال الخرسانة', '1.2', 10, 'م3'],
    ['المرحلة الثانية', '2.1', 300, 'م2'],
  ]);
  noPrices(b, '36000', '40000', '55000');
});

Deno.test('two-row header: "Quantity" merged over "Qty | Unit" still yields the unit', () => {
  const b = read('two_row_header');
  assertEquals(lines(b), [['BOQ', '1', 60, 'm2'], ['BOQ', '2', 4, 'nos']]);
  // The basis names the sheet by position, never by its name (leak audit, 14 Sep 2026).
  assertEquals(b.boq[0].basis, 'sheet 1, row 3');
  noPrices(b, '2700', '3300');
});

Deno.test('the original English CSV still reads as the generic layout', () => {
  const r = boqFromSheet(new TextEncoder().encode('Item,Description,Qty,Unit\n1,Paint,5,sqm'), 'text/csv', 'b.csv');
  assert(r.ok); assertEquals(r.boq.layout, 'generic');
});

Deno.test('an oversize file and a non-spreadsheet are refused before any parsing', () => {
  const big = boqFromSheet(new Uint8Array(MAX_SHEET_BYTES + 1).fill(0x41), 'text/csv', 'big.csv');
  assert(!big.ok); assertEquals(big.error, 'file_too_large');
  const html = boqFromSheet(new TextEncoder().encode('<!doctype html><script>alert(1)</script>'), 'text/csv', 'boq.csv');
  assert(!html.ok); assertEquals(html.error, 'unsafe_file_type');
});
