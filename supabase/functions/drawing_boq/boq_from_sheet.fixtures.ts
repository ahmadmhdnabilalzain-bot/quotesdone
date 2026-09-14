// boq_from_sheet.fixtures — one small BOQ file per bill convention, built in code (14 Sep 2026).
//
// WHY. boq_from_sheet's layout reading is proved on these, and a later before/after audit imports the
// same builders so both runs read byte-identical files. Pure functions: no I/O, no dates, no randomness.
// Every name is ZZ DEMO; no real project, company or person appears. Every file carries a price column
// and a total row, so a test can assert that neither reaches the BOQ.
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';

type Row = (string | number)[];
const quote = (c: string | number, d: string) => { const s = String(c); return s.includes(d) || /["\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const csv = (rows: Row[], d = ',') => new TextEncoder().encode(rows.map((r) => r.map((c) => quote(c, d)).join(d)).join('\r\n'));
function xlsx(rows: Row[], merges: string[] = []): Uint8Array {
  const ws = XLSX.utils.aoa_to_sheet(rows);
  if (merges.length) ws['!merges'] = merges.map((m) => XLSX.utils.decode_range(m));
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'BOQ');
  return new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
}

/** NRM 2 (UK/GCC QS) bill: Ref, Description, Qty, Unit, Rate, Amount £; bill and element headings, page total, collection. */
export const nrmCsv = () => csv([
  ['ZZ DEMO Warehouse — Bill of Quantities'], [],
  ['Ref', 'Description', 'Qty', 'Unit', 'Rate', 'Amount £'],
  ['', 'Bill No. 3 – Substructure', '', '', '', ''],
  ['', 'Element 2.1 – Excavation', '', '', '', ''],
  ['A', 'Excavate topsoil 150mm deep', '250', 'm2', '4.50', '1125.00'],
  ['B', 'Disposal of excavated material off site', '75', 'm3', '22.00', '1650.00'],
  ['C', 'Collection and disposal of site waste', '1', 'item', '300.00', '300.00'],
  ['', 'Page total', '', '', '', '3075.00'],
  ['', 'To collection', '', '', '', '3075.00'],
  ['', 'Collection', '', '', '', ''],
]);

/** FIDIC-style UAE bill: Bill No., Item No., Description, Unit, Qty, Rate (AED), Amount (AED); carried forward / to summary. */
export const fidicXlsx = () => xlsx([
  ['ZZ DEMO Villa, Dubai'], [],
  ['Bill No.', 'Item No.', 'Description', 'Unit', 'Qty', 'Rate (AED)', 'Amount (AED)'],
  [2, '', 'CONCRETE WORKS', '', '', '', ''],
  [2, '2.1', 'Blinding concrete 50mm thick', 'm3', 12.5, 350, 4375],
  [2, '2.2', 'Reinforced concrete isolated footings', 'm3', 48, 1200, 57600],
  ['', '', 'Total carried forward', '', '', '', 61975],
  ['', '', 'Carried to Summary', '', '', '', 61975],
]);

/** CSI MasterFormat: Section code, Description, Quantity, UOM; division headings in the Section column. */
export const masterformatCsv = () => csv([
  ['Section', 'Description', 'Quantity', 'UOM', 'Unit Price', 'Extended'],
  ['Division 03 – Concrete', '', '', '', '', ''],
  ['03 30 00', 'Cast-in-place concrete slab on grade', '85', 'CY', '180', '15300'],
  ['03 20 00', 'Concrete reinforcing', '4.2', 'TON', '1500', '6300'],
  ['Division 09 – Finishes', '', '', '', '', ''],
  ['09 91 23', 'Interior painting', '1200', 'SF', '1.10', '1320'],
  ['', 'Subtotal', '', '', '', '22920'],
]);

/** DIN 276 / GAEB-style export: semicolons, German decimals, Pos. / Kurztext / Menge / ME / EP / GP / KG. */
export const din276Csv = () => csv([
  ['Pos.', 'Kurztext', 'Menge', 'ME', 'EP', 'GP', 'KG'],
  ['', 'Bauwerk – Baukonstruktionen', '', '', '', '', '300'],
  ['01.0010', 'Mauerwerk KS 17,5 cm', '125,50', 'm2', '45,00', '5.647,50', '330'],
  ['01.0020', 'Stahlbeton Decke C25/30', '1.250,5', 'm3', '210,00', '262.605,00', '350'],
  ['', 'Übertrag', '', '', '', '268.252,50', ''],
  ['', 'Summe KG 300', '', '', '', '268.252,50', ''],
], ';');

/** Arabic bill: البند / الوصف / الكمية / الوحدة / السعر / المبلغ, with carried-forward and total rows and a phase heading. */
export const arabicXlsx = () => xlsx([
  ['جدول الكميات'], [],
  ['البند', 'الوصف', 'الكمية', 'الوحدة', 'السعر', 'المبلغ'],
  ['1', 'أعمال الخرسانة', '', '', '', ''],
  ['1.1', 'خرسانة مسلحة للأساسات', 40, 'م3', 900, 36000],
  ['1.2', 'خرسانة عادية', 10, 'م3', 400, 4000],
  ['', 'المجموع المرحل', '', '', '', 40000],
  ['', 'مرحل', '', '', '', 40000],
  ['2', 'المرحلة الثانية', '', '', '', ''],
  ['2.1', 'بلوك إسمنتي 20 سم', 300, 'م2', 50, 15000],
  ['', 'الإجمالي', '', '', '', 55000],
]);

/** Two-row header: "Quantity" merged over "Qty | Unit", "Rate" / "Amount" over "AED". */
export const twoRowHeaderXlsx = () => xlsx([
  ['Item', 'Description', 'Quantity', '', 'Rate', 'Amount'],
  ['', '', 'Qty', 'Unit', 'AED', 'AED'],
  ['1', 'Gypsum board false ceiling', 60, 'm2', 45, 2700],
  ['2', 'Access panels 600x600', 4, 'nos', 150, 600],
  ['', 'Total', '', '', '', 3300],
], ['A1:A2', 'B1:B2', 'C1:D1']);

/** Every fixture with the filename and declared MIME a customer upload would carry. */
export const SHEET_FIXTURES = {
  nrm: { bytes: nrmCsv, filename: 'nrm.csv', mime: 'text/csv' },
  fidic: { bytes: fidicXlsx, filename: 'fidic.xlsx', mime: '' },
  masterformat: { bytes: masterformatCsv, filename: 'masterformat.csv', mime: 'text/csv' },
  din276: { bytes: din276Csv, filename: 'din276.csv', mime: 'text/csv' },
  arabic: { bytes: arabicXlsx, filename: 'arabic.xlsx', mime: '' },
  two_row_header: { bytes: twoRowHeaderXlsx, filename: 'two_row.xlsx', mime: '' },
} as const;
