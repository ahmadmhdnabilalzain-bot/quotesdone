// scripts/e2e/identity_never_leaks_before_reveal.mjs — the planted-identity leak test over EVERY artefact one side
// of the marketplace sees of the other before the reveal (sales_engineer, 3 Nov 2026; qualification matrix gap #3,
// P0, rows E05 / E07 / F04.04: "0 identity strings in 480 trials").
//
// WHAT IT DOES
//   1. CORPUS. Builds 60 drawings and 100 supplier quotations per repeat, 3 repeats (480 trials), each repeat with
//      fresh identities and freshly drawn formats, plus 60 pre-reveal Q&A messages. Every identity is a ZZ fixture:
//      ZZ company / person names, @example.invalid mail, *.example.invalid hosts, the reserved +971 50 000 00xx and
//      +971 4 000 00xx blocks. Planted where real documents carry them: title blocks (right or bottom strip), a
//      letterhead header, a footer, body notes, Form XObjects, Arabic text runs (Type0 / Identity-H), PDF /Info and
//      XMP metadata, link and note annotations, the file name, and embedded raster images (logo, stamp, signature,
//      QR-like code) drawn with the company's name in them. Phones in every spelling a UAE document uses (+971,
//      00971, 971, 05x, (04), dotted, spaced, Arabic-Indic digits); TRNs spaced / dashed / Arabic-Indic; licence,
//      IBAN, P.O. Box (EN and AR), Makani, plot; English, Arabic and transliterated company names.
//   2. PIPELINE. scripts/e2e/identity_leak_pipeline.ts runs the REAL modules (the code the deployed functions
//      import) over the corpus and writes exactly what the other side would be handed.
//   3. GRADE, BY CODE. Every output is text-extracted (pdftotext and our own stream reader, metadata included),
//      raster outputs and rasterised output PDFs are OCR'd (tesseract.js, eng+ara, the portal's own language data),
//      and planted images are checked pixel by pixel where they were placed. A planted token found in ANY surface
//      the other side receives is a leak. A held artefact (nothing sent) is not a leak, and the hold rate is
//      reported beside the leak rate so "0 leaks" can never be bought by holding everything.
//   4. OCR CONTROL. The same OCR reads the ORIGINAL pages: the share of planted tokens it can read there is printed,
//      because an OCR that cannot read the original proves nothing about the redacted copy.
//
//   node scripts/e2e/identity_never_leaks_before_reveal.mjs [--repeats 3] [--out <dir>] [--no-ocr] [--json <file>]
//
// NOTHING HERE CAN REACH A REAL PERSON: it writes files and reads them back. No network call, no database row, no
// model call (spend USD 0). The scanned-PDF drawings are the one path decided by a model in production; they are
// recorded as `model_path` and counted separately (see the report).
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d);
const REPEATS = Number(arg('--repeats', 3));
const OUT = path.resolve(arg('--out', path.join(process.env.TEMP || '/tmp', `qd-leak-${Date.now().toString(36)}`)));
const NO_OCR = process.argv.includes('--no-ocr');
const JSON_OUT = arg('--json', null);
mkdirSync(OUT, { recursive: true });

// ── deterministic randomness: the run is reproducible from its seed ───────────────────────────────────────
let seed = Number(arg('--seed', 20261103));
const rnd = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const chance = (p) => rnd() < p;
const digits = (n) => Array.from({ length: n }, () => Math.floor(rnd() * 10)).join('');
const AR_DIG = '٠١٢٣٤٥٦٧٨٩';
const toAr = (s) => s.replace(/\d/g, (d) => AR_DIG[d]);

// ── identities ───────────────────────────────────────────────────────────────────────────────────────────
const CORE = [['Falcon', 'الصقر', 'Al Saqr'], ['Oasis', 'الواحة', 'Al Waha'], ['Pearl', 'اللؤلؤة', 'Al Lulua'], ['Dune', 'الكثيب', 'Al Katheeb'],
  ['Marina', 'المرسى', 'Al Marsa'], ['Crescent', 'الهلال', 'Al Hilal'], ['Palm', 'النخلة', 'Al Nakhla'], ['Horizon', 'الأفق', 'Al Ufuq']];
const ADJ = [['Blue', 'الأزرق', 'Al Azraq'], ['Golden', 'الذهبي', 'Al Thahabi'], ['Silver', 'الفضي', 'Al Fiddi'], ['Royal', 'الملكي', 'Al Malaki'], ['Green', 'الأخضر', 'Al Akhdar']];
const KIND = [['Contracting', 'للمقاولات'], ['Technical Services', 'للخدمات الفنية'], ['Engineering Consultants', 'للاستشارات الهندسية'], ['Interiors', 'للديكور'], ['Trading', 'للتجارة']];
const SUFFIX = ['LLC', 'L.L.C.', 'FZE', 'FZ-LLC', 'Est.'];
const FIRST = [['Rashid', 'راشد'], ['Omar', 'عمر'], ['Hamdan', 'حمدان'], ['Saeed', 'سعيد'], ['Yousef', 'يوسف'], ['Faisal', 'فيصل'], ['Majid', 'ماجد'], ['Tariq', 'طارق']];
const LAST = [['Qasimi', 'القاسمي'], ['Nuaimi', 'النعيمي'], ['Shamsi', 'الشامسي'], ['Ketbi', 'الكتبي'], ['Dhaheri', 'الظاهري'], ['Mazrouei', 'المزروعي'], ['Suwaidi', 'السويدي']];
let fixtureNo = 11;
const fixtureNN = () => { fixtureNo = fixtureNo >= 99 ? 11 : fixtureNo + 1; return String(fixtureNo); };

/** A planted token: how it was printed, and the keys a grader looks for (compact letters or a digit run). */
const T = (cls, printed, { words = [], digitsKey = null } = {}) => ({ cls, printed, words, digitsKey });
const compact = (s) => norm(s).replace(/[^\p{L}\p{N}]/gu, '');
function norm(s) {
  return String(s ?? '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase()
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6f0))
    .replace(/[ـ‌-‏]/g, '').replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
}
function phoneFormats(nn) {
  const M = `50 000 00${nn}`; const L = `4 000 00${nn}`;
  const mob = [`+971 ${M}`, `+971-50-000-00${nn}`, `00971 ${M}`, `0097150000 00${nn}`, `9715000000${nn}`, `0${M}`, `050-000-00${nn}`, `05000000${nn}`, `(050) 000 00${nn}`,
    `+971 (0)${M}`, `050.000.00${nn}`, `+971.50.000.00${nn}`, toAr(`0${M}`), `+${toAr('971 ' + M)}`, `wa.me/9715000000${nn}`, `Mob: 05 0000 00${nn}`];
  const land = [`+971 ${L}`, `04 000 00${nn}`, `(04) 000 00${nn}`, `04-00000${nn}`, `+971-4-00000${nn}`, toAr(`04 000 00${nn}`), `00971 4 000 00${nn}`];
  return { mobile: { key: `5000000${nn}`, all: mob }, land: { key: `400000${nn}`, all: land } };
}
function supplierIdentity(n) {
  const [c, cAr, cTr] = pick(CORE), [a, aAr, aTr] = pick(ADJ), [k, kAr] = pick(KIND), suf = pick(SUFFIX);
  const code = String.fromCharCode(65 + Math.floor(rnd() * 26)) + String.fromCharCode(65 + Math.floor(rnd() * 26)) + (2 + Math.floor(rnd() * 8));
  const name = `ZZ ${c} ${a} ${code} ${k} ${suf}`;
  const slug = `zz${c}${a}${code}`.toLowerCase();
  const [f, fAr] = pick(FIRST), [l, lAr] = pick(LAST);
  const nn = fixtureNN(), ph = phoneFormats(nn);
  const trn = '100' + digits(12), lic = String(100000 + Math.floor(rnd() * 899999)), iban = `AE${digits(2)}0${digits(2)}000${digits(13)}`, pob = String(10000 + Math.floor(rnd() * 89999));
  const id = {
    n, name, slug, code, person: `ZZ ${f} ${l}`, personAr: `زد زد ${fAr} ${lAr}`,
    email: `${pick(['sales', 'info', 'quotes', f.toLowerCase()])}@${slug}.example.invalid`, web: `www.${slug}.example.invalid`, nn, phones: ph,
    supplier: { company_name: name, email: '', phone: `+9715000000${nn}`, whatsapp: `+9715000000${nn}`, website: `www.${slug}.example.invalid` },
  };
  id.supplier.email = id.email;
  id.tokens = [
    T('company_en', name, { words: [`${c} ${a} ${code}`] }),
    T('company_ar', `شركة ${cAr} ${aAr} ${kAr} ذ.م.م`, { words: [`${cAr} ${aAr}`] }),
    T('company_translit', `${cTr} ${aTr} ${k}`, { words: [`${cTr} ${aTr}`] }),
    T('person_en', id.person, { words: [`${f} ${l}`] }), T('person_ar', id.personAr, { words: [`${fAr} ${lAr}`] }),
    T('email', id.email, { words: [id.email.split('@')[0] + slug] }), T('website', id.web, { words: [slug] }),
    T('phone_mobile', pick(ph.mobile.all), { digitsKey: ph.mobile.key }), T('phone_land', pick(ph.land.all), { digitsKey: ph.land.key }),
    T('trn', pick([`TRN: ${trn}`, `TRN ${trn.replace(/^(\d{3})(\d{4})(\d{4})(\d{4})$/, '$1 $2 $3 $4')}`, `VAT Reg. No. ${trn.replace(/^(\d{3})(\d{4})(\d{4})(\d{4})$/, '$1-$2-$3-$4')}`, `الرقم الضريبي: ${toAr(trn)}`, `Tax Registration Number ${trn}`, trn]), { digitsKey: trn }),
    // A licence printed the way a UAE letterhead prints it: the DED "CN-" number has SEVEN digits, and the TL abbreviation
    // carries its number marker or a licence word. A bare "TL 273158" or a six-digit "CN-123456" is a product code as often
    // as a licence (review of #1838), so the corpus does not plant them and the shared list keeps them.
    T('licence', pick([`Trade Licence No. ${lic}`, `License No: ${lic}`, `CN-${lic}${digits(1)}`, `T.L. No. ${lic}`, `Trade licence TL ${lic}`, `رقم الرخصة: ${toAr(lic)}`, `D.E.D. Licence ${lic}`]), { digitsKey: lic }),
    T('iban', pick([`IBAN: ${iban}`, `IBAN ${iban.replace(/(.{4})/g, '$1 ').trim()}`, `Account IBAN ${iban}`]), { digitsKey: iban.slice(2) }),
    T('po_box', pick([`P.O. Box ${pob}, Dubai`, `PO BOX: ${pob}`, `POB ${pob}`, `ص.ب ${toAr(pob)}`, `P. O. Box ${pob}`]), { digitsKey: pob }),
    T('address', `Office ${100 + Math.floor(rnd() * 900)}, ZZ ${c} ${code} Tower, Al Quoz Industrial Area ${1 + Math.floor(rnd() * 4)}, Dubai`, { words: [`${c} ${code} Tower`] }),
  ];
  return id;
}
function customerIdentity() {
  const [f] = pick(FIRST), [l, lAr] = pick(LAST), [c] = pick(CORE), nn = fixtureNN();
  const name = `ZZ DEMO ${f} ${l}`, project = `ZZ ${c} Heights Villa ${2 + Math.floor(rnd() * 40)}`;
  return { name, nameAr: `${pick(FIRST)[1]} ${lAr}`, email: `qd-leak-${f.toLowerCase()}${nn}@example.invalid`, phone: `+9715000000${nn}`, nn, project,
    tokens: [T('customer_name', pick([name, `Mr. ${f} ${l}`, `${f.toUpperCase()} ${l.toUpperCase()}`]), { words: [`${f} ${l}`] }), T('customer_email', `qd-leak-${f.toLowerCase()}${nn}@example.invalid`, { words: [`qdleak${f.toLowerCase()}${nn}`] }),
      T('customer_phone', pick(phoneFormats(nn).mobile.all), { digitsKey: phoneFormats(nn).mobile.key }), T('project', project, { words: [`${c} Heights`] })] };
}

// ── PDF writer (drawings and quotations) ─────────────────────────────────────────────────────────────────
const esc = (s) => s.replace(/([()\\])/g, '\\$1');
const hasAr = (s) => /[؀-ۿ]/.test(s);
// Arabic runs are written in a Type0 / Identity-H font whose CIDs ARE the Unicode code points, with a ToUnicode
// bfrange back to them: the text layer reads exactly what was planted (pdf.js draws no glyphs for it, so it is
// planted as an image too where pixels matter).
const hex = (s) => [...s].map((ch) => ch.codePointAt(0).toString(16).padStart(4, '0')).join('');
function txt(x, y, size, s) { return hasAr(s) ? `BT /F2 ${size} Tf 1 0 0 1 ${x.toFixed(1)} ${y.toFixed(1)} Tm <${hex(s)}> Tj ET\n` : `BT /F1 ${size} Tf 1 0 0 1 ${x.toFixed(1)} ${y.toFixed(1)} Tm (${esc(s)}) Tj ET\n`; }
function pdfFile({ pages, info, xmp }) {
  const objs = []; const add = (o) => { objs.push(o); return objs.length; };
  const stream = (dict, body, raw = false) => { const b = Buffer.isBuffer(body) ? body : Buffer.from(body, 'latin1'); const z = raw ? b : zlib.deflateSync(b); return { dict: `<< ${dict}${raw ? '' : ' /Filter /FlateDecode'} /Length ${z.length} >>`, z }; };
  add(null); add(null); // 1 catalog, 2 pages
  const f1 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  const cmap = add(stream('', '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /QDU def 1 begincodespacerange <0000> <FFFF> endcodespacerange 1 beginbfrange <0000> <FFFF> <0000> endbfrange endcmap CMapName currentdict /CMap defineresource pop end end'));
  const cid = add('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ArialMT /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 >>');
  const f2 = add(`<< /Type /Font /Subtype /Type0 /BaseFont /ArialMT /Encoding /Identity-H /DescendantFonts [${cid} 0 R] /ToUnicode ${cmap} 0 R >>`);
  const kids = [];
  for (const pg of pages) {
    const xo = [];
    (pg.images || []).forEach((im, i) => { const o = add(stream(`/Type /XObject /Subtype /Image /Width ${im.w} /Height ${im.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode`, im.jpg, true)); xo.push(`/Im${i} ${o} 0 R`); });
    let content = pg.content;
    if (pg.form) { const fo = add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${pg.W} ${pg.H}] /Resources << /Font << /F1 ${f1} 0 R /F2 ${f2} 0 R >> >>`, pg.form)); xo.push(`/Fm0 ${fo} 0 R`); content += 'q /Fm0 Do Q\n'; }
    (pg.images || []).forEach((im, i) => { content += `q ${im.pw.toFixed(1)} 0 0 ${im.ph.toFixed(1)} ${im.px.toFixed(1)} ${im.py.toFixed(1)} cm /Im${i} Do Q\n`; });
    const c = add(stream('', content));
    const annots = (pg.annots || []).map((a) => add(a.uri ? `<< /Type /Annot /Subtype /Link /Rect [${a.rect.join(' ')}] /Border [0 0 0] /A << /S /URI /URI (${esc(a.uri)}) >> >>` : `<< /Type /Annot /Subtype /Text /Rect [${a.rect.join(' ')}] /Contents (${esc(a.text)}) /T (${esc(a.author || '')}) >>`));
    kids.push(add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pg.W} ${pg.H}]${pg.rotate ? ` /Rotate ${pg.rotate}` : ''} /Resources << /Font << /F1 ${f1} 0 R /F2 ${f2} 0 R >> /XObject << ${xo.join(' ')} >> >> /Contents ${c} 0 R${annots.length ? ` /Annots [${annots.map((a) => `${a} 0 R`).join(' ')}]` : ''} >>`));
  }
  const meta = xmp ? add(stream('/Type /Metadata /Subtype /XML', xmp, true)) : null;
  objs[0] = `<< /Type /Catalog /Pages 2 0 R${meta ? ` /Metadata ${meta} 0 R` : ''} >>`;
  objs[1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${kids.length} >>`;
  const infoObj = info ? add(`<< ${Object.entries(info).map(([k, v]) => `/${k} ${hasAr(v) ? `<FEFF${hex(v)}>` : `(${esc(v)})`}`).join(' ')} >>`) : null;
  const parts = [Buffer.from('%PDF-1.6\n%\xe2\xe3\xcf\xd3\n', 'latin1')]; const offs = []; let len = parts[0].length;
  objs.forEach((o, i) => {
    const chunk = [Buffer.from(`${i + 1} 0 obj\n`, 'latin1')];
    if (typeof o === 'string') chunk.push(Buffer.from(o + '\n', 'latin1'));
    else chunk.push(Buffer.from(o.dict + '\nstream\n', 'latin1'), o.z, Buffer.from('\nendstream\n', 'latin1'));
    chunk.push(Buffer.from('endobj\n', 'latin1'));
    offs.push(len); for (const c of chunk) { parts.push(c); len += c.length; }
  });
  const xref = `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')}`;
  parts.push(Buffer.from(xref + `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R${infoObj ? ` /Info ${infoObj} 0 R` : ''} >>\nstartxref\n${len}\n%%EOF\n`, 'latin1'));
  return Buffer.concat(parts);
}
const xmpOf = (creator, tool, title) => `<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/"><dc:creator><rdf:Seq><rdf:li>${creator}</rdf:li></rdf:Seq></dc:creator><dc:title><rdf:Alt><rdf:li xml:lang="x-default">${title}</rdf:li></rdf:Alt></dc:title><xmp:CreatorTool>${tool}</xmp:CreatorTool></rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>`;

// ── raster assets with the name drawn in them (sharp renders SVG text, Arabic shaped) ─────────────────────
let sharp;
async function asset(kind, lines, w, h) {
  const fg = kind === 'stamp' ? '#1a3fb0' : kind === 'signature' ? '#102060' : '#7a1020';
  let body = '';
  if (kind === 'qr') { for (let i = 0; i < 21; i++) for (let j = 0; j < 21; j++) if (rnd() < 0.5 || (i < 7 && j < 7) || (i < 7 && j > 13) || (i > 13 && j < 7)) body += `<rect x="${10 + j * ((w - 20) / 21)}" y="${10 + i * ((h - 40) / 21)}" width="${(w - 20) / 21}" height="${(h - 40) / 21}" fill="#000"/>`; body += `<text x="${w / 2}" y="${h - 8}" font-family="Arial" font-size="14" text-anchor="middle" fill="#000">${lines[0]}</text>`; }
  else if (kind === 'stamp') body = `<circle cx="${w / 2}" cy="${h / 2}" r="${Math.min(w, h) / 2 - 6}" fill="none" stroke="${fg}" stroke-width="5"/>` + lines.map((l, i) => `<text x="${w / 2}" y="${h / 2 - 10 + i * 26}" font-family="Arial" font-size="20" font-weight="bold" text-anchor="middle" fill="${fg}">${l}</text>`).join('');
  else body = lines.map((l, i) => `<text x="${w / 2}" y="${40 + i * 42}" font-family="${kind === 'signature' ? 'Segoe Script, Arial' : 'Arial'}" font-size="${kind === 'signature' ? 30 : 32}" font-weight="bold" text-anchor="middle" fill="${fg}">${l}</text>`).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="100%" height="100%" fill="#fff8e8"/>${body}</svg>`;
  const jpg = await sharp(Buffer.from(svg)).flatten({ background: '#ffffff' }).jpeg({ quality: 90 }).toBuffer();
  return { jpg, w, h };
}

// ── drawings ─────────────────────────────────────────────────────────────────────────────────────────────
async function drawingPdf(sup, cust, v) {
  const W = 1684, H = 1191; // A2 landscape
  const right = v.tb === 'right';
  const strip = right ? { x: 0.82, y: 0, w: 0.18, h: 1 } : { x: 0, y: 0.84, w: 1, h: 0.16 };
  const P = (a, b) => [a * W, (1 - b) * H];
  const t = (a, b, size, s) => { const [x, y] = P(a, b); return txt(x, y, size, s); };
  const L = (a1, b1, a2, b2) => { const [x1, y1] = P(a1, b1), [x2, y2] = P(a2, b2); return `${x1.toFixed(1)} ${y1.toFixed(1)} m ${x2.toFixed(1)} ${y2.toFixed(1)} l S\n`; };
  let plan = '0.6 w ' + L(0.02, 0.02, 0.98, 0.02) + L(0.98, 0.02, 0.98, 0.98) + L(0.98, 0.98, 0.02, 0.98) + L(0.02, 0.98, 0.02, 0.02);
  plan += right ? L(strip.x, 0.02, strip.x, 0.98) : L(0.02, strip.y, 0.98, strip.y);
  // The drawing: walls, rooms, FCU tags (the BOQ), and general notes.
  const bodyW = right ? 0.78 : 0.94, bodyH = right ? 0.94 : 0.80;
  for (let i = 0; i < 6; i++) plan += L(0.05, 0.08 + i * bodyH / 7, 0.05 + bodyW * 0.8, 0.08 + i * bodyH / 7);
  plan += t(0.10, 0.15, 12, 'GROUND FLOOR PLAN - HVAC') + t(0.10, 0.18, 9, 'SCALE 1:100');
  const rooms = ['LIVING ROOM', 'MAJLIS', 'KITCHEN', 'BEDROOM 1', 'BEDROOM 2', 'MAID ROOM'];
  rooms.forEach((r, i) => { plan += t(0.08 + (i % 3) * 0.22, 0.30 + Math.floor(i / 3) * 0.2, 10, r) + t(0.08 + (i % 3) * 0.22, 0.33 + Math.floor(i / 3) * 0.2, 9, `FCU-${i + 1}`); });
  plan += t(0.06, 0.70, 10, 'GENERAL NOTES:') + t(0.06, 0.72, 9, '1. ALL DUCTWORK TO BE GI SHEET AS PER SMACNA.') + t(0.06, 0.74, 9, '2. FCU SCHEDULE: 6 NOS 2 TR DUCTED SPLIT UNITS.');
  // Planted in the body, outside any title block.
  const pt = (tk) => tk; const used = [];
  const at = (cls) => sup.tokens.find((x) => x.cls === cls) || cust.tokens.find((x) => x.cls === cls);
  const put = (tok, a, b, size) => { used.push(tok); plan += t(a, b, size, tok.printed); };
  if (v.bodyContact) { const ph = at('phone_mobile'); used.push(ph, at('person_en')); plan += t(0.06, 0.77, 11, `3. FOR CLARIFICATION CONTACT ENG. ${sup.person.toUpperCase()} ON ${ph.printed}`); }
  if (v.bodyCustomer) { const cn = at('customer_name'); used.push(cn); plan += t(0.30, 0.12, 12, `${cn.printed.toUpperCase()} RESIDENCE`); }
  if (v.header) { put(at('company_en'), 0.05, 0.045, 14); put(at('phone_land'), 0.45, 0.045, 11); put(at('website'), 0.62, 0.045, 11); }
  if (v.footer) { put(at('email'), 0.05, right ? 0.965 : 0.82, 10); put(at('po_box'), 0.30, right ? 0.965 : 0.82, 10); }
  // The title block: in the content stream or in a Form XObject.
  let tbText = '';
  const tb = (a, b, size, tok) => { used.push(tok); const [x, y] = P(a, b); tbText += txt(x, y, size, (tok.label ? tok.label + ' ' : '') + tok.printed); };
  // A title block prints the address on two lines; one 60-character run at 9 pt would run off an 18% strip.
  const addr = at('address'), cut = addr.printed.indexOf(', Al Quoz');
  const rows = [at('company_en'), { ...addr, printed: addr.printed.slice(0, cut + 1) }, T('address_2', addr.printed.slice(cut + 2), { words: [] }), at('phone_mobile'), at('email'), at('website'), at('licence'), { ...at('project'), label: 'PROJECT:' }, { ...at('customer_name'), label: 'CLIENT:' },
    { ...at('person_en'), label: 'DRAWN BY:' }, at('po_box')];
  if (v.arabic) rows.push(at('company_ar'), at('person_ar'));
  if (v.plotMakani) { const mk = digits(10), pl = digits(3) + '-' + digits(4); rows.push(T('makani', `Makani ${mk.slice(0, 5)} ${mk.slice(5)}`, { digitsKey: mk }), T('plot', `Plot No. ${pl}`, { digitsKey: pl.replace('-', '') })); }
  rows.forEach((tok, i) => right ? tb(strip.x + 0.008, 0.06 + i * 0.045, 9, tok) : tb(0.03 + Math.floor(i / 4) * 0.24, strip.y + 0.03 + (i % 4) * 0.03, 9, tok));
  tbText += right ? t(strip.x + 0.008, 0.93, 9, 'DWG NO: M-101   REV: 02   SCALE 1:100') : t(0.62, 0.975, 9, 'DWG NO: M-101 REV 02');
  const page = { W, H, content: plan, images: [], annots: [], rotate: 0 };
  if (v.form) page.form = tbText; else page.content += tbText;
  // Images: a logo in the title block, a QR code, a stamp and a signature near the notes, a logo in the header.
  const img = async (kind, lines, a, b, wN, hN) => {
    const pw = wN * W, ph = hN * H; const im = await asset(kind, lines, Math.round(pw * 1.5), Math.round(ph * 1.5));
    const [px, pyTop] = P(a, b); page.images.push({ ...im, pw, ph, px, py: pyTop - ph });
    return { kind, box: { x: a, y: b, w: wN, h: hN }, words: lines };
  };
  const planted = [];
  if (v.logo) planted.push(await img('logo', [`ZZ ${sup.name.split(' ')[1]}`, sup.code], right ? strip.x + 0.01 : 0.88, right ? 0.55 : strip.y + 0.02, right ? 0.15 : 0.12, right ? 0.08 : 0.10));
  if (v.qr) planted.push(await img('qr', [sup.slug.slice(0, 14)], right ? strip.x + 0.04 : 0.80, right ? 0.66 : strip.y + 0.02, right ? 0.09 : 0.06, right ? 0.12 : 0.11));
  if (v.stamp) planted.push(await img('stamp', [sup.name.split(' ')[1].toUpperCase(), sup.code, 'APPROVED'], 0.62, 0.62, 0.09, 0.13));
  if (v.signature) planted.push(await img('signature', [sup.person.replace('ZZ ', '')], 0.45, 0.80, 0.12, 0.05));
  if (v.headerLogo) planted.push(await img('logo', [`ZZ ${sup.name.split(' ')[1]}`, sup.code], 0.80, 0.03, 0.10, 0.06));
  if (v.annots) { page.annots.push({ uri: 'https://' + sup.web, rect: [W * 0.85, H * 0.5, W * 0.95, H * 0.52] }, { text: `Checked by ${sup.person}, call ${sup.phones.mobile.all[0]}`, author: sup.person, rect: [W * 0.5, H * 0.5, W * 0.52, H * 0.52] }); used.push(at('website'), at('person_en')); }
  if (v.rotate && !planted.length) page.rotate = 90;
  const pages = [page];
  if (v.twoPages) pages.push({ ...page, content: plan.replace('GROUND FLOOR PLAN', 'FIRST FLOOR PLAN') + (v.form ? '' : tbText), images: [], annots: [] });
  const info = { Title: `${cust.tokens.find((x) => x.cls === 'project').printed} - HVAC`, Author: sup.person, Creator: `${sup.name} CAD`, Producer: 'ZZ PDF Writer', Subject: `For ${cust.name}`, Keywords: sup.web };
  const bytes = pdfFile({ pages, info, xmp: xmpOf(sup.person, sup.name, cust.tokens.find((x) => x.cls === 'project').printed) });
  used.push(at('person_en'), at('company_en'), at('website'), at('project'));
  return { bytes, used: [...new Set(used.filter(Boolean))], planted: planted.map((p) => ({ ...p, pages: v.twoPages ? [0] : [0] })) };
}
function scannedPdf(jpg, w, h, sup, cust) {
  const W = 1684, H = 1191;
  return pdfFile({ pages: [{ W, H, content: '', images: [{ jpg, w, h, pw: W, ph: H, px: 0, py: 0 }] }], info: { Author: sup.person, Creator: sup.name, Title: cust.tokens.find((x) => x.cls === 'project').printed }, xmp: xmpOf(sup.person, sup.name, cust.name) });
}
function dxfDrawing(sup, cust) {
  const p = [];
  const sec = (n, b) => p.push([0, 'SECTION'], [2, n], ...b, [0, 'ENDSEC']);
  const line = (layer, x1, y1, x2, y2) => [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
  const text = (layer, x, y, s) => [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, 180], [1, s]];
  const lay = `${sup.slug.toUpperCase()}-M-DUCT`;
  const get = (c) => sup.tokens.find((x) => x.cls === c) || cust.tokens.find((x) => x.cls === c);
  sec('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$INSUNITS'], [70, 4], [9, '$PROJECTNAME'], [1, get('project').printed], [9, '$LASTSAVEDBY'], [1, sup.person]]);
  sec('TABLES', [[0, 'TABLE'], [2, 'LAYER'], [70, 2], [0, 'LAYER'], [2, '0'], [70, 0], [62, 7], [6, 'CONTINUOUS'], [0, 'LAYER'], [2, lay], [70, 0], [62, 1], [6, 'CONTINUOUS'], [0, 'ENDTAB']]);
  sec('BLOCKS', [[0, 'BLOCK'], [8, '0'], [2, 'FCU'], [70, 0], [10, 0], [20, 0], [30, 0], ...line('0', 0, 0, 600, 0), [0, 'ENDBLK']]);
  const ents = [...line('WALLS', 0, 0, 12000, 0), ...line('WALLS', 12000, 0, 12000, 8000), ...line('WALLS', 12000, 8000, 0, 8000), ...line('WALLS', 0, 8000, 0, 0), ...line(lay, 1000, 4000, 9000, 4000)];
  for (let i = 0; i < 4; i++) ents.push([0, 'INSERT'], [8, 'HVAC'], [2, 'FCU'], [10, 1500 + i * 2500], [20, 6000], [30, 0]);
  ents.push(...text('ANNO', 2000, 7000, 'LIVING ROOM'), ...text('ANNO', 7000, 7000, 'MAJLIS'));
  const tbRows = ['company_en', 'phone_mobile', 'email', 'website', 'address', 'licence'].map((c) => get(c));
  tbRows.forEach((tk, i) => ents.push(...text('TITLE', 12500, 7500 - i * 300, tk.printed)));
  ents.push(...text('TITLE', 12500, 5400, 'CLIENT: ' + get('customer_name').printed), ...text('TITLE', 12500, 5100, 'DRAWN BY: ' + sup.person));
  ents.push(...text('ANNO', 2000, 1000, `NOTE: COORDINATE WITH ${sup.person.toUpperCase()} ${get('phone_land').printed}`));
  sec('ENTITIES', ents);
  p.push([0, 'EOF']);
  const used = [...tbRows, get('customer_name'), get('person_en'), get('phone_land'), get('project'), get('company_en')];
  return { bytes: Buffer.from(p.map(([c, v]) => `${String(c).padStart(3)}\n${v}\n`).join(''), 'utf8'), used };
}

// ── quotations ───────────────────────────────────────────────────────────────────────────────────────────
const LINES = [['Supply and install 2 TR ducted split unit', 6, 'nos', 4200], ['GI ductwork with insulation', 85, 'sqm', 180], ['Copper piping 1/2" + 7/8" insulated', 60, 'lm', 95],
  ['Thermostat, wiring and commissioning', 6, 'nos', 350], ['Condensate drain piping', 40, 'lm', 45], ['Supply air diffusers 600x600', 18, 'nos', 210]];
function quoteContent(sup) {
  const tk = (c) => sup.tokens.find((x) => x.cls === c);
  const lines = LINES.slice(0, 3 + Math.floor(rnd() * 4)).map(([d, q, u, r]) => ({ d, q, u, r, amt: q * r }));
  // A line's description sometimes names the supplier's own brand range ("ZZ Falcon Blue QX7 series").
  if (chance(0.3)) lines[0].d += ` - ${sup.name.split(' ').slice(1, 4).join(' ')} series`;
  const total = lines.reduce((s, l) => s + l.amt, 0);
  const header = [tk('company_en'), chance(0.6) ? tk('company_ar') : null, chance(0.4) ? tk('company_translit') : null, tk('address'), tk('po_box'), tk('phone_land'), tk('phone_mobile'), tk('email'), tk('website'), tk('trn'), tk('licence')].filter(Boolean);
  const sign = [`For and on behalf of ${sup.name}`, `Prepared by: ${sup.person}, Sales Engineer`, `Mobile ${tk('phone_mobile').printed}`, chance(0.5) ? tk('person_ar').printed : '', tk('iban').printed].filter(Boolean);
  const used = [...header, tk('person_en'), tk('iban'), ...(sign.some((s) => s === tk('person_ar').printed) ? [tk('person_ar')] : [])];
  return { lines, total, header, sign, used };
}
function quotePdf(sup, c) {
  const W = 595, H = 842; let y = 800, s = '';
  const put = (x, size, str) => { s += txt(x, y, size, str); y -= size + 6; };
  for (const h of c.header) put(40, 9, h.printed);
  y -= 10; put(40, 14, 'QUOTATION'); put(40, 9, `Ref: Q-${sup.code}-2291   Date: 03/11/2026`);
  put(40, 9, 'Description                                         Qty   Unit   Rate   Amount');
  for (const l of c.lines) put(40, 9, `${l.d}   ${l.q} ${l.u}   ${l.r.toFixed(2)}   ${l.amt.toFixed(2)}`);
  put(40, 9, `Total AED ${c.total.toFixed(2)}`); put(40, 9, 'Validity: 30 days. Payment: 50% advance, 50% on completion.');
  y -= 10; for (const g of c.sign) put(40, 9, g);
  return pdfFile({ pages: [{ W, H, content: s }], info: { Author: sup.person, Creator: sup.name, Title: `${sup.name} quotation`, Producer: 'ZZ Office' }, xmp: xmpOf(sup.person, sup.name, `${sup.name} quotation`) });
}
async function quoteXlsx(sup, c) {
  const XLSX = await import(pathToFileURL(path.join(ROOT, 'supabase/functions/_shared/vendor/sheetjs-0.20.3/xlsx.mjs')).href);
  const aoa = [...c.header.map((h) => [h.printed]), [], ['Description', 'Qty', 'Unit', 'Rate', 'Amount'], ...c.lines.map((l) => [l.d, l.q, l.u, l.r, l.amt]), ['Total', '', '', '', c.total], [], ...c.sign.map((g) => [g])];
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), 'Quotation');
  wb.Props = { Author: sup.person, Company: sup.name, Title: `${sup.name} quotation` };
  return Buffer.from(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
}
const quoteCsv = (c) => Buffer.from([...c.header.map((h) => `"${h.printed}"`), 'Description,Qty,Unit,Rate,Amount', ...c.lines.map((l) => `"${l.d}",${l.q},${l.u},${l.r},${l.amt}`), `Total,,,,${c.total}`, ...c.sign.map((g) => `"${g}"`)].join('\n'), 'utf8');
const quoteEml = (sup, c) => Buffer.from([`From: "${sup.person}" <${sup.email}>`, 'To: quotes@example.invalid', `Subject: Quotation from ${sup.name}`, 'MIME-Version: 1.0', 'Content-Type: text/plain; charset=utf-8', '',
  'Dear Sir,', 'Please find our offer below.', '', 'Description | Qty | Unit | Rate | Amount', ...c.lines.map((l) => `${l.d} | ${l.q} | ${l.u} | ${l.r} | ${l.amt}`), `Total AED ${c.total}`, '', 'Best regards,', ...c.sign, ...c.header.map((h) => h.printed)].join('\r\n'), 'utf8');
/** What the supplier types into the portal's quotation form: some of it carries their identity. */
function quoteForm(sup) {
  const tk = (c) => sup.tokens.find((x) => x.cls === c); const used = [];
  const say = (p, cls, f) => { if (!chance(p)) return ''; const t = tk(cls); used.push(t); return f(t.printed); };
  const form = {
    payment_terms: '50% advance, 50% on completion. ' + say(0.35, 'iban', (v) => `Transfer to ${v}.`) + say(0.25, 'company_en', (v) => ` Cheque in favour of ${v}.`),
    warranty: '2 years on compressors. ' + say(0.3, 'phone_mobile', (v) => `Service hotline ${v}.`),
    lead_time: '14 days from PO. ' + say(0.2, 'person_en', (v) => `Site visits arranged by ${v}.`),
    validity: '30 days',
    scope: 'Supply, installation, testing and commissioning. ' + say(0.3, 'address', (v) => `Showroom: ${v}.`) + say(0.25, 'company_ar', (v) => ` ${v}`) + say(0.2, 'website', (v) => ` Catalogue on ${v}`),
    notes: say(0.3, 'email', (v) => `Queries: ${v}. `) + say(0.25, 'person_ar', (v) => `المسؤول: ${v}. `) + say(0.25, 'phone_land', (v) => `للاستفسار: ${v}`) + say(0.2, 'trn', (v) => ` ${v}`),
    exclusions: 'Civil works and false ceiling. ' + say(0.2, 'licence', (v) => `${v}.`) + say(0.2, 'po_box', (v) => ` ${v}`),
    conditions: say(0.25, 'company_translit', (v) => `${v} standard conditions apply.`),
  };
  return { form, used };
}

// ── grading ──────────────────────────────────────────────────────────────────────────────────────────────
/** Digit runs (separators allowed between digits, never a comma: a phone has none, and joining a JSON array of floats
 * on commas "found" a P.O. Box in 0.12499999999999999,0.15624999999999997, 3 Nov 2026), each reduced to its digits. */
function digitRuns(s) { return (norm(s).match(/\d[\d\s.\-()\/+]*\d/g) || []).map((r) => r.replace(/\D/g, '')); }
function found(tok, text) {
  // Digits only as a run of their own (never the whole text squashed: "0.0520,0.5104" squashed held a P.O. Box). An
  // IBAN key keeps its letters out (the AE prefix is dropped when the key is made), so a run is enough there too.
  if (tok.digitsKey) { const key = tok.digitsKey.replace(/\D/g, ''); return digitRuns(text).some((r) => r.includes(key)); }
  const c = compact(text);
  return tok.words.some((w) => { const k = compact(w); if (k.length < 5) return false; if (c.includes(k)) return true; return false; });
}
/** OCR is noisy: a word key also counts when a window of the OCR text differs from it by at most one character. */
function foundFuzzy(tok, text) {
  if (found(tok, text)) return true;
  if (tok.digitsKey) { const key = tok.digitsKey.replace(/\D/g, ''); const ocrDigits = norm(text).replace(/[oO]/g, '0').replace(/[lI|]/g, '1'); return digitRuns(ocrDigits).some((r) => r.includes(key)); }
  const c = compact(text);
  return tok.words.some((w) => { const k = compact(w); if (k.length < 8) return false; for (let i = 0; i + k.length <= c.length; i++) { let d = 0; for (let j = 0; j < k.length && d <= 1; j++) if (c[i + j] !== k[j]) d++; if (d <= 1) return true; } return false; });
}
/** Every string a PDF carries: inflated streams, literal and hex strings, /Info, XMP. */
function pdfStrings(buf) {
  // The dictionaries (/Info, annotations) without the raw stream bodies or the xref table: a literal-string match
  // run across compressed bytes reached "/Size 15" and the offsets and "found" a P.O. Box there (3 Nov 2026).
  const s = buf.toString('latin1'); const chunks = [s.replace(/stream\r?\n[\s\S]*?endstream/g, 'stream endstream').replace(/\bxref\b[\s\S]*?trailer/g, 'trailer')];
  for (const m of s.matchAll(/stream\r?\n/g)) {
    const start = m.index + m[0].length, end = s.indexOf('endstream', start); if (end < 0) continue;
    const raw = buf.subarray(start, end);
    for (const f of [zlib.inflateSync, zlib.inflateRawSync]) { try { chunks.push(f(raw).toString('latin1')); break; } catch { /* not deflated */ } }
  }
  // The decoded strings and XML text only: the raw bytes carry xref offsets and object numbers, digit runs that
  // matched a planted P.O. Box by chance (3 Nov 2026). Words are still searched in the raw bytes (pdf_raw).
  const all = chunks.join('\n'); const out = [];
  for (const m of all.matchAll(/<x:xmpmeta[\s\S]*?<\/x:xmpmeta>/g)) out.push(m[0].replace(/<[^>]*>/g, ' '));
  for (const m of all.matchAll(/<([0-9A-Fa-f\s]{8,})>/g)) { const h = m[1].replace(/\s/g, ''); if (h.length % 4 === 0) { let t = ''; for (let i = h.startsWith('FEFF') || h.startsWith('feff') ? 4 : 0; i < h.length; i += 4) t += String.fromCodePoint(parseInt(h.slice(i, i + 4), 16)); out.push(t); } }
  for (const m of all.matchAll(/\(((?:\\.|[^\\)])*)\)/g)) out.push(m[1].replace(/\\(.)/g, '$1'));
  return out.join('\n');
}
/** Every byte of the file, streams inflated: searched for WORD tokens only (names, hosts), never for digit runs. */
function pdfRaw(buf) { const s = buf.toString('latin1'); const out = [s]; for (const m of s.matchAll(/stream\r?\n/g)) { const st = m.index + m[0].length, en = s.indexOf('endstream', st); if (en < 0) continue; try { out.push(zlib.inflateSync(buf.subarray(st, en)).toString('latin1')); } catch { /* */ } } return out.join('\n'); }
function pdftotext(file) { try { return execFileSync('pdftotext', ['-enc', 'UTF-8', file, '-'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); } catch { return ''; } }

// ── rasterise (pdf.js in Chromium, exactly as src/components/me/pdfRaster.ts does) ───────────────────────
async function rasteriser() {
  const { chromium } = await import('playwright');
  const PDFJS = path.join(ROOT, 'node_modules/pdfjs-dist/build');
  let cur = null;
  const srv = http.createServer((q, s) => {
    if (q.url.startsWith('/doc.pdf')) { s.setHeader('Content-Type', 'application/pdf'); return s.end(cur); }
    if (q.url === '/') { s.setHeader('Content-Type', 'text/html'); return s.end('<!doctype html><title>r</title>'); }
    try { s.setHeader('Content-Type', 'text/javascript'); s.end(readFileSync(path.join(PDFJS, q.url.replace('/pdfjs/', '')))); } catch { s.statusCode = 404; s.end(); }
  });
  await new Promise((ok) => srv.listen(0, '127.0.0.1', ok));
  // The bundled browser when it is installed, else the machine's Edge (the founder's browser on this laptop).
  const b = await chromium.launch().catch(() => chromium.launch({ channel: 'msedge' }));
  const origin = `http://127.0.0.1:${srv.address().port}/`;
  let n = 0;
  return {
    async pages(buf) {
      cur = buf; n++;
      // A fresh page per document: one tab rendering hundreds of 2600 px sheets crashed ("Target crashed", 3 Nov 2026).
      const once = async () => { const pg = await b.newPage(); try { await pg.goto(origin); return await pg.evaluate(async (u) => {
        const pdfjs = await import('/pdfjs/pdf.min.mjs'); pdfjs.GlobalWorkerOptions.workerSrc = '/pdfjs/pdf.worker.min.mjs';
        const pdf = await pdfjs.getDocument({ url: u }).promise; const out = [];
        for (let p = 1; p <= Math.min(pdf.numPages, 20); p++) {
          const page = await pdf.getPage(p); const v1 = page.getViewport({ scale: 1 });
          const vp = page.getViewport({ scale: Math.min(1.8, 2600 / Math.max(v1.width, v1.height)) });
          const c = document.createElement('canvas'); c.width = Math.round(vp.width); c.height = Math.round(vp.height);
          await page.render({ canvasContext: c.getContext('2d'), viewport: vp }).promise;
          out.push({ data: c.toDataURL('image/jpeg', 0.8).split(',')[1], w: c.width, h: c.height });
        }
        return out;
      }, `/doc.pdf?${n}`); } finally { await pg.close().catch(() => {}); } };
      let imgs; try { imgs = await once(); } catch { try { imgs = await once(); } catch (e) { console.warn('rasterise failed: ' + String(e?.message || e).slice(0, 80)); return []; } }
      return imgs.map((i) => ({ ...i, jpg: Buffer.from(i.data, 'base64') }));
    },
    async close() { await b.close(); srv.close(); },
  };
}

// ── OCR ──────────────────────────────────────────────────────────────────────────────────────────────────
async function ocrPool(size = 4) {
  const { createWorker } = await import('tesseract.js');
  const lang = path.join(ROOT, 'public/ocr/lang');
  const ws = await Promise.all(Array.from({ length: size }, async () => { const w = await createWorker(['eng', 'ara'], 1, { langPath: lang, gzip: true, cacheMethod: 'none' }); await w.setParameters({ tessedit_pageseg_mode: '11' }); return w; }));
  const free = [...ws]; const waiters = [];
  const take = () => (free.length ? Promise.resolve(free.pop()) : new Promise((ok) => waiters.push(ok)));
  const give = (w) => (waiters.length ? waiters.shift()(w) : free.push(w));
  return {
    async read(jpg) { const w = await take(); try { const { data } = await w.recognize(jpg); return data.text || ''; } finally { give(w); } },
    async close() { await Promise.all(ws.map((w) => w.terminate())); },
  };
}
/** A planted image is VISIBLE when its own cream ground (#fff8e8, drawn by asset()) still fills >= 15% of where it was
 * placed. A painted box is black and a cut image leaves the white sheet, so neither reads as the image (3 Nov 2026:
 * the first version called any non-black area visible and so counted every image the vector redaction had CUT). */
async function imageVisible(jpg, box) {
  const m = await sharp(jpg).metadata();
  const x = Math.max(0, Math.round((box.x + box.w * 0.1) * m.width)), y = Math.max(0, Math.round((box.y + box.h * 0.1) * m.height));
  const w = Math.max(1, Math.min(m.width - x, Math.round(box.w * 0.8 * m.width))), h = Math.max(1, Math.min(m.height - y, Math.round(box.h * 0.8 * m.height)));
  const { data, info } = await sharp(jpg).extract({ left: x, top: y, width: w, height: h }).raw().toBuffer({ resolveWithObject: true });
  let lit = 0; const px = info.width * info.height;
  for (let i = 0; i < data.length; i += info.channels) if (Math.abs(data[i] - 255) < 12 && Math.abs(data[i + 1] - 248) < 12 && Math.abs(data[i + 2] - 232) < 10) lit++;
  return lit / px >= 0.15;
}

// ── main ─────────────────────────────────────────────────────────────────────────────────────────────────
sharp = (await import('sharp')).default;
const ras = await rasteriser();
const man = { drawings: [], quotes: [], requests: [], qa: [] };
const meta = {}; // id -> { tokens, planted, original rasters }
const wf = (rel, buf) => { const p = path.join(OUT, rel); mkdirSync(path.dirname(p), { recursive: true }); writeFileSync(p, buf); return rel.replace(/\\/g, '/'); };
console.log(`corpus -> ${OUT}`);
const GRADE_ONLY = process.argv.includes('--grade-only');
if (GRADE_ONLY) { Object.assign(man, JSON.parse(readFileSync(path.join(OUT, 'manifest.json'), 'utf8'))); Object.assign(meta, JSON.parse(readFileSync(path.join(OUT, 'meta.json'), 'utf8'))); }
else for (let rep = 0; rep < REPEATS; rep++) {
  for (let i = 0; i < 60; i++) {
    const id = `d${rep}_${String(i).padStart(2, '0')}`;
    const sup = supplierIdentity(i), cust = customerIdentity();
    const kind = i < 36 ? 'pdf' : i < 48 ? 'scan' : 'dxf';
    const filename = pick([`${cust.project} - HVAC.pdf`, `M-101 Mechanical Rev2.pdf`, `${sup.name} - ${cust.name} villa.pdf`, `drawing.pdf`]).replace(/\.pdf$/, kind === 'dxf' ? '.dxf' : '.pdf');
    const ftoks = [...sup.tokens, ...cust.tokens].filter((t) => found(t, filename));
    if (kind === 'dxf') {
      const d = dxfDrawing(sup, cust);
      man.drawings.push({ id, kind, file: wf(`in/${id}.dxf`, d.bytes), filename, rasters: [], customer: { name: cust.name, email: cust.email, phone: cust.phone, project: cust.project } });
      meta[id] = { tokens: [...new Set([...d.used, ...ftoks])], planted: [], originals: [] };
      continue;
    }
    const v = { tb: pick(['right', 'bottom']), header: chance(0.5), footer: chance(0.5), bodyContact: chance(0.5), bodyCustomer: chance(0.4), arabic: chance(0.5), plotMakani: chance(0.5), form: chance(0.4),
      logo: chance(0.8), qr: chance(0.4), stamp: chance(0.4), signature: chance(0.4), headerLogo: chance(0.3), annots: chance(0.5), rotate: chance(0.2), twoPages: chance(0.25) };
    const d = await drawingPdf(sup, cust, v);
    let bytes = d.bytes, planted = d.planted;
    let rasters = await ras.pages(bytes);
    if (kind === 'scan') { bytes = scannedPdf(rasters[0].jpg, rasters[0].w, rasters[0].h, sup, cust); rasters = await ras.pages(bytes); }
    const file = wf(`in/${id}.pdf`, bytes);
    const rp = rasters.map((r, k) => wf(`in/${id}.p${k}.jpg`, r.jpg));
    man.drawings.push({ id, kind, file, filename, rasters: rp, customer: { name: cust.name, email: cust.email, phone: cust.phone, project: cust.project }, variant: v });
    meta[id] = { tokens: [...new Set([...d.used, ...ftoks])], planted, originals: rp };
  }
  for (let r = 0; r < 20; r++) man.requests.push({ id: `00000000-0000-4000-8000-${String(rep * 100 + r).padStart(12, '0')}`, rfq_no: 9000 + rep * 100 + r });
  for (let i = 0; i < 100; i++) {
    const id = `q${rep}_${String(i).padStart(2, '0')}`;
    const sup = supplierIdentity(i); const c = quoteContent(sup); const f = quoteForm(sup);
    const fmt = pick(['pdf', 'pdf', 'xlsx', 'csv', 'eml']);
    const filename = `${pick([sup.name, 'Quotation', `Q-${sup.code}`])} quotation.${fmt}`;
    const buf = fmt === 'pdf' ? quotePdf(sup, c) : fmt === 'xlsx' ? await quoteXlsx(sup, c) : fmt === 'csv' ? quoteCsv(c) : quoteEml(sup, c);
    const mime = { pdf: 'application/pdf', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', csv: 'text/csv', eml: 'message/rfc822' }[fmt];
    man.quotes.push({ id, request: rep * 20 + Math.floor(i / 5), file: wf(`in/${id}.${fmt}`, buf), filename, mime, supplier: sup.supplier, form: f.form, fmt });
    meta[id] = { tokens: [...new Set([...c.used, ...f.used, ...sup.tokens.filter((t) => found(t, filename))])] };
  }
  for (let i = 0; i < 20; i++) {
    const sup = supplierIdentity(i), cust = customerIdentity(), tk = (c) => sup.tokens.find((x) => x.cls === c), ck = (c) => cust.tokens.find((x) => x.cls === c);
    const ask = [`Is the majlis ceiling 3.2 m? ${pick([`Call me on ${tk('phone_mobile').printed}`, `WhatsApp ${tk('phone_mobile').printed}`, `email ${tk('email').printed.replace('@', pick(['@', ' (at) ', ' [at] ']))}`, `see ${tk('website').printed}`])}`, `${pick(['Regards', 'Thanks'])}, ${tk('person_en').printed} - ${tk('company_en').printed}`];
    const askAr = `هل السقف ٣٫٢ م؟ اتصل على ${toAr('0' + sup.phones.mobile.all[0].replace(/^\+971 /, ''))} - ${tk('company_ar').printed}`;
    const ans = `Yes 3.2 m. Site is ${ck('project').printed}. ${pick([`Call ${ck('customer_phone').printed}`, `Mail ${ck('customer_email').printed}`])} - ${ck('customer_name').printed}`;
    for (const [k, text, toks, name, whole = []] of [['a', ask.join(' '), [tk('phone_mobile'), tk('email'), tk('website'), tk('person_en'), tk('company_en')], [sup.name]], ['r', askAr, [tk('phone_mobile'), tk('company_ar')], [sup.name]], ['c', ans, [ck('project'), ck('customer_phone'), ck('customer_email'), ck('customer_name')], [cust.name], [cust.project]]]) {
      // names / whole = what messages_api passes: the supplier's company; the customer's full name, and the project name
      // as a WHOLE name only (review of #1838: its ordinary words are the answer).
      const id = `m${rep}_${i}${k}`; man.qa.push({ id, text, names: name, whole }); meta[id] = { tokens: toks.filter((t) => found(t, text)) };
    }
  }
}
writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(man)); writeFileSync(path.join(OUT, 'meta.json'), JSON.stringify(meta));
console.log(`corpus: ${man.drawings.length} drawings, ${man.quotes.length} quotations, ${man.qa.length} Q&A messages`);

// ── the real modules ─────────────────────────────────────────────────────────────────────────────────────
const run = process.argv.includes('--grade-only') && !process.argv.includes('--rerun-pipeline') ? { status: 0 } : spawnSync('deno', ['run', '-A', '--no-lock', path.join(ROOT, 'scripts/e2e/identity_leak_pipeline.ts'), OUT], { stdio: 'inherit', cwd: ROOT });
if (run.status !== 0) { await ras.close(); throw new Error('pipeline failed'); }
const pipe = JSON.parse(readFileSync(path.join(OUT, 'pipeline.json'), 'utf8'));

// ── grade ────────────────────────────────────────────────────────────────────────────────────────────────
const ocr = NO_OCR ? null : await ocrPool(Number(arg('--ocr-workers', 4)));
const leaks = []; const rows = [];
const control = { tokens: 0, read: 0, images: 0, images_seen: 0 };
async function gradeSurfaces(id, family, surfaces, held, extraTokens = []) {
  const m = meta[id] || { tokens: [] }; const toks = [...m.tokens, ...extraTokens];
  const hits = [];
  for (const s of surfaces) {
    const file = path.join(OUT, s.path); const buf = readFileSync(file);
    const texts = [];
    if (s.name) texts.push(['file_name', s.name]);
    if (s.kind === 'json' || s.kind === 'text_file') texts.push(['text', buf.toString('utf8')]);
    let rasters = [];
    if (s.kind === 'pdf') { texts.push(['pdf_strings', pdfStrings(buf)], ['pdftotext', pdftotext(file)], ['pdf_raw', pdfRaw(buf)]); if (family === 'drawing') rasters = (await ras.pages(buf)).map((r) => r.jpg); }
    if (s.kind === 'image') rasters = [buf];
    for (const [src, t] of texts) for (const tok of toks) if ((src !== 'pdf_raw' || !tok.digitsKey) && found(tok, t)) hits.push({ surface: s.path, source: src, cls: tok.cls, printed: tok.printed });
    for (const [ri, jpg] of rasters.entries()) {
      if (ocr) { const t = await ocr.read(jpg); for (const tok of toks) if (foundFuzzy(tok, t)) hits.push({ surface: s.path, source: 'ocr' + (rasters.length > 1 ? ` p${ri}` : ''), cls: tok.cls, printed: tok.printed }); }
      const page = s.page ?? ri;
      for (const im of m.planted || []) if ((im.pages || [0]).includes(page) && await imageVisible(jpg, im.box)) hits.push({ surface: s.path, source: 'pixels', cls: 'image_' + im.kind, printed: im.words.join(' ') });
    }
  }
  const uniq = [...new Map(hits.map((h) => [`${h.cls}|${h.surface}|${h.source}`, h])).values()];
  rows.push({ id, family, surfaces: surfaces.length, held: held || [], leaked: uniq.length > 0, hits: uniq });
  if (uniq.length) leaks.push({ id, family, hits: uniq });
}
for (const d of pipe.drawings) {
  await gradeSurfaces(d.id, 'drawing', d.surfaces, [...d.held, ...(d.error ? ['error:' + d.error] : [])]);
  // The pixel check must SEE each planted image on the original page, or a clean output proves nothing.
  if (meta[d.id].originals?.length) for (const im of meta[d.id].planted || []) { control.images++; if (await imageVisible(readFileSync(path.join(OUT, meta[d.id].originals[0])), im.box)) control.images_seen++; }
  // OCR control on the original pages of PDF drawings that produced a preview.
  if (ocr && d.surfaces.some((s) => s.kind === 'image') && meta[d.id].originals.length) {
    const t = await ocr.read(readFileSync(path.join(OUT, meta[d.id].originals[0])));
    for (const tok of meta[d.id].tokens.filter((x) => !hasAr(x.printed))) { control.tokens++; if (foundFuzzy(tok, t)) control.read++; }
  }
}
for (const q of pipe.quotes) await gradeSurfaces(q.id, 'quotation', q.surfaces, [...q.held, ...(q.error ? ['error:' + q.error] : [])]);
for (const r of pipe.requests) { const toks = r.quotes.flatMap((id) => meta[id].tokens); await gradeSurfaces(r.id, 'comparison', r.surfaces, r.error ? ['error:' + r.error] : [], toks); }
for (const m of pipe.qa) await gradeSurfaces(m.id, 'qa', m.surfaces, m.held);
if (ocr) await ocr.close();
await ras.close();

// ── report ───────────────────────────────────────────────────────────────────────────────────────────────
const fam = (f) => rows.filter((r) => r.family === f);
const table = ['drawing', 'quotation', 'comparison', 'qa'].map((f) => {
  const rs = fam(f); const shared = rs.filter((r) => r.surfaces > 0);
  return { family: f, trials: rs.length, shared: shared.length, held_entirely: rs.length - shared.length, leaked: rs.filter((r) => r.leaked).length };
});
const byClass = {}; for (const l of leaks) for (const h of l.hits) { const k = `${l.family}:${h.cls}`; byClass[k] = (byClass[k] || 0) + 1; }
const bySurface = {}; for (const l of leaks) for (const h of l.hits) { const k = `${l.family}:${h.surface.split('/').pop()}:${h.source}`; bySurface[k] = (bySurface[k] || 0) + 1; }
const heldWhy = {}; for (const r of rows) for (const h of r.held) { const k = `${r.family}:${String(h).replace(/:.*$/, '')}`; heldWhy[k] = (heldWhy[k] || 0) + 1; }
const trials = rows.filter((r) => r.family === 'drawing' || r.family === 'quotation').length;
const summary = { measured_at: new Date().toISOString(), seed: Number(arg('--seed', 20261103)), repeats: REPEATS, out: OUT, trials, leaked_trials: leaks.filter((l) => l.family === 'drawing' || l.family === 'quotation').length, table, by_class: byClass, by_surface: bySurface, held: heldWhy,
  model_path_drawings: pipe.drawings.filter((d) => d.model_path).length, ocr_control: ocr ? { tokens: control.tokens, read: control.read, rate: control.tokens ? +(control.read / control.tokens).toFixed(3) : null } : 'skipped', image_control: { planted: control.images, seen_on_original: control.images_seen }, leaks: leaks.slice(0, 400) };
console.table(table);
console.log('leaks by class:', byClass);
console.log('leaks by surface:', bySurface);
console.log('held:', heldWhy, ' model-path drawings (not sent locally):', summary.model_path_drawings);
console.log('OCR control (planted Latin tokens read on the ORIGINAL page):', summary.ocr_control, ' image control:', summary.image_control);
if (JSON_OUT) writeFileSync(JSON_OUT, JSON.stringify(summary, null, 1));
writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 1));
console.log(`${summary.leaked_trials} leaked of ${trials} drawing + quotation trials (Q&A ${fam('qa').filter((r) => r.leaked).length}/${fam('qa').length}, comparisons ${fam('comparison').filter((r) => r.leaked).length}/${fam('comparison').length})`);
process.exitCode = leaks.length ? 1 : 0;
