-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721170306   name: fn_supplier_capability_chase
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #83 — nobody is in the loop, so a supplier who stalls mid-onboarding must be chased by the system.
-- Two distinct failure modes, both of which end with a supplier silently receiving zero work:
--   A. capability record exists but is insufficient / unconfirmed -> chase them with the EXACT missing list
--   B. approved supplier with NO capability record at all -> invisible to fn_match_capability entirely
create or replace function public.fn_supplier_capability_chase(p_days integer default 3, p_max_chases integer default 3)
returns json
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  rec record; v_sent int := 0; v_skipped int := 0; v_escalated int := 0; v_orphans int := 0;
  v_to text; v_chases int; v_ask text;
begin
  ---------------------------------------------------------------- A. stalled records
  for rec in
    select sc.supplier_id, sc.review_status, sc.missing_fields, sc.updated_at,
           l.company_name, l.claimed_by, l.email
      from supplier_capabilities sc
      join leads l on l.id = sc.supplier_id
     where sc.confirmed_at is null
       and sc.review_status in ('insufficient','awaiting_confirmation')
       and sc.updated_at < now() - make_interval(days => p_days)
       and coalesce(l.banned,false) = false
       and coalesce(l.permanently_closed,false) = false
  loop
    select count(*) into v_chases from notifications
     where type = 'capability_chase' and lead_id = rec.supplier_id;

    -- Stop emailing after p_max_chases and hand to supplier_success as an action instead.
    if v_chases >= p_max_chases then
      if not exists (select 1 from agent_actions
                      where agent='supplier_success' and kind='capability_stalled'
                        and target_id = rec.supplier_id::text and status in ('needs_review','pending')) then
        insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
        values ('supplier_success','capability_stalled','needs_review','medium',
                'Supplier stalled in onboarding: ' || coalesce(rec.company_name,'#'||rec.supplier_id),
                'Chased ' || v_chases || ' times with no response. They cannot receive any inquiry until their scope is confirmed. Consider a call, or retire the registration.',
                jsonb_build_object('supplier_id',rec.supplier_id,'review_status',rec.review_status,
                                   'missing',to_jsonb(rec.missing_fields),'chases',v_chases),
                'leads', rec.supplier_id::text);
        v_escalated := v_escalated + 1;
      end if;
      continue;
    end if;

    -- one chase per 5 days
    if exists (select 1 from notifications where type='capability_chase' and lead_id=rec.supplier_id
                 and created_at > now() - interval '5 days') then
      v_skipped := v_skipped + 1; continue;
    end if;

    v_to := nullif(trim(coalesce(rec.claimed_by, rec.email)), '');
    if v_to is null or position('@' in v_to) = 0 then v_skipped := v_skipped + 1; continue; end if;

    -- Reuse the agent's own wording. A generic "please complete your profile" is why these stall.
    v_ask := coalesce(
      (select string_agg('  • ' || m, chr(10)) from unnest(rec.missing_fields) m),
      '  • a company profile or catalogue describing the products and services you supply');

    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('capability_chase', v_to, 'supplier', rec.supplier_id, 'email',
      case when rec.review_status='awaiting_confirmation'
           then 'One step left — confirm what your company does'
           else 'We need a little more to start sending you work' end,
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      case when rec.review_status='awaiting_confirmation'
        then 'We have read your documents and prepared a summary of what your company does. We just need you to confirm it is correct before we start matching you to customer requests.'
        else 'We have reviewed the documents you uploaded, but we cannot yet tell precisely what work to send you. Until we can, you will not receive customer requests — we would rather send you nothing than send you jobs you do not do.'
      end || chr(10) || chr(10) ||
      case when rec.review_status='awaiting_confirmation' then 'Open the Profile tab in your supplier portal to confirm.'
           else 'What we still need:' || chr(10) || v_ask end || chr(10) || chr(10) ||
      'This takes a couple of minutes and only needs doing once.' || chr(10) || chr(10) ||
      'QuotesDone',
      'queued');
    v_sent := v_sent + 1;
  end loop;

  ---------------------------------------------------------------- B. approved but no record at all
  for rec in
    select l.id as supplier_id, l.company_name
      from leads l
      left join supplier_capabilities sc on sc.supplier_id = l.id
     where l.approval_status = 'approved'
       and coalesce(l.banned,false) = false
       and coalesce(l.matching_blocked,false) = false
       and sc.supplier_id is null
  loop
    if not exists (select 1 from agent_actions
                    where agent='supplier_success' and kind='capability_missing'
                      and target_id = rec.supplier_id::text and status in ('needs_review','pending')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('supplier_success','capability_missing','needs_review','high',
              'Approved supplier has no capability record: ' || coalesce(rec.company_name,'#'||rec.supplier_id),
              'This supplier is approved but invisible to matching, because fn_match_capability requires a supplier-confirmed capability record. They will receive zero inquiries and will conclude the platform does not work. Run capability_agent analyze for them.',
              jsonb_build_object('supplier_id',rec.supplier_id),
              'leads', rec.supplier_id::text);
      v_orphans := v_orphans + 1;
    end if;
  end loop;

  insert into agent_runs(agent,status,counts,note,started_at,finished_at)
  values ('supplier_success','ok',
          jsonb_build_object('chased',v_sent,'skipped',v_skipped,'escalated',v_escalated,'no_capability_record',v_orphans),
          'capability chase: ' || v_sent || ' chased, ' || v_escalated || ' escalated after ' || p_max_chases ||
          ' attempts, ' || v_orphans || ' approved supplier(s) flagged with no capability record at all',
          now(), now());

  return json_build_object('chased',v_sent,'skipped',v_skipped,'escalated',v_escalated,'no_capability_record',v_orphans);
end $function$;

select cron.schedule('supplier_capability_chase_daily','30 6 * * *',
                     $$select public.fn_supplier_capability_chase();$$);
