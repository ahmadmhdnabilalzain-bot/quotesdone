-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708134342   name: fix_quote_coach_ambiguous
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_quote_coach(p_quote uuid)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare sc jsonb; lbls text[]; miss text; sup record; co text; subject text; msg text;
begin
  sc := public.fn_quote_structured_score(p_quote::text);
  if (sc->>'submittable')::boolean then return jsonb_build_object('ok',true,'submittable',true); end if;
  lbls := '{}';
  for miss in select jsonb_array_elements_text(sc->'missing') loop
    lbls := array_append(lbls, case miss
      when 'line_items' then 'an itemised breakdown — add each item as a line'
      when 'unit_prices_on_all_items' then 'a unit price on every line item'
      when 'brand_model_per_item' then 'the brand and model for each item'
      when 'specifications' then 'technical specifications for the items'
      when 'labour_or_installation' then 'labour / installation cost'
      when 'warranty' then 'the warranty offered'
      when 'lead_time' then 'the lead time / delivery timeline'
      when 'payment_terms' then 'your payment terms'
      when 'exclusions' then 'what is excluded from the quote'
      when 'validity' then 'how long the quote is valid'
      else miss end);
  end loop;
  select l.company_name, l.claimed_by, l.email into sup
    from public.quotes q join public.leads l on l.id=q.supplier_id where q.id=p_quote;
  co := coalesce(sup.company_name,'there');
  if not exists (select 1 from public.notifications n where n.type='quote_coaching'
                   and n.to_email=coalesce(sup.claimed_by,sup.email) and n.created_at > now()-interval '24 hours'
                   and n.body like '%'||p_quote::text||'%') then
    subject := 'Your quote needs a few more details before we can send it';
    msg := 'Hi '||co||','||E'\n\n'||'Thanks for your quote. To make it competitive and send it to the customer, please add the following in your supplier portal:'||E'\n\n'
      ||'• '||array_to_string(lbls, E'\n• ')||E'\n\n'
      ||'Detailed quotes (with brands, specifications and a clear itemised breakdown) win far more often. Open your portal, complete these, and we will send it to the customer right away.'||E'\n\n'||'(ref '||p_quote::text||')';
    insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('quote_coaching', coalesce(sup.claimed_by,sup.email), 'supplier','email',subject,msg,'queued');
  end if;
  return jsonb_build_object('ok',true,'submittable',false,'missing',lbls,'score',sc->>'score');
end $$;
revoke execute on function public.fn_quote_coach(uuid) from anon, authenticated, public;
