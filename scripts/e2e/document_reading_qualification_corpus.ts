// scripts/e2e/document_reading_qualification_corpus.ts — the GOLD corpus of the supplier document-reading qualification.
// Seat: sales_engineer. 3 Nov 2026. Founder's scenario: "a supplier attaches a company profile of 300 pages and the sales
// agent must go through it properly, not summarise wrong information, and set the right keywords for cross-matching."
//
// Every document is INVENTED and built here from code ("ZZ DEMO" names, made-up licence numbers): nothing is copied from
// a real company. Each item carries its known answer in truth.json:
//   trades      the trades the company itself offers (gold), each with the EXACT line that states it and the page it is on
//   forbidden   trades the document mentions but the company does NOT do (a client list, a "we do NOT" line, an
//               equipment list, a project owner): proposing one is a wrong keyword for cross-matching
//   licence     the fields a licence prints, exactly
//   expect      for a file that cannot be read: the honest outcome it must get (never a wrong read)
// Sizes 2, 20, 120 and 300 pages; text-layer PDFs (Standard-14 and embedded-font), image-only scans, a JPEG photo,
// Arabic-only and mixed AR/EN, trades only on page 150+ and 270, decoys, a General Trading licence, multi-activity
// licences, an expired licence, a corrupt PDF, a password-protected PDF (real RC4 encryption) and a 30 MB file.
//
//   deno run -A --unsafe-proto --no-lock --node-modules-dir=auto scripts/e2e/document_reading_qualification_corpus.ts <out dir>
// (--unsafe-proto: pdf-lib assigns Object.prototype.__proto__; node_modules=auto: sharp is a native module.)
import { PDFDocument, StandardFonts, type PDFFont } from 'npm:pdf-lib@1.17.1';
import fontkit from 'npm:@pdf-lib/fontkit@1.1.1';
import sharp from 'npm:sharp@0.33.5';
import { crypto as stdCrypto } from 'jsr:@std/crypto@1';

const OUT = Deno.args[0];
if (!OUT) { console.error('usage: <out dir>'); Deno.exit(2); }
await Deno.mkdir(OUT, { recursive: true });
const AR_FONT = Deno.env.get('QD_ARABIC_FONT') ?? (Deno.build.os === 'windows' ? 'C:/Windows/Fonts/arial.ttf' : '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');

export type GoldTrade = { code: string; line: string; page: number };
export type Item = {
  id: string; file: string; mime: string; kind: 'profile' | 'licence'; cls: string; pages: number; text_layer: boolean;
  registered_name: string; trades: GoldTrade[]; forbidden: string[];
  licence?: Record<string, unknown>; expect?: 'read' | 'needs_model' | 'refused_or_unreadable' | 'held_honestly';
  note: string;
};
const items: Item[] = [];

// ── text pages ─────────────────────────────────────────────────────────────────────────────────────
type Page = string[];   // lines, top to bottom
let seed = 7;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const pick = <T>(a: T[]) => a[Math.floor(rnd() * a.length)];
// What a real long profile is mostly made of (ACCURACY_real_profiles.md: CEO message, policies, org chart, staff and
// machinery lists, certificates, clients, projects). ~900 characters a page, the density measured on real text profiles.
const FILLER: ((n: number) => Page)[] = [
  (n) => [`MESSAGE FROM THE MANAGING DIRECTOR (${n})`, 'Since our foundation we have grown with the ambition of the United Arab Emirates.', 'Our people are our strength, and our clients trust us because we deliver on time.', 'We remain committed to quality, safety and to the communities where we work.', 'Every project is a partnership, and every partner is treated with respect.', 'We thank our clients, consultants and staff for their continued support.', 'Our growth over the last decade reflects a culture of accountability.', 'We invest each year in training, systems and the welfare of our workforce.', 'The coming years will see us expand our presence across the GCC region.', 'Signed, the Managing Director'],
  (n) => [`HEALTH, SAFETY AND ENVIRONMENT POLICY (${n})`, 'The company considers the health and safety of every person on site its first duty.', 'We provide induction and toolbox talks to every employee before work begins.', 'All incidents are reported, investigated and closed with corrective actions.', 'Permits to work are issued for hot work, confined spaces and work at height.', 'Waste is segregated on site and removed by licensed carriers only.', 'Our HSE officers audit each site every week and report to management.', 'Emergency drills are carried out on every project every quarter.', 'Lost time injury frequency is reported monthly to the board.'],
  (n) => [`ORGANISATION CHART (${n})`, 'Managing Director', 'General Manager - Operations', 'Finance Manager', 'Procurement Manager', 'HR and Administration Manager', 'Project Managers (6)', 'Site Engineers (14)', 'Quantity Surveyors (4)', 'Foremen and Supervisors (22)', 'Document Controller', 'Storekeepers (3)', 'Drivers (9)'],
  (n) => [`PLANT AND MACHINERY LIST (${n})`, 'Mobile crane 50 tonne - 1 no. - owned', 'Boom lift 18 m - 2 nos. - owned', 'Forklift 3 tonne - 3 nos. - owned', 'Diesel generator 250 kVA - 2 nos.', 'Pickup trucks - 12 nos.', '30-seater staff buses - 4 nos.', 'Welding machines - 18 nos.', 'Core drilling machines - 6 nos.', 'Laser levels and total station - 3 sets'],
  (n) => [`KEY STAFF CURRICULUM VITAE (${n})`, 'Name: ZZ DEMO Engineer ' + n, 'Position: Senior Project Manager', 'Qualification: B.Sc. Mechanical Engineering', 'Experience: 18 years in the UAE and Qatar', 'Previous employers: ZZ DEMO Contracting, ZZ DEMO Engineering', 'Languages: English, Arabic, Hindi', 'Memberships: Society of Engineers UAE', 'Key projects: Tower ' + n + ', Dubai Marina; Mall extension, Abu Dhabi'],
  (n) => [`PROJECT REFERENCE SHEET ${n}`, `Project: ZZ DEMO Residential Tower ${n}, Jumeirah Village Circle`, 'Client: ZZ DEMO Properties LLC', 'Consultant: ZZ DEMO Engineering Consultants', 'Main contractor: ZZ DEMO Builders LLC', 'Contract value: AED ' + (2 + n % 17) + '.4 million', 'Duration: 14 months', 'Status: completed and handed over', 'Scope: as per the contract documents and approved drawings'],
  (n) => [`QUALITY POLICY (${n})`, 'The company operates a quality management system certified to ISO 9001:2015.', 'Our environmental system is certified to ISO 14001:2015.', 'Occupational health and safety is certified to ISO 45001:2018.', 'Inspection and test plans are agreed with the consultant before work starts.', 'Non-conformances are recorded, reviewed and closed by the QA/QC manager.', 'Material submittals are approved before any procurement.', 'Customer feedback is collected at handover and reviewed by management.'],
  (n) => [`INSURANCE AND BANKING DETAILS (${n})`, 'Contractors all risk insurance: ZZ DEMO Insurance PJSC', 'Third party liability: AED 5,000,000 per occurrence', 'Workmen compensation: as per UAE Labour Law', 'Bankers: ZZ DEMO Bank PJSC, Deira branch', 'Account currency: AED', 'Auditors: ZZ DEMO Chartered Accountants'],
];
const filler = (n: number): Page => FILLER[n % FILLER.length](n);

// Decoys: what a profile mentions that the company does NOT do. Each names a forbidden trade.
const DECOY_CLIENTS: Page = ['OUR VALUED CLIENTS', 'ZZ DEMO Lifts and Escalators LLC (elevator modernisation of their head office)', 'ZZ DEMO Pools and Fountains LLC (swimming pool construction by the client)',
  'ZZ DEMO Crane Rental LLC (heavy equipment rental company)', 'ZZ DEMO Solar Energy LLC (solar farm owner, Sweihan)', 'ZZ DEMO Developers PJSC'];
const DECOY_NOT: Page = ['SCOPE LIMITATIONS', 'Please note: we do NOT undertake elevator or escalator installation; lifts are always by others.', 'We do NOT build swimming pools and we do not supply solar panels.', 'Mobile cranes listed in our plant list are for our own use and are not rented out.'];
const DECOY_FORBIDDEN = ['elevators', 'swimming_pools', 'heavy_equipment', 'solar'];

const PDF_PAD_ID = 'zzdemo-qualification';
async function textPdf(pages: Page[], opts: { font?: 'helvetica' | 'arial' } = {}): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.setTitle('ZZ DEMO synthetic fixture'); doc.setProducer(PDF_PAD_ID);
  let font: PDFFont;
  if (opts.font === 'arial') { doc.registerFontkit(fontkit); font = await doc.embedFont(await Deno.readFile(AR_FONT), { subset: true }); }
  else font = await doc.embedFont(StandardFonts.Helvetica);
  for (const lines of pages) {
    const p = doc.addPage([595, 842]);
    let y = 790;
    for (const [i, l] of lines.entries()) { p.drawText(l, { x: 50, y, size: i === 0 ? 13 : 10, font }); y -= i === 0 ? 26 : 16; }
    p.drawText('ZZ DEMO synthetic fixture - not a real company', { x: 50, y: 30, size: 7, font });
  }
  return await doc.save();
}

// ── scanned pages: each page a picture of its text, nothing in a text layer ─────────────────────────────
const xml = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
async function pageJpeg(lines: Page, rtl = false, quality = 70): Promise<Uint8Array> {
  const x = rtl ? 1160 : 80, anchor = rtl ? 'end' : 'start';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1240" height="1754"><rect width="100%" height="100%" fill="#fbfbf7"/>${
    lines.map((l, k) => `<text x="${x}" y="${140 + k * 58}" font-family="Arial" font-size="${k === 0 ? 40 : 30}" text-anchor="${anchor}" fill="#1a1a1a">${xml(l)}</text>`).join('')}</svg>`;
  return new Uint8Array(await sharp(new TextEncoder().encode(svg)).jpeg({ quality }).toBuffer());
}
async function scanPdf(pages: Page[]): Promise<Uint8Array> {
  const doc = await PDFDocument.create(); doc.setProducer(PDF_PAD_ID);
  for (const lines of pages) {
    const img = await doc.embedJpg(await pageJpeg(lines));
    doc.addPage([595, 842]).drawImage(img, { x: 0, y: 0, width: 595, height: 842 });
  }
  return await doc.save();
}
async function padded(pdf: Uint8Array, toBytes: number): Promise<Uint8Array> {
  // A 30 MB profile: the same document followed by pages of site photos (incompressible JPEGs) until it weighs toBytes.
  // (An attached file would be refused by the type gate as unsafe content: photos are what makes a real profile heavy.)
  const doc = await PDFDocument.load(pdf);
  let size = pdf.length;
  while (size < toBytes) {
    const w = 2400, h = 3200, raw = new Uint8Array(w * h * 3);
    for (let i = 0; i < raw.length; i += 65536) crypto.getRandomValues(raw.subarray(i, Math.min(i + 65536, raw.length)));
    const jpg = new Uint8Array(await sharp(raw, { raw: { width: w, height: h, channels: 3 } }).jpeg({ quality: 90 }).toBuffer());
    doc.addPage([595, 842]).drawImage(await doc.embedJpg(jpg), { x: 0, y: 0, width: 595, height: 842 });
    size += jpg.length;
  }
  return await doc.save();
}

// ── a REAL password-protected PDF: the Standard security handler, revision 2 (RC4, 40-bit), user password "zzdemo" ──
const PAD = Uint8Array.from([0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A]);
const md5 = (b: Uint8Array) => new Uint8Array(stdCrypto.subtle.digestSync('MD5', b));
const cat = (...a: Uint8Array[]) => { const o = new Uint8Array(a.reduce((n, x) => n + x.length, 0)); let i = 0; for (const x of a) { o.set(x, i); i += x.length; } return o; };
const padPw = (pw: string) => { const b = new TextEncoder().encode(pw).slice(0, 32); return cat(b, PAD.slice(0, 32 - b.length)); };
function rc4(key: Uint8Array, data: Uint8Array): Uint8Array {
  const s = Array.from({ length: 256 }, (_, i) => i); let j = 0;
  for (let i = 0; i < 256; i++) { j = (j + s[i] + key[i % key.length]) & 255; [s[i], s[j]] = [s[j], s[i]]; }
  const out = new Uint8Array(data.length); let a = 0; j = 0;
  for (let k = 0; k < data.length; k++) { a = (a + 1) & 255; j = (j + s[a]) & 255; [s[a], s[j]] = [s[j], s[a]]; out[k] = data[k] ^ s[(s[a] + s[j]) & 255]; }
  return out;
}
function encryptedPdf(pageLines: Page[], user = 'zzdemo', owner = 'zzdemo-owner'): Uint8Array {
  const id = md5(new TextEncoder().encode('ZZ DEMO encrypted ' + pageLines.length));
  const O = rc4(md5(padPw(owner)).slice(0, 5), padPw(user));
  const P = -44;
  const pB = new Uint8Array(4); new DataView(pB.buffer).setInt32(0, P, true);
  const key = md5(cat(padPw(user), O, pB, id)).slice(0, 5);
  const U = rc4(key, PAD);
  const objKey = (n: number) => md5(cat(key, Uint8Array.from([n & 255, (n >> 8) & 255, (n >> 16) & 255, 0, 0]))).slice(0, 10);
  const L = (s: string) => new TextEncoder().encode(s);
  const hex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  const objs: Uint8Array[] = [];
  const n = pageLines.length;
  objs.push(L('<< /Type /Catalog /Pages 2 0 R >>'));
  objs.push(L(`<< /Type /Pages /Kids [${pageLines.map((_, i) => `${4 + 2 * i} 0 R`).join(' ')}] /Count ${n} >>`));
  objs.push(L('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'));
  pageLines.forEach((lines, i) => {
    const c = 'BT\n' + lines.map((l, k) => `/F1 10 Tf 1 0 0 1 50 ${790 - 16 * k} Tm (${l.replace(/([()\\])/g, '\\$1')}) Tj\n`).join('') + 'ET\n';
    const enc = rc4(objKey(5 + 2 * i), L(c));
    objs.push(L(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + 2 * i} 0 R >>`));
    objs.push(cat(L(`<< /Length ${enc.length} >>\nstream\n`), enc, L('\nendstream')));
  });
  const encId = objs.length + 1;
  objs.push(L(`<< /Filter /Standard /V 1 /R 2 /O <${hex(O)}> /U <${hex(U)}> /P ${P} >>`));
  const parts: Uint8Array[] = [L('%PDF-1.4\n')]; let len = parts[0].length; const offs: number[] = [];
  objs.forEach((o, i) => { offs.push(len); const b = cat(L(`${i + 1} 0 obj\n`), o, L('\nendobj\n')); parts.push(b); len += b.length; });
  parts.push(L(`xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size ${objs.length + 1} /Root 1 0 R /Encrypt ${encId} 0 R /ID [<${hex(id)}> <${hex(id)}>] >>\nstartxref\n${len}\n%%EOF\n`));
  return cat(...parts);
}

async function save(it: Omit<Item, 'file'> & { ext: string }, bytes: Uint8Array) {
  const file = `${it.id}.${it.ext}`;
  await Deno.writeFile(`${OUT}/${file}`, bytes);
  const { ext: _e, ...rest } = it;
  items.push({ ...rest, file });
  console.log(`${file}  ${(bytes.length / 1048576).toFixed(2)} MB  ${it.pages} pages`);
}

// A profile: `pages` pages of filler, the services block placed at `at` (1-based), decoys at the given pages.
function profilePages(total: number, services: { at: number; lines: Page }[], decoys: { at: number; lines: Page }[] = [], cover: Page = []): Page[] {
  const pages: Page[] = [];
  for (let p = 1; p <= total; p++) {
    const s = services.find((x) => x.at === p), d = decoys.find((x) => x.at === p);
    pages.push(p === 1 && cover.length ? cover : s ? s.lines : d ? d.lines : filler(p));
  }
  return pages;
}
const gold = (code: string, line: string, page: number): GoldTrade => ({ code, line, page });
const cover = (name: string, tag = 'COMPANY PROFILE'): Page => [name, tag, 'Dubai, United Arab Emirates', 'P.O. Box 00000', 'www.zzdemo.example.invalid'];

// ── PROFILES, text layer ─────────────────────────────────────────────────────────────────────────────
{ // P01: 2 pages
  const svc = ['OUR SERVICES', 'Interior fit-out of offices, retail shops and restaurants', 'Bespoke joinery: wardrobes, doors and wall panelling made in our own workshop'];
  await save({ id: 'P01_2p_text', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_short', pages: 2, text_layer: true, registered_name: 'ZZ DEMO Oak Interiors LLC',
    trades: [gold('interior_fitout', svc[1], 2), gold('joinery', svc[2], 2)], forbidden: ['elevators'],
    note: 'two pages; a client list naming a lift company is a decoy' },
    await textPdf([[...cover('ZZ DEMO Oak Interiors LLC'), 'Clients: ZZ DEMO Lifts and Escalators LLC, ZZ DEMO Mall'], svc]));
}
{ // P02: 20 pages, services on page 5, a "we do not" and a client list
  const svc = ['OUR SERVICES', 'Design, supply and installation of HVAC and air conditioning systems', 'Plumbing and sanitary installation for residential and commercial buildings', 'Fire fighting and fire alarm systems installation and maintenance'];
  await save({ id: 'P02_20p_text', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_20', pages: 20, text_layer: true, registered_name: 'ZZ DEMO Coolflow MEP LLC',
    trades: [gold('hvac', svc[1], 5), gold('plumbing', svc[2], 5), gold('fire_fighting', svc[3], 5)], forbidden: DECOY_FORBIDDEN,
    note: 'services on page 5; clients and scope limitations name four trades it does not do' },
    await textPdf(profilePages(20, [{ at: 5, lines: svc }], [{ at: 12, lines: DECOY_CLIENTS }, { at: 13, lines: DECOY_NOT }], cover('ZZ DEMO Coolflow MEP LLC'))));
}
{ // P03: 120 pages, services on page 60
  const svc = ['OUR SERVICES', 'Painting works: interior and exterior paints, epoxy and texture coatings', 'Waterproofing of roofs, basements and wet areas with membranes', 'Flooring: vinyl, epoxy and raised access flooring installation'];
  await save({ id: 'P03_120p_text', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_120', pages: 120, text_layer: true, registered_name: 'ZZ DEMO Finishes Contracting LLC',
    trades: [gold('painting', svc[1], 60), gold('waterproofing', svc[2], 60), gold('flooring', svc[3], 60)], forbidden: DECOY_FORBIDDEN,
    note: 'services only on page 60 of 120' },
    await textPdf(profilePages(120, [{ at: 60, lines: svc }], [{ at: 20, lines: DECOY_CLIENTS }, { at: 21, lines: DECOY_NOT }], cover('ZZ DEMO Finishes Contracting LLC'))));
}
{ // P04: 300 pages, services on page 40 only (the founder's case)
  const svc = ['OUR SERVICES', 'Steel structure fabrication and erection for warehouses and factories', 'Aluminium cladding and curtain wall facades', 'Glass and glazing: shopfronts, skylights and frameless glass partitions'];
  await save({ id: 'P04_300p_text_p40', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_300', pages: 300, text_layer: true, registered_name: 'ZZ DEMO Facade Steel LLC',
    trades: [gold('steel', svc[1], 40), gold('aluminium', svc[2], 40), gold('glazing', svc[3], 40)], forbidden: DECOY_FORBIDDEN,
    note: '300 pages, the services stated only on page 40' },
    await textPdf(profilePages(300, [{ at: 40, lines: svc }], [{ at: 90, lines: DECOY_CLIENTS }, { at: 91, lines: DECOY_NOT }], cover('ZZ DEMO Facade Steel LLC'))));
}
{ // P05: 300 pages, services only on page 155, under an offer heading
  const svc = ['12. Our Services', 'Landscaping: soft and hard landscape works, irrigation networks and maintenance', 'Swimming pools and water features: construction, filtration and maintenance', 'Fencing, shades and tensile structures for car parks and play areas'];
  await save({ id: 'P05_300p_text_p155', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_300_deep', pages: 300, text_layer: true, registered_name: 'ZZ DEMO Green Oasis Contracting LLC',
    trades: [gold('landscaping', svc[1], 155), gold('swimming_pools', svc[2], 155), gold('fencing_shades', svc[3], 155)], forbidden: ['elevators', 'heavy_equipment', 'solar'],
    note: '300 pages, the services only on page 155 (an offer heading); decoys on pages 20-21' },
    await textPdf(profilePages(300, [{ at: 155, lines: svc }], [{ at: 20, lines: DECOY_CLIENTS }, { at: 21, lines: DECOY_NOT.filter((l) => !/swimming/i.test(l)) }], cover('ZZ DEMO Green Oasis Contracting LLC'))));
}
{ // P06: 300 pages, divisions on page 160, written as division pages with no "services" heading or offer phrase
  const svc = ['ELECTRICAL DIVISION', 'Electrical installation: LV switchgear, distribution boards, cabling and lighting for buildings', 'Security systems division: CCTV, access control and intrusion alarms', 'Building automation: BMS controls and smart home systems integration'];
  await save({ id: 'P06_300p_text_p160_divisions', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_300_deep', pages: 300, text_layer: true, registered_name: 'ZZ DEMO Volt Systems LLC',
    trades: [gold('electrical', svc[1], 160), gold('security_systems', svc[2], 160), gold('home_automation', svc[3], 160)], forbidden: DECOY_FORBIDDEN,
    note: '300 pages, the work stated on page 160 as division pages, no offer heading or offer sentence' },
    await textPdf(profilePages(300, [{ at: 160, lines: svc }], [{ at: 30, lines: DECOY_CLIENTS }, { at: 31, lines: DECOY_NOT }], cover('ZZ DEMO Volt Systems LLC'))));
}
{ // P07: 300 pages, services only on page 270 (past 250)
  const svc = ['OUR SERVICES', 'Pest control for residential, commercial and food premises', 'Cleaning services: deep cleaning, facade cleaning and housekeeping staff'];
  await save({ id: 'P07_300p_text_p270', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_300_deep', pages: 300, text_layer: true, registered_name: 'ZZ DEMO Spotless Services LLC',
    trades: [gold('pest_control', svc[1], 270), gold('cleaning', svc[2], 270)], forbidden: DECOY_FORBIDDEN,
    note: '300 pages, the services only on page 270' },
    await textPdf(profilePages(300, [{ at: 270, lines: svc }], [{ at: 50, lines: DECOY_CLIENTS }, { at: 51, lines: DECOY_NOT }], cover('ZZ DEMO Spotless Services LLC'))));
}
{ // P08: 20 pages, Arabic only, embedded font
  const svc = ['خدماتنا', 'أعمال السباكة والتمديدات الصحية للمباني السكنية والتجارية', 'تركيب وصيانة أنظمة التكييف والتهوية'];
  const not = ['ملاحظة', 'لا نقوم بأعمال المصاعد والسلالم المتحركة'];
  const pages = profilePages(20, [{ at: 4, lines: svc }], [{ at: 9, lines: not }], ['زد زد ديمو للمقاولات الفنية ذ.م.م', 'الملف التعريفي للشركة', 'دبي، الإمارات العربية المتحدة'])
    .map((p, i) => (i + 1 === 4 || i + 1 === 9 || i === 0) ? p : ['صفحة ' + (i + 1), 'نلتزم بالجودة والسلامة في جميع مشاريعنا في دولة الإمارات.', 'فريقنا من المهندسين والفنيين ذو خبرة طويلة.', 'نشكر عملاءنا على ثقتهم المستمرة.']);
  await save({ id: 'P08_20p_text_arabic', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_arabic', pages: 20, text_layer: true, registered_name: 'ZZ DEMO Technical Contracting LLC',
    trades: [gold('plumbing', svc[1], 4), gold('hvac', svc[2], 4)], forbidden: ['elevators'],
    note: 'Arabic only (embedded font), services on page 4, a "we do not do lifts" line on page 9' }, await textPdf(pages, { font: 'arial' }));
}
{ // P09: 20 pages, mixed Arabic and English
  const svc = ['OUR SERVICES  خدماتنا', 'Aluminium windows, doors and cladding - أعمال الألمنيوم والكلادينج', 'Glass and glazing works - أعمال الزجاج'];
  await save({ id: 'P09_20p_text_mixed', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_text_mixed', pages: 20, text_layer: true, registered_name: 'ZZ DEMO Crystal Aluminium LLC',
    trades: [gold('aluminium', 'Aluminium windows, doors and cladding', 6), gold('glazing', 'Glass and glazing works', 6)], forbidden: DECOY_FORBIDDEN,
    note: "bilingual lines, embedded font; the gold line is the English half (the Arabic half's glyph order depends on the producer)" },
    await textPdf(profilePages(20, [{ at: 6, lines: svc }], [{ at: 14, lines: DECOY_CLIENTS }, { at: 15, lines: DECOY_NOT }], cover('ZZ DEMO Crystal Aluminium LLC')), { font: 'arial' }));
}

// ── PROFILES, no text layer ────────────────────────────────────────────────────────────────────────────
{ // S01: 2 scanned pages
  const svc = ['OUR SERVICES', 'Steel fabrication and erection of mezzanines and platforms', 'Scaffolding supply, erection and dismantling'];
  await save({ id: 'S01_2p_scan', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_scan', pages: 2, text_layer: false, registered_name: 'ZZ DEMO Iron Works LLC',
    trades: [gold('steel', svc[1], 2), gold('scaffolding', svc[2], 2)], forbidden: [], expect: 'needs_model', note: 'image-only PDF, two pages' },
    await scanPdf([cover('ZZ DEMO Iron Works LLC'), svc]));
}
{ // S02: 20 scanned pages, services on page 15
  const svc = ['OUR SERVICES', 'Landscaping and irrigation works for villas and communities', 'Swimming pool construction and maintenance'];
  const pages = profilePages(20, [{ at: 15, lines: svc }], [], cover('ZZ DEMO Desert Bloom LLC'));
  await save({ id: 'S02_20p_scan_p15', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'profile_scan_deep', pages: 20, text_layer: false, registered_name: 'ZZ DEMO Desert Bloom LLC',
    trades: [gold('landscaping', svc[1], 15), gold('swimming_pools', svc[2], 15)], forbidden: [], expect: 'needs_model', note: 'image-only PDF, the services on page 15 of 20' },
    await scanPdf(pages));
}
{ // S03: a phone photo (JPEG) of the services page
  const svc = ['OUR SERVICES', 'Pest control and fumigation services', 'Cleaning and facility services for offices and towers'];
  await save({ id: 'S03_photo_jpeg', ext: 'jpg', mime: 'image/jpeg', kind: 'profile', cls: 'profile_photo', pages: 1, text_layer: false, registered_name: 'ZZ DEMO Fresh Guard LLC',
    trades: [gold('pest_control', svc[1], 1), gold('cleaning', svc[2], 1)], forbidden: [], expect: 'needs_model', note: 'a JPEG photo of one page' },
    new Uint8Array(await sharp(await pageJpeg(svc, false, 80)).rotate(2, { background: '#dddddd' }).blur(0.6).jpeg({ quality: 72 }).toBuffer()));
}
{ // S04: an Arabic-only photo
  const svc = ['خدماتنا', 'أعمال الدهانات الداخلية والخارجية', 'أعمال الجبس والأسقف المعلقة والقواطع'];
  await save({ id: 'S04_photo_arabic', ext: 'jpg', mime: 'image/jpeg', kind: 'profile', cls: 'profile_photo_arabic', pages: 1, text_layer: false, registered_name: 'ZZ DEMO Decor Contracting LLC',
    trades: [gold('painting', svc[1], 1), gold('gypsum', svc[2], 1)], forbidden: [], expect: 'needs_model', note: 'an Arabic-only JPEG' },
    await pageJpeg(svc, true, 78));
}

// ── LICENCES ───────────────────────────────────────────────────────────────────────────────────────
type Lic = { licence_no: string; legal_name_en: string | null; legal_name_ar?: string | null; authority: string; emirate: string; issue_date: string; expiry_date: string; activities: string[]; legal_form: string };
const dmy = (iso: string) => iso.split('-').reverse().join('/');
function licenceLines(l: Lic, layout: 'comma' | 'per_line'): Page {
  const head = ['GOVERNMENT OF DUBAI', 'DEPARTMENT OF ECONOMY AND TOURISM', 'TRADE LICENCE', '',
    `Licence No: ${l.licence_no}`, `Legal Name: ${l.legal_name_en}`, `Legal Form: ${l.legal_form}`, `Emirate: ${l.emirate}`,
    `Issuing Authority: ${l.authority}`, `Issue Date: ${dmy(l.issue_date)}`, `Expiry Date: ${dmy(l.expiry_date)}`];
  const acts = layout === 'comma' ? [`Business Activities: ${l.activities.join(', ')}`] : ['Business Activities:', ...l.activities];
  return [...head, ...acts, '', '(QuotesDone synthetic fixture - not a real company or licence)'];
}
const DET = 'Dubai Department of Economy and Tourism';
const lic = (no: string, name: string, acts: string[], expiry = '2027-08-31', issue = '2025-09-01'): Lic =>
  ({ licence_no: no, legal_name_en: name, authority: DET, emirate: 'Dubai', issue_date: issue, expiry_date: expiry, activities: acts, legal_form: 'Limited Liability Company' });
const licTruth = (l: Lic) => ({ ...l, legal_name_ar: l.legal_name_ar ?? null });
{
  const l = lic('1100231', 'ZZ DEMO Breeze Air Conditioning LLC', ['Air-Conditioning, Ventilation & Air Filtration Systems Installation & Maintenance']);
  await save({ id: 'L01_text_single', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [gold('hvac', l.activities[0], 1)], forbidden: [], licence: licTruth(l), note: 'one activity, Standard-14 font' }, await textPdf([licenceLines(l, 'comma')]));
}
{
  const l = lic('1100232', 'ZZ DEMO Horizon General Trading LLC', ['General Trading']);
  await save({ id: 'L02_text_general_trading', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [], forbidden: ['general_contracting', 'electrical', 'plumbing', 'hvac'], licence: licTruth(l), note: 'General Trading: names no specific trade' }, await textPdf([licenceLines(l, 'comma')]));
}
{
  const l = lic('1100233', 'ZZ DEMO Allied Technical Services LLC', ['Plumbing & Sanitary Installation', 'Electrical Fitting Contracting', 'Floor & Wall Tiling Works', 'Painting Contracting']);
  await save({ id: 'L03_text_multi_per_line', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [gold('plumbing', l.activities[0], 1), gold('electrical', l.activities[1], 1), gold('flooring', l.activities[2], 1), gold('painting', l.activities[3], 1)], forbidden: [], licence: licTruth(l),
    note: 'four activities, one per line under the label (the layout of a DET activity table)' }, await textPdf([licenceLines(l, 'per_line')]));
}
{
  const l = lic('1100234', 'ZZ DEMO Allied Facades LLC', ['Aluminium & Glass Works', 'Steel Structures Fabrication', 'Glazing Contracting']);
  await save({ id: 'L04_text_multi_comma', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [gold('aluminium', l.activities[0], 1), gold('steel', l.activities[1], 1), gold('glazing', l.activities[2], 1)], forbidden: [], licence: licTruth(l), note: 'three activities on one line' }, await textPdf([licenceLines(l, 'comma')]));
}
{
  const l = lic('1100235', 'ZZ DEMO Expired Builders LLC', ['Building Contracting'], '2025-06-30', '2024-07-01');
  await save({ id: 'L05_text_expired', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [gold('general_contracting', l.activities[0], 1)], forbidden: [], licence: { ...licTruth(l), expired: true }, note: 'expired 30 Jun 2025' }, await textPdf([licenceLines(l, 'comma')]));
}
{
  const l = lic('1100236', 'ZZ DEMO Modern Print LLC', ['Plumbing & Sanitary Installation', 'Pest Control Services']);
  await save({ id: 'L06_text_embedded_font', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [gold('plumbing', l.activities[0], 1), gold('pest_control', l.activities[1], 1)], forbidden: [], licence: licTruth(l),
    note: 'a text licence written with an EMBEDDED font (Identity-H, as most generators write today)' }, await textPdf([licenceLines(l, 'comma')], { font: 'arial' }));
}
{
  const l: Lic = { licence_no: '1100237', legal_name_en: null, legal_name_ar: 'زد زد ديمو للنجارة ذ.م.م', authority: 'دائرة الاقتصاد والسياحة', emirate: 'Dubai', issue_date: '2025-03-01', expiry_date: '2027-02-28', activities: ['أعمال النجارة'], legal_form: 'ذات مسؤولية محدودة' };
  // The digits stand on their own lines, below their Arabic labels: fontkit lays out a right-to-left run with its digits reversed,
  // so "رقم الرخصة: 1100237" drawn as one string PRINTS 7320011 (code and the vision model both read 7320011 on 3 Nov: a fixture
  // artefact, not a reader defect). Code then reads no number or date here (no value on the label's line); the model reads them.
  const lines = ['حكومة دبي', 'رخصة تجارية', 'رقم الرخصة:', l.licence_no, `الاسم القانوني: ${l.legal_name_ar}`, `الشكل القانوني: ${l.legal_form}`, 'الإمارة: دبي',
    `جهة الإصدار: ${l.authority}`, 'تاريخ الإصدار:', dmy(l.issue_date), 'تاريخ الانتهاء:', dmy(l.expiry_date), `الأنشطة: ${l.activities.join('، ')}`];
  await save({ id: 'L07_text_arabic', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'licence_text', pages: 1, text_layer: true, registered_name: 'ZZ DEMO Carpentry LLC',
    trades: [gold('joinery', l.activities[0], 1)], forbidden: [], licence: licTruth(l), note: 'Arabic-only text licence (embedded font)' }, await textPdf([lines], { font: 'arial' }));
}
{
  const l = lic('1100238', 'ZZ DEMO Scanned Electric LLC', ['Electrical Fitting Contracting']);
  await save({ id: 'L08_scan_jpeg', ext: 'jpg', mime: 'image/jpeg', kind: 'licence', cls: 'licence_scan', pages: 1, text_layer: false, registered_name: l.legal_name_en!,
    trades: [gold('electrical', l.activities[0], 1)], forbidden: [], licence: licTruth(l), expect: 'needs_model', note: 'a photographed licence: code reads nothing, the model must' },
    await pageJpeg(licenceLines(l, 'comma'), false, 75));
}

// ── FILES THAT CANNOT BE READ AS GIVEN ───────────────────────────────────────────────────────────────
{
  const whole = await textPdf(profilePages(20, [{ at: 18, lines: ['OUR SERVICES', 'Plumbing and drainage works'] }], [], cover('ZZ DEMO Broken File LLC')));
  await save({ id: 'E01_corrupt_pdf', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'edge_corrupt', pages: 20, text_layer: true, registered_name: 'ZZ DEMO Broken File LLC',
    trades: [], forbidden: ['plumbing'], expect: 'refused_or_unreadable', note: 'the first 35% of a 20-page PDF (an interrupted download): the services page is not in it' }, whole.slice(0, Math.floor(whole.length * 0.35)));
}
{
  const pages = profilePages(3, [{ at: 2, lines: ['OUR SERVICES', 'Electrical installation works'] }], [], cover('ZZ DEMO Locked File LLC'));
  await save({ id: 'E02_password_pdf', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'edge_password', pages: 3, text_layer: true, registered_name: 'ZZ DEMO Locked File LLC',
    trades: [], forbidden: ['electrical'], expect: 'refused_or_unreadable', note: 'RC4-encrypted with a user password: nobody can read it without the password' }, encryptedPdf(pages));
}
{
  const svc = ['OUR SERVICES', 'Thermal and acoustic insulation of ducts, pipes and roofs', 'Waterproofing membranes for roofs and podiums'];
  const base = await textPdf(profilePages(20, [{ at: 8, lines: svc }], [{ at: 12, lines: DECOY_CLIENTS }, { at: 13, lines: DECOY_NOT }], cover('ZZ DEMO Insulation Masters LLC')));
  await save({ id: 'E03_30mb_text', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'edge_30mb_text', pages: 20, text_layer: true, registered_name: 'ZZ DEMO Insulation Masters LLC',
    trades: [gold('thermal_insulation', svc[1], 8), gold('waterproofing', svc[2], 8)], forbidden: DECOY_FORBIDDEN, expect: 'read', note: '30 MB: a 20-page text profile followed by pages of site photos' }, await padded(base, 30 * 1048576));
}
{
  const base = await scanPdf(profilePages(6, [{ at: 3, lines: ['OUR SERVICES', 'Signage and printing of shopfront signs'] }], [], cover('ZZ DEMO Heavy Scan LLC')));
  await save({ id: 'E04_30mb_scan', ext: 'pdf', mime: 'application/pdf', kind: 'profile', cls: 'edge_30mb_scan', pages: 6, text_layer: false, registered_name: 'ZZ DEMO Heavy Scan LLC',
    trades: [gold('signage', 'Signage and printing of shopfront signs', 3)], forbidden: [], expect: 'held_honestly', note: '30 MB scanned profile: over the 12 MB the model is sent; must be held with the reason, never "no trades"' }, await padded(base, 30 * 1048576));
}
{
  const l = lic('1100239', 'ZZ DEMO Broken Licence LLC', ['Plumbing & Sanitary Installation']);
  const whole = await textPdf([licenceLines(l, 'comma')]);
  await save({ id: 'E05_corrupt_licence', ext: 'pdf', mime: 'application/pdf', kind: 'licence', cls: 'edge_corrupt', pages: 1, text_layer: true, registered_name: l.legal_name_en!,
    trades: [], forbidden: ['plumbing'], licence: { licence_no: null, legal_name_en: null, legal_name_ar: null, authority: null, emirate: null, issue_date: null, expiry_date: null, activities: null, legal_form: null },
    expect: 'refused_or_unreadable', note: 'a licence cut off after its first 300 bytes: nothing may be read from it' }, whole.slice(0, 300));
}

// ── THE GENERATED SET: 90 more profiles (30 of them 120-300 pages), the release qualification's gold-set target ──────────────────
// Each draws 2-3 trades from the bank below (a line a real profile prints for that trade, English and, for some, Arabic), places
// them in one of three structures (an offer heading, division pages with no offer words, a prose paragraph), at a position
// (early, middle, deep, last page), and carries the decoy client list and scope limitations of the hand-built set.
const BANK: Record<string, { en: string; ar?: string }> = {
  hvac: { en: 'Supply, installation and maintenance of chilled water and VRF air conditioning systems', ar: 'توريد وتركيب وصيانة أنظمة التكييف المركزي' },
  plumbing: { en: 'Plumbing and drainage installation for villas, towers and hotels', ar: 'أعمال السباكة والصرف الصحي للفلل والأبراج' },
  electrical: { en: 'Electrical installation of LV panels, cable trays, wiring and lighting', ar: 'أعمال التمديدات الكهربائية واللوحات والإنارة' },
  fire_fighting: { en: 'Fire fighting sprinklers, fire pumps and fire alarm systems', ar: 'أنظمة مكافحة الحريق والإنذار' },
  painting: { en: 'Interior and exterior painting, epoxy and texture coating works', ar: 'أعمال الدهانات الداخلية والخارجية' },
  waterproofing: { en: 'Waterproofing of roofs, basements and wet areas with bituminous membranes' },
  flooring: { en: 'Flooring installation: vinyl, epoxy, carpet tiles and raised access floors' },
  gypsum: { en: 'Gypsum board partitions and suspended ceilings', ar: 'أعمال الجبس والأسقف المعلقة' },
  joinery: { en: 'Joinery workshop: doors, wardrobes, kitchen cabinets and wall panelling', ar: 'أعمال النجارة والأبواب والخزائن' },
  interior_fitout: { en: 'Turnkey interior fit-out of offices, retail and restaurants' },
  aluminium: { en: 'Aluminium windows, doors, curtain walls and ACP cladding' },
  glazing: { en: 'Glass and glazing: shopfronts, skylights and frameless glass partitions' },
  steel: { en: 'Structural steel fabrication and erection of warehouses and mezzanines' },
  landscaping: { en: 'Soft and hard landscaping, irrigation networks and maintenance', ar: 'أعمال تنسيق الحدائق وشبكات الري' },
  swimming_pools: { en: 'Swimming pool construction, filtration plant and maintenance' },
  cleaning: { en: 'Cleaning services: deep cleaning, housekeeping and facade cleaning', ar: 'خدمات التنظيف والضيافة' },
  pest_control: { en: 'Pest control and fumigation for homes, offices and food outlets' },
  security_systems: { en: 'CCTV, access control and intrusion alarm systems' },
  scaffolding: { en: 'Scaffolding supply, erection and dismantling' },
  signage: { en: 'Signage: illuminated shopfront signs, wayfinding and vehicle branding' },
  marble_stone: { en: 'Marble and granite supply, cutting, fixing and polishing', ar: 'توريد وتركيب الرخام والجرانيت' },
  thermal_insulation: { en: 'Thermal and acoustic insulation of ducts, pipes and roofs' },
  elevators: { en: 'Elevator and escalator installation, modernisation and maintenance' },
  solar: { en: 'Rooftop solar PV systems design, supply and installation' },
  road_works: { en: 'Road works: asphalt paving, interlock and kerbs' },
  masonry_blockwork: { en: 'Blockwork, plastering and masonry works' },
  curtains_blinds: { en: 'Curtains, roller blinds and motorised shades supply and installation' },
  water_treatment: { en: 'Water treatment plants, filtration and RO systems' },
  labour_supply: { en: 'Manpower supply: skilled and unskilled labour on monthly contracts' },
  facilities_management: { en: 'Facilities management: hard and soft FM for residential communities' },
};
// a decoy names what the company does NOT do: those trades are never drawn as its own (the decoy pages would contradict the gold)
const DRAWN = Object.keys(BANK).filter((c) => !DECOY_FORBIDDEN.includes(c));
const BANK_AR = DRAWN.filter((c) => BANK[c].ar);
const decoyCodes = (own: string[]) => DECOY_FORBIDDEN.filter((c) => !own.includes(c));
const plan: { n: number; pages: number; at: 'early' | 'middle' | 'deep' | 'last'; shape: 'heading' | 'divisions' | 'prose'; lang: 'en' | 'ar' | 'mixed'; scan: boolean }[] = [];
const shapes = ['heading', 'divisions', 'prose'] as const, ats = ['early', 'middle', 'deep', 'last'] as const;
for (let i = 0; i < 30; i++) plan.push({ n: i, pages: i < 10 ? 120 : 300, at: ats[i % 4], shape: shapes[i % 3], lang: i % 10 === 9 ? 'ar' : i % 10 === 8 ? 'mixed' : 'en', scan: false });
for (let i = 30; i < 60; i++) plan.push({ n: i, pages: i % 2 ? 20 : 60, at: ats[i % 4], shape: shapes[i % 3], lang: i % 10 === 9 ? 'ar' : i % 10 === 8 ? 'mixed' : 'en', scan: false });
for (let i = 60; i < 80; i++) plan.push({ n: i, pages: i % 2 ? 2 : 5, at: ats[i % 4], shape: shapes[i % 3], lang: i % 10 === 9 ? 'ar' : 'en', scan: false });
for (let i = 80; i < 90; i++) plan.push({ n: i, pages: [3, 12, 25, 40][i % 4], at: ats[i % 4], shape: 'heading', lang: 'en', scan: true });
const codes = DRAWN;
for (const g of plan) {
  const pool = g.lang === 'ar' ? BANK_AR : codes;
  const own = [...new Set([pool[(g.n * 7) % pool.length], pool[(g.n * 11 + 3) % pool.length], ...(g.n % 3 ? [pool[(g.n * 13 + 5) % pool.length]] : [])])];
  const line = (c: string) => g.lang === 'ar' ? BANK[c].ar! : g.lang === 'mixed' && BANK[c].ar ? `${BANK[c].en} / ${BANK[c].ar}` : BANK[c].en;
  const goldLine = (c: string) => g.lang === 'ar' ? BANK[c].ar! : BANK[c].en;   // a mixed line's gold is its English half (see P09)
  const svc = g.shape === 'heading' ? [g.lang === 'ar' ? 'خدماتنا' : 'OUR SERVICES', ...own.map(line)]
    : g.shape === 'divisions' ? own.flatMap((c) => [`${c.replace(/_/g, ' ').toUpperCase()} DIVISION`, line(c)])
    : [g.lang === 'ar' ? 'نبذة عن أعمالنا' : 'ABOUT OUR WORK', g.lang === 'ar' ? 'منذ تأسيسنا ونحن ننفذ المشاريع في الإمارات.' : 'Since our foundation we have delivered projects across the Emirates.', ...own.map(line)];
  const at = Math.max(2, { early: 2, middle: Math.ceil(g.pages / 2), deep: Math.ceil(g.pages * 0.85), last: g.pages }[g.at]);
  const name = `ZZ DEMO Generated ${String(g.n).padStart(3, '0')} LLC`;
  const decoys = g.pages >= 5 ? [{ at: at === 3 ? 4 : 3, lines: DECOY_CLIENTS }, { at: at === 4 || at === 3 ? 5 : 4, lines: DECOY_NOT }].filter((d) => d.at < g.pages && d.at !== at) : [];
  const pages = profilePages(g.pages, [{ at, lines: svc }], decoys, cover(name));
  const id = `G${String(g.n).padStart(3, '0')}_${g.scan ? 'scan' : g.lang}_${g.pages}p_${g.shape}_${g.at}`;
  const cls = g.scan ? (at > 30 ? 'gen_scan_over_30p' : 'gen_scan') : g.pages >= 120 ? `gen_long_${g.lang}` : g.pages >= 20 ? `gen_mid_${g.lang}` : `gen_short_${g.lang}`;
  const it = { id, ext: 'pdf', mime: 'application/pdf', kind: 'profile' as const, cls, pages: g.pages, text_layer: !g.scan, registered_name: name,
    trades: own.map((c) => gold(c, goldLine(c), at)), forbidden: decoys.length ? decoyCodes(own) : [], ...(g.scan ? { expect: 'needs_model' as const } : {}),
    note: `${g.pages} pages, ${g.shape}, services on page ${at}, ${g.lang}${g.scan ? ', image-only' : ''}` };
  await save(it, g.scan ? await scanPdf(pages) : await textPdf(pages, { font: g.lang === 'en' ? 'helvetica' : 'arial' }));
}

await Deno.writeTextFile(`${OUT}/truth.json`, JSON.stringify({ built_at: new Date().toISOString(), builder: 'scripts/e2e/document_reading_qualification_corpus.ts', items }, null, 1));
console.log(`${items.length} items -> ${OUT}/truth.json`);
