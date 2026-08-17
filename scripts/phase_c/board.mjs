// Compact printer for a kernel invariant board.
//   node scripts/phase_c/board.mjs fn_kernel_trigger_state [more_fns...]
import { sql } from './lib/db.mjs';
for (const fn of process.argv.slice(2)) {
  console.log(`=== ${fn} ===`);
  try {
    const rows = await sql(`select check_name, ok, expected, actual from public.${fn}()`);
    for (const r of rows) {
      console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${r.check_name}`);
      if (!r.ok) console.log(`       exp: ${r.expected}\n       act: ${r.actual}`);
    }
    console.log(`  -> ${rows.filter(r => !r.ok).length} failing of ${rows.length}`);
  } catch (e) { console.log('ERR', String(e.message).slice(0, 400)); }
}
