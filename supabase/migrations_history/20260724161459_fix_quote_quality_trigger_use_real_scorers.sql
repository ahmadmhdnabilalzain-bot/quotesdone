-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724161459   name: fix_quote_quality_trigger_use_real_scorers
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- trg_quote_quality was writing quotes.quality via the DEAD quote_gate() (quote_requirements
-- empty -> always "score 100, no standard"). Rewrite it to compute REAL completeness inline
-- from NEW + quote_items: generic structured score + category-aware domain-spec check.
create or replace function public.trg_quote_quality()
 returns trigger language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare cat text; grp text; blob text; v_items text;
  n int; priced int; branded int; spec_n int; laboured int;
  pts int := 0; gmiss text[] := '{}'; cmiss jsonb := '[]'::jsonb; cmand_missing int := 0;
  r record; cat_pass boolean := true;
begin
  select category into cat from inquiries where id = NEW.inquiry_id;

  select count(*),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0),
    count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where coalesce(labour,0)>0 or coalesce(install,0)>0)
    into n, priced, branded, spec_n, laboured
    from public.quote_items where quote_id = NEW.id::text;

  -- generic completeness (mirrors fn_quote_structured_score)
  if coalesce(n,0)=0 then gmiss := gmiss||'an itemised breakdown (not just a lump sum)';
  else pts:=pts+15; if priced=n then pts:=pts+20; else gmiss:=gmiss||'a unit price on every line'; end if; end if;
  if n>0 and branded=n then pts:=pts+15; else gmiss:=gmiss||'the brand/model for each item'; end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else gmiss:=gmiss||'the key specifications'; end if;
  if coalesce(laboured,0)>0 then pts:=pts+10; else gmiss:=gmiss||'the labour / installation cost'; end if;
  if coalesce(btrim(NEW.warranty),'')<>'' then pts:=pts+6; else gmiss:=gmiss||'the warranty period'; end if;
  if coalesce(btrim(NEW.lead_time),'')<>'' then pts:=pts+6; else gmiss:=gmiss||'the lead / delivery time'; end if;
  if coalesce(btrim(NEW.payment_terms),'')<>'' then pts:=pts+6; else gmiss:=gmiss||'the payment terms'; end if;
  if coalesce(btrim(NEW.exclusions),'')<>'' then pts:=pts+6; else gmiss:=gmiss||'what is excluded'; end if;
  if coalesce(btrim(NEW.validity),'')<>'' then pts:=pts+6; else gmiss:=gmiss||'how long the quote is valid'; end if;

  -- category-aware domain specs
  grp := fn_quote_spec_group(coalesce(cat,''));
  if grp is not null and exists (select 1 from category_quote_specs where spec_group=grp) then
    select string_agg(concat_ws(' ',description,brand,model,specification),' ')
      into v_items from public.quote_items where quote_id = NEW.id::text;
    blob := lower(concat_ws(' ', NEW.scope, NEW.conditions, NEW.exclusions, NEW.notes,
             NEW.warranty, NEW.payment_terms, NEW.lead_time, NEW.validity, v_items));
    for r in select * from category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
      if not (coalesce(blob,'') ~* r.match_regex) then
        cmiss := cmiss || jsonb_build_object('label', r.label, 'mandatory', r.mandatory);
        if r.mandatory then cmand_missing := cmand_missing + 1; end if;
      end if;
    end loop;
    cat_pass := (cmand_missing = 0);
  end if;

  NEW.quality := jsonb_build_object(
    'score', pts,
    'pass', (pts >= 70 and cat_pass),
    'submittable', (pts >= 70 and cat_pass),
    'missing', to_jsonb(gmiss),
    'category', case when grp is null then null else jsonb_build_object(
        'group', grp, 'pass', cat_pass, 'mandatory_missing', cmand_missing, 'missing', cmiss) end,
    'scored_at', now());
  NEW.submittable := (pts >= 70 and cat_pass);
  return NEW;
end $function$;
