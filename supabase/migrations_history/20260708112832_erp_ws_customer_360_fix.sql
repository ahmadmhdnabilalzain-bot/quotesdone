-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708112832   name: erp_ws_customer_360_fix
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_customer_360(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare c public.customers%rowtype; j jsonb;
  ltv numeric(18,2); deal_value numeric(18,2); reveals int;
  rfqs_total int; rfqs_active int; rfqs_done int; avg_budget numeric(18,2);
  last_act timestamptz; score int; cats text; docs jsonb := '[]'::jsonb; summary text;
begin
  select * into c from public.customers where id=p_id;
  if c.id is null then return jsonb_build_object('error','customer not found'); end if;

  select coalesce(sum(reveal_fee) filter (where fee_status='paid'),0), coalesce(sum(quote_amount),0), count(*)
    into ltv, deal_value, reveals from public.transactions where customer_id=p_id;
  select count(*), count(*) filter (where status not in ('completed','cancelled','closed','lost')),
         count(*) filter (where status in ('completed','closed') or outcome='completed'),
         coalesce(round(avg(nullif(expected_value,0)),2),0)
    into rfqs_total, rfqs_active, rfqs_done, avg_budget from public.inquiries where customer_id=p_id;
  select string_agg(distinct category, ', ') into cats from public.inquiries where customer_id=p_id and category is not null;

  select greatest(coalesce(max(i.created_at), c.created_at),
                  coalesce((select max(revealed_at) from public.transactions where customer_id=p_id), c.created_at),
                  c.created_at)
    into last_act from public.inquiries i where i.customer_id=p_id;
  last_act := coalesce(last_act, c.created_at);

  score := least(100, greatest(0,
      coalesce(rfqs_total,0)*12 + coalesce(reveals,0)*25 + round(coalesce(ltv,0)/20)::int
      + (case when last_act > now() - interval '30 days' then 15 else 0 end)));

  docs := coalesce((select jsonb_agg(jsonb_build_object('type','Drawing','name',coalesce(drawing_file_name,'drawing'),'path',drawing_file_path))
                    from public.inquiries where customer_id=p_id and drawing_file_path is not null),'[]'::jsonb);
  if c.signed_terms_path is not null then docs := docs || jsonb_build_object('type','Signed terms','name','terms','path',c.signed_terms_path); end if;

  summary := c.full_name||' joined '||to_char(c.created_at,'Mon YYYY')||'. '
    ||coalesce(rfqs_total,0)||' RFQ(s)'||coalesce(' across '||cats,'')||'. '
    ||coalesce(reveals,0)||' reveal(s), AED '||to_char(coalesce(ltv,0),'FM999999990.00')||' paid to date.'
    ||(case when avg_budget>0 then ' Avg project budget AED '||to_char(avg_budget,'FM999999990') else '' end)
    ||(case when c.banned then ' [BANNED]' when not coalesce(c.email_verified,false) then ' Email unverified.' else '' end);

  j := jsonb_build_object(
    'profile', jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
       'created_at',c.created_at,'phone_verified',c.phone_verified,'email_verified',c.email_verified,
       'banned',c.banned,'banned_reason',c.banned_reason,'wa_optin',c.wa_optin,'tos_accepted_at',c.tos_accepted_at,
       'chat_strikes',c.chat_strikes),
    'metrics', jsonb_build_object('ltv',ltv,'total_deal_value',deal_value,'reveals',reveals,
       'rfqs_total',rfqs_total,'rfqs_active',rfqs_active,'rfqs_completed',rfqs_done,
       'avg_project_budget',avg_budget,'relationship_score',score),
    'ai_summary', summary,
    'preferences', jsonb_build_object(
       'categories', coalesce((select jsonb_agg(distinct category) from public.inquiries where customer_id=p_id and category is not null),'[]'::jsonb),
       'emirates', coalesce((select jsonb_agg(distinct emirate) from public.inquiries where customer_id=p_id and emirate is not null),'[]'::jsonb)),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'category',i.category,'emirate',i.emirate,
       'status',i.status,'pipeline_stage',i.pipeline_stage,'budget',i.expected_value,
       'outcome',i.outcome,'created_at',i.created_at) order by i.created_at desc)
       from (select * from public.inquiries where customer_id=p_id order by created_at desc limit 15) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
       from public.quotes q join public.inquiries i on i.id=q.inquiry_id where i.customer_id=p_id),'[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(jsonb_build_object('quote_amount',t.quote_amount,'reveal_fee',t.reveal_fee,'fee_status',t.fee_status,'revealed_at',t.revealed_at) order by t.revealed_at desc)
       from public.transactions t where t.customer_id=p_id),'[]'::jsonb),
    'documents', docs,
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',c.created_at,'event','Signed up') e
        union all select jsonb_build_object('at',i.created_at,'event','RFQ: '||coalesce(i.category,'inquiry')) from public.inquiries i where i.customer_id=p_id
        union all select jsonb_build_object('at',t.revealed_at,'event','Revealed supplier · AED '||coalesce(t.reveal_fee::text,'0')||' fee') from public.transactions t where t.customer_id=p_id and t.revealed_at is not null
      ) tl)
  );
  return j;
end $$;

revoke execute on function public.fn_ws_customer_360(uuid) from anon, authenticated, public;
