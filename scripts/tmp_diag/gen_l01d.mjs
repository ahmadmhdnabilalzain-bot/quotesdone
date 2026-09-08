import { sql } from '../lib/db.mjs';
import { readFileSync, writeFileSync } from 'node:fs';
let sc = readFileSync('scripts/tmp_diag/l01_step_context.sql','utf8');
const OLD = `      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;`;
const NEW = `      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';`;
const n = sc.split(OLD).length - 1;
if (n !== 3) { console.error('expected 3 doors, found ' + n); process.exit(1); }
sc = sc.split(OLD).join(NEW);
writeFileSync('scripts/tmp_diag/l01_step_context.sql', sc);
console.log('patched ' + n + ' doors; len=' + sc.length);
