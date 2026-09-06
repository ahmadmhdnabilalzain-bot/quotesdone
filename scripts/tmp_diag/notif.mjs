import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select id, type, to_email, to_role, status, created_at, left(coalesce(subject,''),70) subj from public.notifications order by id desc limit 4`), null, 1));
console.log(JSON.stringify(await sql(`select count(*) n from public.notifications where to_email like '%example.invalid%' or coalesce(subject,'') ilike '%ZZ DEMO%' or coalesce(body,'') ilike '%zz-phase-d%'`)));
