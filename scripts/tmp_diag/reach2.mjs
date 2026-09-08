import { sql } from '../lib/db.mjs';
const r = await sql(`select
  substring(prosrc from 415 for 60) ctx,
  (prosrc ~ 'fn_provision_category_call[[:space:]]*[(]') a,
  (prosrc ~ '\yfn_provision_category_call') b,
  (prosrc like '%fn_provision_category_call%') c
 from pg_proc where proname='trg_self_reg_category'`);
console.log(JSON.stringify(r));
