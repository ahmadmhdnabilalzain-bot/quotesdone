// scripts/e2e/journey_proof/personas/dry_run.mjs — A PERSONA JOURNEY, LOCALLY, FOR NOTHING. Seat: customer_support.
// Each customer persona (customers.mjs) talks to the REAL inquiry_intake handler run offline by intake_bridge.ts (Deno, every
// request it makes stubbed: nothing can leave the machine), played by the deterministic stub player (player.mjs
// stubComplete), with the platform's own model replaced by a faithful stand-in reader. The supplier personas
// (suppliers.mjs) then answer the request through stand-in doors that read their files locally. Every persona journey writes
// record.json, people.txt (the "Would a real person have got through?" section in plain text) and, with --pdf, the dossier on
// the QuotesDone template (dossier.ts). No database, no model, no network, USD 0.
//
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL node scripts/e2e/journey_proof/personas/dry_run.mjs \
//       [--personas villa_owner,facility_manager,arabic_mixed,impatient] [--out <dir>] [--pdf] [--latency replay|local]
//
// REPLY TIMES. The offline handler answers in milliseconds, which says nothing about a person's patience. By default
// (--latency replay) each platform reply is given the time the LIVE journey A of 15 Nov 2026 measured for the same turn
// (10.8 s, 11.2 s, ... 28.3 s; A_report.txt), and the record says so; --latency local records the offline time instead.
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';
import { CUSTOMERS, personaProblems } from './customers.mjs';
import { SUPPLIERS, playSupplier } from './suppliers.mjs';
import { createPlayer, stubComplete } from './player.mjs';
import { peopleSection, peopleText } from './report.mjs';
import { nameplatePhoto } from './artefacts.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../../../..');
/** The reply times the live journey A measured on 15 Nov 2026 (inquiry_intake, models on), turn by turn. */
export const LIVE_A_REPLY_S = [10.8, 11.2, 11.9, 21.9, 19.4, 20.2, 22.7, 20.4, 28.3, 23.7, 26.1, 20.0, 19.7];
export const LIVE_A_SOURCE = 'each reply given the time the live journey A of 15 Nov 2026 measured at the same turn (not this machine\'s)';
const MAX_TURNS = 30;

/** What a faithful reader records when the person said these facts (and sent these files). */
export function readingOf(persona, factIds = [], fileIds = []) {
  const reads = {}, req = {};
  for (const id of factIds) { const f = persona.facts.find((x) => x.id === id); if (!f) continue; Object.assign(reads, f.reads || {}); Object.assign(req, f.req || {}); }
  for (const id of fileIds) { const f = (persona.files || []).find((x) => x.id === id); if (f) Object.assign(reads, f.reads || {}); }
  return { reads, req };
}

/** The offline intake handler as a child process: send(turn) -> its answer. */
export function openBridge() {
  const child = spawn('deno', ['run', '--no-lock', '--node-modules-dir=none', '--allow-read=.', join(HERE, 'intake_bridge.ts')], { cwd: REPO, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, SUPABASE_ACCESS_TOKEN: '', SUPABASE_DB_URL: '' } });
  const waiting = []; const errs = [];
  createInterface({ input: child.stdout }).on('line', (l) => { const w = waiting.shift(); if (w) { try { w.ok(JSON.parse(l)); } catch (e) { w.no(e); } } });
  child.stderr.on('data', (d) => errs.push(String(d)));
  child.on('exit', (code) => { for (const w of waiting.splice(0)) w.no(new Error(`the intake bridge exited (${code}): ${errs.join('').slice(-600)}`)); });
  return {
    send: (o) => new Promise((ok, no) => { waiting.push({ ok, no }); child.stdin.write(JSON.stringify(o) + '\n'); }),
    close: () => { child.stdin.end(); child.kill(); },
    stderr: () => errs.join(''),
  };
}

/** The stand-in supplier doors of the dry run: nothing is submitted; files are read here, and the record says so. */
function dryDoors(dir) {
  const read = (bytes, mime) => {
    if (mime !== 'application/pdf') return null;   // no reader for a photo here: the live run sends it to the platform's
    const f = join(dir, `.read_${Date.now()}.pdf`); writeFileSync(f, bytes);
    const r = spawnSync('pdftotext', ['-layout', f, '-'], { encoding: 'utf8' }); spawnSync('rm', ['-f', f]);
    const t = r.status === 0 ? r.stdout : '';
    const tot = /Subtotal\s+AED\s+([\d,]+)/i.exec(t) || /AED\s+([\d,]+)/i.exec(t);
    return tot ? Number(tot[1].replace(/,/g, '')) : null;
  };
  return {
    message: async () => ({ http: null, said: null, not_run: true }),   // the quotation chat needs the platform: not claimed here
    upload: async ({ bytes, mime }) => {
      const amt = read(bytes, mime);
      return { http: null, read_amount: amt, typed_by_supplier: amt == null, quote_id: null, code: 'dry run: nothing was submitted to the platform', accepted: null, held: null };
    },
    afterSilence: async () => null,
  };
}

/** One persona journey, dry. */
export async function dryJourney(persona, { out, latency = 'replay', suppliers = Object.values(SUPPLIERS), pdf = false, log = console.log } = {}) {
  const pr = personaProblems(persona); if (pr.length) throw new Error('REFUSED: ' + pr.join('; '));
  const dir = join(out, `P_${persona.key}`); for (const d of ['', 'customer_files', 'quotations']) mkdirSync(join(dir, d), { recursive: true });
  const started = new Date().toISOString();
  const player = createPlayer({ persona, complete: stubComplete(persona) });
  const bridge = openBridge();
  const chat = []; let resp = null; let outcome = null; const findings = []; const exhibits = [];
  const stamp = (offset_s) => new Date(Date.parse(started) + offset_s * 1000).toISOString();
  let clock_s = 0;
  try {
    const op = player.opener();
    chat.push({ role: 'customer', text: op.text, at: stamp(clock_s) });
    const r0 = readingOf(persona, op.topics);
    let t0 = Date.now(); resp = await bridge.send({ text: op.text, lang: persona.lang, ...r0 });
    for (let i = 0; i < MAX_TURNS; i++) {
      if (!resp.ok) { findings.push({ severity: 'harness', step: '2', text: `the offline intake answered HTTP ${resp.http}: ${resp.error}` }); outcome = 'stopped'; break; }
      const local_s = Math.round((Date.now() - t0) / 100) / 10;
      const latency_s = latency === 'replay' ? LIVE_A_REPLY_S[Math.min(i, LIVE_A_REPLY_S.length - 1)] : local_s;
      clock_s += latency_s;
      const q = resp.next_question;
      const message = [resp.assistant_message, q?.text].filter(Boolean).join(' ');
      chat.push({ role: 'sales engineer', text: message || '(no message)', at: stamp(clock_s), reply_s: latency_s, options: (q?.options || []).map(String), status: resp.status });
      if (resp.status === 'ready') { outcome = 'ready'; break; }
      const t = await player.turn({ message, question: q, latency_s, status: resp.status });
      if (t.abandoned) { outcome = 'abandoned'; chat.push({ role: 'customer', text: `(left the chat: ${t.abandoned.reason})`, at: stamp(clock_s + 1) }); break; }
      if (t.file) {
        const bytes = await nameplatePhoto(); const f = `customer_files/${t.file}.jpg`; writeFileSync(join(dir, f), bytes);
        exhibits.push({ file: f, title: `The photo ${persona.label} sent`, why: 'A phone photo, as a real person sends one instead of a capacity.', attach: true, ours: false });
      }
      const text = t.tap || t.reply || '(sent a photo)';
      clock_s += 6;   // the person's own typing time, nominal
      chat.push({ role: 'customer', text: text + (t.file ? ' (sent a photo of the nameplate)' : ''), at: stamp(clock_s) });
      const rd = readingOf(persona, t.answered, t.file ? [t.file] : []);
      t0 = Date.now(); resp = await bridge.send({ text, lang: persona.lang, ...rd, not_sure: (t.not_sure || []).length > 0 && !t.file });
    }
    if (!outcome) outcome = 'not_ready';
  } finally { bridge.close(); }
  const final_details = resp?.details || {};
  // the suppliers, only once the request would have gone out
  const sup = [];
  if (outcome === 'ready') {
    for (const s of suppliers) {
      sup.push(await playSupplier(s, { doors: dryDoors(dir), job: { rfq: `DRY-${persona.key}`, lines: persona.job.lines },
        save: async (name, bytes) => { const f = `quotations/${name}`; writeFileSync(join(dir, f), bytes); exhibits.push({ file: f, title: `${s.label}: what he sent`, why: `${s.label} ${s.behaviour.replace(/_/g, ' ')}: his own file, exactly as he sent it.`, ours: false }); return f; } }));
    }
  }
  const people = peopleSection({ persona, turns: player.turns, abandoned: player.abandoned, outcome, final_details, suppliers: sup,
    mode: 'dry run: the deterministic stub person, the REAL inquiry_intake handler offline with a stand-in reader model; supplier doors are stand-ins (nothing submitted)',
    latency_source: latency === 'replay' ? LIVE_A_SOURCE : 'measured on this machine (offline, not comparable to live)', spend: player.spend });
  for (const p of people.problems) findings.push({ severity: 'harness', step: 'people', text: `turn ${p.n}: ${p.text}` });
  for (const r of people.repeats) findings.push({ severity: 'product', step: 'people', text: `asked again at turn ${r.n} what was already answered (${r.why}${r.first_asked_at ? `, first at turn ${r.first_asked_at}` : ''}): "${r.question}"` });
  for (const m of people.misunderstood) findings.push({ severity: 'looked_wrong', step: 'people', text: `turn ${m.n}: ${persona.label} did not understand "${m.question}"` });
  if (player.abandoned) findings.push({ severity: 'product', step: 'people', text: `${persona.label} left at turn ${player.abandoned.at}: ${player.abandoned.reason}` });
  const rec = {
    journey: { key: `P-${persona.key}`, title: persona.job.title, short: persona.short, how_made: `${persona.label} typed in his own words; the platform's real intake code answered (offline, dry run)`, site: 'local (offline)', started, finished: new Date().toISOString(), mode: 'dry (persona)', cap_usd: 0, estimate_usd: 0, run_tag: `dry-${persona.key}` },
    steps: [], sections: { s2: { how: 'The persona chat, as the stub person typed it and the real intake handler (offline) answered it. The platform\'s words here are the stand-in writer\'s, followed by the question card the real code chose.', turns: chat, questions: player.turns.filter((t) => t.question).map((t) => ({ text: t.question.text, why: null })), verdicts: [], gaps: [] }, people },
    findings, exhibits,
    stand_ins: [
      'The person is a ZZ DEMO persona played by the deterministic stub (player.mjs stubComplete): it answers from its hidden truth sheet only what was asked, and says "not sure" where the sheet says it does not know. The live run plays the same sheet with a model.',
      'The platform\'s chat is the REAL inquiry_intake handler run offline (intake_bridge.ts, every request it makes stubbed). Its interview model is a faithful stand-in reader that records what the person said under the right key; its reply writer is a stand-in voice. Which question is asked, when, and when the request is ready is the real code\'s.',
      latency === 'replay' ? `Reply times: ${LIVE_A_SOURCE}.` : 'Reply times: measured offline on this machine.',
      'Supplier doors are stand-ins: each supplier persona made its real file (PDF or photo); the PDF was read here with pdftotext; nothing was submitted to the platform, the quotation chat was not run, and no platform answer is claimed.',
      'A platform message with no question card is shown as the stand-in writer\'s words only. Live, the writer may ask in prose; here such a turn asks nothing, so a person who meets two of them in a row leaves (abandon.mjs "stuck"). Treat a "stuck" in the dry run as "the code chose no question", not as what a customer would read.',
    ],
  };
  writeFileSync(join(dir, 'record.json'), JSON.stringify(rec, null, 1));
  writeFileSync(join(dir, 'people.txt'), peopleText(people) + '\n');
  log(`\n=== ${persona.label}: ${people.headline}`);
  if (pdf) {
    const d = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=none', `--allow-read=${REPO},${out}`, `--allow-write=${out}`, join(HERE, '..', 'dossier.ts'), dir], { encoding: 'utf8', cwd: REPO, env: { ...process.env, SUPABASE_ACCESS_TOKEN: '' } });
    log('dossier', (d.stdout || '').trim(), (d.stderr || '').trim().slice(-300));
  }
  return { rec, people, dir };
}

const MAIN = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (MAIN) {
  const argv = process.argv.slice(2); const val = (f, d = null) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
  const keys = val('--personas', Object.keys(CUSTOMERS).join(',')).split(',').map((s) => s.trim()).filter(Boolean);
  for (const k of keys) if (!CUSTOMERS[k]) { console.error(`REFUSED: no persona ${k} (${Object.keys(CUSTOMERS).join(', ')})`); process.exit(2); }
  const out = resolve(val('--out', '/tmp/qd-journey-proof/personas-dry'));
  mkdirSync(out, { recursive: true });
  const all = [];
  for (const k of keys) { const r = await dryJourney(CUSTOMERS[k], { out, latency: val('--latency', 'replay'), pdf: argv.includes('--pdf') }); all.push(r); console.log(peopleText(r.people)); }
  console.log(`\n${all.length} persona journeys, dry, USD 0. Records in ${out}: ${all.map((r) => r.dir.split('/').pop()).join(', ')}`);
  if (!existsSync(out)) process.exit(1);
}
