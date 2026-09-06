import { writeFileSync, readFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';
const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_effect_produce'`);
let def = r[0].def;
const bad = `        'author_agent', coalesce(nullif(btrim(v_payload->>'reviewer_role_id'),''), v_actor),`;
if (def.split(bad).length - 1 !== 1) throw new Error('bad line matched ' + (def.split(bad).length - 1));
def = def.replace(bad, `        'author_agent', v_actor,`);
// keep the same committed HEAD, just replace the routine body below the first CREATE line
const file = 'scripts/sql/phase_d_h10_the_review_verdict_that_named_no_subject.sql';
const cur = readFileSync(file, 'utf8');
const head = cur.slice(0, cur.indexOf('CREATE OR REPLACE FUNCTION'));
writeFileSync(file, head + def + '\n');
console.log('H10 rewritten from live with author_agent = v_actor');
