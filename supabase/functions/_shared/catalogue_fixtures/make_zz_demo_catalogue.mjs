// The ZZ DEMO catalogue fixture: a 2-page text PDF with the STRUCTURE of a real IT/electronics
// importer-wholesaler's catalogue measured on 21 Sep 2026 (the real file is a company's document and is
// never committed). Brand, models and company are invented. What it reproduces, because each broke the
// deterministic path on the real one:
//   * a trading blurb ("IMPORTER, EXPORTER AND WHOLESALER", "stockist") and no installation language;
//   * a marketing sentence with "electric gadgets" in it;
//   * product-type headings split over lines (UNINTERRUPTIBLE / POWER SUPPLY) and a short product list;
//   * side-by-side spec tables, interleaved row by row the way the PDF reader returns them, carrying
//     "Power Indicator LED Light" on a UPS, "DVR Storage Upto 6TB", "Type Cat 6 Cable UTP" and model
//     numbers;
//   * an address block with a "(Warehouse)" line.
//
//   node supabase/functions/_shared/catalogue_fixtures/make_zz_demo_catalogue.mjs
import { writeFileSync } from 'node:fs';
import { demoPdfPages } from '../../../../scripts/lib/demo_pdf.mjs';

const H = 14, S = 7, P = 9;
const page1 = [
  ['ZZ DEMO ZENTEK 2026 Catalogue', 18],
  ['(QuotesDone fixture, not a real company or brand)', P],
  ['IMPORTER, EXPORTER', H],
  ['AND WHOLESALER', H],
  ['ZZ Demo Zentek Trading is a stockist of IT and electronic products since 2009.', P],
  ['All-in-Ones', H],
  ['Desktops', H],
  ['Laptops', H],
  ['Printers', H],
  ['Photocopiers', H],
  ['Projectors', H],
  ['UPS /', H],
  ['Inverter', H],
  ['POS', H],
  ['Solutions', H],
  ['UNINTERRUPTIBLE HIGH QUALITY', H],
  ['POWER SUPPLY LASER TONERS', H],
  ['Our battery backups keep you working and protect your electric gadgets.', P],
  ['Model No: ZZ-UPS650 / ZZ-UPS1000 Model No: ZZ-UPS1500 Model No: ZZ-TN201A / ZZ-TN202A', S],
  ['Type UPS with Built-in AVR Type UPS with Built-in AVR Compatible with: ZZ-P100 / ZZ-P200', S],
  ['Capacity 650VA / 1000VA Capacity 1500VA Yield 1600 pages', S],
  ['Built-in AVR Yes Built-in AVR Yes', S],
  ['Power Indicator LED Light Power Indicator LED Light', S],
  ['Type Sealed Maintenance Free Type Sealed Maintenance Free', S],
];
const page2 = [
  ['POINT OF SALE', H],
  ['CCTV KITS', H],
  ['investing in surveillance DVR Kits', P],
  ['Model No: ZZ-POS15 Model No: ZZ-RP80 Model No: ZZ-DVR4', S],
  ['Type Point of Sale System Type Receipt Printer Type DVR Kit', S],
  ['Model No: ZZ-BC20 Type Barcode Reader Infrared Yes', S],
  ['Type Cash Drawer Features Compatible with POS', S],
  ['Lens 3.6 MM Fixed DVR Storage Upto 6TB NVR Storage Upto 6TB', S],
  ['NETWORKING', H],
  ['CABLES', H],
  ['Model No: ZZ-UTP305 Model No: ZZ-FTP305', S],
  ['Type Cat 6 Cable UTP Type Cat 6 Cable FTP', S],
  ['Sizes 305 M Sizes 305 M', S],
  ['Color Grey Color Grey', S],
  ['ZZ DEMO ZENTEK TRADING LLC (Head Office)', P],
  ['Shop 9, ZZ Demo Bldg., Example Road, Dubai', P],
  ['Tel: +971 500000099 Email: sales@example.invalid', P],
  ['ZZ DEMO ZENTEK TRADING LLC (Warehouse)', P],
];

/** The pages' lines, for a test that needs the text without a PDF reader (the Node meaning check). */
export const PAGES = [page1, page2];

if (import.meta.url === `file:///${process.argv[1]?.replace(/\\/g, '/').replace(/^\//, '')}`) {
  const out = new URL('./zz_demo_it_wholesaler_catalogue.pdf', import.meta.url);
  writeFileSync(out, demoPdfPages(PAGES));
  console.log('wrote', decodeURIComponent(out.pathname));
}
