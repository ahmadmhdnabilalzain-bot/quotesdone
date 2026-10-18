// IS WHAT main SAYS ACTUALLY RUNNING? Every source file of every function, not a sample.
//
// ── WHY THE SIGNATURE SAMPLE WAS REPLACED (13 Oct 2026, it_engineer) ─────────────────────────────
// The previous version took the 25 longest string literals of a function's index.ts and asserted
// each was present in the deployed bundle. Two overlapping main runs of deploy-functions.yml (#1382
// started 02:47, #1393 started 02:50) let the OLDER run finish last: at 02:52 it deployed
// supplier_portal v288 from the older tree over #1393's fix. This check reported nothing, because
// #1393's change was not among the 25 sampled strings, and it never looked at _shared at all.
//
// ── WHAT IT DOES NOW ─────────────────────────────────────────────────────────────────────────────
// GET /v1/projects/<ref>/functions/<slug>/body returns the deployed ESZIP (v2.x). Measured on
// supplier_portal: its sources section carries Deno's TRANSPILED JavaScript of every first-party
// module, and each module's source map carries the ORIGINAL TypeScript in sourcesContent. The original
// is compared, in full, with main's file after normalising line endings and trailing whitespace only;
// a module with no usable map falls back to comparing the transpiled text through norm().
// Remote modules (jsr:, npm:, https:) are dependency resolution, not this repo's code, and are
// not compared.
//
//   MATCH       every deployed first-party file equals main's
//   STALE       at least one differs or is absent on main; the files are listed
//   UNVERIFIED  the body could not be read or parsed; the reason is printed. Never counted as a pass.
//
// Exits 1 on any STALE (and on any UNVERIFIED, which is not evidence of parity). Read-only: GETs.
//
//   node scripts/verify_deploy_parity.mjs --all                 # every function in the repo
//   node scripts/verify_deploy_parity.mjs supplier_portal ...    # named functions
//   node scripts/verify_deploy_parity.mjs --since=HEAD~50        # functions touched in a window
import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import ts from 'typescript-js-api'; // TypeScript 7 (the native compiler) ships no JS API; the parser stays on 5.x

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const FN_DIR = 'supabase/functions';

/**
 * Parse an ESZIP v2.x buffer into Map<specifier, { text, original }> of the modules that carry source.
 * `text` is the ORIGINAL TypeScript when the module's source map carries it in sourcesContent
 * (original: true; measured on dropbox_backup 13 Oct: every first-party module does), else Deno's
 * transpiled JavaScript from the sources section (original: false).
 */
export function parseEszip(buf) {
  if (buf.toString('latin1', 0, 6) !== 'ESZIP2') throw new Error(`not an eszip v2 (magic ${JSON.stringify(buf.toString('latin1', 0, 8))})`);
  const minor = buf.toString('latin1', 6, 8);
  let p = 8;
  const u32 = () => { const v = buf.readUInt32BE(p); p += 4; return v; };
  let hashSize = 32; // v2.0/2.1: sha256 after each section
  if (minor !== '\0\0' && minor !== '.1') {
    const ol = u32();
    const opts = buf.subarray(p, p + ol); p += ol;
    hashSize = 0;
    for (let i = 0; i + 1 < opts.length; i += 2) {
      if (opts[i] === 0) hashSize = opts[i + 1] === 0 ? 0 : 32;
      if (opts[i] === 1) hashSize = opts[i + 1];
    }
    p += hashSize;
  }
  const headerEnd = p + 4 + buf.readUInt32BE(p); p += 4;
  const mods = [];
  while (p < headerEnd) {
    const sl = u32(); const spec = buf.toString('utf8', p, p + sl); p += sl;
    const kind = buf[p++];
    if (kind === 0) { mods.push({ spec, so: u32(), sl: u32(), mo: u32(), ml: u32() }); p += 1; } // + module kind
    else if (kind === 1) { const tl = u32(); p += tl; } // redirect
    else if (kind === 2) { p += 4; } // npm specifier -> package id
    else throw new Error(`unknown module entry kind ${kind} at ${p - 1}`);
  }
  p = headerEnd + hashSize;
  if (minor !== '\0\0') { const nl = u32(); p += nl + hashSize; } // npm snapshot (v2.1+)
  const srcLen = u32(); const base = p;
  if (base + srcLen > buf.length) throw new Error('sources section runs past the end of the body');
  // The source-maps section follows the sources section (and its hash), length-prefixed.
  const mp = base + srcLen + hashSize;
  const mapBase = mp + 4 <= buf.length ? mp + 4 : -1;
  const mapEnd = mapBase < 0 ? -1 : mapBase + buf.readUInt32BE(mp);
  const out = new Map();
  for (const m of mods) {
    if (!m.sl) continue;
    let original = null;
    if (m.ml && mapBase >= 0 && mapBase + m.mo + m.ml <= mapEnd) {
      try {
        const map = JSON.parse(buf.toString('utf8', mapBase + m.mo, mapBase + m.mo + m.ml));
        if (map.sources?.length === 1 && typeof map.sourcesContent?.[0] === 'string') original = map.sourcesContent[0];
      } catch { /* an unreadable map falls back to the transpiled text */ }
    }
    out.set(m.spec, original != null ? { text: original, original: true }
      : { text: buf.toString('utf8', base + m.so, base + m.so + m.sl), original: false });
  }
  return out;
}

// The deployed sources are Deno's TRANSPILED JavaScript (types stripped, layout changed), so a raw
// text compare reports every file as different. Both sides are therefore put through the same
// TypeScript printer (type syntax and comments removed, one canonical layout) and compared whole.
// JavaScript is valid input, so the deployed side round-trips; the TS side loses exactly what
// Deno's emit loses. A change in code or in a string literal survives this and is reported.
export function norm(src) {
  const js = ts.transpileModule(src.replace(/^\uFEFF/, ''), {
    // useDefineForClassFields: false. Deno's emit moves class field initialisers into the constructor
    // (`refreshes = 0;` -> `refreshes; constructor(){ ...; this.refreshes = 0; }`, measured on
    // dropbox_backup/dropbox.ts TokenCache, 13 Oct). With [[Define]] semantics TS kept them as fields
    // and an identical file read STALE. [[Set]] semantics puts both sides' initialisers in the
    // constructor and drops bare field declarations on both.
    compilerOptions: { target: ts.ScriptTarget.ESNext, module: ts.ModuleKind.ESNext, removeComments: true, useDefineForClassFields: false },
    reportDiagnostics: false,
  }).outputText;
  // Deno's emit also drops trailing commas and redundant parentheses ((a && b) ? x : y), and wraps a
  // nested single-statement body in braces (`if (x) for (...) if (y) z;` -> `if(x){for ...}`;
  // measured on pdf_text_positions.ts, unchanged since 29 Sep). Both sides lose every
  // comma-before-closer, parenthesis and brace, symmetrically.
  // ponytail: a change that ONLY moves parens/braces reads MATCH; compare ASTs if that ever matters.
  const tight = (s) => s.replace(/\s+/g, ' ').replace(/ ?([{}()[\],;:=<>+\-*/!?&|.]) ?/g, '$1');
  return tight(tight(js).replace(/,([\]})])/g, '$1').replace(/[(){}]/g, ' ')).trim();
}

// Line endings, trailing whitespace and a BOM only: an original-source compare is otherwise exact.
const plain = (s) => s.replace(/^﻿/, '').replace(/\r\n?/g, '\n').replace(/[ \t]+$/gm, '').trimEnd();

/**
 * A deployed specifier as a path under supabase/, or null when it is not this repo's code.
 * A bundle built from supabase/ keys modules 'functions/<slug>/x.ts'; one built from
 * supabase/functions/ (site_error_ingest, stripe_setup_page, voice_otp_capture, measured 13 Oct)
 * keys the same files '<slug>/x.ts'. Schemes (jsr:, npm:, https:, vfs:) and '---' markers are not.
 */
export function firstPartyPath(spec) {
  if (spec.startsWith('---') || /^[a-z][a-z0-9+.-]*:/i.test(spec)) return null;
  return spec.startsWith('functions/') ? spec : `functions/${spec}`;
}

/** Compare deployed first-party sources with main. readMain(path under supabase/) -> string | null. */
export function compareSources(sources, readMain) {
  const firstParty = [...sources.keys()].filter((s) => firstPartyPath(s)).sort();
  if (!firstParty.length) return { state: 'UNVERIFIED', reason: 'body carries no first-party source', files: 0 };
  const differ = [];
  for (const spec of firstParty) {
    const path = firstPartyPath(spec);
    const main = readMain(path);
    const dep = sources.get(spec);
    const { text, original } = typeof dep === 'string' ? { text: dep, original: false } : dep;
    if (main == null) differ.push(`${path} (not on main)`);
    else if (original ? plain(main) !== plain(text) : norm(main) !== norm(text)) differ.push(path);
  }
  return { state: differ.length ? 'STALE' : 'MATCH', differ, files: firstParty.length };
}

function allSlugs() {
  return readdirSync(FN_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory() && e.name !== '_shared' && existsSync(`${FN_DIR}/${e.name}/index.ts`))
    .map((e) => e.name).sort();
}

function slugsToCheck(argv) {
  const named = argv.filter((a) => !a.startsWith('--'));
  if (named.length) return named;
  if (argv.includes('--all')) return allSlugs();
  const since = (argv.find((a) => a.startsWith('--since=')) || '--since=HEAD~20').split('=')[1];
  let raw;
  try {
    raw = execSync(`git diff --name-only ${since}...HEAD -- ${FN_DIR}/`, { stdio: ['ignore', 'pipe', 'pipe'] }).toString();
  } catch (e) {
    // A range that does not resolve (shallow checkout) must not become an empty, green list.
    console.log(`NOTE: ${since}...HEAD does not resolve (${String(e.message).split('\n')[0]}); checking EVERY function.`);
    return allSlugs();
  }
  // A _shared change can stale any importer, so it widens the window to every function.
  if (/^supabase\/functions\/_shared\//m.test(raw)) return allSlugs();
  const touched = raw.split('\n').map((l) => (l.match(/^supabase\/functions\/([^/]+)\//) || [])[1]).filter(Boolean);
  return [...new Set(touched)].filter((s) => existsSync(`${FN_DIR}/${s}/index.ts`)).sort();
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--staging-only')) {
    console.error(`--staging-only was removed with the staging project on 15 Aug 2026; there is one project (${PROD_REF}).`);
    process.exit(2);
  }
  const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
  const slugs = slugsToCheck(argv);
  console.log(`\nDEPLOY PARITY — ${slugs.length} function(s) on ${PROD_REF}, full first-party source vs main\n`);
  const readMain = (spec) => { const f = `supabase/${spec}`; return existsSync(f) ? readFileSync(f, 'utf8') : null; };
  const rows = [];
  for (const slug of slugs) {
    let row;
    try {
      const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/functions/${slug}/body`,
        { headers: { Authorization: `Bearer ${token}` } });
      if (!r.ok) row = { state: 'UNVERIFIED', reason: `GET body -> HTTP ${r.status}` };
      else row = compareSources(parseEszip(Buffer.from(await r.arrayBuffer())), readMain);
    } catch (e) {
      row = { state: 'UNVERIFIED', reason: String(e.message || e).split('\n')[0] };
    }
    rows.push({ slug, ...row });
    const detail = row.state === 'MATCH' ? `${row.files} file(s)`
      : row.state === 'STALE' ? `${row.differ.length}/${row.files} differ: ${row.differ.join(', ')}`
      : row.reason;
    console.log(`${slug.padEnd(32)} ${row.state.padEnd(10)} ${detail}`);
  }
  const stale = rows.filter((r) => r.state === 'STALE');
  const unv = rows.filter((r) => r.state === 'UNVERIFIED');
  console.log(`\n${'='.repeat(96)}`);
  console.log(`MATCH ${rows.length - stale.length - unv.length}   STALE ${stale.length}   UNVERIFIED ${unv.length}   of ${rows.length}`);
  if (stale.length) console.log(`STALE: ${stale.map((r) => r.slug).join(' ')}`);
  if (unv.length) console.log(`UNVERIFIED: ${unv.map((r) => r.slug).join(' ')}`);
  process.exitCode = stale.length || unv.length ? 1 : 0;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main();
