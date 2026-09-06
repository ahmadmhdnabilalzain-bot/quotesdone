// §5: "alias self-review accepted = 0". fn_kernel_reviewer_independent resolves BOTH identity
// vocabularies before comparing, so naming the creator by an alias must be refused exactly as
// naming them directly is. Three arms: the creator by their own key, the creator by every alias
// that resolves to them, and an independent role as the control.
import { probe } from './probe.mjs';

console.log(await probe(`do $p$
declare v_out text := ''; v_creator text; v_alias text; r record; v_n int := 0;
begin
  -- A step that DECLARES a reviewer, so the declared-reviewer check cannot be what answers.
  select s.accountable_role_id into v_creator
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
   order by s.step_id limit 1;

  v_out := 'creator=' || v_creator
        || ' | self(direct)=' || public.fn_kernel_reviewer_independent(v_creator, v_creator)::text;

  -- Every alias the estate resolves to the same effective identity.
  for r in
    select a.role_id, a.alias
      from (select x.role_id, x.role_id alias from public.fn_phase_c_resolve_actor(v_creator) x) a
  loop v_n := v_n + 1; end loop;

  select string_agg(distinct t.alias, ',') into v_alias from (
    select a.alias from public.org_role_alias a where a.role_id = v_creator limit 3) t;

  if coalesce(v_alias,'') = '' then
    v_out := v_out || ' | no distinct alias resolves to this creator, so the alias arm has an EMPTY '
          || 'POPULATION and proves nothing on its own';
  else
    for r in select unnest(string_to_array(v_alias, ',')) alias loop
      v_out := v_out || ' | self(alias ' || r.alias || ')='
            || public.fn_kernel_reviewer_independent(v_creator, r.alias)::text;
    end loop;
  end if;

  v_out := v_out || ' | independent_control='
        || public.fn_kernel_reviewer_independent(v_creator, 'general_counsel')::text;
  raise exception 'AL<<%>>', v_out;
end $p$;`, 'AL'));
