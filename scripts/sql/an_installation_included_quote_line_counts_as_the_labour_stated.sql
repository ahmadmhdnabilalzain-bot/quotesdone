-- it_engineer, 12 Oct 2026, final sandbox run 2 (tag 1c94fa6a). Every demo aluminium quote stayed a DRAFT and the
-- customer's portal showed "0 quotes" (browser walk: "quotes and comparison report - prices on screen: false").
-- Measured on production: quote 721fac77 scored 65 (pass needs 70); missing = brand/model, key specifications and
-- "the labour / installation cost" - although its scope says "Supply, delivery and installation". supplier_api
-- (submit_quote, finding 15) records "installation included in the rate" as install = 0 on the first line, and
-- trg_quote_quality counted only labour > 0 or install > 0, so the stated zero read as "not stated" and cost the
-- quote the 10 points that would have made it 75 and submittable.
-- Fix: a line whose labour or install is STATED (not null, zero included) counts. A line with neither is still
-- missing. Only that filter and the test that reads it change; the rest of the body is the canonical one from
-- quote_quality_trade_keys_and_repeat_requests_are_code_not_the_model.sql. CREATE OR REPLACE keeps the ACL; the
-- revoke/grant below are repeated from the canonical file so this file stands on its own.
-- No backfill: pre-launch there is no real quote; the demo rows of run 1c94fa6a are left as the run recorded them.
-- prevented by: scripts/checks/an_installation_included_line_counts_as_labour_stated.test.mjs

create or replace function public.trg_quote_quality()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare cat text; grp text; v_md5 text; v_present text[]; v_cat_status text := null;
  n int; priced int; branded int; spec_n int; laboured int;
  pts int := 0; gmiss text[] := '{}'; cmiss jsonb := '[]'::jsonb; cmand_missing int := 0;
  r record; cat_pass boolean := true;
begin
  select category into cat from public.inquiries where id = NEW.inquiry_id;

  select count(*),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0),
    count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where labour is not null or install is not null)
    into n, priced, branded, spec_n, laboured
    from public.quote_items where quote_id = NEW.id::text;

  if coalesce(n,0)=0 then gmiss := array_append(gmiss,'an itemised breakdown (not just a lump sum)');
  else pts:=pts+15; if priced=n then pts:=pts+20; else gmiss:=array_append(gmiss,'a unit price on every line'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else gmiss:=array_append(gmiss,'the brand/model for each item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else gmiss:=array_append(gmiss,'the key specifications'); end if;
  if coalesce(laboured,0)>0 then pts:=pts+10; else gmiss:=array_append(gmiss,'the labour / installation cost'); end if;
  if coalesce(btrim(NEW.warranty),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the warranty period'); end if;
  if coalesce(btrim(NEW.lead_time),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the lead / delivery time'); end if;
  if coalesce(btrim(NEW.payment_terms),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the payment terms'); end if;
  if coalesce(btrim(NEW.exclusions),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'what is excluded'); end if;
  if coalesce(btrim(NEW.validity),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'how long the quote is valid'); end if;

  grp := public.fn_quote_spec_group(coalesce(cat,''));
  if grp is not null and exists (select 1 from public.category_quote_specs where spec_group=grp) then
    -- A reading already reasoned for this exact text is used. Without one nothing is asked (24 Sep 2026): the
    -- category status is 'not_read' and the quote is judged on its structural score alone.
    v_md5 := md5(coalesce(public.fn_quote_aspect_text(NEW), ''));
    select a.present into v_present from public.quote_aspect_reading a
     where a.quote_id = NEW.id and a.content_md5 = v_md5 and a.status = 'reasoned';
    if found then
      v_cat_status := 'reasoned';
      for r in select * from public.category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
        if not (r.aspect = any(coalesce(v_present, '{}'::text[]))) then
          cmiss := cmiss || jsonb_build_object('label', r.label, 'mandatory', r.mandatory);
          if r.mandatory then cmand_missing := cmand_missing + 1; end if;
        end if;
      end loop;
      cat_pass := (cmand_missing = 0);
    else
      v_cat_status := 'not_read';
    end if;
  end if;

  NEW.quality := jsonb_build_object(
    'score', pts, 'pass', (pts >= 70 and cat_pass), 'submittable', (pts >= 70 and cat_pass),
    'missing', to_jsonb(gmiss),
    'category', case when grp is null then null else jsonb_build_object(
        'group', grp, 'status', v_cat_status, 'content_md5', v_md5, 'pass', cat_pass,
        'mandatory_missing', case when v_cat_status = 'reasoned' then cmand_missing end,
        'missing', case when v_cat_status = 'reasoned' then cmiss end) end,
    'scored_at', now());
  NEW.submittable := (pts >= 70 and cat_pass);
  return NEW;
end $fn$;
revoke execute on function public.trg_quote_quality() from public, anon, authenticated;
grant execute on function public.trg_quote_quality() to service_role;
