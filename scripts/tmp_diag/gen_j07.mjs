import { writeFileSync } from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_phase_d_dispatch_step'`);
let body = prosrc;
const rep = (o, n) => { const c = body.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); body = body.replace(o, n); };

rep(`    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');
    end if;`,
`    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');

      -- J07. A ROLE IS NOT ALWAYS WHAT THE OWNER COLUMN HOLDS. E25 made the accountable role the
      -- owner of a COMPANY-scoped write, which is right about WHO is accountable and says nothing
      -- about what the column stores. Measured 23 Aug 2026 on W01-S07: the object is initiative,
      -- the relation public.org_tasks, the owner column dept_key, and
      --
      --   insert or update on table "org_tasks" violates foreign key constraint
      --   "org_tasks_dept_key_fkey"      -- FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key)
      --
      -- because a role id is not a department key. The column's own foreign key settles it: where
      -- the accountable role does not satisfy that key, the answer is the value from this role's
      -- OWN registry row that does. public.org_role.primary_department_id resolves against
      -- public.org_departments for all 180 roles; public.org_agents.department is the same fact
      -- under the runtime key, and is tried second for a role recorded only there.
      --
      -- Nothing is invented and nothing is chosen: two candidates, both read off the role's own
      -- record, each TESTED against the foreign key before it is used. A role whose registry row
      -- satisfies neither leaves the owner exactly as E25 left it, and the write refuses as before.
      select cl3.relname, ns3.nspname, a4.attname
        into v_own_rel, v_own_ns, v_own_col
        from public.phase_d_object_write_map wm3
        join pg_attribute a3 on a3.attrelid = to_regclass(wm3.target_relation)
                            and a3.attname = wm3.owner_column and a3.attnum > 0
        join pg_constraint c3 on c3.conrelid = a3.attrelid and c3.contype = 'f'
                             and a3.attnum = any (c3.conkey)
        join pg_class cl3 on cl3.oid = c3.confrelid
        join pg_namespace ns3 on ns3.oid = cl3.relnamespace
        join pg_attribute a4 on a4.attrelid = c3.confrelid and a4.attnum = c3.confkey[1]
       where wm3.object_id = v_cx#>>'{business_object,object_id}'
         and coalesce(btrim(wm3.owner_column),'') <> ''
       limit 1;

      if v_own_rel is not null and v_owner is not null then
        execute format('select not exists (select 1 from %I.%I where %I::text = $1)',
                       v_own_ns, v_own_rel, v_own_col)
          into v_owner_unfit using v_owner;
        if coalesce(v_owner_unfit, false) then
          execute format(
            'select c.v from (select r.primary_department_id::text v, 1 ord from public.org_role r'
            || ' where r.role_id = $1'
            || ' union all select a.department::text, 2 from public.org_agents a where a.agent_key = $1) c'
            || ' where c.v is not null'
            || '   and exists (select 1 from %I.%I t where t.%I::text = c.v)'
            || ' order by c.ord limit 1',
            v_own_ns, v_own_rel, v_own_col)
            into v_owner_fit using v_owner;
          if v_owner_fit is not null then v_owner := v_owner_fit; end if;
        end if;
      end if;
      v_own_rel := null; v_own_ns := null; v_own_col := null;
    end if;`);

rep('  v_own_rel  text;   -- J06',
    '  v_own_rel  text;   -- J06\n  v_own_col  text;   -- J07\n  v_owner_unfit boolean;   -- J07\n  v_owner_fit   text;      -- J07');

const header = `-- J07 — the accountable role was written into a column that holds a department
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. W01-S07 was one of the seven steps the 257-step
-- coverage matrix left without an effect:
--
--   pd_effect_reference_unresolved :: insert or update on table "org_tasks" violates foreign key
--   constraint "org_tasks_dept_key_fkey"
--
-- The object is \`initiative\`, its write map targets public.org_tasks with owner_column dept_key, and
-- that column is FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key). E25 gave a
-- COMPANY-scoped write its owner from public.phase_c_workflow_step_run.accountable_role_id -- the
-- frozen registry's own answer to who is accountable, and the right answer to that question. It is
-- not an answer to what the column holds.
--
-- The column's foreign key is the authority on that, so it is read: where the accountable role does
-- not satisfy the key, the value is taken from the role's OWN registry row --
-- public.org_role.primary_department_id, which resolves against public.org_departments for all 180
-- roles, or public.org_agents.department for a role recorded only under its runtime key -- and each
-- candidate is TESTED against the foreign key before it is used. A role whose registry row
-- satisfies neither leaves the owner where E25 left it and the write refuses as before.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_dispatch_step (phase_d_j06 is the last file
-- that defines it). No DDL, no grants.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j07.mjs.
CREATE OR REPLACE FUNCTION public.fn_phase_d_dispatch_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_j07_the_accountable_role_was_written_into_a_column_that_holds_a_department.sql',
  header + body + '$function$;\n');
console.log('written');
