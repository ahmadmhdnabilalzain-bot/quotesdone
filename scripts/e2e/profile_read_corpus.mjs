// scripts/e2e/profile_read_corpus.mjs — THE COMPANY PROFILES A SUPPLIER ACTUALLY SENDS, EACH WITH THE TRUTH WRITTEN BEFORE ANY RUN.
// Assigned: sales_engineer. 2 Nov 2026, ledger 1469. Every company is a ZZ DEMO and every file says so on its last line.
//
// A real UAE profile is not a services list: it opens with a chairman's message, then the company, then (somewhere) what it
// does, then an organisation chart, an equipment list, clients, projects, insurance, certificates and a contact page.
// _shared/supplier_doc_trades.ts documents the traps that produced false trades on real profiles ("Management 1" ->
// accounting, "SECTION 13: INSURANCE DETAILS" -> insurance brokerage, "Full range of equipment" -> commercial kitchens,
// "ISO 9001:2015" -> iso_certification), so the text profiles carry exactly those lines. The trades each file STATES are
// the only trades its screen may show (exact-trade-or-none: a nearest trade is a defect).
//
//   truth.read   'text' | 'none' | 'scan' | 'unreadable'   (see profile_read_judge.mjs)
//   truth.stated trade codes the file offers;  truth.fileText every line the file prints
import { demoPdfPages } from '../lib/demo_pdf.mjs';
import { rawPdf, docx } from './document_intake_corpus.mjs';
import sharp from 'sharp';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const MIME = { pdf: 'application/pdf', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const FIXTURE = '(QuotesDone synthetic fixture - not a real company)';

// The lines before and after "Our services" in a long real profile.
const before = (name, about) => ['Chairman message', 'Since our founding we have valued safety, integrity and long term relationships with our clients.',
  'We thank our staff, our partners and our clients for their trust.', 'About us', about, `${name} has offices in Dubai and Sharjah.`];
const after = (name) => ['Organisation', 'Management 1', 'General Manager', 'Operations Manager', 'Finance Manager', 'Projects Manager', 'Estimating department', 'Procurement department', 'Site supervision', 'Quality control', 'Health and safety',
  'Our people', '- 85 skilled staff and 6 project teams', '- Safety induction for every worker before the first day on site', '- Annual training and toolbox talks',
  'Quality policy', 'We deliver every project to the agreed specification and hand it over clean, complete and on time.', 'Health and safety policy', 'Zero harm is our target on every site we work on.',
  'Equipment', 'Full range of equipment for every project', '- Scissor lifts and mobile scaffolds', '- Cutting and drilling machines', '- Delivery trucks and trailers', '- Site offices and storage containers', '- Hand tools and measuring instruments',
  'Our clients', '- Emaar, Damac, Nakheel and Aldar', '- Government departments and hospitality groups', 'Selected projects', '- Marina Heights tower, 42 floors', '- Palm villas, 120 homes', '- Business Bay office fit-out', '- Al Barsha school extension', '- Jumeirah beach hotel refurbishment', '- Sharjah residential compound, 64 homes', '- Yas Island showroom',
  'SECTION 13: INSURANCE DETAILS', 'Contractors all risk and workmen compensation cover is held with a UAE insurer.',
  'Certifications', '- ISO 9001:2015 quality management', '- ISO 45001:2018 occupational health and safety', 'Contact us', `${name}, Al Quoz Industrial Area 3, Dubai`, FIXTURE];

function pdfOf(lines, perPage = 34) {
  const pages = []; for (let i = 0; i < lines.length; i += perPage) pages.push(lines.slice(i, i + perPage).map((l, k) => [l, i + k === 0 ? 14 : 10]));
  return demoPdfPages(pages);
}
const textPdf = (name, about, services, tail = after(name)) => { const lines = [`${name} - Company Profile`, ...before(name, about), 'Our services', ...services.map((s) => `- ${s}`), ...tail]; return { lines, bytes: pdfOf(lines) }; };

// A photograph: noise with a few shapes, no text of any kind. A real brochure's pages are mostly these.
const photo = (w, h, seed) => sharp({ create: { width: w, height: h, channels: 3, background: { r: 90 + seed * 30, g: 120, b: 150 - seed * 20 }, noise: { type: 'gaussian', mean: 128, sigma: 38 } } })
  .composite([{ input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect x="${60 + seed * 40}" y="200" width="${w - 220}" height="${h / 2}" fill="#d9d4c8" opacity="0.85"/><circle cx="${w - 160}" cy="140" r="90" fill="#f2e6b0" opacity="0.9"/></svg>`) }]).jpeg({ quality: 60 }).toBuffer();
const pdfText = (lines) => 'BT\n' + lines.map(([t, size], i) => `/F1 ${size} Tf\n1 0 0 1 60 ${780 - i * (size + 10)} Tm\n(${String(t).replace(/([()\\])/g, '\\$1')}) Tj\n`).join('') + 'ET\n';

/** Returns [{ id, label, file, name, mime, upload, truth }]; files are written under dir. */
export async function profileCorpus(dir) {
  // `company` is the name the profile prints, and the name the walk registers the supplier under and prints on its licence: a profile
  // about another company than the one registered is not what a supplier uploads, and the reader is told whose work counts (rule 4).
  const out = []; const put = (id, label, name, bytes, mime, truth, extra = {}) => { writeFileSync(join(dir, name), bytes); out.push({ id, label, file: join(dir, name), name, mime, truth, company: truth.fileText[0]?.split(' - ')[0], ...extra }); };

  // 1. a text PDF: aluminium and glazing among the usual noise of a long profile
  { const n = 'ZZ DEMO Al Reem Facades LLC'; const p = textPdf(n, `${n} is a UAE contractor that designs, supplies and installs aluminium and glass systems.`, ['Aluminium works', 'Glazing works']);
    put('text_pdf', 'text PDF, 2 services among a long profile', 'al_reem_facades_profile.pdf', p.bytes, MIME.pdf, { read: 'text', stated: ['aluminium', 'glazing'], fileText: p.lines }); }

  // 2. the same kind of company as a scanned PDF: pages are pictures, there is no text layer
  { const lines = ['ZZ DEMO Reem Projects LLC - Company Profile', 'About us', 'ZZ DEMO Reem Projects LLC is a UAE contractor serving Dubai and Sharjah.', 'Our services', '- HVAC works', '- Plumbing works', FIXTURE];
    const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1240" height="1754"><rect width="100%" height="100%" fill="#fff"/>${lines.map((l, k) => `<text x="80" y="${150 + k * 80}" font-family="Arial" font-size="34">${esc(l)}</text>`).join('')}</svg>`);
    const jpeg = await sharp(svg).flatten({ background: '#ffffff' }).jpeg({ quality: 80 }).toBuffer();
    put('scanned_pdf', 'scanned PDF (image only), 2 services', 'reem_projects_profile_scan.pdf', rawPdf([{ jpeg, w: 1240, h: 1754 }]), MIME.pdf, { read: 'scan', stated: ['hvac', 'plumbing'], fileText: lines }); }

  // 2b. the profile saved as a picture (a screenshot or phone photo): the portal sends pictures to the vision model
  { const lines = ['ZZ DEMO Pearl Lifts and Floors LLC - Company Profile', 'About us', 'ZZ DEMO Pearl Lifts and Floors LLC is a UAE company serving Dubai and Abu Dhabi.', 'Our services', '- Elevator installation', '- Flooring works', FIXTURE];
    const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1240" height="1100"><rect width="100%" height="100%" fill="#fff"/>${lines.map((l, k) => `<text x="80" y="${120 + k * 80}" font-family="Arial" font-size="34">${esc(l)}</text>`).join('')}</svg>`);
    put('photo_png', 'profile saved as a PNG picture, 2 services', 'pearl_lifts_profile.png', await sharp(svg).png().toBuffer(), 'image/png', { read: 'scan', stated: ['elevators', 'flooring'], fileText: lines }); }

  // 3. an image-heavy brochure: three photo pages with no text, then one text page that lists the services
  { const lines = ['ZZ DEMO Sahara Finishes LLC - Brochure', 'What we do', '- Painting works', '- Waterproofing works', 'Our work is shown on the previous pages.', FIXTURE];
    const pages = [{ jpeg: await photo(800, 1130, 1), w: 800, h: 1130 }, { jpeg: await photo(800, 1130, 2), w: 800, h: 1130 }, { jpeg: await photo(800, 1130, 3), w: 800, h: 1130 },
      { content: pdfText(lines.map((l, i) => [l, i === 0 ? 16 : 11])) }];
    put('brochure', 'image-heavy brochure: 3 photo pages and one text page', 'sahara_finishes_brochure.pdf', rawPdf(pages), MIME.pdf, { read: 'text', stated: ['painting', 'waterproofing'], fileText: lines }); }

  // 4. a Word profile
  { const n = 'ZZ DEMO Falcon Interiors LLC'; const lines = [`${n} - Company Profile`, ...before(n, `${n} is a UAE company established in 2014 that fits out villas and offices.`), 'Our services', '- Joinery works', '- Flooring works', ...after(n)];
    put('docx', 'Word profile (DOCX), 2 services', 'falcon_interiors_profile.docx', docx(lines), MIME.docx, { read: 'text', stated: ['joinery', 'flooring'], fileText: lines }); }

  // 5. Arabic and English side by side (a Word file: the Arabic is real text, not a font trick)
  { const lines = ['ZZ DEMO Al Noor Landscaping LLC - Company Profile', 'شركة النور لتنسيق الحدائق - الملف التعريفي', 'About us', 'ZZ DEMO Al Noor Landscaping LLC is a UAE company serving Dubai and Ajman.', 'عن الشركة', 'شركة إماراتية تخدم دبي وعجمان منذ عام 2015.',
      'Our services', '- Landscaping works', '- Waterproofing works', 'خدماتنا', '- أعمال تنسيق الحدائق', '- أعمال العزل المائي', 'Clients', '- Emaar and Nakheel', 'Contact us', 'Al Quoz Industrial Area 3, Dubai', FIXTURE];
    put('bilingual', 'Arabic and English side by side (DOCX)', 'al_noor_landscaping_profile_ar_en.docx', docx(lines), MIME.docx, { read: 'text', stated: ['landscaping', 'waterproofing'], fileText: lines }); }

  // 6. a multi-trade MEP and fit-out profile
  { const n = 'ZZ DEMO Najm MEP and Fit-Out LLC'; const p = textPdf(n, `${n} is a UAE contractor delivering building services and finishes under one contract.`, ['Electrical works', 'Plumbing works', 'HVAC works', 'Fire fighting systems', 'Painting works']);
    put('multi_trade', 'multi-trade profile: 5 services', 'najm_mep_profile.pdf', p.bytes, MIME.pdf, { read: 'text', stated: ['electrical', 'plumbing', 'hvac', 'fire_fighting', 'painting'], fileText: p.lines }); }

  // 7. a profile that says who the company is and never what it sells
  { const n = 'ZZ DEMO Horizon Holdings LLC'; const lines = [`${n} - Company Profile`, 'Chairman message', 'Our values are integrity, safety and respect for every person we work with.', 'About us', `${n} is a UAE company established in 2016.`,
      'Our people', '- 40 staff in Dubai', 'Our clients', '- Emaar and Damac', 'Certifications', '- ISO 9001:2015 quality management', 'Contact us', `${n}, Business Bay, Dubai`, FIXTURE];
    put('no_services', 'profile that states no service', 'horizon_holdings_profile.pdf', pdfOf(lines), MIME.pdf, { read: 'none', stated: [], fileText: lines }); }

  // 8. a blank page
  put('blank', 'blank PDF', 'blank_profile.pdf', rawPdf([{ content: '' }]), MIME.pdf, { read: 'unreadable', stated: [], fileText: [] }, { failedRead: true, company: 'ZZ DEMO Blank Page LLC' });

  // 9. a file that is not a PDF at all, named .pdf (a corrupt or truncated upload)
  put('corrupt', 'corrupt file named .pdf', 'corrupt_profile.pdf', Buffer.concat([Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R'), Buffer.from(Array.from({ length: 600 }, (_, i) => (i * 37 + 11) % 256))]), MIME.pdf,
    { read: 'unreadable', stated: [], fileText: [] }, { failedRead: true, company: 'ZZ DEMO Corrupt File LLC' });
  return out;
}
