-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724153713   name: pure_category_scorer_for_qa
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Pure, table-free category scorer so the daily QA suite can assert the category gate
-- blocks a spec-thin quote for any trade, without inserting rows.
create or replace function public.fn_quote_category_score_text(p_category text, p_text text)
returns jsonb language plpgsql immutable set search_path to 'public','pg_temp'
as $fn$
declare grp text; blob text; r record; tot int:=0; okc int:=0; mand_missing int:=0; miss jsonb:='[]'::jsonb;
begin
  grp := fn_quote_spec_group(coalesce(p_category,''));
  if grp is null or not exists (select 1 from category_quote_specs where spec_group=grp) then
    return jsonb_build_object('applicable',false); end if;
  blob := lower(coalesce(p_text,''));
  for r in select * from category_quote_specs where spec_group=grp loop
    tot := tot + 1;
    if blob ~* r.match_regex then okc := okc + 1;
    else miss := miss || jsonb_build_object('aspect',r.aspect,'mandatory',r.mandatory);
      if r.mandatory then mand_missing := mand_missing + 1; end if; end if;
  end loop;
  return jsonb_build_object('applicable',true,'group',grp,'aspects_total',tot,'aspects_present',okc,
    'mandatory_missing',mand_missing,'category_pass',(mand_missing=0),'missing',miss);
end $fn$;
revoke execute on function public.fn_quote_category_score_text(text,text) from public, anon, authenticated;

-- clean the QA intake row from the live test
delete from public.inquiry_intake where email='qa.intake.audit@quotesdone.com';
