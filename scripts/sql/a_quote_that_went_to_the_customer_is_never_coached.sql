-- A QUOTE THAT WENT TO THE CUSTOMER IS NEVER COACHED (12 Nov 2026, sales_engineer; final audit of 12 Nov,
-- customer_journey B3 / fix group Q1; founder ledger 1642 "Proceed with fixes").
--
-- MEASURED (final audit, run d9a04dbc, 11-12 Nov 2026): 8 of 8 live quotes. Quote c946acf8: 23:38:45 the customer's
-- new_quote; 23:38:46 the supplier's quote_coaching "Your quote needs a few more details before we can send it ...
-- please add a unit price on every line item ... and we will send it to the customer right away"; 23:38:47 the
-- supplier's quote_spec_released "Your quote is approved ... now with the customer". E-mail and WhatsApp, every quote.
--
-- CAUSE: supplier_api acceptLive called fn_quote_coach after the quote had gone live whenever fn_quote_structured_score
-- said "not submittable", and fn_quote_coach writes the notice on that score alone, whatever the quote's state.
--
-- NOW, the same rule at both layers: the caller coaches only a quote the accept rule refused (it stays a draft:
-- supplier_api/lib/quote_acceptance.ts), and fn_quote_coach itself writes nothing for a quote that is not a draft, or
-- that is waiting on the quality hold (the hold desk sends that supplier its own list of fixes), so no other caller can
-- tell a supplier "before we can send it" about a quote the customer already has. A draft the accept rule refused is
-- still coached once per 24 h with what the score finds missing (the existing guard, unchanged).
-- CREATE OR REPLACE: the ACL is preserved (EXECUTE was revoked from public, anon and authenticated). No new routine.
-- Probe: a_quote_that_went_to_the_customer_is_never_coached_probe.sql (pure, rolls back).
-- prevented by: supabase/functions/supplier_api/a_quote_that_goes_live_is_never_coached.test.ts

create or replace function public.fn_quote_coach(p_quote uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare sc jsonb; lbls text[]; miss text; sup record; co text; subject text; msg text; v_status text; v_held boolean := false;
begin
  -- Only a draft the accept rule refused is coached: a quote with the customer (submitted, revealed, ...) never is, and
  -- a quality-held draft hears from the hold desk, not from here.
  select coalesce(q.status, 'draft') into v_status from public.quotes q where q.id = p_quote;
  if v_status is distinct from 'draft' then
    return jsonb_build_object('ok', true, 'coached', false, 'reason', 'not_a_draft', 'status', v_status);
  end if;
  begin
    select exists (select 1 from public.quote_quality_hold h where h.quote_id = p_quote and h.released_at is null and h.superseded_at is null) into v_held;
  exception when undefined_table then v_held := false;
  end;
  if v_held then return jsonb_build_object('ok', true, 'coached', false, 'reason', 'quality_hold'); end if;

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
end $function$;

select case
  when (select prosrc from pg_proc where oid = 'public.fn_quote_coach(uuid)'::regprocedure) not like '%not_a_draft%'
    then 'PROBE FAILED: fn_quote_coach still coaches a quote that is not a draft'
  when has_function_privilege('anon', 'public.fn_quote_coach(uuid)', 'execute')
    then 'PROBE FAILED: anon can execute fn_quote_coach'
  else 'PROBE OK' end as verdict;
