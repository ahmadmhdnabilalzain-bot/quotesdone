import { readFileSync } from 'node:fs';
const files = [
  'supabase/functions/kb_ingest/index.ts',
  'supabase/functions/kb_ingest_text/index.ts',
  'QUOTESDONE_CODEBASE.md',
];
for (const f of files) {
  const b = readFileSync(f);
  const nulls = [];
  for (let i = 0; i < b.length; i++) if (b[i] === 0) nulls.push(i);
  const bom = b[0] === 0xFF && b[1] === 0xFE ? 'UTF-16LE BOM'
    : b[0] === 0xFE && b[1] === 0xFF ? 'UTF-16BE BOM'
    : b[0] === 0xEF && b[1] === 0xBB && b[2] === 0xBF ? 'UTF-8 BOM' : 'none';
  let ctrl = 0;
  for (let i = 0; i < b.length; i++) { const c = b[i]; if (c < 9 || (c > 13 && c < 32)) ctrl++; }
  console.log(`${f}\n  bytes=${b.length} bom=${bom} NUL=${nulls.length}${nulls.length ? ' firstAt=' + nulls[0] : ''} otherCtrl=${ctrl - nulls.length}`);
  if (nulls.length) {
    const at = nulls[0];
    console.log(`  context bytes ${Math.max(0, at - 24)}..${at + 24}: ` +
      JSON.stringify(b.slice(Math.max(0, at - 24), at + 24).toString('latin1')));
  }
}
