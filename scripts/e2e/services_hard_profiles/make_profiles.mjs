// Renders the hard-profile set (profiles_def.mjs) to PDFs with a real text layer, as a supplier would upload them
// (sales_engineer, 12 Nov 2026; ruling 1647; docs/reports/2026-11-12-supplier-service-profiling.md):
//   <out>/<id>_<slug>.profile.pdf, <out>/<id>_<slug>.licence.pdf (and H08's Word copy), <out>/answer_keys.json
//   and, beside this file, answer_keys.json and ANSWER_KEYS.md (the keys are source: they are derived from profiles_def.mjs only).
// Uses the repo's own licence layout (scripts/e2e/registration_fixtures.mjs licenceHtml) and Chromium from the repo's node_modules.
// The PDFs are generated, so they are written OUTSIDE the repository (refused inside it).
//   node scripts/e2e/services_hard_profiles/make_profiles.mjs [--out <dir>]      default: <tmp>/services_hard_profiles
//   node scripts/e2e/services_hard_profiles/make_profiles.mjs --keys-only        the two key files only (no browser)
import { writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROFILES, GLOSSY, SYNTHETIC } from './profiles_def.mjs';

const HERE = dirname(fileURLToPath(import.meta.url)), REPO = resolve(HERE, '..', '..', '..');
const argv = process.argv.slice(2), opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : null; };
const KEYS_ONLY = argv.includes('--keys-only');
const OUT = resolve(opt('--out') || join(tmpdir(), 'services_hard_profiles'));
if (OUT === REPO || OUT.startsWith(REPO + '/')) { console.error('REFUSED: the PDFs are generated; write them outside the repository (--out)'); process.exit(2); }
// an HTML body as the lines a Word file would hold (headings, paragraphs, list items), in logical order
const linesOf = (html) => html.replace(/<\/(h2|h3|p|li|div)>/g, '\n').replace(/<[^>]+>/g, '').split('\n').map((l) => l.trim()).filter(Boolean);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const CSS = `@page { size: A4; margin: 14mm } body { font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 10.5pt; color: #222 }
  h1 { color: #0b4f6c; margin: 0 0 4px } h2 { color: #0b4f6c; border-bottom: 2px solid #0b4f6c; padding-bottom: 3px; margin-top: 18px } h3 { color: #333; margin: 12px 0 2px }
  li { margin: 4px 0 } .brk { page-break-before: always } .band { background: #0b4f6c; color: #fff; padding: 18px; border-radius: 6px; margin-bottom: 10px } .band h1 { color: #fff }
  .foot { color: #888; font-size: 8pt; margin-top: 30px } .img { height: 120mm; border-radius: 6px; margin: 8px 0 } .cap { font-size: 9.5pt; color: #444 } .big { font-size: 26pt; color: #0b4f6c; margin-top: 60mm }`;

function profileHtml(P) {
  const rtl = P.lang === 'ar';
  const body = P.glossy ? glossyBody(P) : P.body;
  return `<!doctype html><html${rtl ? ' dir="rtl" lang="ar"' : ''}><head><meta charset="utf-8"><style>${CSS}</style></head><body>
    <div class="band"><h1>${esc(rtl ? P.company_ar : P.company)}</h1><div>${rtl ? esc(P.tagline) : `Company profile 2026 - ${esc(P.tagline)}`}</div></div>
    ${body}
    <p class="foot">(${SYNTHETIC})</p></body></html>`;
}
// 30 pages: cover + 8 front-matter pages + 18 project pages (a picture and a caption each) + 4 back pages - 1 (cover carries the band)
function glossyBody(P) {
  const hue = (i) => `hsl(${(i * 47) % 360} 35% 62%)`;
  const front = GLOSSY.front.map(([h, t]) => `<div class="brk"></div><div class="big">${esc(h)}</div><p>${esc(t)}</p>`).join('');
  const projects = GLOSSY.projects.map(([name, year, cap], i) => `<div class="brk"></div><div class="img" style="background:${hue(i)}"></div><h3>${esc(name)}</h3><p class="cap">${esc(year)}. ${esc(cap)}</p>`).join('');
  const back = GLOSSY.back.map(([h, t]) => `<div class="brk"></div><div class="big">${esc(h)}</div><p>${esc(t)}</p>`).join('');
  return `<div class="big">${esc(P.tagline)}</div>${front}<div class="brk"></div><div class="big">Selected projects</div>${projects}${back}`;
}
const licenceOf = (P) => ({ key: P.licence.key, licence_no: P.licence.licence_no, legal_name: P.company, trade_name: P.company.replace(/ (LLC|FZE|Est)$/, ''), issue: '2025-06-01', expiry: '2027-05-31', activities: P.licence.activities });

const rowOf = (P, base) => ({ id: P.id, slug: P.slug, company: P.company, signup_trade: P.signup_trade, lang: P.lang || 'en', profile: `${base}.profile.pdf`, licence: `${base}.licence.pdf`,
  licence_activities: P.licence.activities, key: P.key });
const out = [];
if (KEYS_ONLY) {
  for (const P of PROFILES) { const base = `${P.id}_${P.slug}`; out.push(rowOf(P, base)); if (P.lang === 'ar') out.push({ ...rowOf(P, base), id: P.id + 'D', profile: `${base}.profile.docx` }); }
} else {
  mkdirSync(OUT, { recursive: true });
  const { chromium } = await import('playwright');
  const { licenceHtml } = await import('../registration_fixtures.mjs');
  const { docx } = await import('../document_intake_corpus.mjs');
  const browser = await chromium.launch();
  try {
  for (const P of PROFILES) {
    const pdf = async (html) => { const p = await browser.newPage(); await p.setContent(html, { waitUntil: 'load' }); const b = await p.pdf({ format: 'A4', printBackground: true, preferCSSPageSize: true }); await p.close(); return b; };
    const base = `${P.id}_${P.slug}`;
    const prof = await pdf(profileHtml(P)), lic = await pdf(licenceHtml(licenceOf(P)));
    writeFileSync(join(OUT, `${base}.profile.pdf`), prof); writeFileSync(join(OUT, `${base}.licence.pdf`), lic);
    out.push(rowOf(P, base));
    console.log(base, prof.length, lic.length);
    // THE ARABIC PROFILE TWICE (H08): Chromium prints Arabic into the PDF text layer as presentation forms in VISUAL order (what many
    // designed Arabic PDFs give a reader); a Word file gives the same words in logical order. Both are what suppliers upload.
    if (P.lang === 'ar') {
      const d = docx([P.company_ar, P.tagline, ...linesOf(P.body), `(${SYNTHETIC})`]);
      writeFileSync(join(OUT, `${base}.profile.docx`), d);
      out.push({ ...out[out.length - 1], id: P.id + 'D', profile: `${base}.profile.docx` });
      console.log(base + ' (docx)', d.length);
    }
  }
  } finally { await browser.close(); }
}
const keysJson = JSON.stringify({ note: `${SYNTHETIC}. Keys are taxonomy keys as of 12 Nov 2026.`, profiles: out }, null, 1) + '\n';
writeFileSync(join(HERE, 'answer_keys.json'), keysJson);
if (!KEYS_ONLY) writeFileSync(join(OUT, 'answer_keys.json'), keysJson);

// the human-readable answer keys
const L = (a) => (a && a.length ? a.map((x) => `\`${x}\``).join(', ') : '(none)');
const md = ['# Hard-profile set: answer keys', '', `Twelve invented ZZ DEMO companies (${SYNTHETIC}). Written 12 Nov 2026 by the sales_engineer analyst for founder ruling 1647.`,
  'Each key is what a sharp human sales engineer lists after reading the profile and its licence, and the questions he would ask. Keys are `taxonomy_trade` / `taxonomy_trade_service` keys as they stand today; "no key today" is what the taxonomy cannot express.', ''];
for (const P of PROFILES) {
  const k = P.key;
  md.push(`## ${P.id} ${P.company}`, '', `Files: \`${P.id}_${P.slug}.profile.pdf\`, \`${P.id}_${P.slug}.licence.pdf\`. Licence activities: ${P.licence.activities.join('; ')}. Sign-up trade: \`${P.signup_trade}\`.`, '',
    `- Trades that must be proposed: ${L(k.must_trades)}`, `- Trades that are not wrong: ${L(k.ok_trades)}`, `- Services evidenced in so many words (own team): ${L(k.must_services)}`, `- Fair readings, not required: ${L(k.ok_services)}`,
    `- Through a partner or sister company (must be distinguished, never ticked as own): ${L(k.partner)}`, `- Evidenced but NO key today (the supplier's own words): ${k.no_key.length ? k.no_key.join('; ') : '(none)'}`,
    ...(Object.keys(k.umbrella || {}).length ? [`- Umbrella words and the candidates to ask about: ${Object.entries(k.umbrella).map(([w, c]) => `"${w}" -> ${c.join(' / ')}`).join(' ; ')}`] : []),
    ...(k.must_not ? [`- Must NOT be proposed: ${L(k.must_not)}`] : []), ...(k.must_be_empty ? ['- Nothing may be proposed.'] : []), `- Too vague to match on without asking: ${k.vague ? 'YES' : 'no'}`,
    '- Questions the sales engineer would ask:', ...k.questions.map((q) => `  - ${q}`), '');
}
writeFileSync(join(HERE, 'ANSWER_KEYS.md'), md.join('\n'));
console.log('written', out.length, 'profiles', KEYS_ONLY ? '(keys only)' : `-> ${OUT}`);
