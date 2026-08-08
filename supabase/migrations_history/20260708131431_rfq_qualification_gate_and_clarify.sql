-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708131431   name: rfq_qualification_gate_and_clarify
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- HARD GATE: never route an incomplete RFQ. A match cannot be created unless the inquiry is rfq_ready.
create or replace function public.trg_gate_incomplete_match()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare ready boolean;
begin
  select rfq_ready into ready from public.inquiries where id = NEW.inquiry_id;
  if ready is not true then return null; end if;   -- silently skip: incomplete RFQs don't qualify for routing
  return NEW;
end $$;
drop trigger if exists gate_incomplete_match on public.inquiry_matches;
create trigger gate_incomplete_match before insert on public.inquiry_matches
  for each row execute function public.trg_gate_incomplete_match();

-- ADAPTIVE CLARIFICATION: email the customer the exact missing points so they return and complete the RFQ.
create or replace function public.run_rfq_clarify(p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare r record; lbl text; miss_labels text[]; body text; subject text; n int:=0; sample jsonb:='[]'::jsonb; co text;
begin
  for r in
    select i.id, i.summary, i.completeness, c.email cust_email, c.full_name
    from public.inquiries i join public.customers c on c.id=i.customer_id
    where coalesce(i.rfq_ready,false)=false
      and coalesce(i.status,'') not in ('completed','accepted','closed','cancelled','lost')
      and i.created_at > now()-interval '30 days'
      and c.email is not null and c.email <> ''
      and jsonb_array_length(coalesce(i.completeness->'missing','[]'::jsonb)) > 0
      and not exists (select 1 from public.notifications nz where nz.type='inquiry_incomplete'
                        and nz.inquiry_id=i.id and nz.created_at > now()-interval '2 days')
    limit 200
  loop
    miss_labels := '{}';
    for lbl in select jsonb_array_elements_text(r.completeness->'missing') loop
      miss_labels := array_append(miss_labels, case lbl
        when 'category' then 'the type of service / category you need'
        when 'emirate' then 'which emirate the work is in'
        when 'scope_detail' then 'a clear description of the work (scope)'
        when 'scope_type' then 'whether it is a single trade or a full / turnkey job'
        when 'budget' then 'your budget or budget range'
        when 'supporting_detail' then 'supporting details — the trades involved, a drawing, or a bill of quantities (BOQ)'
        else lbl end);
    end loop;
    n := n+1;
    if jsonb_array_length(sample) < 10 then
      sample := sample || jsonb_build_object('inquiry_id',r.id,'to',r.cust_email,'missing',to_jsonb(miss_labels));
    end if;
    if not p_dry_run then
      co := coalesce(nullif(split_part(coalesce(r.full_name,''),' ',1),''),'there');
      subject := 'A few details needed to get you quotes — QuotesDone';
      body := 'Hi '||co||','||E'\n\n'||'Thanks for your request'||coalesce(' ('||left(r.summary,80)||')','')
        ||'. Before we can send it to suppliers and collect quotes, we need a little more information:'||E'\n\n'
        ||'• '||array_to_string(miss_labels, E'\n• ')||E'\n\n'
        ||'Please open your request on QuotesDone and add these details so we can match you to the right suppliers:'||E'\n'
        ||'https://quotesdone.com/app/'||E'\n\n'||'As soon as it is complete we will start collecting quotes for you. Thank you!';
      insert into public.notifications(type,to_email,to_role,inquiry_id,channel,subject,body,status)
        values('inquiry_incomplete', r.cust_email, 'customer', r.id, 'email', subject, body, 'queued');
    end if;
  end loop;
  return jsonb_build_object('ok',true,'dry_run',p_dry_run,'to_notify',n,'sample',sample);
end $$;
revoke execute on function public.run_rfq_clarify(boolean) from anon, authenticated, public;
