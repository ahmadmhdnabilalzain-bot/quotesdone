-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721172923   name: fn_category_sales_restore
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Restores the category_sales sweep I deleted on 18 July. Evidence for the loss:
--   hot_lead   actions created after 18 Jul: 0  (24 before)
--   supply_gap actions created after 18 Jul: 0  (10 before)
-- coverage_gap survives, but that is dispatch_inquiry's PER-INQUIRY signal, not a category sweep.
--
-- hot_lead is the commercially important half: an inquiry sitting on submitted quotes that the
-- customer has not revealed is revenue already earned and not collected. Nothing has been watching
-- for those for three days.
--
-- Rebuilt as a DB function (not an edge function) so it lives in pg_proc where it is visible to
-- schema inspection, and cannot go missing again without leaving a trace.
create or replace function public.fn_category_sales(p_min_age_hours integer default 24)
returns json
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
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
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values (v_slug,'hot_lead','needs_review','medium',
              'Hot lead — ' || v_label || ' / ' || coalesce(nullif(trim(rec.emirate),''),'UAE') ||
                ': ' || rec.n_quotes || ' quote(s), not revealed',
              'nudge the customer to reveal',
              jsonb_build_object('inquiry_id',rec.id,'category',rec.category,'emirate',rec.emirate,
                                 'quotes',rec.n_quotes,'waiting_since',rec.first_quote),
              'inquiries', rec.id::text);
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
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values (v_slug,'supply_gap','needs_review','high',
              'Supply gap — ' || rec.category || ' / ' || rec.emirate || ': no suppliers matched',
              'source or activate suppliers in this category',
              jsonb_build_object('category',rec.category,'emirate',rec.emirate,'inquiries',rec.n_inquiries),
              'inquiries', null);
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
end $function$;

select cron.schedule('category_sales_daily','30 5 * * *', $$select public.fn_category_sales();$$);
