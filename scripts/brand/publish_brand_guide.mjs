// Publish docs/brand/QUOTESDONE_BRAND_GUIDE.md as a corporate PDF report (6 Sep 2026).
//
// The founder: "any report needs to be in PDF format". The brand guide is a report like every other: this
// script turns the markdown into the narrative body report_pdf already parses (UPPERCASE headings, "  Key: value"
// lines, "- " bullets), inserts ONE board_reports row (report_type 'brand'), and the z_report_pdf_enqueue trigger
// hands it to the action invoker, which renders it through the report_pdf edge function into the private
// `reports` bucket — the same door every finance and board report goes through, so it appears in the OS Reports
// panel. Hex colours in "Key: #RRGGBB" lines get a swatch in the PDF. Re-running publishes a new version (a new
// row, dated today); the previous versions stay in the registry like every other report's history.
//
// The renderer's fonts are WinAnsi (Latin-1), so Arabic sample strings in the guide are replaced by "[Arabic]"
// in the PDF body; the markdown keeps them.
//
//   node scripts/brand/publish_brand_guide.mjs            # dry run: prints the narrative body and stops
//   node scripts/brand/publish_brand_guide.mjs --publish  # inserts the board_reports row
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sql } from '../lib/db.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const md = fs.readFileSync(path.join(here, '..', '..', 'docs', 'brand', 'QUOTESDONE_BRAND_GUIDE.md'), 'utf8');

function toNarrative(src) {
  const out = []; let title = 'QuotesDone Brand Guide';
  // Arabic, Arabic Supplement and the two Arabic Presentation Forms blocks.
  const latin = (s) => s.replace(/[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]+/g, '[Arabic]').replace(/\s{2,}/g, ' ').trim();
  const inline = (s) => latin(s.replace(/\*\*(.+?)\*\*/g, '$1').replace(/`(.+?)`/g, '$1').replace(/\[(.+?)\]\((.+?)\)/g, '$1 ($2)'));
  let inTable = false;
  for (const raw of src.split('\n')) {
    const line = raw.replace(/\s+$/, '');
    if (/^# /.test(line)) { title = inline(line.slice(2)); continue; }
    // Headings become the UPPERCASE lines parseNarrative recognises: no lowercase, no "1.2"-style decimals.
    if (/^## /.test(line)) { out.push('', inline(line.slice(3)).toUpperCase().replace(/[^A-Z0-9 \-&/,()'#]/g, ''), ''); inTable = false; continue; }
    if (/^### /.test(line)) { out.push('', inline(line.slice(4)).toUpperCase().replace(/[^A-Z0-9 \-&/,()'#]/g, ''), ''); inTable = false; continue; }
    if (/^\|/.test(line)) {
      if (/^\|\s*-{2,}/.test(line)) continue;                     // the separator row
      const cells = line.split('|').slice(1, -1).map((c) => inline(c));
      if (!inTable) { inTable = true; if (/^(colour|token|role|element|level|platform|state|item|pair|size|do|word|wrong|surface|face|use)$/i.test(cells[0].trim())) continue; } // header row of a table
      if (cells.length >= 2) out.push('  ' + cells[0].slice(0, 60) + ': ' + cells.slice(1).filter(Boolean).join(' — '));
      continue;
    }
    inTable = false;
    if (/^\s*[-*] /.test(line)) { out.push('- ' + inline(line.replace(/^\s*[-*] /, ''))); continue; }
    if (/^>\s?/.test(line)) { out.push(inline(line.replace(/^>\s?/, ''))); continue; }
    if (/^---+$/.test(line)) continue;
    out.push(inline(line));
  }
  const body = (title + '\n' + '='.repeat(Math.min(title.length, 60)) + '\n' + out.join('\n')).replace(/\n{3,}/g, '\n\n').trim() + '\n';
  return { title, body };
}

const { title, body } = toNarrative(md);
if (!process.argv.includes('--publish')) { console.log(body); console.log(`\n-- dry run: ${body.length} chars, ${body.split('\n').length} lines; add --publish to insert the report row`); process.exit(0); }

const esc = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const kpis = {
  colours: 15, kit_files: 58, typefaces: 4, wcag_pairs_measured: 30,
  source: 'docs/brand/QUOTESDONE_BRAND_GUIDE.md', published_by: 'scripts/brand/publish_brand_guide.mjs',
};
const r = await sql(`insert into public.board_reports (week_start, title, body, kpis, report_type)
  values (current_date, ${esc(title)}, ${esc(body)}, ${esc(JSON.stringify(kpis))}::jsonb, 'brand')
  returning id, week_start, report_type, created_at`);
console.log('board_reports row:', JSON.stringify(r[0]));
const q = await sql(`select id, status, idempotency_key, created_at from public.action_execution where idempotency_key = 'report_pdf:board:${r[0].id}'`);
console.log('queued for the action invoker:', JSON.stringify(q[0] || null));
process.exit(0);
