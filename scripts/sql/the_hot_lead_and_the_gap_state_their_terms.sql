-- fn_category_sales: hot_lead and supply_gap now state their assumptions, impact and cost (s36).
-- Definition otherwise byte-identical to production on 13 Aug 2026.

CREATE OR REPLACE FUNCTION public.fn_category_sales(p_min_age_hours integer DEFAULT 24)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_hot int := 0; v_gap int := 0; v_cats int := 0; v_slug text; v_label text;
begin
  ---------------------------------------------------------------- HOT LEADS
  -- Quotes are in, the customer has not revealed. Every one of these is uncollected revenue.
  for rec in
    select i.id, i.category, i.emirate, count(q.id) as n_quotes, min(q.created_at) as first_quote
      from inquiries i
      join quotes q on q.inquiry_id = i.id and q.status = 'submitted'
     where not exists (select 1 from transactions tr where tr.inquiry_id = i.id and tr.revealed_at is not null)
       and coalesce(i.status,'') <> 'split'
     group by i.id, i.category, i.emirate
    having min(q.created_at) < now() - make_interval(hours => p_min_age_hours)
  loop
    v_slug := 'cat:' || lower(coalesce(nullif(trim(rec.category),''),'uncategorised'));
    v_label := coalesce(nullif(trim(rec.category),''),'Uncategorised');
    -- one open hot_lead per inquiry
    if not exists (select 1 from agent_actions
                    where kind = 'hot_lead' and target_id = rec.id::text
                      and status in ('needs_review','pending','open','proposed')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
      values (v_slug,'hot_lead','needs_review','medium',
              'Hot lead — ' || v_label || ' / ' || coalesce(nullif(trim(rec.emirate),''),'UAE') ||
                ': ' || rec.n_quotes || ' quote(s), not revealed',
              'nudge the customer to reveal',
              jsonb_build_object('inquiry_id',rec.id,'category',rec.category,'emirate',rec.emirate,
                                 'quotes',rec.n_quotes,'waiting_since',rec.first_quote),
              'inquiries', rec.id::text,
              -- s36 (13 Aug 2026): what this nudge takes on trust.
              jsonb_build_array(
                'That the customer has SEEN the quotes. The reveal gate hides supplier identity, not the fact that offers arrived; whether they have opened the portal at all is not measured here.',
                'That ' || rec.n_quotes || ' quote(s) is enough to decide on. Quoting is blind, so a customer who is waiting may be waiting for one more comparable offer rather than hesitating over these.',
                'The age is measured from the FIRST quote (' || to_char(rec.first_quote at time zone 'UTC','YYYY-MM-DD HH24:MI') || 'Z), so an inquiry whose quotes arrived days apart looks older than the customer''s actual wait for a comparable set.'),
              'This is the one point in the funnel where money changes hands. A quoted inquiry that is never revealed is the supplier''s work and the platform''s fee both thrown away.',
              'No spend. One nudge to the customer. The reveal fee is theirs to pay and is not a discount to offer.');
      v_hot := v_hot + 1;
    end if;
  end loop;

  ---------------------------------------------------------------- SUPPLY GAPS
  -- Category+emirate combinations where finalized demand found nobody. Feeds supplier activation.
  for rec in
    select coalesce(nullif(trim(i.category),''),'uncategorised') as category,
           coalesce(nullif(trim(i.emirate),''),'UAE') as emirate,
           count(*) as n_inquiries
      from inquiries i
     where i.rfq_ready is true
       and coalesce(i.status,'') <> 'split'
       and not exists (select 1 from inquiry_matches m where m.inquiry_id = i.id)
       and i.created_at > now() - interval '30 days'
     group by 1,2
  loop
    v_slug := 'cat:' || lower(rec.category);
    if not exists (select 1 from agent_actions
                    where kind = 'supply_gap' and agent = v_slug
                      and detail->>'emirate' = rec.emirate
                      and status in ('needs_review','pending','open','proposed')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
      values (v_slug,'supply_gap','needs_review','high',
              'Supply gap — ' || rec.category || ' / ' || rec.emirate || ': no suppliers matched',
              'source or activate suppliers in this category',
              jsonb_build_object('category',rec.category,'emirate',rec.emirate,'inquiries',rec.n_inquiries),
              'inquiries', null,
              -- s36 (13 Aug 2026): what this gap takes on trust.
              jsonb_build_array(
                'A gap means the matcher wrote no inquiry_matches row. That does NOT distinguish "no supplier exists in this category" from "suppliers exist but none has declared this capability" - the second is fixable today and the first is not.',
                'The window is 30 days, so a gap already closed by a supplier who joined yesterday keeps appearing until the inquiry ages out of it.',
                'Category and emirate are the customer''s intake as it was recorded. A mis-categorised inquiry manufactures a gap in a category with no real demand behind it.'),
              'An RFQ in a category with no supplier cannot be quoted at all, so the request is lost before price ever matters. Supply is the binding constraint on revenue.',
              'No spend to decide. Filling it costs invitation volume and sending reputation, which the invite ramp caps - or nothing at all, if a supplier already on file simply has not declared the capability.');
      v_gap := v_gap + 1;
    end if;
  end loop;

  select count(distinct coalesce(nullif(trim(category),''),'uncategorised')) into v_cats from inquiries;

  insert into agent_runs(agent,status,counts,note,started_at,finished_at)
  values ('category_sales','ok',
          jsonb_build_object('hot',v_hot,'gaps',v_gap,'categories',v_cats),
          'category sweep: ' || v_hot || ' new hot lead(s), ' || v_gap || ' new supply gap(s) across ' || v_cats || ' categories',
          now(), now());

  return json_build_object('hot',v_hot,'gaps',v_gap,'categories',v_cats);
end $function$
;
