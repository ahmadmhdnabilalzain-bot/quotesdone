import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select count(*) n, coalesce(sum(cost_aed),0) aed from public.ai_cost_log where occurred_at >= current_date - 1`)));
