-- AUDIT 7.1, completion. it/code_deploy was being gated by the catch-all - "no row in
-- action_class_gate, therefore not autonomous" - which produces the right answer for the wrong
-- reason. A gated action should say WHICH gate holds it, otherwise the register cannot be reviewed.
insert into public.action_class_gate (action_class, gate_action_class, rationale) values
  ('code_deploy','production_deploy','Promotes code, schema or configuration to production. The gate requires staging and automated tests to pass first.')
on conflict (action_class) do nothing;

-- THE INVARIANT, asserted rather than the change. Every action class a department is allowed to do
-- anything with on its own - autonomous or supervised - must have been reviewed and mapped. A class
-- that reaches this state without a row is exactly the hole 7.1 was about, and it can no longer be
-- created silently: this will fail the next migration that tries.
do $$
declare v_missing text;
begin
  select string_agg(distinct oa.dept_key || '/' || oa.action_class, ', ')
    into v_missing
    from public.org_authority oa
    left join public.action_class_gate g on g.action_class = oa.action_class
   where oa.max_tier in ('autonomous','supervised') and g.action_class is null;

  if v_missing is not null then
    raise exception 'these classes may act without a human but have no reviewed gate mapping: %', v_missing;
  end if;
end $$;;
