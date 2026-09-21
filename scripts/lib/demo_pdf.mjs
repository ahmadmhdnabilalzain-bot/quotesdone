// A one-page PDF built by hand for ZZ DEMO fixtures — a trade licence, a company profile — with no
// dependency and no embedded font (Standard-14 Helvetica), so a file is ~1.5 kB.
//
// Lifted out of scripts/staging/make_fixture_licence_pdf.mjs (12 Aug 2026) on 14 Sep 2026, when the
// e2e harness (scripts/e2e/fixtures.mjs) needed the same document with per-run text: every demo
// supplier it creates carries a licence file the product can open, named for that supplier. One
// generator, two callers, rather than a second copy of the byte layout.
//
// Latin-1 only (Helvetica has no Arabic glyphs); callers keep the text ASCII. Everything printed is
// invented and says so.

/** lines: [text, fontSize][] top to bottom. Returns a Buffer holding a valid PDF 1.4 file. */
export function demoPdf(lines) {
  let y = 760;
  let text = 'BT\n';
  for (const [line, size] of lines) {
    text += `/F1 ${size} Tf\n1 0 0 1 60 ${y} Tm\n(${String(line).replace(/([()\\])/g, '\\$1')}) Tj\n`;
    y -= size + 10;
  }
  text += 'ET\n';
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${text.length} >>\nstream\n${text}endstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => { offsets.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xref = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`
       + offsets.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')
       + `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

/** The trade licence a ZZ DEMO supplier carries. */
export function demoTradeLicence({ company, licenceNo, issue = '15/03/2025', expiry = '14/03/2028', activity = 'General Trading' }) {
  return demoPdf([
    ['GOVERNMENT OF DUBAI', 18],
    ['DEPARTMENT OF ECONOMY AND TOURISM', 13],
    ['TRADE LICENCE', 16],
    ['', 11],
    [`Licence No.: ${licenceNo}`, 12],
    [`Company Name: ${company}`, 12],
    ['(QuotesDone fixture, not a real company)', 10],
    ['Legal Type: Limited Liability Company', 12],
    ['Issuing Authority: Dubai Department of Economy and Tourism', 12],
    ['Emirate: Dubai', 12],
    ['City: Dubai', 12],
    [`Issue Date: ${issue}`, 12],
    [`Expiry Date: ${expiry}`, 12],
    [`Activities: ${activity}`, 11],
  ]);
}
