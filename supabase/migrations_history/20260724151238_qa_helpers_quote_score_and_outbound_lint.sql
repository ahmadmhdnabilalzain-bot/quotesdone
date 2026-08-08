-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724151238   name: qa_helpers_quote_score_and_outbound_lint
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Pure, table-free quote scorer mirroring fn_quote_structured_score's logic, so the daily
-- QA suite can assert the gate blocks incomplete quotes WITHOUT inserting/deleting rows.
create or replace function public.fn_quote_score_json(p_quote jsonb, p_items jsonb)
returns jsonb language plpgsql immutable set search_path to 'public','pg_temp'
as $fn$
declare n int; priced int; branded int; laboured int; spec_n int; pts int:=0; miss text[]:='{}'; it jsonb;
begin
  n:=0; priced:=0; branded:=0; laboured:=0; spec_n:=0;
  for it in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    n:=n+1;
    if coalesce((it->>'unit_price')::numeric,0) > 0 then priced:=priced+1; end if;
    if coalesce(it->>'brand','')<>'' and coalesce(it->>'model','')<>'' then branded:=branded+1; end if;
    if (it->>'labour') is not null or (it->>'install') is not null then laboured:=laboured+1; end if;
    if coalesce(it->>'specification','')<>'' then spec_n:=spec_n+1; end if;
  end loop;
  if n=0 then miss:=array_append(miss,'line_items');
  else pts:=pts+15; if priced=n then pts:=pts+20; else miss:=array_append(miss,'unit_prices_on_all_items'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else miss:=array_append(miss,'brand_model_per_item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else miss:=array_append(miss,'specifications'); end if;
  if laboured>0 then pts:=pts+10; else miss:=array_append(miss,'labour_or_installation'); end if;
  if coalesce(p_quote->>'warranty','')<>'' then pts:=pts+6; else miss:=array_append(miss,'warranty'); end if;
  if coalesce(p_quote->>'lead_time','')<>'' then pts:=pts+6; else miss:=array_append(miss,'lead_time'); end if;
  if coalesce(p_quote->>'payment_terms','')<>'' then pts:=pts+6; else miss:=array_append(miss,'payment_terms'); end if;
  if coalesce(p_quote->>'exclusions','')<>'' then pts:=pts+6; else miss:=array_append(miss,'exclusions'); end if;
  if coalesce(p_quote->>'validity','')<>'' then pts:=pts+6; else miss:=array_append(miss,'validity'); end if;
  return jsonb_build_object('score',pts,'submittable',pts>=70,'items',n,'missing',to_jsonb(miss));
end $fn$;
revoke execute on function public.fn_quote_score_json(jsonb,jsonb) from public, anon, authenticated;

-- Outbound-reply linter: any public-assistant reply in the last N hours that contradicts
-- current policy (the same forbid_regex rules) is a regression — an agent SAID something wrong.
create or replace function public.fn_lint_outbound(p_hours int default 24)
returns jsonb language sql security definer set search_path to 'public','pg_temp'
as $fn$
  select jsonb_build_object(
    'hits', count(*),
    'sample', coalesce(jsonb_agg(jsonb_build_object('when',a.created_at,'rule',p.name,'reply',left(a.reply,160))) filter (where p.id is not null), '[]'::jsonb)
  )
  from assistant_logs a
  left join policy_rules p on p.active and a.reply ~* p.forbid_regex
  where a.created_at > now() - make_interval(hours => p_hours)
    and p.id is not null;
$fn$;
revoke execute on function public.fn_lint_outbound(int) from public, anon, authenticated;

-- Standing QA customer credentials (auth user already minted: qa.intake.audit@quotesdone.com)
insert into app_secrets(key,value) values
 ('qa_customer_email','qa.intake.audit@quotesdone.com'),
 ('qa_customer_password','QaAudit!2026x')
on conflict (key) do update set value=excluded.value;
