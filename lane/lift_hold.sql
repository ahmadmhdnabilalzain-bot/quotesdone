do $$
declare v_id bigint;
begin
  insert into public.founder_instruction (instruction, said_at)
  values ('7 Oct: "from now on keep open router always on" - founder lifted the paid-model hold on all 19 llm_route_health routes permanently; failure circuit breakers still trip on real errors.', now())
  returning id into v_id;
  perform set_config('app.change_reason', 'founder:' || v_id, true);
  update public.llm_route_health
     set open_until = null,
         opened_reason = 'founder:' || v_id || ' keep OpenRouter always on (hold lifted 7 Oct 2026)',
         updated_at = now()
   where open_until > now();
end $$;
select count(*) filter (where open_until > now()) still_held,
       public.fn_kernel_paid_provider_gate((select model_id from public.model_registry where active limit 1))->>'rule' gate_rule,
       (select max(id) from public.founder_instruction) ledger
  from public.llm_route_health;
