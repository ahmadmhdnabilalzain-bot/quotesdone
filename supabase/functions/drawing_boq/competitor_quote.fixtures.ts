// competitor_quote.fixtures — a competitor's priced QUOTATION as a customer uploads it, in the two forms they
// arrive in: a PDF with a text layer and an XLSX (10 Nov 2026, sales_engineer; founder 10 Nov: "a competitor's
// quotation a customer uploads is treated as an inquiry - quantities and specs - with names and prices removed and
// rebuilt in our template"). Pure, no I/O. Every party is ZZ DEMO, every address example.invalid, every phone a 000
// number, the TRN and IBAN are all-zero shapes: nothing here can reach a real person.
//
// What makes it a real quotation and not a clean bill: a letterhead (firm, P.O. Box, phone, e-mail, web, TRN), a
// quotation number, "To:" / "Attn:" / "Project:" lines, a Brand column, a description that wraps onto a second line,
// rates and amounts with thousands separators, Sub Total / VAT 5% / Grand Total, payment / validity / delivery terms,
// bank details with an IBAN, and a signature block with the salesman's name and mobile.
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';

/** The lines the quotation prices, as they must reach suppliers: description words, quantity, unit, spec (brand). */
export const QUOTE_LINES: { desc: RegExp; qty: number; unit: string; spec?: RegExp }[] = [
  { desc: /porcelain floor tiles 600x600.*adhesive and grout/i, qty: 145, unit: 'm2', spec: /RAK Ceramics/ },
  { desc: /porcelain skirting 100mm/i, qty: 96, unit: 'lm', spec: /RAK Ceramics/ },
  { desc: /gypsum board false ceiling 12\.5mm/i, qty: 132, unit: 'm2', spec: /Knauf/ },
  { desc: /emulsion paint to walls/i, qty: 410, unit: 'm2', spec: /Jotun/ },
  { desc: /solid core timber door 900x2100/i, qty: 7, unit: 'nos' },
  { desc: /aluminium sliding window 1500x1200/i, qty: 5, unit: 'nos', spec: /Alumil/ },
  { desc: /wall hung wc/i, qty: 3, unit: 'set', spec: /Grohe/ },
];
/** Every figure that is a PRICE on the quotation (rates, amounts, totals, VAT). None may reach a supplier. */
export const QUOTE_PRICES = ['85.00', '12,325', '12325', '25.00', '2,400', '65.00', '8,580', '8580', '18.50', '7,585', '7585', '1,850', '12,950', '12950',
  '2,200', '11,000', '1,450', '4,350', '4350', '59,190', '59190', '2,959', '62,149', '62149'];
/** Every string that names a party, the project or the job. Any one in a supplier-facing output is a FAIL. */
export const QUOTE_IDENTITY = ['Gulf Fitout', 'GULF FITOUT', 'zz-gulffitout', '000 0321', '0000321', '100000000000003', 'GFC/Q/2026/0912', 'Rashid Kareem',
  '000 0177', 'Palm Villa', 'Al Barsha', 'Sameer Nasser', '000 0444', 'AE070000000000000000000', 'Box 00000'];

const HEAD = ['S.No', 'Description', 'Brand', 'Qty', 'Unit', 'Rate (AED)', 'Amount (AED)'];
const ROWS: (string | number)[][] = [
  [1, 'Supply and install porcelain floor tiles 600x600mm, matt finish, laid on adhesive and grout', 'RAK Ceramics', 145, 'm2', '85.00', '12,325.00'],
  [2, 'Porcelain skirting 100mm high to match floor tiles, Palm Villa ground floor', 'RAK Ceramics', 96, 'lm', '25.00', '2,400.00'],
  [3, 'Gypsum board false ceiling 12.5mm on GI frame, taped and jointed, as per Gulf Fitout standard detail', 'Knauf', 132, 'm2', '65.00', '8,580.00'],
  [4, 'Emulsion paint to walls, one coat primer and two finish coats', 'Jotun Fenomastic', 410, 'm2', '18.50', '7,585.00'],
  [5, 'Solid core timber door 900x2100 with hardwood frame and ironmongery', '', 7, 'nos', '1,850.00', '12,950.00'],
  [6, 'Aluminium sliding window 1500x1200, double glazed', 'Alumil', 5, 'nos', '2,200.00', '11,000.00'],
  [7, 'Wall hung WC complete with concealed cistern and flush plate', 'Grohe', 3, 'set', '1,450.00', '4,350.00'],
];
const LETTERHEAD = [
  'ZZ DEMO GULF FITOUT CONTRACTING LLC',
  'P.O. Box 00000, Dubai, U.A.E.  |  Tel: +971 4 000 0321  |  Email: sales@zz-gulffitout.example.invalid',
  'www.zz-gulffitout.example.invalid   TRN: 100000000000003',
  'QUOTATION',
  'Quotation No: GFC/Q/2026/0912     Date: 08 Nov 2026',
  'To: ZZ DEMO Rashid Kareem',
  'Attn: ZZ DEMO Rashid Kareem, Mobile +971 50 000 0177',
  'Project: ZZ DEMO Palm Villa 14, Al Barsha South, Dubai',
  'Subject: Interior fit-out works',
];
const TAIL = [
  ['', 'Sub Total', '', '', '', '', '59,190.00'],
  ['', 'VAT 5%', '', '', '', '', '2,959.50'],
  ['', 'Grand Total (AED)', '', '', '', '', '62,149.50'],
];
const TERMS = [
  'Payment Terms: 50% advance, 40% on delivery, 10% on completion',
  'Validity: 30 days from the date of this quotation',
  'Delivery: 3 weeks from receipt of advance',
  'Bank: ZZ DEMO Bank, IBAN AE070000000000000000000',
  'For ZZ DEMO Gulf Fitout Contracting LLC',
  'ZZ DEMO Sameer Nasser, Sales Manager, +971 50 000 0444',
];

const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
/** The quotation as a one-page A4 PDF with a Helvetica text layer, laid out as a contractor's template prints it. */
export function competitorQuotePdf(): Uint8Array {
  const pw = 595, ph = 842, fs = 8;
  const tt = (x: number, y: number, s: string, size = fs) => `BT /F1 ${size} Tf 1 0 0 1 ${x.toFixed(1)} ${(ph - y).toFixed(1)} Tm (${esc(s)}) Tj ET\n`;
  // Right-aligned figures, as every quotation template prints them (Helvetica digits are 0.556 em).
  const rt = (right: number, y: number, s: string) => tt(right - s.length * fs * 0.556, y, s);
  let s = tt(40, 40, LETTERHEAD[0], 13);
  LETTERHEAD.slice(1, 3).forEach((l, i) => { s += tt(40, 58 + i * 12, l); });
  s += tt(260, 100, LETTERHEAD[3], 14);
  LETTERHEAD.slice(4).forEach((l, i) => { s += tt(40, 122 + i * 12, l); });
  const X = [40, 66, 272, 382, 394, 472, 555];                       // left edges; figures right-aligned to these
  let y = 210;
  HEAD.forEach((h, k) => { s += k === 3 || k >= 5 ? rt(X[k], y, h) : tt(X[k], y, h); });
  y += 16;
  for (const r of ROWS) {
    // The description wraps at 40 characters onto a second line, under the first.
    const d = String(r[1]); const cut = d.length > 40 ? d.lastIndexOf(' ', 40) : d.length;
    s += tt(X[0], y, String(r[0])) + tt(X[1], y, d.slice(0, cut)) + (r[2] ? tt(X[2], y, String(r[2])) : '') + rt(X[3], y, String(r[3])) + tt(X[4], y, String(r[4])) + rt(X[5], y, String(r[5])) + rt(X[6], y, String(r[6]));
    if (cut < d.length) { y += 10; s += tt(X[1], y, d.slice(cut + 1)); }
    y += 16;
  }
  for (const r of TAIL) { s += tt(X[1], y, String(r[1])) + rt(X[6], y, String(r[6])); y += 14; }
  y += 20;
  for (const l of TERMS) { s += tt(40, y, l); y += 12; }
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [4 0 R] /Count 1 >>', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pw} ${ph}] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>`, `<< /Length ${s.length} >>\nstream\n${s}\nendstream`,
    '<< /Title (Quotation GFC/Q/2026/0912 ZZ DEMO Palm Villa) /Author (ZZ DEMO Sameer Nasser) /Producer (ZZ DEMO Gulf Fitout ERP) >>'];
  let out = '%PDF-1.4\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return new TextEncoder().encode(out + 'trailer\n<< /Root 1 0 R /Info 6 0 R >>\n%%EOF\n');
}

/** The same quotation as an XLSX the contractor's estimator exported: letterhead rows above the table. */
export function competitorQuoteXlsx(): Uint8Array {
  const aoa: (string | number)[][] = [...LETTERHEAD.map((l) => [l]), [], HEAD, ...ROWS, ...TAIL, [], ...TERMS.map((l) => [l])];
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), 'Quotation GFC-Q-0912');
  return new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
}
export const QUOTE_FILE = 'GFC-Q-2026-0912 ZZ Palm Villa quotation';
