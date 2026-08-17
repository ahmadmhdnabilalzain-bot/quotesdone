// Generate a cutover migration from the LIVE trigger bodies.
//
//   node scripts/phase_c/gen_cutover.mjs <spec.json> <out.sql> <header.txt>
//
// Editing a live trigger by hand is how a notification path gets broken while wiring a workflow.
// This reads the deployed definition, inserts ONE `perform public.fn_kernel_source_emit(...)` at a
// named anchor, and refuses to emit if the anchor is absent, ambiguous, or already carries the
// call. Everything else in the body is byte-identical to what is running now.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const [specPath, outPath, headerPath] = process.argv.slice(2);
const spec = JSON.parse(readFileSync(specPath, 'utf8'));
const parts = [];

for (const s of spec.sources) {
  const rows = await sql(
    `select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=${`'${s.routine}'`}`);
  if (rows.length !== 1) { console.error(`${s.routine}: expected 1 definition, got ${rows.length}`); process.exit(1); }
  let def = rows[0].d;

  if (/fn_kernel_source_emit/.test(def)) {
    console.error(`${s.routine}: already calls fn_kernel_source_emit — refusing to add a second call`);
    process.exit(1);
  }
  const occurrences = def.split(s.anchor).length - 1;
  if (occurrences !== 1) {
    console.error(`${s.routine}: anchor ${JSON.stringify(s.anchor)} appears ${occurrences} times, need exactly 1`);
    process.exit(1);
  }

  const call =
`  -- K20 cutover. ${s.why}
  perform public.fn_kernel_source_emit('${s.source_key}', jsonb_build_object(
    'source_ref',  ${s.source_ref},
    'raw_payload', ${s.payload}));
`;
  def = s.before
    ? def.replace(s.anchor, call + s.anchor)
    : def.replace(s.anchor, s.anchor + '\n' + call);

  parts.push(`-- ${s.source_key}\n--   ${s.why}\n${def};\n`);
}

writeFileSync(outPath,
  readFileSync(headerPath, 'utf8') + '\nbegin;\n\n' + parts.join('\n') +
  '\n' + (spec.tail || '') + '\ncommit;\n');
console.log(`emitted ${parts.length} routine(s) to ${outPath}`);
