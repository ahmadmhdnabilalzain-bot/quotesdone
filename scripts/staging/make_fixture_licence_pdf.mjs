// A one-page UAE trade licence for a ZZ DEMO fixture company, built by hand so the media-in path
// can be exercised end to end without a real supplier's document and without a dependency.
//
// WHY THIS EXISTS. wa_inbound now downloads a WhatsApp attachment, sanitises it, stores it, reads
// it with license_extract and writes the result onto the lead. Proving that chain needs a real
// readable document arriving over a real fetch. Twilio has never received a media message (checked
// 12 Aug 2026: 0 of the last 100 messages carry media), so there is no MediaUrl to replay, and a
// real supplier's licence must not be re-filed to make a test pass.
//
// The company named here is the existing ZZ DEMO fixture convention — 'ZZ DEMO — …' in the name,
// which is how this codebase has marked non-real rows since 7 Aug. Everything on it is invented on
// purpose and says so.
//
// Standard-14 Helvetica, so no font is embedded and the file stays ~1.6 kB.
import { writeFileSync } from 'node:fs';

const LINES = [
  ['GOVERNMENT OF DUBAI', 18],
  ['DEPARTMENT OF ECONOMY AND TOURISM', 13],
  ['TRADE LICENCE', 16],
  ['', 11],
  ['Licence No.: 9900771', 12],
  ['Company Name: ZZ DEMO - Al Noor HVAC Manufacturing', 12],
  ['(QuotesDone fixture, not a real company)', 10],
  ['Legal Type: Limited Liability Company', 12],
  ['Issuing Authority: Dubai Department of Economy and Tourism', 12],
  ['Emirate: Dubai', 12],
  ['City: Dubai', 12],
  ['Issue Date: 15/03/2025', 12],
  ['Expiry Date: 14/03/2028', 12],
  ['Activities: Air Conditioning Units Manufacturing;', 11],
  ['            Ventilation Systems Installation and Maintenance', 11],
  ['TRN: 100299887700003', 12],
];

let y = 760;
let text = 'BT\n';
for (const [line, size] of LINES) {
  text += `/F1 ${size} Tf\n1 0 0 1 60 ${y} Tm\n(${line.replace(/([()\\])/g, '\\$1')}) Tj\n`;
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

const buf = Buffer.from(pdf, 'latin1');
const out = process.argv[2] || 'fixture_licence.pdf';
writeFileSync(out, buf);
// The data: URL is what the probe hands wa_inbound as MediaUrl0. fetch() accepts data: URLs and
// returns the bytes with the declared content-type, so the download leg runs exactly as written.
writeFileSync(out + '.dataurl.txt', 'data:application/pdf;base64,' + buf.toString('base64'));
console.log(`${out}  ${buf.length} bytes  dataurl ${buf.toString('base64').length} chars`);
