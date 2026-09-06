// RAISE's format string uses % per argument and %% for a literal percent; the six payload raises
// were written with %s, which plpgsql emits as the value followed by a literal 's'. Rewritten as a
// single '%' with one concatenated argument, so there is no format string to get wrong at all.
import { readFileSync, writeFileSync } from 'node:fs';

const FIX = [
  ['scripts/tmp_diag/splice_o08.mjs',
    `      raise exception 'PDA5%%|%|%|%|%|%|%',
        chr(31), v_a5_A, v_a5_B, v_a5_C, v_a5_G,
        (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_ovl)),
        (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_alias)),
        v_a5_t1||'/'||v_a5_t2||' '||v_a5_r1||'/'||v_a5_r2||' '||v_a5_c1||'/'||v_a5_c2;`,
    `      raise exception '%', 'PDA5' || chr(31) || v_a5_A ||'|'|| v_a5_B ||'|'|| v_a5_C ||'|'|| v_a5_G
        ||'|'|| (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_ovl))
        ||'|'|| (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_alias))
        ||'|'|| v_a5_t1||'/'||v_a5_t2||' '||v_a5_r1||'/'||v_a5_r2||' '||v_a5_c1||'/'||v_a5_c2;`],

  ['scripts/tmp_diag/splice_o08.mjs',
    `      raise exception 'PDL5%%|%|%|%|%|%',
        chr(31), v_l5_A, v_l5_B, v_l5_C, v_l5_T, v_l5_S, v_l5_t1||'/'||v_l5_t2;`,
    `      raise exception '%', 'PDL5' || chr(31) || v_l5_A ||'|'|| v_l5_B ||'|'|| v_l5_C ||'|'|| v_l5_T
        ||'|'|| v_l5_S ||'|'|| v_l5_t1||'/'||v_l5_t2;`],

  ['scripts/tmp_diag/splice_o08.mjs',
    `      raise exception 'PDF4%%|%|%|%|%|%|%',
        chr(31), v_f4_N, v_f4_U, v_f4_D, v_f4_R, v_f4_S, v_f4_E, v_f4_W;`,
    `      raise exception '%', 'PDF4' || chr(31) || v_f4_N ||'|'|| v_f4_U ||'|'|| v_f4_D ||'|'|| v_f4_R
        ||'|'|| v_f4_S ||'|'|| v_f4_E ||'|'|| v_f4_W;`],

  ['scripts/tmp_diag/splice_o08_tail.js',
    `      raise exception 'PDQ1%%|%|%', chr(31), v_q1_I, v_q1_C, v_q1_n;`,
    `      raise exception '%', 'PDQ1' || chr(31) || v_q1_I ||'|'|| v_q1_C ||'|'|| v_q1_n;`],

  ['scripts/tmp_diag/splice_o08_tail.js',
    `      raise exception 'PDQ4%%|%|%|%|%', chr(31), v_q4_a1, v_q4_a2, v_q4_a3, v_q4_a4, v_q4_n;`,
    `      raise exception '%', 'PDQ4' || chr(31) || v_q4_a1 ||'|'|| v_q4_a2 ||'|'|| v_q4_a3 ||'|'|| v_q4_a4 ||'|'|| v_q4_n;`],

  ['scripts/tmp_diag/splice_o08_tail.js',
    `      raise exception 'PDQ5%%|%|%|%|%|%', chr(31), v_q5_N, v_q5_R, v_q5_B, v_q5_O, v_q5_I, v_q5_n1||'/'||v_q5_n2;`,
    `      raise exception '%', 'PDQ5' || chr(31) || v_q5_N ||'|'|| v_q5_R ||'|'|| v_q5_B ||'|'|| v_q5_O ||'|'|| v_q5_I ||'|'|| v_q5_n1||'/'||v_q5_n2;`],
];

for (const [file, find, repl] of FIX) {
  const s = readFileSync(file, 'utf8');
  const n = s.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR in ${file} matched ${n} time(s):\n${find}`); process.exit(1); }
  writeFileSync(file, s.replace(find, repl));
  console.log('fixed', file, find.slice(0, 40).replace(/\n/g, ' '));
}
