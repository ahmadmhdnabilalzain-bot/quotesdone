// scripts/e2e/evidence_pack.mjs — the founder's EVIDENCE PACK: three customer journeys and one supplier registration,
// end to end on PRODUCTION, captured as screenshots, PDFs, transcripts and a screen recording. ZZ DEMO only.
// Assigned: customer_support (founder ledger 1604, 10 Nov 2026: "PROOF, not a test summary").
//
//   node scripts/e2e/evidence_pack.mjs --dry            the harness, models OFF (rehearsal window models_allowed=false)
//   node scripts/e2e/evidence_pack.mjs                  the one real run, models ON, capped (default USD 4)
//   options: --only 1,2,3,4   --out <dir>   --cap-usd 4   --keep (tear down later: run.mjs --purge-tag <tag>)
//
// WHAT EACH JOURNEY DOES, THROUGH THE PRODUCT'S OWN DOORS
//   1 text only            the customer types in the request chat (/me -> New request), answers the sales engineer.
//   2 text + drawing + BOQ the same chat, with a villa HVAC drawing on the paperclip and a BOQ .xlsx on the BOQ button
//                          (customer_api analyze_drawing -> drawing_redact + drawing_boq; analyze_document).
//   3 a voice note only    the chat's microphone: the recorded audio goes to `transcribe` (the server path the portal
//                          uses when the browser has no speech engine). The harness plays a synthesised voice note into
//                          the page's microphone (getUserMedia returns the note's audio); everything after the mic is
//                          the product: MediaRecorder -> blobToWavB64 -> transcribe -> the text box -> Send.
//   For each: the posted request, what a supplier sees (portal + supplier_api inquiry_pdf), five ZZ DEMO suppliers
//   quoting by UPLOADING a quotation PDF (supplier_api extract_quote -> quote_extract, then submit_quote, exactly
//   QuoteForm's payload; a held quote goes through the hold desk spec_fill/spec_approve), the customer's comparison
//   (portal + customer_api compare_pdf), a TEST-mode reveal (stripe_checkout -> Stripe hosted test card -> stripe_confirm)
//   and the invoice (reveal_invoice).
//   4 supplier registration, recorded: /supplier -> sign-up with the REAL e-mail code (Resend sink, resend_sink.mjs) ->
//     company + trade -> licence, company profile, catalogue -> the Supplier Agreement -> Submit -> the Services tab
//     (what our reader proposed, with its evidence and the licence check) -> ticked and confirmed -> approved.
//
// WHAT IS NOT THE PRODUCT, SAID PLAINLY
//   * A customer session is injected (fixtures.mjs: no OTP delivery to a reserved domain); the supplier fixtures are
//     made by fixtures.makeDemoSupplier (mandatory six, agreement signed through kyc accept_terms).
//   * The chat's answers come from a per-journey script (FACTS below) matched to the question asked; nothing is
//     typed by a model on the customer's side.
//   * A demo supplier the live matcher did not pick is matched by the harness (recorded as such in manifest.json).
//   * The supplier registration's mobile is the reserved fixture block, recorded verified (no SMS can reach it), and the
//     form's one kyc read is held while it is recorded (fixture_mobile.mjs recordFixtureMobileBeforeTheForm, 11 Nov 2026).
//
// SAFETY: identities are ZZ DEMO / qd-<tag>-*@example.invalid / +971 50 000 00xx; the one exception is the registration
// account's e-mail, Resend's own sink delivered+qd-<tag>-...@resend.dev (accepted and dropped by Resend, no inbox).
// Every notification the run caused is counted by status before teardown; a sent/queued/pending row fails the run.
import { mkdirSync, writeFileSync, readFileSync, existsSync, copyFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, write, call, waitFor } from './fixtures.mjs';
import { launch, signedInPage, openPortal, portalUrl, SITE, carriesRunTag } from './browser.mjs';
import { rasterise } from './portal_raster.mjs';
import { payHostedTestCheckout } from './stripe_test_checkout.mjs';
import { sinkAddress, readCode, cleanSink, leftoversSink } from './resend_sink.mjs';
import { keys, BASE, makeInquiry, internalCred, TRADES } from '../lib/demo_factory.mjs';
import { demoTradeLicence } from '../lib/demo_pdf.mjs';
import { recordFixtureMobileBeforeTheForm } from './fixture_mobile.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const val = (f, d = null) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const DRY = argv.includes('--dry');
const KEEP = argv.includes('--keep');
const ONLY = (val('--only', '1,2,3,4')).split(',').map((s) => s.trim());
const CAP = Number(val('--cap-usd', '4'));
const OUT = resolve(val('--out', join(process.env.QD_EVIDENCE_OUT || '/tmp/qd-evidence', DRY ? 'dry' : 'real')));
const VOICES = process.env.QD_PIPER_VOICES || '';
process.env.QD_FIXTURES = '1';
// staff_transport is a live taxonomy_trade the demo factory's 25-trade table does not carry; a demo supplier of it needs
// a capability profile (products_norm, brands), so the table is extended for this process only.
if (!TRADES.staff_transport) TRADES.staff_transport = { name: 'Staff Transport', products: ['staff bus rental', 'bus hire', 'staff shuttle', 'labour transport', 'bus with driver', 'coach rental', 'chauffeur service', 'school transport'], brands: ['Ashok Leyland', 'King Long'] };
// The microphone's AudioContext must run without a gesture of its own (the click on the mic is the gesture).
process.env.QD_CHROMIUM_ARGS = [process.env.QD_CHROMIUM_ARGS || '', '--autoplay-policy=no-user-gesture-required'].join(' ').trim();
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const M = { dry: DRY, site: SITE, started: new Date().toISOString(), journeys: {}, registration: null, findings: [], safety: null, spend: null, teardown: null };
const finding = (where, what) => { M.findings.push({ where, what }); log('FINDING', where, what); };
const save = () => writeFileSync(join(OUT, 'manifest.json'), JSON.stringify(M, null, 1));

// ── small document makers ──────────────────────────────────────────────────────────────────────────────────────────
let BROWSER = null; let RUN_REF = null;
async function htmlPdf(html, opts = {}) {
  const ctx = await BROWSER.newContext(); const p = await ctx.newPage();
  await p.setContent(html, { waitUntil: 'load' });
  const b = await p.pdf({ printBackground: true, format: opts.format || 'A4', landscape: !!opts.landscape, margin: { top: '12mm', bottom: '12mm', left: '12mm', right: '12mm' } });
  await ctx.close(); return b;
}
/** Every page of a PDF as a JPEG next to it (the portal's own rasteriser), so the README can show it. */
async function pdfPictures(pdf, base) {
  try {
    const imgs = await rasterise(pdf);
    imgs.forEach((im, i) => writeFileSync(`${base}_p${i + 1}.jpg`, Buffer.from(im.data, 'base64')));
    return imgs.length;
  } catch (e) { log('raster failed', base, e.message); return 0; }
}
const fetchBytes = async (url) => { const r = await fetch(url); if (!r.ok) throw new Error(`GET ${url.slice(0, 80)}: HTTP ${r.status}`); return Buffer.from(await r.arrayBuffer()); };
const aed = (n) => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

function xlsx(path, title, rows) {
  const py = `import openpyxl,sys,json\nfrom openpyxl.styles import Font,PatternFill\nwb=openpyxl.Workbook();ws=wb.active;ws.title='BOQ'\nd=json.loads(sys.argv[2])\nws.append([d['title']]);ws['A1'].font=Font(bold=True,size=13)\nws.append([])\nws.append(['Item','Description','Qty','Unit'])\nfor c in ws[3]: c.font=Font(bold=True); c.fill=PatternFill('solid',fgColor='DDE6F0')\nfor r in d['rows']: ws.append(r)\nws.column_dimensions['B'].width=78\nwb.save(sys.argv[1])\n`;
  const r = spawnSync('python3', ['-c', py, path, JSON.stringify({ title, rows })], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('xlsx: ' + r.stderr);
}

/** A voice note: each [lang, text] segment spoken by an offline neural voice (piper), joined, 16 kHz mono WAV. */
function voiceNote(path, segments) {
  const parts = [];
  segments.forEach(([lang, text], i) => {
    const model = join(VOICES, lang === 'ar' ? 'ar_JO-kareem-medium.onnx' : 'en_GB-alan-medium.onnx');
    const f = `${path}.${i}.wav`;
    const r = spawnSync('piper', ['-m', model, '-f', f, '--sentence-silence', '0.35'], { input: text, encoding: 'utf8' });
    if (r.status !== 0 || !existsSync(f)) throw new Error('piper failed: ' + (r.stderr || '').slice(-300));
    parts.push(f);
  });
  const inputs = parts.flatMap((p) => ['-i', p]);
  const filter = parts.map((_, i) => `[${i}:a]aresample=16000,apad=pad_dur=0.4[a${i}]`).join(';') + ';' + parts.map((_, i) => `[a${i}]`).join('') + `concat=n=${parts.length}:v=0:a=1[out]`;
  const r = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', ...inputs, '-filter_complex', filter, '-map', '[out]', '-ac', '1', '-ar', '16000', path]);
  if (r.status !== 0) throw new Error('ffmpeg: ' + r.stderr);
  const d = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path], { encoding: 'utf8' });
  return Number(d.stdout.trim()) || 10;
}

// ── the three journeys: who the customer is, what he says, and how five suppliers answer ──────────────────────────────
// FACTS: [question pattern, answer]. The first fact whose pattern matches the sales engineer's question (or the open
// questions it lists) and has not been given yet is the next answer. OPENER is the first message.
export const JOURNEYS = {
  1: {
    folder: '1_text_only', label: 'J1 Office', trade: 'wallpaper', title: 'Replace PVC wall panels on an MDF partition, Business Bay office',
    serviceWords: 'Wall panels, Wall cladding, Wallpaper supply & installation, Wallpaper removal',
    opener: 'Hello. In our office in Business Bay, Dubai, we have an MDF partition wall covered with PVC wall panels. The panels are old, scratched and some are coming off. We want the old PVC panels removed and new PVC wall panels installed on the same MDF partition.',
    facts: [
      [/payment/i, 'Payment terms: 50% advance and 50% on completion is fine for us.'],
      [/pattern|repeat|match/i, 'Plain wood-grain panels, so there is no pattern repeat to match. The panels are 250 mm wide and butt-jointed.'],
      [/design code|colourway|product code|colour code/i, 'Light oak colourway, matt wood-grain. Any manufacturer code in that colour is fine, or equivalent.'],
      [/wallcovering type|type of wall|category|vinyl|wallpaper or/i, 'Rigid PVC wall cladding panels, not wallpaper, about 8 mm thick.'],
      [/how (big|many)|area|size|sqm|square|coverage|walls|rooms|dimension|length|height|quantit/i, 'The partition is 12 metres long and 2.8 metres high, panels on one side only, so about 34 square metres. We also need about 24 running metres of aluminium edge trims and skirting.'],
      [/style|finish|colou?r|look|texture|design|pattern|type of panel|material|spec|grade|fire|brand|origin|quality/i, 'Light oak wood-look PVC panels, matt finish, fire rated Class B (B-s1,d0) or better. European made, German or similar, or equivalent quality.'],
      [/supply|install|hang|provide|scope|remov|dispos|old panel/i, 'Supply and installation, including removal and disposal of the old panels and repair of the MDF where needed.'],
      [/surface|condition|prepar|repair|smooth|mdf/i, 'Some MDF boards are swollen near the floor and must be repaired or replaced before the new panels go on.'],
      [/where|location|emirate|area of|address|access|floor|building|working hours|time of work/i, 'Business Bay, Dubai. Office on the 14th floor, access by the service lift, and work only after 6 pm or at weekends.'],
      [/when|timeline|date|deadline|by when|start|complet|finish by|schedule/i, 'We need it finished by 15 December 2026.'],
      [/warrant|guarantee/i, 'At least 2 years warranty on materials and installation.'],
      [/budget|price range|spend|cost/i, 'Our budget is around AED 10,000 to 14,000.'],
    ],
    confirm: 'Yes, that is all correct. Please send it to suppliers.',
    // the lines a supplier prices when the request carries no BOQ of its own
    defaultLines: [
      { description: 'Removal and disposal of existing PVC wall panels', qty: 34, unit: 'm2' },
      { description: 'Repair of swollen MDF boards and preparation', qty: 1, unit: 'lot' },
      { description: 'Supply and install PVC wall panels, fire rated', qty: 34, unit: 'm2' },
      { description: 'Aluminium edge trims and skirting', qty: 24, unit: 'lm' },
    ],
    specFor: (d, s) => /remov|dispos|strip/i.test(d) ? 'Manual removal, debris to approved disposal site' : /mdf|repair|prepar/i.test(d) ? 'Moisture-resistant MDF 18 mm, sanded and primed'
      : /trim|skirt|edge|profile/i.test(d) ? 'Aluminium 6063 profile, anodised, 2.5 m lengths' : /panel|clad/i.test(d) ? `PVC panel 8 mm, 250 x 2800 mm, light oak matt, ${s.brandLine}` : 'As per the request',
    rate: (d, u) => /remov|dispos|strip/i.test(d) ? 28 : /mdf|repair|prepar/i.test(d) ? (u === 'lot' || u === 'ls' ? 1400 : 45) : /trim|skirt|edge|profile/i.test(d) ? 38 : /panel|clad|install/i.test(d) ? 185 : /clean|after.?hours|night/i.test(d) ? 600 : 120,
    suppliers: [
      { label: 'Al Noor Interiors', factor: 1.00, brandLine: 'made in Germany, Class B-s1,d0', origin: 'Germany', lead: '12 days from LPO', warranty: '3 years on panels and workmanship', payment: '40% advance, 60% on completion', omit: null, excl: 'Electrical works, painting of adjacent walls.' },
      { label: 'Gulf Panel Systems', factor: 0.78, brandLine: 'made in China, fire class E', origin: 'China', lead: '7 days from LPO', warranty: '1 year on workmanship', payment: '50% advance, 50% on completion', omit: null, excl: 'Electrical works.' },
      { label: 'Emirates Wall Concepts', factor: 1.26, brandLine: 'premium, made in Italy, Class B-s1,d0', origin: 'Italy', lead: '18 days from LPO', warranty: '5 years on panels and workmanship', payment: '30% advance, 70% on completion', omit: null, excl: 'None.' },
      { label: 'Desert Fit Out Works', factor: 0.84, brandLine: 'made in Turkey, Class B-s1,d0', origin: 'Turkey', lead: '10 days from LPO', warranty: '2 years on panels and workmanship', payment: '50% advance, 50% on completion', omit: /remov|dispos|mdf|repair|prepar/i, excl: 'Removal of the existing panels and any MDF repair are by the client.' },
      { label: 'Marina Decor Contracting', factor: 1.06, brandLine: 'made in Germany, Class B-s1,d0', origin: 'Germany', lead: '6 weeks from LPO (panels imported to order)', warranty: '2 years on panels and workmanship', payment: '50% advance, 50% on completion', omit: null, excl: 'Electrical works.' },
    ],
    hold: { finish: 'Light oak wood-look, matt', thickness: '8 mm', size: '250 x 2800 mm', material: 'PVC' },
    holdBy: [
      [/trim|skirting/, 'Aluminium trim profile, anodised'],
      [/type|category/, (sp, d) => /trim|skirt/i.test(d) ? 'Aluminium edge trim and skirting profile' : 'Rigid PVC wall cladding panel, wood-grain, 8 mm'],
      [/brand|manufactur/, (sp, d) => /trim|skirt/i.test(d) ? 'Local extrusion, made in UAE' : `${sp.origin} manufacturer's own range (${sp.brandLine})`],
      [/design|colour|code/, 'Light oak, matt wood-grain'],
      [/repeat|match/, 'No pattern repeat: plain wood-grain panels, butt-jointed'],
      [/width|roll|size|length/, '250 mm wide x 2800 mm long panels'],
      [/fire/, (sp) => /class e/i.test(sp.brandLine) ? 'Fire class E (EN 13501-1)' : 'Class B-s1,d0 (EN 13501-1)'],
      [/substrate/, 'MDF partition'], [/adhesive/, 'Panel adhesive with concealed clips'], [/prepar|surface/, 'Repair of swollen MDF and sanding before fixing'],
      [/wall_dimension|dimension/, '12 m long x 2.8 m high, one side, about 34 m2'],
    ],
  },
  2: {
    folder: '2_text_drawing_boq', label: 'J2 Villa', trade: 'hvac', title: 'Villa HVAC from a drawing and a BOQ, Al Barsha South',
    serviceWords: null,   // fixtures.mjs SERVICE_WORDS.hvac
    opener: 'Hi, we are finishing a G+1 private villa in Al Barsha South, Dubai and need the air conditioning supplied and installed as per the attached HVAC drawing and BOQ: ducted split units concealed in the false ceiling, with ductwork, grilles, thermostats and exhaust fans, including testing and commissioning.',
    facts: [
      [/payment/i, 'Payment terms: 30% advance, 60% on delivery of the units and 10% after commissioning.'],
      [/copper|pipe length|piping/i, 'Allow up to 20 metres of insulated copper piping per unit; the BOQ has 120 metres in total.'],
      [/inverter|fixed.?speed/i, 'Inverter units, please.'],
      [/number of units|how many units|per type/i, 'Six units: two of 3.0 TR, two of 2.5 TR and two of 2.0 TR, as in the BOQ.'],
      [/capacity|btu|\btr\b|kw|tonnage/i, 'DSU-01 and DSU-02 are 3.0 TR, DSU-03 and DSU-04 are 2.5 TR, DSU-05 and DSU-06 are 2.0 TR, as in the equipment schedule on the drawing.'],
      [/duct.{0,30}(route|size)|routes|duct size/i, 'The duct routes and sizes are on drawing M-101: main ducts 500 x 300, about 160 square metres of ductwork in total.'],
      [/system|type of ac|kind of air|ducted|split|cassette|vrf|central/i, 'Ducted concealed split units, as shown on the drawing: six units from 2 TR to 3 TR.'],
      [/brand|tier|make|manufactur|premium|origin|quality|efficien/i, 'Japanese brand, Daikin or Mitsubishi Electric or equivalent, inverter type, R410A or R32.'],
      [/space|used for|how big|area|size|villa|ceiling height|room/i, 'It is a private villa, about 420 square metres over ground and first floor, ceiling height 3.2 metres with a false ceiling.'],
      [/new|replace|replacement|existing|repair|service/i, 'New installation, the villa is under construction.'],
      [/drawing|load|calculation|mep|engineer/i, 'Yes, the attached MEP drawing and the BOQ show the units and quantities.'],
      [/electric|power|isolator|supply/i, 'The power points and isolators are by the electrical contractor; you only connect to them.'],
      [/install|supply|scope|commission|test/i, 'Supply, installation, testing and commissioning, everything in the BOQ.'],
      [/where|location|emirate|address|access/i, 'Al Barsha South, Dubai. Site access is easy, ground floor and first floor, no crane needed.'],
      [/when|timeline|date|deadline|by when|start|complet/i, 'We need it installed and commissioned by 31 January 2027.'],
      [/warrant|guarantee/i, 'Minimum 5 years on the compressors and 2 years on the whole installation.'],
      [/budget|price|cost/i, 'Our budget is around AED 90,000.'],
    ],
    confirm: 'Yes, that is correct. Please send it to suppliers.',
    defaultLines: [
      { description: 'Ducted split unit 3.0 TR, inverter (DSU-01, DSU-02)', qty: 2, unit: 'nos' },
      { description: 'Ducted split unit 2.5 TR, inverter (DSU-03, DSU-04)', qty: 2, unit: 'nos' },
      { description: 'Ducted split unit 2.0 TR, inverter (DSU-05, DSU-06)', qty: 2, unit: 'nos' },
      { description: 'GI ductwork with 25 mm insulation', qty: 160, unit: 'm2' },
      { description: 'Supply diffusers and return grilles', qty: 38, unit: 'nos' },
      { description: 'Copper refrigerant piping with insulation', qty: 120, unit: 'm' },
      { description: 'uPVC condensate drain piping', qty: 60, unit: 'm' },
      { description: 'Wall-mounted digital thermostat', qty: 6, unit: 'nos' },
      { description: 'Bathroom exhaust fan with ducting', qty: 5, unit: 'nos' },
      { description: 'Testing, commissioning and air balancing', qty: 1, unit: 'lot' },
    ],
    specFor: (d, s) => /exhaust/i.test(d) ? 'Ceiling fan 150 m3/h, 100 mm flexible duct' : /test|commission|balanc/i.test(d) ? 'TAB to SMACNA, written report'
      : /ducted|split|\bunit\b|inverter/i.test(d) ? `${s.brand} ducted inverter, R32, made in ${String(s.origin).replace(/\s*\(.*\)$/, '')}` : /duct/i.test(d) ? 'GI 24-26 gauge to SMACNA, 25 mm insulation'
      : /diffuser|grille/i.test(d) ? 'Powder-coated aluminium, with plenums' : /copper|refrigerant/i.test(d) ? 'ASTM B280 copper, 19 mm insulation' : /drain|condensate/i.test(d) ? 'uPVC 32 mm with traps'
      : /thermostat|controller/i.test(d) ? `${s.brand} wired digital controller` : 'As per the BOQ',
    rate: (d, u) => /exhaust/i.test(d) ? 650 : /3\.0\s*tr|3\s*tr\b|36000/i.test(d) ? 8900 : /2\.5\s*tr/i.test(d) ? 7600 : /2\.0\s*tr|2\s*tr\b/i.test(d) ? 6600 : /ducted|split|unit/i.test(d) && u === 'nos' ? 7400 : /duct/i.test(d) ? 115 : /diffuser|grille/i.test(d) ? 165 : /copper|refrigerant/i.test(d) ? 95 : /drain|condensate/i.test(d) ? 38 : /thermostat|controller/i.test(d) ? 420 : /exhaust|fan/i.test(d) ? 650 : /test|commission|balanc/i.test(d) ? 4500 : 250,
    brandRe: /ducted|split|unit|inverter/i,
    suppliers: [
      { label: 'Cool Breeze HVAC', factor: 1.00, brand: 'Daikin', origin: 'Thailand (Japanese brand)', lead: '4 weeks from LPO', warranty: '5 years on compressors, 2 years on the complete installation', payment: '30% advance, 60% on delivery, 10% on commissioning', omit: null, excl: 'Civil works, false ceiling openings, electrical power supply to isolators.' },
      { label: 'Arabian Air Systems', factor: 0.76, brand: 'Gree', origin: 'China', lead: '3 weeks from LPO', warranty: '1 year on the complete installation', payment: '50% advance, 50% on completion', omit: null, excl: 'Civil works, electrical power supply.' },
      { label: 'Polar Tech Contracting', factor: 1.13, brand: 'Mitsubishi Electric', origin: 'Japan', lead: '3 weeks from LPO', warranty: '5 years on compressors, 2 years on the complete installation', payment: '30% advance, 70% on completion', omit: null, excl: 'Civil works, electrical power supply.' },
      { label: 'Sahara Cooling Solutions', factor: 0.90, brand: 'Daikin', origin: 'Malaysia (Japanese brand)', lead: '4 weeks from LPO', warranty: '5 years on compressors, 1 year on the installation', payment: '40% advance, 60% on completion', omit: /test|commission|balanc|thermostat/i, excl: 'Testing and commissioning, thermostats, civil works.' },
      { label: 'Al Khaleej MEP Services', factor: 0.73, brand: 'Midea', origin: 'China', lead: '12 weeks from LPO', warranty: '2 years on the complete installation', payment: '50% advance, 50% on completion', omit: null, excl: 'Civil works, electrical power supply.' },
    ],
    hold: { refrigerant: 'R32', standard: 'ESMA 5-star', material: 'Galvanised steel to SMACNA' },
    holdBy: [
      [/model/, (sp, d) => /ducted|split|unit/i.test(d) ? `${sp.brand} ducted concealed inverter unit` : 'As per the BOQ line'],
      [/unit_type|type/, (sp, d) => /ducted|split|unit/i.test(d) ? 'Ducted concealed split, inverter' : 'As per the BOQ line'],
      [/inverter/, 'Inverter'], [/esma|star/, 'ESMA 5-star'], [/t3|ambient/, 'T3 rated, 52 C ambient'],
      [/copper|pipe_length/, 'Up to 20 m of insulated copper pipe per unit included'],
      [/power|phase|voltage/, '220-240 V single phase for 2.0 and 2.5 TR, 380-415 V three phase for 3.0 TR'],
      [/material/, 'Galvanised steel to SMACNA'], [/insulation/, '25 mm thermal insulation with vapour barrier'],
    ],
  },
  3: {
    folder: '3_voice_note', label: 'J3 Transport', trade: 'staff_transport', title: 'Rent a 30-seat staff bus with driver, Abu Dhabi, 6 months',
    serviceWords: 'Bus hire, Staff shuttles, Labour transport',
    // [language, words] — Gulf Arabic greeting and ask, then the details in English, as a UAE office manager speaks.
    opener: [['ar', 'السلام عليكم. أبغى أستأجر باص للموظفين، لو سمحت.'],
      ['en', 'Hi, this is about a staff bus for our company in Abu Dhabi. We need one thirty seat bus with a driver, for six months, starting on the first of December. It is to bring our staff from Mussafah to our office on Al Reem Island, in the morning at six thirty and back at five thirty in the evening, Sunday to Thursday. The bus must be air conditioned, a 2022 model or newer, with insurance, fuel and Salik included, and the driver must have an Abu Dhabi bus licence. Please send me your best monthly price. Yalla, shukran.']],
    facts: [
      [/payment/i, 'We pay monthly, at the start of each month.'],
      [/how many|seat|passeng|staff|people|capacity|size of (the )?bus/i, 'Thirty seats. We have twenty eight staff, so a thirty seat bus is enough.'],
      [/driver|chauffeur|licen[cs]e|permit|with or without/i, 'Yes, with a driver. He must have a valid Abu Dhabi bus driving licence and the passenger transport permit.'],
      [/how long|duration|period|months?|contract|start|from when|when|date/i, 'Six months, from the first of December 2026 to the end of May 2027.'],
      [/route|where|pick|drop|location|emirate|from|to/i, 'Pick up in Mussafah Industrial Area and drop at our office on Al Reem Island, Abu Dhabi, and back in the evening.'],
      [/time|schedule|hours|shift|trip|days|week/i, 'Two trips a day, six thirty in the morning and five thirty in the evening, Sunday to Thursday.'],
      [/model|year|age|condition|new|brand|type of bus|make/i, 'A 2022 model or newer, air conditioned, in good condition.'],
      [/fuel|salik|parking|insurance|include|maintenance|cost/i, 'Fuel, Salik tolls, parking, insurance and maintenance should all be included in the monthly price.'],
      [/pricing|basis|per trip|monthly|fixed price|rate/i, 'A fixed monthly price for the six months, all inclusive.'],
      [/replace|breakdown|backup|standby/i, 'If the bus breaks down we need a replacement bus within a few hours.'],
      [/budget|price/i, 'Our budget is around twelve to fifteen thousand dirhams a month.'],
    ],
    confirm: 'Yes, that is correct. Please send it to the suppliers.',
    defaultLines: [{ description: '30-seat air-conditioned staff bus with driver, monthly rental', qty: 6, unit: 'month' }],
    specFor: (d, s) => `${s.vehicle.replace(/, air conditioned.*$/, '')}, A/C, licensed driver`,
    rate: () => 13500,
    brandRe: /bus|coach|vehicle|seat/i,
    suppliers: [
      { label: 'Capital Shuttle Services', factor: 1.00, brand: 'Ashok Leyland', vehicle: 'Ashok Leyland Falcon 32-seat bus, 2023 model, air conditioned', origin: 'India', lead: 'Available from 1 December 2026', warranty: 'Replacement bus within 3 hours of a breakdown; full maintenance included', payment: 'Monthly in advance', omit: null, incl: 'Driver with Abu Dhabi bus licence, fuel, Salik, comprehensive insurance, maintenance.', excl: 'Trips outside the agreed route are charged AED 150 per hour.' },
      { label: 'Al Dhafra Bus Rental', factor: 0.82, brand: 'King Long', vehicle: 'King Long 30-seat bus, 2021 model, air conditioned', origin: 'China', lead: 'Available from 1 December 2026', warranty: 'Replacement bus within 24 hours', payment: 'Monthly in advance', omit: null, incl: 'Driver, insurance, maintenance.', excl: 'Fuel and Salik are charged at actual cost.' },
      { label: 'Royal Coach Transport', factor: 1.32, brand: 'Mercedes-Benz', vehicle: 'Mercedes-Benz 30-seat coach, 2024 model, air conditioned, Wi-Fi', origin: 'Germany', lead: 'Available from 1 December 2026', warranty: 'Replacement coach within 2 hours; full maintenance included', payment: 'Monthly in advance', omit: null, incl: 'Driver with Abu Dhabi bus licence, fuel, Salik, comprehensive insurance, maintenance.', excl: 'None.' },
      { label: 'Reem Staff Transport', factor: 0.95, brand: 'Hyundai', vehicle: 'Hyundai County 29-seat bus, 2022 model, air conditioned', origin: 'South Korea', lead: 'Available from 1 December 2026', warranty: 'Replacement bus within 6 hours', payment: 'Monthly in advance', omit: null, incl: 'Driver, fuel, insurance, maintenance.', excl: 'Salik, and driver overtime after 10 hours a day at AED 60 per hour.' },
      { label: 'Mussafah Fleet Solutions', factor: 0.90, brand: 'Tata', vehicle: 'Tata 32-seat bus, 2023 model, air conditioned', origin: 'India', lead: 'Available from 15 January 2027 (bus on another contract until then)', warranty: 'Replacement bus within 4 hours', payment: 'Monthly in advance', omit: null, incl: 'Driver with Abu Dhabi bus licence, fuel, Salik, insurance, maintenance.', excl: 'None.' },
    ],
    specRows: (s) => [['Vehicle', s.vehicle], ['Route and passengers', '28 staff, Mussafah Industrial Area to Al Reem Island, Abu Dhabi'],
      ['Trips', '2 a day, 06:30 and 17:30, Sunday to Thursday'], ['Contract', '6 months, fixed monthly rate'], ['Replacement vehicle', s.warranty],
      ['Insurance', 'Comprehensive vehicle and passenger insurance'], ['Inter-emirate travel', 'Within Abu Dhabi only; other emirates charged separately']],
    hold: {},
    holdBy: [
      [/passenger|route/, '28 staff; Mussafah Industrial Area to Al Reem Island, Abu Dhabi, and back'],
      [/vehicle_type|seating/, (sp) => sp.vehicle],
      [/age|air_cond/, (sp) => `${/(\d{4}) model/.exec(sp.vehicle)?.[1] || '2023'} model, fully air conditioned`],
      [/trip|schedule/, '2 trips a day: 06:30 from Mussafah, 17:30 from Al Reem Island, Sunday to Thursday'],
      [/driver|licen|permit/, 'Driver with an Abu Dhabi bus driving licence and passenger transport permit, included'],
      [/fuel/, (sp) => /fuel/i.test(sp.incl || '') ? 'Fuel included in the monthly rate' : 'Fuel not included: charged at actual cost'],
      [/replacement|service_level|response/, (sp) => sp.warranty],
      [/insurance/, 'Comprehensive vehicle and passenger insurance included'],
      [/duration|pricing/, '6 months, fixed monthly rate'],
      [/exclusion/, (sp) => sp.excl],
      [/inter_emirate|emirate/, 'Within Abu Dhabi only; trips to other emirates charged separately'],
      [/payment/, (sp) => sp.payment],
    ],
  },
};

// ── the drawing and the BOQ of journey 2 ───────────────────────────────────────────────────────────────────────────
export function villaHvacDrawingHtml() {
  const room = (x, y, w, h, name, area, tag, diff) => {
    let s = `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="#111" stroke-width="3"/>`;
    s += `<text x="${x + 10}" y="${y + 24}" font-size="15" font-weight="700">${name}</text><text x="${x + 10}" y="${y + 42}" font-size="12">${area} m²</text>`;
    if (tag) s += `<rect x="${x + w - 110}" y="${y + 8}" width="100" height="26" fill="#e8f1fb" stroke="#1f5f9f"/><text x="${x + w - 102}" y="${y + 26}" font-size="13" font-weight="700" fill="#1f5f9f">${tag}</text>`;
    for (let i = 0; i < diff; i++) { const dx = x + 30 + (i % 3) * ((w - 60) / 2.4), dy = y + h - 60 - Math.floor(i / 3) * 50; s += `<rect x="${dx}" y="${dy}" width="22" height="22" fill="none" stroke="#1f5f9f" stroke-width="2"/><line x1="${dx}" y1="${dy}" x2="${dx + 22}" y2="${dy + 22}" stroke="#1f5f9f"/><line x1="${dx + 22}" y1="${dy}" x2="${dx}" y2="${dy + 22}" stroke="#1f5f9f"/><text x="${dx + 26}" y="${dy + 16}" font-size="10" fill="#1f5f9f">SD</text>`; }
    s += `<path d="M ${x + 20} ${y + 70} H ${x + w - 30}" stroke="#7a9cc6" stroke-width="10" fill="none" opacity="0.55"/><text x="${x + 26}" y="${y + 64}" font-size="10" fill="#1f5f9f">GI DUCT 500x300</text>`;
    return s;
  };
  const gf = [room(40, 90, 330, 250, 'MAJLIS', 48, 'DSU-01 3.0TR', 5), room(370, 90, 360, 250, 'LIVING / DINING', 62, 'DSU-02 3.0TR', 6), room(40, 340, 330, 210, 'KITCHEN', 24, null, 2), room(370, 340, 360, 210, 'GUEST BEDROOM', 26, 'DSU-03 2.5TR', 4)].join('');
  const ff = [room(800, 90, 380, 250, 'MASTER BEDROOM', 44, 'DSU-04 2.5TR', 5), room(1180, 90, 330, 250, 'BEDROOM 2', 22, 'DSU-05 2.0TR', 3), room(800, 340, 380, 210, 'FAMILY LOUNGE', 38, 'DSU-06 2.0TR', 5), room(1180, 340, 330, 210, 'BEDROOM 3', 21, 'DSU-05 2.0TR', 3)].join('');
  const sched = [['DSU-01', 'Ducted split unit, inverter', '3.0 TR', 'Majlis', 1], ['DSU-02', 'Ducted split unit, inverter', '3.0 TR', 'Living / Dining', 1], ['DSU-03', 'Ducted split unit, inverter', '2.5 TR', 'Guest bedroom + kitchen', 1], ['DSU-04', 'Ducted split unit, inverter', '2.5 TR', 'Master bedroom', 1], ['DSU-05', 'Ducted split unit, inverter', '2.0 TR', 'Bedrooms 2 + 3', 1], ['DSU-06', 'Ducted split unit, inverter', '2.0 TR', 'Family lounge', 1], ['EF-01..05', 'Bathroom exhaust fan', '150 m³/h', 'Bathrooms', 5], ['TH-01..06', 'Wall thermostat', 'Digital', 'Each unit', 6]];
  const rows = sched.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('');
  return `<!doctype html><html><head><style>
    @page { size: A3 landscape; margin: 8mm } body { font-family: Arial, Helvetica, sans-serif; margin: 0 }
    .sheet { position: relative; border: 3px solid #111; height: 272mm; } .tb { position: absolute; right: 0; top: 0; bottom: 0; width: 70mm; border-left: 3px solid #111; padding: 6mm; font-size: 11px; }
    .tb b { display: block; font-size: 13px; margin-top: 3mm } table { border-collapse: collapse; font-size: 11px } td, th { border: 1px solid #333; padding: 3px 6px }
    th { background: #dde6f0 }</style></head><body><div class="sheet">
    <div style="position:absolute;left:6mm;top:4mm;font-size:18px;font-weight:700">GROUND FLOOR AND FIRST FLOOR - HVAC LAYOUT (DUCTED SPLIT SYSTEM)</div>
    <svg style="position:absolute;left:4mm;top:16mm" width="1220" height="476" viewBox="0 0 1540 600" font-family="Arial">
      <text x="40" y="70" font-size="16" font-weight="700">GROUND FLOOR PLAN</text><text x="800" y="70" font-size="16" font-weight="700">FIRST FLOOR PLAN</text>${gf}${ff}
      <text x="40" y="585" font-size="12">SCALE 1:100   ALL DUCT SIZES IN MM   UNITS CONCEALED ABOVE FALSE CEILING</text></svg>
    <div style="position:absolute;left:6mm;bottom:6mm"><div style="font-weight:700;font-size:13px;margin-bottom:2mm">EQUIPMENT SCHEDULE</div>
      <table><tr><th>TAG</th><th>DESCRIPTION</th><th>CAPACITY</th><th>AREA SERVED</th><th>QTY</th></tr>${rows}</table></div>
    <div style="position:absolute;left:150mm;bottom:6mm;font-size:11px"><div style="font-weight:700;font-size:13px;margin-bottom:2mm">LEGEND</div>
      SD - Supply diffuser 600x600 (38 nos total incl. return grilles RG)<br>RG - Return grille 600x300<br>TH - Wall thermostat<br>Refrigerant piping copper, insulated (approx. 120 m)<br>Condensate drain uPVC 32 mm (approx. 60 m)<br>GI ductwork with 25 mm insulation (approx. 160 m²)</div>
    <div class="tb"><b>CONSULTANT</b>ZZ DEMO MEP CONSULTANTS<br>Office 000, ZZ Tower, Dubai<br>Tel +971 4 000 0000<br>MOB +971 50 000 0094<br>zz.mep@example.invalid
      <b>CLIENT</b>ZZ DEMO PRIVATE VILLA<br>Mr. ZZ Demo Owner<br>Plot 000-0000, Al Barsha South<b>PROJECT</b>G+1 PRIVATE VILLA - MEP WORKS
      <b>DRAWING</b>HVAC LAYOUT - GF AND FF<b>DRG NO.</b>M-101  REV 0<b>DATE</b>01/11/2026<b>NOTE</b>ZZ DEMO FIXTURE - NOT A REAL PROJECT</div>
  </div></body></html>`;
}
export const J2_BOQ = [
  [1, 'Ducted split unit 3.0 TR, inverter, concealed (DSU-01, DSU-02)', 2, 'nos'],
  [2, 'Ducted split unit 2.5 TR, inverter, concealed (DSU-03, DSU-04)', 2, 'nos'],
  [3, 'Ducted split unit 2.0 TR, inverter, concealed (DSU-05, DSU-06)', 2, 'nos'],
  [4, 'GI ductwork with 25 mm thermal insulation, to SMACNA', 160, 'm2'],
  [5, 'Supply diffusers 600x600 and return grilles 600x300', 38, 'nos'],
  [6, 'Copper refrigerant piping with insulation', 120, 'm'],
  [7, 'uPVC condensate drain piping 32 mm', 60, 'm'],
  [8, 'Wall-mounted digital thermostat', 6, 'nos'],
  [9, 'Bathroom exhaust fan 150 m3/h with ducting', 5, 'nos'],
  [10, 'Testing, commissioning and air balancing', 1, 'lot'],
];

// ── a supplier's quotation, as his own document ─────────────────────────────────────────────────────────────────────
export function quoteLinesFor(J, s, requestLines) {
  const base = (requestLines && requestLines.length ? requestLines : J.defaultLines).map((l) => ({ description: String(l.description || l.item || '').trim(), qty: Number(l.qty ?? l.estimate ?? 1) || 1, unit: String(l.unit || 'nos') }));
  const lines = [];
  for (const l of base) {
    if (s.omit && s.omit.test(l.description)) continue;   // the deliberately missing scope item
    const d = l.description;
    const spec = J.specFor(d, s);
    const rate = Math.round(J.rate(d, l.unit.toLowerCase()) * s.factor);
    lines.push({ description: d, specification: spec, qty: l.qty, unit: l.unit, rate, amount: Math.round(rate * l.qty * 100) / 100, origin: s.origin });
  }
  return lines;
}
export function quotationHtml({ J, s, company, rfq, ref, lines }) {
  const sub = lines.reduce((a, l) => a + l.amount, 0), vat = Math.round(sub * 5) / 100, tot = Math.round((sub + vat) * 100) / 100;
  const rows = lines.map((l, i) => `<tr><td>${i + 1}</td><td class=d>${esc(l.description)}</td><td class=d>${esc(l.specification || '')}</td><td class=r>${l.qty}</td><td>${esc(l.unit)}</td><td class=r>${aed(l.rate)}</td><td class=r>${aed(l.amount)}</td></tr>`).join('');
  return { sub, vat, tot, html: `<!doctype html><html><head><style>
    body { font-family: Arial, Helvetica, sans-serif; font-size: 11px; color: #1a1a1a } td.d { white-space: nowrap; font-size: 9px; padding-right: 18px } h1 { font-size: 20px; margin: 0; color: #0c3c6b }
    .hd { display: flex; justify-content: space-between; border-bottom: 3px solid #0c3c6b; padding-bottom: 8px; margin-bottom: 12px }
    table { width: 100%; border-collapse: collapse; margin-top: 8px } th { background: #0c3c6b; color: #fff; text-align: left; padding: 5px } td { border-bottom: 1px solid #ccc; padding: 5px; vertical-align: top }
    .r { text-align: right } .tot td { border: none; padding: 3px 5px } .terms td { border: none; padding: 2px 4px } .terms td:first-child { font-weight: 700; width: 150px }
    .fx { margin-top: 18px; font-size: 9.5px; color: #777 }</style></head><body>
    <div class="hd"><div><h1>${esc(company)}</h1><div>Office 000, ZZ Business Centre, ${J.folder === '3_voice_note' ? 'Mussafah, Abu Dhabi' : 'Al Quoz, Dubai'}, UAE</div><div>Tel +971 4 000 0000 · sales@example.invalid · TRN 100000000000003</div></div>
      <div style="text-align:right"><div style="font-size:18px;font-weight:700">QUOTATION</div><div>Ref: ${esc(ref)}</div><div>Date: ${new Date().toLocaleDateString('en-GB')}</div><div>Your job: QuotesDone ${esc(rfq)}</div></div></div>
    <div><b>Subject:</b> ${esc(J.title)}</div>
    <table><tr><th>No</th><th>Description</th><th>Specification</th><th class=r>Qty</th><th>Unit</th><th class=r>Rate (AED)</th><th class=r>Amount (AED)</th></tr>${rows}</table>
    <table class="tot" style="width:45%;margin-left:55%"><tr><td>Subtotal</td><td class=r>AED ${aed(sub)}</td></tr><tr><td>VAT 5%</td><td class=r>AED ${aed(vat)}</td></tr><tr><td><b>Grand Total</b></td><td class=r><b>AED ${aed(tot)}</b></td></tr></table>
    <div style="margin-top:14px;font-weight:700">Terms and conditions</div>
    <table class="terms"><tr><td>Prices</td><td>In AED, excluding VAT (VAT 5% shown separately)</td></tr>
      <tr><td>Validity</td><td>30 days</td></tr><tr><td>Lead time</td><td>${esc(s.lead)}</td></tr><tr><td>Payment terms</td><td>${esc(s.payment)}</td></tr>
      <tr><td>Warranty</td><td>${esc(s.warranty)}</td></tr><tr><td>Country of origin</td><td>${esc(s.origin)}</td></tr>
      ${s.incl ? `<tr><td>Inclusions</td><td>${esc(s.incl)}</td></tr>` : ''}${(J.specRows ? J.specRows(s) : []).map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('')}<tr><td>Exclusions</td><td>${esc(s.excl)}</td></tr></table>
    <div style="margin-top:22px">For ${esc(company)}<br><br>Authorised signatory</div>
    <div class="fx">ZZ DEMO FIXTURE - this company does not exist and every figure is invented (QuotesDone evidence pack).</div></body></html>` };
}

// ── the request chat, driven as a customer drives it ───────────────────────────────────────────────────────────────
function nextAnswer(J, j, given) {
  const asked = [j?.next_question?.text || j?.next_question?.question || (typeof j?.next_question === 'string' ? j.next_question : ''), j?.assistant_message || '',
    ...(Array.isArray(j?.remaining_questions) ? j.remaining_questions : []).map((x) => typeof x === 'string' ? x : (x?.text || x?.question || x?.label || ''))].join(' \n ');
  // the question asked FIRST, then anything else still open
  const primary = asked.split(' \n ')[0] + ' ' + (j?.assistant_message || '');
  for (const src of [primary, asked]) {
    for (const [re, ans] of J.facts) if (!given.has(ans) && re.test(src)) { given.add(ans); return ans; }
  }
  return null;
}
async function intakeTurn(page, action, { timeoutMs = 360000 } = {}) {
  // the composer's mount-time carry_from:'portal' call is not this turn's answer (evidence re-run ea40c830: taking it as one
  // sent the next line before intake_id existed and opened a stray second intake)
  const first = page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake') && !/poll_turn_id|carry_from/.test(r.request().postData() || ''), { timeout: timeoutMs });
  await action();
  const res = await first.catch(() => null);
  let j = res ? await res.json().catch(() => ({})) : null;
  // a turn still owed the model's answer: the page polls until it lands (NewRequest watchTurn)
  if (j && j.pending && j.reask_turn_id) {
    const until = Date.now() + timeoutMs;
    while (Date.now() < until) {
      const p = await page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake') && /poll_turn_id/.test(r.request().postData() || ''), { timeout: 60000 }).catch(() => null);
      const pj = p ? await p.json().catch(() => ({})) : {};
      if (pj.polled && !pj.pending) { j = { ...j, assistant_message: pj.assistant_message, pending: false, polled_answer: true }; break; }
    }
  }
  await page.waitForTimeout(900);
  return j;
}
const qText = (x) => typeof x === 'string' ? x : (x?.text || x?.question || x?.label || '');

async function runChat(J, s, dir, ev) {
  const page = s.page; let n = 0;
  const shot = async (name) => { const f = join(dir, `${String(++n).padStart(2, '0')}_${name}.png`); await page.screenshot({ path: f }).catch(() => {}); ev.shots.push(f.split('/').pop()); return f; };
  const panelShot = async (name) => { const f = join(dir, `${String(++n).padStart(2, '0')}_${name}.png`); const el = page.locator('section[aria-label="New request"]').first(); await el.screenshot({ path: f }).catch(async () => { await page.screenshot({ path: f }).catch(() => {}); }); ev.shots.push(f.split('/').pop()); return f; };
  const T = ev.transcript;
  const record = (j, label) => {
    if (!j) { T.push({ role: 'system', text: `(${label}: no answer from inquiry_intake)` }); return; }
    T.push({ role: 'sales engineer', text: j.assistant_message || (j.pending ? '(still working on the answer)' : ''), status: j.status, readiness: j.readiness ?? j.readiness_score ?? null,
      category: j.category ?? null, next: qText(j.next_question), options: (j.next_question?.options || []).map(qText), open: (j.remaining_questions || []).map(qText) });
  };
  await openPortal(page, portalUrl('customer', 'en'), s.calls);
  await shot('customer_portal_signed_in');
  await page.getByRole('button', { name: /^New request/ }).first().click({ timeout: 20000 });
  const box = page.locator('#qd-intake-input'); await box.waitFor({ state: 'visible', timeout: 20000 });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await panelShot('request_chat_opened');
  T.push({ role: 'sales engineer', text: (await page.locator('section[aria-label="New request"]').first().innerText().catch(() => '')).split('\n').find((l) => /QuotesDone sales engineer/.test(l)) || '(greeting)' });
  const say = async (text, label) => {
    await box.fill(text); T.push({ role: 'customer', text });
    const j = await intakeTurn(page, () => box.press('Enter')); record(j, label); await panelShot(label); return j;
  };
  let j = null;
  if (J.voice) {
    j = await speak(page, J.opener, 'voice_note_1', dir, ev, panelShot, record);
  } else j = await say(J.opener, 'customer_first_message');
  if (J.attach) {
    for (const a of J.attach) {
      const input = page.locator(`input[type=file][aria-label="${a.input}"]`);
      T.push({ role: 'customer', text: `(attached ${a.name})` });
      const want = (r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes(a.action);
      const resP = page.waitForResponse(want, { timeout: 420000 }).catch(() => null);
      const turnP = page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake') && !/poll_turn_id|carry_from/.test(r.request().postData() || ''), { timeout: 480000 }).catch(() => null);
      await input.setInputFiles(a.path);
      const res = await resP; const rj = res ? await res.json().catch(() => ({})) : {};
      ev.attachments.push({ file: a.name, action: a.action, http: res?.status() ?? 0, boq_lines: rj?.boq?.boq?.length ?? 0, method: rj?.boq?.method ?? null, redaction_complete: rj?.redaction_complete ?? null,
        pages_in: rj?.redaction_pages_in ?? null, pages_out: rj?.redaction_pages_out ?? null, held: rj?.drawing_held ?? null, note: rj?.note ?? null, error: rj?.error ?? null });
      if (rj?.drawing_redacted_paths) ev.redacted_paths = rj.drawing_redacted_paths;
      await page.waitForTimeout(1500);
      await panelShot(`after_${a.kind}_read`);
      if ((rj?.boq?.boq?.length || 0) > 0) { const tj = await turnP; let jj = tj ? await tj.json().catch(() => ({})) : null; await page.waitForTimeout(1200); record(jj, `after ${a.kind}`); if (jj) j = jj; await panelShot(`sales_engineer_after_${a.kind}`); }
    }
  }
  const given = new Set();
  let heldTurns = 0;
  for (let turn = 0; turn < 10 && j && j.status !== 'ready'; turn++) {
    // a request held for the sales engineer (no trade decided) does not move by typing more: stop after two
    if (j.status === 'held' && !j.category && ++heldTurns > 2) break;
    let ans = nextAnswer(J, j, given);
    const opts = (j.next_question?.options || []).map(qText).filter(Boolean);
    if (!ans && opts.length) {
      // the intake offered complete answers: tap the suggested one, as a customer would
      const pick = j.next_question?.suggested ? String(j.next_question.suggested) : opts[0];
      const chip = page.locator('[role="group"] button').filter({ hasText: pick }).first();
      if (await chip.isVisible().catch(() => false)) {
        T.push({ role: 'customer', text: `(tapped "${pick}")` });
        j = await intakeTurn(page, () => chip.click()); record(j, 'chip'); await panelShot(`customer_tapped_answer_${turn + 1}`); continue;
      }
      ans = pick;
    }
    if (!ans) ans = /\?/.test(String(j.assistant_message || '') + qText(j.next_question)) ? "I am not sure about that one, please let the supplier advise." : (given.has(J.confirm) ? 'That is everything we know; for anything else, please let the supplier advise.' : J.confirm);
    given.add(ans);
    if (J.voice) j = await speak(page, [['en', ans]], `voice_note_${turn + 2}`, dir, ev, panelShot, record);
    else j = await say(ans, `customer_answer_${turn + 1}`);
  }
  ev.intake = { status: j?.status ?? null, readiness: j?.readiness ?? null, category: j?.category ?? null, brief: j?.brief ?? null, turns: T.filter((t) => t.role === 'customer').length };
  ev.chat_text = await page.locator('section[aria-label="New request"]').first().innerText().catch(() => '');
  if (j?.status !== 'ready') return null;
  await page.waitForTimeout(1200);
  await panelShot('ready_summary_before_send');
  const send = page.getByRole('button', { name: /Send to suppliers/ }).first();
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('create_inquiry'), { timeout: 180000 }).catch(() => null),
    send.click({ timeout: 20000 }),
  ]);
  const cj = res ? await res.json().catch(() => ({})) : {};
  T.push({ role: 'customer', text: '(pressed "Send to suppliers")' });
  await page.waitForTimeout(5000);
  await shot('request_sent');
  ev.create_inquiry = { http: res?.status() ?? 0, inquiry_id: cj.inquiry_id ?? cj.id ?? null, quotable_ids: cj.quotable_ids ?? null, matches: cj.matches ?? null, split: cj.split ?? null, scope_sent: JSON.parse(res?.request().postData() || '{}').scope_type ?? null, routing: cj.routing ?? null, error: cj.error ?? null };
  // ONE CONTRACTOR FOUND NOBODY (rulings 1021/1025): the portal asks "separate quotes per trade instead?" and only the
  // customer's yes re-posts it. The customer says yes, as a customer who wants quotes would.
  const yes = page.getByRole('button', { name: 'Yes, get separate quotes per trade' }).first();
  if (await yes.isVisible().catch(() => false)) {
    await shot('no_single_contractor_ask_separate_quotes');
    T.push({ role: 'sales engineer', text: (await page.locator('section').filter({ has: yes }).first().innerText().catch(() => '')).slice(0, 800) });
    const [rr] = await Promise.all([
      page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('repeat_inquiry'), { timeout: 180000 }).catch(() => null),
      yes.click(),
    ]);
    const rj = rr ? await rr.json().catch(() => ({})) : {};
    T.push({ role: 'customer', text: '(pressed "Yes, get separate quotes per trade")' });
    await page.waitForTimeout(4000); await shot('separate_quotes_sent');
    ev.create_inquiry.separate = { http: rr?.status() ?? 0, inquiry_id: rj.inquiry_id ?? rj.id ?? null, quotable_ids: rj.quotable_ids ?? null, child_ids: rj.child_ids ?? null, matches: rj.matches ?? null, error: rj.error ?? null };
    if (rj.inquiry_id ?? rj.id) { ev.create_inquiry.first_inquiry_id = ev.create_inquiry.inquiry_id; ev.create_inquiry.inquiry_id = rj.inquiry_id ?? rj.id; ev.create_inquiry.quotable_ids = rj.quotable_ids ?? rj.child_ids ?? [rj.inquiry_id ?? rj.id]; }
  }
  return ev.create_inquiry.inquiry_id;
}

/** One voice note through the chat's microphone: play it into getUserMedia, stop, wait for transcribe, send. */
async function speak(page, segments, name, dir, ev, panelShot, record) {
  const wav = join(dir, `${name}.wav`);
  const secs = voiceNote(wav, segments);
  ev.voice_notes.push({ file: `${name}.wav`, seconds: Math.round(secs * 10) / 10, script: segments.map(([l, t]) => `[${l}] ${t}`).join(' ') });
  // handed to the page as bytes: the site's CSP (connect-src) refuses any fetch to a host of ours, rightly
  await page.evaluate((b64) => { window.__qdVoiceB64 = b64; }, readFileSync(wav).toString('base64'));
  const mic = page.getByRole('button', { name: 'Speak your request' }).first();
  await mic.click({ timeout: 15000 });
  await page.waitForTimeout(1200);
  await panelShot(`${name}_recording`);
  await page.waitForTimeout(Math.max(500, secs * 1000 - 400));
  const tr = page.waitForResponse((r) => r.url().includes('/functions/v1/transcribe'), { timeout: 180000 }).catch(() => null);
  await page.getByRole('button', { name: 'Stop voice typing' }).first().click({ timeout: 15000 }).catch(() => mic.click());
  const res = await tr; const tj = res ? await res.json().catch(() => ({})) : {};
  ev.transcriptions.push({ note: name, http: res?.status() ?? 0, ok: tj.ok ?? false, text: tj.text ?? null, error: tj.error ?? null });
  await page.waitForTimeout(1200);
  const box = page.locator('#qd-intake-input');
  const typed = await box.inputValue().catch(() => '');
  await panelShot(`${name}_transcribed_into_the_box`);
  if (!typed.trim()) { ev.transcript.push({ role: 'customer', text: `(voice note ${name}: the transcription came back empty: ${JSON.stringify(tj).slice(0, 200)})` }); return null; }
  ev.transcript.push({ role: 'customer', text: `(voice note, ${Math.round(secs)} s) ${typed}`, voice: `${name}.wav` });
  const j = await intakeTurn(page, () => box.press('Enter'));
  record(j, name); await panelShot(`${name}_answered`);
  return j;
}

// voice: the browser has no speech engine (as Firefox), so the chat records and uses the server's transcribe; the
// microphone hands the page the voice note's audio.
const VOICE_INIT = () => {
  try { Object.defineProperty(window, 'SpeechRecognition', { value: undefined, configurable: true }); Object.defineProperty(window, 'webkitSpeechRecognition', { value: undefined, configurable: true }); } catch (_e) { /* */ }
  const md = navigator.mediaDevices;
  if (md) md.getUserMedia = async () => {
    const ac = new AudioContext(); await ac.resume().catch(() => {});
    const bin = atob(window.__qdVoiceB64 || ''); const u8 = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    const buf = u8.buffer;
    const ab = await ac.decodeAudioData(buf);
    const src = ac.createBufferSource(); src.buffer = ab; const dest = ac.createMediaStreamDestination(); src.connect(dest); src.start();
    return dest.stream;
  };
};

// ── one journey ────────────────────────────────────────────────────────────────────────────────────────────────────
async function journey(run, k) {
  const J = JOURNEYS[k]; const dir = join(OUT, J.folder); mkdirSync(dir, { recursive: true });
  const ev = M.journeys[k] = { title: J.title, trade: J.trade, shots: [], transcript: [], attachments: [], voice_notes: [], transcriptions: [], suppliers: [], quotes: [], files: [] };
  J.voice = k === '3';
  log(`journey ${k}: ${J.title}`);
  // the customer and five suppliers of the trade, each stating its services through the product
  const cust = await makeDemoCustomer(run, { label: J.label });
  ev.customer = { email: cust.email, name: cust.fullName, id: cust.customerId };
  const sups = [];
  for (const s of J.suppliers) {
    const sup = await makeDemoSupplier(run, { trade: J.trade, label: s.label, activity: J.title.split(',')[0] });
    if (J.serviceWords) {
      const rw = await call('supplier_api', sup.jwt, { action: 'services_rewrite', text: J.serviceWords, removed: [] });
      // 12 Nov 2026 (review of PR #1980): our own unique service names come back OFFERED ('exact_label', no model); he adds them
      const named = (rw.json?.meaning?.proposals || []).filter((p) => p.because === 'exact_label').map((p) => p.key);
      const st = await call('supplier_api', sup.jwt, { action: 'services_state' });
      const sv = await call('supplier_api', sup.jwt, { action: 'services_save_rewrite', trades: [...new Set([J.trade, ...(st.json?.checklist || []).map((c) => c.code)])],
        roles: st.json?.capability?.roles?.length ? st.json.capability.roles : ['contractor', 'installer', 'supplier'], services: named,
        implied: (rw.json?.implied || []).filter((i) => !i.removed).map((i) => i.key), removed: [], own_words: rw.json?.own_words || [], raw_text: J.serviceWords });
      sup.services = { stated: named, saved: sv.json?.ok === true };
      if (!named.length) finding(`journey ${k}`, `services_rewrite named no service for "${J.serviceWords}" (HTTP ${rw.status})`);
    }
    sups.push({ spec: s, fx: sup });
    ev.suppliers.push({ label: s.label, company: sup.company, lead_id: sup.leadId, email: sup.email, services: sup.services });
  }
  save();

  // the request, in the customer's browser
  const s = await signedInPage(BROWSER, cust, { lang: 'en', viewport: 'desktop' });
  if (J.voice) await s.page.addInitScript(VOICE_INIT);
  let inquiryId = null;
  try {
    if (k === '2') {
      const dPdf = await htmlPdf(villaHvacDrawingHtml(), { format: 'A3', landscape: true });
      writeFileSync(join(dir, 'customer_drawing_HVAC_layout_M-101.pdf'), dPdf); await pdfPictures(dPdf, join(dir, 'customer_drawing_HVAC_layout_M-101'));
      xlsx(join(dir, 'customer_BOQ_villa_HVAC.xlsx'), 'ZZ DEMO Villa, Al Barsha South - HVAC bill of quantities', J2_BOQ);
      J.attach = [
        { kind: 'drawing', name: 'customer_drawing_HVAC_layout_M-101.pdf', path: join(dir, 'customer_drawing_HVAC_layout_M-101.pdf'), input: 'Attach a drawing, photo or quotation', action: 'analyze_drawing' },
        { kind: 'boq', name: 'customer_BOQ_villa_HVAC.xlsx', path: join(dir, 'customer_BOQ_villa_HVAC.xlsx'), input: 'Attach a BOQ — Excel, CSV, PDF or a photo', action: 'analyze_document' },
      ];
    }
    inquiryId = await runChat(J, s, dir, ev);
  } catch (e) { finding(`journey ${k} chat`, String(e.stack || e.message).split('\n').slice(0, 3).join(' | ')); await s.page.screenshot({ path: join(dir, '99_chat_error.png') }).catch(() => {}); }
  writeFileSync(join(dir, 'chat_transcript.txt'), transcriptText(J, ev));
  if (!inquiryId) {
    if (!DRY) finding(`journey ${k}`, `the request chat did not post a request (intake ${JSON.stringify(ev.intake)})`);
    // DRY RUN ONLY: models are off, so the interview is held by design; the rest of the chain is walked on a request the
    // demo factory writes. Never in the real run.
    if (!DRY) { await s.ctx.close(); return ev; }
    const inq = await makeInquiry(run, { customer: { customerId: cust.customerId, locale: 'en' }, trade: J.trade, status: 'sent', rfqReady: false, summary: J.title, raw_input: Array.isArray(J.opener) ? J.opener.map((x) => x[1]).join(' ') : J.opener });
    inquiryId = inq.id; ev.fallback_inquiry = true;
    await write(`update public.inquiries set category = ${q(J.trade)}, trades = array[${q(J.trade)}], boq = ${q(JSON.stringify({ boq: J.defaultLines }))}::jsonb where id = ${q(inquiryId)}`, 'dry-run request');
  }
  run.ids.inquiries.add(String(inquiryId));
  for (const c of ev.create_inquiry?.quotable_ids || []) run.ids.inquiries.add(String(c));
  if (ev.create_inquiry?.first_inquiry_id) run.ids.inquiries.add(String(ev.create_inquiry.first_inquiry_id));
  // the part of a split request in this journey's trade is the one its five suppliers quote
  const qids = (ev.create_inquiry?.quotable_ids || []).map(String);
  let quotable = qids[0] || String(inquiryId);
  if (qids.length > 1) { const cats = await read(`select id::text id, category, trades from public.inquiries where id::text in (${qids.map(q).join(',')})`); quotable = (cats.find((c) => c.category === J.trade || (c.trades || []).includes(J.trade)) || cats[0] || { id: quotable }).id; ev.split_parts = cats; }
  ev.inquiry_id = inquiryId; ev.quotable_id = quotable;
  const row = (await read(`select id, rfq_no, category, trades, status, scope_type, summary, emirate, boq, spec->'customer_requirements' req, drawing_redacted_paths, public.fn_inquiry_is_demo(id) demo from public.inquiries where id = ${q(quotable)}`))[0] || {};
  ev.inquiry = { rfq_no: row.rfq_no, category: row.category, trades: row.trades, status: row.status, summary: row.summary, emirate: row.emirate, demo: row.demo, boq_lines: (row.boq?.boq || []).length, drawing_pages: (row.drawing_redacted_paths || []).length, requirements: row.req };
  writeFileSync(join(dir, 'request_as_stored.json'), JSON.stringify(row, null, 1));
  // the live matcher's choice, then the harness invites any of its five the matcher did not pick
  const matched = await read(`select m.supplier_id, l.company_name, l.is_demo, m.match_reason from public.inquiry_matches m join public.leads l on l.id = m.supplier_id where m.inquiry_id = ${q(quotable)}`);
  ev.matched_by_product = matched.map((m) => ({ id: m.supplier_id, company: m.company_name, demo: m.is_demo, reason: String(m.match_reason || '').slice(0, 160) }));
  if (matched.some((m) => m.is_demo !== true)) finding(`journey ${k}`, 'a REAL supplier was matched to a demo request');
  const mine = new Set(matched.map((m) => String(m.supplier_id)));
  ev.invited_by_harness = [];
  for (const x of sups) if (!mine.has(String(x.fx.leadId))) {
    await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(quotable)}, ${Number(x.fx.leadId)}, 'evidence pack: invited by the harness') on conflict do nothing`, 'evidence invitation');
    ev.invited_by_harness.push(x.spec.label);
  }
  save();
  const supDir = join(dir, 'supplier_view'); mkdirSync(supDir, { recursive: true });

  // what a supplier sees: the portal, and the inquiry in our template
  const S1 = sups[0].fx;
  {
    const sp = await signedInPage(BROWSER, S1, { lang: 'en', viewport: 'desktop' });
    try {
      await openPortal(sp.page, portalUrl('supplier', 'en'), sp.calls);
      await sp.page.getByRole('button', { name: /^Inquiries received/ }).first().click({ timeout: 20000 }).catch(() => {});
      const rowBtn = sp.page.locator(`#qd-inq-${quotable} > button`);
      await rowBtn.waitFor({ timeout: 30000 }).catch(() => {});
      await sp.page.screenshot({ path: join(dir, '40_supplier_inquiries_received.png') });
      await rowBtn.click().catch(() => {});
      await sp.page.locator(`#qd-inq-d-${quotable}`).waitFor({ timeout: 30000 }).catch(() => {});
      await sp.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      await sp.page.locator(`#qd-inq-d-${quotable}`).first().scrollIntoViewIfNeeded().catch(() => {});
      await sp.page.screenshot({ path: join(dir, '41_supplier_inquiry_detail.png'), fullPage: true });
      ev.supplier_view_text = (await sp.page.locator(`#qd-inq-d-${quotable}`).first().innerText().catch(() => '')).slice(0, 4000);
      const leaked = [cust.fullName, cust.email, cust.phone].filter((x) => x && ev.supplier_view_text.includes(x));
      if (leaked.length) finding(`journey ${k}`, `customer identity on the supplier's screen: ${leaked.join(', ')}`);
    } catch (e) { finding(`journey ${k} supplier view`, e.message.split('\n')[0]); }
    finally { await sp.ctx.close(); }
    const ip = await call('supplier_api', S1.jwt, { action: 'inquiry_pdf', inquiry_id: quotable, lang: 'en' }, 180000);
    if (ip.json?.url) {
      const b = await fetchBytes(ip.json.url); writeFileSync(join(dir, '42_inquiry_as_sent_to_suppliers.pdf'), b); await pdfPictures(b, join(supDir, 'inquiry_pdf'));
      ev.files.push('42_inquiry_as_sent_to_suppliers.pdf');
    } else finding(`journey ${k}`, `supplier_api inquiry_pdf gave no PDF: HTTP ${ip.status} ${ip.text}`);
    const docs = await call('supplier_api', S1.jwt, { action: 'inquiry_documents', inquiry_id: quotable });
    for (const d of docs.json?.documents || []) {
      if (d.kind === 'drawing_page' && d.url) writeFileSync(join(supDir, d.name), await fetchBytes(d.url).catch(() => Buffer.alloc(0)));
      if (d.kind === 'boq_csv' && d.content) writeFileSync(join(supDir, d.name), d.content);
    }
    ev.supplier_documents = (docs.json?.documents || []).map((d) => d.name);
  }

  // five quotations, each the supplier's own PDF uploaded through the portal's door
  const reqLines = (row.boq?.boq || []).filter((l) => l && (l.description || l.item));
  const qDir = join(dir, 'quotations'); mkdirSync(qDir, { recursive: true });
  for (const [i, x] of sups.entries()) {
    const sp = x.spec, sup = x.fx;
    const lines = quoteLinesFor(J, sp, reqLines);
    const ref = `ZZQ-${run.tag.toUpperCase()}-${k}${i + 1}`;
    const doc = quotationHtml({ J, s: sp, company: sup.company, rfq: row.rfq_no || quotable.slice(0, 8), ref, lines });
    const pdf = await htmlPdf(doc.html, { landscape: true });
    const fname = `Q${i + 1}_${sp.label.replace(/[^A-Za-z0-9]+/g, '_')}_supplier_quotation.pdf`;
    writeFileSync(join(qDir, fname), pdf);
    const rec = { n: i + 1, label: sp.label, company: sup.company, file: `quotations/${fname}`, ex_vat: doc.sub, vat: doc.vat, total: doc.tot, origin: sp.origin, lead: sp.lead, warranty: sp.warranty, omitted: sp.omit ? String(sp.omit) : null };
    ev.quotes.push(rec);
    try {
      if (sp.omit) { await chatQuote(sup, quotable, pdf, fname, sp, rec, reqLines.length ? reqLines : J.defaultLines, J, lines); save(); continue; }
      const images = (await rasterise(pdf)).map(({ mime, data }) => ({ mime, data }));
      const ex = await call('supplier_api', sup.jwt, { action: 'extract_quote', inquiry_id: quotable, images, original: { b64: pdf.toString('base64'), filename: fname, mime: 'application/pdf' } }, 240000);
      rec.extract = { http: ex.status, ok: ex.json?.ok ?? false, code: ex.json?.code ?? null, read_by: ex.json?.proposal?.fallback_reason ? 'code (doc_read)' : 'model', amount: ex.json?.proposal?.amount ?? null, lines: (ex.json?.proposal?.line_items || []).length, masked: ex.json?.proposal?.masked_terms || [] };
      const pr = ex.json?.proposal || {};
      // QuoteForm.buildPayload: the read proposal, with any term the read left blank typed by the supplier
      const body = { action: 'submit_quote', inquiry_id: quotable, amount: Number(pr.amount ?? doc.sub), currency: 'AED', lead_time: pr.lead_time || sp.lead, notes: pr.notes || '', scope: pr.scope || pr.description_anonymized || J.title,
        conditions: pr.conditions || '', exclusions: pr.exclusions || sp.excl, validity: pr.validity || '30 days', payment_terms: pr.payment_terms || sp.payment, warranty: pr.warranty || sp.warranty,
        items: (pr.line_items && pr.line_items.length ? pr.line_items : lines.map((l) => ({ description: l.description, specification: l.specification, qty: l.qty, unit: l.unit, unit_price: l.rate, amount: l.amount, country_of_origin: l.origin }))),
        masked_terms: pr.masked_terms || null, source: 'upload', original_file_path: ex.json?.original_file_path, original_file_name: ex.json?.original_file_name,
        subtotal: pr.subtotal ?? undefined, vat_amount: pr.vat_amount ?? undefined, trn: pr.trn ?? undefined, vat_treatment: 'exclusive', price_ex_vat: Number(pr.subtotal ?? pr.amount ?? doc.sub) };
      if (!ex.json?.ok) finding(`journey ${k} quote ${i + 1}`, `extract_quote did not read the PDF: HTTP ${ex.status} ${ex.json?.code || ''} ${ex.text}`);
      const pre = await call('supplier_api', sup.jwt, { ...body, dry_run: true }, 180000);
      rec.preflight = { would_hold: pre.json?.would_hold ?? null, missing: (pre.json?.spec_missing || []).map((m) => m.attr), would_accept: pre.json?.would_accept ?? null };
      const sub = await call('supplier_api', sup.jwt, body, 240000);
      const qid = sub.json?.quote?.id ?? sub.json?.quote_id ?? (sub.json?.options || [])[0]?.quote_id ?? null;
      rec.quote_id = qid; rec.submit = { http: sub.status, accepted: sub.json?.accepted ?? null, held: sub.json?.held ?? null, code: sub.json?.code ?? null, missing: (sub.json?.missing || sub.json?.spec_missing || []).map((m) => m?.attr ?? m) };
      if (qid) run.ids.quotes.add(String(qid));
      // the review refused the form (a BOQ line unpriced, a quantity that differs): the portal sends him to the
      // sales engineer's quotation chat, where he explains it
      if (qid && sub.json?.accepted) rec.cleared_by = 'accepted at upload (no hold)';
      if (!qid && sub.json?.code === 'quote_review_changes') { rec.via_form_refused = sub.json?.review_issues || null; await chatQuote(sup, quotable, pdf, fname, sp, rec, reqLines.length ? reqLines : J.defaultLines, J, lines); save(); continue; }
      if (qid && sub.json?.held) {
        // the hold desk, as the supplier uses it: state each named detail, approve the regenerated quotation; if the
        // approval names more details, he states those too (at most three rounds)
        rec.hold_rounds = [];
        for (let round = 0; round < 3; round++) {
          const h = await call('supplier_api', sup.jwt, { action: 'spec_hold', quote_id: qid });
          const L = {}, Tm = {};
          for (const l of h.json?.schema?.lines || []) for (const f of l.fields) if (f.missing || !f.value) (L[l.line_no] ||= {})[f.attr] = holdValue(J, sp, f, lines[l.line_no - 1]);
          const TF = { delivery: sp.lead, lead_time: sp.lead, installation_included: 'yes', installation_detail: 'Included as quoted', warranty_period: /\d+\s*(year|month|week|day)/i.test(sp.warranty) ? sp.warranty : '6 months, the full contract period', warranty_coverage: sp.warranty, price_ex_vat: String(doc.sub), validity: '30 days', payment_terms: sp.payment };
          for (const t of h.json?.schema?.terms || []) Tm[t.attr] = TF[t.attr] ?? (t.type === 'number' ? '1' : (t.options?.[0] ?? 'As per the quotation'));
          const asked = (h.json?.schema?.lines || []).flatMap((l) => l.fields.filter((f) => f.missing || !f.value).map((f) => `line ${l.line_no}: ${f.attr}`)).concat((h.json?.schema?.terms || []).map((t) => `term: ${t.attr}`));
          const f1 = await call('supplier_api', sup.jwt, { action: 'spec_fill', quote_id: qid, values: { lines: L, terms: Tm } }, 180000);
          const ap = f1.json?.complete ? await call('supplier_api', sup.jwt, { action: 'spec_approve', quote_id: qid, confirm: true }, 180000) : null;
          const r = { asked, lines: L, terms: Tm, fill: { http: f1.status, complete: f1.json?.complete ?? null, missing: (f1.json?.missing || []).map((m) => m?.attr ?? m), errors: f1.json?.errors ?? f1.json?.error ?? null },
            approve: ap ? { http: ap.status, released: ap.json?.released ?? null, code: ap.json?.code ?? null, missing: (ap.json?.missing || []).map((m) => `${m?.line_no ? 'line ' + m.line_no + ' ' : ''}${m?.attr ?? m}`), review: (ap.json?.review_issues || []).map((x) => x.code) } : null };
          r.form_fields = (h.json?.schema?.lines || []).map((l) => ({ line: l.line_no, fields: l.fields.map((f) => `${f.attr}${f.options ? '[' + f.options.slice(0, 6).join('/') + ']' : ''}${f.missing ? '*' : ''}`) }));
          r.hold_missing_before = (h.json?.hold?.missing || []).map((m) => `${m.line_no ? 'line ' + m.line_no + ' ' : ''}${m.attr}`);
          r.line_specifications = lines.map((l, k) => `line ${k + 1}: ${l.specification}`);
          const hh = await call('supplier_api', sup.jwt, { action: 'spec_hold', quote_id: qid });
          r.hold_after = { state: hh.json?.hold?.state ?? null, missing: (hh.json?.hold?.missing || []).map((m) => `${m.line_no ? 'line ' + m.line_no + ' ' : ''}${m.attr}: ${String(m.label_en || '').slice(0, 160)}`) };
          rec.hold_rounds.push(r);
          rec.hold_desk = { asked, complete: r.fill.complete, released: r.approve?.released ?? null };
          if (r.approve?.released) rec.cleared_by = `hold desk, round ${round + 1} (spec_fill + spec_approve)`;
          if (r.approve?.released || !asked.length || !f1.json?.complete) break;
        }
        if (!rec.hold_desk?.released) finding(`journey ${k} quote ${i + 1}`, `the hold desk did not release it: ${JSON.stringify(rec.hold_rounds.slice(-1)[0]?.approve || rec.hold_rounds.slice(-1)[0]?.fill).slice(0, 300)}`);
      }
    } catch (e) { finding(`journey ${k} quote ${i + 1}`, e.message.split('\n')[0]); }
    save();
  }
  // the quotations as the customer sees them (our template, with the sales engineer's notes)
  const live = await read(`select id::text id, supplier_id, status, quote_amount, review_notes from public.quotes where inquiry_id = ${q(quotable)} order by quote_amount`);
  ev.live_quotes = live.map((r) => ({ id: r.id, supplier_id: r.supplier_id, status: r.status, amount: Number(r.quote_amount), notes: r.review_notes }));
  for (const r of live) run.ids.quotes.add(r.id);
  for (const rec of ev.quotes) {
    if (!rec.quote_id) continue;
    const r = await call('customer_api', cust.jwt, { action: 'quote_pdf', quote_id: rec.quote_id, lang: 'en' }, 180000);
    if (r.json?.url) { const b = await fetchBytes(r.json.url); const f = `quotations/Q${rec.n}_as_the_customer_sees_it.pdf`; writeFileSync(join(dir, f), b); rec.customer_pdf = f; }
    else rec.customer_pdf_error = `HTTP ${r.status} ${r.text}`;
  }
  save();

  // the comparison: in the portal, and the report PDF
  const cmp = await call('quote_compare', cust.jwt, { inquiry_id: quotable, lang: 'en' }, 240000);
  const A = cmp.json?.analysis || null;
  writeFileSync(join(dir, 'comparison_analysis.json'), JSON.stringify(cmp.json || {}, null, 1));
  ev.comparison = { http: cmp.status, ok: cmp.json?.ok ?? false, degraded: cmp.json?.degraded ?? false, top3: summariseTop(A, ev) };
  try {
    await openPortal(s.page, portalUrl('customer', 'en', `?request=${inquiryId}`), s.calls);
    await s.page.waitForTimeout(4000);
    const card = s.page.locator(`[id="inq-${inquiryId}"]`).first();
    await card.scrollIntoViewIfNeeded().catch(() => {});
    await s.page.screenshot({ path: join(dir, '50_customer_request_with_quotes.png') });
    const cmpBtn = s.page.getByRole('button', { name: /compare/i }).first();
    if (await cmpBtn.isVisible().catch(() => false)) { await cmpBtn.click().catch(() => {}); await s.page.waitForTimeout(8000); }
    await s.page.waitForLoadState('networkidle', { timeout: 60000 }).catch(() => {});
    await s.page.screenshot({ path: join(dir, '51_customer_request_full_page.png'), fullPage: true });
    // the comparison block alone, readable at full size
    const block = s.page.locator('div, section').filter({ has: s.page.getByText(/^(Expert comparison report|Comparison by our rules)$/) }).filter({ hasText: 'Top picks' }).last();
    if (await block.count()) { await block.scrollIntoViewIfNeeded().catch(() => {}); await block.screenshot({ path: join(dir, '51_customer_comparison_top3.png') }).catch((e) => finding(`journey ${k} comparison crop`, e.message.split('\n')[0])); }
    else finding(`journey ${k} comparison crop`, 'no comparison block with "Top picks" on screen');
  } catch (e) { finding(`journey ${k} comparison screen`, e.message.split('\n')[0]); }
  const cp = await call('customer_api', cust.jwt, { action: 'compare_pdf', inquiry_id: quotable, lang: 'en' }, 240000);
  const cpu = cp.json?.url || cp.json?.pdf_url || cp.json?.file_url;
  if (cpu) { const b = await fetchBytes(cpu); writeFileSync(join(dir, '52_comparison_report.pdf'), b); await pdfPictures(b, join(dir, '52_comparison_report')); ev.files.push('52_comparison_report.pdf'); }
  else finding(`journey ${k}`, `compare_pdf gave no PDF: HTTP ${cp.status} ${cp.text}`);
  save();

  // the reveal, in Stripe TEST mode, of the sales engineer's first pick
  const pickId = ev.comparison.top3?.[0]?.quote_id || live.find((r) => r.status !== 'draft' && r.status !== 'held')?.id;
  if (pickId) await reveal(cust, s, pickId, inquiryId, dir, ev, k);
  else finding(`journey ${k}`, 'no live quote to reveal');
  await s.ctx.close();
  save();
  return ev;
}

/** The quotation chat (Inquiries received -> "Send your quotation to the sales engineer"): upload the file, answer
 *  each point the review raises in words (an unpriced BOQ line is declared excluded, by the client), let the
 *  sales engineer generate the standardised quotation, submit. */
async function chatQuote(sup, quotable, pdf, fname, sp, rec, reqLines, J, sLines = []) {
  rec.via = 'quotation chat (supplier_api review_*)';
  const C = rec.chat = [];
  const settle = async (r) => { let v = r; for (let i = 0; i < 40 && (v.json?.reviewing || v.json?.state === 'reviewing'); i++) { await sleep(6000); v = await call('supplier_api', sup.jwt, { action: 'review_thread', inquiry_id: quotable }); } return v; };
  const note = (what, v) => C.push({ what, http: v.status, state: v.json?.state ?? null, open: (v.json?.open_requests || []).filter((o) => o.kind !== 'choice').map((o) => `${o.code}${o.boq_line ? '@' + o.boq_line : ''}: ${o.label_en}`), error: v.json?.code || v.json?.error || null,
    said: (v.json?.messages || []).filter((m) => m.role === 'sales_engineer').slice(-1).map((m) => m.body_en)[0] || null });
  let v = await call('supplier_api', sup.jwt, { action: 'review_start', inquiry_id: quotable }, 180000); note('start', v);
  v = await settle(await call('supplier_api', sup.jwt, { action: 'review_upload', inquiry_id: quotable, file: { b64: pdf.toString('base64'), filename: fname, mime: 'application/pdf' } }, 240000)); note('upload', v);
  for (let cycle = 0; cycle < 2; cycle++) {
  for (let i = 0; i < 4 && v.json?.state === 'changes_requested'; i++) {
    const open = (v.json?.open_requests || []).filter((o) => o.kind !== 'choice');
    const ans = open.map((o) => {
      const l = String(o.label_en || '');
      if (o.code === 'line_items' || /itemised lines/i.test(l)) return sLines.map((x, k) => `line ${k + 1} specification: ${x.specification}`).join('. ');
      if (o.code === 'boq_line_not_priced' && o.boq_line) return `BOQ line ${o.boq_line} excluded — by the client (${String((reqLines[o.boq_line - 1] || {}).description || 'as stated in our exclusions').slice(0, 60)})`;
      if (/quantity/i.test(l) && o.boq_line) return `BOQ line ${o.boq_line} quantity — as per the BOQ`;
      if (/unit/i.test(l) && o.boq_line && o.code === 'unit_mismatch') return `BOQ line ${o.boq_line} unit — as per the BOQ`;
      if (o.code === 'vat_basis' || /VAT/.test(l)) return 'prices exclude VAT';
      if (o.code === 'validity') return 'validity 30 days';
      if (o.code === 'delivery' || /lead time|delivery/i.test(l)) return `lead time ${sp.lead}`;
      if (o.code === 'installation_included') return /supply only/i.test(sp.excl || '') ? 'supply only' : 'installation included';
      if (o.code === 'warranty_period') return /\d+\s*(year|month|week|day)/i.test(sp.warranty) ? `warranty ${sp.warranty}` : 'warranty 6 months, the full contract period';
      if (o.code === 'warranty_coverage') return `warranty covers ${sp.warranty}`;
      if (o.code === 'payment_terms' || /payment/i.test(l)) return `payment terms ${sp.payment}`;
      // "state the exact X (for example: "line 2 X: …")": answered in exactly that form
      const ex = /for example:\s*"([^"]+?)\s*[:…]/.exec(l);
      if (ex) {
        const n = Number(/^line (\d+)/i.exec(ex[1])?.[1] || o.line_no || 1);
        const what = ex[1].replace(/^line \d+\s*/i, '');
        return `${ex[1]}: ${holdValue(J, sp, { attr: what.replace(/\W+/g, '_').toLowerCase(), label_en: what }, sLines[n - 1])}`;
      }
      return null;
    }).filter(Boolean);
    if (!ans.length) break;
    v = await settle(await call('supplier_api', sup.jwt, { action: 'review_message', inquiry_id: quotable, text: [...new Set(ans)].join('. ') }, 240000)); note(`reply ${i + 1}: ${[...new Set(ans)].join('. ').slice(0, 200)}`, v);
  }
  if (v.json?.state === 'awaiting_choice') { v = await settle(await call('supplier_api', sup.jwt, { action: 'review_choose', inquiry_id: quotable, choice: 'generate' }, 240000)); note('choose generate', v); }
  if (v.json?.state === 'ready_to_submit') { v = await settle(await call('supplier_api', sup.jwt, { action: 'review_submit', inquiry_id: quotable }, 240000)); note('submit', v); }
  if (v.json?.state !== 'changes_requested') break;
  }
  const ids = v.json?.submitted_quote_ids || [];
  rec.quote_id = ids[0] || null; rec.submit = { via: 'review_submit', state: v.json?.state ?? null, quote_ids: ids };
  if (ids.length) rec.cleared_by = 'quotation chat (review_message, review_choose generate, review_submit)';
  for (const id of ids) RUN_REF.ids.quotes.add(String(id));
  if (!ids.length) finding('quotation chat', `${sp.label}: not submitted, state ${v.json?.state} ${JSON.stringify(C.slice(-1)).slice(0, 300)}`);
}

/** What the supplier types on the hold desk for one detail: the journey's own answer for it, else what his quotation states. */
function holdValue(J, sp, f, line) {
  const a = `${f.attr} ${f.label_en || ''}`.toLowerCase(), desc = line?.description || '';
  if (/specification/.test(a) && line?.specification) return `${line.specification}`;
  if (f.options?.length) {   // a field with choices takes one of them: the closest to what his quotation states
    const want = `${J.hold[f.attr] || ''} ${line?.specification || ''} ${desc}`.toLowerCase();
    return f.options.find((o) => want.includes(String(o).toLowerCase())) || f.options.find((o) => String(o).toLowerCase().split(/\W+/).some((w) => w.length > 3 && want.includes(w))) || f.options[0];
  }
  if (J.hold[f.attr] && J.hold[f.attr] !== 'As stated on the line') return J.hold[f.attr];
  for (const [re, v] of J.holdBy || []) if (re.test(a)) return typeof v === 'function' ? v(sp, desc) : v;
  if (/origin/.test(a)) return sp.origin;
  if (/brand|make|manufactur/.test(a)) return sp.brand || `Importer's own range, made in ${sp.origin}`;
  if (/roll_size/.test(a)) return '250 mm x 2800 mm panel';
  if (/capacity/.test(a) && /(\d+(?:\.\d+)?)\s*TR/i.test(desc)) return /(\d+(?:\.\d+)?)\s*TR/i.exec(desc)[1];
  if (f.options?.length) return f.options[0];
  if (f.type === 'number') return '1';
  return desc || 'As stated in the quotation';
}

function summariseTop(A, ev) {
  if (!A) return null;
  const all = A.all_quotes || [];
  const ranked = (A.top_3 || A.top3 || A.ranking || A.quotes || []).slice(0, 3);
  const qid = (x) => x?.quote_id || x?.id || all.find((a) => a.label === x?.label)?.quote_id || all.find((a) => a.label === x?.label)?.id || null;
  return ranked.map((x, i) => ({ rank: i + 1, label: x.label ?? null, quote_id: qid(x), price: x.price ?? x.amount ?? null, why: x.why ?? x.reason ?? x.rationale ?? x.summary ?? null, raw: x }));
}

async function reveal(cust, s, quoteId, inquiryId, dir, ev, k) {
  const R = ev.reveal = { quote_id: quoteId };
  const init = await call('stripe_checkout', cust.jwt, { action: 'element_init', quote_id: quoteId });
  R.mode = init.json?.mode ?? null; R.key_prefix = String(init.json?.publishable_key || '').slice(0, 8);
  if (!(init.json?.mode === 'test' && R.key_prefix.startsWith('pk_test'))) { finding(`journey ${k} reveal`, `not served the TEST key: ${JSON.stringify(init.json).slice(0, 200)}`); return; }
  const sess = await call('stripe_checkout', cust.jwt, { quote_id: quoteId, return_url: 'https://quotesdone.com/me' });
  if (!sess.json?.url) { finding(`journey ${k} reveal`, `no checkout session: ${sess.text}`); return; }
  const p = s.page;
  try {
    await p.goto(sess.json.url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await p.locator('#cardNumber').waitFor({ timeout: 60000 });
    await p.screenshot({ path: join(dir, '60_stripe_test_checkout.png') });
    await payHostedTestCheckout(p);
    await p.screenshot({ path: join(dir, '61_stripe_test_card_entered.png') });
    await p.waitForURL(/quotesdone\.(com|ae)/, { timeout: 120000 }).catch(() => {});
    await p.waitForTimeout(6000);
  } catch (e) { finding(`journey ${k} reveal`, e.message.split('\n')[0]); }
  const tx = await waitFor(async () => (await read(`select id, fee_status, reveal_fee, processing_fee, total_charged, quote_amount, doc_path, stripe_invoice_id is not null has_invoice from public.transactions where quote_id = ${q(quoteId)}`))[0], { timeoutMs: 120000 });
  R.tx = tx || null;
  try {
    await openPortal(p, portalUrl('customer', 'en', `?request=${inquiryId}&quote=${quoteId}`), s.calls);
    await p.waitForTimeout(5000);
    await p.screenshot({ path: join(dir, '62_customer_after_reveal_supplier_and_invoice.png'), fullPage: true });
  } catch (e) { finding(`journey ${k} after reveal`, e.message.split('\n')[0]); }
  const inv = await waitFor(async () => { const r = await call('reveal_invoice', cust.jwt, { quote_id: quoteId, doc: 'invoice', lang: 'en' }, 120000); return r.json?.url ? r : null; }, { timeoutMs: 120000, everyMs: 8000 });
  if (inv?.json?.url) { const b = await fetchBytes(inv.json.url); writeFileSync(join(dir, '63_invoice.pdf'), b); await pdfPictures(b, join(dir, '63_invoice')); ev.files.push('63_invoice.pdf'); }
  else finding(`journey ${k}`, 'reveal_invoice gave no invoice PDF');
}

function transcriptText(J, ev) {
  const lines = [`QuotesDone request chat - ${J.title}`, `Customer: ${ev.customer?.name} <${ev.customer?.email}> (ZZ DEMO identity)`, `Captured ${new Date().toISOString()} on ${SITE}${DRY ? ' (DRY RUN, models off)' : ''}`, ''];
  for (const t of ev.transcript) {
    lines.push(`${t.role.toUpperCase()}: ${t.text || ''}`);
    if (t.next) lines.push(`    question: ${t.next}`);
    if (t.options?.length) lines.push(`    answer buttons: ${t.options.join(' | ')}`);
    if (t.open?.length) lines.push(`    still open: ${t.open.join(' | ')}`);
    if (t.status) lines.push(`    [status ${t.status}${t.readiness != null ? `, readiness ${JSON.stringify(t.readiness)}` : ''}${t.category ? `, trade ${t.category}` : ''}]`);
    lines.push('');
  }
  if (ev.chat_text) lines.push('---- the chat panel as it read on screen at the end ----', ev.chat_text);
  return lines.join('\n');
}

// ── 4. a supplier registers, recorded ──────────────────────────────────────────────────────────────────────────────
async function registration(run) {
  const dir = join(OUT, '4_supplier_registration'); mkdirSync(dir, { recursive: true });
  const R = M.registration = { steps: [], shots: [] };
  const email = sinkAddress(run.tag, 'reg'); R.account_email = email;
  const company = `ZZ DEMO Falcon Glass and Aluminium ${run.tag.toUpperCase()}`; R.company = company;
  const mobile = `+9715000000${String(70 + Math.floor(Math.random() * 15)).padStart(2, '0')}`;
  const lic = join(dir, 'trade_licence.pdf'), prof = join(dir, 'company_profile.pdf'), cat = join(dir, 'product_catalogue.pdf');
  writeFileSync(lic, demoTradeLicence({ company, licenceNo: `ZZDEMO-${run.tag}-REG`.toUpperCase(), activity: 'Aluminium and Glass Works; Installing Curtain Walls' }));
  writeFileSync(prof, await htmlPdf(companyProfileHtml(company)));
  writeFileSync(cat, await htmlPdf(catalogueHtml(company)));
  const ctx = await BROWSER.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, locale: 'en-GB', recordVideo: { dir: join(dir, 'raw_video'), size: { width: 1440, height: 900 } } });
  await ctx.addInitScript(() => localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() })));
  if (process.env.QD_E2E_RUN_TAG) {
    const extra = { 'x-qd-e2e-run': process.env.QD_E2E_RUN_TAG, 'x-qd-e2e-secret': await internalCred() };
    await ctx.route((u) => carriesRunTag(u, BASE), (route) => route.request().method() === 'OPTIONS' ? route.continue() : route.continue({ headers: { ...route.request().headers(), ...extra } }));
  }
  const p = await ctx.newPage(); p.setDefaultTimeout(45000); const Mn = p.locator('main');
  let n = 0;
  const shot = async (name, full = false) => { const f = join(dir, `${String(++n).padStart(2, '0')}_${name}.png`); await p.screenshot({ path: f, fullPage: full }).catch(() => {}); R.shots.push(f.split('/').pop()); };
  const step = (name, ok, detail = '') => { R.steps.push({ name, ok: !!ok, detail }); log(`${ok ? 'PASS' : 'FAIL'} [registration] ${name} ${detail}`); };
  const slowType = async (loc, text) => { await loc.click(); await loc.fill(''); await loc.pressSequentially(text, { delay: 35 }); };
  try {
    await p.goto(`${SITE}/supplier`, { waitUntil: 'domcontentloaded' });
    await p.waitForTimeout(2500); await shot('supplier_landing_page');
    const cta = p.getByRole('link', { name: /Open the supplier portal/ }).first();
    if (await cta.isVisible().catch(() => false)) await cta.click(); else await p.goto(`${SITE}/portal`);
    await p.locator('#qd-supplier-signin').waitFor({ timeout: 30000 });
    const tab = p.locator('#qd-supplier-signin').getByRole('button', { name: /^Create account$/ }).first();
    if (await tab.isVisible().catch(() => false)) await tab.click();
    await p.waitForTimeout(800); await shot('sign_up_form');
    const box = p.locator('#qd-supplier-signin');
    await slowType(box.locator('input').first(), email);
    await shot('sign_up_email_typed');
    const tSend = Date.now();
    await box.getByRole('button', { name: /^Create my account$/ }).click();
    const codeBox = box.locator('input[autocomplete="one-time-code"]');
    const sent = await codeBox.waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
    await shot('verification_code_requested');
    step('sign-up sends the e-mail code', sent);
    const got = sent ? await readCode(email, tSend) : { code: null };
    R.code_mail = { from: got.from, subject: got.subject, last_event: got.last_event, queued_ms: got.queued_ms };
    step('the code e-mail is delivered (Resend sink) and read back', !!got.code, `${got.subject || ''} ${got.last_event || ''}`);
    if (!got.code) throw new Error('no verification code');
    await slowType(codeBox, got.code);
    await shot('verification_code_typed');
    // Founder ruling 1672 (12 Nov 2026): no company name and no trade are typed; Verify opens the registration form (the row is created
    // with no name and the licence names it). Verify therefore mounts the form, inside the held kyc read below.
    const readTok = () => p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('qd-portal-auth') || 'null'); return a?.access_token || localStorage.getItem('qd-sup-token'); } catch { return null; } });
    let tok = null;
    // THE FIXTURE MOBILE, RECORDED BEFORE THE FORM'S ONE READ (11 Nov 2026, customer_support; registration certification 3b). This
    // reloaded the page once kyc read verified (recordFixtureMobile); on production a reload after Create company landed in the
    // workspace, never the form, so the walk lost the licence upload. Now, as supplier_registration_certification.mjs does since
    // #1918: the form's kyc 'state' read is held while the fast writes are made around "Create company", and the form itself must
    // show "Mobile verified" (fixture_mobile.mjs recordFixtureMobileBeforeTheForm). The reserved mobile is refused before any SMS.
    let holdGate = null, lead = null;
    await p.route((u) => /\/functions\/v1\/kyc(?:\?|$)/.test(String(u)), async (route) => {
      let action = null; try { action = JSON.parse(route.request().postData() || '{}').action; } catch { /* not JSON */ }
      if (action === 'state' && holdGate) await holdGate;
      return route.fallback();
    });
    const fm = await recordFixtureMobileBeforeTheForm({
      holdFormRead: async () => { let rel; holdGate = new Promise((r) => { rel = r; }); return () => { holdGate = null; rel(); }; },
      openForm: async () => {
        await box.getByRole('button', { name: /^Verify and continue$|^Verify/ }).first().click();
        const regOk = await Mn.getByTestId('accept-terms').first().waitFor({ timeout: 40000 }).then(() => true).catch(() => false);
        await p.waitForTimeout(1000); await shot('verified_registration_form');
        step('the code verifies and the registration form opens, nothing typed', regOk && !(await Mn.getByRole('textbox', { name: /Company name/ }).count().catch(() => 0)));
        tok = await readTok();
        lead = await waitFor(async () => (await read(`select id, sector, company_name from public.leads where lower(claimed_by)=lower(${q(email)}) order by id desc limit 1`))[0] || null, { timeoutMs: 40000 });
        step('company created', !!lead, lead ? `lead ${lead.id}` : 'no lead row');
        if (lead) {
          R.lead_id = lead.id; run.ids.leads.add(String(lead.id));
          await write(`update public.leads set tags = array(select distinct unnest(coalesce(tags,'{}') || ARRAY['qd_demo','qd_run:${run.tag}'])) where id=${Number(lead.id)}`, 'tag the run\'s new lead');
        }
      },
      markVerified: () => write(`update public.leads set phone=${q(mobile)}, owner_phone_verified=true where lower(claimed_by)=lower(${q(email)})`, 'fixture mobile verified'),
      chooseWhatsapp: () => call('kyc', tok, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' }),
      kycState: async () => (await call('kyc', tok, { action: 'state' })).json,
      sendSms: async () => (await call('kyc', tok, { action: 'send_sms', phone: mobile })).json,
      formShowsVerified: () => Mn.getByText(/^Mobile verified$/).first().waitFor({ timeout: 25000 }).then(() => true).catch(() => false),
      sleep,
    });
    R.mobile = { number: mobile, sms_refused: fm.smsRefused, held_ms: fm.heldMs, detail: fm.detail };
    step('the fixture mobile is refused by kyc, recorded verified, and the form shows it', fm.ok && fm.smsRefused, fm.detail);
    await Mn.getByTestId('accept-terms').first().waitFor({ timeout: 40000 }).catch(() => {});
    await p.waitForTimeout(1200); await shot('registration_form', true);
    // the agreement, at its own step before the documents, with the accepting person's full name (ruling 1672)
    await Mn.getByTestId('accepter-name').fill('ZZ DEMO Evidence Person');
    await Mn.getByRole('checkbox', { name: /I accept the QuotesDone/ }).check();
    await Mn.getByTestId('accept-agreement').click();
    step('the agreement is accepted at its own step', await Mn.getByTestId('agreement-accepted').waitFor({ timeout: 20000 }).then(() => true).catch(() => false));
    await shot('supplier_agreement_accepted');
    // the trade licence: read on upload
    await Mn.locator('input[type=file]').nth(0).setInputFiles(lic);
    await Mn.getByText(/^Reading licence/).first().waitFor({ timeout: 10000 }).catch(() => {});
    await shot('trade_licence_reading');
    await Mn.getByText(/^Reading licence/).first().waitFor({ state: 'detached', timeout: 240000 }).catch(() => {});
    await p.waitForTimeout(1500); await shot('trade_licence_read', true);
    const licRow = (await read(`select license_doc_path, trade_license_no, license_expiry, licence_legal_name, license_authority from public.leads where id=${Number(lead?.id || 0)}`))[0];
    R.licence_read = licRow || null;
    step('the licence is stored and read', !!licRow?.license_doc_path, JSON.stringify(licRow || {}));
    await Mn.locator('input[type=file]').nth(1).setInputFiles(prof);
    await Mn.locator('input[type=file]').nth(2).setInputFiles(cat).catch(() => {});
    await p.waitForTimeout(1200); await shot('company_profile_and_catalogue_attached', true);
    // the Supplier Agreement: the link the form names, read, then accepted
    const agreeLink = Mn.getByRole('link', { name: /Supplier Agreement/ }).first();
    R.agreement_href = await agreeLink.getAttribute('href').catch(() => null);
    await Mn.getByRole('button', { name: /^Submit for approval/ }).click();
    const wsNav = p.getByRole('navigation').filter({ has: p.getByRole('button', { name: /^Inquiries received$/ }) }).first();
    const done = await wsNav.waitFor({ timeout: 180000 }).then(() => true).catch(() => false);
    await p.waitForTimeout(2500); await shot('submitted_workspace', true);
    step('Submit ends in the workspace', done);
    // what our agent made of the documents: proposed services with evidence and the licence check
    await p.reload({ waitUntil: 'domcontentloaded' }); await wsNav.waitFor({ timeout: 40000 }).catch(() => {});
    await wsNav.getByRole('button', { name: /^Services$/ }).click();
    const prop = Mn.getByTestId('proposed-services');
    const hasProp = await prop.waitFor({ timeout: 120000 }).then(() => true).catch(() => false);
    await p.waitForTimeout(1500);
    await shot('services_tab_what_our_agent_read', true);
    if (hasProp) { await prop.scrollIntoViewIfNeeded(); await p.waitForTimeout(600); await prop.screenshot({ path: join(dir, `${String(++n).padStart(2, '0')}_proposed_services_with_evidence_and_licence_check.png`) }); R.shots.push(`${String(n).padStart(2, '0')}_proposed_services_with_evidence_and_licence_check.png`); R.proposed_text = (await prop.innerText()).slice(0, 4000); }
    step('the Services tab shows proposed services from the documents', hasProp, hasProp ? '' : 'no proposed-services section within 120 s');
    R.profile_summary = (await Mn.getByTestId('profile-summary').innerText().catch(() => '')).slice(0, 3000);
    const ps = Mn.getByTestId('profile-summary');
    if (await ps.isVisible().catch(() => false)) { await ps.scrollIntoViewIfNeeded(); await p.waitForTimeout(500); await ps.screenshot({ path: join(dir, `${String(++n).padStart(2, '0')}_profile_summary_and_licence_check.png`) }).catch(() => {}); R.shots.push(`${String(n).padStart(2, '0')}_profile_summary_and_licence_check.png`); }
    // the trades read from his documents: tick every service of the first (his own trade), as a supplier does
    // 12 Nov 2026 (ruling 1647): no "Select all" on a trade; he opens "Browse all services of my trades" and ticks the boxes of his trade
    const browse = Mn.getByTestId('browse-trades');
    if (await browse.isVisible().catch(() => false)) {
      if (!(await browse.evaluate((el) => el.open).catch(() => true))) await browse.locator('summary').click().catch(() => {});
      for (const cb of await browse.locator('fieldset').first().locator('input[type=checkbox]').all().catch(() => [])) await cb.check().catch(() => {});
      await p.waitForTimeout(800);
    }
    for (const role of [/^Contractor$/, /^Installer \/ applicator$/]) { const cb = Mn.getByRole('checkbox', { name: role }).first(); if (await cb.isVisible().catch(() => false)) await cb.check().catch(() => {}); }
    await shot('services_ticked_and_roles_chosen', true);
    // tick the proposed services, add the supplier's own sentence, let the sales engineer rewrite it, confirm
    if (hasProp) {
      const all = prop.getByRole('button', { name: /tick all/i }).first();
      if (await all.isVisible().catch(() => false)) await all.click(); else for (const cb of await prop.locator('input[type=checkbox]').all()) await cb.check().catch(() => {});
      await shot('proposed_services_ticked');
    }
    const ta = Mn.locator('textarea').first();
    if (await ta.isVisible().catch(() => false)) {
      await slowType(ta, 'We supply and install aluminium sliding and casement windows, aluminium doors, shopfronts, glass curtain walls and skylights for villas and offices.');
      const rwBtn = Mn.getByRole('button', { name: /^Rewrite my services$/ });
      if (await rwBtn.isVisible().catch(() => false)) { await rwBtn.click(); await Mn.getByRole('button', { name: /Our sales engineer is reading it/ }).waitFor({ state: 'detached', timeout: 180000 }).catch(() => {}); }
      await p.waitForTimeout(1500); await shot('services_rewritten_by_the_sales_engineer', true);
    }
    const roleBoxes = Mn.locator('fieldset').filter({ hasText: /role/i }).locator('input[type=checkbox]');
    if ((await roleBoxes.count()) && !(await roleBoxes.locator(':checked').count().catch(() => 0))) await roleBoxes.first().check().catch(() => {});
    const confirm = Mn.getByRole('button', { name: /^(Confirm my services|Update my services)$/ });
    const canConfirm = await confirm.isEnabled().catch(() => false);
    if (canConfirm) await confirm.click();
    const saved = await Mn.getByText(/^Saved\. Your services are confirmed/).first().waitFor({ timeout: 60000 }).then(() => true).catch(() => false);
    await p.waitForTimeout(1200); await shot('services_confirmed');
    step('services confirmed', canConfirm && saved);
    let a2; const t0 = Date.now();
    for (;;) { a2 = (await read(`select approval_status, verified, licence_gate_reason, signed_terms_path, accepted_terms_version from public.leads where id=${Number(lead?.id || 0)}`))[0]; if (a2?.approval_status === 'approved' || Date.now() - t0 > 120000) break; await sleep(3000); }
    R.final = a2 || null;
    step('approved and verified', a2?.approval_status === 'approved' && a2?.verified === true, JSON.stringify(a2 || {}));
    // the Supplier Agreement he accepted, then back to his verified workspace
    await p.goto(`${SITE}${R.agreement_href && R.agreement_href.startsWith('/') ? R.agreement_href : '/supplier-agreement'}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
    await p.waitForTimeout(2500); await shot('supplier_agreement_page');
    for (let y = 0; y < 5; y++) { await p.mouse.wheel(0, 700); await p.waitForTimeout(500); }
    await p.goto(`${SITE}/portal`, { waitUntil: 'domcontentloaded' }); await wsNav.waitFor({ timeout: 40000 }).catch(() => {});
    await p.waitForTimeout(3000); await shot('verified_supplier_workspace', true);
    if (a2?.signed_terms_path) {
      run.ids.storage.push('signed-terms/' + a2.signed_terms_path);
      const { SERVICE } = await keys();
      const r = await fetch(`${BASE}/storage/v1/object/signed-terms/${a2.signed_terms_path.split('/').map(encodeURIComponent).join('/')}`, { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
      if (r.ok) writeFileSync(join(dir, 'signed_supplier_agreement_certificate.pdf'), Buffer.from(await r.arrayBuffer()));
    }
  } catch (e) { step('registration walk', false, String(e.message).split('\n')[0]); await shot('zz_failure', true); }
  finally {
    for (const d of await read(`select license_doc_path p from public.leads where id=${Number(R.lead_id || 0)} union all select company_profile_doc_path from public.leads where id=${Number(R.lead_id || 0)} union all select unnest(catalog_doc_paths) from public.leads where id=${Number(R.lead_id || 0)}`).catch(() => [])) if (d.p) run.ids.storage.push('supplier-docs/' + d.p);
    const vid = p.video(); await ctx.close();
    const raw = vid ? await vid.path().catch(() => null) : null;
    if (raw && existsSync(raw)) {
      copyFileSync(raw, join(dir, 'supplier_registration_recording.webm'));
      const ff = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', raw, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '23', '-movflags', '+faststart', join(dir, 'supplier_registration_recording.mp4')]);
      R.video = ff.status === 0 ? ['supplier_registration_recording.mp4', 'supplier_registration_recording.webm'] : ['supplier_registration_recording.webm'];
      spawnSync('rm', ['-rf', join(dir, 'raw_video')]);   // the raw recording is copied; disk is tight
    }
  }
  return R;
}
function companyProfileHtml(company) {
  return `<!doctype html><html><head><style>body{font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#222} h1{color:#0b4f6c;margin:0} h2{color:#0b4f6c;border-bottom:2px solid #0b4f6c;padding-bottom:3px;margin-top:18px} li{margin:3px 0}</style></head><body>
  <h1>${esc(company)}</h1><div>Company profile 2026 · Dubai, United Arab Emirates</div>
  <h2>About us</h2><p>We are an aluminium and glass contractor established in Dubai in 2012. We design, fabricate and install aluminium windows, doors and facades for villas, offices, schools and retail across the UAE, from our 4,000 m² workshop in Dubai Industrial City. Our team of 85 includes 6 facade engineers and 40 certified installers.</p>
  <h2>Our services</h2><ul><li>Supply and installation of aluminium sliding, casement and tilt-and-turn windows (thermal break systems)</li><li>Aluminium doors, sliding-folding doors and entrance doors</li><li>Glass curtain wall and structural glazing for commercial buildings</li><li>ACP cladding and aluminium louvres for facades</li><li>Aluminium pergolas and shades for villas</li><li>Frameless glass partitions and shower enclosures</li><li>Skylights and glass canopies</li><li>Maintenance and repair of aluminium windows and doors</li></ul>
  <h2>Selected projects</h2><ul><li>Curtain wall, 3,200 m², G+12 office building, Business Bay, Dubai (2024)</li><li>Windows and doors for 46 villas, Dubai South (2023)</li><li>ACP cladding and louvres, school campus, Sharjah (2022)</li></ul>
  <h2>Quality and approvals</h2><p>ISO 9001:2015 certified. Approved applicator for European thermal-break systems. Dubai Civil Defence approved for fire-rated glazing.</p>
  <p style="color:#888;font-size:10px;margin-top:30px">ZZ DEMO FIXTURE - this company does not exist; prepared for the QuotesDone evidence pack.</p></body></html>`;
}
function catalogueHtml(company) {
  return `<!doctype html><html><body style="font-family:Arial;font-size:12px"><h1 style="color:#0b4f6c">${esc(company)} - Product catalogue</h1>
  <table border="1" cellpadding="6" style="border-collapse:collapse;width:100%"><tr><th>Product</th><th>System</th><th>Use</th></tr>
  <tr><td>Thermal-break sliding window</td><td>70 mm, double glazed 6+12+6</td><td>Villas, apartments</td></tr><tr><td>Casement / tilt-and-turn window</td><td>65 mm thermal break</td><td>Villas, offices</td></tr>
  <tr><td>Sliding-folding door</td><td>Heavy duty, up to 6 panels</td><td>Villas</td></tr><tr><td>Unitised curtain wall</td><td>Structural glazing, low-e</td><td>Commercial towers</td></tr>
  <tr><td>ACP cladding</td><td>4 mm FR core</td><td>Facades</td></tr><tr><td>Aluminium louvres and pergolas</td><td>Powder coated</td><td>Villas, schools</td></tr></table>
  <p style="color:#888;font-size:10px">ZZ DEMO FIXTURE - not a real company.</p></body></html>`;
}

// ── the run ────────────────────────────────────────────────────────────────────────────────────────────────────────
// Imported (the document makers are reused by a local parse check), it only defines; run, it runs.
const MAIN = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (MAIN) await main();
async function main() {
mkdirSync(OUT, { recursive: true });
const guards = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
if (guards.length !== 3) { console.error('REFUSED: the demo guards are not installed: ' + guards.join(',')); process.exit(2); }
if (ONLY.includes('3') && (!VOICES || !existsSync(join(VOICES, 'en_GB-alan-medium.onnx')))) { console.error('REFUSED: journey 3 needs QD_PIPER_VOICES (piper voices en_GB-alan-medium and ar_JO-kareem-medium)'); process.exit(2); }
const run = await openRun({ capUsd: CAP, minutes: 120 }); RUN_REF = run;
M.tag = run.tag; log(`run tag ${run.tag}, out ${OUT}, ${DRY ? 'DRY (models off)' : `REAL (models on, cap USD ${CAP})`}`);
if (DRY) await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'dry run: models off');
M.window = (await read(`select run_tag, models_allowed, cap_usd, expires_at from public.rehearsal_window where run_tag = ${q('qd_run:' + run.tag)}`))[0];
save();
// A STOPPED RUN STILL COUNTS AND CLEANS (10 Nov 2026, real run 1 was stopped by hand and its notifications were never
// counted before teardown deleted them). SIGINT/SIGTERM run the same safety count, spend read and teardown as the end.
let finishing = null;
const finish = async (why) => {
  if (finishing) return finishing;
  finishing = (async () => {
    M.stopped = why;
    if (BROWSER) await BROWSER.close().catch(() => {});
    const ids = (s) => [...s].map(q).join(',') || 'null';
    const notes = await read(`select status, channel, count(*)::int n, bool_and(coalesce(to_email,'') ~* '@example\\.invalid$|@resend\\.dev$' or to_email is null) demo_addr from public.notifications
       where to_email like 'qd-${run.tag}-%' or to_email ilike '%qd-${run.tag}-%' or lead_id::text in (${ids(run.ids.leads)}) or inquiry_id::text in (${ids(run.ids.inquiries)}) or quote_id::text in (${ids(run.ids.quotes)}) group by 1, 2 order by 1, 2`).catch((e) => [{ error: e.message }]);
    const dispatched = notes.filter((r) => ['sent', 'queued', 'pending', 'sending'].includes(r.status));
    M.safety = { counted_at: new Date().toISOString(), before_teardown: true, notifications: notes, dispatched: dispatched.reduce((a, r) => a + r.n, 0), note: 'counted by status BEFORE teardown; the sign-up code e-mail of journey 4 goes to Resend\'s own sink (delivered+qd-<tag>-...@resend.dev) by design and is not a public.notifications row (login_otp sends it directly)' };
    M.spend = (await read(`select count(*)::int calls, round(coalesce(sum(cost_usd_reported),0)::numeric, 4) usd_reported, round(coalesce(sum(cost_aed),0)::numeric, 4) aed,
        json_agg(json_build_object('fn', fn, 'model', model_used, 'usd', cost_usd_reported, 'aed', cost_aed, 'ok', ok) order by occurred_at) rows from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`).catch((e) => [{ error: e.message }]))[0];
    save();
    log('safety', JSON.stringify({ dispatched: M.safety.dispatched, rows: notes }));
    log('spend', JSON.stringify({ calls: M.spend?.calls, usd: M.spend?.usd_reported, aed: M.spend?.aed }));
    if (!KEEP) {
      let closed = null;
      try { closed = await closeRun(run); } catch (e) { log('teardown retry', e.message); await sleep(60000); closed = await closeRun(run).catch((x) => ({ error: x.message })); }
      const sink = M.registration?.account_email ? await cleanSink(M.registration.account_email).catch((e) => ({ error: e.message })) : null;
      M.teardown = { removed: closed?.removed?.summary ?? closed?.error ?? null, leftovers: closed?.leftovers ?? null, sink };
    } else { await write(`update public.rehearsal_window set ended_at = now(), models_allowed = false where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'rehearsal window'); M.teardown = { kept: `node scripts/e2e/run.mjs --purge-tag ${run.tag}` }; }
    M.finished = new Date().toISOString(); save();
    log('teardown', JSON.stringify(M.teardown));
    log(`findings: ${M.findings.length}`); for (const f of M.findings) log(' -', f.where, f.what);
  })();
  return finishing;
};
for (const sig of ['SIGINT', 'SIGTERM']) process.once(sig, () => { log(`stopped by ${sig}: counting and tearing down`); finish(sig).finally(() => process.exit(1)); });
try {
  BROWSER = await launch();
  const origNew = BROWSER.newContext.bind(BROWSER);
  BROWSER.newContext = (o = {}) => origNew({ ...o, deviceScaleFactor: o.deviceScaleFactor ?? 2 });   // pictures a person will read
  for (const k of ['1', '2', '3']) if (ONLY.includes(k)) { try { await journey(run, k); } catch (e) { finding(`journey ${k}`, String(e.stack || e.message).split('\n').slice(0, 3).join(' | ')); } save(); }
  if (ONLY.includes('4')) { try { await registration(run); } catch (e) { finding('registration', String(e.stack || e.message).split('\n').slice(0, 3).join(' | ')); } save(); }
} finally {
  await finish('completed');
  process.exit(0);
}
}
