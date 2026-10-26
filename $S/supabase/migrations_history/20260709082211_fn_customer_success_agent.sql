-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709082211   name: fn_customer_success_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_customer_success()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_kpis jsonb; n_checkin int:=0; n_reengage int:=0; n_esc int:=0; rec record; v_subject text; v_body text;
begin
  -- snapshot KPIs
  select to_jsonb(k) into v_kpis from public.customer_kpis k;
  insert into public.customer_kpi_snapshots(snapshot_date,kpis) values(current_date,coalesce(v_kpis,'{}'::jsonb))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- FOLLOW-UP (operational, auto-send): project check-in — revealed but not completed for 7+ days
  for rec in
    select i.id as inquiry_id, i.customer_id, c.full_name, c.email, i.category
    from inquiries i join customers c on c.id=i.customer_id
    where i.status='revealed' and i.completed_at is null
      and coalesce(i.stage_changed_at,i.created_at) < now()-interval '7 days'
      and coalesce(c.banned,false)=false and c.email like '%@%'
      and not exists (select 1 from notifications n where n.type='customer_checkin' and n.body like '%'||i.id::text||'%' and n.created_at>now()-interval '21 days')
    limit 200
  loop
    v_subject:='How is your '||coalesce(rec.category,'project')||' going?';
    v_body:='Hi '||coalesce(rec.full_name,'there')||E',\n\nWe wanted to check in on your '||coalesce(rec.category,'project')||' booked through QuotesDone. Is everything going well with your supplier?\n\nIf you need anything — a hand resolving an issue, another quote, or help with your next project — just reply to this email. We are here to help.\n\n(ref '||rec.inquiry_id||')';
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('customer_checkin',rec.email,'customer','email',v_subject,v_body,'queued');
    n_checkin:=n_checkin+1;
  end loop;

  -- FOLLOW-UP (operational, auto-send): re-engagement — last project 30+ days ago, no new inquiry since
  for rec in
    select c.id as customer_id, c.full_name, c.email
    from customers c
    where coalesce(c.banned,false)=false and c.email like '%@%'
      and exists (select 1 from inquiries i where i.customer_id=c.id and (i.status='revealed' or i.completed_at is not null))
      and (select max(created_at) from inquiries i where i.customer_id=c.id) < now()-interval '30 days'
      and not exists (select 1 from notifications n where n.type='customer_reengage' and n.to_email=c.email and n.created_at>now()-interval '45 days')
    limit 200
  loop
    v_subject:='Planning your next project?';
    v_body:='Hi '||coalesce(rec.full_name,'there')||E',\n\nIt has been a little while since your last project on QuotesDone. Whenever you are planning your next one — big or small — post it in a minute and compare anonymous quotes from vetted UAE suppliers.\n\nStart here: https://quotesdone.com/app\n\nHappy to help anytime.';
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('customer_reengage',rec.email,'customer','email',v_subject,v_body,'queued');
    n_reengage:=n_reengage+1;
  end loop;

  -- ESCALATIONS to founder (never auto-resolve): disputes/refunds, reveal non-response, bad reviews, complaints
  for rec in
    select 'dispute' as sig, t.customer_id as cid, coalesce(c.full_name,'customer') as who, t.id::text as ref,
      'Refund/dispute open — review and resolve.' as msg, 'high' as risk
    from transactions t join customers c on c.id=t.customer_id
    where (t.refund_status is not null or (t.refund_requested_at is not null and t.refund_resolved_at is null))
    union all
    select 'reveal_no_response', t.customer_id, coalesce(c.full_name,'customer'), t.id::text,
      'Customer paid to reveal but supplier has not acknowledged within 48h — service risk.', 'high'
    from transactions t join customers c on c.id=t.customer_id
    where t.supplier_ack_at is null and t.revealed_at is not null and t.revealed_at < now()-interval '48 hours' and t.refund_status is null
    union all
    select 'bad_review', r.customer_id, coalesce(c.full_name,'customer'), r.id::text,
      'Low review left ('||r.rating||'/5) — follow up on dissatisfaction.', 'medium'
    from reviews r join customers c on c.id=r.customer_id where r.rating<=2
    union all
    select 'complaint', c.id, coalesce(c.full_name,'customer'), im.id::text,
      'Inbound complaint from customer — needs attention.', 'high'
    from inbound_messages im join customers c on lower(c.email)=lower(im.from_email)
    where im.ai_category ilike '%complaint%' and im.replied_at is null
  loop
    if not exists (select 1 from agent_actions a where a.kind='customer_escalation' and a.detail->>'signal'=rec.sig and a.detail->>'ref'=rec.ref and a.status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values('customer_success','customer_escalation','pending',rec.risk,
        'Customer '||rec.sig||': '||rec.who, rec.msg,
        jsonb_build_object('signal',rec.sig,'ref',rec.ref,'customer',rec.who),
        'customers', rec.cid::text);
      n_esc:=n_esc+1;
    end if;
  end loop;

  return jsonb_build_object('ran_at',now(),'kpis',v_kpis,'checkins_queued',n_checkin,'reengage_queued',n_reengage,'escalations',n_esc);
end $fn$;

revoke all on function public.fn_customer_success() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('customer_success','Customer Success','💚',true,
  'Ensures customer satisfaction across the journey. Monitors response times, project progress, complaints, reviews, disputes and opportunities; scores per-customer health and churn risk. Auto-sends helpful operational follow-ups (project check-ins, next-project re-engagement) and ESCALATES complaints, disputes/refunds, reveal non-response and low reviews to the founder. Never issues refunds, moves money, cancels projects or deletes customers on its own.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('customer_success_daily','40 6 * * *', $$select public.fn_customer_success();$$);
