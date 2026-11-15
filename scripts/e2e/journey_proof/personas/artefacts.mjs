// scripts/e2e/journey_proof/personas/artefacts.mjs — THE FILES REAL PEOPLE SEND, made for a persona journey. Seat:
// customer_support. A real villa owner sends a phone photo of a nameplate, not a spec sheet; a real small contractor sends a
// photo of a handwritten quotation, or a plain PDF, or a price range "subject to site visit". Every file here is ZZ DEMO:
// invented names, example.invalid addresses, the reserved +971 50 000 00xx block; nothing names a real person or company.
//
//   simplePdf(lines)          a plain one-page text PDF, written byte by byte (no browser, no dependency): what an office
//                             PC's "print to PDF" of a typed quotation looks like to a reader
//   quotePdf(...)             a supplier's own typed quotation, or his range "subject to site visit", as simplePdf
//   handwrittenPhoto(...)     a phone photo of a handwritten quotation: tilted paper, ink-blue script, uneven light (JPEG)
//   nameplatePhoto()          a phone photo of an outdoor unit's nameplate (JPEG)
// The photos are drawn with sharp (already in node_modules); each is under 200 KB.

const esc = (s) => String(s).replace(/[\\()]/g, (c) => '\\' + c).replace(/[^\x20-\x7e]/g, '?');
/** A one-page A4 text PDF; `lines` are [text] or [{ text, size, bold }]. */
export function simplePdf(lines, { title = 'Quotation' } = {}) {
  const L = lines.map((l) => (typeof l === 'string' ? { text: l } : l));
  let y = 800; const ops = [];
  for (const l of L) { const size = l.size || 10.5; y -= size + 5; ops.push(`BT /${l.bold ? 'F2' : 'F1'} ${size} Tf 56 ${y} Td (${esc(l.text)}) Tj ET`); }
  const stream = ops.join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(stream, 'latin1')} >>\nstream\n${stream}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    `<< /Title (${esc(title)}) /Producer (ZZ DEMO) >>`,
  ];
  let out = '%PDF-1.4\n'; const at = [];
  objs.forEach((o, i) => { at.push(Buffer.byteLength(out, 'latin1')); out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xref = Buffer.byteLength(out, 'latin1');
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${at.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')}`;
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R /Info 7 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

const aed = (n) => `AED ${Math.round(n).toLocaleString('en-US')}`;
/** The lines a supplier prices, with his rates: [{ description, qty, unit, rate, amount }]. */
export function pricedLines(lines, rateOf, factor = 1) {
  return lines.map((l) => { const rate = Math.round(rateOf(l.description) * factor); return { ...l, rate, amount: rate * (Number(l.qty) || 1) }; });
}
export const HVAC_RATE = (d) => /remov|dispos/i.test(d) ? 150 : /inspect|repair/i.test(d) ? 350 : /cassette/i.test(d) ? 6200 : /2\.0\s*tr|2\s*tr/i.test(d) ? 3100 : /split|unit/i.test(d) ? 2650 : /test|commission/i.test(d) ? 600 : 300;

/** A supplier's own typed quotation (kind 'proper') or his price range subject to a site visit (kind 'range'). */
export function quotePdf({ supplier, rfq, ref, lines, kind = 'proper', low = null, high = null }) {
  const sub = lines.reduce((a, l) => a + l.amount, 0); const vat = Math.round(sub * 0.05);
  const head = [{ text: supplier.letterhead || supplier.label, size: 15, bold: true }, supplier.address || 'ZZ DEMO address, Dubai, UAE', `Tel ${supplier.phone || '+971 50 000 0099'}  ·  ${supplier.email || 'zz-demo@example.invalid'}  ·  TRN ${supplier.trn || '100000000000003'}`, ' '];
  if (kind === 'range') {
    return simplePdf([...head, { text: `Quotation ${ref}  (your request ${rfq})`, bold: true }, ' ', 'Dear Sir,', 'Thank you for your enquiry for the air conditioning works.',
      'We cannot give a firm price without seeing the units. Our budget price is:', ' ',
      { text: `${aed(low)} to ${aed(high)} excluding VAT, SUBJECT TO SITE VISIT.`, bold: true, size: 12 }, ' ',
      'The final price will be confirmed after our technician inspects the units, the piping and the power.',
      'Site visit free of charge. Warranty as per manufacturer. Payment 50% advance, 50% on completion.', 'Validity 15 days.', ' ', 'Regards,', supplier.signer || 'ZZ DEMO Sales'], { title: `Quotation ${ref}` });
  }
  return simplePdf([...head, { text: `QUOTATION ${ref}   Your request: ${rfq}   Date: 2026-11-15`, bold: true }, ' ',
    ...lines.map((l, i) => `${i + 1}. ${l.description}  |  ${l.qty} ${l.unit}  x  ${aed(l.rate)}  =  ${aed(l.amount)}`), ' ',
    `Subtotal ${aed(sub)}    VAT 5% ${aed(vat)}    Total ${aed(sub + vat)}`, ' ',
    `Lead time: ${supplier.lead || '7 days from LPO'}.  Warranty: ${supplier.warranty || '2 years on installation, 5 years on compressor'}.`,
    `Payment: ${supplier.payment || '50% advance, 50% on completion'}.  Validity: 30 days.`, `Exclusions: ${supplier.exclusions || 'civil works, false ceiling repair'}.`, ' ', 'Regards,', supplier.signer || 'ZZ DEMO Sales'], { title: `Quotation ${ref}` });
}

const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
async function sharpOf() { return (await import('sharp')).default; }

/** A phone photo of a handwritten quotation: the supplier wrote it on his pad and photographed it. */
export async function handwrittenPhoto({ supplier, lines, ref }) {
  const sharp = await sharpOf();
  const total = lines.reduce((a, l) => a + l.amount, 0);
  const brief = (d) => d.replace(/\s*\(.*\)$/, '').split(/[ ,]+/).slice(0, 4).join(' ');
  const rows = [`${supplier.letterhead || supplier.label}`, `Quotation no. ${ref}`, 'To: customer (QuotesDone)', ' ',
    ...lines.map((l) => `${l.qty} x ${brief(l.description)} = ${Math.round(l.amount)}/-`), ' ', `Total AED ${Math.round(total)}/- + VAT`, 'Warranty 1 yr. Advance 50%', `Mob ${supplier.phone || '+971 50 000 0098'}`];
  const W = 900, H = 1200;
  // no script font is installed: a slanted italic serif, each word nudged off the line, reads as a hand on a pad
  // each word is placed by hand (a rough advance of 0.5 em a letter) and nudged off the line, as a hand writes on a pad
  const line = (r, size) => { let x = 0; return r.split(' ').map((w, j) => { const t = `<text x="${x}" y="${[0, 3, -2, 2, -3, 1][j % 6]}" font-family="FreeSerif, DejaVu Serif, serif" font-style="italic" font-size="${size}" fill="#1b2f86">${xml(w)}</text>`; x += Math.round((w.length * 0.5 + 0.55) * size); return t; }).join(''); };
  const text = rows.map((r, i) => `<g transform="translate(${92 + (i % 3) * 4} ${150 + i * 74}) rotate(${(i % 2 ? -0.8 : 0.6)}) skewX(-9)">${line(r, i === 0 ? 38 : 34)}</g>`).join('');
  const rules = Array.from({ length: 15 }, (_, i) => `<line x1="40" x2="${W - 40}" y1="${162 + i * 74}" y2="${162 + i * 74}" stroke="#9fb7d8" stroke-width="1.4"/>`).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><defs><radialGradient id="g" cx="0.3" cy="0.2" r="1"><stop offset="0" stop-color="#fbf8ee"/><stop offset="1" stop-color="#d8d0bb"/></radialGradient></defs>
    <rect width="${W}" height="${H}" fill="#6b5a46"/><g transform="rotate(-4 450 600)"><rect x="60" y="40" width="${W - 120}" height="${H - 90}" fill="url(#g)"/>${rules}${text}</g></svg>`;
  return await sharp(Buffer.from(svg)).blur(0.6).modulate({ brightness: 0.96 }).jpeg({ quality: 62 }).toBuffer();
}

/** A phone photo of the nameplate on an outdoor unit (the villa owner's "sticker on the outside unit"). */
export async function nameplatePhoto() {
  const sharp = await sharpOf();
  const rows = ['ZZ DEMO AIR CONDITIONER', 'OUTDOOR UNIT', 'MODEL: GWH18-ZZ', 'COOLING CAPACITY: 18000 BTU/h (5.3 kW)', 'RATED VOLTAGE: 220-240V ~ 50Hz 1PH', 'REFRIGERANT: R410A  1.25 kg', 'T3 CLIMATE CLASS', 'MFG: 2018-06   SERIAL: ZZ000000018'];
  const W = 1000, H = 760;
  const text = rows.map((r, i) => `<text x="120" y="${190 + i * 56}" font-family="DejaVu Sans, Arial, sans-serif" font-size="${i < 2 ? 34 : 28}" font-weight="${i < 2 ? 700 : 400}" fill="#222">${xml(r)}</text>`).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="#8d9296"/>
    <g transform="rotate(3 500 380)"><rect x="80" y="110" width="840" height="540" rx="10" fill="#e6e3dc" stroke="#555" stroke-width="3"/>${text}</g>
    <rect width="${W}" height="${H}" fill="#fff" opacity="0.08"/></svg>`;
  return await sharp(Buffer.from(svg)).blur(0.8).jpeg({ quality: 60 }).toBuffer();
}
