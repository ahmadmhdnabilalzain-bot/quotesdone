import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select rule_id, required_context, refusal_code, enforcement_point from public.phase_d_rule_enforcement where rule_id='BR-011'`)));
const s = await sql(`select substring(prosrc from position('BR-011' in prosrc)-100 for 1600) src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_phase_d_rule_check'`);
console.log(s[0].src);
