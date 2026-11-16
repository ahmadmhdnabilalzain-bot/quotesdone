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
// The byte layout lives in scripts/lib/demo_pdf.mjs since 14 Sep 2026, shared with the e2e harness.
import { writeFileSync } from 'node:fs';
import { demoTradeLicence } from '../../lib/demo_pdf.mjs';

const buf = demoTradeLicence({
  company: 'ZZ DEMO - Al Noor HVAC Manufacturing',
  licenceNo: '9900771',
  activity: 'Air Conditioning Units Manufacturing; Ventilation Systems Installation and Maintenance',
});
const out = process.argv[2] || 'fixture_licence.pdf';
writeFileSync(out, buf);
// The data: URL is what the probe hands wa_inbound as MediaUrl0. fetch() accepts data: URLs and
// returns the bytes with the declared content-type, so the download leg runs exactly as written.
writeFileSync(out + '.dataurl.txt', 'data:application/pdf;base64,' + buf.toString('base64'));
console.log(`${out}  ${buf.length} bytes  dataurl ${buf.toString('base64').length} chars`);
