import { readFileSync, writeFileSync } from 'node:fs';
const patch = (file, pairs) => {
  let s = readFileSync('scripts/tmp_diag/' + file, 'utf8');
  for (const [a, b] of pairs) {
    if (!s.includes(a)) { console.error(`MISS in ${file}: ${a.slice(0,70)}`); process.exit(1); }
    s = s.split(a).join(b);
  }
  writeFileSync('scripts/tmp_diag/' + file, s);
  console.log(file + ' patched, len=' + s.length);
};
patch('l01_fixture_input.sql', [
  [`     where m.context_key = p_key\n       and sc.canonical_ref is not null`,
   `     where m.context_key = p_key and m.key_role = 'IDENTIFIES'\n       and sc.canonical_ref is not null`],
  [`                           (select object_id from public.phase_d_context_key_object where context_key = p_key));`,
   `                           (select object_id from public.phase_d_context_key_object\n                             where context_key = p_key and key_role = 'IDENTIFIES'));`],
  [`       where m.context_key = p_key order by sc.scenario_record_id limit 1;`,
   `       where m.context_key = p_key and m.key_role = 'IDENTIFIES'\n       order by sc.scenario_record_id limit 1;`],
]);
patch('l01_fixture_effect_payload.sql', [
  [`       where cko.context_key = r.src\n         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''`,
   `       where cko.context_key = r.src and cko.key_role = 'IDENTIFIES'\n         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''`],
]);
