// scripts/e2e/document_intake_corpus.mjs — the SYNTHETIC supplier-document corpus of the intake accuracy suite.
// Assigned: sales_engineer (supplier verification + matching); it_engineer (the harness). Founder gate, ledger 1162:
// "not a single mistake in any trade licence shared by a supplier, nor a company profile or a document not read and
// analysed properly for the cross matching later when customers share inquiries."
//
// Every document here is INVENTED and generated from code: no real licence was copied, no real company is named
// (every name starts "ZZ DEMO"), every licence number is a made-up pattern. Each file carries its ground truth
// (truth.json), so the suite can say per field, per authority and per format whether the pipeline read it right.
//
// WHAT IS COVERED
//   18 issuing authorities, each in its own layout, label vocabulary and date style (the labels and layouts are
//   modelled on the SHAPE of each authority's licence, not copied from one):
//     Dubai DED (old commercial licence) + DET (new), Abu Dhabi ADDED + ADGM, Sharjah SEDD, Ajman DED,
//     RAK DED + RAKEZ, UAQ DED, Fujairah DED; free zones JAFZA, DMCC, DAFZA, DSO, IFZA, Meydan, SHAMS, DIFC.
//   Formats: text PDF (colon layout and two-column table layout), image-only scanned PDF, PNG, JPG, rotated 90,
//   skewed, low DPI, phone photo (perspective, blur, shadow), multi-page PDF, bilingual EN/AR image, Arabic-only
//   image. Specials: an expired licence (text + scan), a licence printing another company's name (text + scan),
//   a blank PDF page, a blank photo, and a supplier with no licence at all.
//   Company profiles (PDF, DOCX, PPTX, PNG) naming trades, brands, capacities and certificates; a product
//   catalogue PDF; a VAT registration certificate (prints no expiry: the truth is null) and an ISO certificate.
//
//   node scripts/e2e/document_intake_corpus.mjs --out <dir>     writes the files + <dir>/truth.json
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { deflateRawSync, crc32 } from 'node:zlib';
import sharp from 'sharp';
import { demoPdfPages } from '../lib/demo_pdf.mjs';

// ── the authorities ───────────────────────────────────────────────────────────────────────────────
// authority: the canonical name the suite compares against (_shared/document_expiry.ts canonicalAuthority maps
// what a document prints, or what a model answers, onto the same list). date: how this authority prints dates.
export const AUTHORITIES = {
  dubai_ded_old: { emirate: 'Dubai', authority: 'Dubai Department of Economic Development', layout: 'colon', date: 'dmy/',
    title: ['GOVERNMENT OF DUBAI', 'DEPARTMENT OF ECONOMIC DEVELOPMENT', 'COMMERCIAL LICENCE'], form: 'Limited Liability Company',
    no: (n) => String(500000 + n * 7919 % 400000), printsEmirate: true,
    L: { no: 'License No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Type', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issued By' } },
  dubai_det: { emirate: 'Dubai', authority: 'Dubai Department of Economy and Tourism', layout: 'table', date: 'dMonY',
    title: ['GOVERNMENT OF DUBAI', 'DEPARTMENT OF ECONOMY AND TOURISM', 'TRADE LICENCE'], form: 'Limited Liability Company',
    no: (n) => String(1000000 + n * 7919 % 900000), printsEmirate: true,
    L: { no: 'Licence Number', name: 'Legal Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Business Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  abu_dhabi_added: { emirate: 'Abu Dhabi', authority: 'Abu Dhabi Department of Economic Development', layout: 'colon', date: 'dmy-',
    title: ['ABU DHABI DEPARTMENT OF ECONOMIC DEVELOPMENT', 'COMMERCIAL LICENSE'], form: 'Limited Liability Company',
    no: (n) => 'CN-' + (1000000 + n * 104729 % 8999999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  adgm: { emirate: 'Abu Dhabi', authority: 'Abu Dhabi Global Market Registration Authority', layout: 'table', date: 'ymd',
    title: ['ABU DHABI GLOBAL MARKET', 'REGISTRATION AUTHORITY', 'COMMERCIAL LICENCE'], form: 'Private Company Limited by Shares',
    no: (n) => String(n * 37 + 10000).padStart(9, '0'), printsEmirate: false,
    L: { no: 'Registered Number', name: 'Company Name', trade: 'Trading Name', form: 'Legal Status', issue: 'Date of Issue', expiry: 'Licence Expiry Date', acts: 'Licensed Activities', auth: 'Issued By' } },
  sharjah_sedd: { emirate: 'Sharjah', authority: 'Sharjah Economic Development Department', layout: 'table', date: 'dmy/',
    title: ['GOVERNMENT OF SHARJAH', 'ECONOMIC DEVELOPMENT DEPARTMENT', 'TRADE LICENSE'], form: 'Limited Liability Company',
    no: (n) => String(700000 + n * 613 % 99999), printsEmirate: true,
    L: { no: 'License No.', name: 'Company Name', trade: 'Trade Name', form: 'Legal Type', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activity', emirate: 'Emirate', auth: 'Issuing Authority' } },
  ajman_ded: { emirate: 'Ajman', authority: 'Ajman Department of Economic Development', layout: 'colon', date: 'dmy/',
    title: ['GOVERNMENT OF AJMAN', 'DEPARTMENT OF ECONOMIC DEVELOPMENT', 'TRADE LICENCE'], form: 'Sole Establishment',
    no: (n) => String(10000 + n * 271 % 89999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Establishment Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Valid Until', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  rak_ded: { emirate: 'Ras Al Khaimah', authority: 'Ras Al Khaimah Department of Economic Development', layout: 'colon', date: 'dMONy',
    title: ['GOVERNMENT OF RAS AL KHAIMAH', 'DEPARTMENT OF ECONOMIC DEVELOPMENT', 'TRADE LICENCE'], form: 'Limited Liability Company',
    no: (n) => String(20000 + n * 331 % 79999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  rakez: { emirate: 'Ras Al Khaimah', authority: 'Ras Al Khaimah Economic Zone Authority', layout: 'table', date: 'dMonY',
    title: ['RAS AL KHAIMAH ECONOMIC ZONE', 'RAKEZ', 'LICENSE'], form: 'Free Zone Limited Liability Company',
    no: (n) => String(5000000 + n * 7717 % 999999), printsEmirate: false,
    L: { no: 'License Number', name: 'Company Name', trade: 'Trade Name', form: 'Legal Status', issue: 'Issue Date', expiry: 'License Expiry Date', acts: 'Activities', auth: 'Issued By' } },
  uaq_ded: { emirate: 'Umm Al Quwain', authority: 'Umm Al Quwain Department of Economic Development', layout: 'colon', date: 'dmy/',
    title: ['GOVERNMENT OF UMM AL QUWAIN', 'DEPARTMENT OF ECONOMIC DEVELOPMENT', 'TRADE LICENCE'], form: 'Limited Liability Company',
    no: (n) => String(3000 + n * 97 % 6999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  fujairah_ded: { emirate: 'Fujairah', authority: 'Fujairah Department of Industry and Economy', layout: 'colon', date: 'dmy/',
    title: ['GOVERNMENT OF FUJAIRAH', 'DEPARTMENT OF INDUSTRY AND ECONOMY', 'TRADE LICENCE'], form: 'Limited Liability Company',
    no: (n) => String(40000 + n * 113 % 9999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  jafza: { emirate: 'Dubai', authority: 'Jebel Ali Free Zone Authority', layout: 'table', date: 'dmy/',
    title: ['JEBEL ALI FREE ZONE AUTHORITY', 'JAFZA', 'TRADING LICENCE'], form: 'Free Zone Establishment',
    no: (n) => String(100000 + n * 4271 % 99999), printsEmirate: false,
    L: { no: 'Licence No', name: 'Name of Company', trade: 'Trade Name', form: 'Legal Status', issue: 'Date of Issue', expiry: 'Valid Until', acts: 'Licensed Activities', auth: 'Issued By' } },
  dmcc: { emirate: 'Dubai', authority: 'Dubai Multi Commodities Centre Authority', layout: 'colon', date: 'MonDY',
    title: ['DUBAI MULTI COMMODITIES CENTRE', 'DMCC AUTHORITY', 'TRADE LICENCE'], form: 'DMCC Company',
    no: (n) => 'DMCC-' + (100000 + n * 6007 % 899999), printsEmirate: false,
    L: { no: 'Licence Number', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Licensed Activities', auth: 'Issuing Authority' } },
  dafza: { emirate: 'Dubai', authority: 'Dubai Airport Free Zone Authority', layout: 'table', date: 'dmy/',
    title: ['DUBAI AIRPORT FREEZONE AUTHORITY', 'DAFZA', 'TRADE LICENSE'], form: 'Free Zone Company',
    no: (n) => String(1000 + n * 37 % 8999), printsEmirate: false,
    L: { no: 'License No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Status', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', auth: 'Issuing Authority' } },
  dso: { emirate: 'Dubai', authority: 'Dubai Silicon Oasis Authority', layout: 'colon', date: 'dmy/',
    title: ['DUBAI SILICON OASIS AUTHORITY', 'DSO', 'TRADE LICENCE'], form: 'Free Zone Limited Liability Company',
    no: (n) => String(10000 + n * 409 % 89999), printsEmirate: false,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', auth: 'Issuing Authority' } },
  ifza: { emirate: 'Dubai', authority: 'International Free Zone Authority', layout: 'table', date: 'dMonY',
    title: ['INTERNATIONAL FREE ZONE AUTHORITY', 'IFZA DUBAI', 'COMMERCIAL LICENCE'], form: 'Free Zone Company',
    no: (n) => String(10000 + n * 503 % 89999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  meydan: { emirate: 'Dubai', authority: 'Meydan Free Zone', layout: 'colon', date: 'dmy/',
    title: ['MEYDAN FREE ZONE', 'DUBAI', 'COMMERCIAL LICENCE'], form: 'Free Zone Limited Liability Company',
    no: (n) => 'MFZ-' + (1000 + n * 211 % 8999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  shams: { emirate: 'Sharjah', authority: 'Sharjah Media City Authority', layout: 'table', date: 'dmy/',
    title: ['SHARJAH MEDIA CITY', 'SHAMS', 'LICENCE'], form: 'Free Zone Establishment',
    no: (n) => String(2000000 + n * 1013 % 999999), printsEmirate: true,
    L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Form', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', emirate: 'Emirate', auth: 'Issuing Authority' } },
  difc: { emirate: 'Dubai', authority: 'Dubai International Financial Centre Registrar of Companies', layout: 'colon', date: 'ymd',
    title: ['DUBAI INTERNATIONAL FINANCIAL CENTRE', 'REGISTRAR OF COMPANIES', 'COMMERCIAL LICENCE'], form: 'Private Company',
    no: (n) => 'CL' + (1000 + n * 29 % 8999), printsEmirate: false,
    L: { no: 'Registered Number', name: 'Company Name', trade: 'Trading Name', form: 'Legal Status', issue: 'Date of Issue', expiry: 'Expiry Date', acts: 'Licensed Activities', auth: 'Issued By' } },
};

// One activity line per trade, worded the way UAE licences word an activity; null = no construction trade.
export const ACTIVITIES = [
  ['Aluminium Works Contracting', 'aluminium'], ['Electrical Fitting Contracting', 'electrical'],
  ['Plumbing and Sanitary Installation', 'plumbing'], ['Air Conditioning and Ventilation Systems Installation', 'hvac'],
  ['Floor and Wall Tiling Works', 'flooring'], ['Carpentry and Joinery Works', 'joinery'], ['Painting Contracting', 'painting'],
  ['Building Waterproofing Works', 'waterproofing'], ['Landscaping Works', 'landscaping'], ['Glass and Glazing Works', 'glazing'],
  ['Lifts and Escalators Installation and Maintenance', 'elevators'], ['Fire Fighting Equipment Installation', 'fire_fighting'],
  ['General Trading', null], ['Import and Export', null],
];
const NAMES = ['Falcon', 'Pearl', 'Dune', 'Oasis', 'Horizon', 'Saker', 'Marina', 'Crescent', 'Ghaf', 'Palm', 'Sidra', 'Nakheel', 'Corniche', 'Lulu', 'Wadi', 'Qamar', 'Najm', 'Reem'];
const NAMES_AR = { Falcon: 'فالكون', Pearl: 'اللؤلؤة', Dune: 'الكثبان', Oasis: 'الواحة', Horizon: 'الأفق', Saker: 'الصقر', Marina: 'المرسى', Crescent: 'الهلال',
  Ghaf: 'الغاف', Palm: 'النخلة', Sidra: 'السدرة', Nakheel: 'النخيل', Corniche: 'الكورنيش', Lulu: 'لولو', Wadi: 'الوادي', Qamar: 'القمر', Najm: 'النجم', Reem: 'الريم' };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const pad = (n) => String(n).padStart(2, '0');
export function printDate(iso, style) {
  const [y, m, d] = iso.split('-').map(Number);
  switch (style) {
    case 'dmy/': return `${pad(d)}/${pad(m)}/${y}`;
    case 'dmy-': return `${pad(d)}-${pad(m)}-${y}`;
    case 'ymd': return iso;
    case 'dMonY': return `${pad(d)} ${MON[m - 1]} ${y}`;
    case 'dMONy': return `${pad(d)}-${MON[m - 1].toUpperCase()}-${y}`;
    case 'MonDY': return `${MONTH[m - 1]} ${d}, ${y}`;
    default: throw new Error(style);
  }
}

// ── one licence's content ─────────────────────────────────────────────────────────────────────────
export function licenceTruth(key, n, opts = {}) {
  const A = AUTHORITIES[key];
  const word = NAMES[n % NAMES.length];
  const acts = opts.acts || [ACTIVITIES[n % 12], ACTIVITIES[(n + 5) % 12]];
  const tradeWord = acts[0][0].split(' ')[0];
  const suffix = /Sole/.test(A.form) ? 'Est' : /Establishment/.test(A.form) ? 'FZE' : /Free Zone|DMCC/.test(A.form) ? (key === 'dmcc' ? 'DMCC' : 'FZ LLC') : /Private|Limited by Shares/.test(A.form) ? 'Ltd' : 'LLC';
  const legal = opts.legal || `ZZ DEMO ${word} ${tradeWord} ${suffix}`;
  // issued in the past (2024-2026, never after Sep 2026), valid until 2027 or later
  const iy = 2024 + (n % 3), im = 1 + (n % 9), id = 1 + (n % 27), ey = Math.max(iy + 2 + (n % 2), 2027);
  return {
    licence_no: A.no(n + 1), legal_name_en: legal, legal_name_ar: `زد زد ديمو ${NAMES_AR[word]}`,
    trade_name: `ZZ DEMO ${word} ${tradeWord}`, activities: acts.map((a) => a[0]), trades: [...new Set(acts.map((a) => a[1]).filter(Boolean))].sort(),
    authority: A.authority, legal_form: A.form, issue_date: opts.issue || `${iy}-${pad(im)}-${pad(id)}`,
    expiry_date: opts.expiry || `${ey}-${pad(im)}-${pad(id === 1 ? 28 : id - 1)}`, emirate: A.emirate,
  };
}
const fieldRows = (A, t) => [
  [A.L.no, t.licence_no], [A.L.name, t.legal_name_en], [A.L.trade, t.trade_name], [A.L.form, t.legal_form],
  ...(A.printsEmirate ? [[A.L.emirate, t.emirate]] : []), [A.L.auth, t.authority],
  [A.L.issue, printDate(t.issue_date, A.date)], [A.L.expiry, printDate(t.expiry_date, A.date)], [A.L.acts, t.activities.join(', ')],
];

// ── text PDF: colon layout (one string per line) or a two-column table (label and value each placed on its own) ──
const esc = (s) => String(s).replace(/([()\\])/g, '\\$1');
export function licenceTextPdf(A, t, { cover = false } = {}) {
  const rows = fieldRows(A, t);
  const head = A.title.map((s, i) => [s, i === A.title.length - 1 ? 16 : 13]);
  const footer = [['(QuotesDone synthetic fixture - not a real company or licence)', 8]];
  let page;
  if (A.layout === 'colon') page = [...head, ['', 10], ...rows.map(([k, v]) => [`${k}: ${v}`, 11]), ['', 10], ...footer];
  else {
    // the table: every cell is its own BT..ET with its own Tm, label at x=60, value at x=230, same baseline
    let y = 760, c = '';
    for (const [s, size] of head) { c += `BT /F1 ${size} Tf 1 0 0 1 60 ${y} Tm (${esc(s)}) Tj ET\n`; y -= size + 10; }
    y -= 14;
    for (const [k, v] of rows) { c += `BT /F1 10 Tf 1 0 0 1 60 ${y} Tm (${esc(k)}) Tj ET\nBT /F1 10 Tf 1 0 0 1 230 ${y} Tm (${esc(v)}) Tj ET\n`; y -= 22; }
    c += `BT /F1 8 Tf 1 0 0 1 60 ${y - 20} Tm (${esc(footer[0][0])}) Tj ET\n`;
    return cover ? multiPage(c) : demoPdfPages([[]], { content: c });
  }
  if (cover) return demoPdfPages([[['COVER LETTER', 14], ['To whom it may concern,', 11], ['Please find our trade licence on the next page.', 11]], page]);
  return demoPdfPages([page]);
}
function multiPage(tableContent) {
  // page 1 a cover letter, page 2 the table licence: built by hand because demoPdfPages shares one `content`
  const pages = ['BT /F1 14 Tf 1 0 0 1 60 760 Tm (COVER LETTER) Tj ET\nBT /F1 11 Tf 1 0 0 1 60 730 Tm (Please find our trade licence on the next page.) Tj ET\n', tableContent];
  return rawPdf(pages.map((c) => ({ content: c })));
}
/** A PDF whose pages are given content streams, optionally each with one JPEG XObject (a scanned page). */
export function rawPdf(pages) {
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', null, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  const kids = [];
  const bin = [];
  for (const p of pages) {
    const pageId = objs.length + 1;
    kids.push(`${pageId} 0 R`);
    let res = '/Font << /F1 3 0 R >>', content = p.content || '';
    objs.push(null); // page placeholder
    if (p.jpeg) {
      const imgId = objs.length + 1;
      objs.push({ dict: `<< /Type /XObject /Subtype /Image /Width ${p.w} /Height ${p.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>`, data: p.jpeg });
      res += ` /XObject << /Im1 ${imgId} 0 R >>`;
      content = `q 595 0 0 842 0 0 cm /Im1 Do Q\n`;
    }
    const cId = objs.length + 1;
    objs.push({ dict: `<< /Length ${Buffer.byteLength(content, 'latin1')} >>`, data: Buffer.from(content, 'latin1') });
    objs[pageId - 1] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << ${res} >> /Contents ${cId} 0 R >>`;
  }
  objs[1] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>`;
  const parts = [Buffer.from('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n', 'latin1')];
  let len = parts[0].length; const offs = [];
  objs.forEach((o, i) => {
    offs.push(len);
    const b = typeof o === 'string' ? Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, 'latin1')
      : Buffer.concat([Buffer.from(`${i + 1} 0 obj\n${o.dict}\nstream\n`, 'latin1'), o.data, Buffer.from('\nendstream\nendobj\n', 'latin1')]);
    parts.push(b); len += b.length;
  });
  parts.push(Buffer.from(`xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')
    + `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${len}\n%%EOF\n`, 'latin1'));
  return Buffer.concat(parts);
}

// Arabic-only licences print everything in Arabic (dates and the licence number stay in digits).
export const ACT_AR = { 'Aluminium Works Contracting': 'مقاولات أعمال الألمنيوم', 'Electrical Fitting Contracting': 'مقاولات التركيبات الكهربائية',
  'Plumbing and Sanitary Installation': 'تركيب التمديدات الصحية والسباكة', 'Air Conditioning and Ventilation Systems Installation': 'تركيب أنظمة التكييف والتهوية',
  'Floor and Wall Tiling Works': 'أعمال تبليط الأرضيات والجدران', 'Carpentry and Joinery Works': 'أعمال النجارة', 'Painting Contracting': 'مقاولات أعمال الدهان',
  'Building Waterproofing Works': 'أعمال عزل المباني ضد الماء', 'Landscaping Works': 'أعمال تنسيق الحدائق', 'Glass and Glazing Works': 'أعمال الزجاج',
  'Lifts and Escalators Installation and Maintenance': 'تركيب وصيانة المصاعد والسلالم المتحركة', 'Fire Fighting Equipment Installation': 'تركيب معدات مكافحة الحريق',
  'General Trading': 'تجارة عامة', 'Import and Export': 'استيراد وتصدير' };
const EMIRATE_AR = { Dubai: 'دبي', 'Abu Dhabi': 'أبوظبي', Sharjah: 'الشارقة', Ajman: 'عجمان', 'Umm Al Quwain': 'أم القيوين', 'Ras Al Khaimah': 'رأس الخيمة', Fujairah: 'الفجيرة' };
const AUTH_AR = { 'Ajman Department of Economic Development': 'دائرة التنمية الاقتصادية - عجمان', 'Fujairah Department of Industry and Economy': 'دائرة الصناعة والاقتصاد - الفجيرة' };
const FORM_AR = { 'Sole Establishment': 'مؤسسة فردية', 'Limited Liability Company': 'شركة ذات مسؤولية محدودة' };
// ── the same licence as a picture (what a phone or a scanner produces) ───────────────────────────────
const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
export function licenceSvg(A, t, lang = 'en') {
  const W = 1240, H = 1754; let y = 150; const out = [];
  const txt = (x, s, size, anchor = 'start', weight = 'normal') => out.push(`<text x="${x}" y="${y}" font-family="Arial" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}" fill="#111">${xml(s)}</text>`);
  const AR = { no: 'رقم الرخصة', name: 'اسم الشركة', trade: 'الاسم التجاري', form: 'الشكل القانوني', emirate: 'الإمارة', auth: 'جهة الإصدار', issue: 'تاريخ الإصدار', expiry: 'تاريخ الانتهاء', acts: 'الأنشطة' };
  const keys = ['no', 'name', 'trade', 'form', ...(A.printsEmirate ? ['emirate'] : []), 'auth', 'issue', 'expiry', 'acts'];
  const val = { no: t.licence_no, name: t.legal_name_en, trade: t.trade_name, form: t.legal_form, emirate: t.emirate, auth: t.authority,
    issue: printDate(t.issue_date, A.date), expiry: printDate(t.expiry_date, A.date), acts: t.activities.join(', ') };
  const valAr = { ...val, name: t.legal_name_ar, trade: t.legal_name_ar, form: FORM_AR[t.legal_form] || 'شركة ذات مسؤولية محدودة', emirate: EMIRATE_AR[t.emirate], auth: AUTH_AR[t.authority] || t.authority,
    acts: t.activities.map((a) => ACT_AR[a] || a).join('، ') };
  if (lang !== 'ar') for (const s of A.title) { txt(W / 2, s, 40, 'middle', 'bold'); y += 56; }
  if (lang !== 'en') { txt(W / 2, 'رخصة تجارية', 44, 'middle', 'bold'); y += 60; }
  y += 40;
  for (const k of keys) {
    // The activities print one per line, as a licence prints them: a long line would run off the page edge.
    const lines = (v) => (k === 'acts' ? String(v).split(/(?<=[,،])\s*/) : [v]);
    if (lang === 'en') { txt(90, A.L[k], 28, 'start', 'bold'); lines(val[k]).forEach((v, i) => { if (i) y += 40; txt(520, v, 28); }); }
    else if (lang === 'bi') { txt(90, A.L[k], 26, 'start', 'bold'); txt(1160, AR[k], 26, 'end', 'bold'); lines(val[k]).forEach((v, i) => { if (i) y += 38; txt(450, v, 26); }); }
    else { txt(1160, AR[k], 28, 'end', 'bold'); lines(valAr[k]).forEach((v, i) => { if (i) y += 40; txt(820, v, 28, 'end'); }); }
    y += 64;
  }
  y += 40; txt(90, lang === 'ar' ? 'نموذج اصطناعي - ليست رخصة حقيقية' : '(QuotesDone synthetic fixture - not a real company or licence)', 20);
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="100%" height="100%" fill="#fbfbf8"/>`
    + `<rect x="40" y="40" width="${W - 80}" height="${H - 80}" fill="none" stroke="#335" stroke-width="4"/>${out.join('')}</svg>`);
}
export async function picture(svg, variant) {
  const base = sharp(svg).flatten({ background: '#ffffff' });
  switch (variant) {
    case 'png': return { bytes: await base.png().toBuffer(), mime: 'image/png', ext: 'png' };
    case 'jpg': return { bytes: await base.jpeg({ quality: 82 }).toBuffer(), mime: 'image/jpeg', ext: 'jpg' };
    case 'rotated90': return { bytes: await base.rotate(90).jpeg({ quality: 82 }).toBuffer(), mime: 'image/jpeg', ext: 'jpg' };
    case 'skewed': return { bytes: await sharp(await base.png().toBuffer()).rotate(4, { background: '#ffffff' }).jpeg({ quality: 80 }).toBuffer(), mime: 'image/jpeg', ext: 'jpg' };
    case 'lowdpi': return { bytes: await base.resize({ width: 520 }).jpeg({ quality: 60 }).toBuffer(), mime: 'image/jpeg', ext: 'jpg' };  // ~63 dpi
    case 'phone': {
      // perspective-like shear, a slight turn, a desk-grey surround, soft focus and uneven light
      const sheared = await sharp(await base.png().toBuffer()).affine([[1, 0.06], [0.03, 0.96]], { background: '#6b6b6b' }).png().toBuffer();
      const turned = await sharp(sheared).rotate(-3, { background: '#6b6b6b' }).blur(0.8).modulate({ brightness: 0.88 }).png().toBuffer();
      const m = await sharp(turned).metadata();
      const shadow = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${m.width}" height="${m.height}"><defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#000" stop-opacity="0.25"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient></defs><rect width="100%" height="100%" fill="url(#g)"/></svg>`);
      return { bytes: await sharp(turned).composite([{ input: shadow }]).jpeg({ quality: 72 }).toBuffer(), mime: 'image/jpeg', ext: 'jpg' };
    }
    case 'scan_pdf': {
      const j = await base.resize({ width: 1240 }).jpeg({ quality: 78 }).toBuffer();
      const m = await sharp(j).metadata();
      return { bytes: rawPdf([{ jpeg: j, w: m.width, h: m.height }]), mime: 'application/pdf', ext: 'pdf' };
    }
    default: throw new Error(variant);
  }
}

// ── profiles, catalogue, certificates ──────────────────────────────────────────────────────────────
function zip(entries) {
  // a minimal deflate zip (docx / pptx are zips of XML); node's own zlib, no dependency
  const parts = [], central = []; let off = 0;
  for (const [name, data] of entries) {
    const raw = Buffer.from(data, 'utf8'), comp = deflateRawSync(raw), nm = Buffer.from(name, 'utf8'), c = crc32(raw);
    const h = Buffer.alloc(30); h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt16LE(0x0800, 6); h.writeUInt16LE(8, 8);
    h.writeUInt32LE(c, 14); h.writeUInt32LE(comp.length, 18); h.writeUInt32LE(raw.length, 22); h.writeUInt16LE(nm.length, 26);
    parts.push(h, nm, comp);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(0x0800, 8); ch.writeUInt16LE(8, 10);
    ch.writeUInt32LE(c, 16); ch.writeUInt32LE(comp.length, 20); ch.writeUInt32LE(raw.length, 24); ch.writeUInt16LE(nm.length, 28); ch.writeUInt32LE(off, 42);
    central.push(ch, nm); off += 30 + nm.length + comp.length;
  }
  const cd = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cd, end]);
}
const X = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
export function docx(paras) {
  const W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  return zip([['[Content_Types].xml', `${X}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>`],
    ['word/document.xml', `${X}<w:document ${W}><w:body>${paras.map((p) => `<w:p><w:r><w:t xml:space="preserve">${xml(p)}</w:t></w:r></w:p>`).join('')}</w:body></w:document>`]]);
}
function pptx(slides) {
  const A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
  return zip([['[Content_Types].xml', `${X}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/>${slides.map((_, i) => `<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`).join('')}</Types>`],
    ...slides.map((ps, i) => [`ppt/slides/slide${i + 1}.xml`, `${X}<p:sld ${A}><p:cSld><p:spTree><p:sp><p:txBody>${ps.map((t) => `<a:p><a:r><a:t>${xml(t)}</a:t></a:r></a:p>`).join('')}</p:txBody></p:sp></p:spTree></p:cSld></p:sld>`])]);
}
// The way a real profile lists what the company does: a services list, each item the trade's own name.
const PROFILE_SERVICE = { aluminium: 'Aluminium works', electrical: 'Electrical works', plumbing: 'Plumbing works', hvac: 'HVAC works',
  flooring: 'Flooring works', joinery: 'Joinery works', painting: 'Painting works', waterproofing: 'Waterproofing works',
  landscaping: 'Landscaping works', glazing: 'Glazing works', elevators: 'Elevator installation', fire_fighting: 'Fire fighting systems' };
function profileLines(name, trades, brands, i) {
  return [`${name} - Company Profile`, 'About us', `${name} is a UAE contractor established in 20${10 + i}, serving Dubai, Sharjah and Abu Dhabi.`,
    'Our services', ...trades.map((t) => `- ${PROFILE_SERVICE[t]}`), 'Brands we work with', `- ${brands.join(', ')}`,
    'Capacity', `- ${40 + i * 10} skilled staff, ${2 + i} project teams, projects up to AED ${(i + 2) * 500},000`,
    'Certifications', '- ISO 9001:2015 quality management', '(QuotesDone synthetic fixture - not a real company)'];
}

// A company profile of a given format, printing the given company's name. The corpus prints its own fictional company on each
// profile; stage 2 S21 prints the SUPPLIER's registered name on it (stage-2 run f0b2de8f, 2 Nov 2026: a profile that names another
// company than the registered one proposes no trade, by design, so a profile of "another company" cannot prove the reading).
export async function profileBytes(fmt, name, trades, brands, i) {
  const lines = profileLines(name, trades, brands, i);
  if (fmt === 'pdf') return { bytes: demoPdfPages([lines.map((l) => [l, l.startsWith('-') ? 10 : 12])]), mime: 'application/pdf' };
  if (fmt === 'docx') return { bytes: docx(lines), mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };
  if (fmt === 'pptx') return { bytes: pptx([lines.slice(0, 3), lines.slice(3)]), mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation' };
  const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1240" height="1400"><rect width="100%" height="100%" fill="#fff"/>${lines.map((l, k) => `<text x="80" y="${120 + k * 70}" font-family="Arial" font-size="30">${xml(l)}</text>`).join('')}</svg>`);
  return { bytes: await sharp(svg).png().toBuffer(), mime: 'image/png' };
}

// ── the corpus ─────────────────────────────────────────────────────────────────────────────────────
const IMG_VARIANTS = ['scan_pdf', 'png', 'jpg', 'rotated90', 'skewed', 'lowdpi', 'phone'];
export async function buildCorpus(outDir) {
  mkdirSync(outDir, { recursive: true });
  const docs = [];
  const save = (id, bytes, ext, mime, rec) => { const file = `${id}.${ext}`; writeFileSync(join(outDir, file), bytes); docs.push({ id, file, mime, ...rec }); };
  let n = 0;
  const keys = Object.keys(AUTHORITIES);
  for (const key of keys) {
    const A = AUTHORITIES[key];
    // 1. the text PDF in this authority's own layout
    const t = licenceTruth(key, n++);
    save(`lic_${key}_text`, licenceTextPdf(A, t), 'pdf', 'application/pdf', { kind: 'licence', authority: key, format: `text_pdf_${A.layout}`, registered_name: t.legal_name_en, truth: t, expected: 'approve', text_layer: true });
    // 2. the same authority as a picture, rotating through the scan shapes
    const t2 = licenceTruth(key, n++);
    const v = IMG_VARIANTS[keys.indexOf(key) % IMG_VARIANTS.length];
    const p = await picture(licenceSvg(A, t2, 'en'), v);
    save(`lic_${key}_${v}`, p.bytes, p.ext, p.mime, { kind: 'licence', authority: key, format: v, registered_name: t2.legal_name_en, truth: t2, expected: 'approve', text_layer: false });
  }
  // 3. bilingual and Arabic-only pictures, a multi-page PDF, and a second picture shape for six authorities
  for (const [key, lang, v] of [['dubai_det', 'bi', 'jpg'], ['sharjah_sedd', 'bi', 'phone'], ['abu_dhabi_added', 'bi', 'scan_pdf'],
                                ['ajman_ded', 'ar', 'png'], ['fujairah_ded', 'ar', 'jpg']]) {
    const t = licenceTruth(key, n++);
    const p = await picture(licenceSvg(AUTHORITIES[key], t, lang), v);
    // An Arabic-only licence never prints the English name the company registered with: no code and no model can match
    // the two exactly, so the right decision is a hold on the name (unread or mismatch: a person compares them).
    // What it prints is the truth: the trade name, the legal form and the activities in Arabic.
    const tt = lang === 'ar' ? { ...t, legal_name_en: null, trade_name: t.legal_name_ar, legal_form: FORM_AR[t.legal_form], activities: t.activities.map((x) => ACT_AR[x]) } : t;
    save(`lic_${key}_${lang}_${v}`, p.bytes, p.ext, p.mime, { kind: 'licence', authority: key, format: `${lang === 'bi' ? 'bilingual' : 'arabic_only'}_${v}`, registered_name: t.legal_name_en, truth: tt, expected: lang === 'ar' ? 'hold_name' : 'approve', text_layer: false });
  }
  for (const key of ['dmcc', 'jafza']) {
    const t = licenceTruth(key, n++);
    save(`lic_${key}_multipage`, licenceTextPdf(AUTHORITIES[key], t, { cover: true }), 'pdf', 'application/pdf', { kind: 'licence', authority: key, format: 'multipage_pdf', registered_name: t.legal_name_en, truth: t, expected: 'approve', text_layer: true });
  }
  // 4. the cases that must be HELD
  { const t = licenceTruth('dubai_det', n++, { issue: '2024-07-01', expiry: '2025-06-30' });
    save('lic_expired_text', licenceTextPdf(AUTHORITIES.dubai_det, t), 'pdf', 'application/pdf', { kind: 'licence', authority: 'dubai_det', format: 'text_pdf_table', registered_name: t.legal_name_en, truth: t, expected: 'licence_expired', text_layer: true }); }
  { const t = licenceTruth('sharjah_sedd', n++, { issue: '2024-02-11', expiry: '2026-02-10' });
    const p = await picture(licenceSvg(AUTHORITIES.sharjah_sedd, t, 'en'), 'jpg');
    save('lic_expired_scan', p.bytes, p.ext, p.mime, { kind: 'licence', authority: 'sharjah_sedd', format: 'jpg', registered_name: t.legal_name_en, truth: t, expected: 'licence_expired', text_layer: false }); }
  { const t = licenceTruth('dubai_ded_old', n++, { legal: 'ZZ DEMO Mirage Contracting LLC' });
    save('lic_mismatch_text', licenceTextPdf(AUTHORITIES.dubai_ded_old, t), 'pdf', 'application/pdf', { kind: 'licence', authority: 'dubai_ded_old', format: 'text_pdf_colon', registered_name: 'ZZ DEMO Sahara Technical Services LLC', truth: t, expected: 'name_autofilled', text_layer: true });
    // the same licence uploaded by an ALREADY APPROVED supplier registered under another name (a licence swap)
    docs.push({ id: 'lic_mismatch_text_approved_swap', file: 'lic_mismatch_text.pdf', mime: 'application/pdf', kind: 'licence', authority: 'dubai_ded_old', format: 'text_pdf_colon', registered_name: 'ZZ DEMO Oasis Swap Trading LLC', start_approved: true, truth: t, expected: 'name_autofilled', text_layer: true }); }
  { const t = licenceTruth('rakez', n++, { legal: 'ZZ DEMO Atlas Building Works FZ LLC' });
    const p = await picture(licenceSvg(AUTHORITIES.rakez, t, 'en'), 'png');
    save('lic_mismatch_scan', p.bytes, p.ext, p.mime, { kind: 'licence', authority: 'rakez', format: 'png', registered_name: 'ZZ DEMO Zenith Maintenance FZ LLC', truth: t, expected: 'name_autofilled', text_layer: false }); }
  const blankTruth = { licence_no: null, legal_name_en: null, legal_name_ar: null, trade_name: null, activities: [], trades: [], authority: null, legal_form: null, issue_date: null, expiry_date: null, emirate: null };
  save('lic_blank_pdf', rawPdf([{ content: '' }]), 'pdf', 'application/pdf', { kind: 'licence', authority: 'none', format: 'blank_pdf', registered_name: 'ZZ DEMO Blank Page LLC', truth: blankTruth, expected: 'licence_unreadable', text_layer: false });
  save('lic_blank_photo', await sharp({ create: { width: 900, height: 1200, channels: 3, background: '#f4f4f0' } }).jpeg().toBuffer(), 'jpg', 'image/jpeg', { kind: 'licence', authority: 'none', format: 'blank_photo', registered_name: 'ZZ DEMO Blank Photo LLC', truth: blankTruth, expected: 'licence_unreadable', text_layer: false });
  docs.push({ id: 'lic_missing', file: null, mime: null, kind: 'licence', authority: 'none', format: 'no_file', registered_name: 'ZZ DEMO No Licence LLC', truth: blankTruth, expected: 'reg_licence', text_layer: false });

  // 5. company profiles, a catalogue, and two certificates
  const P = [
    ['profile_pdf', ['aluminium', 'glazing'], ['Technal', 'Schueco'], 'pdf'], ['profile_docx', ['electrical', 'fire_fighting'], ['Schneider', 'ABB'], 'docx'],
    ['profile_pptx', ['hvac', 'plumbing'], ['Daikin', 'Grohe'], 'pptx'], ['profile_png', ['joinery', 'flooring'], ['Egger', 'Tarkett'], 'png'],
    ['profile_pdf_paint', ['painting', 'waterproofing'], ['Jotun', 'Sika'], 'pdf'], ['profile_docx_land', ['landscaping'], ['Rain Bird'], 'docx'],
  ];
  P.forEach(([id, trades, brands, fmt], i) => { /* sync builders below */ docs.push({ id, pending: { trades, brands, fmt, i } }); });
  for (const d of docs.filter((x) => x.pending)) {
    const { trades, brands, fmt, i } = d.pending; delete d.pending;
    const name = `ZZ DEMO ${NAMES[i + 3]} Projects LLC`;
    const { bytes, mime } = await profileBytes(fmt, name, trades, brands, i);
    const ext = fmt;
    writeFileSync(join(outDir, `${d.id}.${ext}`), bytes);
    Object.assign(d, { file: `${d.id}.${ext}`, mime, kind: 'profile', authority: 'n/a', format: fmt, registered_name: name, truth: { trades: [...trades].sort(), brands }, text_layer: fmt !== 'png' });
  }
  // A NAME PRINTED WITHOUT A LEGAL SUFFIX (12 Oct 2026): every name here holds a trade word ("Cleaning", "Floor",
  // "التنظيف") and none is the company's trade; only the services list is. The registered name carries the suffix the
  // profile leaves off; "Trade Name" and the Arabic trade name are known only by their labels.
  { const name = 'ZZ DEMO Falcon Cleaning';
    const lines = [`${name} - Company Profile`, 'Trade Name: ZZ DEMO Horizon Floor', 'الاسم التجاري: زد زد ديمو الأفق للتنظيف', 'About us',
      `${name} is a UAE contractor established in 2012, serving Dubai and Sharjah.`, 'Our services', `- ${PROFILE_SERVICE.painting}`,
      '(QuotesDone synthetic fixture - not a real company)'];
    save('profile_docx_unsuffixed_name', docx(lines), 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      { kind: 'profile', authority: 'n/a', format: 'docx', registered_name: `${name} LLC`, truth: { trades: ['painting'], brands: [] }, text_layer: true }); }
  save('catalogue_pdf', demoPdfPages([[['ZZ DEMO Reem Building Supplies - Product Catalogue 2026', 14], ['Section 1: Aluminium Works', 12], ['- Thermal break aluminium windows, series TB-60', 10],
    ['- Sliding door systems, series SL-90', 10], ['Section 2: Glazing Works', 12], ['- Double glazed units 6+12+6 mm', 10], ['Warehouse: Al Quoz Industrial Area 3, Dubai', 9],
    ['(QuotesDone synthetic fixture - not a real company)', 8]]]), 'pdf', 'application/pdf', { kind: 'catalogue', authority: 'n/a', format: 'pdf', registered_name: 'ZZ DEMO Reem Building Supplies LLC', truth: { trades: ['aluminium', 'glazing'] }, text_layer: true });
  save('vat_certificate', demoPdfPages([[['FEDERAL TAX AUTHORITY', 16], ['TAX REGISTRATION CERTIFICATE', 14], ['Legal Name: ZZ DEMO Falcon Aluminium LLC', 11],
    ['Tax Registration Number (TRN): 100000000000003', 11], ['Effective Registration Date: 01/01/2024', 11], ['Date of Issue: 15/01/2024', 11],
    ['(QuotesDone synthetic fixture - not a real certificate)', 8]]]), 'pdf', 'application/pdf', { kind: 'vat_cert', authority: 'n/a', format: 'pdf', registered_name: 'ZZ DEMO Falcon Aluminium LLC', truth: { expiry_date: null }, text_layer: true });
  save('iso_certificate', demoPdfPages([[['CERTIFICATE OF REGISTRATION', 16], ['ISO 9001:2015', 14], ['This is to certify that ZZ DEMO Pearl Electrical LLC', 11],
    ['Certificate No: QMS-ZZ-40217', 11], ['Initial Certification Date: 12/05/2022', 11], ['Valid Until: 11/05/2028', 11],
    ['(QuotesDone synthetic fixture - not a real certificate)', 8]]]), 'pdf', 'application/pdf', { kind: 'iso_cert', authority: 'n/a', format: 'pdf', registered_name: 'ZZ DEMO Pearl Electrical LLC', truth: { expiry_date: '2028-05-11' }, text_layer: true });

  // Only an Arabic-only licence prints the Arabic name; on every other document it is not there to be read.
  for (const d of docs) if (d.kind === 'licence' && d.truth && !String(d.format).startsWith('arabic_only')) d.truth = { ...d.truth, legal_name_ar: null };
  writeFileSync(join(outDir, 'truth.json'), JSON.stringify({ generated_at: new Date().toISOString(), docs }, null, 1));
  return docs;
}

if (process.argv[1] && process.argv[1].endsWith('document_intake_corpus.mjs')) {
  const i = process.argv.indexOf('--out');
  if (i < 0) { console.error('usage: --out <dir>'); process.exit(2); }
  const docs = await buildCorpus(process.argv[i + 1]);
  console.log(`${docs.length} documents written to ${process.argv[i + 1]}`);
}
