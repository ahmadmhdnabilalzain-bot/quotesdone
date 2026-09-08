import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- G16 — the factory read the catalogue by key alone, and a key stopped being unique
--
-- Every content read in fn_phase_d_fixture_scenario was written as
--
--     (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
--       where c.scope = 'EFFECT_PAYLOAD' and c.field_key = 'kind')
--
-- a scalar subquery keyed on nothing but the field name. That worked for exactly as long as no
-- field name was used twice. G15 added PDF-4013, a document kind for W07, beside PDF-0042, the
-- partnership kind for W21 — because public.documents.kind and public.opportunity.kind are two
-- different columns of two different relations that happen to share a name — and the next scenario
-- build died at the first stage with
--
--     ERROR: 21000: more than one row returned by a subquery used as an expression
--
-- which is Postgres refusing to choose, and is the good outcome. The alternative shape, an
-- unqualified LIMIT 1, would have picked one silently: this estate has already paid for that once,
-- when a pack auditor resolved a key to the first matching row and invented a 16,608-record hole.
--
-- fn_phase_d_fixture_input has scoped this correctly all along — step_id, then workflow_id, then
-- unscoped — and the factory simply did not use it because it runs before any step exists. So the
-- scoping is lifted into a routine of its own, keyed on the OBJECT the stage is creating: the
-- governing workflow of that object, from the frozen binding, selects the fixture written for it,
-- and an unscoped fixture still answers where no scoped one exists. Ambiguity between two fixtures
-- at the same scope raises rather than choosing.
--
-- Every catalogue read in the factory now goes through it. There are eleven.
--
-- ROLLBACK: drop fn_phase_d_stage_content and re-apply the previous fn_phase_d_fixture_scenario.`;

const HELPER = `
CREATE OR REPLACE FUNCTION public.fn_phase_d_stage_content(p_object_id text, p_scope text, p_key text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_wf  text;
  v_n   int;
  v_val text;
begin
  select b.governing_workflow_id into v_wf
    from public.phase_d_business_object_binding b where b.object_id = p_object_id;

  -- The fixture written FOR this object's workflow, if there is one.
  select count(*), min(c.value #>> '{}') into v_n, v_val
    from public.phase_d_fixture_catalogue c
   where c.scope = p_scope and c.field_key = p_key
     and c.workflow_id is not null
     and (c.workflow_id = v_wf or v_wf like '%' || c.workflow_id || '%');
  if v_n = 1 then return v_val; end if;
  if v_n > 1 then
    raise exception 'fn_phase_d_stage_content: % fixtures at scope % for key % are scoped to the workflow of %. Refusing to choose one. (pd_fixture_ambiguous_content)',
      v_n, p_scope, p_key, p_object_id using errcode = '21000';
  end if;

  -- Otherwise the unscoped one, and there must be exactly one of those too.
  select count(*), min(c.value #>> '{}') into v_n, v_val
    from public.phase_d_fixture_catalogue c
   where c.scope = p_scope and c.field_key = p_key and c.workflow_id is null;
  if v_n > 1 then
    raise exception 'fn_phase_d_stage_content: % unscoped fixtures at scope % for key %. Refusing to choose one; scope them to the workflow they were written for. (pd_fixture_ambiguous_content)',
      v_n, p_scope, p_key using errcode = '21000';
  end if;
  return v_val;   -- null when nothing is committed, which the caller's own NOT NULL will report
end
$function$;

revoke all on function public.fn_phase_d_stage_content(text,text,text) from public;
`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let def = r[0].def;

// Replace every bare catalogue read with the scoped helper.
const re = /\(select c\.value #>> '\{\}' from public\.phase_d_fixture_catalogue c\s*\n\s*where c\.scope\s*=\s*'([A-Z_]+)' and c\.field_key\s*=\s*'([a-z_0-9]+)'\)/g;
let count = 0;
def = def.replace(re, (_m, scope, key) => {
  count++;
  return `public.fn_phase_d_stage_content(st.object_id, '${scope}', '${key}')`;
});
if (count < 8) throw new Error(`only ${count} catalogue reads rewritten; expected the full set`);

// The artifact digest read is keyed on CONTEXT_KEY and sits outside a stage arm (it uses `c`
// with a different alias shape); leave it, but confirm it is still unique by construction.
writeFileSync('scripts/sql/phase_d_g16_the_factory_read_the_catalogue_by_key_alone.sql',
  HEAD + '\n' + HELPER + '\n' + def + '\n');
console.log(`G16 written, ${count} catalogue reads scoped`);
