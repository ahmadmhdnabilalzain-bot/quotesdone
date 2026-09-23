// Load every trade pack's spec checklists into public.trade_spec_checklist. Seat: sales_engineer.
//
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir>            # DRY RUN: prints what it would load
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir> --apply    # replaces the loaded trades' rows (production write)
//
// A pack is <trade>.json with entries[]; an entry of kind 'spec_checklist' carries required_specs (the
// sentences an exact quote must state). Drafts (*.draft.json) are skipped: only a verified pack is a rule.
// The code of a spec is spec_<its first clause> — the same function as _shared/line_specs/reasoned_specs.ts
// specCode (scripts/checks/decision_points_are_reasoned.test.mjs asserts they agree), so a supplier's
// filled-in value lands on the same key the reasoning reads. A trade's rows are REPLACED on load: a
// checklist removed from its pack stops holding quotes.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const specCode = (label) => 'spec_' + String(label).toLowerCase().split(/[(:,;]/)[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
const TRADE_CODE = /^[a-z0-9_-]+$/;

export function checklistsOf(pack, file) {
  const out = [];
  if (!TRADE_CODE.test(String(pack.trade ?? ''))) return out;   // the table refuses it; skip, do not abort the load
  for (const e of pack.entries ?? []) {
    if (e.kind !== 'spec_checklist' || !Array.isArray(e.required_specs) || !e.required_specs.length) continue;
    const seen = new Set();
    const specs = e.required_specs.map((s) => ({ code: specCode(s), label_en: String(s) })).filter((s) => s.code !== 'spec_' && !seen.has(s.code) && seen.add(s.code));
    if (specs.length) out.push({ trade_code: String(pack.trade), topic_id: String(e.id), topic: String(e.topic ?? e.id), specs, source_pack: file });
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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [dir, ...flags] = process.argv.slice(2);
  if (!dir) { console.error('usage: node scripts/kb/load_trade_spec_checklists.mjs <packs dir> [--apply]'); process.exit(2); }
  const rows = loadDir(dir);
  const trades = [...new Set(rows.map((r) => r.trade_code))];
  console.log(`${rows.length} checklists across ${trades.length} trades`);
  if (!rows.length) { console.log('nothing to load'); process.exit(0); }
  if (!flags.includes('--apply')) { console.log('dry run; pass --apply to load'); process.exit(0); }
  const { sql } = await import('../lib/db.mjs');
  const lit = (v) => "'" + String(v).replace(/'/g, "''") + "'";
  const values = rows.map((r) => `(${lit(r.trade_code)}, ${lit(r.topic_id)}, ${lit(r.topic)}, ${lit(JSON.stringify(r.specs))}::jsonb, ${lit(r.source_pack)})`).join(',\n');
  await sql(`delete from public.trade_spec_checklist where trade_code in (${trades.map(lit).join(', ')});
    insert into public.trade_spec_checklist (trade_code, topic_id, topic, specs, source_pack) values ${values};`);
  console.log('loaded');
}
