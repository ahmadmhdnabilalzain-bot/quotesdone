// Load every trade pack's spec checklists into public.trade_spec_checklist. Seat: sales_engineer.
//
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir>            # DRY RUN: prints exactly what it would write, per trade
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir> --rows     # DRY RUN, and every row it would write, as JSON
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir> --apply    # replaces the loaded trades' rows (production write)
//
// A pack is <trade>.json with entries[]; an entry of kind 'spec_checklist' carries required_specs (the
// sentences an exact quote must state). Drafts (*.draft.json) are skipped: only a verified pack is a rule.
// The code of a spec is spec_<its first clause> — the same function as _shared/line_specs/reasoned_specs.ts
// specCode (scripts/checks/decision_points_are_reasoned.test.mjs asserts they agree), so a supplier's
// filled-in value lands on the same key the reasoning reads. A trade's rows are REPLACED on load: a
// checklist removed from its pack stops holding quotes.
//
// THE EXPERT INTERVIEW'S FIELDS (10 Nov 2026, founder ledger 1587: one interview, complete enough that every supplier can
// quote without asking). Each checklist also carries, into the columns of
// scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview.sql:
//   spec_guide               the pack's rows {spec, why_needed_to_price, uae_options, follow_up_if, blocking}, each with its code;
//   blocking                 the pack's blocking LABELS, written as their CODES (what the request's state is keyed by);
//   site_visit_required_when the pack's sentence, or null;
//   pack_order               the checklist's position among its pack's checklists (the core job first).
// A blocking label or a guide row that names no spec of its own checklist is REFUSED (reported, exit 1, nothing written):
// the table would refuse it too, and a blocking spec the interview cannot ask is a request that can never be ready.
// --apply needs scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview.sql applied first (the columns).
// prevented by: scripts/checks/the_spec_checklist_loader_carries_the_expert_fields.test.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const specCode = (label) => 'spec_' + String(label).toLowerCase().split(/[(:,;]/)[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
const TRADE_CODE = /^[a-z0-9_-]+$/;
const text = (v) => (v === undefined || v === null ? '' : String(v).trim());

/** One checklist entry's guide, blocking codes and refusals, against the specs the row will carry. */
export function expertFieldsOf(e, specs) {
  const codes = new Set(specs.map((s) => s.code));
  const refused = [];
  const seen = new Set();
  const spec_guide = [];
  for (const g of Array.isArray(e.spec_guide) ? e.spec_guide : []) {
    const code = specCode(g?.spec);
    if (!codes.has(code)) { refused.push(`${e.id}: spec_guide row "${text(g?.spec)}" names no spec of this checklist`); continue; }
    if (seen.has(code)) continue;
    seen.add(code);
    // NOT NEEDED WHEN (15 Nov 2026, journey A): the pack names the specs whose answer makes this one unnecessary by their LABELS;
    // the row carries their codes, and a label that is no spec of this checklist is refused like a blocking one.
    const nn = g?.not_needed_when && typeof g.not_needed_when === 'object' && text(g.not_needed_when.text) ? g.not_needed_when : null;
    const answered = [];
    for (const label of Array.isArray(nn?.answered) ? nn.answered : []) {
      const c = specCode(label);
      if (!codes.has(c)) { refused.push(`${e.id}: not_needed_when of "${text(g?.spec)}" names "${text(label)}", no spec of this checklist`); continue; }
      if (!answered.includes(c)) answered.push(c);
    }
    spec_guide.push({ code, spec: text(g.spec), why_needed_to_price: text(g.why_needed_to_price), uae_options: text(g.uae_options),
      follow_up_if: text(g.follow_up_if), blocking: g.blocking === true,
      ...(nn ? { not_needed_when: { ...(answered.length ? { answered } : {}), text: text(nn.text) } } : {}) });
  }
  const blocking = [];
  for (const label of Array.isArray(e.blocking) ? e.blocking : []) {
    const code = specCode(label);
    if (!codes.has(code)) { refused.push(`${e.id}: blocking "${text(label)}" names no spec of this checklist`); continue; }
    if (!blocking.includes(code)) blocking.push(code);
  }
  // The guide's own flag and the blocking list say the same thing in the packs (measured 10 Nov 2026: 0 of 305 differ);
  // the list decides, and a guide row is marked from it so the two can never disagree in the table.
  for (const g of spec_guide) g.blocking = blocking.includes(g.code);
  const svw = text(e.site_visit_required_when);
  return { spec_guide, blocking, site_visit_required_when: svw || null, refused };
}

export function checklistsOf(pack, file) {
  const out = [];
  if (!TRADE_CODE.test(String(pack.trade ?? ''))) return out;   // the table refuses it; skip, do not abort the load
  let order = 0;
  for (const e of pack.entries ?? []) {
    if (e.kind !== 'spec_checklist' || !Array.isArray(e.required_specs) || !e.required_specs.length) continue;
    const seen = new Set();
    const specs = e.required_specs.map((s) => ({ code: specCode(s), label_en: String(s) })).filter((s) => s.code !== 'spec_' && !seen.has(s.code) && seen.add(s.code));
    if (specs.length) out.push({ trade_code: String(pack.trade), topic_id: String(e.id), topic: String(e.topic ?? e.id), specs, ...expertFieldsOf(e, specs), pack_order: order++, source_pack: file });
  }
  return out;
}

/** Every checklist of every verified pack, one row per (trade, checklist): a duplicate across files keeps the first. */
export function loadDir(dir) {
  const seen = new Set();
  return readdirSync(dir).filter((f) => f.endsWith('.json') && !f.includes('.draft')).sort()
    .flatMap((f) => checklistsOf(JSON.parse(readFileSync(join(dir, f), 'utf8')), f))
    .filter((r) => { const k = r.trade_code + '|' + r.topic_id; if (seen.has(k)) return false; seen.add(k); return true; });
}

/** Per trade: what the load writes for it. */
export function summaryOf(rows) {
  const by = new Map();
  for (const r of rows) {
    const s = by.get(r.trade_code) ?? { trade: r.trade_code, checklists: 0, specs: 0, guide_rows: 0, blocking: 0, site_visit: 0 };
    s.checklists++; s.specs += r.specs.length; s.guide_rows += r.spec_guide.length; s.blocking += r.blocking.length; s.site_visit += r.site_visit_required_when ? 1 : 0;
    by.set(r.trade_code, s);
  }
  return [...by.values()];
}

const lit = (v) => "'" + String(v).replace(/'/g, "''") + "'";
const arr = (a) => (a.length ? `array[${a.map(lit).join(',')}]::text[]` : `'{}'::text[]`);
/** The one statement --apply sends: the loaded trades' rows deleted and inserted again, in one transaction. */
export function loadSql(rows) {
  const trades = [...new Set(rows.map((r) => r.trade_code))];
  const values = rows.map((r) => `(${lit(r.trade_code)}, ${lit(r.topic_id)}, ${lit(r.topic)}, ${lit(JSON.stringify(r.specs))}::jsonb, ${lit(JSON.stringify(r.spec_guide))}::jsonb, ${arr(r.blocking)}, ${r.site_visit_required_when === null ? 'null' : lit(r.site_visit_required_when)}, ${r.pack_order}, ${lit(r.source_pack)})`).join(',\n');
  return `delete from public.trade_spec_checklist where trade_code in (${trades.map(lit).join(', ')});
    insert into public.trade_spec_checklist (trade_code, topic_id, topic, specs, spec_guide, blocking, site_visit_required_when, pack_order, source_pack) values ${values};`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [dir, ...flags] = process.argv.slice(2);
  if (!dir) { console.error('usage: node scripts/kb/load_trade_spec_checklists.mjs <packs dir> [--rows] [--apply]'); process.exit(2); }
  const rows = loadDir(dir);
  const trades = summaryOf(rows);
  const refused = rows.flatMap((r) => r.refused);
  console.log('trade                                checklists  specs  guide_rows  blocking  site_visit');
  for (const s of trades) console.log(`${s.trade.padEnd(36)} ${String(s.checklists).padStart(10)} ${String(s.specs).padStart(6)} ${String(s.guide_rows).padStart(11)} ${String(s.blocking).padStart(9)} ${String(s.site_visit).padStart(11)}`);
  const sum = (k) => trades.reduce((n, s) => n + s[k], 0);
  console.log(`${rows.length} checklists across ${trades.length} trades: ${sum('specs')} specs, ${sum('guide_rows')} guide rows, ${sum('blocking')} blocking specs, ${sum('site_visit')} site-visit conditions; `
    + `${rows.filter((r) => r.blocking.length).length} checklists with a blocking list, ${rows.filter((r) => !r.blocking.length).length} without`);
  console.log(`it would DELETE every row of these ${trades.length} trades from public.trade_spec_checklist and INSERT ${rows.length} rows`);
  if (flags.includes('--rows')) for (const r of rows) { const { refused: _r, ...row } = r; console.log(JSON.stringify(row)); }
  if (refused.length) { console.error(`REFUSED (${refused.length}); nothing is written:\n  ` + refused.join('\n  ')); process.exit(1); }
  if (!rows.length) { console.log('nothing to load'); process.exit(0); }
  if (!flags.includes('--apply')) { console.log('dry run; pass --apply to load'); process.exit(0); }
  const { sql } = await import('../lib/db.mjs');
  await sql(loadSql(rows.map(({ refused: _r, ...row }) => row)));
  console.log('loaded');
}
