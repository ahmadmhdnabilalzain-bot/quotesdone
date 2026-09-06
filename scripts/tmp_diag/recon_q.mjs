import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('policy guard + match guards', `select p.proname, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('fn_phase_d_object_policy_guard','fn_unsafe_match_eligibility_guard','trg_gate_incomplete_match','fn_notify_matched_supplier')`);
