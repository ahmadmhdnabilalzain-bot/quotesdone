// Load every trade pack's spec checklists into public.trade_spec_checklist. Seat: sales_engineer.
//
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir>            # DRY RUN: prints what it would load
//   node scripts/kb/load_trade_spec_checklists.mjs <packs dir> --apply    # upserts (production write)
//
// A pack is <trade>.json with entries[]; an entry of kind 'spec_checklist' carries required_specs (the
// sentences an exact quote must state). Drafts (*.draft.json) are skipped: only a verified pack is a rule.
// The code of a spec is spec_<its first clause> — the same function as _shared/line_specs/reasoned_specs.ts
// specCode, so a supplier's filled-in value lands on the same key the reasoning reads.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export const specCode = (label) => 'spec_' + String(label).toLowerCase().split(/[(:,;]/)[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);

export function checklistsOf(pack, file) {
  const out = [];
  for (const e of pack.entries ?? []) {
    if (e.kind !== 'spec_checklist' || !Array.isArray(e.required_specs) || !e.required_specs.length) continue;
    const seen = new Set();
    const specs = e.required_specs.map((s) => ({ code: specCode(s), label_en: String(s) })).filter((s) => s.code !== 'spec_' && !seen.has(s.code) && seen.add(s.code));
    out.push({ trade_code: String(pack.trade), topic_id: String(e.id), topic: String(e.topic ?? e.id), specs, source_pack: file });
  }
  return out;
}

const [dir, ...flags] = process.argv.slice(2);
if (dir && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop())) {
  const rows = readdirSync(dir).filter((f) => f.endsWith('.json') && !f.includes('.draft')).flatMap((f) => checklistsOf(JSON.parse(readFileSync(join(dir, f), 'utf8')), f));
  console.log(`${rows.length} checklists across ${new Set(rows.map((r) => r.trade_code)).size} trades`);
  if (!flags.includes('--apply')) { console.log('dry run; pass --apply to load'); process.exit(0); }
  const { sql } = await import('../lib/db.mjs');
  const lit = (v) => "'" + String(v).replace(/'/g, "''") + "'";
  const values = rows.map((r) => `(${lit(r.trade_code)}, ${lit(r.topic_id)}, ${lit(r.topic)}, ${lit(JSON.stringify(r.specs))}::jsonb, ${lit(r.source_pack)})`).join(',\n');
  await sql(`insert into public.trade_spec_checklist (trade_code, topic_id, topic, specs, source_pack) values ${values}
    on conflict (trade_code, topic_id) do update set topic = excluded.topic, specs = excluded.specs, source_pack = excluded.source_pack, loaded_at = now()`);
  console.log('loaded');
}
