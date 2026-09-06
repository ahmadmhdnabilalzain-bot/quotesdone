import { sql } from '../phase_c/lib/db.mjs';
const J=x=>JSON.stringify(x);
console.log('tables role/agent', J(await sql(`select table_name from information_schema.tables where table_schema='public' and (table_name ilike '%role%' or table_name ilike 'org_agent%' or table_name='org_canonical_roles') order by 1`)));
console.log('cos in org_agents', J(await sql(`select agent_key, dept_key from public.org_agents where agent_key='chief_of_staff' limit 1`)).slice(0,200));
console.log('assurance dept', J(await sql(`select dept_key from public.org_departments where dept_key ilike '%assur%' or dept_key='assurance' limit 3`)));
console.log('org_departments sample', J(await sql(`select dept_key from public.org_departments limit 12`)));
