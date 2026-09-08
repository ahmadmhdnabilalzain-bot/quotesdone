import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';
const get = async sig => (await sql(`select pg_get_functiondef('${sig}'::regprocedure) def`))[0].def;
for (const [sig, out] of [
  ['public.fn_phase_d_fixture_input(bigint,text,text)', 'l01_fixture_input.sql'],
  ['public.fn_phase_d_fixture_effect_payload(bigint)', 'l01_fixture_effect_payload.sql'],
]) {
  const def = await get(sig);
  const lines = def.split('\n');
  lines.forEach((l, i) => { if (l.includes('phase_d_context_key_object')) console.log(`${out} :: ${i}: ${l}`); });
  writeFileSync('scripts/tmp_diag/' + out, def);
}
