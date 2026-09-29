CREATE OR REPLACE FUNCTION public.fn_cad_read_claim(p_limit integer DEFAULT 3)
 RETURNS SETOF cad_read_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.cad_read_jobs j
     set status = 'failed', finished_at = now(),
         error = coalesce(j.error, 'the reader stopped three times without finishing')
   where j.status in ('queued', 'running') and j.attempts >= 3
     and (j.status = 'queued' or j.claimed_at < now() - interval '30 minutes');
  return query
  update public.cad_read_jobs j
     set status = 'running', attempts = j.attempts + 1, claimed_at = now()
   where j.id in (
     select c.id from public.cad_read_jobs c
      where c.attempts < 3
        and (c.status = 'queued' or (c.status = 'running' and c.claimed_at < now() - interval '30 minutes'))
      order by c.created_at
      limit greatest(1, least(coalesce(p_limit, 3), 10))
      for update skip locked)
  returning j.*;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_cancel_inquiry(p_inquiry uuid, p_customer uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v inquiries%rowtype; v_paid boolean; v_cnt int; v_warned boolean:=false; v_email text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  if v.status='cancelled' or v.pipeline_stage='cancelled' then
    return jsonb_build_object('ok',true,'already_cancelled',true); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed') or v.pipeline_stage in ('revealed','won') then
    return jsonb_build_object('error','already_revealed',
      'message','This request already has an active revealed deal and cannot be cancelled. You can close it instead.'); end if;

  update inquiries set status='cancelled', pipeline_stage='cancelled', outcome='cancelled',
      lost_reason=coalesce(p_reason,'customer_cancelled'), completed_at=now(), stage_changed_at=now()
    where id=p_inquiry;
  insert into inquiry_cancellations(inquiry_id,customer_id,reason) values (p_inquiry, v.customer_id, p_reason);

  select count(*) into v_cnt from inquiry_cancellations where customer_id=v.customer_id and created_at > now()-interval '30 days';
  if v.customer_id is not null and v_cnt >= 3 then
    select email into v_email from customers where id=v.customer_id;
    if v_email is not null and position('@' in v_email)>1
       and not exists (select 1 from notifications where type='cancel_warning' and to_email=v_email and created_at > now()-interval '30 days') then
      insert into notifications(type,to_email,to_role,inquiry_id,subject,body,channel,status)
      values('cancel_warning', v_email, 'customer', p_inquiry,
        'A quick note about cancelled requests',
        'We noticed a few of your recent requests were cancelled. That is completely fine — but every request you post is prepared and quoted by suppliers who set aside real time for it. To keep things fair for them, we kindly ask that you post requests you intend to proceed with. If you would like help scoping a job before posting, our team is glad to assist.',
        'email','queued');
      v_warned:=true;
    end if;
  end if;
  return jsonb_build_object('ok',true,'cancelled',true,'cancellations_30d',v_cnt,'warned',v_warned);
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_correct(p_source_table text, p_source_id text, p_by text, p_correction text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_c text := public.fn_case_mask(p_correction);
begin
  if coalesce(v_c, '') = '' then return null; end if;
  update public.seat_case_memory m
     set corrected_by = p_by, correction = v_c,
         lessons = case when ('Corrected by ' || p_by || ': ' || v_c) = any (m.lessons) then m.lessons
                        else m.lessons || ('Corrected by ' || p_by || ': ' || v_c) end,
         updated_at = now()
   where m.source_table = p_source_table and m.source_id = p_source_id
  returning id into v_id;
  return v_id;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_case_embed_claim(p_limit integer DEFAULT 8)
 RETURNS TABLE(id bigint, text text, hash text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with pick as (
    select m.id from public.seat_case_memory m
     where m.embedding is null
       and (m.embed_claimed_at is null or m.embed_claimed_at < now() - interval '3 minutes')
     order by m.id
     limit greatest(1, least(coalesce(p_limit, 8), 200))
     for update skip locked
  )
  update public.seat_case_memory m set embed_claimed_at = now()
    from pick where m.id = pick.id
  returning m.id, left(m.situation, 1200), md5(m.situation);
$function$


CREATE OR REPLACE FUNCTION public.fn_case_embed_write(p_id bigint, p_embedding vector, p_hash text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  with u as (
    update public.seat_case_memory m
       set embedding = p_embedding, embedded_hash = p_hash, embed_claimed_at = null
     where m.id = p_id and md5(m.situation) = p_hash
    returning 1)
  select exists (select 1 from u);
$function$


CREATE OR REPLACE FUNCTION public.fn_case_from_campaign(n marketing_campaign, o marketing_campaign DEFAULT NULL::marketing_campaign)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    if not coalesce(n.is_demo, false) then
      perform public.fn_case_remember('marketing', 'campaign_plan', 'marketing_campaign', n.id::text, null,
        concat_ws(' | ', n.title, 'theme: ' || n.theme, 'month ' || n.month, 'spend: ' || n.spend_policy),
        case when n.approved_at is not null then 'plan approved by ' || coalesce(n.approved_by, 'the founder') else 'plan sent for approval' end,
        null, case when n.approved_at is not null then 'approved' end,
        n.approved_at is not null, '{}', n.created_at, null);
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('marketing_campaign', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_ceo_approval(n ceo_approval, o ceo_approval DEFAULT NULL::ceo_approval)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('ceo', 'approval:' || n.subject_kind, 'ceo_approval', n.decision_id::text, null,
      concat_ws(' | ', n.subject_kind || ' ' || n.decision || ': ' || n.rationale, 'AED ' || n.amount_aed), n.decision,
      n.rationale, n.decision, true, '{}', n.decided_at, null);
    if n.decision = 'refused' then
      perform public.fn_case_correct(
        case n.subject_kind when 'refund' then 'refund_case' when 'publication' then 'marketing_campaign' end,
        n.subject_id, 'ceo', 'Refused by the CEO: ' || n.rationale);
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('ceo_approval', n.decision_id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_ceo_decision_log(n ceo_decision_log, o ceo_decision_log DEFAULT NULL::ceo_decision_log)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('ceo', 'decision', 'ceo_decision_log', n.id::text, null,
      concat_ws(' | ', n.decision_key, n.reading_before), n.the_decision, null,
      concat_ws('; ', n.outcome, 'after: ' || n.reading_after, 'founder: ' || n.founder_answer),
      n.outcome is not null, '{}', n.decided_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('ceo_decision_log', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_complaint(n complaint_tickets, o complaint_tickets DEFAULT NULL::complaint_tickets)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('customer_support', 'complaint', 'complaint_tickets', n.id::text, null,
      n.message, 'status ' || n.status, n.decision_ref, n.final_response,
      n.final_response_at is not null, array[n.name, n.email], n.created_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('complaint_tickets', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_decision_record(n decision_record, o decision_record DEFAULT NULL::decision_record)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('ceo', 'decision_record', 'decision_record', n.id::text, null,
      concat_ws(' | ', n.problem, left(n.context, 600)), n.recommendation,
      concat_ws('; ', 'expected: ' || n.expected_outcome, 'risks: ' || n.risks),
      concat_ws('; ', 'status ' || n.status, n.actual_outcome),
      n.actual_outcome is not null or n.status in ('executed','obsolete','rejected','reversed'),
      '{}', n.created_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('decision_record', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_expense(n expense_entries, o expense_entries DEFAULT NULL::expense_entries)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('accountant', 'expense_classification', 'expense_entries', n.id::text, null,
      concat_ws(' | ', 'vendor ' || n.vendor, n.currency || ' ' || n.amount, n.doc_kind, n.note, n.doc_note),
      'classified as ' || coalesce(n.category, 'unclassified'), null, n.category,
      n.category is not null, '{}', n.created_at, null);
    if o.category is not null and n.category is distinct from o.category then
      perform public.fn_case_correct('expense_entries', n.id::text, 'accountant',
        'Re-classified from ' || o.category || ' to ' || coalesce(n.category, 'unclassified'));
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('expense_entries', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_inquiry(n inquiries, o inquiries DEFAULT NULL::inquiries)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_known text[]; v_fin boolean;
begin
  begin
    select array[c.full_name, c.email, c.phone, c.whatsapp_phone] into v_known
      from public.customers c where c.id = n.customer_id;
    v_fin := n.completed_at is not null or n.outcome is not null or n.lost_reason is not null
             or n.status in ('revealed','expired','cancelled','canceled','closed','won','lost','completed');
    perform public.fn_case_remember('sales_engineer', 'inquiry', 'inquiries', n.id::text,
      coalesce(n.trades[1], n.category),
      concat_ws(' | ', coalesce(n.summary_masked, n.summary), left(coalesce(n.raw_input_masked, n.raw_input), 600),
                'category: ' || n.category, 'emirate: ' || n.emirate, 'scope: ' || n.scope_type),
      concat_ws('; ', 'status ' || n.status, 'stage ' || n.pipeline_stage,
                case when n.hired_supplier_id is not null then 'supplier hired' end),
      null,
      concat_ws('; ', n.outcome, 'lost: ' || n.lost_reason),
      v_fin, coalesce(v_known, '{}'), n.created_at,
      case when n.lost_reason is not null then 'Lost because: ' || n.lost_reason end);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('inquiries', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_it_finding(n it_engineer_finding, o it_engineer_finding DEFAULT NULL::it_engineer_finding)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('it_engineer', 'it_finding', 'it_engineer_finding', n.issue_key, null,
      concat_ws(' | ', n.title, 'where: ' || n.where_it_is, 'blast: ' || n.blast),
      case when n.closed_at is not null then 'closed' else 'open' end,
      array_to_string(n.ruled_out, '; '), n.close_note,
      n.closed_at is not null, '{}', n.started_at,
      case when n.closed_at is not null and n.close_note is not null then 'Fixed by: ' || n.close_note end);
    if o.closed_at is not null and n.closed_at is null then
      perform public.fn_case_correct('it_engineer_finding', n.issue_key, 'it_engineer',
        'Reopened: the earlier fix (' || coalesce(o.close_note, 'no note') || ') did not hold');
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('it_engineer_finding', n.issue_key, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_refund_case(n refund_case, o refund_case DEFAULT NULL::refund_case)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('accountant', 'refund', 'refund_case', n.refund_id::text, null,
      concat_ws(' | ', n.requested_reason, 'AED ' || n.amount_aed, 'eligibility: ' || n.eligibility,
                n.eligibility_reason),
      concat_ws('; ', n.decision, 'state ' || n.state), n.decision_rationale,
      concat_ws('; ', n.state, n.provider_status, n.failure_reason),
      n.state in ('ceo_declined','succeeded','reconciled','communicated','canceled','ineligible'),
      array[n.destination_ref], n.created_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('refund_case', n.refund_id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_social_reply(n social_message, o social_message DEFAULT NULL::social_message)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_in public.social_message; v_reply text; v_known text[];
begin
  begin
    if n.direction = 'out' and n.in_reply_to is not null then
      select * into v_in from public.social_message m where m.id = n.in_reply_to;
    elsif n.direction = 'in' then
      v_in := n;
    end if;
    if v_in.id is not null and v_in.outcome is not null then
      select m.body into v_reply from public.social_message m
       where m.in_reply_to = v_in.id and m.direction = 'out' order by m.id desc limit 1;
      select array[c.handle, c.user_id] into v_known from public.social_conversation c where c.id = v_in.conversation_id;
      perform public.fn_case_remember('marketing', 'social_reply', 'social_message', v_in.id::text, null,
        concat_ws(' | ', v_in.body, v_in.platform || ' ' || v_in.channel),
        coalesce('replied: ' || left(v_reply, 500), 'no reply sent'), null, v_in.outcome,
        true, coalesce(v_known, '{}'), v_in.occurred_at, null);
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('social_message', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_spec_offer(n spec_alternative_offer, o spec_alternative_offer DEFAULT NULL::spec_alternative_offer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_case_remember('sales_engineer', 'spec_offer', 'spec_alternative_offer', n.id::text, null,
      concat_ws(' | ', 'no exact match for ' || n.label_en || ' = ' || n.requested, 'item: ' || n.item,
                'alternatives: ' || left(n.alternatives::text, 400)),
      'offered ' || jsonb_array_length(case when jsonb_typeof(n.alternatives) = 'array' then n.alternatives else '[]'::jsonb end) || ' alternative(s)',
      null, concat_ws('; ', n.state, 'accepted: ' || n.accepted_value, n.closed_reason),
      n.state <> 'open', '{}', n.opened_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('spec_alternative_offer', n.id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_from_support_case(n support_case, o support_case DEFAULT NULL::support_case)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_known text[] := '{}';
begin
  begin
    -- party_id is a key, not a name: the identity to mask is read from the party it names (a customer
    -- uuid, or a supplier's leads id — fn_sales_portal_report's convention).
    if n.party_kind = 'customer' then
      select array[c.full_name, c.email, c.phone, c.whatsapp_phone] into v_known
        from public.customers c where c.id::text = n.party_id;
    elsif n.party_kind = 'supplier' and n.party_id ~ '^\d+$' then
      select array[l.company_name, l.contact_name, l.signatory_name, l.email, l.phone, l.phone_e164, l.whatsapp, l.whatsapp_phone]
        into v_known from public.leads l where l.id = n.party_id::bigint;
    end if;
    perform public.fn_case_remember('customer_support', 'support_case', 'support_case', n.case_id::text, null,
      concat_ws(' | ', n.subject, n.party_kind || ' party'),
      'state ' || n.state, null, n.close_reason,
      n.state = 'closed' or n.closed_at is not null, coalesce(v_known, '{}'), n.opened_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('support_case', n.case_id::text, sqlerrm);
  end;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_mask(p_text text, p_known text[] DEFAULT '{}'::text[])
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v text := coalesce(p_text, '');
  k text;
  m text[];
begin
  if p_text is null then return null; end if;
  -- Shapes first, so a name inside an address cannot leave "[party]@domain" behind.
  v := regexp_replace(v, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[email]', 'g');
  v := regexp_replace(v, 'https?://\S+|www\.\S+', '[link]', 'gi');
  -- A phone is a run of 9+ digits with separators; a date (2026-09-01) or an amount is not.
  for m in select regexp_matches(v, '\+?\d[\d\s\-().]{6,}\d', 'g') loop
    if length(regexp_replace(m[1], '\D', '', 'g')) >= 9 then
      v := replace(v, m[1], '[phone]');
    end if;
  end loop;
  -- Each identity string the row names, whole, longest first.
  for k in select btrim(x) from unnest(coalesce(p_known, '{}')) x
            where length(btrim(x)) >= 3 order by length(btrim(x)) desc loop
    v := regexp_replace(v, regexp_replace(k, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'), '[party]', 'gi');
  end loop;
  -- Then each WORD of a name (a first name alone is still a name), whole words only so "Ali" can
  -- never eat "quality"; words with no letter in them are left to the phone rule above.
  for k in select distinct btrim(t) from unnest(coalesce(p_known, '{}')) x, regexp_split_to_table(x, '\s+') t
            where x !~ '@' and length(btrim(t)) >= 3 and btrim(t) ~ '[[:alpha:]]' loop
    v := regexp_replace(v, '\m' || regexp_replace(k, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '\M', '[party]', 'gi');
  end loop;
  return nullif(left(btrim(v), 2000), '');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_case_recall(p_seat text, p_embedding vector, p_trade text DEFAULT NULL::text, p_k integer DEFAULT 5, p_case_kind text DEFAULT NULL::text, p_other_seats boolean DEFAULT true, p_floor real DEFAULT 0.84, p_exclude_source_table text DEFAULT NULL::text, p_exclude_source_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_trade text := nullif(lower(btrim(p_trade)), '');
  v_out   jsonb;
  v_prev  text := current_setting('enable_indexscan');
begin
  if p_embedding is null then
    return jsonb_build_object('ok', false, 'reason', 'no_embedding', 'cases', '[]'::jsonb);
  end if;
  -- EXACT UNTIL 20,000 ROWS. An HNSW scan with a WHERE clause can return fewer than k rows that
  -- clear the floor; below this size the exact scan costs milliseconds and misses nothing. The
  -- setting is put back before returning, so a caller's own transaction keeps its planner.
  if (select count(*) from public.seat_case_memory where embedding is not null) < 20000 then
    perform set_config('enable_indexscan', 'off', true);
  end if;
  with c as (
    select m.*, (1 - (m.embedding <=> p_embedding))::real as sim
      from public.seat_case_memory m
     where m.embedding is not null
       and (p_other_seats or m.seat = p_seat)
       and (p_case_kind is null or m.case_kind = p_case_kind)
       and (v_trade is null or m.trade is null or m.trade = v_trade)
       -- IS DISTINCT, not "not (a = b)": with no exclusion given, "not (x = null)" is null and would
       -- silently drop every row (it did, on the first probe run).
       and (m.source_table, m.source_id) is distinct from (p_exclude_source_table, p_exclude_source_id)
  ), top as (
    select * from c where sim >= coalesce(p_floor, 0.84)
     order by sim + case when correction is not null then 0.05 else 0 end desc
     limit greatest(1, least(coalesce(p_k, 5), 20))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'case_id', t.id, 'seat', t.seat, 'case_kind', t.case_kind, 'trade', t.trade,
           'situation', t.situation, 'decision', t.decision, 'reasoning', t.reasoning,
           'outcome', t.outcome, 'finalised', t.finalised, 'finalised_at', t.finalised_at,
           'lessons', to_jsonb(t.lessons), 'correction', t.correction, 'corrected_by', t.corrected_by,
           'similarity', round(t.sim::numeric, 3), 'opened_at', t.opened_at,
           'source', case when t.seat = p_seat then t.source_table || ':' || t.source_id end)
         order by t.sim + case when t.correction is not null then 0.05 else 0 end desc), '[]'::jsonb)
    into v_out from top t;
  perform set_config('enable_indexscan', v_prev, true);
  return jsonb_build_object('ok', true, 'floor', coalesce(p_floor, 0.84), 'cases', v_out,
                            'finalised_precedent', exists (select 1 from jsonb_array_elements(v_out) e where (e->>'finalised')::boolean));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_case_recall_ml(p_seat text, p_embedding vector, p_trade text DEFAULT NULL::text, p_k integer DEFAULT 5, p_case_kind text DEFAULT NULL::text, p_other_seats boolean DEFAULT true, p_floor real DEFAULT 0.85, p_exclude_source_table text DEFAULT NULL::text, p_exclude_source_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_trade text := nullif(lower(btrim(p_trade)), '');
  v_out   jsonb;
begin
  if p_embedding is null then
    return jsonb_build_object('ok', false, 'reason', 'no_embedding', 'cases', '[]'::jsonb);
  end if;
  with c as (
    select m.*, (1 - (v.embedding <=> p_embedding))::real as sim
      from public.knowledge_vector_ml v
      join public.seat_case_memory m on v.src = 'seat_case_memory' and m.id::text = v.row_id
     where (p_other_seats or m.seat = p_seat)
       and (p_case_kind is null or m.case_kind = p_case_kind)
       and (v_trade is null or m.trade is null or m.trade = v_trade)
       and (m.source_table, m.source_id) is distinct from (p_exclude_source_table, p_exclude_source_id)
  ), top as (
    select * from c where sim >= coalesce(p_floor, 0.85)
     order by sim + case when correction is not null then 0.05 else 0 end desc
     limit greatest(1, least(coalesce(p_k, 5), 20))
  )
  -- The answer is fn_case_recall's, key for key (the source is named only to its own seat), plus 'space'.
  select coalesce(jsonb_agg(jsonb_build_object(
           'case_id', t.id, 'seat', t.seat, 'case_kind', t.case_kind, 'trade', t.trade,
           'situation', t.situation, 'decision', t.decision, 'reasoning', t.reasoning,
           'outcome', t.outcome, 'finalised', t.finalised, 'finalised_at', t.finalised_at,
           'lessons', to_jsonb(t.lessons), 'correction', t.correction, 'corrected_by', t.corrected_by,
           'similarity', round(t.sim::numeric, 3), 'opened_at', t.opened_at,
           'source', case when t.seat = p_seat then t.source_table || ':' || t.source_id end)
         order by t.sim + case when t.correction is not null then 0.05 else 0 end desc), '[]'::jsonb)
    into v_out from top t;
  return jsonb_build_object('ok', true, 'space', 'ml', 'floor', coalesce(p_floor, 0.85), 'cases', v_out,
                            'finalised_precedent', exists (select 1 from jsonb_array_elements(v_out) e where (e->>'finalised')::boolean));
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_record_verified_resolution(p_case_id bigint, p_resolution text, p_verified_by jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; v_open int;
begin
  select * into c from public.support_case where case_id = p_case_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such case'); end if;
  if c.state = 'closed' then
    return jsonb_build_object('ok', true, 'already_closed', true, 'reason', c.close_reason);
  end if;
  if coalesce(btrim(p_resolution), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a close needs a reason; a close that records facts and decides nothing is the defect this estate has already paid for.');
  end if;
  -- VERIFICATION IS A READING OF STATE, not a claim that work happened. "Do not mark a case resolved
  -- on CEO receipt or service task acceptance": both of those are receipts, and a receipt is an
  -- acknowledgement that something was HANDED OVER, not evidence that it landed.
  if p_verified_by is null or coalesce(p_verified_by->>'observed', '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'p_verified_by must name what was OBSERVED (the row, the provider state, the delivered message). A CEO receipt or an accepted service task is an acknowledgement of handover, not evidence of an outcome.');
  end if;

  -- AND THE CASE CANNOT CLOSE OVER LIVE WORK. A refund still moving is an open case whatever the
  -- conversation felt like.
  select count(*) into v_open from public.refund_case
   where case_id = p_case_id
     and state in ('requested','investigating','eligible','ceo_authorized','submitted','provider_pending');
  if v_open > 0 then
    return jsonb_build_object('ok', false, 'reason',
      format('%s refund(s) on this case are still moving. Closing now would report a resolution the money has not reached yet.', v_open));
  end if;

  update public.support_case
     set state = 'closed', closed_at = now(), last_activity_at = now(),
         close_reason = p_resolution || ' || verified by: ' || (p_verified_by->>'observed')
   where case_id = p_case_id;

  return jsonb_build_object('ok', true, 'case_id', p_case_id, 'state', 'closed',
    'verified_by', p_verified_by,
    'note', 'Closed against an observed outcome, not against a receipt.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_case_remember(p_seat text, p_case_kind text, p_source_table text, p_source_id text, p_trade text, p_situation text, p_decision text, p_reasoning text, p_outcome text, p_finalised boolean, p_known text[] DEFAULT '{}'::text[], p_opened_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_lesson text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_sit text := public.fn_case_mask(p_situation, p_known);
  v_id  bigint;
begin
  if coalesce(v_sit, '') = '' then return null; end if;
  insert into public.seat_case_memory as m
    (seat, case_kind, source_table, source_id, trade, situation, decision, reasoning, outcome,
     finalised, finalised_at, lessons, opened_at)
  values (p_seat, p_case_kind, p_source_table, p_source_id, nullif(lower(btrim(p_trade)), ''), v_sit,
          public.fn_case_mask(p_decision, p_known), public.fn_case_mask(p_reasoning, p_known),
          public.fn_case_mask(p_outcome, p_known), coalesce(p_finalised, false),
          case when p_finalised then now() end,
          case when coalesce(p_lesson, '') <> '' then array[public.fn_case_mask(p_lesson, p_known)] else '{}' end,
          coalesce(p_opened_at, now()))
  on conflict (source_table, source_id) do update set
    trade        = coalesce(excluded.trade, m.trade),
    situation    = excluded.situation,
    decision     = coalesce(excluded.decision, m.decision),
    reasoning    = coalesce(excluded.reasoning, m.reasoning),
    outcome      = coalesce(excluded.outcome, m.outcome),
    finalised    = m.finalised or excluded.finalised,
    finalised_at = coalesce(m.finalised_at, excluded.finalised_at),
    lessons      = case when coalesce(p_lesson, '') <> '' and not (excluded.lessons[1] = any (m.lessons))
                        then m.lessons || excluded.lessons else m.lessons end,
    embedding    = case when m.situation is distinct from excluded.situation then null else m.embedding end,
    updated_at   = now()
  returning id into v_id;
  return v_id;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_category_expert_ref(p_category text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text; v_txt text;
begin
  v_key := public.fn_resolve_cat_agent(p_category);
  if v_key is null then return ''; end if;
  select string_agg('## '||topic||E'\n'||content, E'\n\n' order by topic, content)
    into v_txt from agent_knowledge
    where agent_key = v_key
      and topic in ('Pricing benchmarks & red flags','Quote analysis & comparison',
                    'Standards, materials & specifications','Field expertise — UAE codes, standards & specs');
  return left(coalesce(v_txt,''), 4500);
end $function$


CREATE OR REPLACE FUNCTION public.fn_category_key_ask(p_word text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Files nothing (24 Sep 2026): the key is category_route_map / catalog_supplier_categories.slug or none.
  select null::bigint
$function$


CREATE OR REPLACE FUNCTION public.fn_category_key_for_slug(p_slug text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select i.category_key
    from (
      select m.catalog_num, 1 as pri from public.category_route_map m where m.category = lower(btrim(p_slug))
      union all
      select c.num, 2 from public.catalog_supplier_categories c where c.slug = lower(btrim(p_slug))
      union all
      select o.catalog_num, 3 from public.org_category_identity o
       where o.category_key = public.fn_reason_route_answer('category_key:' || lower(btrim(p_slug)))
    ) r
    join public.org_category_identity i on i.catalog_num = r.catalog_num
   where coalesce(btrim(p_slug), '') <> ''
   order by r.pri, i.category_key
   limit 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_category_key_from_text(p_text text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- SCALARS, NOT A RECORD: a plpgsql record that was never assigned raises "not assigned yet" on its first
-- field reference, so the run-less path would have thrown instead of falling through (caught in rehearsal).
-- Every step below parses a REFERENCE (a uuid after "inquiry" or "run", a key in its own format) and looks
-- it up; none decides what the text is about. The fourth step (a catalogue name found as a substring of
-- the text, the longest winning) is deleted: a task that names no inquiry, run or key gets no category pack.
declare v_id uuid; v_run uuid; v_slug text; v_key text;
        v_ev_type text; v_ev_entity text; v_ev_payload jsonb; v_ctx jsonb;
begin
  if coalesce(p_text, '') = '' then return null; end if;

  -- 1. an explicit inquiry reference
  begin
    v_id := substring(p_text from '(?i)inquiry[:=# ]\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid;
  exception when others then v_id := null; end;

  -- 2. a workflow run reference: the event that started the run names the inquiry
  if v_id is null then
    begin
      v_run := substring(p_text from '(?i)\mrun[:=#]\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid;
    exception when others then v_run := null; end;
    if v_run is not null then
      select e.entity_type, e.entity_id, e.payload, r.context into v_ev_type, v_ev_entity, v_ev_payload, v_ctx
        from public.workflow_run r
        left join public.company_event e on e.id = r.trigger_event_id
       where r.id = v_run;
      if coalesce(v_ctx, '{}'::jsonb) ? 'inquiry_id' then
        begin v_id := (v_ctx->>'inquiry_id')::uuid; exception when others then v_id := null; end;
      end if;
      if v_id is null and v_ev_type = 'inquiry' then
        begin v_id := v_ev_entity::uuid; exception when others then v_id := null; end;
      end if;
    end if;
  end if;

  if v_id is not null then
    select i.category into v_slug from public.inquiries i where i.id = v_id;
  end if;
  if v_slug is null and v_ev_payload is not null then v_slug := v_ev_payload->>'category'; end if;
  if v_slug is not null then
    v_key := public.fn_category_key_for_slug(v_slug);
    if v_key is not null then return v_key; end if;
  end if;

  -- 3. a category key written in its own format (NNN_slug), accepted only when it exists
  v_key := substring(p_text from '\m([0-9]{3}_[a-z0-9-]+)\M');
  if v_key is not null and exists (select 1 from public.org_category_identity where category_key = v_key) then
    return v_key;
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_category_knowledge(p_category text)
 RETURNS TABLE(catalog_slug text, topic text, content text, priority integer, layer text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- THE KNOWLEDGE WAS COMPLETE AND UNREACHABLE.
  -- All 84 spec categories carry their 8 modules under agent_key 'cat:<catalogue-slug>', but the
  -- live intake assigns one of 56 LEGACY slugs whose overlap with the catalogue is exactly zero.
  -- lead_trade_map is the bridge; this is the first thing that walks it at read time.
  -- Accepts either vocabulary so callers do not need to know which one they hold.
  with resolved as (
    select coalesce(
      (select c.slug from public.catalog_supplier_categories c where c.slug = p_category),
      (select m.catalog_slug from public.lead_trade_map m
         join public.catalog_supplier_categories c2 on c2.slug = m.catalog_slug
        where m.trade_key = p_category)
    ) as slug
  )
  select r.slug, k.topic, k.content, k.priority, k.layer
    from resolved r
    join public.agent_knowledge k on k.agent_key = 'cat:' || r.slug
   where r.slug is not null
   order by k.priority desc nulls last, k.topic;
$function$


CREATE OR REPLACE FUNCTION public.fn_category_knowledge_promote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_slug text; v_know text; v_name text; r jsonb;
begin
  if NEW.kind='category_knowledge' and NEW.status in ('approved','done')
     and coalesce(OLD.status,'') not in ('approved','done') then
    v_slug := NEW.detail->>'slug'; v_know := NEW.detail->>'knowledge'; v_name := NEW.detail->>'name';
    if v_slug is not null and v_know is not null then
      -- publish the quoting-knowledge blob live (full parity) if not already present
      if not exists (select 1 from agent_knowledge where agent_key='cat:'||v_slug) then
        insert into agent_knowledge(agent_key,topic,content,priority,created_at,updated_at)
        values ('cat:'||v_slug, coalesce(v_name,v_slug), v_know, 100, now(), now());
      else
        update agent_knowledge set content=v_know, updated_at=now() where agent_key='cat:'||v_slug;
      end if;
      -- apply the proposed regulation -> category mapping
      for r in select * from jsonb_array_elements(coalesce(NEW.detail->'reg_matches','[]'::jsonb)) loop
        update regulations
          set categories = array(select distinct e from unnest(coalesce(categories,'{}'::text[]) || array[v_slug]) e)
          where id::text = (r->>'id') and not (v_slug = any(coalesce(categories,'{}'::text[])));
      end loop;
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_category_questions(p_category text, p_lang text DEFAULT 'en'::text, p_limit integer DEFAULT 22)
 RETURNS TABLE(field_key text, question text, answer_type text, mandatory boolean, ask_order integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'kb_stage'
AS $function$
  -- THE SPEC'S "INQUIRY QUALIFICATION LOGIC", REACHABLE FOR THE FIRST TIME.
  -- 16,588 questions (4,117 distinct texts, 7,079 mandatory, 14,051 bilingual) live in kb_stage
  -- keyed by FAMILY slug. The intake speaks a legacy slug. The chain is
  --   intake slug -> lead_trade_map -> catalogue slug -> catalog_category_domain -> family
  -- and this walks all of it, accepting either vocabulary at the front.
  --
  -- field_key is NULL on every row; the real supplier-facing key and the ask-order live inside
  -- `activation`. Sorting by that order is the point - it is what makes this an ordered interview
  -- rather than the flat, unordered list category_specs.fields produces.
  --
  -- Deduplicated on question text: a family spans up to 465 subcategories which repeat the generic
  -- spine (emirate, exact need, scope, quantity, date), so without DISTINCT ON the first 20 rows
  -- would be the same question twenty times.
  with fam as (
    select d.domain_slug
      from public.catalog_category_domain d
     where d.catalog_slug = coalesce(
       (select c.slug from public.catalog_supplier_categories c where c.slug = p_category),
       (select m.catalog_slug from public.lead_trade_map m where m.trade_key = p_category))
  )
  select * from (
    select distinct on (q.question_en)
           coalesce(q.activation->>'supplier_facing_field', q.field_key) as field_key,
           case when p_lang = 'ar' and coalesce(q.question_ar,'') <> '' then q.question_ar else q.question_en end as question,
           q.answer_type,
           q.mandatory,
           coalesce((q.activation->>'order')::int, 999) as ask_order
      from kb_stage.questions q
      join fam on fam.domain_slug = q.category_slug
     where coalesce(q.question_en,'') <> ''
     order by q.question_en, q.mandatory desc
  ) x
  order by x.mandatory desc, x.ask_order, x.field_key
  limit greatest(p_limit, 1);
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_accept_support_report(p_report_id bigint, p_receipt text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report%rowtype;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no report %s', p_report_id));
  end if;
  if coalesce(btrim(p_receipt), '') = '' then
    -- The receipt is the whole point. Without it, "accepted" is support's word for the CEO.
    return jsonb_build_object('ok', false, 'reason',
      'A receipt is required to accept. An acceptance with no receipt is the accepting party''s '
      || 'assumption, not their agreement.');
  end if;

  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = p_receipt,
         owner_role_id = 'ceo', completion_note = coalesce(p_note, completion_note)
   where id = p_report_id;

  return jsonb_build_object('ok', true, 'report_id', p_report_id, 'owner', 'ceo',
    'note', 'Accepted. Ownership has moved to the CEO, which is the only thing that moves it.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_accountant_notice_report_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.support_ceo_report; h public.agent_actions; v_fixture boolean; v_key text; v_owner text;
  v_decision text; v_receipt text; v_acc jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id and source_agent = 'accountant' for update;
  if not found or r.status <> 'sent'
     or not (r.idempotency_key like 'notice\_undelivered:%' or r.idempotency_key like 'notice\_unverified:%') then
    return jsonb_build_object('ok', false, 'reason', 'no open accountant notice report ' || p_report_id);
  end if;
  select * into h from public.agent_actions where id = (r.verified_evidence->>'handoff_id')::bigint;
  v_fixture := h.detail::text ilike '%ZZ DEMO%'
    or coalesce((public.fn_delivery_request_outcome((h.evidence->>'delivery_request')::bigint)->>'fixture')::boolean, false)
    or exists (select 1 from public.customers c where c.id::text = h.detail->>'customer_id' and c.email ilike '%@example.invalid')
    or exists (select 1 from public.leads l where l.id::text = h.detail->>'supplier_id'
                                            and (l.company_name ilike '%ZZ DEMO%' or coalesce(l.claimed_by, l.email, '') ilike '%@example.invalid'));

  if v_fixture then
    v_decision := 'need_not_go_fixture';
    v_receipt := 'ceo: decided it need not go. The ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?')
      || ') is about a ZZ DEMO fixture: no real person was meant to receive it.';
  elsif r.idempotency_key like 'notice\_unverified:%'
        and jsonb_array_length(coalesce(r.verified_evidence->'sends', '[]'::jsonb)) > 0
        and not exists (select 1 from jsonb_array_elements(r.verified_evidence->'sends') o
                         where public.fn_delivery_request_outcome((o->>'request_id')::bigint)->>'state' not in ('reached', 'ended', 'failed')) then
    -- Every send (both on a reveal) reached an outcome between the report and this decision: nothing is
    -- broken. A send that failed is carried by the sales engineer's delivery_undelivered report.
    v_decision := 'arrived_late';
    v_receipt := 'ceo: read. Every send of the ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?')
      || ') reached an outcome after it was reported, so there is no defect to raise'
      || case when exists (select 1 from jsonb_array_elements(r.verified_evidence->'sends') o
                            where public.fn_delivery_request_outcome((o->>'request_id')::bigint)->>'state' = 'failed')
              then '; a send that did not arrive is decided on its delivery_undelivered report.' else '.' end;
  elsif r.idempotency_key like 'notice\_undelivered:%' and h.status is distinct from 'failed' then
    v_decision := 'unreachable_recorded';
    v_receipt := 'ceo: decided. The ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?')
      || ') could not be written because no address is on file for the ' || case when h.evidence->>'customer_reachable' = 'false' then 'customer'
                                                                    when h.evidence->>'supplier_reachable' = 'false' or h.detail ? 'supplier_id' then 'supplier'
                                                                    else 'customer' end
      || '. Recorded that it cannot go until one exists; the portal shows the same facts when they sign in.';
  else
    -- The sales engineer's handler raised, or the send never reached an outcome: a defect.
    v_owner := case when r.idempotency_key like 'notice\_undelivered:%' then 'sales_engineer' else 'customer_support' end;
    v_key := 'monitor:' || split_part(r.idempotency_key, ':', 1) || ':' || coalesce(h.detail->>'type', 'unknown');
    perform public.fn_it_engineer_finding_upsert(v_key,
      case when v_owner = 'sales_engineer'
           then 'The sales engineer could not write a ' || coalesce(h.detail->>'type', '?') || ' notice the accountant asked for'
           else 'A ' || coalesce(h.detail->>'type', '?') || ' notice has no delivery outcome after its window' end,
      case when v_owner = 'sales_engineer' then 'public.' || coalesce((select k.handler from public.seat_handoff_kind k
                                                    where k.type = h.detail->>'type' and k.from_seat = 'accountant' and k.to_seat = 'sales_engineer'), 'fn_seat_handoff_act')
           else 'public.fn_customer_support_delivery_watch' end,
      'agent_facing', 1,
      jsonb_build_object('owner_seat', v_owner, 'handoff_id', h.id, 'report_id', r.id, 'handoff_status', h.status,
                         'error', h.detail->>'error', 'delivery_loop', r.verified_evidence->>'delivery_loop'),
      '{}'::text[], array['why handoff ' || coalesce(h.id::text, '?') || ' produced no delivered notice'], 'fn_ceo_accountant_notice_report_decide');
    v_decision := 'defect_raised';
    v_receipt := 'ceo: decided. The ' || coalesce(h.detail->>'type', '?') || ' notice (handoff ' || coalesce(h.id::text, '?') || ') '
      || case when v_owner = 'sales_engineer' then 'was never written' else 'has no delivery outcome' end
      || ', which is a defect: raised as IT finding ' || v_key || ', which the IT loop hands to ' || v_owner || ' and re-verifies; it clears when the next conversation of this kind works.';
  end if;

  v_acc := public.fn_ceo_accept_support_report(r.id, v_receipt, v_decision);
  if not coalesce((v_acc->>'ok')::boolean, false) then
    raise exception 'fn_ceo_accountant_notice_report_decide: report % was not accepted: %', r.id, v_acc->>'reason';
  end if;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', v_decision);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_accountant_reports_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; n int := 0;
begin
  -- A dispute review is NOT acknowledged here: reading it is not approving it. It stays open until the
  -- CEO approves the submission (fn_ceo_approve_dispute_submission) or the accountant submits at T-24h.
  -- A notice escalation is decided by fn_ceo_accountant_notice_report_decide, not acknowledged here.
  for r in select * from public.support_ceo_report where source_agent = 'accountant' and status = 'sent'
              and idempotency_key not like 'dispute\_review:%'
              and idempotency_key not like 'notice\_undelivered:%' and idempotency_key not like 'notice\_unverified:%'
            order by id loop
    perform public.fn_ceo_accept_support_report(r.id,
      'ceo: read the accountant''s ' || r.severity || ' report "' || left(r.subject, 140) || '" with its evidence ('
        || (select count(*) from jsonb_object_keys(r.verified_evidence)) || ' field(s))');
    n := n + 1;
  end loop;
  return jsonb_build_object('acknowledged', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_approval_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.subject_kind is distinct from old.subject_kind
     or new.subject_id is distinct from old.subject_id
     or new.decision   is distinct from old.decision
     or new.decided_by is distinct from old.decided_by
     or new.amount_aed is distinct from old.amount_aed
     or new.rationale  is distinct from old.rationale
     or new.decided_at is distinct from old.decided_at then
    raise exception 'ceo_approval %: a decision is superseded, never edited', old.decision_id
      using errcode = '23514',
            hint = 'Write a new decision and point the old row''s superseded_by at it.';
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_approve_dispute_submission(p_id text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.stripe_dispute;
begin
  if coalesce(btrim(p_note), '') = '' then raise exception 'an approval to submit dispute evidence carries a note of what was read'; end if;
  select * into d from public.stripe_dispute where id = p_id for update;
  if not found or d.draft_saved_at is null or d.evidence_submitted_at is not null or d.closed_at is not null then
    return jsonb_build_object('ok', false, 'reason', 'dispute ' || p_id || ' has no saved, unsubmitted draft to approve');
  end if;
  update public.stripe_dispute set approved_by = 'ceo', approved_at = now() where id = p_id;
  if d.review_report_id is not null then
    perform public.fn_ceo_accept_support_report(d.review_report_id, 'ceo: approved submitting the evidence for ' || p_id || ' — ' || p_note);
  end if;
  return jsonb_build_object('ok', true, 'dispute', p_id, 'approved_by', 'ceo');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_backup_coverage_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; v_re jsonb; v_cov jsonb; v_receipt text;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  v_re  := public.fn_it_backup_recheck();
  v_cov := public.fn_backup_coverage();
  v_receipt := 'ceo: ran the IT backup re-check (closed ' || coalesce(v_re ->> 'closed', '0') || ', second refiles '
               || coalesce(v_re ->> 'second_refiles', '0') || ', escalated ' || coalesce(v_re ->> 'escalated', '0')
               || '); coverage now ok=' || coalesce(v_cov ->> 'ok', '?') || ', failing=' || coalesce(v_cov ->> 'failing', '[]')
               || ', refiles open past 48h=' || coalesce(v_cov ->> 'refiles_open_past_48h', '?')
               || ', not done after 48h=' || coalesce(v_cov ->> 'not_done_after_48h', '?')
               || '. Each file still missing is carried by its own backup_escalation report.';
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo',
         completed_at = case when coalesce((v_cov ->> 'ok')::boolean, false) then now() else completed_at end,
         completion_note = case when coalesce((v_cov ->> 'ok')::boolean, false) then 'coverage measured ok after the re-check' else completion_note end
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'recheck', v_re, 'coverage', v_cov);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_backup_daily_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  update public.support_ceo_report
     set status = 'completed', accepted_at = now(), completed_at = now(), owner_role_id = 'ceo',
         acceptance_receipt = 'ceo: noted the day''s backup position',
         completion_note = 'ceo: noted. The IT engineer''s daily confirmation requests nothing; a backup case still failing after two '
           || 'refiles or 48 hours reaches the CEO as its own backup escalation report, which has its own decider. Position noted: '
           || left(r.subject, 600)
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'completed');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_backup_escalation_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.support_ceo_report; v_files jsonb; v_demo boolean; v_errs text; v_cause text; v_h bigint; v_out jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  v_files := coalesce(r.verified_evidence->'files', '[]'::jsonb);
  v_demo := jsonb_array_length(v_files) > 0
            and not exists (select 1 from jsonb_array_elements(v_files) e where not coalesce((e->>'demo')::boolean, false));
  v_errs := coalesce((select string_agg(coalesce(e->>'error', ''), ' | ') from jsonb_array_elements(v_files) e), '');
  if not v_demo then
    v_errs := v_errs || ' | ' || coalesce((select string_agg(note, ' | ') from public.agent_runs
                                              where agent in ('dropbox_backup', 'fn:dropbox_backup') and status = 'error'
                                                and started_at > now() - interval '48 hours'), '');
  end if;
  v_cause := case
    when v_errs ~* '(no_dropbox_auth|invalid_access_token|expired_access_token|invalid_grant|access token|dbx_upload 401|get_metadata 401)' then 'Dropbox refused our credentials (the connection needs to be re-authorised)'
    when v_errs ~* '(insufficient_space|over_quota|storage (is )?full|quota)' then 'the Dropbox account is out of space'
    when v_errs ~* '(payment|billing|plan (expired|limit)|account_suspended|disabled)' then 'the Dropbox plan or billing is blocking uploads'
    else null end;

  if v_cause is not null and not v_demo then
    v_out := public.fn_notify_founder(
      'Dropbox backup is blocked by something outside the company',
      'Our document backup to your Dropbox has stopped because ' || v_cause || '. ' || jsonb_array_length(v_files)
        || ' document(s) are waiting and will be sent as soon as it is fixed. Nothing inside the company can fix this part; it needs you.',
      'high', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_external:' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'));
  else
    v_h := public.fn_seat_handoff('ceo', 'sales_engineer', 'backup.remediate', 'support_ceo_report', r.id::text,
      jsonb_build_object('report_id', r.id, 'refile_handoff_id', r.verified_evidence->'handoff_id',
        'files', (select coalesce(jsonb_agg(e - 'state' - 'status' - 'attempts'), '[]'::jsonb) from jsonb_array_elements(v_files) e where e->>'state' <> 'ok'),
        'refile_attempts', 0,
        'instructions', 'Re-file each file below from its source. Where the source no longer exists, mark its row abandoned with the reason (error ''abandoned: ...'') so it stops counting as lost. Do not close this: the IT engineer re-checks and closes.'));
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(),
         acceptance_receipt = 'ceo: ' || case when v_h is not null then 'instructions sent back as handoff ' || v_h
                                              else 'external cause (' || v_cause || '), founder notified' end
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'cause', coalesce(v_cause, 'internal'), 'demo', v_demo,
                            'remediate_handoff', v_h, 'founder', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_backup_escalation_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'CEO re-checked: the IT engineer verified every file of the remediation (handoff ' || a.id || ') and closed it.'
    from public.agent_actions a
   where r.idempotency_key like 'backup_escalation:%' and r.status = 'accepted'
     and a.kind = 'handoff' and a.detail->>'type' = 'backup.remediate' and a.detail->>'report_id' = r.id::text and a.status = 'done';
  get diagnostics n = row_count;
  return jsonb_build_object('completed', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_backup_heartbeat_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; v_after public.support_ceo_report;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status not in ('sent', 'accepted') then
    return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id);
  end if;
  -- the check's own product, written after the alarm: the daily check ran again
  select * into v_after from public.support_ceo_report
   where idempotency_key like 'dropbox\_backup\_daily:%' and created_at > r.created_at order by created_at limit 1;
  if v_after.id is not null then
    update public.support_ceo_report
       set status = 'completed', completed_at = now(), owner_role_id = 'ceo',
           accepted_at = coalesce(accepted_at, now()),
           acceptance_receipt = coalesce(acceptance_receipt, 'ceo: measured the daily Dropbox check'),
           completion_note = 'ceo: the daily Dropbox check ran again after this alarm: it filed report ' || v_after.id
             || ' (' || v_after.idempotency_key || ') at ' || to_char(v_after.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
             || ' Dubai. Closed as measured.'
     where id = r.id;
    return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'completed', 'evidence_report', v_after.id);
  end if;
  if r.status = 'sent' then
    update public.support_ceo_report
       set status = 'accepted', accepted_at = now(), owner_role_id = 'it_engineer', next_review_at = now() + interval '24 hours',
           acceptance_receipt = 'ceo: accepted. The daily Dropbox check has filed no report since this alarm, so the cause is still there. '
             || 'it_engineer repairs the chain it named: ' || left(coalesce(r.requested_outcome, 'the daily check'), 400)
             || ' The CEO re-measures it every hour (ceo.report_answer) and closes it when the check reports again.'
     where id = r.id;
  end if;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'accepted', 'cause', 'no daily report since the alarm');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_binding_constraint(p_figures jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  s jsonb := p_figures->'supply'; d jsonb := p_figures->'demand'; m jsonb := p_figures->'money';
begin
  if (s->>'matchable')::int = 0 then
    return jsonb_build_object('stage','supply_confirmation','severity','blocking',
      'finding', format('No supplier can be matched to any request. %s suppliers are on file and %s have confirmed the trades they actually do.',
                        s->>'leads_total', s->>'matchable'),
      'why_it_outranks_everything','A request that matches nobody produces no quote, no comparison, no reveal and no revenue. Every other number below is downstream of this one and cannot move until it does.',
      'proposal','Send a one-screen confirmation link to invited suppliers: show the trades already scraped for them and let them press yes. That single action sets the two fields the matcher requires and does not depend on the parked supplier portal.',
      'measure_of_success','matchable > 0, then the first request that reaches a supplier.');
  end if;

  if (d->>'inquiries_ever')::int = 0 then
    return jsonb_build_object('stage','demand','severity','blocking',
      'finding', format('Supply is ready (%s matchable) and no customer has posted a request. Real customers: %s.',
                        s->>'matchable', d->>'customers_real'),
      'why_it_outranks_everything','Matchable supply with no demand earns nothing, and suppliers who are asked to wait without a request go cold.',
      'proposal','Outbound to the buyer side of the existing list — the consultants, fit-out contractors and interior designers already on file — since they are buyers of these trades and their emails are already held.',
      'measure_of_success','the first request posted by someone who is not the founder.');
  end if;

  if (d->>'quotes_ever')::int = 0 then
    return jsonb_build_object('stage','supplier_response','severity','blocking',
      'finding','Requests exist and no supplier has quoted.',
      'why_it_outranks_everything','A marketplace that cannot return a quote has failed the customer once, and the customer does not come back.',
      'proposal','Measure dispatch: how many suppliers each request reached, and how many opened it. If dispatch is working, the problem is the ask; if it is not, the problem is delivery.',
      'measure_of_success','at least three quotes on a request, which is what the top-three comparison needs.');
  end if;

  if (d->>'comparisons_ever')::int = 0 then
    return jsonb_build_object('stage','comparison','severity','blocking',
      'finding','Quotes exist and no comparison has been produced.',
      'why_it_outranks_everything','The comparison IS the product. Without it there is nothing to pay to reveal.',
      'proposal','The comparison engine falls back to a deterministic ranking while paid inference is held. Confirm the fallback produces a report a buyer would act on, since that is what every customer will see.',
      'measure_of_success','a published comparison a customer opens.');
  end if;

  if (d->>'reveals_ever')::int = 0 then
    return jsonb_build_object('stage','reveal','severity','blocking',
      'finding','Comparisons exist and nobody has paid to reveal.',
      'why_it_outranks_everything','This is the only revenue event in the model.',
      'proposal','Check the reveal price is visible before the click and that the paid receipt actually reaches both parties.',
      'measure_of_success','the first 3% fee settled in the bank.');
  end if;

  if (m->>'revenue_week_aed')::numeric = 0 and (m->>'revenue_life_aed')::numeric > 0 then
    return jsonb_build_object('stage','repeat','severity','watch',
      'finding','Revenue exists but none this week.',
      'why_it_outranks_everything','A marketplace lives on repeat, and one-off revenue hides churn.',
      'proposal','Look at whether last week''s buyers returned and whether revealed suppliers responded.',
      'measure_of_success','revenue in consecutive weeks.');
  end if;

  return jsonb_build_object('stage','growth','severity','healthy',
    'finding', format('The chain is intact end to end. Revenue this week AED %s.', m->>'revenue_week_aed'),
    'why_it_outranks_everything','Nothing in the chain is broken, so the constraint is rate rather than function.',
    'proposal','Raise the top of the funnel and protect the reveal conversion.',
    'measure_of_success','week-on-week revenue growth.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_board_pack(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date;
  v_from timestamptz := date_trunc('month', p_month)::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (date_trunc('month', p_month) + interval '1 month')::timestamp at time zone 'Asia/Dubai';
  v_supply jsonb; v_seats jsonb; v_cash jsonb; v_launch public.ceo_launch_gate; v_text text;
begin
  with real as (
    select l.id, l.emirate, l.approved_at from public.leads l
     where l.approved_at is not null and l.approved_at < v_to
       and not (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ilike 'ZZ DEMO%' or coalesce(l.email, '') ilike '%@example.invalid'))
  select jsonb_build_object(
    'verified_total', (select count(*) from real),
    'verified_added', (select count(*) from real where approved_at >= v_from),
    'by_emirate', (select coalesce(jsonb_agg(jsonb_build_object('emirate', e, 'total', t, 'added', a) order by t desc, e), '[]'::jsonb)
                     from (select coalesce(nullif(btrim(emirate), ''), 'not stated') e, count(*) t, count(*) filter (where approved_at >= v_from) a
                             from real group by 1) x),
    'by_trade', (select coalesce(jsonb_agg(jsonb_build_object('trade', tr, 'total', t, 'added', a) order by t desc, tr), '[]'::jsonb)
                   from (select tr, count(*) t, count(*) filter (where r.approved_at >= v_from) a
                           from real r join public.supplier_capabilities sc on sc.supplier_id = r.id and sc.confirmed_at is not null,
                                unnest(sc.trades) tr group by tr order by count(*) desc, tr limit 15) x))
    into v_supply;

  select coalesce(jsonb_object_agg(owner_seat, jsonb_build_object('duties', n, 'green', g, 'failing', f)), '{}'::jsonb) into v_seats
    from (select d.owner_seat, count(*) n,
                 count(*) filter (where d.last_ok_at >= now() - 2 * d.every - interval '15 minutes') g,
                 count(*) filter (where d.failures > 0) f
            from public.seat_duty d where d.enabled group by d.owner_seat) x;

  select figures -> 'cash_position' into v_cash from public.accountant_month_close where month = v_m;
  select * into v_launch from public.ceo_launch_gate order by week desc limit 1;

  v_text := format(E'BOARD PACK, %s\n\nSupply: %s verified suppliers, %s added this month.', to_char(v_m, 'FMMonth YYYY'),
                   v_supply->>'verified_total', v_supply->>'verified_added')
    || E'\nBy emirate: ' || coalesce((select string_agg(format('%s %s (+%s)', e->>'emirate', e->>'total', e->>'added'), ', ')
                                        from jsonb_array_elements(v_supply->'by_emirate') e), 'none')
    || E'\nBy trade: ' || coalesce((select string_agg(format('%s %s (+%s)', e->>'trade', e->>'total', e->>'added'), ', ')
                                      from jsonb_array_elements(v_supply->'by_trade') e), 'none')
    || E'\n\nSeats (duties green of registered, failing): '
    || coalesce((select string_agg(format('%s %s/%s, %s failing', k, v->>'green', v->>'duties', v->>'failing'), '; ' order by k)
                   from jsonb_each(v_seats) s(k, v)), 'no duties registered')
    || E'\n\nRunway (the accountant''s month close): '
    || case when v_cash is null then 'the accountant has not closed ' || to_char(v_m, 'FMMonth YYYY') || ' yet.'
            when v_cash->'runway'->>'missing' is not null then (v_cash->'runway'->>'missing') || '.'
            else format('%s months: AED %s available against AED %s spent a month.', v_cash->'runway'->>'months',
                        v_cash->'runway'->>'available_aed', v_cash->'runway'->>'monthly_spend_aed') end
    || E'\n\nCustomer launch gate: '
    || case when v_launch.week is null then 'not measured yet.'
            else format('%s of %s trades ready (%s%%), verdict %s%s, week of %s.', v_launch.trades_ready, v_launch.trades_total,
                        v_launch.coverage_pct, v_launch.verdict, coalesce(', decision ' || v_launch.decision, ''), v_launch.week) end;

  return jsonb_build_object('month', v_m, 'supply', v_supply, 'seats', v_seats, 'cash_position', v_cash,
    'launch_gate', case when v_launch.week is null then null else to_jsonb(v_launch) end, 'text', v_text);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_command_interpret(p_command_id bigint, p_intent text, p_why text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.ceo_command; v_work boolean;
begin
  select * into c from public.ceo_command where command_id = p_command_id for update;
  if not found then raise exception 'no command %', p_command_id using errcode = 'P0002'; end if;
  select i.needs_work into v_work from public.ceo_command_intent i where i.intent_id = p_intent;
  if v_work is null then raise exception 'unknown intent %', p_intent using errcode = '22023'; end if;
  -- Idempotent: a command already understood is not re-routed (a replay after a live answer is a no-op).
  if c.state <> 'interpreting' then
    return jsonb_build_object('command_id', p_command_id, 'intent', c.intent_id, 'state', c.state, 'changed', false);
  end if;
  update public.ceo_command set intent_id = p_intent, state = 'accepted',
         outcome = coalesce(outcome, left('understood as ' || p_intent || coalesce(': ' || nullif(btrim(p_why), ''), ''), 1000))
   where command_id = p_command_id;
  -- An instruction that asks for work becomes work. One that states a rule or asks a question is
  -- accepted and answered without manufacturing a task nobody wanted.
  if v_work then
    insert into public.ceo_task (command_id, title, detail) values (p_command_id, left(btrim(c.body), 200), c.body);
    update public.ceo_command set state = 'routed'        where command_id = p_command_id;
    update public.ceo_command set state = 'tasks_created' where command_id = p_command_id;
  end if;
  select * into c from public.ceo_command where command_id = p_command_id;
  return jsonb_build_object('command_id', p_command_id, 'intent', c.intent_id, 'state', c.state, 'changed', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_command_state_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.state is distinct from old.state
     and not exists (select 1 from public.ceo_command_transition
                      where from_state = old.state and to_state = new.state) then
    raise exception 'ceo_command %: transition % -> % is not a legal move',
      old.command_id, old.state, new.state
      using hint = 'Legal moves are listed in public.ceo_command_transition.';
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_command_submit(p_channel text, p_from text, p_body text)
 RETURNS TABLE(command_id bigint, intent_id text, state text, matched text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  if coalesce(btrim(p_body), '') = '' then
    raise exception 'an empty instruction is not an instruction' using errcode = '22023';
  end if;
  -- Recorded first, understood second. 'interpreting' is the state ceo_command_state already defines as
  -- "the CEO is working out what was asked"; fn_ceo_command_interpret moves it on with the reasoned intent.
  insert into public.ceo_command (channel, from_identity, body, intent_id, matched_rule, state)
  values (p_channel, p_from, p_body, 'ambiguous', null, 'received')
  returning ceo_command.command_id into v_id;
  update public.ceo_command set state = 'interpreting' where ceo_command.command_id = v_id;
  return query
    select c.command_id, c.intent_id, c.state, null::text
      from public.ceo_command c where c.command_id = v_id;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_company_stage_advance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cur public.ceo_company_stage_log; v_read jsonb := '{}'::jsonb; k text; v_next text;
begin
  select * into cur from public.ceo_company_stage_log where left_at is null for update;
  for k in select distinct exit_measure from public.ceo_company_stage where exit_measure is not null loop
    v_read := v_read || jsonb_build_object(k, public.fn_ambition_measure(k, timestamptz '2026-01-01', now()));
  end loop;
  v_next := public.fn_ceo_company_stage_next(cur.stage, v_read);
  if v_next <> cur.stage then
    update public.ceo_company_stage_log set left_at = now(), exit_reading = v_read where id = cur.id;
    insert into public.ceo_company_stage_log (stage) values (v_next);
    perform public.fn_ceo_plan_log('company_stage', 'company_stage:' || v_next,
      format('The company moved from %s to %s on measured milestones.', cur.stage, v_next), jsonb_build_object('readings', v_read));
  end if;
  return jsonb_build_object('stage', v_next, 'from', cur.stage, 'moved', v_next <> cur.stage, 'readings', v_read);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_company_stage_next(p_current text, p_readings jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text := p_current; s record;
begin
  loop
    select * into s from public.ceo_company_stage where stage = v;
    exit when s.exit_measure is null or (p_readings->>s.exit_measure) is null
           or (p_readings->>s.exit_measure)::numeric < s.exit_threshold;
    select stage into v from public.ceo_company_stage where stage_order = s.stage_order + 1;
    exit when v is null;
  end loop;
  return coalesce(v, p_current);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_constraint_lever()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.ceo_plan; l public.ceo_constraint_lever; v_id bigint; v_ref text; v_level int; r record; n_closed int := 0;
begin
  select * into p from public.ceo_plan order by plan_date desc, id desc limit 1;

  -- tracked to done: the binding stage moved on, so the constraint the idea was for is no longer the one that binds
  for r in select i.* from public.ceo_improvement i where i.source_kind = 'binding_constraint' and i.status in ('open', 'assigned') loop
    if p.id is not null and p.stage is distinct from r.evidence->>'stage' then
      perform public.fn_ceo_improvement_close(r.id, format('The binding constraint moved from %s to %s (ceo_plan %s, %s).',
        r.evidence->>'stage', p.stage, p.id, p.plan_date));
      n_closed := n_closed + 1;
    end if;
  end loop;

  if p.id is null or p.stage is null or p.stage = 'on_plan' then
    return jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'proposed', null, 'closed', n_closed);
  end if;
  select * into l from public.ceo_constraint_lever where stage = p.stage;
  if l.stage is null then
    -- a stage with no lever is a gap in this table, recorded for the CEO rather than silently skipped
    perform public.fn_it_engineer_finding_upsert('ceo:no_constraint_lever:' || p.stage,
      'The binding stage ' || p.stage || ' has no lever in ceo_constraint_lever', 'public.ceo_constraint_lever', 'agent_facing', 1,
      jsonb_build_object('stage', p.stage, 'owner_seat', 'ceo'), '{}'::text[], array['which step the company can move for this stage'], 'ceo');
    return jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'proposed', null, 'closed', n_closed, 'error', 'no lever');
  end if;
  v_level := case when p.plan_date - p.constraint_since >= 14 then 2 else 1 end;
  v_ref := p.stage || ':' || p.constraint_since || ':L' || v_level;
  v_id := public.fn_ceo_improvement_open('binding_constraint', v_ref, l.owner_seat,
    case when v_level = 2 then format('ESCALATED: %s has bound the funnel for %s days. ', p.decision->>'label', p.plan_date - p.constraint_since) else '' end
      || l.proposal || ' Owner: ' || l.owner_seat || '. Due: ' || to_char(p.plan_date + 14, 'DD Mon YYYY') || '. Proven by: ' || l.measure || '.',
    jsonb_build_object('stage', p.stage, 'plan_id', p.id, 'constraint_since', p.constraint_since, 'level', v_level,
      'lever', p.decision->>'lever', 'held_because', p.decision->>'held_because',
      'month_to_date', p.funnel->'month_to_date', 'last_7_days', p.funnel->'last_7_days',
      'measure', l.measure, 'due_on', p.plan_date + 14));
  return jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'level', v_level, 'proposed', v_id, 'closed', n_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_context(p_query text, p_max_chars integer DEFAULT 18000, p_limit integer DEFAULT 8, p_embedding vector DEFAULT NULL::vector)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
  v_used int := 0;
  v_n int := 0;
  v_how text := null;
begin
  for r in select * from public.fn_ceo_knowledge_search(p_query, p_limit, p_embedding => p_embedding) loop
    exit when v_used + length(r.body) > greatest(2000, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'domain', r.domain, 'body', r.body, 'body_sha256', r.body_sha256,
      'source_ids', to_jsonb(r.source_ids), 'source_path', r.source_path,
      'review_status', r.review_status, 'authority_effect', r.authority_effect,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'query', p_query,
    'records', v_out,
    'record_count', v_n,
    'chars_used', v_used,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    'signal', case when v_n = 0
                   then case when p_embedding is null then 'INSUFFICIENT CONTEXT -- no embedding was passed, and this pack is read by meaning only. Say so rather than answering from memory.'
                             else 'INSUFFICIENT CONTEXT -- nothing in the CEO knowledge pack is near this query in meaning. Say so rather than answering from memory.' end
                   else 'Advisory context only. Company facts, targets, budgets and permissions must be read from the application, not from these records.' end,
    'pack_fingerprint', (select max(pack_fingerprint) from public.ceo_knowledge));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_daily_digest(p_local_date date DEFAULT NULL::date, p_revise boolean DEFAULT false, p_revision_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz text := 'Asia/Dubai';
  v_date date; v_key text;
  v_row public.ceo_daily_digest%rowtype;
  v_brief jsonb;
begin
  v_date := coalesce(p_local_date, (now() at time zone v_tz)::date);
  v_key  := 'quotesdone:'||to_char(v_date,'YYYY-MM-DD');

  select * into v_row from public.ceo_daily_digest where report_key = v_key;   -- UNFILTERED

  if found and not p_revise then
    if v_row.submitted_at is null then v_row := public.fn_ceo_daily_digest_submit(v_row.id); end if;
    return jsonb_build_object('report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
      'status', v_row.status, 'generated', false, 'reason', 'already generated for this local date',
      'submitted', v_row.submitted_at is not null, 'delivery_attempts', v_row.delivery_attempts,
      'last_delivery_error', v_row.last_delivery_error);
  end if;

  begin
    v_brief := public.fn_founder_brief(v_date);
  exception when others then
    if v_row.id is not null then
      update public.ceo_daily_digest set last_delivery_error = 'generation failed: '||sqlerrm, updated_at = now()
       where id = v_row.id;
    end if;
    return jsonb_build_object('report_key', v_key, 'generated', false, 'error', sqlerrm);
  end;

  if p_revise and v_row.id is not null then
    -- A correction is a new send of the corrected text: clear the old submission and the old PDF.
    update public.ceo_daily_digest
       set revision = revision + 1, revision_note = p_revision_note,
           subject = v_brief->>'subject', body = v_brief->>'body', figures = v_brief->'figures',
           command_center_id = (v_brief->>'command_center_id')::uuid,
           status = 'generated', generated_at = now(), submitted_at = null, notification_id = null,
           pdf_bucket = null, pdf_path = null, last_delivery_error = null, updated_at = now()
     where id = v_row.id returning * into v_row;
  else
    insert into public.ceo_daily_digest(company_key, local_date, local_timezone, report_key, revision, revision_note,
                                        subject, body, figures, status, command_center_id, delivery_attempts)
    values ('quotesdone', v_date, v_tz, v_key, 1, p_revision_note,
            v_brief->>'subject', v_brief->>'body', v_brief->'figures', 'generated',
            (v_brief->>'command_center_id')::uuid, 0)
    returning * into v_row;
  end if;

  v_row := public.fn_ceo_daily_digest_submit(v_row.id);

  return jsonb_build_object('report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status, 'generated', true, 'submitted', v_row.submitted_at is not null,
    'delivery_attempts', v_row.delivery_attempts, 'last_delivery_error', v_row.last_delivery_error);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_daily_digest_attach_pdf(p_id bigint, p_bucket text, p_path text, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.ceo_daily_digest%rowtype;
begin
  if p_path is null or p_error is not null then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'customer list PDF: '||coalesce(p_error, 'no path returned'), updated_at = now()
     where id = p_id and submitted_at is null returning * into v_row;
    return jsonb_build_object('id', p_id, 'submitted', false, 'error', v_row.last_delivery_error);
  end if;
  update public.ceo_daily_digest set pdf_bucket = p_bucket, pdf_path = p_path, updated_at = now()
   where id = p_id and submitted_at is null;
  v_row := public.fn_ceo_daily_digest_submit(p_id);
  return jsonb_build_object('id', p_id, 'submitted', v_row.submitted_at is not null,
                            'notification_id', v_row.notification_id, 'error', v_row.last_delivery_error);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_daily_digest_submit(p_id bigint)
 RETURNS ceo_daily_digest
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.ceo_daily_digest%rowtype;
  v_owner text;
  v_notif_id bigint;
  v_needs_pdf boolean;
begin
  select * into v_row from public.ceo_daily_digest where id = p_id;
  if not found or v_row.submitted_at is not null then return v_row; end if;

  v_needs_pdf := coalesce((v_row.figures->'customers'->>'count')::int, 0) > 0;
  if v_needs_pdf and v_row.pdf_path is null then
    update public.ceo_daily_digest
       set last_delivery_error = 'waiting for the customer list PDF', updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end if;

  select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
    from public.app_secrets where key = 'admin_emails';
  if v_owner is null then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'no recipient configured in app_secrets.admin_emails', updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end if;

  begin
    insert into public.notifications(type, to_email, to_role, channel, subject, body, attachments)
      values ('founder_brief', v_owner, 'admin', 'email',
              coalesce(v_row.subject, 'QuotesDone daily brief - '||to_char(v_row.local_date,'Dy DD Mon')),
              coalesce(v_row.body, ''),
              case when v_row.pdf_path is not null then jsonb_build_array(jsonb_build_object(
                'bucket', v_row.pdf_bucket, 'path', v_row.pdf_path,
                'filename', 'QuotesDone customers registered '||to_char(v_row.local_date,'YYYY-MM-DD')||'.pdf')) end)
    returning id into v_notif_id;
  exception when others then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'submission raised: '||sqlerrm, updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end;

  update public.ceo_daily_digest
     set notification_id = v_notif_id,
         submitted_at = case when v_notif_id is not null then now() end,
         status = case when v_notif_id is not null then 'submitted' else status end,
         delivery_attempts = delivery_attempts + 1,
         last_delivery_error = case when v_notif_id is null then 'the founder-mail gate did not accept the row' end,
         updated_at = now()
   where id = p_id returning * into v_row;
  return v_row;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_daily_digest_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz text := 'Asia/Dubai';
  v_local timestamp; v_at time; v_date date; v_key text;
  v_row public.ceo_daily_digest%rowtype;
  v_res jsonb;
begin
  v_local := now() at time zone v_tz;
  v_date  := v_local::date;
  v_key   := 'quotesdone:'||to_char(v_date,'YYYY-MM-DD');

  begin
    select coalesce(nullif(btrim(value),''),'20:00')::time into v_at from public.app_secrets where key = 'ceo_digest_local_time';
  exception when others then v_at := time '20:00'; end;
  v_at := coalesce(v_at, time '20:00');

  if v_local::time < v_at then
    return jsonb_build_object('fired', false, 'reason', 'before the configured local time',
      'local_now', to_char(v_local,'YYYY-MM-DD HH24:MI'), 'configured_at', v_at::text, 'report_key', v_key,
      'exists', exists (select 1 from public.ceo_daily_digest where report_key = v_key));
  end if;

  v_res := public.fn_ceo_daily_digest(v_date) || jsonb_build_object('fired', true, 'configured_at', v_at::text);

  select * into v_row from public.ceo_daily_digest where report_key = v_key;
  if found and v_row.submitted_at is null and v_row.pdf_path is null
     and coalesce((v_row.figures->'customers'->>'count')::int, 0) > 0 then
    v_res := v_res || jsonb_build_object('pdf_pending', true, 'id', v_row.id, 'report_key', v_row.report_key,
      'pdf_title', 'Customers registered - '||to_char(v_row.local_date,'Dy DD Mon YYYY'),
      'pdf_blocks', public.fn_founder_brief_pdf_blocks(v_row.figures));
  end if;
  return v_res;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_daily_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date;
  v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_verdict jsonb; v_status jsonb; h record; n_stuck_new int := 0; v_stuck jsonb := '[]'::jsonb; v_prio jsonb := '{}'::jsonb;
  v_signals jsonb; v_matters text[] := '{}'; v_note bigint; s text; v_m jsonb; v_first text; v_task bigint; v_body text; v_dir jsonb; v_d public.ceo_directive;
begin
  -- the morning read: every path metric against today (idempotent: the verdict opens a task once per miss)
  v_verdict := public.fn_ceo_target_daily_verdict(p_at);
  v_status := public.fn_ceo_year_plan_status(p_at);

  -- unblocking: a handoff the receiving seat never answered within twice its reply time (a day when none is set)
  for h in select a.id, a.agent, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v_stuck := v_stuck || jsonb_build_object('handoff_id', h.id, 'seat', h.agent, 'type', h.type, 'from', h.from_seat, 'since', h.created_at);
    if not exists (select 1 from public.ceo_task where title = format('Stuck handoff #%s', h.id)) then
      v_task := public.fn_ceo_task_open(format('Stuck handoff #%s', h.id),
        format(E'%s from %s to %s has waited since %s with no answer. The CEO re-runs it (fn_seat_handoff_act) and, if it fails again, the failure is on this task.',
               h.type, h.from_seat, h.agent, h.created_at));
      begin
        perform public.fn_seat_handoff_act(h.id);                    -- the unblock: the receiving seat acts now
        update public.ceo_task set state = 'done', closed_at = now(), evidence = 'Re-run on ' || v_day || ': the seat answered.'
         where task_id = v_task and exists (select 1 from public.agent_actions where id = h.id and (status = 'done' or detail ? 'replied_at'));
      exception when others then
        update public.ceo_task set state = 'blocked', blocked_reason = left('Re-run failed: ' || sqlerrm, 1000) where task_id = v_task;
      end;
      n_stuck_new := n_stuck_new + 1;
    end if;
  end loop;

  -- the experience, cash and incident signals
  v_signals := jsonb_build_object(
    'stranded_registrations', public.fn_ceo_plan_measure('stranded_submissions', p_at - interval '1 day', p_at),
    'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at - interval '7 days', p_at),
    'requests_unquoted_3d', (select count(*) from public.inquiries i join public.customers c on c.id = i.customer_id
                               where i.parent_inquiry_id is null and i.created_at < p_at - interval '3 days' and i.created_at > p_at - interval '30 days'
                                 and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
                                 and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
                                 and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid')),
    'findings_open', (select count(*) from public.it_engineer_finding where closed_at is null),
    'findings_new_today', (select count(*) from public.it_engineer_finding where closed_at is null and started_at > p_at - interval '1 day'),
    'fee_month_aed', public.fn_ambition_measure('fee_aed', v_from, p_at),
    'costs_month_aed', public.fn_ambition_measure('costs_aed', v_from, p_at),
    'cost_ceiling_month_aed', (select cost_ceiling_aed from public.ceo_year_plan where month = v_m0),
    'stale_tasks', (select count(*) from public.ceo_task where state in ('open', 'working', 'blocked') and created_at < p_at - interval '14 days'));

  -- the directives: issued from the signals above and re-checked on their own done-condition before the priorities
  v_dir := public.fn_ceo_directive_run(p_at);

  -- the day's priorities per seat: its earliest-due open directive, in words; else its oldest improvement's proposal
  foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
    select e into v_m from jsonb_array_elements(v_status->'metrics') e
     where e->>'owner_seat' = s and e->>'status' in ('miss', 'within_tolerance')
     order by (e->>'status' = 'miss') desc, abs(coalesce((e->>'gap_pct')::numeric, 0)) desc limit 1;
    v_d := null;
    select * into v_d from public.ceo_directive d where d.seat = s and d.status = 'open' order by d.deadline, d.id limit 1;
    v_first := case
      when v_d.id is not null then format('Directive #%s, due %s: %s Done when %s', v_d.id,
        to_char(v_d.deadline at time zone 'Asia/Dubai', 'DD Mon HH24:MI'), v_d.instruction, v_d.done_when)
      when v_m is not null then format('Recover %s: %s against %s today (%s).', v_m->>'metric', coalesce(v_m->>'actual', '?'), v_m->>'expected', v_m->>'status')
      when exists (select 1 from jsonb_array_elements(v_stuck) e where e->>'seat' = s) then 'Answer the handoffs waiting past their reply time.'
      when exists (select 1 from public.ceo_improvement i where i.seat = s and i.status = 'assigned') then
        (select format('Improvement #%s: %s', i.id, left(i.proposal, 300)) from public.ceo_improvement i
          where i.seat = s and i.status = 'assigned' order by i.id limit 1)
      else 'Hold the path: every target of the month is on track.' end;
    v_prio := v_prio || jsonb_build_object(s, jsonb_build_object('first', v_first,
      'misses', (select coalesce(jsonb_agg(e->>'metric'), '[]'::jsonb) from jsonb_array_elements(v_status->'metrics') e where e->>'owner_seat' = s and e->>'status' = 'miss'),
      'directive_id', v_d.id,
      'stuck_handoffs', (select count(*) from jsonb_array_elements(v_stuck) e where e->>'seat' = s),
      'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = s and i.status in ('open', 'assigned'))));
  end loop;

  -- what matters enough for the founder's daily note (otherwise he gets nothing today)
  if coalesce((v_verdict->>'tasks_opened')::int, 0) > 0 then v_matters := v_matters || format('%s target(s) fell behind the path today', v_verdict->>'tasks_opened'); end if;
  if n_stuck_new > 0 then v_matters := v_matters || format('%s handoff(s) were stuck and re-run', n_stuck_new); end if;
  if coalesce((v_signals->>'stranded_registrations')::numeric, 0) > 0 then v_matters := v_matters || format('%s supplier registration(s) waited over 24 hours', v_signals->>'stranded_registrations'); end if;
  if coalesce((v_signals->>'bounce_pct_7d')::numeric, 0) >= 5 then v_matters := v_matters || format('email bounces at %s %% over 7 days', v_signals->>'bounce_pct_7d'); end if;
  if coalesce((v_signals->>'requests_unquoted_3d')::int, 0) > 0 then v_matters := v_matters || format('%s request(s) have no quote after 3 days', v_signals->>'requests_unquoted_3d'); end if;
  if coalesce((v_signals->>'costs_month_aed')::numeric, 0) > coalesce((v_signals->>'cost_ceiling_month_aed')::numeric, 1e12) then
    v_matters := v_matters || format('costs this month AED %s are over the ceiling of AED %s', round((v_signals->>'costs_month_aed')::numeric), v_signals->>'cost_ceiling_month_aed');
  end if;

  insert into public.ceo_day (day, facts, priorities, matters)
  values (v_day, jsonb_build_object('verdict', v_verdict, 'plan', v_status, 'signals', v_signals, 'stuck', v_stuck), v_prio, v_matters)
  on conflict (day) do update set facts = excluded.facts, priorities = excluded.priorities,
    matters = coalesce((select array_agg(distinct m) from unnest(ceo_day.matters || excluded.matters) m), '{}'), updated_at = now();

  select note_handoff_id into v_note from public.ceo_day where day = v_day;
  if cardinality(v_matters) > 0 and v_note is null then
    v_body := 'Today, ' || to_char(v_day, 'Dy DD Mon') || E':\n- ' || array_to_string(v_matters, E'\n- ')
      || E'\n\nWhat the seats do about it:\n' || (select string_agg(format('- %s: %s', k, v->>'first'), E'\n' order by k) from jsonb_each(v_prio) x(k, v));
    v_note := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_day', v_day::text,
      jsonb_build_object('recipient_role', 'founder', 'event', 'CEO daily note: ' || to_char(v_day, 'Dy DD Mon'), 'detail', left(v_body, 4000),
                         'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_day:' || v_day));
    update public.ceo_day set note_handoff_id = v_note where day = v_day;
  end if;
  return jsonb_build_object('day', v_day, 'misses', v_verdict->'misses', 'stuck_new', n_stuck_new, 'matters', to_jsonb(v_matters),
                            'note_handoff_id', v_note, 'priorities', v_prio, 'directives', v_dir);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_daily_run_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_daily_run(now()) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decide(p_path text, p_item_key text, p_originator text, p_decision text, p_reasons text, p_version jsonb DEFAULT '{}'::jsonb, p_source_table text DEFAULT NULL::text, p_source_id text DEFAULT NULL::text, p_revise_handoffs bigint[] DEFAULT NULL::bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x public.ceo_decision_round; n jsonb; v_gen int; v_round int; v_rej int; v_h bigint;
  v_ids bigint[] := coalesce(p_revise_handoffs, '{}'); v_problem text; v_version jsonb := coalesce(p_version, '{}'::jsonb);
begin
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || p_item_key));
  if p_source_id is not null then
    select * into x from public.ceo_decision_round
     where item_key = p_item_key and source_table is not distinct from p_source_table and source_id = p_source_id;
    if found then
      return jsonb_build_object('recorded', true, 'already', true, 'round_id', x.id, 'decision', x.decision,
                                'generation', x.generation, 'round', x.round);
    end if;
  end if;
  n := public.fn_ceo_decision_next(p_item_key);
  if not (n->>'open')::boolean then
    return jsonb_build_object('recorded', false, 'closed', true, 'item_key', p_item_key, 'decision', n->>'last_decision', 'round_id', n->'last_id');
  end if;
  v_problem := public.fn_ceo_reasons_problem(p_reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: every CEO decision carries its reasons (' || p_decision || ' on ' || p_item_key || '): ' || v_problem;
  end if;
  -- what was decided on is kept, cut to the ledger's bound rather than refusing the decision
  v_version := public.fn_ceo_decision_version_cut(v_version);
  v_gen := (n->>'generation')::int; v_round := (n->>'round')::int; v_rej := (n->>'rejections')::int;
  if p_decision = 'rejected' then
    if v_rej >= 4 then
      v_h := public.fn_ceo_decision_owe(p_path, p_item_key, p_originator, v_gen,
               'sent back 4 times; a fifth rejection is refused, so the CEO approves it, or replaces or withdraws it', p_reasons, v_version);
      return jsonb_build_object('recorded', false, 'round_limit', true, 'item_key', p_item_key, 'generation', v_gen,
                                'rejections', v_rej, 'decision_owed_handoff', v_h);
    end if;
    if p_revise_handoffs is null then
      v_h := public.fn_seat_handoff('ceo', p_originator, 'ceo.revise', 'ceo_decision_round', p_item_key || ':g' || v_gen || ':r' || v_round,
        jsonb_build_object('path', p_path, 'item_key', p_item_key, 'generation', v_gen, 'round', v_round, 'rounds_left', 4 - v_rej - 1,
                           'reasons', left(p_reasons, 3000), 'version', v_version));
      v_ids := array[v_h];
    end if;
  end if;
  insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons, version, source_table, source_id, revise_handoff_ids)
  values (p_path, p_item_key, p_originator, p_decision, p_reasons, v_version, p_source_table, p_source_id, v_ids)
  returning * into x;
  return jsonb_build_object('recorded', true, 'round_id', x.id, 'decision', x.decision, 'generation', x.generation,
                            'round', x.round, 'revise_handoff_ids', to_jsonb(x.revise_handoff_ids));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decide_refund(p_refund_id bigint, p_approve boolean, p_rationale text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record;
begin
  if coalesce(btrim(p_rationale), '') = '' then
    -- Applies to BOTH directions. The constitution asks for an evidence-based explanation on a
    -- denial specifically, and an approval with no reasoning is just as unauditable.
    return jsonb_build_object('ok', false, 'reason',
      'a rationale is required. A refund decided with no stated reasoning cannot be audited, and a denial owes the customer an explanation.');
  end if;

  select * into r from public.refund_case where refund_id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  if r.state not in ('eligible','ineligible','requested','investigating') then
    return jsonb_build_object('ok', false, 'reason',
      format('this refund is already %L. Deciding it again would be a second remedy on the same money.', r.state));
  end if;

  update public.refund_case
     set state = case when p_approve then 'ceo_authorized' else 'ceo_declined' end,
         decided_by = 'ceo', decided_at = now(),
         decision = case when p_approve then 'approved' else 'declined' end,
         decision_rationale = p_rationale, updated_at = now()
   where refund_id = p_refund_id;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id,
    'state', case when p_approve then 'ceo_authorized' else 'ceo_declined' end,
    'note', case when p_approve
                 then 'Authorised. Execution is the payment service''s, and the states stay separate: authorised is not submitted, and submitted is not settled.'
                 else 'Declined with a rationale. Support owes the customer that explanation and an appropriate alternative remedy -- a decline is not the end of the case.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decide_report(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text; v_family text; v jsonb;
begin
  select idempotency_key into v_key from public.support_ceo_report where id = p_report_id;
  if v_key is null then return jsonb_build_object('ok', false, 'reason', 'no report ' || p_report_id); end if;
  v_family := split_part(v_key, ':', 1);
  v := case v_family
    when 'backup_escalation'         then public.fn_ceo_backup_escalation_decide(p_report_id)
    when 'dropbox_backup_escalation' then public.fn_ceo_backup_coverage_decide(p_report_id)
    when 'delivery_undelivered'      then public.fn_ceo_delivery_undelivered_decide(p_report_id)
    when 'it_backup_heartbeat'       then public.fn_ceo_backup_heartbeat_decide(p_report_id)
    when 'dropbox_backup_daily'      then public.fn_ceo_backup_daily_decide(p_report_id)
    else jsonb_build_object('ok', false, 'report_id', p_report_id, 'family', v_family, 'reason', 'no decider for this family')
  end;
  -- A decider that answered 'undecided' refused on purpose (a founder alert with no confirmed delivery on any channel
  -- is "not the CEO's to wave through"): it stays 'sent' so the IT silence watch still tells the founder.
  if exists (select 1 from public.support_ceo_report where id = p_report_id and status = 'sent')
     and coalesce(v ->> 'reason', '') not like 'undecided%' then
    v := public.fn_ceo_report_default_decide(p_report_id, v_family || ': ' || coalesce(v ->> 'reason', 'the decider left it open'))
         || jsonb_build_object('family_answer', v);
  end if;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decides_post_reveal_dispute(p_id bigint, p_outcome text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.post_reveal_dispute; c record; s record; v_ref text; v_en text; v_ar text;
begin
  if p_outcome is null or p_outcome not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    raise exception 'the outcome is customer_upheld, supplier_upheld, shared or no_fault, not %', p_outcome;
  end if;
  update public.post_reveal_dispute set stage = 'decided', outcome = p_outcome, outcome_note = p_note,
         decided_by = 'ceo', decided_at = now()
   where id = p_id and stage in ('review', 'ceo_decision') returning * into d;
  if not found then raise exception 'dispute % is not awaiting a decision', p_id; end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO decided the dispute'
   where issue_key = 'dispute_decision_overdue:' || p_id and closed_at is null;
  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');
  v_en := case p_outcome when 'customer_upheld' then 'the customer''s complaint is upheld'
    when 'supplier_upheld' then 'the supplier''s position is upheld' when 'shared' then 'responsibility is shared by both parties'
    else 'no fault was found on either side' end;
  v_ar := case p_outcome when 'customer_upheld' then 'قُبلت شكوى العميل'
    when 'supplier_upheld' then 'ثبت موقف المورّد' when 'shared' then 'المسؤولية مشتركة بين الطرفين'
    else 'لم يثبت تقصير على أي من الطرفين' end;
  select c2.email, c2.locale into c from public.customers c2 where c2.id = d.customer_id;
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = d.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.decided', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'القرار في القضية ' || v_ref else 'Dispute ' || v_ref || ': the decision' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'راجعنا القضية ' || v_ref || ' بعد الاطلاع على أقوال الطرفين ومستنداتهما، وانتهت المراجعة إلى أنه ' || v_ar || '. '
        || 'وإن كان لديكم اعتراض على القرار، فيسعدنا أن تردّوا على هذه الرسالة خلال عشرة أيام عمل.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'We have reviewed dispute ' || v_ref || ' on the statements and evidence of both parties. The outcome: ' || v_en || '. '
        || 'If you disagree with the decision, reply to this e-mail within 10 working days.' end,
      case when role = 'customer' then d.customer_id end, case when role = 'supplier' then d.supplier_id end, d.inquiry_id)
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(d.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'outcome', p_outcome);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decision_close(p_item_key text, p_decision text, p_reasons text, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.ceo_decision_round; x public.ceo_decision_round; v_effect jsonb := '{}'::jsonb; v_id bigint;
  r public.refunds; i public.ceo_improvement;
begin
  if p_decision not in ('replaced', 'withdrawn') then
    raise exception 'the CEO closes an open item by replacing or withdrawing it, not %', p_decision using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || p_item_key));
  select * into l from public.ceo_decision_round where item_key = p_item_key order by generation desc, round desc limit 1;
  if l.id is null or l.decision <> 'rejected' then
    return jsonb_build_object('ok', false, 'reason', 'no open item ' || p_item_key || ' (its last decision is ' || coalesce(l.decision, 'none') || ')');
  end if;
  if l.path = 'seat_deliberation' and exists (select 1 from public.seat_deliberation d
       where d.id = (l.version->>'deliberation_id')::bigint and d.status = 'open') then
    return jsonb_build_object('ok', false, 'reason', 'the revision is under review now; the CEO decides it at its review turn');
  end if;
  if l.path = 'refund' then   -- locked, and still an open request, before the ledger says anything about it
    select * into r from public.refunds where id = split_part(p_item_key, ':', 2)::bigint for update;
    if r.id is null or r.status <> 'requested' then
      return jsonb_build_object('ok', false, 'reason', 'refund ' || split_part(p_item_key, ':', 2) || ' is ' || coalesce(r.status, 'missing') || ', not an open request');
    end if;
  end if;
  insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons, version, source_table, source_id)
  values (l.path, p_item_key, l.originator_seat, p_decision, p_reasons,
          public.fn_ceo_decision_version_cut(l.version || jsonb_build_object('closes_round_id', l.id, 'closing', coalesce(p_detail, '{}'::jsonb))),
          'ceo_decision_close', null)
  returning * into x;

  if l.path = 'refund' then
    if p_decision = 'withdrawn' then
      -- DECLINED, never paid (fn_ceo_refund_decline, the same decline the review makes). No money guard is involved.
      v_effect := jsonb_build_object('decline', public.fn_ceo_refund_decline(r.id, p_reasons, 'ceo_withdrew', l.version->'failed'));
    end if;
    -- A stalled remediation is superseded by the CEO's decision. Closing its last handoff re-runs the review
    -- (fn_ceo_refund_loop_advance), which for a replaced refund starts the fresh generation and for a declined
    -- one answers that the refund is no longer open.
    for v_id in select a.id from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                  and a.detail->>'type' = 'refund.remediate' and a.detail->>'refund_id' = r.id::text order by a.id loop
      perform public.fn_seat_handoff_complete(v_id, jsonb_build_object('superseded_by_ceo', p_decision, 'round_id', x.id,
                                                                         'reasons', left(p_reasons, 2000)));
      v_effect := v_effect || jsonb_build_object('superseded_remediation', coalesce(v_effect->'superseded_remediation', '[]'::jsonb) || to_jsonb(v_id));
    end loop;
    if p_decision = 'replaced' and not (v_effect ? 'superseded_remediation') then
      v_effect := v_effect || jsonb_build_object('review', public.fn_ceo_refund_review(r.id, 'ceo_replaced'));
    end if;
  elsif l.path = 'ceo_experiment' then
    update public.ceo_experiment
       set status = 'rejected', closed_at = now(), updated_at = now(),
           approval = coalesce(approval, '{}'::jsonb) || jsonb_build_object('closed_by_ceo', p_decision, 'reasons', left(p_reasons, 4000), 'round_id', x.id)
     where id = split_part(p_item_key, ':', 2)::bigint and status = 'proposed';
    v_effect := jsonb_build_object('experiment_closed', found);
  elsif l.path = 'ceo_improvement' then
    select * into i from public.ceo_improvement where id = split_part(p_item_key, ':', 2)::bigint for update;
    if i.id is not null and i.status in ('open', 'assigned') then
      update public.ceo_improvement set status = 'dropped', closed_at = now(), done_evidence = p_decision || ' by the CEO: ' || left(p_reasons, 3000)
       where id = i.id;
      update public.ceo_task set state = 'done', closed_at = now(), evidence = left(coalesce(evidence || E'\n', '') || p_decision || ' by the CEO: ' || p_reasons, 8000)
       where task_id = i.task_id and state in ('open', 'working', 'blocked');
      v_effect := jsonb_build_object('improvement_dropped', i.id);
    end if;
    -- the conversation closes whatever the improvement's state (it may have finished while the CEO's choice was
    -- owed, and the review sweep no longer reads a handoff that is waiting on that choice)
    if i.handoff_id is not null and exists (select 1 from public.agent_actions where id = i.handoff_id and status = 'pending') then
      perform set_config('qd.handoff_closer', 'ceo', true);
      perform public.fn_seat_handoff_complete(i.handoff_id, jsonb_build_object('verified_by', 'ceo', 'improvement_id', i.id,
        'closed', p_decision, 'reasons', left(p_reasons, 2000), 'round_id', x.id));
      perform set_config('qd.handoff_closer', '', true);
      v_effect := v_effect || jsonb_build_object('handoff_closed', i.handoff_id);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'round_id', x.id, 'decision', x.decision, 'generation', x.generation, 'round', x.round, 'effect', v_effect);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decision_next(p_item_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when l.id is null
    then jsonb_build_object('open', true, 'generation', 1, 'round', 1, 'rejections', 0)
    else jsonb_build_object('open', l.decision not in ('approved', 'withdrawn'), 'last_id', l.id, 'last_decision', l.decision,
      'last_round', l.round, 'path', l.path, 'originator', l.originator_seat,
      'generation', case when l.decision = 'replaced' then l.generation + 1 else l.generation end,
      'round', case when l.decision = 'replaced' then 1 else l.round + 1 end,
      'rejections', case when l.decision = 'replaced' then 0
                         else (select count(*) from public.ceo_decision_round r
                                where r.item_key = p_item_key and r.generation = l.generation and r.decision = 'rejected') end)
  end
  from (select 1) one
  left join lateral (select * from public.ceo_decision_round r where r.item_key = p_item_key order by r.generation desc, r.round desc limit 1) l on true
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decision_owe(p_path text, p_item_key text, p_originator text, p_generation integer, p_why text, p_last_reasons text DEFAULT NULL::text, p_version jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_after int := coalesce((select max(r.round) from public.ceo_decision_round r
                                  where r.item_key = p_item_key and r.generation = p_generation), 0);
begin
  return public.fn_seat_handoff(p_originator, 'ceo', 'ceo.decision_owed', 'ceo_decision_round',
    p_item_key || ':g' || p_generation || ':after_r' || v_after,
    jsonb_build_object('path', p_path, 'item_key', p_item_key, 'generation', p_generation, 'after_round', v_after, 'why', p_why,
      'last_reasons', left(p_last_reasons, 3000), 'version', coalesce(p_version, '{}'::jsonb),
      'rounds', (select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'decision', r.decision, 'reasons', left(r.reasons, 600))
                                           order by r.round), '[]'::jsonb)
                   from public.ceo_decision_round r where r.item_key = p_item_key and r.generation = p_generation)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decision_version_cut(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when length(coalesce(p, '{}'::jsonb)::text) <= 29000 then coalesce(p, '{}'::jsonb)
    else coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p) e
                    where jsonb_typeof(e.value) in ('number', 'string', 'boolean', 'null') and length(e.value::text) <= 200), '{}'::jsonb)
         || jsonb_build_object('cut_at_12000_chars', left(p::text, 12000)) end
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_decisions_evaluate(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d record; x record;
  v_out jsonb := '[]'::jsonb; v_fired int := 0; v_written int := 0; v_missing text[] := '{}';
  v_blind text[] := '{}';   -- active rules whose MEASURE has no instrument (22 Sep 2026, SEATS-07)
  v_state text; v_detail text; v_reading text;
  v_day date := ((now() at time zone 'Asia/Dubai')::date - 1);   -- the last COMPLETE Dubai day
  v_hold timestamptz := timestamptz '2026-08-15 02:51:33.108565+00';
  v_n bigint; v_m numeric; v_rate numeric; v_prev text; v_ev jsonb;
  v_rows jsonb;   -- [{key, decision, outcome, evidence}] this rule wants written
begin
  for d in select * from public.ceo_decision where active order by decision_key loop
    v_rows := '[]'::jsonb; v_state := 'quiet'; v_detail := null; v_reading := null;
    if d.measure_sql is not null then
      begin execute d.measure_sql into v_reading;
      exception when others then v_reading := 'INSTRUMENT FAILED -- '||sqlerrm; end;
    end if;

    case d.decision_key
    when 'target_is_reachable' then
      -- "Any weekly feasibility run whose verdict is not REACHABLE, or any week the required run rate
      -- rises above twice the highest ever measured." One firing per feasibility run.
      for x in select v.*, c.contract_key,
                      (select max(v2.current_run_rate) from public.target_verdict v2 where v2.contract_id = c.id) as best_rate
                 from public.target_contract c
                 join lateral (select * from public.target_verdict v where v.contract_id = c.id order by v.run_at desc limit 1) v on true
                where c.status = 'active' and c.metric_unit = 'AED'
      loop
        if x.verdict <> 'REACHABLE' or (x.best_rate > 0 and x.required_run_rate > 2 * x.best_rate) then
          v_rows := v_rows || jsonb_build_object('key', 'target_is_reachable:verdict:'||x.id, 'outcome', 'decided',
            'decision', format('The AED 1,000,000 target is NOT reachable on the evidence (verdict %s of %s). What must change: %s',
                               x.verdict, to_char(x.run_at at time zone 'Asia/Dubai','DD Mon YYYY'),
                               coalesce(array_to_string(x.what_must_change, ' '), x.verdict_reason)),
            'evidence', jsonb_build_object('contract', x.contract_key, 'verdict_id', x.id, 'verdict', x.verdict,
              'run_at', x.run_at, 'verdict_reason', x.verdict_reason, 'binding_stage', x.binding_stage,
              'required_run_rate', x.required_run_rate, 'highest_measured_run_rate', x.best_rate,
              'measured_rate_count', x.measured_rate_count, 'assumed_rate_count', x.assumed_rate_count));
        end if;
      end loop;

    when 'binding_constraint' then
      -- "Any week the binding stage named by the feasibility run differs from the one currently being
      -- worked." The one being worked is the stage of the last logged binding_constraint decision.
      select v.* into x from public.target_verdict v join public.target_contract c on c.id = v.contract_id
       where c.status = 'active' and v.binding_stage is not null order by v.run_at desc limit 1;
      if not found then
        v_detail := 'no feasibility run has named a binding stage (target_verdict.binding_stage is null on every run), so there is nothing to compare the worked stage with';
      else
        -- THE STAGE BEING WORKED IS THE PLAN'S, NOT THE LAST LOG LINE'S (22 Sep 2026). The company
        -- works whatever public.ceo_plan.stage names — fn_ceo_plan_tick writes it every Dubai day
        -- and directs the seats from it. Reading the last logged decision instead compared the
        -- verdict with the evaluator's own previous output, which is a loop, not a measurement.
        select p.stage into v_prev from public.ceo_plan p order by p.plan_date desc, p.id desc limit 1;
        if v_prev is null then
          v_detail := 'no CEO plan has named a stage yet (public.ceo_plan is empty), so the stage being worked is unknown';
        end if;
        if v_prev is distinct from x.binding_stage then
          v_rows := jsonb_build_array(jsonb_build_object('key', 'binding_constraint:verdict:'||x.id, 'outcome', 'decided',
            'decision', format('Work the %s stage next: the feasibility run names it as the binding constraint%s.',
                               x.binding_stage, case when v_prev is null then ' and no plan names a stage being worked' else ', and the CEO plan is working '||v_prev end),
            'evidence', jsonb_build_object('verdict_id', x.id, 'run_at', x.run_at, 'binding_stage', x.binding_stage,
              'binding_reason', x.binding_reason, 'stage_being_worked', v_prev, 'stage_read_from', 'ceo_plan.stage')));
        end if;
      end if;

    when 'supplier_admission' then
      -- "A registration arrives with all six present." Fixtures never produce a company decision.
      for x in select l.id, l.company_name, l.verified, l.owner_email_verified, l.owner_phone_verified
                 from public.leads l
                where l.claimed and coalesce(l.company_name,'') not ilike 'ZZ DEMO%'
                  and coalesce(l.email,'') !~* '@example[.]invalid$'
                  and cardinality(public.fn_supplier_mandatory_six_for(l.id)) = 0
      loop
        v_rows := v_rows || jsonb_build_object(
          'key', 'supplier_admission:lead:'||x.id||':'||case when x.owner_email_verified and x.owner_phone_verified then 'admit' else 'hold' end,
          'outcome', 'decided',
          'decision', case when x.owner_email_verified and x.owner_phone_verified
                           then format('Admit %s: all six mandatory fields present, email and UAE mobile confirmed by OTP.', x.company_name)
                           else format('Hold %s: the six are present but the %s is not OTP-confirmed.', x.company_name,
                                       case when not coalesce(x.owner_email_verified,false) then 'email' else 'UAE mobile' end) end,
          'evidence', jsonb_build_object('lead_id', x.id, 'mandatory_missing', '[]'::jsonb,
            'owner_email_verified', x.owner_email_verified, 'owner_phone_verified', x.owner_phone_verified,
            'verified_flag_now', x.verified));
      end loop;

    when 'report_to_founder' then
      -- "Every reporting cadence." Fires once per weekly report the founder actually received.
      for x in select * from public.ceo_weekly_report where founder_submitted_at is not null
                  and report_key like 'quotesdone:%'
                order by week_start desc limit 4
      loop
        select count(*) into v_n from public.ceo_decision_log l
         where l.decided_at > x.founder_submitted_at - interval '7 days' and l.decided_at <= x.founder_submitted_at;
        v_rows := v_rows || jsonb_build_object('key', 'report_to_founder:'||x.report_key||':r'||x.revision, 'outcome', 'decided',
          'decision', format('Reported to the founder: "%s". %s decision(s) taken alone in the week before it; none escalated.', x.subject, v_n),
          'evidence', jsonb_build_object('report_id', x.id, 'report_key', x.report_key, 'notification_id', x.notification_id,
            'delivered_at', x.founder_submitted_at, 'pdf', x.pdf_bucket||'/'||x.pdf_path, 'decisions_alone', v_n, 'escalated', 0));
      end loop;

    when 'channel_volume' then
      -- "Any bounce rate above 5 per cent." Bounces = email_suppressions added for a bounce in the last 7
      -- days, over emails sent in the same window. The "proposal to send more" half has no instrument.
      select count(*) into v_n from public.notifications
       where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
      select count(*) into v_m from public.email_suppressions
       where reason ilike '%bounce%' and created_at > now() - interval '7 days';
      v_rate := case when v_n > 0 then round(100.0 * v_m / v_n, 2) end;
      v_detail := format('bounce %s%% (%s bounced / %s sent, 7 days); proposals to raise volume are not instrumented',
                         coalesce(v_rate::text,'n/a'), v_m, v_n);
      if v_rate > 5 then
        v_rows := jsonb_build_array(jsonb_build_object('key', 'channel_volume:'||v_day, 'outcome', 'decided',
          'decision', format('No outreach channel is raised above its standing ceiling: the 7-day bounce rate is %s%%, above the 5%% limit.', v_rate),
          'evidence', jsonb_build_object('bounced_7d', v_m, 'sent_7d', v_n, 'bounce_pct', v_rate, 'ceilings', v_reading)));
      end if;

    when 'refund' then
      -- "A buyer asks for a refund, or a reveal is disputed." Weighing a buyer's stated reason is
      -- judgement; the CEO's refund review decides it. Until that review has an outcome, say so.
      for x in select t.id, t.refund_status,
                      (select rv.outcome from public.refund_ceo_review rv where rv.transaction_id = t.id
                        order by rv.created_at desc limit 1) as review_outcome
                 from public.transactions t where coalesce(t.refund_status,'') <> ''
      loop
        v_rows := v_rows || jsonb_build_object(
          'key', 'refund:tx:'||x.id||':'||coalesce(x.review_outcome,'open'),
          'outcome', case when x.review_outcome is null then 'needs_judgement' else 'decided' end,
          'decision', case when x.review_outcome is null
                           then format('Refund on transaction %s needs judgement: no CEO refund review has reached an outcome.', x.id)
                           else format('Refund on transaction %s: %s (the CEO refund review).', x.id, x.review_outcome) end,
          'evidence', jsonb_build_object('transaction_id', x.id, 'refund_status', x.refund_status, 'review_outcome', x.review_outcome));
      end loop;

    when 'paid_inference' then
      -- "Any request that needs a paid model while the hold is on." ai_gateway marks those rows HELD.
      -- One firing per complete Dubai day. A charge during the hold is not a rule's to excuse.
      select coalesce(sum(n), 0), coalesce(jsonb_object_agg(fn, n), '{}'::jsonb) into v_n, v_ev from (
        select coalesce(fn, '(unnamed)') fn, count(*) n from public.ai_cost_log
         where model_selected_because like '%HELD:%'
           and occurred_at >= (v_day::timestamp at time zone 'Asia/Dubai')
           and occurred_at <  ((v_day + 1)::timestamp at time zone 'Asia/Dubai')
         group by fn) s;
      select coalesce(sum(cost_aed),0) into v_m from public.ai_cost_log where occurred_at > v_hold;
      if v_n > 0 or v_m > 0 then
        v_rows := jsonb_build_array(jsonb_build_object('key', 'paid_inference:'||v_day,
          'outcome', case when v_m > 0 then 'needs_judgement' else 'decided' end,
          'decision', case when v_m > 0
            then format('Paid inference was charged during the hold (AED %s since 15 Aug). The hold is the founder''s constraint; this is not excused by a rule.', v_m)
            else format('Paid inference refused on %s for %s request(s) that asked for a model; each was held and answered without one. Cost since the hold: AED 0.', v_day, v_n) end,
          'evidence', jsonb_build_object('day', v_day, 'held_requests', v_n, 'held_by_function', v_ev, 'cost_since_hold_aed', v_m)));
      end if;

    when 'risk_owner' then
      -- "A risk is raised, or a mitigation passes its review date untested." public.risk_register
      -- holds the live risks (risk, owner_agent, mitigation, status, review_due). What it CANNOT
      -- answer is when a mitigation was last actually tested — nothing records a test — so this
      -- rule fires on the two halves that ARE measurable and says so in its detail.
      for x in select rr.id, rr.risk, rr.owner_agent, rr.mitigation, rr.review_due, rr.dept_key,
                      (rr.owner_agent is null or not exists (select 1 from public.org_agents oa
                         where oa.agent_key = rr.owner_agent and oa.active)) as no_live_owner,
                      (rr.review_due is not null and rr.review_due < current_date) as review_past
                 from public.risk_register rr where rr.status = 'open'
      loop
        continue when not (x.no_live_owner or x.review_past);
        v_rows := v_rows || jsonb_build_object(
          'key', 'risk_owner:risk:'||x.id||':'||case when x.no_live_owner then 'unowned' else 'review_past' end,
          'outcome', 'needs_judgement',
          'decision', case when x.no_live_owner
            then format('Risk %s ("%s") has no live owner (%s): the CEO must name the seat that owns it and the date its mitigation is tested.',
                        x.id, left(x.risk, 90), coalesce(x.owner_agent, 'nobody named'))
            else format('Risk %s ("%s") passed its review date (%s) with no recorded test: the CEO must re-date it or retire it.',
                        x.id, left(x.risk, 90), x.review_due) end,
          'evidence', jsonb_build_object('risk_id', x.id, 'risk', x.risk, 'owner_agent', x.owner_agent,
            'owner_is_a_live_seat', not x.no_live_owner, 'mitigation', x.mitigation, 'review_due', x.review_due,
            'department', x.dept_key,
            'not_measured', 'no table records when a mitigation was last actually tested; this firing reads ownership and review date only'));
      end loop;
      v_detail := 'read from public.risk_register (open risks: owner not a live seat, or review_due past). '
                  || 'NOT measured: when a mitigation was last actually tested — nothing records it.';

    when 'spend_against_constraint' then
      -- INSTRUMENTED FROM THE ACCOUNTANT'S BOOKS (28 Sep 2026, ceo). Spend = posted gl_journal_lines
      -- on expense accounts, debit minus credit, over the last 30 days. Each expense account is
      -- attributed to a funnel stage (or 'overhead' = aimed at no stage) in
      -- public.gl_account_funnel_stage. The binding stage is the latest feasibility verdict's; when
      -- no verdict names one, the stage the CEO plan is working (ceo_plan.stage) stands in, and the
      -- evidence says which was used. Fires: stage-aimed spend on a stage other than the binding one
      -- (decided: move it), and any expense account with spend but no attribution (needs_judgement).
      v_prev := null;
      select v.binding_stage into v_prev from public.target_verdict v join public.target_contract c on c.id = v.contract_id
       where c.status = 'active' and v.binding_stage is not null order by v.run_at desc limit 1;
      v_ev := jsonb_build_object('binding_stage_read_from', 'target_verdict.binding_stage');
      if v_prev is null then
        select p.stage into v_prev from public.ceo_plan p order by p.plan_date desc, p.id desc limit 1;
        v_ev := jsonb_build_object('binding_stage_read_from', 'ceo_plan.stage (no feasibility verdict names a binding stage)');
      end if;
      for x in select coalesce(fs.stage, '(unattributed)') as stage, fs.stage is null as unattributed,
                      jsonb_agg(s.account_code order by s.account_code) as accounts, sum(s.amt) as amt
                 from (select l.account_code, sum(l.debit - l.credit) as amt
                         from public.gl_journal_lines l
                         join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
                         join public.gl_accounts a on a.code = l.account_code and a.type = 'expense'
                        where j.entry_date > current_date - 30
                        group by l.account_code having sum(l.debit - l.credit) <> 0) s
                 left join public.gl_account_funnel_stage fs on fs.account_code = s.account_code
                group by 1, 2
      loop
        continue when x.stage = 'overhead';
        continue when not x.unattributed and x.stage is not distinct from v_prev;
        v_rows := v_rows || jsonb_build_object(
          'key', 'spend_against_constraint:'||to_char(v_day, 'YYYY-MM')||':'||x.stage,
          'outcome', case when x.unattributed then 'needs_judgement' else 'decided' end,
          'decision', case when x.unattributed
            then format('AED %s of spend in the last 30 days sits on expense account(s) %s that no row attributes to a funnel stage: the CEO must attribute it before it can be judged against the binding stage (%s).',
                        x.amt, x.accounts, coalesce(v_prev, 'unknown'))
            else format('AED %s of spend in the last 30 days went to the %s stage while the binding stage is %s: move it to %s.',
                        x.amt, x.stage, coalesce(v_prev, 'unknown'), coalesce(v_prev, 'the binding stage')) end,
          'evidence', v_ev || jsonb_build_object('amount_aed', x.amt, 'stage_aimed_at', x.stage, 'accounts', x.accounts,
            'binding_stage', v_prev, 'window_days', 30, 'source', 'gl_journal_lines (posted, expense accounts)'));
      end loop;
      v_detail := format('read from the books: posted expense lines, 30 days, attributed by gl_account_funnel_stage; binding stage %s (%s)',
                         coalesce(v_prev, 'unknown'), v_ev->>'binding_stage_read_from');

    when 'structure' then
      v_state := 'founder_specified'; v_detail := 'the founder specifies the seats; the CEO decides nothing here';

    when 'company_stage' then
      -- 28 Sep 2026 (ceo; it_engineer sweep, ledger 760): the stage move is its own seat duty
      -- (seat_duty 'ceo.company_stage' -> fn_ceo_company_stage_advance, daily), which writes
      -- ceo_company_stage_log with the exit readings. Unnamed here, the rule counted as no_evaluator and
      -- heartbeat step ceoDecisions has failed every hour since 24 Sep 02:46 UTC.
      v_state := 'decided_by_the_plan'; v_detail := 'fn_ceo_company_stage_advance (seat_duty ceo.company_stage)';

    when 'directive_escalation' then
      -- 29 Sep 2026 (ceo, founder_instruction 1059 audit): the rule is decided by its own duty. fn_ceo_directive_run
      -- (seat_duty ceo.directive, hourly) re-issues a directive that passed its deadline unmet, once, writes this
      -- rule's ceo_decision_log row with the directive, its done-condition and the re-issue id, and turns a second
      -- miss into a CEO task. Unnamed here, the rule counted as no_evaluator (the_ceo_issues_directives_and_closes_
      -- them_on_their_own_condition.sql added it without telling the evaluator), which fails heartbeat step ceoDecisions.
      v_state := 'decided_by_its_duty';
      v_detail := 'fn_ceo_directive_run (seat_duty ceo.directive); open directives past their deadline now: ' || coalesce(v_reading, '?');

    when 'seat_directive', 'constraint_stalled', 'plan_review' then
      -- 22 Sep 2026 (ceo): decided by the daily plan on its own heartbeat step (fn_ceo_plan_tick, step
      -- ceoPlan), which writes these rows with their evidence. Named here so they are not no_evaluator.
      v_state := 'decided_by_the_plan'; v_detail := 'fn_ceo_plan_tick (the_ceo_plans_every_day_and_directs_the_seats.sql)';

    else
      v_state := 'no_evaluator'; v_missing := v_missing || d.decision_key;
    end case;

    if jsonb_array_length(v_rows) > 0 then
      v_state := 'fired'; v_fired := v_fired + jsonb_array_length(v_rows);
      if not p_dry_run then
        with ins as (
          insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, escalated_to_founder, outcome, dedupe_key)
          select d.decision_key, e->>'decision', (e->'evidence') || jsonb_build_object('rule', d.trigger_condition),
                 v_reading, false, e->>'outcome', e->>'key'
            from jsonb_array_elements(v_rows) e
          on conflict (dedupe_key) where dedupe_key is not null do nothing
          returning 1)
        select v_written + count(*) into v_written from ins;
      end if;
    end if;

    v_out := v_out || jsonb_build_object('rule', d.decision_key, 'state', v_state, 'firings', jsonb_array_length(v_rows),
                                         'detail', v_detail, 'keys', (select jsonb_agg(e->'key') from jsonb_array_elements(v_rows) e));
  end loop;

  -- ok is the honest answer to "was every active rule actually evaluated". A branch that answers
  -- 'not_instrumented' did not evaluate anything, so it cannot leave ok true (22 Sep 2026).
  --
  -- THE KEY NAME IS LOAD-BEARING, DO NOT "TIDY" IT — AND NO CHECK WILL STOP YOU. The review of
  -- #852 measured this: renaming `uninstrumented_error` to `error` still passes every assertion in
  -- the repository. It is caught only OPERATIONALLY, and late: the ceoDecisions step goes
  -- permanently red on the heartbeat, which is how an estate learns to ignore a red step. The
  -- reason the name matters is below; treat this paragraph as the check that does not exist.
  -- resilience_ping's failureOf (steps.ts:14)
  -- counts a step as FAILED only when it answers ok:false AND a string `error` key; ok:false with
  -- no `error` is a result that has already reported itself, and is deliberately left alone.
  -- The missing-evaluator case keeps `error` because it IS a heartbeat failure — a rule nothing
  -- evaluates is a defect in the code. The uninstrumented case is reported under
  -- `uninstrumented_error` instead, because it is a standing, known gap the CEO must close by
  -- instrumenting the measure or deactivating the rule, not a tick that went wrong. Renaming it to
  -- `error` would turn the ceoDecisions step permanently red and train the estate to ignore it.
  return jsonb_build_object('ok', cardinality(v_missing) = 0 and cardinality(v_blind) = 0, 'dry_run', p_dry_run,
           'fired', v_fired, 'written', v_written, 'rules', v_out,
           'not_instrumented', to_jsonb(v_blind))
      || case when cardinality(v_missing) = 0 then '{}'::jsonb
              else jsonb_build_object('error', 'active ceo_decision rule(s) with no evaluator: '||array_to_string(v_missing, ', ')) end
      || case when cardinality(v_blind) = 0 then '{}'::jsonb
              else jsonb_build_object('uninstrumented_error',
                     'active ceo_decision rule(s) whose measure has no instrument, so they were not evaluated: '
                     ||array_to_string(v_blind, ', ')) end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_delivery_undelivered_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.support_ceo_report; n public.notifications; twin public.notifications; v_receipt text;
  v_req public.agent_actions; v_subject bigint;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  select * into n from public.notifications
   where id = coalesce((r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                       (r.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
  if n.id is null then
    -- The report may name the notification only through its request (18 Sep reports did: the
    -- recheck found "nothing was queued"). A subject that no longer exists cannot be re-checked.
    select * into v_req from public.agent_actions
     where id = nullif(r.verified_evidence ->> 'request_id', '')::bigint and kind = 'handoff';
    -- subject_id is a notifications.id only when it is all digits; a never-queued message carries a text dedupe key.
    v_subject := coalesce(case when v_req.detail ->> 'subject_id' ~ '^[0-9]{1,18}$' then (v_req.detail ->> 'subject_id')::bigint end,
                          (r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint);
    if v_req.id is not null and v_req.detail ->> 'subject_table' = 'notifications' and v_subject is not null
       and not exists (select 1 from public.notifications x where x.id = v_subject) then
      v_receipt := 'ceo: the founder alert this report is about (notification ' || v_subject || ', request '
                   || v_req.id || ') no longer exists in public.notifications, so its delivery can never be '
                   || 're-checked and there is nothing left to deliver. Closed on that fact rather than left open for ever.';
      update public.support_ceo_report
         set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
       where id = r.id;
      return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', v_subject, 'subject_present', false, 'receipt', v_receipt);
    end if;
    return jsonb_build_object('ok', false, 'report_id', r.id, 'reason', 'the report names no notification');
  end if;
  -- The email twin fn_notify_founder writes in the same statement as the WhatsApp fan-out.
  select * into twin from public.notifications t
   where t.channel = 'email' and t.type = n.type and t.created_at = n.created_at
     and t.to_role is not distinct from n.to_role and t.id <> n.id and t.status = 'sent'
   order by t.id limit 1;

  -- 22 Sep 2026 (every_whatsapp_says_whether_it_arrived.sql): for WhatsApp and SMS a SID is only Twilio's
  -- acceptance; "the provider confirmed" needs Twilio's delivered/read report.
  if n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> ''
     and (coalesce(n.channel, 'email') not in ('whatsapp', 'sms') or n.provider_status in ('delivered', 'read')) then
    v_receipt := 'ceo: the provider confirmed notification ' || n.id || ' (' || n.channel || ', message '
                 || n.provider_message_id || ', sent ' || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai)';
  elsif n.status = 'sent' and n.channel = 'whatsapp' and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' was handed to Twilio at '
                 || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai '
                 || case when coalesce(btrim(n.provider_message_id), '') = '' then 'without a provider id on record; '
                         else '(message ' || n.provider_message_id || ') and Twilio has not reported it delivered; ' end
                 || 'the email twin ' || twin.id || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || ').';
  elsif n.status in ('failed', 'skipped', 'suppressed') and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' (' || n.channel || ') ended ' || n.status
                 || coalesce(' — ' || left(n.last_error, 160), '') || '; the email twin ' || twin.id
                 || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || '), so the alert reached the founder.';
  else
    -- A founder alert with no delivered twin, or still in the queue: not the CEO's to wave through.
    return jsonb_build_object('ok', false, 'report_id', r.id, 'notification_id', n.id, 'status', n.status,
                              'reason', 'undecided: no confirmed delivery on any channel');
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', n.id, 'receipt', v_receipt);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_directive_issue(p_seat text, p_kind text, p_ref text, p_instruction text, p_done_when text, p_done_sql text, p_deadline timestamp with time zone, p_evidence jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_done boolean;
begin
  if exists (select 1 from public.ceo_directive where seat = p_seat and source_kind = p_kind and source_ref = p_ref and status <> 'met')
     or not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return null;
  end if;
  begin
    execute 'select coalesce((' || p_done_sql || ')::boolean, false)' into v_done;
  exception when others then v_done := false;
  end;
  if v_done then
    return null;   -- nothing to direct: the condition is already met
  end if;
  insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, evidence)
  values (p_seat, p_kind, p_ref, p_instruction, p_done_when, p_done_sql, p_deadline, coalesce(p_evidence, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_directive_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; d public.ceo_directive; v bigint; v_ok boolean; v_err text; v_new bigint; v_dec bigint; v_task bigint;
  n_issued int := 0; n_met int := 0; n_esc int := 0; n_missed int := 0; v_q date;
  v_late text := $q$exists (select 1 from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = %1$L and a.status = 'pending' and a.created_at < now() - k.reply_within)$q$;
begin
  -- 1. target misses on the year-one plan
  for r in select e->>'metric' as metric, e->>'owner_seat' as seat, e->>'actual' as actual, e->>'expected' as expected
             from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(p_at)->'metrics', '[]'::jsonb)) e
            where e->>'status' = 'miss' and e->>'owner_seat' is not null loop
    v := public.fn_ceo_directive_issue(r.seat, 'target_miss', r.metric || ':' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM'),
      format('Bring %s back to its path: it reads %s against %s. Name the step that is not converting and change that step.', r.metric, coalesce(r.actual, '?'), r.expected),
      format('%s is no longer a miss on the year-one plan.', r.metric),
      format($q$not exists (select 1 from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb)) e where e->>'metric' = %L and e->>'status' = 'miss')$q$, r.metric),
      p_at + interval '7 days', jsonb_build_object('metric', r.metric, 'actual', r.actual, 'expected', r.expected));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 2. late deliverables: the month marketing plan
  for r in select i.id, (i.evidence->>'plan_month')::date as m, (i.evidence->>'deadline')::date as due_was, (i.evidence->>'due_on')::date as due_on
             from public.ceo_improvement i where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    v := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'marketing_month_plan:' || r.m,
      format('Send the CEO the marketing plan for %s. It was due on %s; the month does not start unplanned.', to_char(r.m, 'FMMonth YYYY'), to_char(r.due_was, 'DD Mon')),
      format('marketing_month_plan for %s exists and has left draft, or improvement #%s is closed.', r.m, r.id),
      format($q$exists (select 1 from public.marketing_month_plan p where p.month = %L::date and p.status <> 'draft') or exists (select 1 from public.ceo_improvement i where i.id = %s and i.status = 'done')$q$, r.m, r.id),
      greatest(coalesce(r.due_on::timestamp at time zone 'Asia/Dubai', p_at), p_at) + interval '1 day',
      jsonb_build_object('improvement_id', r.id, 'plan_month', r.m, 'due_was', r.due_was));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 3. stuck handoffs: pending past twice the kind's reply window (a day when none is set), as the daily run reads them
  for r in select a.id, a.agent as seat, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v := public.fn_ceo_directive_issue(r.seat, 'stuck_handoff', 'agent_actions:' || r.id,
      format('Answer handoff #%s (%s from %s), waiting since %s.', r.id, r.type, r.from_seat, to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')),
      format('handoff #%s is answered (replied_at set) or no longer pending.', r.id),
      format($q$exists (select 1 from public.agent_actions a where a.id = %s and (a.status <> 'pending' or a.detail ? 'replied_at'))$q$, r.id),
      p_at + interval '1 day', jsonb_build_object('handoff_id', r.id, 'type', r.type, 'from', r.from_seat, 'since', r.created_at));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 4. the latest seat audit's below-bar seats
  select max(quarter) into v_q from public.ceo_seat_audit;
  for r in select a.seat, a.shortfalls, a.improvement_id from public.ceo_seat_audit a where a.quarter = v_q and a.below_bar loop
    v := public.fn_ceo_directive_issue(r.seat, 'seat_audit', v_q || ':' || r.seat,
      format('Get back to the senior bar found short in the audit of the quarter starting %s: %s.', to_char(v_q, 'DD Mon YYYY'), array_to_string(r.shortfalls, '; ')),
      'no handoff to the seat is open past its reply window, and none of its duties is failing or overdue.',
      format('not ' || v_late || $q$ and not exists (select 1 from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = %1$L)$q$, r.seat),
      p_at + interval '14 days', jsonb_build_object('quarter', v_q, 'improvement_id', r.improvement_id, 'shortfalls', r.shortfalls));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- the close loop: each open directive is re-checked on its own predicate
  for d in select * from public.ceo_directive where status = 'open' order by id loop
    v_err := null;
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false; v_err := left(sqlerrm, 300);
    end;
    if v_ok then
      update public.ceo_directive set status = 'met', closed_at = p_at,
             evidence = evidence || jsonb_build_object('closed', jsonb_build_object('checked_at', p_at, 'predicate', d.done_sql, 'result', true))
       where id = d.id;
      n_met := n_met + 1;
    elsif p_at > d.deadline and d.escalated_from is null then
      update public.ceo_directive set status = 'escalated', closed_at = p_at,
             evidence = evidence || jsonb_build_object('escalated', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err))
       where id = d.id;
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref, 'RE-ISSUED after the deadline of ' || to_char(d.deadline at time zone 'Asia/Dubai', 'DD Mon') || ' passed: ' || d.instruction,
              d.done_when, d.done_sql, p_at + (d.deadline - d.issued_at), d.id, d.evidence)
      returning id into v_new;
      insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, outcome, dedupe_key)
      values ('directive_escalation',
              format('Directive #%s to %s passed its deadline unmet; re-issued once as #%s, due %s.', d.id, d.seat, v_new,
                     to_char((p_at + (d.deadline - d.issued_at)) at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('directive_id', d.id, 'reissue_id', v_new, 'seat', d.seat, 'done_when', d.done_when, 'deadline', d.deadline, 'predicate_error', v_err),
              'done-condition false at ' || p_at, 'decided', 'ceo_directive_escalation:' || d.id)
      on conflict do nothing returning id into v_dec;
      update public.ceo_directive set evidence = evidence || jsonb_build_object('decision_log_id', v_dec) where id = d.id;
      n_esc := n_esc + 1;
    elsif p_at > d.deadline then
      v_task := public.fn_ceo_task_open(format('Directive #%s to %s missed after re-issue', d.id, d.seat),
        format(E'%s\nDone when: %s\nFirst issued as #%s. The CEO decides the next step itself; it is not re-issued again.', d.instruction, d.done_when, d.escalated_from));
      update public.ceo_directive set status = 'missed', closed_at = p_at,
             evidence = evidence || jsonb_build_object('missed', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err, 'task_id', v_task))
       where id = d.id;
      n_missed := n_missed + 1;
    end if;
  end loop;

  return jsonb_build_object('issued', n_issued, 'met', n_met, 'escalated', n_esc, 'missed', n_missed,
    'open', (select count(*) from public.ceo_directive where status = 'open'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_directive_run_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_directive_run(now()) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_experiment_propose(p_seat text, p_key text, p_hypothesis text, p_metric_key text, p_metric_definition text, p_baseline numeric, p_baseline_note text, p_target numeric, p_direction text, p_approach text, p_starts_on date, p_days integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e public.ceo_experiment; v_held bigint;
begin
  if not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    raise exception 'a hypothesis is proposed by an active seat, not %', p_seat;
  end if;
  perform public.fn_ambition_measure(p_metric_key, now() - interval '1 day', now());   -- raises on a metric nobody can measure
  select * into e from public.ceo_experiment where key = p_key for update;
  if found and e.status <> 'proposed' then
    return e.id;                                   -- decided already: a new hypothesis takes a new key
  end if;
  insert into public.ceo_experiment (key, proposed_by, hypothesis, metric_key, metric_definition, baseline, baseline_note,
                                     target, direction, approach, starts_on, days)
  values (p_key, p_seat, p_hypothesis, p_metric_key, p_metric_definition, p_baseline, p_baseline_note,
          p_target, coalesce(p_direction, 'min'), p_approach, p_starts_on, p_days)
  on conflict (key) do update set hypothesis = excluded.hypothesis, metric_key = excluded.metric_key,
       metric_definition = excluded.metric_definition, baseline = excluded.baseline, baseline_note = excluded.baseline_note,
       target = excluded.target, direction = excluded.direction, approach = excluded.approach, starts_on = excluded.starts_on,
       days = excluded.days, iteration = ceo_experiment.iteration + 1, approval_held_id = null, updated_at = now()
  returning * into e;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.experiment_approval',
    'A seat proposes an experiment against one of the plan''s unknowns. As the chief executive, judge the approach: '
      || 'is the hypothesis falsifiable, is the metric the right one and honestly measurable, are the baseline and '
      || 'target realistic against the plan, and is it safe for customers, suppliers and the founder''s rules? '
      || 'Approve it, send it back for revision, or reject it.',
    ('[{"id":"approve","meaning":"the approach is sound; run it with an owner and an end date"},'
    || '{"id":"revise","meaning":"worth testing, but the metric, target, duration or approach must change first"},'
    || '{"id":"reject","meaning":"not worth the company''s effort or not safe to run"}]')::jsonb,
    jsonb_build_object('experiment', to_jsonb(e) - 'approval', 'reading_now', public.fn_ambition_measure(e.metric_key, now() - interval '30 days', now()),
                       'company_stage', (select stage from public.ceo_company_stage_log where left_at is null order by id desc limit 1)),
    jsonb_build_object('experiment_id', e.id, 'iteration', e.iteration), 'ceo_exp_approve:' || e.id || ':' || e.iteration);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'owner_seat', 'question', 'the seat that runs it (sales_engineer, customer_support, accountant, it_engineer or marketing)'),
    jsonb_build_object('key', 'days', 'question', 'how many days it runs before a final verdict (7 to 365)'),
    jsonb_build_object('key', 'conditions', 'question', 'the conditions, or for revise the change required')));
  update public.ceo_experiment set approval_held_id = v_held where id = e.id;
  return e.id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_experiment_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e public.ceo_experiment; v_week date := date_trunc('week', (now() at time zone 'Asia/Dubai'))::date;
  v_today date := (now() at time zone 'Asia/Dubai')::date; v_from timestamptz; v_reading numeric; v_held bigint;
  n_started int := 0; n_measured int := 0; n_filed int := 0;
begin
  -- an approved experiment starts on its day
  update public.ceo_experiment set status = 'running', updated_at = now() where status = 'approved' and starts_on <= v_today;
  get diagnostics n_started = row_count;

  for e in select * from public.ceo_experiment where status = 'running' order by id loop
    v_from := (e.starts_on::timestamp at time zone 'Asia/Dubai');
    v_reading := public.fn_ambition_measure(e.metric_key, v_from, now());
    insert into public.ceo_experiment_verdict (experiment_id, week, iteration, reading, reading_from, reading_to)
    values (e.id, v_week, e.iteration, v_reading, v_from, now())
    on conflict (experiment_id, week) do update set reading = excluded.reading, reading_to = excluded.reading_to
      where ceo_experiment_verdict.decided_at is null;
    n_measured := n_measured + 1;
    if (select held_id from public.ceo_experiment_verdict where experiment_id = e.id and week = v_week) is null then
      v_held := public.fn_seat_duty_reason('ceo', 'ceo.experiment_verdict',
        'The weekly verdict on a running experiment. Read the hypothesis, its baseline and target, this week''s measured '
          || 'reading and the earlier verdicts. Keep it (it is working, or too early to judge and still sound), kill it '
          || '(the evidence refutes it or it costs more than it can return), or iterate it (change the approach and run '
          || 'again). A reading of null means the metric is not measurable yet: say whether that is expected.',
        ('[{"id":"kept","meaning":"keep running it as it is (after its end date: the hypothesis held and the change stays)"},'
        || '{"id":"killed","meaning":"stop it: the evidence refutes it or it is not worth continuing"},'
        || '{"id":"iterated","meaning":"change the approach and run the next iteration"}]')::jsonb,
        jsonb_build_object('experiment', to_jsonb(e) - 'approval', 'reading', v_reading, 'week', v_week,
                           'days_left', e.ends_on - v_today, 'past_end_date', v_today >= e.ends_on,
                           'earlier', (select coalesce(jsonb_agg(jsonb_build_object('week', week, 'reading', reading, 'decision', decision, 'fields', fields) order by week), '[]'::jsonb)
                                         from public.ceo_experiment_verdict where experiment_id = e.id and week < v_week)),
        jsonb_build_object('experiment_id', e.id, 'week', v_week), 'ceo_exp_verdict:' || e.id || ':' || v_week);
      perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
        jsonb_build_object('key', 'lesson', 'question', 'what this week teaches, in one sentence a future decision can reuse'),
        jsonb_build_object('key', 'next_step', 'question', 'for iterated: the changed approach; otherwise the next action')));
      update public.ceo_experiment_verdict set held_id = v_held where experiment_id = e.id and week = v_week;
      n_filed := n_filed + 1;
    end if;
  end loop;
  return jsonb_build_object('week', v_week, 'started', n_started, 'measured', n_measured, 'verdicts_filed', n_filed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_founder_summary(p_event text, p_detail text, p_dedupe text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'founder', p_dedupe,
    jsonb_build_object('recipient_role', 'founder', 'kind', 'refund_ceo_summary', 'level', 'high',
                       'event', left(p_event, 200), 'detail', left(p_detail, 1500), 'dedupe_key', p_dedupe));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_founder_text_forbidden()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select '(switched off|switch them|campaign|\mgate\M|go[- ]?live|invite_enabled|\mcaps?\M|ceiling|warm[- ]?up|subscription)'::text
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_improvement_close(p_id bigint, p_evidence text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.ceo_improvement;
begin
  update public.ceo_improvement set status = 'done', closed_at = now(), done_evidence = p_evidence
   where id = p_id and status in ('open', 'assigned') returning * into i;
  if not found then return; end if;
  update public.ceo_task set state = 'done', closed_at = now(), evidence = left(coalesce(evidence || E'\n', '') || p_evidence, 8000)
   where task_id = i.task_id and state in ('open', 'working', 'blocked');
  if i.handoff_id is not null and exists (select 1 from public.agent_actions where id = i.handoff_id and status = 'pending') then
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(i.handoff_id, jsonb_build_object('verified_by', 'ceo', 'improvement_id', i.id, 'evidence', p_evidence));
    perform set_config('qd.handoff_closer', '', true);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_improvement_open(p_kind text, p_ref text, p_seat text, p_proposal text, p_evidence jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_task bigint; v_hid bigint;
begin
  if p_kind in ('lesson', 'recurring_finding')
     and (select count(*) from public.ceo_improvement where seat = p_seat and status in ('open', 'assigned')) >= 20 then
    return null;   -- capped: re-proposed by the next sweep once the seat has room; nothing is closed to make room
  end if;
  insert into public.ceo_improvement (source_kind, source_ref, seat, proposal, evidence)
  values (p_kind, p_ref, p_seat, p_proposal, coalesce(p_evidence, '{}'::jsonb))
  on conflict (source_kind, source_ref) do nothing returning id into v_id;
  if v_id is null then return null; end if;   -- proposed already
  v_task := public.fn_ceo_task_open(format('Improvement #%s for %s: %s', v_id, p_seat, left(p_proposal, 200)),
                                    format(E'%s\nSource: %s %s.\nEvidence: %s', p_proposal, p_kind, p_ref, coalesce(p_evidence, '{}'::jsonb)));
  if p_seat <> 'ceo' then
    v_hid := public.fn_seat_handoff('ceo', p_seat, 'ceo.improvement', 'ceo_improvement', v_id::text,
      jsonb_build_object('improvement_id', v_id, 'task_id', v_task, 'proposal', p_proposal, 'source', p_kind, 'evidence', p_evidence));
  end if;
  update public.ceo_improvement set status = 'assigned', task_id = v_task, handoff_id = v_hid where id = v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_improvement_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n_new int := 0; n_done int := 0; c_id bigint; v bigint; v_ans timestamptz;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';

  -- a metric behind its path on 7 or more of the last 14 days: the plan for it is not working
  for r in select d.metric_key, d.owner_seat, count(*) filter (where d.status = 'miss') as misses,
                  min(d.actual) filter (where d.status = 'miss') as low, max(d.expected) as expected
             from public.target_daily_verdict d
            where d.contract_id = c_id and d.day > current_date - 14
            group by 1, 2 having count(*) filter (where d.status = 'miss') >= 7 loop
    v := public.fn_ceo_improvement_open('recurring_miss', r.metric_key || ':' || to_char(current_date, 'YYYY-MM'), r.owner_seat,
      format('%s has been behind its path on %s of the last 14 days. Change how the seat moves it, not the target: name the step that is not converting and fix that step.', r.metric_key, r.misses),
      jsonb_build_object('metric', r.metric_key, 'misses_14d', r.misses, 'lowest_actual', r.low, 'expected', r.expected));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- a lesson a seat wrote down in the last 30 days becomes ONE change to its routine: keyed on the
  -- lesson, not on the case, so the tenth case with the same lesson finds the first improvement.
  for r in select m.seat, m.case_kind, m.lessons[1] as lesson, max(m.id) as last_case, count(*) as cases
             from public.seat_case_memory m
            where cardinality(m.lessons) > 0 and coalesce(m.updated_at, m.opened_at) > now() - interval '30 days'
              and exists (select 1 from public.org_role o where o.role_id = m.seat and o.status = 'active')
            group by 1, 2, 3 loop
    v := public.fn_ceo_improvement_open('lesson', 'lesson:' || r.seat || ':' || md5(r.case_kind || '|' || r.lesson), r.seat,
      format('Make this lesson part of the routine, so the same case does not come back: %s', r.lesson),
      jsonb_build_object('case_memory_id', r.last_case, 'case_kind', r.case_kind, 'lesson', r.lesson, 'cases', r.cases));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- an open finding seen three or more times is a process fault, not a one-off
  for r in select f.issue_key, f.title, f.seen_count, coalesce(nullif(f.evidence->>'owner_seat', ''), f.raised_by) as seat
             from public.it_engineer_finding f where f.closed_at is null and f.seen_count >= 3 loop
    if exists (select 1 from public.org_role o where o.role_id = r.seat and o.status = 'active') then
      v := public.fn_ceo_improvement_open('recurring_finding', r.issue_key, r.seat,
        format('Remove the cause of a finding seen %s times: %s', r.seen_count, left(r.title, 300)),
        jsonb_build_object('issue_key', r.issue_key, 'seen_count', r.seen_count));
      n_new := n_new + (v is not null)::int;
    end if;
  end loop;

  -- tracked to done: the CEO is the originator, re-verifies, and is the one who closes
  for r in select i.*, coalesce(i.evidence->>'lesson',
                                (select m.lessons[1] from public.seat_case_memory m where m.id = (i.evidence->>'case_memory_id')::bigint)) as lesson
             from public.ceo_improvement i where i.status in ('open', 'assigned') loop
    if r.source_kind in ('recurring_miss', 'month_miss')
       and (select count(*) filter (where d.status in ('on_track', 'within_tolerance')) = 7 and count(*) = 7
              from public.target_daily_verdict d where d.contract_id = c_id and d.metric_key = r.evidence->>'metric'
               and d.day > current_date - 7 and d.day > r.created_at::date) then
      perform public.fn_ceo_improvement_close(r.id, format('%s back on its path for 7 days running (%s).', r.evidence->>'metric', current_date));
      n_done := n_done + 1;
    elsif r.source_kind = 'recurring_finding'
       and exists (select 1 from public.it_engineer_finding f where f.issue_key = r.source_ref and f.closed_at is not null) then
      perform public.fn_ceo_improvement_close(r.id, format('Finding %s closed.', r.source_ref));
      n_done := n_done + 1;
    elsif r.source_kind = 'lesson' and r.lesson is not null then
      -- answered = the seat replied on the handoff (or there was no handoff: the CEO's own lesson)
      select coalesce((a.detail->>'replied_at')::timestamptz, a.decided_at) into v_ans
        from public.agent_actions a where a.id = r.handoff_id;
      if r.handoff_id is null then v_ans := r.created_at; end if;
      if v_ans is not null
         and not exists (select 1 from public.seat_case_memory m
                          where m.seat = r.seat and m.case_kind = r.evidence->>'case_kind' and m.lessons[1] = r.lesson
                            and (not coalesce(m.finalised, false) or m.opened_at > v_ans)) then
        perform public.fn_ceo_improvement_close(r.id, format('Re-verified by the CEO: every %s case of %s carrying this lesson is finalised and none has opened since the answer (%s).',
                                                             r.evidence->>'case_kind', r.seat, v_ans));
        n_done := n_done + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('proposed', n_new, 'closed', n_done,
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_incident_advance(p_incident_id bigint, p_depth integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.refund_incident; v jsonb; v_paused boolean; v_what text; v_fixed text; t public.transactions; v_new int;
begin
  select * into i from public.refund_incident where id = p_incident_id for update;
  if not found or not i.sealed or i.status = 'fixed' then return jsonb_build_object('moved', false); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
               and a.detail->>'incident_id' = p_incident_id::text and a.status = 'pending') then
    return jsonb_build_object('moved', false, 'waiting', true);
  end if;
  select * into t from public.transactions where id = i.transaction_id;
  v := public.fn_ceo_refund_checklist(i.transaction_id, 'verify', true);

  if not (v->>'ok')::boolean and p_depth < 1 then
    -- A fix can surface the next thing to fix (a top-up changes what the supplier owes). One more
    -- round, bounded: each fix is applied once per incident.
    v_new := public.fn_ceo_incident_fix_round(i.id, v);
    if v_new > 0 then return public.fn_ceo_incident_advance(i.id, p_depth + 1); end if;
  end if;

  select * into i from public.refund_incident where id = p_incident_id;
  v_what := 'Refund mismatch on reveal #' || left(i.transaction_id::text, 8) || ' (' || array_to_string(i.kinds, ', ')
         || '): approved AED ' || coalesce(i.approved_aed::text, '?') || ', refunded AED ' || coalesce(i.actual_aed::text, '?') || '.';
  v_fixed := (select string_agg(f->>'fix', '; ') from jsonb_array_elements(i.fixes) f);

  if (v->>'ok')::boolean then
    update public.refund_incident set status = 'fixed', closed_at = now() where id = i.id;
    if not exists (select 1 from public.refund_incident x where x.status in ('open', 'paused') and x.id <> i.id) then
      update public.decision_policy set value = 'false'::jsonb, updated_at = now() where key = 'refunds_and_supplier_charges_paused';
    end if;
    v_paused := public.fn_refunds_paused();
    perform public.fn_ceo_founder_summary('Refund mismatch fixed: reveal #' || left(i.transaction_id::text, 8),
      v_what || ' Fixed: ' || coalesce(v_fixed, 'nothing needed') || '. Every check passes again. Refunds and supplier charges are '
        || case when v_paused then 'still PAUSED by another open incident' else 'running again' end || '.',
      'refund_incident:' || i.id || ':fixed');
    return jsonb_build_object('moved', true, 'status', 'fixed', 'paused', v_paused);
  end if;

  update public.refund_incident set status = 'paused' where id = i.id;
  -- A refund the retry could not settle: the customer is told it is in progress, nothing more.
  if exists (select 1 from jsonb_array_elements(v->'failed') f where f->>'kind' = 'stripe_failed_or_pending')
     and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                   and a.detail->>'incident_id' = i.id::text and a.detail->>'fix' = 'retry_refund' and a.status in ('done', 'failed')) then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.in_progress', 'transactions', t.id::text,
      jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id,
                         'amount_aed', coalesce(t.total_charged, t.reveal_fee)));
  end if;
  perform public.fn_ceo_founder_summary('Refund mismatch still open: reveal #' || left(i.transaction_id::text, 8),
    v_what || ' Tried: ' || coalesce(v_fixed, 'nothing automatic') || '. Still failing: '
      || (select string_agg((f->>'item') || ' (' || coalesce(f->>'reason', '') || ')', '; ') from jsonb_array_elements(v->'failed') f)
      || '. Refunds and supplier charges stay PAUSED.',
    'refund_incident:' || i.id || ':paused');
  return jsonb_build_object('moved', true, 'status', 'paused', 'failed', v->'failed');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_incident_fix_round(p_incident_id bigint, p_verify jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  i public.refund_incident; t public.transactions; v_kinds text[]; v_kind text; v_fix text; v_subject text; v_payload jsonb;
  v_money jsonb; v_app numeric; v_act numeric; du public.supplier_dues; y record; v_new int := 0; v_fixes jsonb := '[]'::jsonb;
begin
  select * into i from public.refund_incident where id = p_incident_id;
  select * into t from public.transactions where id = i.transaction_id;
  select x->'evidence' into v_money from jsonb_array_elements(p_verify->'items') x where x->>'item' = 'money_moved_as_approved';
  v_app := (v_money->>'approved_aed')::numeric; v_act := (v_money->>'actual_aed')::numeric;
  select coalesce(array_agg(distinct x->>'kind'), '{}') into v_kinds from jsonb_array_elements(p_verify->'failed') x;
  -- A refund that never settled is retried, never also topped up; a duplicate is cancelled first, and
  -- only booked as a loss if Stripe will not cancel it.
  if 'stripe_failed_or_pending' = any(v_kinds) then v_kinds := array_remove(v_kinds, 'under_refund'); end if;
  if 'duplicate_refund' = any(v_kinds) then v_kinds := array_remove(v_kinds, 'over_refund'); end if;

  foreach v_kind in array v_kinds loop
    v_fix := case v_kind when 'under_refund' then 'refund_difference' when 'over_refund' then 'book_over_refund_loss'
                         when 'stripe_failed_or_pending' then 'retry_refund' when 'duplicate_refund' then 'cancel_duplicate'
                         when 'charge_missing' then 'raise_charge' when 'wrong_charge_unsent' then 'reissue_charge'
                         when 'wrong_charge_sent' then 'reissue_charge' end;
    if v_fix is not null then
      v_subject := p_incident_id || ':' || v_fix || case when v_fix = 'reissue_charge' then ':' || v_kind else '' end;
      continue when exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'accountant'
                              and a.target_id = 'incident.fix:' || v_subject);
      v_payload := jsonb_build_object('incident_id', p_incident_id, 'transaction_id', t.id, 'refund_id', i.refund_id, 'fix', v_fix,
                                      'payment_ref', t.payment_ref, 'sent', v_kind = 'wrong_charge_sent');
      if v_fix = 'refund_difference' then v_payload := v_payload || jsonb_build_object('amount_fils', round((v_app - v_act) * 100)::bigint); end if;
      if v_fix = 'book_over_refund_loss' then v_payload := v_payload || jsonb_build_object('amount_aed', v_act - v_app); end if;
      if v_fix = 'cancel_duplicate' then
        v_payload := v_payload || jsonb_build_object('excess_aed', v_act - v_app,
          'refund_ids', (select jsonb_agg(x.stripe_refund_id order by x.id) from public.refunds x
                          where x.status = 'succeeded' and (x.transaction_id = t.id or x.stripe_payment_intent = t.payment_ref)));
      end if;
      perform public.fn_seat_handoff('ceo', 'accountant', 'incident.fix', 'refund_incident', v_subject, v_payload);
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', v_fix);
      v_new := v_new + 1;

    elsif v_kind = 'missed_handoff' then
      -- THE CEO RE-TRIGGERS WHAT DID NOT HAPPEN. A sales-engineer handoff that finished without a
      -- delivery behind it is superseded and sent again; a failed one never blocks a new one.
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      for y in
        select a.id from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.status = 'done'
           and ((a.target_id = 'refund.paid:' || t.id
                 and not exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.agent = 'customer_support'
                                   and b.target_id = 'delivery.request:refund_issued:' || t.id and b.status = 'done'
                                   and coalesce((b.evidence->>'delivered')::boolean, false)))
             or (du.id is not null and a.target_id = 'nonresponse.charge_raised:' || du.id
                 and not exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.agent = 'customer_support'
                                   and b.target_id = 'delivery.request:nonresponse_charge:' || du.id and b.status = 'done'
                                   and coalesce((b.evidence->>'delivered')::boolean, false))))
      loop
        update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', p_incident_id) where id = y.id;
        -- its delivery request, if any, goes with it, so the new one is not deduplicated into the old
        update public.agent_actions b set status = 'failed', detail = b.detail || jsonb_build_object('superseded_by_incident', p_incident_id)
         where b.kind = 'handoff' and b.agent = 'customer_support' and b.status = 'done'
           and b.target_id in ('delivery.request:refund_issued:' || t.id, 'delivery.request:nonresponse_charge:' || coalesce(du.id::text, '-'))
           and not coalesce((b.evidence->>'delivered')::boolean, false);
        v_new := v_new + 1;
      end loop;
      if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                       and a.target_id = 'refund.paid:' || t.id and a.status <> 'failed') then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', t.id::text,
          jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id, 'inquiry_id', t.inquiry_id,
                             'quote_id', t.quote_id, 'revealed_at', t.revealed_at, 'amount_aed', coalesce(round(t.refund_amount_aed, 2), v_act)));
        v_new := v_new + 1;
      end if;
      if du.id is not null
         and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                           and a.target_id = 'nonresponse.charge_raised:' || du.id and a.status <> 'failed') then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', du.id::text,
          public.fn_accountant_nonresponse_charge(t.id, null)
            || jsonb_build_object('due_id', du.id, 'transaction_id', t.id, 'supplier_id', t.supplier_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id));
        v_new := v_new + 1;
      end if;
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', 'retriggered the handoffs that had no delivery behind them');
    else
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', 'none automatic: stays paused for the CEO');
    end if;
  end loop;

  update public.refund_incident
     set fixes = fixes || v_fixes, kinds = (select array_agg(distinct k) from unnest(kinds || v_kinds) k)
   where id = p_incident_id;
  return v_new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_it_escalation_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; h public.agent_actions; v_demo boolean; v_detail text; v_d bigint; v_acc jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id and source_agent = 'it_engineer' for update;
  if not found or r.status <> 'sent' then
    return jsonb_build_object('ok', false, 'reason', 'no open IT report ' || p_report_id);
  end if;
  select * into h from public.agent_actions where id = (r.verified_evidence->>'handoff_id')::bigint;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'report ' || p_report_id || ' names no handoff');
  end if;
  v_demo := coalesce((h.detail->>'demo')::boolean, false);
  -- A finding its duty marks no_founder_email (a moderate or low dependency advisory) stays with its
  -- owning seat: the founder is emailed for a new bug only when it is high or critical.
  if coalesce((h.detail->'finding_evidence'->>'no_founder_email')::boolean, false) then
    return jsonb_build_object('ok', true, 'report_id', r.id, 'handoff_id', h.id, 'founder_delivery_handoff', null,
      'accepted', public.fn_ceo_accept_support_report(r.id,
        'ceo: below high severity, so the ' || h.agent || ' keeps it and the founder is not emailed'));
  end if;
  v_detail := 'What is wrong: ' || coalesce(h.detail->>'title', h.detail->>'issue_key') || E'.\n'
    || 'Where: ' || coalesce(h.detail->>'where_it_is', h.detail->>'subject', 'not recorded') || E'.\n'
    || 'Since: ' || to_char((h.detail->>'occurrence_started_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || E' (Dubai).\n'
    || 'What was tried: the ' || h.agent || ' was asked at '
    || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' and '
    || case when h.detail ? 'replied_at' then 'replied: ' || coalesce(h.evidence->>'reply', 'no words recorded')
            else 'did not reply' end || E'\n\n'
    || 'Nothing inside the company fixed it, so it needs a code or configuration change. It stays tracked '
    || 'until the IT engineer confirms it is gone. Reference: ' || (h.detail->>'issue_key') || '.';

  if not v_demo then
    v_d := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'support_ceo_report', r.id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
                         'event', 'New problem the IT engineer could not fix: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 120),
                         'detail', v_detail, 'dedupe_key', 'it_new_bug:' || (h.detail->>'issue_key')));
  end if;
  v_acc := public.fn_ceo_accept_support_report(r.id,
    'ceo: new bug, no seat could fix it — ' || case when v_demo then 'ZZ DEMO case, the founder is not emailed'
                                                   else 'founder told through customer_support handoff ' || v_d end);
  -- Duty 18: every new bug gets its incident record now; duty 17 completes it before the loop closes.
  perform public.fn_it_incident_open(h.id);
  return jsonb_build_object('ok', true, 'report_id', r.id, 'handoff_id', h.id, 'demo', v_demo,
                            'founder_delivery_handoff', v_d, 'accepted', v_acc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_it_reports_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; n_ack int := 0; n_dec int := 0;
begin
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent' order by id loop
    if r.severity = 'routine' then
      perform public.fn_ceo_accept_support_report(r.id,
        'ceo: read the IT line — ' || coalesce(r.verified_evidence->>'open_loops', '0') || ' open loop(s), each with a named owner');
      n_ack := n_ack + 1;
    elsif r.idempotency_key like 'it_loop:%' then
      perform public.fn_ceo_it_escalation_decide(r.id);
      n_dec := n_dec + 1;
    end if;
  end loop;
  return jsonb_build_object('acknowledged', n_ack, 'decided', n_dec);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_judgement_accept(p_plan_id bigint, p_output jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  p public.ceo_plan; v_why text; x jsonb; v_keys text[] := array['invitations_delivered','registrations_submitted','registrations_verified',
    'stranded_submissions','inquiries_posted','quote_coverage_pct','reveals_paid','fee_aed','bounce_pct_7d'];
  v_hid bigint; v_ids jsonb := '[]';
begin
  select * into p from public.ceo_plan where id = p_plan_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no ceo_plan '||p_plan_id); end if;

  v_why := case
    when p_error is not null then 'the call failed: '||left(p_error, 300)
    when p_output is null or jsonb_typeof(p_output) <> 'object' then 'no JSON object came back'
    when not exists (select 1 from jsonb_array_elements(p.decision->'options') o where o->>'id' = p_output->>'option_id') then 'option_id is not one of the options'
    when length(coalesce(p_output->>'reasoning','')) not between 40 and 2000 then 'reasoning missing or out of bounds'
    -- every test is coalesced: a missing field compares NULL, and a NULL WHEN is a pass
    when not coalesce(p_output->'prediction'->>'measure_key' = any (v_keys), false) then 'prediction.measure_key is not a funnel measure'
    when coalesce(p_output->'prediction'->>'direction','') not in ('min','max') then 'prediction.direction is not min or max'
    when coalesce(p_output->'prediction'->>'value','') !~ '^[0-9]+(\.[0-9]+)?$' then 'prediction.value is not a number >= 0'
    -- A cast is only reached once its format is proven: OR gives no evaluation-order guarantee, CASE does.
    when coalesce(p_output->'prediction'->>'by_date','') !~ '^\d{4}-\d{2}-\d{2}$' then 'prediction.by_date is not a date'
    when (p_output->'prediction'->>'by_date')::date not between p.plan_date + 1 and p.plan_date + 30 then 'prediction.by_date is not 1-30 days ahead'
    when jsonb_typeof(coalesce(p_output->'directives','[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_output->'directives','[]'::jsonb)) > 3 then 'directives is not an array of at most 3'
    when exists (select 1 from jsonb_array_elements(coalesce(p_output->'directives','[]'::jsonb)) dd
                  where jsonb_typeof(dd) <> 'object'
                     or not coalesce(dd->>'seat' = any (array['sales_engineer','customer_support','accountant','it_engineer','marketing']), false)
                     or not exists (select 1 from public.org_role r where r.role_id = dd->>'seat' and r.status = 'active')
                     or not coalesce(dd->>'measure_key' = any (v_keys), false) or coalesce(dd->>'direction','') not in ('min','max')
                     or coalesce(dd->>'target','') !~ '^[0-9]+(\.[0-9]+)?$'
                     or case when coalesce(dd->>'due_days','') ~ '^[0-9]{1,3}$' then (dd->>'due_days')::int not between 1 and 14 else true end
                     or length(coalesce(dd->>'instruction','')) > 400) then 'a directive is outside the contract'
    when length(coalesce(p_output->>'founder_decision','')) > 300 then 'founder_decision is longer than 300 characters'
    -- instructions 636/639: the campaign gate, its volume and subscriptions never reach the founder, and a
    -- seat that is not in org_agents is never named to him
    when coalesce(p_output->>'founder_decision','') ~* public.fn_ceo_founder_text_forbidden() then 'founder_decision raises a subject reserved from the founder (campaign, invitations, caps, subscriptions, a seat that does not exist)'
  end;

  if v_why is not null then
    update public.ceo_plan set judgement = judgement || jsonb_build_object('answered_at', now(), 'accepted', false, 'rejected_because', v_why, 'output', p_output)
     where id = p.id;
    return jsonb_build_object('ok', false, 'plan_id', p.id, 'plan_c_stands', true, 'error', 'model answer rejected: '||v_why);
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_output->'directives','[]'::jsonb)) loop
    v_hid := public.fn_seat_handoff('ceo', x->>'seat', 'ceo.directive', 'ceo_plan',
      p.plan_date::text||':model:'||(x->>'seat')||':'||(x->>'measure_key'),
      jsonb_build_object('stage', coalesce(x->>'stage', p.stage), 'measure_key', x->>'measure_key', 'direction', x->>'direction',
                         'target', (x->>'target')::numeric, 'due_days', (x->>'due_days')::int, 'instruction', x->>'instruction',
                         'due_at', now() + make_interval(days => (x->>'due_days')::int), 'plan_id', p.id,
                         'prediction', p_output->'prediction', 'decided_by', 'model', 'level', p.decision->'level'));
    v_ids := v_ids || to_jsonb(v_hid);
  end loop;

  perform public.fn_ceo_plan_log('binding_constraint', 'judgement:plan:'||p.id,
    format('Model judgement on %s: %s. %s', p.stage, p_output->>'option_id', left(p_output->>'reasoning', 1500)),
    jsonb_build_object('plan_id', p.id, 'contract', (public.fn_ceo_judgement_contract())->>'version', 'output', p_output,
                       'plan_c_choice', p.decision->>'plan_c_choice', 'directive_handoffs', v_ids));
  update public.ceo_plan
     set decided_by = 'model',
         founder_line = coalesce(founder_line, nullif(p_output->>'founder_decision','')),
         judgement = judgement || jsonb_build_object('answered_at', now(), 'accepted', true, 'output', p_output, 'directive_handoffs', v_ids)
   where id = p.id;
  return jsonb_build_object('ok', true, 'plan_id', p.id, 'option_id', p_output->>'option_id', 'directive_handoffs', v_ids);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_judgement_contract()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'version', 'ceo-judgement-v1',
    'system', 'You are the chief executive of QuotesDone, a UAE construction-procurement marketplace. Customers post requests; verified suppliers quote; the customer sees a free comparison of the best three technical quotes plus every other quote, and pays a 3% reveal fee (plus card processing) to reveal the supplier they choose. Suppliers pay no commission. The company goal is AED 1,000,000 of reveal-fee revenue by 31 August 2027. You direct five seats: sales_engineer, customer_support, accountant, it_engineer, marketing (marketing owns the demand stage: buyers posting requests). input.marketing is the marketing seat''s latest daily report: read it as the picture of that stage. Decide ONLY from the numbers in the input; never invent one. You may not move money, change a supplier or customer record, message a customer, a supplier or the founder, or touch any founder switch. The supplier invitation campaign (its go, its switches, its daily volume and ramp), subscriptions and seats that do not exist yet are not yours to propose or mention: when a stage is held by them, choose hold_reserved and leave founder_decision null. founder_decision is only for a stage a seat can move that has not moved in 14 days despite directives. Choose exactly one option id from input.options. Justify the choice briefly in the reasoning field, citing the input numbers you relied on. Make one measurable prediction. Reply with a single JSON object matching output_schema and nothing else.',
    'input_fields', jsonb_build_array('date','goal','month_target','funnel','attainment','constraint','open_directives','options','plan_c_choice','marketing'),
    'output_schema', jsonb_build_object(
      'option_id', 'one of input.options[].id',
      'reasoning', 'string, 40-2000 characters, cites input numbers',
      'prediction', jsonb_build_object('measure_key','one of the measure keys in input.funnel','direction','min|max','value','number >= 0','by_date','YYYY-MM-DD, 1-30 days after input.date'),
      'directives', 'array of at most 3: {seat: sales_engineer|customer_support|accountant|it_engineer|marketing, stage, measure_key, direction, target >= 0, due_days 1-14, instruction <= 400 characters}',
      'founder_decision', 'null, or <= 300 characters naming the one decision only the founder can take'),
    'plan_c', 'If the slot is off, the call fails, or the answer fails validation, the coded decision already taken stands and the rejection is recorded on the plan.')
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_judgement_counterparts(p_plan_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(string_agg(distinct l.model_used, ',' order by l.model_used), 'deterministic')
    from public.agent_actions a
    join public.ai_cost_log l
      on l.seat = a.agent and l.ok and coalesce(l.model_used, 'none') not in ('none', '')
     and l.occurred_at >= a.created_at
   where a.kind = 'handoff' and a.detail->>'type' = 'ceo.directive' and a.status = 'pending'
     and exists (select 1 from public.ceo_plan p where p.id = p_plan_id);
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_judgement_request(p_plan_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.ceo_plan; c jsonb := public.fn_ceo_judgement_contract();
begin
  select * into p from public.ceo_plan where id = p_plan_id;
  if not found then return null; end if;
  return jsonb_build_object('contract', c->>'version', 'system', c->>'system', 'output_schema', c->'output_schema',
    'input', jsonb_build_object(
      'date', p.plan_date, 'goal', 'AED 1,000,000 cumulative reveal fees by 2027-08-31',
      'month_target', p.month_target, 'funnel', p.funnel - 'gates' || jsonb_build_object('founder_switches', p.funnel->'gates'),
      'attainment', p.decision->'attainment',
      'constraint', jsonb_build_object('stage', p.stage, 'label', p.decision->>'label', 'lever', p.decision->>'lever',
                                       'since', p.constraint_since, 'days', p.decision->'days_on_constraint', 'stalled', p.decision->'stalled'),
      'open_directives', (select coalesce(jsonb_agg(jsonb_build_object('seat', a.agent, 'stage', a.detail->>'stage', 'measure_key', a.detail->>'measure_key',
                                   'target', a.detail->'target', 'due_at', a.detail->>'due_at', 'reply', a.evidence)), '[]'::jsonb)
                            from public.agent_actions a where a.kind='handoff' and a.detail->>'type'='ceo.directive' and a.status='pending'),
      'options', p.decision->'options', 'plan_c_choice', p.decision->>'plan_c_choice',
      -- the marketing report the plan read when it was made (fn_ceo_plan_tick), 22 Sep 2026 (instruction 721)
      'marketing', p.funnel->'marketing_report'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_knowledge_search(p_query text, p_limit integer DEFAULT 8, p_kind text DEFAULT NULL::text, p_domain text DEFAULT NULL::text, p_embedding vector DEFAULT NULL::vector)
 RETURNS TABLE(record_id text, record_version text, record_kind text, title text, domain text, body text, body_sha256 text, source_ids text[], source_path text, review_status text, authority_effect text, contains_synthetic_example boolean, requires_current_verification boolean, relevance real, matched_how text, warning text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_embedding is null then return; end if;
  return query
  select k.record_id, k.record_version, k.record_kind, k.title, k.domain, k.body, k.body_sha256, k.source_ids, k.source_path,
         k.review_status, k.authority_effect, k.contains_synthetic_example, k.requires_current_verification,
         (1 - (k.embedding_gte <=> p_embedding))::real as relevance, 'meaning'::text as matched_how,
         'Advisory only. authority_effect=none: this may not approve an action, change a target or '
         || 'become policy. review_status=' || k.review_status || '. '
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- it is authored, not QuotesDone experience. ' else '' end
         || case when k.requires_current_verification
                 then 'REQUIRES CURRENT VERIFICATION against an authoritative company source. ' else '' end
         || 'Current company facts come from the application, never from this record.' as warning
    from public.ceo_knowledge k
   where k.runtime_index_eligible and k.embedding_gte is not null
     and (p_kind is null or k.record_kind = p_kind)
     and (p_domain is null or k.domain = p_domain)
     and 1 - (k.embedding_gte <=> p_embedding) >= 0.84
   order by k.embedding_gte <=> p_embedding, k.record_id
   limit greatest(1, least(coalesce(p_limit, 8), 50));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_knowledge_search_vector()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.body,'')), 'C');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_launch_readiness(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_week date := date_trunc('week', p_at at time zone 'Asia/Dubai')::date;
  v_total int; v_ready int; v_gaps jsonb; v_measured timestamptz; v_verdict text; v_decision text; v_decide boolean; v_hid bigint;
begin
  select count(*), count(*) filter (where g.matchable >= g.target), max(g.measured_at)
    into v_total, v_ready, v_measured
    from public.taxonomy_trade t left join public.supply_gap g on g.trade = t.code and g.emirate = 'UAE'
   where t.active;
  select coalesce(jsonb_agg(jsonb_build_object('trade', x.code, 'label', x.label, 'matchable', x.matchable, 'target', x.target)
                            order by x.short desc, x.code), '[]'::jsonb)
    into v_gaps
    from (select t.code, t.label, coalesce(g.matchable, 0) as matchable, g.target, coalesce(g.target, 0) - coalesce(g.matchable, 0) as short
            from public.taxonomy_trade t left join public.supply_gap g on g.trade = t.code and g.emirate = 'UAE'
           where t.active and (g.trade is null or g.matchable < g.target)
           order by short desc, t.code limit 10) x;
  v_verdict := case when v_total = 0 or v_measured is null or v_measured < p_at - interval '8 days' then 'not_measurable'
                    when v_ready = v_total then 'ready' else 'not_ready' end;
  -- Every week from 1 Dec 2026 to 31 Jan 2027 (the last month before January, and January itself); after that, the
  -- first run of each quarter decides, whatever weekday the weekly duty happens to run on (decided_on, not the week).
  -- Before December nothing is decided: October to December is supplier registration by the founder's plan.
  v_decide := (v_day >= date '2026-12-01' and v_day < date '2027-02-01')
              or (v_day >= date '2027-02-01'
                  and not exists (select 1 from public.ceo_launch_gate g where g.decided_on >= date_trunc('quarter', v_day)::date));
  v_decision := case when not v_decide then null when v_verdict = 'ready' then 'january_holds' else 'launch_waits' end;

  insert into public.ceo_launch_gate (week, trades_total, trades_ready, coverage_pct, widest_gaps, measured_at, verdict, decision, decided_on)
  values (v_week, v_total, v_ready, case when v_total > 0 then round(100.0 * v_ready / v_total, 1) else 0 end, v_gaps, v_measured, v_verdict, v_decision,
          case when v_decision is not null then v_day end)
  on conflict (week) do update set trades_total = excluded.trades_total, trades_ready = excluded.trades_ready,
    coverage_pct = excluded.coverage_pct, widest_gaps = excluded.widest_gaps, measured_at = excluded.measured_at,
    verdict = excluded.verdict,
    -- a run that takes no decision never erases one already taken this week
    decision = coalesce(excluded.decision, ceo_launch_gate.decision),
    decided_on = coalesce(excluded.decided_on, ceo_launch_gate.decided_on);

  -- the founder is told a decision once: when it is first taken, and when it changes
  if v_decision is not null and v_decision is distinct from
       (select g.decision from public.ceo_launch_gate g where g.week < v_week and g.decision is not null order by g.week desc limit 1)
     and (select founder_notice from public.ceo_launch_gate where week = v_week) is null then
    v_hid := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_launch_gate', v_week::text,
      jsonb_build_object('recipient_role', 'founder', 'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_launch_gate:' || v_week,
        'event', case v_decision when 'january_holds' then 'CEO: the customer launch in January 2027 holds'
                                 else 'CEO: the customer launch waits for supply' end,
        'detail', format('The supplier base can quote %s of %s trades (%s%%) at the level where requests open to customers. ', v_ready, v_total,
                         case when v_total > 0 then round(100.0 * v_ready / v_total, 1) else 0 end)
          || case v_decision when 'january_holds' then 'Every trade is covered, so January holds on supply.'
             else 'Customers launch only when every trade is covered. Widest gaps: '
                  || coalesce((select string_agg(format('%s %s/%s', e->>'label', e->>'matchable', e->>'target'), ', ')
                                 from jsonb_array_elements(v_gaps) e), 'none measured') || '.' end
          || ' This is the supply gate only; the product is proven in the sandbox before any launch.'));
    update public.ceo_launch_gate set founder_notice = v_hid where week = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'trades_total', v_total, 'trades_ready', v_ready, 'verdict', v_verdict,
                            'decision', v_decision, 'founder_notice', v_hid);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_launch_readiness_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_launch_readiness(now()) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_management_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := public.fn_ceo_review_week(); v_facts jsonb; v_held bigint;
begin
  if (select held_id from public.ceo_review where kind = 'management_review' and period = v_week) is not null then
    return jsonb_build_object('week', v_week, 'already_filed', true);
  end if;
  select jsonb_build_object(
    'seats', (select jsonb_object_agg(r.role_id, jsonb_build_object(
        'duties', (select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_result', d.last_result)), '[]'::jsonb)
                     from public.seat_duty d where d.owner_seat = r.role_id),
        'open_findings', (select count(*) from public.it_engineer_finding f where f.closed_at is null
                            and coalesce(f.evidence->>'owner_seat', f.raised_by) = r.role_id),
        'reasoning_waiting', (select count(*) from public.reasoning_held_question h where h.seat = r.role_id and h.status = 'held'),
        'handoffs_pending', (select count(*) from public.agent_actions a where a.agent = r.role_id and a.kind = 'handoff' and a.status = 'pending'),
        -- the seat reports against its own year-one targets and its month directive
        'targets', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(public.fn_ceo_year_plan_status(now())->'metrics') x
                     where x->>'owner_seat' = r.role_id),
        'month_directive', (select jsonb_build_object('actions', d.actions, 'targets', d.targets, 'handoff_id', d.handoff_id, 'status', d.status)
                              from public.ceo_seat_directive d where d.seat = r.role_id and d.month = date_trunc('month', now() at time zone 'Asia/Dubai')::date),
        'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = r.role_id and i.status in ('open', 'assigned'))))
      from public.org_role r where r.status = 'active'),
    'duties_unhealthy', public.fn_seat_duty_health(),
    'week_revenue_aed', (select coalesce(sum(reveal_fee), 0) from public.transactions where fee_status in ('paid', 'collected', 'succeeded') and revealed_at > now() - interval '7 days'),
    'requests_7d', (select count(*) from public.inquiries where created_at > now() - interval '7 days'),
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'suppliers_approved', (select count(*) from public.leads where approval_status = 'approved' and not coalesce(is_demo, false)),
    'forecast', (select facts from public.ceo_review where kind = 'target_forecast' and period = v_week),
    'last_review', (select jsonb_build_object('week', period, 'verdict', decision, 'fields', fields) from public.ceo_review
                     where kind = 'management_review' and period < v_week and decision is not null order by period desc limit 1))
  into v_facts;
  insert into public.ceo_review (kind, period, facts) values ('management_review', v_week, v_facts)
  on conflict (kind, period) do update set facts = excluded.facts;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.management_review',
    'The weekly management review. Read each seat''s week — its duties, failures, open findings, what waits in its '
      || 'reasoning queue, and its own targets and month directive on the founder''s year-one path — against last week''s review. Give the verdict and name the one '
      || 'binding constraint.',
    ('[{"id":"on_track","meaning":"the company is on its plan this week"},'
    || '{"id":"at_risk","meaning":"the plan holds but something material is slipping"},'
    || '{"id":"off_track","meaning":"the plan is not working and must change"}]')::jsonb,
    v_facts, jsonb_build_object('kind', 'management_review', 'period', v_week), 'ceo_mreview:' || v_week);
  -- ONE VERDICT LINE (24 Sep 2026, it_engineer): the per-seat week is the SQL facts above (duties, failures,
  -- findings, queue, targets, directive); the model gives only the verdict and the one binding constraint, at
  -- normal stakes, so the review is one think() call. The five per-seat direction fields it wrote before are gone.
  update public.reasoning_held_question
     set request = jsonb_set(request || '{"stakes":"normal"}'::jsonb, '{decision,fields}', jsonb_build_array(
           jsonb_build_object('key', 'binding_constraint', 'question', 'the one constraint that most limits progress this week')))
   where id = v_held;
  update public.ceo_review set held_id = v_held where kind = 'management_review' and period = v_week;
  return jsonb_build_object('week', v_week, 'filed', v_held);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_marketing_plan_watch(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cal jsonb := public.fn_marketing_plan_calendar(p_at); v_month date; v_deadline date; v_today date;
  p public.marketing_month_plan; v_late boolean; v_stalled boolean := false; v_id bigint; r record; n_closed int := 0;
  v_covered boolean;
begin
  v_month := (cal->>'plan_month')::date; v_deadline := (cal->>'deadline')::date; v_today := (cal->>'today')::date;
  select * into p from public.marketing_month_plan where month = v_month;
  v_covered := public.fn_marketing_month_covered_by_approved_calendar(v_month);
  v_late := v_today > v_deadline and (p.month is null or p.status = 'draft') and not v_covered;

  if v_late then
    v_id := public.fn_ceo_improvement_open('marketing_plan_late', v_month::text, 'marketing',
      format('The marketing plan for %s was due to the CEO by %s (a week before month end, instruction 866) and has not arrived (%s). '
             || 'Send it today with its evidence; the CEO reviews it on the review machine and the month does not start unplanned.',
             to_char(v_month, 'FMMonth YYYY'), to_char(v_deadline, 'DD Mon'), coalesce('status ' || p.status, 'no plan row')),
      jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', p.status, 'due_on', v_today + 1));
  end if;

  -- closed the day the plan reaches the CEO, or when an approved calendar already covers the month
  for r in select i.id, (i.evidence->>'plan_month')::date as m from public.ceo_improvement i
            where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    if exists (select 1 from public.marketing_month_plan mp where mp.month = r.m and mp.status <> 'draft') then
      perform public.fn_ceo_improvement_close(r.id, format('The %s plan reached the CEO (%s).', to_char(r.m, 'FMMonth YYYY'),
        (select status from public.marketing_month_plan where month = r.m)));
      n_closed := n_closed + 1;
    elsif public.fn_marketing_month_covered_by_approved_calendar(r.m) then
      perform public.fn_ceo_improvement_close(r.id, format('%s is already planned: the founder approved campaign %s, which schedules posts in that month; no second plan is drafted.',
        to_char(r.m, 'FMMonth YYYY'),
        (select string_agg(distinct c.campaign_key, ', ') from public.marketing_campaign c join public.marketing_post mp2 on mp2.campaign_id = c.id
          where not c.is_demo and c.approved_hash is not null and mp2.status <> 'cancelled'
            and date_trunc('month', mp2.scheduled_at at time zone 'Asia/Dubai')::date = date_trunc('month', r.m)::date)));
      n_closed := n_closed + 1;
    end if;
  end loop;

  -- the CEO's own side: a plan waiting on the CEO for more than 2 days with no CEO turn since it was sent
  if p.status = 'with_ceo' and p.plan_sent_at < p_at - interval '2 days'
     and not exists (select 1 from public.marketing_plan_review_turn t where t.month = p.month and t.seat = 'ceo'
                       and t.created_at >= p.plan_sent_at) then
    v_stalled := true;
    perform public.fn_it_engineer_finding_upsert('ceo:marketing_plan_review_stalled:' || v_month,
      'The CEO has not reviewed the marketing plan for ' || to_char(v_month, 'FMMonth YYYY') || ' sent ' || to_char(p.plan_sent_at at time zone 'Asia/Dubai', 'DD Mon'),
      'public.marketing_month_plan / seat_deliberation ' || coalesce(p.deliberation_id::text, 'none'), 'agent_facing', 1,
      jsonb_build_object('month', v_month, 'deliberation_id', p.deliberation_id, 'owner_seat', 'ceo'),
      '{}'::text[], array['where the review machine stopped advancing the CEO''s turn'], 'ceo');
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO''s turn on the marketing plan is recorded, or the plan left the CEO'
   where issue_key like 'ceo:marketing\_plan\_review\_stalled:%' and closed_at is null
     and not (v_stalled and issue_key = 'ceo:marketing_plan_review_stalled:' || v_month);

  return jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', coalesce(p.status, 'none'),
    'late', v_late, 'covered_by_approved_calendar', v_covered, 'improvement', v_id, 'review_stalled', v_stalled, 'closed', n_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_marketing_plan_watch_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_marketing_plan_watch(now()) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_month_plan(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date; v_pm date := (v_m0 - interval '1 month')::date;
  c_id bigint; d public.ceo_seat_directive; r jsonb; x jsonb; v_status text; v_targets jsonb; v_need numeric; v_act numeric;
  v_miss jsonb; v_hid bigint; n_closed int := 0; n_issued int := 0; v_body text; v_facts jsonb; s text; v_cost numeric; v_ceiling numeric;
  v_board jsonb;   -- BOARD PACK
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then return jsonb_build_object('month', v_m0, 'contract', null); end if;

  -- 1. close last month's directives, met or missed; a missed target becomes an improvement for the seat
  if exists (select 1 from public.target_path where contract_id = c_id and month = v_pm) then
    r := public.fn_ceo_path_month_result(c_id, v_pm);
    for d in select * from public.ceo_seat_directive where month = v_pm and status = 'issued' loop
      select coalesce(jsonb_agg(e), '[]'::jsonb) into x from jsonb_array_elements(r) e where e->>'owner_seat' = d.seat;
      v_status := case when exists (select 1 from jsonb_array_elements(x) e where e->>'result' = 'missed') then 'missed'
                       when exists (select 1 from jsonb_array_elements(x) e where e->>'result' = 'met') then 'met'
                       else 'not_measurable' end;
      update public.ceo_seat_directive set status = v_status, outcome = x, closed_at = now() where month = d.month and seat = d.seat;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions where id = d.handoff_id and status = 'pending') then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('verified_by', 'ceo', 'month', v_pm, 'result', v_status, 'outcome', x));
        perform set_config('qd.handoff_closer', '', true);
      end if;
      for v_miss in select e from jsonb_array_elements(x) e where e->>'result' = 'missed' loop
        perform public.fn_ceo_improvement_open('month_miss', v_pm || ':' || d.seat || ':' || (v_miss->>'metric'), d.seat,
          format('%s closed %s at %s against a target of %s. Name the root cause and what changes this month.', v_miss->>'metric', to_char(v_pm, 'Mon YYYY'), v_miss->>'actual', v_miss->>'target'),
          v_miss || jsonb_build_object('month', v_pm));
      end loop;
      n_closed := n_closed + 1;
    end loop;

    -- 2. the founder's monthly report, once per month
    if not exists (select 1 from public.ceo_month_report where month = v_pm) then
      v_board := public.fn_ceo_board_pack(v_pm);   -- BOARD PACK
      select cost_ceiling_aed into v_ceiling from public.ceo_year_plan where month = v_pm;
      v_cost := (select (e->>'actual')::numeric from jsonb_array_elements(r) e where e->>'metric' = 'costs_aed');
      v_facts := jsonb_build_object('month', v_pm, 'metrics', r,
        'directives', (select coalesce(jsonb_object_agg(seat, status), '{}'::jsonb) from public.ceo_seat_directive where month = v_pm),
        'improvements_opened', (select count(*) from public.ceo_improvement where created_at >= v_pm and created_at < v_m0),
        'improvements_closed', (select count(*) from public.ceo_improvement where closed_at >= v_pm and closed_at < v_m0),
        'cost_ceiling_aed', v_ceiling, 'costs_aed', v_cost, 'next_month', (select to_jsonb(y) from public.ceo_year_plan y where y.month = v_m0))
        || jsonb_build_object('board', v_board - 'text');   -- BOARD PACK
      v_body := format(E'Monthly review, %s.\n\nTargets against the plan:\n', to_char(v_pm, 'FMMonth YYYY'))
        || (select string_agg(format('- %s (%s): %s of %s, %s', e->>'metric', e->>'owner_seat', coalesce(e->>'actual', 'not measurable'),
                                     e->>'target', e->>'result'), E'\n' order by e->>'owner_seat') from jsonb_array_elements(r) e)
        || E'\n\nSeats: ' || coalesce((select string_agg(seat || ' ' || status, ', ' order by seat) from public.ceo_seat_directive where month = v_pm), 'no directives were issued')
        || format(E'\nCosts: AED %s against a ceiling of AED %s.', coalesce(round(v_cost)::text, 'not measurable'), v_ceiling)
        || format(E'\nImprovements: %s opened, %s closed.', v_facts->>'improvements_opened', v_facts->>'improvements_closed')
        || coalesce(format(E'\n\nNext month: %s verified suppliers by month end, %s requests, AED %s of reveal fees.',
                           v_facts->'next_month'->>'verified', v_facts->'next_month'->>'requests', v_facts->'next_month'->>'fee_aed'), '')
        || E'\n\n' || coalesce(v_board->>'text', '');   -- BOARD PACK
      v_hid := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_month_report', v_pm::text,
        jsonb_build_object('recipient_role', 'founder', 'event', 'CEO monthly review: ' || to_char(v_pm, 'FMMonth YYYY'), 'detail', left(v_body, 7000),
                           'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_month:' || v_pm));
      insert into public.ceo_month_report (month, facts, body, handoff_id) values (v_pm, v_facts, v_body, v_hid);
    end if;
  end if;

  -- 3. this month's directive per seat, from the plan table; a cumulative target carries last month's shortfall
  if exists (select 1 from public.target_path where contract_id = c_id and month = v_m0) then
    foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
      continue when exists (select 1 from public.ceo_seat_directive where month = v_m0 and seat = s);
      continue when not exists (select 1 from public.org_role where role_id = s and status = 'active');
      v_targets := '[]'::jsonb;
      for x in select to_jsonb(p) from public.target_path p where p.contract_id = c_id and p.month = v_m0 and p.owner_seat = s order by p.metric_key loop
        v_need := null;
        if x->>'kind' = 'cumulative' then
          v_act := public.fn_ambition_measure(x->>'metric_key', v_m0::timestamp at time zone 'Asia/Dubai', p_at);
          v_need := greatest(0, (x->>'value')::numeric - coalesce(v_act, 0));
        end if;
        v_targets := v_targets || jsonb_build_object('metric', x->>'metric_key', 'kind', x->>'kind', 'direction', x->>'direction',
                                                     'target', (x->>'value')::numeric, 'still_needed', v_need);
      end loop;
      insert into public.ceo_seat_directive (month, seat, targets, actions)
      values (v_m0, s, v_targets, coalesce((select array_agg(a.action order by a.id) from public.ceo_plan_action a
                                             where a.seat = s and v_m0 between a.from_month and a.to_month), '{}'::text[]));
      v_hid := public.fn_seat_handoff('ceo', s, 'ceo.month_directive', 'ceo_seat_directive', v_m0 || ':' || s,
        jsonb_build_object('month', v_m0, 'targets', v_targets,
                           'actions', (select to_jsonb(actions) from public.ceo_seat_directive where month = v_m0 and seat = s),
                           'due_at', ((v_m0 + interval '1 month')::timestamp at time zone 'Asia/Dubai')));
      update public.ceo_seat_directive set handoff_id = v_hid where month = v_m0 and seat = s;
      n_issued := n_issued + 1;
    end loop;
  end if;
  return jsonb_build_object('month', v_m0, 'closed', n_closed, 'issued', n_issued,
    'reported', (select handoff_id from public.ceo_month_report where month = v_pm));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_month_plan_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_month_plan(now()) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_owes_a_decision(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.decision_owed',
    'A seat''s submission has been ' || coalesce(a.detail->>'why', 'sent back 4 times') || '. As the chief executive, decide what is good for '
      || 'the company: replace it (a different piece of work, owner or approach takes its place) or withdraw it (it does not go ahead). '
      || 'Say why, answering the reasons given in every round.',
    '[{"id":"replace","meaning":"replace the item: say in your reasons what takes its place (other work, owner or approach). A refund restarts its review with a fresh count; any other item closes and the seat is told what replaces it"},{"id":"withdraw","meaning":"withdraw the item: it does not go ahead (a refund is declined, never paid), and the seat is told why"}]'::jsonb,
    jsonb_build_object('path', a.detail->>'path', 'item_key', a.detail->>'item_key', 'rounds', a.detail->'rounds',
                       'last_reasons', a.detail->>'last_reasons', 'submission', a.detail->'version'),
    jsonb_build_object('handoff_id', p_id, 'item_key', a.detail->>'item_key'),
    'ceo_decision_owed:' || (a.detail->>'item_key') || ':g' || coalesce(a.detail->>'generation', '1') || ':after_r' || coalesce(a.detail->>'after_round', '0'));
  return jsonb_build_object('waiting', 'the CEO replaces or withdraws ' || coalesce(a.detail->>'item_key', '?') || ', with reasons (held question ' || v_held || ')',
                            'held_id', v_held);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_path_month_result(p_contract bigint, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p record; v_from timestamptz := p_month::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (p_month + interval '1 month')::timestamp at time zone 'Asia/Dubai'; v_act numeric; v_out jsonb := '[]'::jsonb;
begin
  for p in select * from public.target_path where contract_id = p_contract and month = p_month order by owner_seat, metric_key loop
    v_act := public.fn_ambition_measure(p.metric_key, v_from, v_to);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'direction', p.direction, 'target', p.value, 'actual', v_act,
      'result', case when v_act is null then 'not_measurable'
                     when p.direction = 'max' then case when v_act <= p.value then 'met' else 'missed' end
                     when p.value <= 0 then 'met'
                     when v_act >= p.value then 'met' else 'missed' end);
  end loop;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_act(p_plan_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.ceo_plan; d jsonb; dr jsonb; v_open bigint; v_hid bigint; v_logged int := 0; v_issued jsonb := '[]';
begin
  select * into p from public.ceo_plan where id = p_plan_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no ceo_plan '||p_plan_id); end if;
  d := p.decision;

  -- the constraint, once per run of the same stage
  v_logged := v_logged + public.fn_ceo_plan_log('binding_constraint', 'binding_constraint:plan:'||p.stage||':'||p.constraint_since,
    format('The binding constraint is %s (since %s). %s', d->>'label', p.constraint_since,
           case when d->>'lever' <> 'seat' and p.stage <> 'on_plan' then 'Held, no directive: '||coalesce(d->>'held_because','')
                            when d->>'lever' = 'seat' and p.stage <> 'on_plan' then (d->>'owner_seat')||' is directed to move it.' else 'Every stage is on plan.' end),
    jsonb_build_object('plan_id', p.id, 'plan_stage', p.stage, 'lever', d->>'lever', 'held_because', d->>'held_because', 'attainment', d->'attainment',
                       'funnel_month_to_date', p.funnel->'month_to_date', 'month_target', p.month_target));

  if (d->>'stalled')::boolean then
    v_logged := v_logged + public.fn_ceo_plan_log('constraint_stalled', 'constraint_stalled:'||p.stage||':'||p.constraint_since||':L'||(d->>'level'),
      format('The %s constraint has held %s days and the last 7 days read %s against a weekly plan it must reach. Level %s: %s.',
             d->>'label', d->>'days_on_constraint', coalesce(p.funnel->'last_7_days'->>(d->'directive'->>'measure_key'), p.funnel->'state'->>(d->'directive'->>'measure_key'), 'n/a'),
             d->>'level', case d->>'level' when '3' then 'the founder is told in the brief' else 'deadline tightened to 3 days' end),
      jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'days', d->'days_on_constraint', 'level', d->'level', 'last_7_days', p.funnel->'last_7_days'));
  end if;

  -- jsonb_build_object stores a SQL NULL as JSON null, which IS NOT NULL: unwrap it before testing.
  dr := nullif(d->'directive', 'null'::jsonb);
  if dr is not null then
    select a.id into v_open from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'ceo.directive' and a.detail->>'from' = 'ceo'
       and a.detail->>'stage' = p.stage and a.status = 'pending' limit 1;
    if v_open is null then
      v_hid := public.fn_seat_handoff('ceo', dr->>'seat', 'ceo.directive', 'ceo_plan', p.plan_date::text||':'||p.stage,
        dr || jsonb_build_object('plan_id', p.id, 'due_at', now() + make_interval(days => (dr->>'due_days')::int),
                                 'prediction', d->'prediction', 'decided_by', p.decided_by));
      v_issued := v_issued || jsonb_build_object('handoff_id', v_hid) || dr;
      v_logged := v_logged + public.fn_ceo_plan_log('seat_directive', 'seat_directive:issued:'||v_hid,
        format('%s must bring %s %s %s within %s days (level %s).', dr->>'seat', dr->>'measure_key',
               case dr->>'direction' when 'min' then 'to at least' else 'down to' end, dr->>'target', dr->>'due_days', dr->>'level'),
        jsonb_build_object('plan_id', p.id, 'handoff_id', v_hid, 'directive', dr, 'prediction', d->'prediction'));
    else
      v_issued := v_issued || jsonb_build_object('handoff_id', v_open, 'already_open', true);
    end if;
  end if;

  update public.ceo_plan set directives = v_issued where id = p.id;
  return jsonb_build_object('ok', true, 'plan_id', p.id, 'stage', p.stage, 'directives', v_issued, 'decisions_written', v_logged);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_brief_lines()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A HELD stage (lever founder_reserved / unowned) contributes no line at all: the founder is not told
  -- the CEO is waiting on the campaign, nor about a seat that does not exist. Every line is then passed
  -- through fn_ceo_founder_text_forbidden, so a line that would raise a reserved subject is dropped.
  select coalesce((select jsonb_agg(x) from jsonb_array_elements_text((
    select case when p.decision->>'lever' = 'seat' or p.stage = 'on_plan' then
             jsonb_build_array('The CEO''s focus: '||(p.decision->>'label')
             || case when p.stage = 'on_plan' then '.'
                     else ' ('||coalesce(p.decision->'attainment'->p.stage->>'actual','0')||' of '
                          ||coalesce(p.decision->'attainment'->p.stage->>'planned_to_date','0')||' planned so far this month; day '
                          ||(p.decision->>'days_on_constraint')||' on this constraint).' end)
           else '[]'::jsonb end
        || coalesce((select jsonb_agg(initcap(replace(a.agent,'_',' '))||' is directed to bring '||replace(a.detail->>'measure_key','_',' ')
                                      ||case a.detail->>'direction' when 'max' then ' down to ' else ' to ' end||(a.detail->>'target')
                                      ||' by '||to_char((a.detail->>'due_at')::timestamptz at time zone 'Asia/Dubai','DD Mon')||'.')
                       from public.agent_actions a
                      where a.kind='handoff' and a.detail->>'type'='ceo.directive' and a.status='pending'
                        and exists (select 1 from public.org_role r where r.role_id = a.agent and r.status = 'active')), '[]'::jsonb)
        || case when p.founder_line is not null then jsonb_build_array('Waiting on you: '||p.founder_line) else '[]'::jsonb end
      from public.ceo_plan p order by p.plan_date desc limit 1)) x
   where x !~* public.fn_ceo_founder_text_forbidden()), '[]'::jsonb)
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_decide(p_funnel jsonb, p_target jsonb, p_prev jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pro numeric := (p_funnel->>'day_of_month')::numeric / (p_funnel->>'days_in_month')::numeric;
  v_dim numeric := (p_funnel->>'days_in_month')::numeric;
  m jsonb := p_funnel->'month_to_date'; w jsonb := p_funnel->'last_7_days'; s jsonb := p_funnel->'state';
  g jsonb := p_funnel->'gates';
  v_today date := (p_funnel->>'local_date')::date;
  v_att jsonb := '{}'; v_stage text; v_label text; v_owner text; v_lever text := 'seat';
  v_key text; v_dir text := 'min'; v_month_qty numeric; v_since date; v_days int; v_week_actual numeric;
  v_stalled boolean := false; v_level int; v_target numeric; v_due int; v_founder text; v_cap int; v_hold text;
  v_choice text; v_options jsonb; v_stage_order text[] := array['deliverability','invitations','registrations',
    'verification','demand','quotes','reveals'];
  st text; v_plan numeric; v_act numeric; v_a numeric;
  v_gate_open boolean := coalesce((g->>'invite_enabled')::boolean,false) and coalesce((g->>'supplier_outreach_golive')::boolean,false);
  v_scope text[] := case when jsonb_typeof(p_funnel->'company_stage'->'scope') = 'array'
                         then array(select jsonb_array_elements_text(p_funnel->'company_stage'->'scope')) else v_stage_order end;
  v_held_upstream text[] := '{}'; v_first_held text;
begin
  -- attainment per stage: actual month-to-date over the pro-rated month plan (null when the plan is < 1)
  foreach st in array v_stage_order loop
    v_plan := null; v_act := null; v_a := null;
    case st
      when 'invitations'   then v_plan := (p_target->>'invites')::numeric * v_pro;    v_act := (m->>'invitations_delivered')::numeric;
      when 'registrations' then v_plan := (p_target->>'registered')::numeric * v_pro; v_act := (m->>'registrations_submitted')::numeric;
      when 'verification'  then v_plan := (p_target->>'verified')::numeric * v_pro;   v_act := (m->>'registrations_verified')::numeric;
      when 'demand'        then v_plan := (p_target->>'inquiries')::numeric * v_pro;  v_act := (m->>'inquiries_posted')::numeric;
      when 'reveals'       then v_plan := (p_target->>'reveals')::numeric * v_pro;    v_act := (m->>'reveals_paid')::numeric;
      when 'quotes'        then v_plan := case when m->>'quote_coverage_pct' is not null then 70 end; v_act := (m->>'quote_coverage_pct')::numeric;
      else null;
    end case;
    if v_plan is not null and v_plan >= 1 then v_a := round(coalesce(v_act,0) / v_plan, 3); end if;
    v_att := v_att || jsonb_build_object(st, jsonb_build_object('actual', v_act, 'planned_to_date', round(v_plan), 'attainment', v_a));
  end loop;

  -- the binding stage
  if (s->>'bounce_pct_7d')::numeric > 5 then
    v_stage := 'deliverability';
  elsif (s->>'stranded_submissions')::numeric > 0 then
    v_stage := 'verification';
  else
    foreach st in array v_stage_order loop
      continue when st = 'deliverability' or not (st = any (v_scope));
      if (v_att->st->>'attainment') is not null and (v_att->st->>'attainment')::numeric < 0.8 then
        if st in ('invitations','registrations') and not v_gate_open then
          v_held_upstream := v_held_upstream || st;          -- held by the founder's gate: record it and keep walking
          v_first_held := coalesce(v_first_held, st);
          continue;
        end if;
        v_stage := st; exit;
      end if;
    end loop;
    v_stage := coalesce(v_stage, v_first_held);
  end if;
  v_stage := coalesce(v_stage, 'on_plan');

  v_label := case v_stage
    when 'deliverability' then 'email deliverability (bounces above 5%)'
    when 'invitations'    then 'supplier invitations delivered'
    when 'registrations'  then 'supplier registrations submitted'
    when 'verification'   then 'supplier registrations verified'
    when 'demand'         then 'customer requests posted'
    when 'quotes'         then 'requests reaching 3 quotes'
    when 'reveals'        then 'reveal fees paid'
    else 'every stage on plan' end;
  -- demand (customer requests posted) is buyer acquisition: the marketing seat's since 22 Sep 2026 (instruction 721).
  v_owner := case v_stage when 'deliverability' then 'customer_support' when 'demand' then 'marketing'
                          when 'on_plan' then null else 'sales_engineer' end;
  v_key := case v_stage
    when 'deliverability' then 'bounce_pct_7d' when 'invitations' then 'invitations_delivered'
    when 'registrations' then 'registrations_submitted'
    when 'verification' then case when (s->>'stranded_submissions')::numeric > 0 then 'stranded_submissions' else 'registrations_verified' end
    when 'demand' then 'inquiries_posted' when 'quotes' then 'quote_coverage_pct' when 'reveals' then 'reveals_paid' end;
  if v_key in ('bounce_pct_7d','stranded_submissions') then v_dir := 'max'; end if;

  -- who can move it. A HELD stage is recorded here and in ceo_decision_log, and NOWHERE the founder reads
  -- (instructions 636 and 639, 22 Sep 2026): the campaign gate and the daily cap are never raised with him.
  v_cap := coalesce((g->>'invite_daily_cap')::int, 0);
  if v_stage in ('invitations','registrations') and not v_gate_open then
    v_lever := 'founder_reserved';
    v_hold := 'the campaign gate is closed: the founder''s reserved decision, held silently';
  elsif v_stage = 'invitations' and ceil((p_target->>'invites')::numeric / 22) > v_cap then
    v_hold := format('the daily cap of %s is below the %s a day this month''s plan needs; the directive is bounded by the cap',
                     v_cap, ceil((p_target->>'invites')::numeric / 22));
  end if;

  -- how long it has held, and whether it is moving
  if p_prev is not null and p_prev->>'stage' = v_stage then v_since := (p_prev->>'constraint_since')::date;
  else v_since := v_today; end if;
  v_days := v_today - v_since;
  v_month_qty := case v_stage when 'invitations' then (p_target->>'invites')::numeric when 'registrations' then (p_target->>'registered')::numeric
                   when 'verification' then (p_target->>'verified')::numeric when 'demand' then (p_target->>'inquiries')::numeric
                   when 'reveals' then (p_target->>'reveals')::numeric end;
  v_week_actual := (w->>v_key)::numeric;
  if v_stage <> 'on_plan' and v_days >= 7 then
    v_stalled := case when v_dir = 'max' then true
                      when v_key = 'quote_coverage_pct' then coalesce(v_week_actual, 0) < 35
                      else coalesce(v_week_actual, 0) < 0.5 * ceil(coalesce(v_month_qty,0) * 7 / v_dim) end;
  end if;
  v_level := case when v_stalled and v_days >= 14 then 3 when v_stalled then 2 else 1 end;
  if v_level = 3 and v_lever = 'seat' and v_stage <> 'invitations' then
    v_founder := format('The %s constraint has not moved in %s days although %s was directed; it now needs your view.', v_label, v_days, v_owner);
  end if;

  v_due := case v_level when 1 then 7 else 3 end;
  v_target := case
    when v_dir = 'max' and v_key = 'bounce_pct_7d' then 5
    when v_dir = 'max' then 0
    when v_key = 'quote_coverage_pct' then 70
    when v_key = 'invitations_delivered' then least(ceil(v_month_qty * v_due / v_dim), v_cap * v_due)
    else greatest(1, ceil(coalesce(v_month_qty,0) * v_due / v_dim)) end;

  v_options := jsonb_build_array(
    jsonb_build_object('id','hold','effect','no directive; the seats run their standing duties'),
    jsonb_build_object('id','direct_owner','effect',format('direct %s: %s %s %s within %s days', v_owner, v_key, case v_dir when 'min' then '>=' else '<=' end, v_target, v_due)),
    jsonb_build_object('id','escalate','effect','record the stall, tighten the deadline to 3 days, and put the constraint in the founder brief at 14 days'),
    jsonb_build_object('id','hold_reserved','effect','the stage is held by a reserved decision or has no owning seat: record it internally, give no seat an order it cannot carry out, say nothing to the founder'),
    jsonb_build_object('id','revise_target','effect','propose a new month target with the evidence; the table changes only by a recorded CEO decision'));
  v_choice := case when v_stage = 'on_plan' then 'hold' when v_lever <> 'seat' then 'hold_reserved'
                   when v_stalled then 'escalate' else 'direct_owner' end;

  return jsonb_build_object(
    'stage', v_stage, 'label', v_label, 'owner_seat', v_owner, 'lever', v_lever,
    'company_stage', p_funnel->'company_stage'->>'stage', 'scope', to_jsonb(v_scope), 'held_upstream', to_jsonb(v_held_upstream),
    'constraint_since', v_since, 'days_on_constraint', v_days, 'stalled', v_stalled, 'level', v_level,
    'attainment', v_att, 'founder_line', v_founder, 'held_because', v_hold, 'options', v_options, 'plan_c_choice', v_choice,
    'directive', case when v_lever = 'seat' and v_stage <> 'on_plan' then jsonb_build_object(
        'seat', v_owner, 'stage', v_stage, 'measure_key', v_key, 'direction', v_dir, 'target', v_target,
        'due_days', v_due, 'level', v_level) end,
    'prediction', case when v_lever = 'seat' and v_stage <> 'on_plan' then jsonb_build_object(
        'measure_key', v_key, 'direction', v_dir, 'value', v_target, 'by_date', v_today + v_due) end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_followup(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record; v numeric; v_met boolean; n_met int := 0; n_missed int := 0; n_open int := 0; v_err jsonb := '[]';
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'ceo.directive' and detail->>'from' = 'ceo' and status = 'pending'
            order by id loop
    begin
      v := public.fn_ceo_plan_measure(a.detail->>'measure_key',
             case when a.detail->>'measure_key' in ('bounce_pct_7d','stranded_submissions') then p_now else a.created_at end, p_now);
      v_met := case when v is null then false
                    when a.detail->>'direction' = 'max' then v <= (a.detail->>'target')::numeric
                    else v >= (a.detail->>'target')::numeric end;
      if v_met or p_now > (a.detail->>'due_at')::timestamptz then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(a.id, coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', 'ceo', 'verified_at', p_now, 'reading', v, 'target', a.detail->'target', 'met', v_met));
        perform set_config('qd.handoff_closer', '', true);
        perform public.fn_ceo_plan_log('seat_directive', 'seat_directive:'||case when v_met then 'met' else 'missed' end||':'||a.id,
          format('%s %s the directive: %s read %s against %s by %s.', a.agent, case when v_met then 'met' else 'missed' end,
                 a.detail->>'measure_key', coalesce(v::text,'n/a'), a.detail->>'target', a.detail->>'due_at'),
          jsonb_build_object('handoff_id', a.id, 'reading', v, 'target', a.detail->'target', 'met', v_met,
                             'prediction', a.detail->'prediction', 'prediction_held', v_met));
        if v_met then n_met := n_met + 1; else n_missed := n_missed + 1; end if;
      else
        n_open := n_open + 1;
      end if;
    exception when others then
      perform set_config('qd.handoff_closer', '', true);
      v_err := v_err || jsonb_build_object('handoff', a.id, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'met', n_met, 'missed', n_missed, 'open', n_open)
      || case when jsonb_array_length(v_err) = 0 then '{}'::jsonb else jsonb_build_object('error', v_err::text) end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_funnel(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_m0 timestamptz := date_trunc('month', v_local) at time zone 'Asia/Dubai';
  v_w0 timestamptz := p_at - interval '7 days';
  k text; v_mtd jsonb := '{}'; v_l7 jsonb := '{}';
begin
  foreach k in array array['invitations_delivered','registrations_submitted','registrations_verified',
                           'inquiries_posted','quote_coverage_pct','reveals_paid','fee_aed'] loop
    v_mtd := v_mtd || jsonb_build_object(k, public.fn_ceo_plan_measure(k, v_m0, p_at));
    v_l7  := v_l7  || jsonb_build_object(k, public.fn_ceo_plan_measure(k, v_w0, p_at));
  end loop;
  return jsonb_build_object(
    'at', p_at, 'local_date', v_local::date,
    'day_of_month', extract(day from v_local)::int,
    'days_in_month', extract(day from (date_trunc('month', v_local) + interval '1 month - 1 day'))::int,
    'month_to_date', v_mtd, 'last_7_days', v_l7,
    'company_stage', (select jsonb_build_object('stage', s.stage, 'since', l.entered_at, 'scope', to_jsonb(s.constraint_scope),
                                                'exit', s.exit_meaning, 'exit_measure', s.exit_measure, 'exit_threshold', s.exit_threshold,
                                                'exit_reading', case when s.exit_measure is not null then public.fn_ambition_measure(s.exit_measure, timestamptz '2026-01-01', p_at) end)
                        from public.ceo_company_stage_log l join public.ceo_company_stage s on s.stage = l.stage where l.left_at is null),
    'state', jsonb_build_object(
      'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at, p_at),
      'stranded_submissions', public.fn_ceo_plan_measure('stranded_submissions', p_at, p_at),
      'contactable_leads', public.fn_ceo_plan_measure('contactable_leads', p_at, p_at),
      'fee_aed_cumulative', public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', p_at)),
    'gates', (select jsonb_build_object(
        'invite_enabled', coalesce(max(value) filter (where key='invite_enabled'),'') = 'true',
        'supplier_outreach_golive', coalesce(max(value) filter (where key='supplier_outreach_golive'),'') = 'true',
        'invite_daily_cap', coalesce(nullif(max(value) filter (where key='invite_daily_cap'),'')::int, 0),
        'ceo_model_slot', coalesce(nullif(max(value) filter (where key='ceo_model_slot'),''), 'off'))
      from public.app_secrets where key in ('invite_enabled','supplier_outreach_golive','invite_daily_cap','ceo_model_slot')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_log(p_key text, p_dedupe text, p_decision text, p_evidence jsonb, p_outcome text DEFAULT 'decided'::text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with ins as (
    insert into public.ceo_decision_log (decision_key, the_decision, evidence, escalated_to_founder, outcome, dedupe_key)
    values (p_key, p_decision, p_evidence, false, p_outcome, p_dedupe)
    on conflict (dedupe_key) where dedupe_key is not null do nothing returning 1)
  select count(*)::int from ins
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_measure(p_key text, p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v numeric; v_sent numeric; v_bounced numeric;
begin
  case p_key
  when 'invitations_delivered' then
    select count(*) into v from public.notifications n left join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.provider_message_id is not null
       and n.sent_at >= p_from and n.sent_at < p_to
       and coalesce(n.to_email,'') not ilike '%@example.invalid'
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  when 'registrations_submitted', 'registrations_verified' then
    select count(*) into v from public.leads l
     where case when p_key = 'registrations_submitted' then l.registration_submitted_at else l.approved_at end >= p_from
       and case when p_key = 'registrations_submitted' then l.registration_submitted_at else l.approved_at end <  p_to
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  when 'stranded_submissions' then
    select count(*) into v from public.leads l
     where l.registration_submitted_at < p_to - interval '24 hours' and l.approved_at is null and l.rejection_reason is null
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  when 'inquiries_posted', 'quote_coverage_pct' then
    with i as (
      select i.id from public.inquiries i join public.customers c on c.id = i.customer_id
       where i.parent_inquiry_id is null and i.created_at >= p_from
         and i.created_at < case when p_key = 'quote_coverage_pct' then p_to - interval '3 days' else p_to end
         and coalesce(i.provenance->>'source','') not in ('demo_factory','e2e')
         and not (coalesce(c.is_demo,false) or coalesce(c.full_name,'') ilike 'ZZ DEMO%'
                  or coalesce(c.email,'') ilike '%@example.invalid' or coalesce(c.phone,'') like '+9715000000%'))
    select case when p_key = 'inquiries_posted' then count(*)
                when count(*) = 0 then null     -- no request old enough to judge: not measurable, not zero
                else round(100.0 * count(*) filter (where (select count(*) from public.quotes q where q.inquiry_id = i.id) >= 3) / count(*), 1) end
      into v from i;
  when 'reveals_paid', 'fee_aed' then
    select case when p_key = 'reveals_paid' then count(*) else coalesce(sum(coalesce(t.reveal_fee, t.app_fee, 0)), 0) end into v
      from public.transactions t join public.customers c on c.id = t.customer_id
     where t.payment_ref ~ '^(pi|ch|py)_' and t.revealed_at >= p_from and t.revealed_at < p_to
       and not (coalesce(c.is_demo,false) or coalesce(c.full_name,'') ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid');
  when 'bounce_pct_7d' then
    -- the same reading as the channel_volume rule in fn_ceo_decisions_evaluate
    select count(*) into v_sent from public.notifications
     where channel = 'email' and status = 'sent' and sent_at > p_to - interval '7 days' and sent_at <= p_to;
    select count(*) into v_bounced from public.email_suppressions
     where reason ilike '%bounce%' and created_at > p_to - interval '7 days' and created_at <= p_to;
    v := case when v_sent >= 20 then round(100.0 * v_bounced / v_sent, 2) end;   -- under 20 sends is not a rate
  when 'contactable_leads' then
    select count(*) into v from public.leads l
     where l.email is not null and l.invited_at is null and coalesce(l.invite_status,'') <> 'bounced'
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  else
    raise exception 'fn_ceo_plan_measure: unknown measure %', p_key;
  end case;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_review(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local date := (p_at at time zone 'Asia/Dubai')::date; v_n int := 0; t public.ceo_plan_month;
  v_from timestamptz; v_to timestamptz; v_fee_cum numeric; v_plan_cum numeric; v_left numeric; v_months int; ev jsonb;
begin
  if extract(isodow from v_local) = 1 then
    v_to := v_local::timestamp at time zone 'Asia/Dubai'; v_from := v_to - interval '7 days';
    select * into t from public.ceo_plan_month where month = date_trunc('month', v_from at time zone 'Asia/Dubai')::date;
    ev := jsonb_build_object('week_from', v_from, 'week_to', v_to,
      'invitations', jsonb_build_array(public.fn_ceo_plan_measure('invitations_delivered', v_from, v_to), round(coalesce(t.invites,0)*7/30.0)),
      'registrations', jsonb_build_array(public.fn_ceo_plan_measure('registrations_submitted', v_from, v_to), round(coalesce(t.registered,0)*7/30.0)),
      'verified', jsonb_build_array(public.fn_ceo_plan_measure('registrations_verified', v_from, v_to), round(coalesce(t.verified,0)*7/30.0)),
      'inquiries', jsonb_build_array(public.fn_ceo_plan_measure('inquiries_posted', v_from, v_to), round(coalesce(t.inquiries,0)*7/30.0)),
      'reveals', jsonb_build_array(public.fn_ceo_plan_measure('reveals_paid', v_from, v_to), round(coalesce(t.reveals,0)*7/30.0)),
      'fee_aed', jsonb_build_array(public.fn_ceo_plan_measure('fee_aed', v_from, v_to), round(coalesce(t.fee_aed,0)*7/30.0)),
      'directives', (select jsonb_build_object('met', count(*) filter (where (evidence->>'met')::boolean), 'missed', count(*) filter (where not (evidence->>'met')::boolean))
                       from public.agent_actions where kind='handoff' and detail->>'type'='ceo.directive' and status='done' and decided_at >= v_from and decided_at < v_to),
      'shape', '[actual, plan]');
    v_n := v_n + public.fn_ceo_plan_log('plan_review', 'plan_review:week:'||to_char(v_from at time zone 'Asia/Dubai','IYYY-"W"IW'),
      format('Week review: invitations %s/%s, registrations %s/%s, requests %s/%s, reveals %s/%s, fee AED %s/%s (actual/plan).',
             ev->'invitations'->>0, ev->'invitations'->>1, ev->'registrations'->>0, ev->'registrations'->>1,
             ev->'inquiries'->>0, ev->'inquiries'->>1, ev->'reveals'->>0, ev->'reveals'->>1, ev->'fee_aed'->>0, ev->'fee_aed'->>1), ev);
  end if;

  if extract(day from v_local) = 1 then
    v_fee_cum := public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', v_local::timestamp at time zone 'Asia/Dubai');
    select coalesce(sum(fee_aed),0) into v_plan_cum from public.ceo_plan_month where month < v_local;
    select count(*) into v_months from public.ceo_plan_month where month >= v_local;
    v_left := 1000000 - v_fee_cum;
    ev := jsonb_build_object('fee_cumulative', v_fee_cum, 'plan_cumulative', v_plan_cum, 'remaining', v_left, 'months_left', v_months,
      'required_per_month', case when v_months > 0 then round(v_left / v_months) end,
      'highest_month_ever', (select max(public.fn_ceo_plan_measure('fee_aed', m.month::timestamp at time zone 'Asia/Dubai', (m.month + interval '1 month')::timestamp at time zone 'Asia/Dubai'))
                               from public.ceo_plan_month m where m.month < v_local));
    v_n := v_n + public.fn_ceo_plan_log('plan_review', 'plan_review:month:'||to_char(v_local - 1, 'YYYY-MM'),
      format('Month review: cumulative fee AED %s against a plan of AED %s. AED %s remains over %s months: AED %s a month is now required.',
             v_fee_cum, v_plan_cum, v_left, v_months, coalesce(ev->>'required_per_month','n/a')), ev);
  end if;
  return v_n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_plan_tick(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_fu jsonb; v_funnel jsonb; v_target jsonb; v_prev jsonb; v_dec jsonb; v_act jsonb; v_rev int; v_req jsonb;
  p public.ceo_plan;
begin
  v_fu := public.fn_ceo_plan_followup(p_at);

  select * into p from public.ceo_plan where plan_date = v_local::date;
  if found then
    return jsonb_build_object('ok', coalesce((v_fu->>'ok')::boolean, false), 'planned', false, 'reason', 'today''s plan exists',
                              'plan_id', p.id, 'stage', p.stage, 'followup', v_fu)
        || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
  end if;
  if v_local::time < time '06:00' then
    return jsonb_build_object('ok', coalesce((v_fu->>'ok')::boolean, false), 'planned', false, 'reason', 'before 06:00 Dubai', 'followup', v_fu)
        || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
  end if;

  v_funnel := public.fn_ceo_plan_funnel(p_at);
  -- THE CEO READS THE MARKETING PICTURE INTO THE PLAN (instruction 721): the latest marketing.report is kept on the
  -- day's plan row, read by the judgement request as input.marketing. Informational: it changes no lever.
  v_funnel := v_funnel || jsonb_build_object('marketing_report',
    (select jsonb_build_object('report_date', m.report_date, 'no_data_yet', m.no_data_yet, 'headline', m.figures->>'headline',
                               'measured', m.figures->'measured', 'not_measured', m.figures->'not_measured')
       from public.marketing_report m where m.report_date <= v_local::date order by m.report_date desc limit 1));
  select to_jsonb(m) into v_target from public.ceo_plan_month m where m.month = date_trunc('month', v_local)::date;
  select to_jsonb(x) into v_prev from public.ceo_plan x where x.plan_date < v_local::date order by x.plan_date desc limit 1;
  v_dec := public.fn_ceo_plan_decide(v_funnel, coalesce(v_target, '{}'::jsonb), v_prev);

  insert into public.ceo_plan (plan_date, funnel, month_target, stage, constraint_since, decision, founder_line)
  values (v_local::date, v_funnel, v_target, v_dec->>'stage', (v_dec->>'constraint_since')::date, v_dec, v_dec->>'founder_line')
  returning * into p;

  v_act := public.fn_ceo_plan_act(p.id);
  v_rev := public.fn_ceo_plan_review(p_at);

  v_req := public.fn_ceo_judgement_request(p.id);
  update public.ceo_plan set judgement = jsonb_build_object('slot', v_funnel->'gates'->>'ceo_model_slot', 'request', v_req,
           'plan_c_acted', true) where id = p.id;

  return jsonb_build_object('ok', coalesce((v_act->>'ok')::boolean, false) and coalesce((v_fu->>'ok')::boolean, false),
    'planned', true, 'plan_id', p.id, 'stage', p.stage, 'lever', v_dec->>'lever', 'stalled', v_dec->'stalled',
    'directives', v_act->'directives', 'decisions_written', v_act->'decisions_written', 'reviews_written', v_rev, 'followup', v_fu,
    'judgement', jsonb_build_object('slot', v_funnel->'gates'->>'ceo_model_slot',
                                    'call_model', v_funnel->'gates'->>'ceo_model_slot' = 'on'))
    || case when coalesce((v_act->>'ok')::boolean, false) then '{}'::jsonb else jsonb_build_object('error', v_act->>'error') end
    || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_pricing_monitor()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := public.fn_ceo_review_week(); v_ev jsonb; v_quoted int; v_held bigint;
begin
  with q as (
    select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) as quotes
      from public.inquiries i where i.created_at > now() - interval '90 days'
  )
  select jsonb_build_object(
    'pricing_config', (select to_jsonb(p) - 'id' - 'updated_at' from public.pricing_config p order by id limit 1),
    'requests_90d', (select count(*) from q),
    'quoted_requests_90d', (select count(*) from q where quotes > 0),
    'reveals_90d', (select count(*) from public.transactions where revealed_at > now() - interval '90 days'),
    'refunds_90d', (select count(*) from public.transactions where refund_requested_at > now() - interval '90 days'),
    'avg_quote_aed', (select round(avg(quote_amount), 2) from public.quotes where created_at > now() - interval '90 days' and quote_amount > 0),
    'avg_reveal_fee_aed', (select round(avg(reveal_fee), 2) from public.transactions where revealed_at > now() - interval '90 days'),
    'nonresponse_refunds', (select coalesce(sum(rv_nonresponse_refunds), 0) from public.leads),
    'supplier_fee_paying', (select count(*) from public.leads where registration_paid_at is not null),
    'competitors_on_file', (select count(*) from public.competitor),
    'unit_economics_last_month', public.fn_accountant_unit_economics((date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date))
  into v_ev;
  v_quoted := (v_ev->>'quoted_requests_90d')::int;
  insert into public.ceo_review (kind, period, facts, decision) values ('pricing_monitor', v_week, v_ev,
    case when v_quoted < 20 then 'insufficient_evidence' end)
  on conflict (kind, period) do update set facts = excluded.facts,
    decision = case when ceo_review.decided_at is null then excluded.decision else ceo_review.decision end;

  -- UNDER 20 QUOTED REQUESTS THE EVIDENCE CANNOT SUPPORT A PRICE CALL: recorded, not reasoned, not proposed.
  if v_quoted >= 20 and (select held_id from public.ceo_review where kind = 'pricing_monitor' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.pricing_monitor',
      'The weekly pricing review. From 90 days of evidence, decide whether our pricing (the supplier annual fee, the caps, '
        || 'the promotion window and the non-response charge) should stay as it is or whether an evidence-based change should '
        || 'be proposed to the founder. The 3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope.',
      ('[{"id":"keep","meaning":"the evidence supports the current pricing"},'
      || '{"id":"propose_change","meaning":"the evidence supports proposing a specific change to the founder"}]')::jsonb,
      v_ev, jsonb_build_object('kind', 'pricing_monitor', 'period', v_week), 'ceo_pricing:' || v_week);
    update public.reasoning_held_question
       set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
             jsonb_build_object('key', 'proposal', 'question', 'the exact change proposed, if any, with the figure'),
             jsonb_build_object('key', 'evidence', 'question', 'the measured evidence it rests on')))
     where id = v_held;
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'pricing_monitor' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'quoted_requests_90d', v_quoted, 'reasoning_filed', v_held is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_reads_marketing_report(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; m public.marketing_report;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'marketing.report' then
    raise exception 'fn_ceo_reads_marketing_report: % is not a marketing.report handoff', p_id;
  end if;
  update public.marketing_report set read_by_ceo_at = coalesce(read_by_ceo_at, now())
   where report_date = (a.detail->>'subject_id')::date returning * into m;
  if m.report_date is null then
    raise exception 'marketing.report % names report %, which does not exist', p_id, a.detail->>'subject_id';
  end if;
  return jsonb_build_object('read', true, 'read_at', m.read_by_ceo_at, 'report_date', m.report_date,
                            'headline', m.figures->>'headline', 'no_data_yet', m.no_data_yet,
                            'note', 'Read by the CEO for the overall picture. Informational: nothing was approved or decided.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_reads_marketing_review(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; r public.marketing_review;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'marketing.review' then
    raise exception 'fn_ceo_reads_marketing_review: % is not a marketing.review handoff', p_id;
  end if;
  update public.marketing_review set read_by_ceo_at = coalesce(read_by_ceo_at, now())
   where id = (a.detail->>'subject_id')::bigint returning * into r;
  if r.id is null then raise exception 'marketing.review % names review %, which does not exist', p_id, a.detail->>'subject_id'; end if;
  return jsonb_build_object('read', true, 'read_at', r.read_by_ceo_at, 'kind', r.kind, 'period', r.period,
                            'note', 'Read by the CEO. The quarterly review carries the January 2027 launch proposal for the CEO''s decision.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_reasons_problem(p_reasons text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when coalesce(cardinality(w), 0) = 0 then 'no reasons were given'
    when cardinality(w) < 6 then 'the reasons are ' || cardinality(w) || ' word(s); a decision says why in at least six'
    when (select count(distinct x) from unnest(w) x) < 4 then 'the reasons repeat the same few words'
  end
  from (select regexp_split_to_array(nullif(public.fn_seat_deliberation_norm(p_reasons), ''), ' ') w) s
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_approval_checks_the_process()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_tx uuid; v jsonb;
begin
  if TG_TABLE_NAME = 'ceo_approval' then
    if NEW.subject_kind <> 'refund' or NEW.decision <> 'approved' then return NEW; end if;
    if coalesce(NEW.subject_id, '') !~ '^[0-9]+$' then
      raise exception 'a refund approval names the refund by its id; % is not one', coalesce(NEW.subject_id, '(nothing)') using errcode = '23514';
    end if;
    select transaction_id into v_tx from public.refunds where id = NEW.subject_id::bigint;
  else
    if NEW.state <> 'ceo_authorized' or (TG_OP = 'UPDATE' and OLD.state = 'ceo_authorized') then return NEW; end if;
    v_tx := NEW.transaction_id;
  end if;
  if v_tx is null then
    raise exception 'the CEO may not approve a refund that names no payment' using errcode = '23514';
  end if;
  v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
  if not (v->>'ok')::boolean then
    raise exception 'the CEO may not approve this refund: % check(s) failed — %', jsonb_array_length(v->'failed'),
      (select string_agg((i->>'item') || ': ' || coalesce(i->>'reason', ''), ' | ') from jsonb_array_elements(v->'failed') i)
      using errcode = '23514',
            hint = 'Founder, 14 Sep 2026: the CEO''s approval exists to make sure the process was done correctly. fn_ceo_refund_review runs the checklist, records the evidence and sends each failure to the seat that owns it.';
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
  v_offp_text text; v_offp_key text; v_offp_choice text; v_offp_held bigint;   -- item 5, reasoned (23 Sep 2026)
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    -- 1. THE CUSTOMER'S COMPLAINT, ON RECORD OR NOT -- NEVER A CONDITION (14 Sep 2026). This item was
    -- complaint_within_7_days_with_proof and refused every refund where the customer did not complain
    -- within 7 days with proof. Terms v7 §5 and Refund Policy v1.5 §3/§5 say the opposite: "you do not
    -- need to do anything for the clock to start", a complaint may come "at any time", and proof "is
    -- never a condition of the refund". So it now records the evidence and always passes; the conditions
    -- the terms DO set are items 2 to 6.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'customer_complaint_on_record',
      'passed', true,
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached,
        'basis', 'Terms v7 section 5, Refund Policy v1.5 sections 3 and 5: no complaint or proof is required; the ladder runs from payment'),
      'reason', null, 'remedy', 'none needed', 'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', true, 'kind', 'information');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
    -- OFF-PLATFORM ENGAGEMENT IS REASONED FROM WHAT WAS WRITTEN, NEVER SPOTTED (23 Sep 2026,
    -- founder_instruction 886-903). A pattern on the note decided this exclusion, and an exclusion DECLINES
    -- the refund: "they did not use the platform" matched nothing, "not off-platform" matched. The notes are
    -- now read by the CEO seat's reasoning (ceo.refund_off_platform) and the answer is read back by its key.
    -- The platform's own default note is our text, not the customer's, so it asks nothing. Until the
    -- reasoning answers, v_offp stays null: no exclusion is assumed, and item 7 below keeps the refund
    -- waiting (fn_ceo_refund_review neither approves nor declines it, and pages nobody).
    v_offp_text := nullif(concat_ws(E'\n',
        case when btrim(coalesce(r.reason_note, '')) not in ('', 'The customer reported that the revealed supplier has not responded.')
             then 'Refund note: ' || btrim(r.reason_note) end,
        (select string_agg('Support note on the supplier''s response: ' || btrim(w.close_reason), E'\n' order by w.id)
           from public.supplier_response_watch w where w.transaction_id = t.id and btrim(coalesce(w.close_reason, '')) <> '')), '');
    if v_offp_text is null then
      v_offp := false;
    else
      v_offp_key := 'refund_offp:' || t.id || ':' || md5(v_offp_text);
      v_offp_choice := public.fn_reason_route_answer(v_offp_key);
      if v_offp_choice is null then
        v_offp := null;
        v_offp_held := public.fn_reason_route_ask('ceo', 'ceo.refund_off_platform', v_offp_text,
          jsonb_build_array(
            jsonb_build_object('id', 'engaged_off_platform', 'meaning', 'the note records that the customer dealt with or hired the supplier outside QuotesDone'),
            jsonb_build_object('id', 'not_off_platform', 'meaning', 'the note does not record any dealing with the supplier outside QuotesDone')),
          jsonb_build_object('transaction_id', t.id, 'refund_id', r.id), v_offp_key);
      else
        v_offp := v_offp_choice = 'engaged_off_platform';
      end if;
    end if;
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if coalesce(v_offp, false) then v_excl := v_excl || 'the customer engaged the supplier off the platform (reasoned by the CEO seat)'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');
    -- 7. The notes on record have been READ (reasoned), so item 5 is a finding and not an assumption.
    if v_offp is null then
      v_items := v_items || jsonb_build_object('item', 'off_platform_engagement_reasoned',
        'passed', false,
        'evidence', jsonb_build_object('held_question_id', v_offp_held, 'dedupe_key', v_offp_key),
        'reason', 'the CEO seat is still reasoning whether the notes on record say the customer dealt with the supplier off the platform',
        'remedy', 'none by hand: the answer arrives through the reasoning queue and the review re-runs itself',
        'owner', 'ceo', 'remedy_key', 'reasoning', 'remediable', true, 'kind', 'needs_reasoning');
    end if;

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'charge_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_decline(p_refund_id bigint, p_reasons text, p_trigger text, p_failed jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.refunds; v_dec bigint; v_rev bigint; v_cycle int;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found or r.status <> 'requested' then
    return jsonb_build_object('ok', false, 'reason', 'refund ' || p_refund_id || ' is ' || coalesce(r.status, 'missing') || ', not an open request');
  end if;
  insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
  values ('refund', r.id::text, 'refused', 'ceo', round(r.amount_fils / 100.0, 2), left(p_reasons, 2000)) returning decision_id into v_dec;
  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, decision_id, trigger, sealed)
  values (r.id, r.transaction_id, v_cycle, 'declined', coalesce(p_failed, '[]'::jsonb), v_dec, p_trigger, true) returning id into v_rev;
  return jsonb_build_object('ok', true, 'decision_id', v_dec, 'review_id', v_rev, 'cycle', v_cycle,
                            'refund', public.fn_refund_decide(r.id, false, 'ceo', left(p_reasons, 900)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_loop_advance(p_refund_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.refund_ceo_review;
begin
  select * into v from public.refund_ceo_review where refund_id = p_refund_id and outcome = 'rejected' order by cycle desc limit 1;
  if not found or not v.sealed or v.rechecked_at is not null then return jsonb_build_object('moved', false); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = p_refund_id::text and (a.detail->>'cycle')::int = v.cycle and a.status <> 'done') then
    return jsonb_build_object('moved', false, 'waiting', true, 'cycle', v.cycle);
  end if;
  if exists (select 1 from public.refund_ceo_review x where x.refund_id = p_refund_id and x.cycle > v.cycle) then
    return jsonb_build_object('moved', false);
  end if;
  update public.refund_ceo_review set rechecked_at = now() where id = v.id;
  return jsonb_build_object('moved', true, 'review', public.fn_ceo_refund_review(p_refund_id, 'remediation_closed'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_loop_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record; v jsonb; n_closed int := 0; n_overdue int := 0; n_raised int := 0; x record; l public.ceo_decision_round;
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'refund.remediate' and status = 'pending' order by id loop
    v := public.fn_ceo_refund_checklist((a.detail->>'transaction_id')::uuid, 'approve', false);
    if not exists (select 1 from jsonb_array_elements(v->'items') i
                    where (a.detail->'checks') ? (i->>'item') and not coalesce((i->>'passed')::boolean, false)) then
      perform public.fn_seat_handoff_complete(a.id, jsonb_build_object('resolved_by', 're-measured', 'checks', a.detail->'checks'));
      n_closed := n_closed + 1;
    elsif now() > (a.detail->>'deadline')::timestamptz and not (a.detail ? 'escalated_at') then
      select * into l from public.ceo_decision_round where item_key = 'refunds:' || (a.detail->>'refund_id')
       order by generation desc, round desc limit 1;
      -- marked escalated only once the CEO is actually owed the choice (a remediation opened before the ledger has
      -- no round to decide on; it stays unmarked and the handoff SLA watch keeps it in view)
      if l.decision = 'rejected' then
        perform public.fn_ceo_decision_owe('refund', l.item_key, a.agent, l.generation,
          'left with its remediation undone past the deadline ' || to_char((a.detail->>'deadline')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY')
            || ' (the ' || a.agent || ' has not closed ' || coalesce(a.detail->>'checks', '?') || ')',
          l.reasons, l.version);
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_at', now()) where id = a.id;
        n_overdue := n_overdue + 1;
      end if;
    end if;
  end loop;

  if not public.fn_refunds_paused() then
    for x in select t.id from public.transactions t
              where t.refund_status in ('refunded', 'succeeded') and t.refund_amount_aed is not null
                and coalesce(t.refund_reason, 'supplier_unresponsive') = 'supplier_unresponsive'
                and not exists (select 1 from public.supplier_dues d where d.transaction_id = t.id and coalesce(d.status, '') <> 'cancelled') loop
      v := public.fn_accountant_raise_nonresponse_charge(x.id, true);
      if coalesce((v->>'created')::boolean, false) then n_raised := n_raised + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('remediation_closed', n_closed, 'remediation_overdue', n_overdue, 'held_charges_raised', n_raised);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_mismatch_playbook(p_transaction_id uuid, p_verify jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_inc bigint; v_money jsonb; v_app numeric; v_act numeric;
begin
  -- (a) PAUSE. Every refund and charge path reads this.
  update public.decision_policy set value = 'true'::jsonb, updated_at = now() where key = 'refunds_and_supplier_charges_paused';
  -- (b) THE INCIDENT: approved vs actual vs difference.
  select x->'evidence' into v_money from jsonb_array_elements(p_verify->'items') x where x->>'item' = 'money_moved_as_approved';
  v_app := (v_money->>'approved_aed')::numeric; v_act := (v_money->>'actual_aed')::numeric;
  insert into public.refund_incident (transaction_id, refund_id, approved_aed, actual_aed, difference_aed, status, evidence)
  values (p_transaction_id, (p_verify->>'refund_id')::bigint, v_app, v_act, v_act - v_app, 'open', p_verify)
  returning id into v_inc;
  -- (c) FIX BY TYPE, then seal so no fix can close the incident before every fix exists.
  perform public.fn_ceo_incident_fix_round(v_inc, p_verify);
  update public.refund_incident set sealed = true where id = v_inc;
  -- (d) and (e): re-run the checklist; resume only when green; tell the founder.
  return jsonb_build_object('incident_id', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_review(p_refund_id bigint, p_trigger text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.refunds; v jsonb; v_cycle int; v_nonrem jsonb; v_rev bigint; v_dec bigint; x record; v_task bigint;
  v_tasks jsonb := '[]'::jsonb; v_rat text; v_deadline timestamptz; v_chase int; v_adv jsonb;
  v_wait boolean := false;   -- a check still being reasoned (23 Sep 2026)
  v_item text := 'refunds:' || p_refund_id; v_ids bigint[] := '{}'; v_cyc jsonb;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'reason', 'refund is ' || r.status || '; the CEO reviews only an open request'); end if;
  if r.refund_decision_id is not null then return jsonb_build_object('ok', true, 'outcome', 'already_approved', 'decision_id', r.refund_decision_id); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = r.id::text and a.status = 'pending') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_remediation');
  end if;
  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  v := public.fn_ceo_refund_checklist(r.transaction_id, 'approve', true);

  if (v->>'ok')::boolean then
    v_rat := 'Cycle ' || v_cycle || ': every pre-approval check passed ('
          || (select string_agg(i->>'item', ', ') from jsonb_array_elements(v->'items') i) || '). Evidence: refund_ceo_check for this transaction.';
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'approved', 'ceo', round(r.amount_fils / 100.0, 2), v_rat) returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(), decision_note = v_rat where id = r.id;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'approved', v_dec, p_trigger, true) returning id into v_rev;
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'approved', v_rat,
               jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'decision_id', v_dec), 'refund_ceo_review', v_rev::text);
    return jsonb_build_object('ok', true, 'outcome', 'approved', 'cycle', v_cycle, 'decision_id', v_dec, 'round', v_cyc);
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_nonrem from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false);
  if jsonb_array_length(v_nonrem) > 0 then
    v_rat := 'Declined, because these checks cannot be fixed and the refund is not paid: '
          || (select string_agg((i->>'item') || ' — ' || coalesce(i->>'reason', ''), '; ') from jsonb_array_elements(v_nonrem) i);
    v_adv := public.fn_ceo_refund_decline(r.id, v_rat, p_trigger, v->'failed');
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'withdrawn', left(v_rat, 3000),
               jsonb_build_object('refund_id', r.id, 'cycle', v_adv->'cycle', 'decision_id', v_adv->'decision_id', 'failed', v->'failed'),
               'refund_ceo_review', v_adv->>'review_id');
    return jsonb_build_object('ok', true, 'outcome', 'declined', 'cycle', v_adv->'cycle', 'reason', v_rat, 'round', v_cyc);
  end if;

  -- A CHECK THAT IS STILL BEING REASONED IS NOT A FAILURE (23 Sep 2026, founder_instruction 886-903).
  -- Under the model hold the off-platform notes wait in the CEO seat's reasoning queue. Counting that as a
  -- rejected cycle would hand work to nobody who can do it. So the refund rests, visible, with no cycle spent;
  -- the reasoned answer re-runs this review (fn_reason_apply_ceo__refund_off_platform).
  -- Only the unread note fails: the refund rests. Other remediable failures still go to their owners below.
  v_wait := exists (select 1 from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning');
  if v_wait and not exists (select 1 from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning',
      'held', (select jsonb_agg(i->'evidence') from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning'));
  end if;

  v_rat := 'Cycle ' || v_cycle || ': these checks still fail and go back to the seats that own them: '
        || (select string_agg((i->>'item') || ' (' || coalesce(i->>'reason', 'no reason recorded') || ')', '; ')
              from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning');

  -- THE LOOP GUARD (founder_instruction 1059), in place of the founder page after three cycles: after 4
  -- rejections the CEO approves, replaces or withdraws, with reasons. The escalated row records the stop, once:
  -- while the CEO's choice is owed a re-run answers that and writes nothing. (An approval above is never held by
  -- it: a refund whose checks now pass is approved, which settles what was owed.)
  if (public.fn_ceo_decision_next(v_item)->>'rejections')::int >= 4 then
    -- a check still being reasoned is not a rejection the CEO must act on: the refund rests, as above
    if v_wait then
      return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning', 'at_loop_guard', true);
    end if;
    if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                 and a.detail->>'type' = 'ceo.decision_owed' and a.detail->>'item_key' = v_item) then
      return jsonb_build_object('ok', false, 'outcome', 'awaiting_ceo_replace_or_withdraw', 'cycle', v_cycle - 1);
    end if;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'escalated', v->'failed', p_trigger, true) returning id into v_rev;
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'rejected', v_rat,
               jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'failed', v->'failed'), 'refund_ceo_review', v_rev::text);
    return jsonb_build_object('ok', false, 'outcome', 'awaiting_ceo_replace_or_withdraw', 'cycle', v_cycle, 'round', v_cyc);
  end if;

  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger)
  values (r.id, r.transaction_id, v_cycle, 'rejected', v->'failed', p_trigger) returning id into v_rev;
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  v_deadline := public.fn_add_working_days(now(), coalesce(v_chase, 3));
  for x in
    select i->>'owner' as owner, i->>'remedy_key' as rk, jsonb_agg(i->>'item') as checks, jsonb_agg(i) as items
      from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning' group by 1, 2 order by 1, 2
  loop
    v_task := public.fn_seat_handoff('ceo', x.owner, 'refund.remediate', 'refunds', r.id || ':c' || v_cycle || ':' || x.rk,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'cycle', v_cycle, 'review_id', v_rev,
                         'remedy_key', x.rk, 'checks', x.checks, 'items', x.items, 'deadline', v_deadline));
    v_tasks := v_tasks || jsonb_build_object('handoff_id', v_task, 'owner', x.owner, 'checks', x.checks);
    v_ids := v_ids || v_task;
  end loop;
  update public.refund_ceo_review set sealed = true, tasks = v_tasks where id = v_rev;
  v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'rejected', v_rat,
             jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'failed', v->'failed', 'tasks', v_tasks), 'refund_ceo_review', v_rev::text, v_ids);
  v_adv := public.fn_ceo_refund_loop_advance(r.id);
  return jsonb_build_object('ok', false, 'outcome', 'rejected', 'cycle', v_cycle, 'tasks', v_tasks, 'advance', v_adv, 'round', v_cyc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_refund_verify(p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_inc bigint;
begin
  -- An incident already open on this payment owns the re-verification: it re-runs the checklist and
  -- either closes (and resumes) or stays paused. A second incident on the same money is never opened.
  select id into v_inc from public.refund_incident i
   where i.transaction_id = p_transaction_id and i.status in ('open', 'paused') order by id desc limit 1;
  if v_inc is not null then
    return jsonb_build_object('incident', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
  end if;
  v := public.fn_ceo_refund_checklist(p_transaction_id, 'verify', true);
  if (v->>'ok')::boolean then return v; end if;
  return v || jsonb_build_object('incident', public.fn_ceo_refund_mismatch_playbook(p_transaction_id, v));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_report_answer_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v jsonb; n_answered int := 0; n_closed int := 0; n_failed int := 0; v_errors jsonb := '[]'::jsonb;
begin
  for r in select id from public.support_ceo_report where status = 'sent' order by id limit 200 loop
    begin
      v := public.fn_ceo_decide_report(r.id);
      n_answered := n_answered + (coalesce((v ->> 'ok')::boolean, false))::int;
    exception when others then
      n_failed := n_failed + 1;
      v_errors := v_errors || jsonb_build_object('report_id', r.id, 'error', left(sqlerrm, 200));
    end;
  end loop;
  for r in select id from public.support_ceo_report
            where status = 'accepted' and idempotency_key like 'it\_backup\_heartbeat:%' order by id loop
    v := public.fn_ceo_backup_heartbeat_decide(r.id);
    n_closed := n_closed + (v ->> 'decision' = 'completed')::int;
  end loop;
  -- a report the CEO could not answer is a finding, not a silence: the IT watch would page the founder for it
  if n_failed > 0 then
    perform public.fn_it_engineer_finding_upsert('ceo:report_answer_failed',
      n_failed || ' report(s) to the CEO raised in their decider and stay unanswered',
      'public.fn_ceo_report_answer_sweep', 'agent_facing', n_failed,
      jsonb_build_object('errors', v_errors, 'owner_seat', 'ceo'), '{}'::text[], array['why each decider raised'], 'ceo');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'every report to the CEO was answered (fn_ceo_report_answer_sweep)'
     where issue_key = 'ceo:report_answer_failed' and closed_at is null;
  end if;
  return jsonb_build_object('answered', n_answered, 'failed', n_failed, 'heartbeat_closed', n_closed,
    'still_sent', (select count(*) from public.support_ceo_report where status = 'sent'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_report_default_decide(p_report_id bigint, p_why text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; v_owner text;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  -- the seat that carries the work: the report's own owner when it names a live seat other than the CEO, else its source
  select o.role_id into v_owner from public.org_role o
   where o.status = 'active' and o.role_id = any(array[nullif(r.owner_role_id, 'ceo'), r.source_agent]) order by o.role_id = r.source_agent limit 1;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), next_review_at = now() + interval '24 hours',
         owner_role_id = coalesce(v_owner, r.owner_role_id),
         acceptance_receipt = 'ceo: accepted on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai. '
           || coalesce(v_owner, 'the reporting seat') || ' carries: ' || left(coalesce(r.requested_outcome, r.subject), 400)
           || '. No coded decider could close it (' || left(coalesce(p_why, 'no reason given'), 300) || '), so it is reviewed again at '
           || to_char((now() + interval '24 hours') at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai and closed only when its cause is measured gone.'
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'accepted', 'owner', coalesce(v_owner, r.owner_role_id), 'why', p_why);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_request_decision(p_case_id bigint, p_subject text, p_evidence jsonb, p_recommendation text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_r jsonb;
begin
  if coalesce(btrim(p_recommendation), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'a recommendation is required. Handing the CEO a question with no view is support declining to do its own work, and it is how a decision queue fills with items nobody has thought about.');
  end if;
  if p_evidence is null or p_evidence = '{}'::jsonb then
    return jsonb_build_object('ok', false, 'reason',
      'evidence is required. A decision asked for without the facts behind it cannot be made well, only quickly.');
  end if;

  v_r := public.fn_support_report_to_ceo(
    p_idempotency_key, 'elevated', p_subject, p_evidence,
    to_jsonb(array['investigated the case', 'checked the standing grant', 'formed a recommendation']),
    p_recommendation);

  return jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'report', v_r,
    'case_id', p_case_id,
    -- The case does NOT move to a resolved state here. That is the explicit v1.2 rule.
    'note', 'Routed to the CEO with evidence and a recommendation. The case stays open: it is not resolved by the CEO receiving it.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_review_applies(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_kind text; v_period date;
  rv public.ceo_review; v_review jsonb; v_notice jsonb; v_fields jsonb; v_gate jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_kind := r.subject->>'kind'; v_period := (r.subject->>'period')::date;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  select * into rv from public.ceo_review where kind = v_kind and period = v_period for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no review row'); end if;
  if rv.decided_at is not null then return jsonb_build_object('applied', true, 'already', v_kind || ' ' || v_period); end if;
  select coalesce(jsonb_object_agg(k, v->>'value'), '{}'::jsonb) into v_fields from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v);

  -- THE CHALLENGE (narrowed 24 Sep 2026, it_engineer): only a call that goes to the founder - a pricing proposal or
  -- "tell the founder" - is challenged by the accountant on a model of another family. An internal verdict is one call.
  -- A PRICING CHANGE IS HIGH STAKES (29 Sep 2026, instruction 1009): it goes to the founder only once the accountant agreed on
  -- another family, or, while the model hold is on, at once with the review owed.
  if v_kind = 'pricing_monitor' and v_choice = 'propose_change' then
    v_gate := public.fn_high_stakes_gate('pricing_change', 'ceo', 'ceo_review', v_kind || ':' || v_period,
      'Challenge the chief executive''s pricing call before it reaches the founder.',
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000),
                         'founder_detail', left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)),
      nullif(p_result->>'model', ''), 'agent_reasoning');
    v_review := v_gate;
  elsif v_choice in ('propose_change', 'tell_founder') then
    v_review := public.fn_seat_duty_cross_review('ceo.' || v_kind, 'ceo', 'accountant',
      case v_kind when 'management_review' then 'Challenge the chief executive''s reading of the company''s week.'
                  when 'pricing_monitor' then 'Challenge the chief executive''s pricing call before it reaches the founder.'
                  else 'Challenge the chief executive''s response to the revenue forecast.' end,
      -- seat_deliberation.evidence is capped at 60,000 characters; a week that outgrows it is passed as text, cut.
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
      p_result, 'ceo_review', v_kind || ':' || v_period);
  end if;
  update public.ceo_review set decision = v_choice, fields = v_fields, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', review = v_review, decided_at = now()
   where kind = v_kind and period = v_period;

  -- A pricing proposal still waiting for the accountant reaches the founder when the accountant agrees (trg_high_stakes_review).
  if (v_kind = 'pricing_monitor' and v_choice = 'propose_change' and coalesce((v_gate->>'proceed')::boolean, false))
     or (v_kind = 'target_forecast' and v_choice = 'tell_founder') then
    v_notice := public.fn_ceo_review_tells_founder(v_kind, v_period,
      case when v_kind = 'pricing_monitor' then 'CEO pricing proposal (evidence-based) for the week of ' || v_period
           else 'CEO: the AED 1M revenue forecast needs your decision (week of ' || v_period || ')' end,
      left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)
        || E'\n\nThe accountant is challenging this on a model of another family (seat_deliberation '
        || coalesce(v_review->>'deliberation_id', 'not opened: ' || coalesce(v_review->>'error', v_review->>'reason', '?')) || ').',
      case when v_kind = 'pricing_monitor' then 'founder_brief' else 'business_health_at_risk' end);
  end if;
  return jsonb_build_object('applied', true, 'kind', v_kind, 'period', v_period, 'choice', v_choice, 'review', v_review, 'founder', v_notice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_review_one_answered_improvement(p_handoff_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; v_why text; v_cyc jsonb; v_receipt text;
begin
  select a.id, a.agent, a.evidence, a.detail, i.id imp_id, i.status imp_status, i.seat imp_seat, i.task_id, i.done_evidence
    into h
    from public.agent_actions a
    left join public.ceo_improvement i on i.handoff_id = a.id
   where a.id = p_handoff_id and a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.improvement'
     and a.detail ? 'replied_at'
   for update of a;
  if not found then return jsonb_build_object('reviewed', false); end if;
  v_why := case
    when h.imp_status in ('done', 'dropped') then null
    when coalesce(h.evidence->>'accepted', '') <> 'true' then 'the answer does not accept the improvement'
    when h.evidence->>'seat' is distinct from h.agent or h.imp_seat is distinct from h.agent then 'answered by a seat other than the one asked'
    end;
  -- At the loop guard the CEO owes a replace-or-withdraw: a later answer that deserves it is still approved (which
  -- settles what was owed), but one that does not is not returned a fifth time.
  if h.detail ? 'decision_owed' and v_why is not null then
    return jsonb_build_object('reviewed', false, 'waiting', 'the CEO replaces or withdraws improvement #' || h.imp_id);
  end if;
  if h.imp_id is null then
    -- Nothing to review: no improvement carries it. Returning it (as before) asked the seat to answer nothing, and
    -- the handler accepts again, for ever; the CEO closes it with that receipt instead.
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object('verified_by', 'ceo', 'reviewed_at', now(),
      'receipt', 'Closed by the CEO: no ceo_improvement carries this handoff, so there is nothing for the seat to answer.'));
    perform set_config('qd.handoff_closer', '', true);
    return jsonb_build_object('reviewed', true, 'closed', true, 'orphan', true);
  end if;
  if v_why is null then
    v_receipt := case when h.imp_status in ('done', 'dropped')
                      then format('The CEO closes this answer because improvement #%s is already %s: %s', h.imp_id, h.imp_status, coalesce(h.done_evidence, 'no evidence recorded'))
                      else format('Reviewed by the CEO: %s accepted improvement #%s. The work is tracked on ceo_task #%s and closed by the CEO sweep when its source recovers.',
                                  h.agent, h.imp_id, coalesce(h.task_id::text, 'none')) end;
    v_cyc := public.fn_ceo_decide('ceo_improvement', 'ceo_improvement:' || h.imp_id, h.agent, 'approved', v_receipt,
               jsonb_build_object('improvement_id', h.imp_id, 'handoff_id', h.id, 'answer', left(h.evidence::text, 8000)), 'agent_actions',
               h.id || ':replied:' || (h.detail->>'replied_at'));
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(h.id, h.evidence || jsonb_build_object(
      'verified_by', 'ceo', 'reviewed_at', now(), 'improvement_id', h.imp_id, 'receipt', v_receipt, 'round', v_cyc));
    perform set_config('qd.handoff_closer', '', true);
    return jsonb_build_object('reviewed', true, 'closed', true, 'round', v_cyc);
  end if;
  v_cyc := public.fn_ceo_decide('ceo_improvement', 'ceo_improvement:' || h.imp_id, h.agent, 'rejected',
             'The CEO returned the answer to improvement #' || h.imp_id || ' because ' || v_why,
             jsonb_build_object('improvement_id', h.imp_id, 'handoff_id', h.id, 'answer', left(h.evidence::text, 8000)), 'agent_actions',
             h.id || ':replied:' || (h.detail->>'replied_at'), array[h.id]);
  if coalesce((v_cyc->>'round_limit')::boolean, false) then
    update public.agent_actions set detail = detail || jsonb_build_object('decision_owed', v_cyc->'decision_owed_handoff') where id = h.id;
    return jsonb_build_object('reviewed', true, 'decision_owed', v_cyc);
  end if;
  update public.agent_actions
     set detail = (detail - 'replied_at') || jsonb_build_object('returned', jsonb_build_object('at', now(), 'by', 'ceo', 'reason', v_why, 'round', v_cyc))
   where id = h.id;
  perform public.fn_seat_handoff_event(h.id, 'returned');
  return jsonb_build_object('reviewed', true, 'returned', true, 'reason', v_why, 'round', v_cyc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_review_tells_founder(p_kind text, p_period date, p_event text, p_detail text, p_mail_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; a public.agent_actions;
begin
  -- customer_support is the one sender; the founder path honours app.qd_stub_founder_notify (a probe never reaches him).
  v_id := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_review', p_kind || ':' || p_period,
    jsonb_build_object('recipient_role', 'founder', 'event', p_event, 'detail', p_detail, 'level', 'info',
                       'kind', p_mail_kind, 'dedupe_key', 'ceo_review:' || p_kind || ':' || p_period));
  select * into a from public.agent_actions where id = v_id;
  update public.ceo_review set founder_notice = jsonb_build_object('handoff_id', v_id, 'status', a.status, 'evidence', a.evidence)
   where kind = p_kind and period = p_period;
  return jsonb_build_object('handoff_id', v_id, 'status', a.status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_review_week()
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select date_trunc('week', (now() at time zone 'Asia/Dubai'))::date $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_reviews_answered_improvements()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; v jsonb; n_closed int := 0; n_returned int := 0; n_owed int := 0; v_failed jsonb := '[]'::jsonb;
begin
  for h in select a.id from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.improvement'
              and a.detail ? 'replied_at'
            order by a.id loop
    -- one answer that cannot be decided is reported and left for the next run; it never holds the others back
    begin
      v := public.fn_ceo_review_one_answered_improvement(h.id);
    exception when others then
      v_failed := v_failed || jsonb_build_object('handoff_id', h.id, 'error', left(sqlerrm, 300));
      continue;
    end;
    n_closed := n_closed + coalesce((v->>'closed')::boolean, false)::int;
    n_returned := n_returned + coalesce((v->>'returned')::boolean, false)::int;
    n_owed := n_owed + (v ? 'decision_owed')::int;
  end loop;
  return jsonb_build_object('closed', n_closed, 'returned', n_returned, 'decision_owed', n_owed, 'failed', v_failed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_revision_applies(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; a public.agent_actions; v_choice text; v_f jsonb; v_problem text; v jsonb;
  d public.seat_deliberation; e public.ceo_experiment; v_model text; v_target numeric; v_days int; v_revised jsonb;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_f := public.fn_ambition_fields(p_result);
  -- a round the CEO has already left takes no revision (checked first, so a stale answer is never re-reasoned)
  select * into a from public.agent_actions where id = (r.subject->>'handoff_id')::bigint and kind = 'handoff';
  if a.id is null or a.status <> 'pending' then
    return jsonb_build_object('applied', true, 'already', 'the CEO has moved on from this round');
  end if;
  -- A revision answers the CEO's reasons; an empty one is not a resubmission and is reasoned again.
  v_problem := public.fn_ceo_reasons_problem(coalesce(v_f->>'answers', '') || ' ' || coalesce(p_result->>'answer', ''));
  if v_problem is not null then
    raise exception using errcode = 'check_violation', message = 'UNANSWERED_REVISION: a revision answers the CEO''s reasons: ' || v_problem;
  end if;
  v_model := coalesce((select m.model_id from public.model_registry m where m.model_id = p_result->>'model'), 'deterministic');

  if a.detail->>'path' = 'seat_deliberation' then
    select * into d from public.seat_deliberation where id = (a.detail->'version'->>'deliberation_id')::bigint;
    -- a deliberation that has no round left (opened before the five-round rule, or at its cap) cannot take the
    -- revision: the CEO is owed the choice instead of the seat's answer failing on every retry
    if d.round >= d.max_rounds then
      v := jsonb_build_object('decision_owed', public.fn_ceo_decision_owe('seat_deliberation', a.detail->>'item_key', a.agent,
             coalesce((a.detail->>'generation')::int, 1), 'revised with no round left in its deliberation (' || d.round || ' of ' || d.max_rounds || ')',
             a.detail->>'reasons', a.detail->'version'));
      update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id,
               'answers', left(coalesce(v_f->>'answers', ''), 3000), 'no_round_left', v) where id = a.id;
      return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'resubmission', v);
    end if;
    v_revised := d.proposal || jsonb_build_object('revision', coalesce(v_f->>'revision', p_result->>'answer'), 'answers_to_the_ceo', v_f->>'answers',
                                                  'revision_choice', v_choice, 'revises_round', a.detail->'round');
    if length(v_revised::text) > 28000 then   -- seat_deliberation.proposal holds 30,000 characters
      v_revised := jsonb_build_object('previous_proposal_cut', left(d.proposal::text, 6000),
        'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 12000), 'answers_to_the_ceo', left(v_f->>'answers', 4000),
        'revision_choice', v_choice, 'revises_round', a.detail->'round');
    end if;
    v := public.fn_seat_deliberation_revise(d.id, v_revised, v_model);
  elsif a.detail->>'path' = 'ceo_experiment' then
    select * into e from public.ceo_experiment where id = (a.detail->'version'->>'experiment_id')::bigint;
    v_target := case when coalesce(v_f->>'target', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_f->>'target')::numeric else e.target end;
    v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;
    v := jsonb_build_object('experiment_id', public.fn_ceo_experiment_propose(e.proposed_by, e.key,
           coalesce(nullif(btrim(v_f->>'hypothesis'), ''), e.hypothesis), e.metric_key, e.metric_definition, e.baseline, e.baseline_note,
           v_target, e.direction, coalesce(nullif(btrim(v_f->>'approach'), ''), e.approach), e.starts_on, v_days));
  else
    raise exception 'no revision route for a % item (%)', coalesce(a.detail->>'path', '?'), a.detail->>'item_key';
  end if;
  update public.agent_actions
     set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id, 'choice', v_choice,
                      'answers', left(coalesce(v_f->>'answers', ''), 3000), 'model', v_model, 'resubmission', v),
         detail = detail || jsonb_build_object('awaiting', 'the CEO decides the resubmitted round')
   where id = a.id;
  return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'choice', v_choice, 'resubmission', v);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_root_cause_applies(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text; v_f jsonb; v_task bigint; v_hid bigint; v_review jsonb;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_task := (r.subject->>'task_id')::bigint; v_hid := nullif(r.subject->>'handoff_id', '')::bigint;
  v_f := public.fn_ambition_fields(p_result);
  update public.ceo_task
     set state = case when state = 'open' then 'working' else state end,
         evidence = left(coalesce(evidence || E'\n\n', '') || format(E'Root cause from %s (%s): %s\nCorrective action: %s\nRecovery by: %s',
                           r.seat, v_choice, coalesce(v_f->>'root_cause', '?'), coalesce(v_f->>'corrective_action', '?'), coalesce(v_f->>'recovery_by', '?')), 8000)
   where task_id = v_task;
  if v_hid is not null and exists (select 1 from public.agent_actions where id = v_hid and status = 'pending') then
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('kind', 'ceo.root_cause', 'verified_by', 'ceo', 'root_cause', v_choice, 'fields', v_f, 'held_id', p_id));
    perform set_config('qd.handoff_closer', '', true);
  end if;
  -- the other side reads it on a model of another family: the CEO for a seat's answer, the accountant for the CEO's own
  v_review := public.fn_seat_duty_cross_review(r.seat || '.root_cause', r.seat, case when r.seat = 'ceo' then 'accountant' else 'ceo' end,
    'Challenge this root cause and corrective action for a metric behind the company''s target path.',
    jsonb_build_object('miss', r.request->'context'->'case'), jsonb_build_object('call', v_choice, 'fields', v_f,
    'reasoning', left(coalesce(p_result->>'answer', ''), 3000)), p_result, 'ceo_task', v_task::text);
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, situation, decision, reasoning, outcome, finalised, lessons, opened_at)
  values (r.seat, 'target_miss', 'ceo_task', v_task::text,
          left(format('%s behind the base-case path: %s', r.subject->>'metric', r.request->'context'->'case'), 4000),
          v_choice, left(coalesce(p_result->>'answer', ''), 4000), null, false,
          case when coalesce(v_f->>'corrective_action', '') <> '' then array[v_f->>'corrective_action'] else '{}'::text[] end, r.created_at)
  on conflict (source_table, source_id) do update set decision = excluded.decision, reasoning = excluded.reasoning, lessons = excluded.lessons, updated_at = now();
  return jsonb_build_object('applied', true, 'task', v_task, 'root_cause', v_choice, 'review', v_review);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_root_cause_ask(p_seat text, p_task bigint, p_miss jsonb, p_handoff bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_held bigint;
begin
  v_held := public.fn_seat_duty_reason(p_seat, p_seat || '.root_cause',
    'A metric you own is behind the company''s target path beyond its tolerance. As the owner, find the root cause from '
      || 'the evidence, not the symptom, and say what you will change and by when the measure recovers.',
    ('[{"id":"demand_short","meaning":"not enough requests or buyers are reaching the platform"},'
    || '{"id":"supply_short","meaning":"not enough verified, responsive suppliers in the trades that are asked for"},'
    || '{"id":"conversion","meaning":"requests, quotes or comparisons are not converting at the planned rate"},'
    || '{"id":"execution","meaning":"one of our own duties failed, slipped or was not done"},'
    || '{"id":"instrumentation","meaning":"the measure is wrong or does not capture what happened"},'
    || '{"id":"plan_assumption","meaning":"the plan''s assumption for this metric is wrong and the path should be revised"}]')::jsonb,
    p_miss || jsonb_build_object('task_id', p_task, 'last_14_days', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'expected', expected, 'actual', actual, 'status', status) order by day), '[]'::jsonb)
                                                                    from public.target_daily_verdict where metric_key = p_miss->>'metric' and day > current_date - 14)),
    jsonb_build_object('task_id', p_task, 'handoff_id', p_handoff, 'metric', p_miss->>'metric'), 'root_cause:' || p_seat || ':' || p_task);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'root_cause', 'question', 'the root cause, with the evidence it rests on'),
    jsonb_build_object('key', 'corrective_action', 'question', 'what you will change'),
    jsonb_build_object('key', 'recovery_by', 'question', 'the date the measure is back within tolerance (YYYY-MM-DD)')));
  return v_held;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_sales_engineer_report_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.support_ceo_report; req public.agent_actions; h public.agent_actions;
  v_addr text; v_h bigint; v_receipt text; v_decision text; v_key text; v_what text; v_acc jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id and source_agent = 'sales_engineer' for update;
  if not found or r.status <> 'sent' then
    return jsonb_build_object('ok', false, 'reason', 'no open sales engineer report ' || p_report_id);
  end if;

  if r.idempotency_key like 'handoff\_unanswered:%' then
    select * into h from public.agent_actions where id = (r.verified_evidence->>'handoff_id')::bigint;
    v_key := 'monitor:handoff_unanswered:' || coalesce(h.detail->>'type', 'unknown') || ':' || coalesce(h.agent, 'unknown');
    perform public.fn_it_engineer_finding_upsert(v_key,
      'The ' || coalesce(h.agent, 'receiving seat') || ' did not answer "' || coalesce(h.detail->>'type', '?') || '" from the sales engineer within its window',
      'public.' || coalesce((select k.handler from public.seat_handoff_kind k
                              where k.type = h.detail->>'type' and k.from_seat = h.detail->>'from' and k.to_seat = h.agent), 'fn_seat_handoff_act'),
      'agent_facing', 1,
      jsonb_build_object('owner_seat', h.agent, 'handoff_id', h.id, 'report_id', r.id, 'handoff_status', h.status, 'error', h.detail->>'error'),
      '{}'::text[], array['why the handler did not answer handoff ' || coalesce(h.id::text, '?')], 'fn_ceo_sales_engineer_report_decide');
    v_decision := 'defect_raised';
    v_receipt := 'ceo: decided. "' || coalesce(h.detail->>'type', '?') || '" (handoff ' || coalesce(h.id::text, '?') || ') went unanswered past its window, '
      || 'so the handler is at fault: raised as IT finding ' || v_key || ', which the IT loop hands to the ' || coalesce(h.agent, 'owning seat')
      || ' and re-verifies; it clears when the next conversation of this kind works.';

  elsif r.idempotency_key not like 'delivery\_undelivered:%' then
    v_decision := 'read';
    v_receipt := 'ceo: read the sales engineer''s ' || r.severity || ' report "' || left(r.subject, 140) || '" with its evidence.';

  else
    select * into req from public.agent_actions where id = (r.verified_evidence->>'request_id')::bigint;
    v_addr := coalesce(req.detail->'prepared'->>'to_email', req.detail->>'to_email', '');
    v_what := coalesce(req.detail->>'msg_type', substring(r.subject from '^A (\S+)'), 'notice');
    if req.id is null then
      v_decision := 'need_not_go_request_gone';
      v_receipt := 'ceo: decided it need not go. Request ' || coalesce(r.verified_evidence->>'request_id', '?') || ' (a ' || v_what
        || ') no longer exists: its words and its address are gone, so nothing can be resent.';
    elsif req.detail ? 'remediate_handoff_id' then
      v_decision := 'part_of_remediation';
      v_receipt := 'ceo: read. This is the resend for remediation handoff ' || (req.detail->>'remediate_handoff_id')
        || ', and it is decided there.';
    elsif req.detail::text ilike '%ZZ DEMO%' or v_addr ilike '%@example.invalid' then
      v_decision := 'need_not_go_fixture';
      v_receipt := 'ceo: decided it need not go. A ZZ DEMO fixture ' || v_what || ' addressed to ' || coalesce(nullif(v_addr, ''), 'a fixture')
        || ': example.invalid is never delivered, and no real person was meant to receive it.';
    elsif coalesce(req.detail->>'recipient_role', '') not in ('customer', 'supplier') then
      v_decision := 'need_not_go_internal';
      v_receipt := 'ceo: decided it need not go. A ' || v_what || ' addressed to ''' || coalesce(req.detail->>'recipient_role', 'nobody')
        || ''', which is no seat and not a kind the founder is emailed; the CEO has read it here, which is the delivery it needed.';
    else
      v_h := public.fn_seat_handoff('ceo', 'sales_engineer', 'delivery.remediate', 'support_ceo_report', r.id::text,
        jsonb_build_object('report_id', r.id, 'request_id', req.id, 'msg_type', v_what,
                           'recipient_role', req.detail->>'recipient_role', 'result', r.verified_evidence->>'result'));
      v_decision := 'remediate';
      v_receipt := 'ceo: decided. The ' || v_what || ' did not reach the ' || (req.detail->>'recipient_role') || ' ('
        || coalesce(r.verified_evidence->>'result', '?') || '): the sales engineer reaches them on another channel on file (handoff '
        || v_h || '), and the CEO closes it when the resend is confirmed or no channel exists.';
    end if;
  end if;

  v_acc := public.fn_ceo_accept_support_report(r.id, v_receipt, v_decision);
  if not coalesce((v_acc->>'ok')::boolean, false) then
    raise exception 'fn_ceo_sales_engineer_report_decide: report % was not accepted: %', r.id, v_acc->>'reason';
  end if;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', v_decision, 'remediation_handoff', v_h);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_sales_engineer_reports_sweep(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; h public.agent_actions; rs public.agent_actions; v jsonb; k text; v_verdict text; v_window interval;
        n jsonb := '{}'::jsonb; n_closed int := 0; n_wait int := 0; v_err jsonb := '[]'::jsonb;
begin
  for r in select s.id, s.source_agent from public.support_ceo_report s
            where s.status = 'sent'
              and (s.source_agent = 'sales_engineer'
                   or (s.source_agent = 'accountant'
                       and (s.idempotency_key like 'notice\_undelivered:%' or s.idempotency_key like 'notice\_unverified:%')))
              -- a report whose decision raised waits an hour, so it cannot hold the head of the queue
              and (s.last_delivery_error is null or s.next_review_at <= now())
            order by s.id limit greatest(coalesce(p_limit, 100), 1) loop
    begin
      v := case when r.source_agent = 'accountant' then public.fn_ceo_accountant_notice_report_decide(r.id)
                else public.fn_ceo_sales_engineer_report_decide(r.id) end;
      k := coalesce(v->>'decision', 'not_decided');
      n := n || jsonb_build_object(k, coalesce((n->>k)::int, 0) + 1);
    exception when others then
      v_err := v_err || jsonb_build_object('report_id', r.id, 'error', left(sqlerrm, 300));
      update public.support_ceo_report
         set last_delivery_error = left('ceo decision failed: ' || sqlerrm, 300), next_review_at = now() + interval '1 hour'
       where id = r.id;
    end;
  end loop;

  select reply_within into v_window from public.seat_handoff_kind
   where type = 'delivery.remediate' and from_seat = 'ceo' and to_seat = 'sales_engineer';
  v_window := coalesce(v_window, interval '24 hours');
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'delivery.remediate' and detail->>'from' = 'ceo'
              and status in ('pending', 'failed') order by id loop
    begin
      rs := null;
      if (h.evidence->>'resend_request_id') is not null then
        select * into rs from public.agent_actions where id = (h.evidence->>'resend_request_id')::bigint;
      end if;
      v_verdict := case
        when h.status = 'failed' then
          'unreachable: the sales engineer could not act (' || coalesce(h.detail->>'error', 'no error recorded') || ')'
        when rs.id is not null and rs.detail->>'loop' in ('confirmed', 'handled_by_the_ladder') then
          'reached: the resend by ' || coalesce(h.evidence->>'channel', '?') || ' was confirmed (request ' || rs.id || ')'
        when rs.id is not null and rs.detail ? 'loop' then
          'unreachable: the resend by ' || coalesce(h.evidence->>'channel', '?') || ' ended ' || (rs.detail->>'loop') || ' (request ' || rs.id || ')'
        when rs.id is null and h.detail ? 'replied_at' then
          'unreachable: ' || coalesce(h.evidence->>'reply', 'no other channel on file')
        when now() > h.created_at + v_window then
          'unreachable: no outcome within ' || v_window
      end;
      if v_verdict is null then n_wait := n_wait + 1; continue; end if;
      perform set_config('qd.handoff_closer', 'ceo', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'ceo', 'verified_at', now(), 'verdict', v_verdict));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('remediation_handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  return jsonb_build_object('decided', n, 'remediations_closed', n_closed, 'remediations_waiting', n_wait, 'errors', v_err,
    'still_unread', (select count(*) from public.support_ceo_report where source_agent = 'sales_engineer' and status = 'sent'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_seat_audit(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_q date := date_trunc('quarter', p_at at time zone 'Asia/Dubai')::date; v_health jsonb := public.fn_seat_duty_health();
  s record; v_n int; v_ok int; v_rate numeric; v_duties int; v_failing int; v_late int; v_missed int;
  v_short text[]; v_m jsonb; v_id bigint; n_below int := 0; n_closed int := 0; r record;
begin
  if exists (select 1 from public.ceo_seat_audit where quarter = v_q) then
    return jsonb_build_object('quarter', v_q, 'already', true);
  end if;

  for s in select role_id from public.org_role where status = 'active' and role_id <> 'ceo' order by role_id loop
    select count(*), count(*) filter (where verdict = 'correct') into v_n, v_ok
      from public.seat_knowledge_exam where seat = s.role_id and graded_at > p_at - interval '90 days';
    v_rate := case when v_n >= 5 then round(v_ok::numeric / v_n, 3) end;
    select count(*) into v_duties from public.seat_duty where owner_seat = s.role_id and enabled;
    select count(*) into v_failing from jsonb_array_elements(v_health) h where h->>'owner_seat' = s.role_id;
    select count(*) into v_late from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = s.role_id and a.status = 'pending' and a.created_at < p_at - k.reply_within;
    select count(*) into v_missed from public.ceo_seat_directive
     where seat = s.role_id and status = 'missed' and month >= (v_q - interval '3 months')::date;

    v_short := '{}';
    if v_rate is not null and v_rate < 0.80 then
      v_short := v_short || format('knowledge %s%% correct on %s graded items in 90 days: retrain on the items missed (IT refiled each one for re-research) until the rate is back over 80%%', round(v_rate * 100), v_n);
    end if;
    if v_failing > 0 then
      v_short := v_short || format('%s of %s duties failing or overdue now: repair each until it runs on its clock', v_failing, v_duties);
    end if;
    if v_late > 0 then
      v_short := v_short || format('%s handoffs open past their reply window: answer each, and say why it was late', v_late);
    end if;
    if v_missed >= 2 then
      v_short := v_short || format('%s monthly targets missed in the last quarter: name the step that did not convert and change it', v_missed);
    end if;
    v_m := jsonb_build_object('knowledge_graded_90d', v_n, 'knowledge_correct_90d', v_ok, 'knowledge_rate', v_rate,
      'duties', v_duties, 'duties_failing', v_failing, 'handoffs_late', v_late, 'months_missed', v_missed);

    v_id := null;
    if cardinality(v_short) > 0 then
      v_id := public.fn_ceo_improvement_open('seat_audit', v_q || ':' || s.role_id, s.role_id,
        format('Quarterly audit of %s for the quarter starting %s: below the senior bar. ', s.role_id, to_char(v_q, 'DD Mon YYYY'))
          || array_to_string(v_short, '; ') || '. Due before the next quarterly audit.',
        v_m || jsonb_build_object('quarter', v_q));
      n_below := n_below + 1;
    end if;
    insert into public.ceo_seat_audit (quarter, seat, measures, shortfalls, below_bar, improvement_id)
    values (v_q, s.role_id, v_m, v_short, cardinality(v_short) > 0, v_id);
  end loop;

  -- last quarter's audit improvements close when the seat is back at the bar this quarter
  for r in select i.id, i.seat from public.ceo_improvement i
            where i.source_kind = 'seat_audit' and i.status in ('open', 'assigned') and (i.evidence->>'quarter')::date < v_q loop
    if exists (select 1 from public.ceo_seat_audit a where a.quarter = v_q and a.seat = r.seat and not a.below_bar) then
      perform public.fn_ceo_improvement_close(r.id, format('%s is back at the bar in the audit of the quarter starting %s.', r.seat, v_q));
      n_closed := n_closed + 1;
    end if;
  end loop;
  return jsonb_build_object('quarter', v_q, 'seats', (select count(*) from public.ceo_seat_audit where quarter = v_q),
                            'below_bar', n_below, 'closed', n_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_seat_audit_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_seat_audit(now()) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_seat_board(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_from timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days, 7)));
  j jsonb;
begin
  select jsonb_build_object(
    'window_days', greatest(1, coalesce(p_days, 7)),
    'since', v_from,
    'seats', (
      select jsonb_object_agg(s.seat, jsonb_build_object(

        -- WHAT IT DID: every run, and every run that failed. Same source for all six, so the
        -- comparison between seats is honest.
        'runs',        (select count(*) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat and r.started_at >= v_from),
        'errors',      (select count(*) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat
                           and r.status = 'error' and r.started_at >= v_from),
        'last_seen',   (select max(r.started_at) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat),

        -- WHAT IS WAITING ON IT: work assigned and not finished. This is the half the CEO had no
        -- sight of at all.
        'open_tasks',  (select count(*) from org_tasks t
                         where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),
        'oldest_open_task_days', (select round(extract(epoch from (now() - min(t.created_at)))/86400)
                         from org_tasks t
                        where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),

        -- WHAT IT FILED TO THE CEO, and whether the CEO has picked it up. An unread report is the
        -- CEO's own backlog, not the seat's.
        --
        -- THE NAME OF THIS FIGURE WAS WRONG AND THE FOUNDER CAUGHT IT. It read
        -- 'awaiting_my_acceptance', and on 9 September he read the board and asked "wait is the CEO
        -- basically waiting to approve the accountant report" -- a fair reading of that phrase, and
        -- not what the number means. Measured: three routines read accepted_at
        -- (fn_ceo_weekly_figures, fn_ceo_seat_board, fn_customer_mandatory_check) and all three only
        -- COUNT it for display. Nothing gates on it. Both accountant reports say in their own
        -- requested_outcome field "NOTHING IS REQUESTED", and one had already reached the founder.
        -- It is a read receipt, not an approval queue, and the label now says which. A number whose
        -- name implies work is blocked, on a board built so the chief executive knows what is
        -- waiting on whom, is worse than no number.
        'filed_to_ceo',    (select count(*) from support_ceo_report c where c.source_agent = s.seat),
        'filed_but_not_yet_read_by_ceo', (select count(*) from support_ceo_report c
                                    where c.source_agent = s.seat and c.accepted_at is null),

        -- WHAT IT ACHIEVED: the question this seat's own job answers.
        'achievement', case s.seat
          when 'accountant' then jsonb_build_object(
            'expense_records_with_a_document', (select count(*) from expense_entries where doc_path is not null),
            'journals_posted',                 (select count(*) from gl_journal where status = 'posted'),
            'weekly_reports_delivered',        (select count(*) from accountant_weekly_report where founder_submitted_at is not null))
          when 'customer_support' then jsonb_build_object(
            'conversations_answered',          (select count(*) from assistant_logs where created_at >= v_from),
            'questions_it_could_not_answer',   (select count(*) from sales_knowledge_gap where status = 'open'),
            'supplier_contacts_logged',        (select count(*) from supplier_response_watch))
          when 'sales_engineer' then jsonb_build_object(
            'assists_given',                   (select count(*) from sales_decision_log where created_at >= v_from),
            'quotes',                          (select count(*) from quotes),
            'comparisons',                     (select count(*) from quote_comparisons))
          when 'it_engineer' then jsonb_build_object(
            'findings_open',                   (select count(*) from it_watch_finding where status = 'open'),
            'findings_closed',                 (select count(*) from it_watch_finding where status = 'resolved'),
            'alerts_delivered',                (select count(*) from notifications
                                                 where kind like 'it_%' and status = 'sent'))
          -- 22 Sep 2026 (founder instruction 721): the marketing seat reports the overall picture to the CEO.
          -- Its reports are READ, never approved; 'read_by_ceo' counts the CEO's read receipts.
          when 'marketing' then jsonb_build_object(
            'reports_filed',                   (select count(*) from marketing_report),
            'reports_read_by_ceo',             (select count(*) from marketing_report where read_by_ceo_at is not null),
            'ad_spend_reported_aed',           (select coalesce(sum(amount_aed), 0) from ad_spend_reported),
            'latest_report',                   (select jsonb_build_object('date', m.report_date, 'headline', m.figures->'headline',
                                                                          'no_data_yet', m.no_data_yet)
                                                  from marketing_report m order by m.report_date desc limit 1))
          when 'ceo' then jsonb_build_object(
            'approvals_decided',               (select count(*) from ceo_approval),
            'reports_accepted',                (select count(*) from support_ceo_report where accepted_at is not null),
            'weekly_reports_delivered',        (select count(*) from ceo_weekly_report where founder_submitted_at is not null))
          else '{}'::jsonb end))
      from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'basis', 'Every figure is a count of rows that exist, over the window for activity and lifetime '
          || 'for achievement. Nothing here is scored or rated. A zero means the thing has not '
          || 'happened, not that nobody counted it — the seats were created 7-9 September 2026 and '
          || 'the company has taken no revenue yet.'
  ) into j;
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_self_review()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'ceo') $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_standing()
 RETURNS TABLE(domain text, decision_key text, authority text, reading text, reading_kind text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
  v text;
begin
  for r in select d.domain, d.decision_key, d.authority, d.measure, d.measure_sql
             from public.ceo_decision d
            where d.active
            order by d.domain, d.decision_key
  loop
    domain := r.domain; decision_key := r.decision_key; authority := r.authority;
    if r.measure_sql is null then
      reading := 'NOT INSTRUMENTED -- ' || r.measure;
      reading_kind := 'not_instrumented';
    else
      begin
        execute r.measure_sql into v;
        reading := coalesce(v, '(null)');
        reading_kind := 'measured';
      exception when others then
        -- An instrument that throws is not a zero either. It is a broken instrument, and it says so.
        reading := 'INSTRUMENT FAILED -- ' || sqlerrm;
        reading_kind := 'instrument_failed';
      end;
    end if;
    return next;
  end loop;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_strategy_measure(p_metric text, p_category text, p_from date, p_to date, p_include_demo boolean DEFAULT false)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case p_metric
    when 'inquiries' then (select count(*)::int from public.inquiries i left join public.customers c on c.id = i.customer_id
                            where i.category = p_category and (i.created_at at time zone 'Asia/Dubai')::date between p_from and p_to
                              and (p_include_demo or not coalesce(c.is_demo, false)))
    when 'suppliers_added' then (select count(*)::int from public.leads l join public.lead_category lc on lc.lead_id = l.id and lc.is_primary
                                  where lc.slug = p_category and (l.created_at at time zone 'Asia/Dubai')::date between p_from and p_to
                                    and (p_include_demo or not coalesce(l.is_demo, false)))
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_strategy_memo(p_month date DEFAULT NULL::date, p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_m date := date_trunc('month', coalesce(p_month, (v_today - interval '1 month')::date))::date; v_e date;
  f jsonb; c jsonb; v_bet jsonb; v_grade jsonb; prev public.ceo_strategy_memo; v_meas int; v_body text; v_n jsonb; v_base int;
begin
  if v_m >= date_trunc('month', v_today)::date then
    raise exception 'month % has not ended; the memo is written for a month that is over', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.ceo_strategy_memo where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already', true);
  end if;
  v_e := (v_m + interval '1 month')::date - 1;
  f := public.fn_ceo_strategy_memo_facts(v_m, p_include_demo);

  -- the bet (rule-based; see the header)
  select x into c from jsonb_array_elements(f->'categories') x where (x->>'requests')::int > 0
   order by (x->>'requests')::int desc, x->>'category' limit 1;
  if c is not null then
    v_base := (c->>'requests')::int;
    v_bet := jsonb_build_object('metric', 'inquiries', 'category', c->>'category', 'baseline', v_base);
  else
    select x into c from jsonb_array_elements(f->'categories') x where (x->>'suppliers_added')::int > 0
     order by (x->>'suppliers_added')::int - (x->>'suppliers_added_prior')::int desc, (x->>'suppliers_added')::int desc, x->>'category' limit 1;
    if c is null then
      select x into c from jsonb_array_elements(f->'categories') x order by (x->>'suppliers_on_file')::int desc, x->>'category' limit 1;
    end if;
    v_base := coalesce((c->>'suppliers_added')::int, 0);
    v_bet := jsonb_build_object('metric', 'suppliers_added', 'category', c->>'category', 'baseline', v_base);
  end if;
  v_bet := v_bet || jsonb_build_object('target', greatest(v_base + 1, ceil(v_base * 1.2)::int),
    'month', to_char((v_m + interval '1 month')::date, 'YYYY-MM'));
  v_bet := v_bet || jsonb_build_object('wording', format('In %s we focus on %s: %s from %s to at least %s.',
    to_char((v_m + interval '1 month')::date, 'Mon YYYY'), coalesce(v_bet->>'category', 'no category on file'),
    case v_bet->>'metric' when 'inquiries' then 'customer requests' else 'suppliers added' end, v_bet->>'baseline', v_bet->>'target'));

  -- the grading of last month's bet, measured by the same code over the month it was made for
  select * into prev from public.ceo_strategy_memo where month = (v_m - interval '1 month')::date;
  if prev.month is null then
    v_grade := jsonb_build_object('grade', 'none', 'note', 'no memo, so no bet, for ' || to_char((v_m - interval '1 month')::date, 'Mon YYYY'));
  else
    v_meas := public.fn_ceo_strategy_measure(prev.bet->>'metric', prev.bet->>'category', v_m, v_e, prev.include_demo);
    v_grade := prev.bet || jsonb_build_object('measured', v_meas,
      'grade', case when v_meas >= (prev.bet->>'target')::int then 'hit'
                    when v_meas > (prev.bet->>'baseline')::int then 'partial' else 'missed' end);
  end if;

  v_body := 'CEO STRATEGY MEMO - ' || to_char(v_m, 'FMMonth YYYY') || E'\n\n'
    || '1. MARKET CHANGES' || E'\n'
    || format('  Competitors watched %s. Pages that changed this month: %s. Competitors re-verified: %s. Relevant trends: %s.',
              f#>>'{market,competitors_watched}', jsonb_array_length(f#>'{market,competitor_pages_changed}'),
              jsonb_array_length(f#>'{market,competitors_verified}'), jsonb_array_length(f#>'{market,relevant_trends}')) || E'\n'
    || coalesce((select string_agg('  - ' || (x->>'competitor') || ' changed its ' || (x->>'page') || ' page (' || (x->>'on') || ')', E'\n')
                   from (select x from jsonb_array_elements(f#>'{market,competitor_pages_changed}') x limit 5) z) || E'\n', '')
    || coalesce((select string_agg('  - Trend: ' || (x->>'title') || coalesce(' - ' || (x->>'why'), ''), E'\n')
                   from jsonb_array_elements(f#>'{market,relevant_trends}') x) || E'\n', '')
    || E'\n' || '2. CATEGORY GROWTH (this month / month before)' || E'\n'
    || coalesce((select string_agg(format('  %-40s requests %s / %s, suppliers added %s / %s', x->>'category', x->>'requests', x->>'requests_prior',
                                          x->>'suppliers_added', x->>'suppliers_added_prior'), E'\n')
                   from (select x from jsonb_array_elements(f->'categories') x limit 5) z), '  no category on file') || E'\n\n'
    || '3. THE BET FOR ' || upper(to_char((v_m + interval '1 month')::date, 'FMMonth YYYY')) || E'\n'
    || '  ' || (v_bet->>'wording') || E'\n'
    || '  Measured by: ' || (v_bet->>'metric') || ' in ' || coalesce(v_bet->>'category', '-') || ', expected result ' || (v_bet->>'target') || '.' || E'\n\n'
    || '4. LAST MONTH''S BET' || E'\n'
    || case when v_grade->>'grade' = 'none' then '  ' || (v_grade->>'note')
            else format('  %s  Result %s against a target of %s (baseline %s): %s.', v_grade->>'wording', v_grade->>'measured',
                        v_grade->>'target', v_grade->>'baseline', upper(v_grade->>'grade')) end || E'\n\n'
    || 'Every figure is measured from the live tables at the moment of writing. The bet''s wording is rule-based while the model hold is on.';

  insert into public.ceo_strategy_memo (month, facts, bet, grading, wording_source, body, include_demo)
  values (v_m, f, v_bet, v_grade, 'rule_based (model hold on)', v_body, p_include_demo);

  v_n := public.fn_notify_founder(p_event => 'CEO strategy memo - ' || to_char(v_m, 'FMMonth YYYY'), p_detail => v_body,
                                  p_level => 'info', p_kind => 'ceo_strategy_memo',
                                  p_dedupe_key => 'ceo_strategy_memo:' || to_char(v_m, 'YYYY-MM') || case when p_include_demo then ':zz-demo' else '' end,
                                  p_owner_agent => 'ceo');
  update public.ceo_strategy_memo set notify = v_n where month = v_m;
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'bet', v_bet, 'grading', v_grade, 'notify', v_n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_strategy_memo_facts(p_month date, p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_pm date; v_pe date;
  v_changed jsonb; v_verified jsonb; v_trends jsonb; v_cats jsonb;
begin
  v_e := (v_m + interval '1 month')::date - 1; v_pm := (v_m - interval '1 month')::date; v_pe := v_m - 1;

  select coalesce(jsonb_agg(jsonb_build_object('competitor', c.name, 'page', z.page_kind, 'url', z.url, 'on', z.on_day) order by z.on_day), '[]'::jsonb)
    into v_changed
    from (select competitor_id, page_kind, url, (requested_at at time zone 'Asia/Dubai')::date on_day, content_hash,
                 lag(content_hash) over (partition by competitor_id, page_kind order by requested_at) prev_hash
            from public.competitor_scan where content_hash is not null) z
    join public.competitor c on c.id = z.competitor_id
   where z.on_day between v_m and v_e and z.prev_hash is not null and z.prev_hash <> z.content_hash;

  select coalesce(jsonb_agg(jsonb_build_object('competitor', name, 'kind', kind, 'threat', threat_level) order by name), '[]'::jsonb)
    into v_verified from public.competitor where verified_at between v_m and v_e;

  select coalesce(jsonb_agg(jsonb_build_object('title', title, 'why', why_it_matters, 'url', url) order by seen_at desc), '[]'::jsonb)
    into v_trends
    from (select * from public.marketing_trend where relevant and (seen_at at time zone 'Asia/Dubai')::date between v_m and v_e
           order by seen_at desc limit 5) t;

  select coalesce(jsonb_agg(x order by (x->>'requests')::int desc, (x->>'suppliers_added')::int desc, x->>'category'), '[]'::jsonb)
    into v_cats
    from (select jsonb_build_object('category', slug,
                   'suppliers_added', public.fn_ceo_strategy_measure('suppliers_added', slug, v_m, v_e, p_include_demo),
                   'suppliers_added_prior', public.fn_ceo_strategy_measure('suppliers_added', slug, v_pm, v_pe, p_include_demo),
                   'requests', public.fn_ceo_strategy_measure('inquiries', slug, v_m, v_e, p_include_demo),
                   'requests_prior', public.fn_ceo_strategy_measure('inquiries', slug, v_pm, v_pe, p_include_demo),
                   'suppliers_on_file', n) x
            from (select lc.slug, count(*) n from public.lead_category lc join public.leads l on l.id = lc.lead_id
                   where lc.is_primary and (p_include_demo or not coalesce(l.is_demo, false))
                   group by lc.slug) s) y;

  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_e,
    'market', jsonb_build_object('competitors_watched', (select count(*) from public.competitor where watched),
                                 'competitor_pages_changed', v_changed, 'competitors_verified', v_verified,
                                 'relevant_trends', v_trends),
    'categories', v_cats,
    'measured_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_supplier_target(p_at timestamp with time zone DEFAULT now(), p_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb := public.fn_ceo_supplier_target_status(p_at, p_demo); g jsonb := public.fn_every_category_has_ten_suppliers(p_demo);
  v_title text; v_task bigint;
begin
  if (s->>'behind')::boolean then
    v_title := format('Supplier target behind on %s%s', s->>'day', case when p_demo then ' (demo)' else '' end);
    if not exists (select 1 from public.ceo_task where title = v_title) then
      v_task := public.fn_ceo_task_open(v_title, format(
        E'%s verified suppliers against %s expected on the path to %s by %s. Shortfall %s in %s days: %s a day needed.\n'
        || E'Registered (capabilities confirmed): %s. Categories below 10 verified: %s of %s, so paid marketing stays closed (ledger 1004).\n'
        || 'Trades with 10+ verified, by emirate: %s. Direct the sales engineer and marketing to the widest trades.',
        s->>'verified', s->>'expected_today', s->>'target', s->>'milestone', s->>'shortfall', s->>'days_left', s->>'pace_per_day',
        s->>'registered', g->>'below_ten', g->>'categories', s->'trades_at_ten_by_emirate'));
    end if;
  end if;
  return s || jsonb_build_object('task_id', v_task, 'gate', g->'gate', 'below_ten', g->'below_ten');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_supplier_target_now()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_supplier_target(now(), false) $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_supplier_target_status(p_at timestamp with time zone DEFAULT now(), p_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_verified int; v_registered int;
  m record; v_expected numeric; v_short int; v_days int; v_emirates jsonb;
begin
  select coalesce(sum(verified), 0), coalesce(sum(registered), 0) into v_verified, v_registered
    from (select count(*) filter (where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)) as verified,
                 count(*) as registered
            from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
           where sc.confirmed_at is not null and coalesce(l.is_demo, false) = p_demo) x;
  -- The founder's year-one milestones (24 Sep 2026, restated 28 Sep). The path starts at 0 on 28 Sep 2026.
  select * into m from (values
      (date '2026-10-12',  50, date '2026-09-28',   0),
      (date '2026-11-30', 200, date '2026-10-12',  50),
      (date '2026-12-31', 300, date '2026-11-30', 200)) v(due, target, prev_due, prev_target)
   where v.due >= v_day order by v.due limit 1;
  if m.due is null then
    return jsonb_build_object('day', v_day, 'verified', v_verified, 'registered', v_registered, 'milestone', null, 'behind', false);
  end if;
  v_expected := m.prev_target + (m.target - m.prev_target) * greatest(0, least(1, (v_day - m.prev_due)::numeric / (m.due - m.prev_due)));
  v_short := greatest(0, m.target - v_verified);
  v_days := greatest(1, m.due - v_day);
  select jsonb_object_agg(emirate, verified) into v_emirates
    from (select emirate, count(distinct trade) filter (where verified >= 10) as verified
            from public.fn_supplier_target_by_trade_emirate(p_demo) group by emirate) e;
  return jsonb_build_object('day', v_day, 'verified', v_verified, 'registered', v_registered,
    'milestone', m.due, 'target', m.target, 'expected_today', floor(v_expected)::int,
    'behind_path', greatest(0, floor(v_expected)::int - v_verified), 'shortfall', v_short,
    'days_left', m.due - v_day, 'pace_per_day', round(v_short::numeric / v_days, 1),
    'behind', v_verified < floor(v_expected), 'trades_at_ten_by_emirate', v_emirates);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_takes_sales_escalation(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_kind text; v_options jsonb; v_question text; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_kind := a.detail->>'escalation';
  if v_kind = 'thin_supply' then
    v_question := 'The sales engineer escalates a customer request whose exact trade has fewer matchable suppliers than it needs. '
      || 'Our rules: a request goes only to suppliers of the exact trade (no nearest trade), and any number of suppliers may quote; '
      || 'the comparison report recommends the top three by value. Decide what happens to this request.';
    v_options := '[{"id":"send_to_matched","meaning":"send it now to every exact-trade supplier that matches, however few"},'
              || '{"id":"recruit_then_send","meaning":"the sales engineer recruits suppliers for this exact trade first and sends when enough match, telling the customer the date"},'
              || '{"id":"tell_customer_no_supply","meaning":"no supplier of this exact trade can serve it; the customer is told plainly and nothing is charged"}]';
  elsif v_kind = 'disputed_reveal' then
    v_question := 'The sales engineer escalates a reveal the customer or the supplier disputes. Decide the company''s answer; '
      || 'a refund is decided by the CEO''s refund checklist, never here.';
    v_options := '[{"id":"uphold_reveal","meaning":"the reveal was delivered as the terms say; the fee stands and the parties are told why"},'
              || '{"id":"refund_review","meaning":"open the refund review: the CEO''s refund checklist decides it against the Stripe record"},'
              || '{"id":"investigate","meaning":"the facts are not enough; the sales engineer gathers the named facts and escalates again"}]';
  else
    raise exception 'sales.escalation: unknown escalation %, expected thin_supply or disputed_reveal', coalesce(v_kind, '(none)');
  end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.sales_escalation', v_question, v_options::jsonb,
    coalesce(a.detail->'case', '{}'::jsonb) || jsonb_build_object('escalation', v_kind, 'subject', a.detail->>'subject_table', 'subject_id', a.detail->>'subject_id'),
    jsonb_build_object('handoff_id', a.id, 'escalation', v_kind), 'sales_escalation:' || a.id);
  return jsonb_build_object('accepted', true, 'escalation', v_kind, 'held_question', v_held,
    'waiting', 'the CEO decides this by reasoning (held question ' || v_held || ') and answers on this handoff');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_target_daily_verdict(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; v_day date := v_local::date;
  v_m0 date := date_trunc('month', v_local)::date; v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_frac numeric := extract(day from v_local) / extract(day from (date_trunc('month', v_local) + interval '1 month - 1 day'));
  p record; v_exp numeric; v_act numeric; v_gap numeric; v_status text; v_task bigint; v_hid bigint; v_prev_cum numeric;
  n_miss int := 0; n_new int := 0; n_closed int := 0; v_out jsonb := '[]'::jsonb; c_id bigint;
  v_pm date; v_launch date; m_next record; m_prev record;
  -- the customer side of the plan: zero until customers launch (founder, 24 Sep 2026: customers from January 2027)
  c_customer constant text[] := array['inquiries_posted', 'quotes_received', 'quote_coverage_pct', 'reveals_paid',
    'b2b_active_accounts', 'fee_aed', 'fee_aed_cumulative', 'checkout_success_pct', 'reveal_conversion_pct'];
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then raise exception 'ceo.target_verdict: the year-one plan contract is not active'; end if;

  -- the plan month graded: this month, or before the path starts, its first month (graded 'not_yet_due')
  v_pm := coalesce((select max(month) from public.target_path where contract_id = c_id and month = v_m0),
                   (select min(month) from public.target_path where contract_id = c_id and month > v_m0));
  v_launch := (select min(month) from public.ceo_year_plan where requests > 0);
  select * into m_next from public.ceo_year_plan_milestone where due > v_day order by due limit 1;
  if m_next is null then select * into m_next from public.ceo_year_plan_milestone order by due desc limit 1; end if;
  select * into m_prev from public.ceo_year_plan_milestone where due < m_next.due order by due desc limit 1;

  for p in
    select t.metric_key, t.owner_seat, t.kind, t.direction, t.value, t.tolerance_pct from public.target_path t
     where t.contract_id = c_id and t.month = v_pm
    union all
    select 'verified_suppliers_milestone', 'sales_engineer', 'milestone', 'min', m_next.verified, 20 where m_next.due is not null
    order by 1
  loop
    if p.kind = 'milestone' then
      v_act := public.fn_ambition_measure('registrations_verified_cumulative', v_from, p_at);
      v_exp := case when m_prev.due is null or v_day >= m_next.due then m_next.verified
                    else round(m_prev.verified + (m_next.verified - m_prev.verified)
                               * (v_day - m_prev.due)::numeric / (m_next.due - m_prev.due), 1) end;
    else
      v_act := public.fn_ambition_measure(p.metric_key, v_from, p_at);
      if p.kind = 'cumulative' then
        -- the day's line starts from last month's TARGET; a real shortfall is carried by the month directive (still_needed)
        select coalesce(max(value), 0) into v_prev_cum from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_pm;
        v_exp := round(v_prev_cum + (p.value - v_prev_cum) * v_frac, 1);
      elsif p.kind = 'month' and p.direction = 'min' then v_exp := round(p.value * v_frac, 1);
      else v_exp := p.value; end if;   -- a ceiling (direction max) is the whole month's: costs are lumpy, never pro-rated
    end if;

    v_gap := case when v_exp > 0 and v_act is not null then round(100.0 * (v_act - v_exp) / v_exp, 1) end;
    v_status := case when p.kind <> 'milestone' and v_pm <> v_m0 then 'not_yet_due'
                     when p.metric_key = any (c_customer) and (v_launch is null or v_m0 < v_launch) then 'not_yet_due'
                     when p.direction = 'max' then
                       case when v_act is null then 'not_measurable'
                            when v_act <= v_exp then 'on_track'
                            when v_gap <= p.tolerance_pct then 'within_tolerance'
                            else 'miss' end
                     when p.kind in ('month', 'cumulative') and extract(day from v_local) < 7 then 'too_early'
                     when v_exp is null or v_exp <= 0 then 'no_target'
                     when v_act is null then 'not_measurable'
                     when v_act >= v_exp then 'on_track'
                     when -v_gap <= p.tolerance_pct then 'within_tolerance'
                     else 'miss' end;

    -- the month's open task for this metric, if any
    select t.task_id into v_task from public.target_daily_verdict d join public.ceo_task t on t.task_id = d.task_id
     where d.contract_id = c_id and d.metric_key = p.metric_key and d.day >= v_m0 and d.day <= v_day
       and t.state in ('open', 'working', 'blocked') order by d.day desc limit 1;
    v_hid := null;
    if v_status = 'miss' then
      n_miss := n_miss + 1;
      if v_task is null then
        v_task := public.fn_ceo_task_open(format('Target miss: %s (%s) %s', p.metric_key, p.owner_seat, to_char(v_m0, 'Mon YYYY')),
          format(E'On %s %s read %s against %s (%s) on the founder''s year-one path (%s%% gap, tolerance %s%%).\nOwner: %s. The root-cause question went to the owner; this task closes when the measure is back within tolerance.',
                 v_day, p.metric_key, v_act, v_exp, case when p.direction = 'max' then 'the month''s ceiling' else 'expected by today' end,
                 v_gap, p.tolerance_pct, p.owner_seat));
        n_new := n_new + 1;
        if p.owner_seat = 'ceo' then
          perform public.fn_ceo_root_cause_ask('ceo', v_task, jsonb_build_object('metric', p.metric_key, 'day', v_day, 'expected', v_exp,
                                               'actual', v_act, 'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        else
          v_hid := public.fn_seat_handoff('ceo', p.owner_seat, 'ceo.root_cause', 'ceo_task', v_task::text,
            jsonb_build_object('task_id', v_task, 'metric', p.metric_key, 'day', v_day, 'expected', v_exp, 'actual', v_act,
                               'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        end if;
      end if;
    elsif v_task is not null and v_status in ('on_track', 'within_tolerance') then
      update public.ceo_task set state = 'done', closed_at = now(),
             evidence = format('Recovered on %s: %s read %s against %s expected (%s).', v_day, p.metric_key, v_act, v_exp, v_status)
       where task_id = v_task;
      n_closed := n_closed + 1; v_task := null;
    elsif v_task is not null and v_status = 'not_measurable' then
      update public.ceo_task set state = 'blocked',
             blocked_reason = format('On %s %s became not measurable (under 20 in its denominator); the miss is neither confirmed nor cleared.', v_day, p.metric_key)
       where task_id = v_task and state <> 'blocked';
    end if;

    insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status, task_id, handoff_id)
    values (v_day, c_id, p.metric_key, p.owner_seat, v_exp, v_act, v_gap, v_status, case when v_status = 'miss' then v_task end, v_hid)
    on conflict (day, contract_id, metric_key) do update set expected = excluded.expected, actual = excluded.actual, gap_pct = excluded.gap_pct,
      status = excluded.status, task_id = coalesce(target_daily_verdict.task_id, excluded.task_id),
      handoff_id = coalesce(target_daily_verdict.handoff_id, excluded.handoff_id);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'status', v_status, 'expected', v_exp, 'actual', v_act);
  end loop;

  -- an empty verdict reads as "0 misses"; it must fail loudly instead
  if jsonb_array_length(v_out) = 0 then raise exception 'ceo.target_verdict: no plan metric graded on %', v_day; end if;
  return jsonb_build_object('day', v_day, 'contract_id', c_id, 'plan_month', v_pm, 'customers_launch', v_launch,
                            'milestone', jsonb_build_object('due', m_next.due, 'verified', m_next.verified),
                            'metrics', v_out, 'misses', n_miss, 'tasks_opened', n_new, 'tasks_closed', n_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_target_forecast()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_all jsonb := '[]'::jsonb; v_ms jsonb; v_week date := public.fn_ceo_review_week(); v_held bigint; c_id bigint;
  v_today date := (now() at time zone 'Asia/Dubai')::date; v_now numeric;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then raise exception 'ceo.target_forecast: the year-one plan contract is not active'; end if;
  v := public.fn_target_feasibility(c_id, true);
  v_all := jsonb_build_array(jsonb_build_object('contract', 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30', 'verdict', v->>'verdict',
             'verdict_reason', v->>'verdict_reason', 'remaining', v->'remaining_outcome', 'days_remaining', v->'days_remaining',
             'required_run_rate_per_day', v->'required_run_rate_per_day', 'binding_stage', v->>'binding_stage',
             'what_must_change', v->'what_must_change'));

  v_now := public.fn_ambition_measure('registrations_verified_cumulative', now(), now());
  select coalesce(jsonb_agg(jsonb_build_object('due', m.due, 'verified_target', m.verified, 'verified_now', v_now,
           'gap', greatest(m.verified - v_now, 0),
           'needed_per_day', case when m.due > v_today then round(greatest(m.verified - v_now, 0) / (m.due - v_today), 2) end)
           order by m.due), '[]'::jsonb)
    into v_ms from public.ceo_year_plan_milestone m where m.due >= v_today and m.verified > 0;

  insert into public.ceo_review (kind, period, facts) values ('target_forecast', v_week, jsonb_build_object('verdicts', v_all, 'milestones', v_ms))
  on conflict (kind, period) do update set facts = excluded.facts;

  if coalesce(v->>'verdict', '') <> 'ON_TRACK'
     and (select held_id from public.ceo_review where kind = 'target_forecast' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.target_forecast',
      'This week''s forecast says the founder''s year-one plan (50 verified suppliers by 12 Oct, 200 by 30 Nov, 300 by 31 Dec 2026, '
        || 'customers from January 2027) is not on track. As the chief executive, decide the company''s response, and say what must change and who owns it.',
      ('[{"id":"hold_course","meaning":"the plan in force is right; the gap is expected at this stage and closes as it runs"},'
      || '{"id":"change_plan","meaning":"the plan must change: a different binding constraint, channel or sequence"},'
      || '{"id":"tell_founder","meaning":"the gap needs a decision only the founder holds (money, a commercial rule, his intent)"}]')::jsonb,
      jsonb_build_object('forecast', v - 'chain', 'milestones', v_ms, 'year_plan', public.fn_ceo_year_plan_status(now())),
      jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'ceo_forecast:' || v_week);
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'target_forecast' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'verdicts', v_all, 'milestones', v_ms, 'reasoning_filed', v_held is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_task_open(p_title text, p_detail text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  insert into public.ceo_task (title, detail, state) values (left(p_title, 300), left(p_detail, 8000), 'open') returning task_id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_week_plan_vs_actual(p_week_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c_id bigint; v_m0 date := date_trunc('month', p_week_end)::date; v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (p_week_end + 1)::timestamp at time zone 'Asia/Dubai';
  v_frac numeric := extract(day from p_week_end) / extract(day from (v_m0 + interval '1 month - 1 day'));
  p record; v_prev numeric; v_exp numeric; v_act numeric; v_gap numeric; v_res text; v_action text; v_rows jsonb := '[]'::jsonb; v_text text;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null or not exists (select 1 from public.target_path where contract_id = c_id and month = v_m0) then
    return jsonb_build_object('rows', '[]'::jsonb, 'text', 'PLAN AGAINST ACTUAL' || E'\n' || '  No year-one path for ' || to_char(v_m0, 'FMMonth YYYY') || ' (the path runs October 2026 to September 2027).');
  end if;
  for p in select * from public.target_path where contract_id = c_id and month = v_m0 order by owner_seat, metric_key loop
    if p.kind = 'cumulative' then
      select coalesce(max(value), 0) into v_prev from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_m0;
      v_exp := round(v_prev + (p.value - v_prev) * v_frac, 1);
    elsif p.kind = 'month' and p.direction = 'min' then v_exp := round(p.value * v_frac, 1);
    else v_exp := p.value; end if;
    v_act := public.fn_ambition_measure(p.metric_key, v_from, v_to);
    v_gap := case when v_act is not null then round(v_act - v_exp, 1) end;
    v_res := case when v_act is null then 'not measurable'
                  when p.direction = 'max' then case when v_act <= v_exp then 'within the ceiling' else 'OVER the ceiling' end
                  when v_act >= v_exp then 'on plan' else 'BEHIND' end;
    select coalesce(nullif(substring(t.evidence from 'Corrective action: ([^\n]*)'), '?'), 'root cause asked of ' || p.owner_seat || ' (task #' || t.task_id || ')')
      into v_action from public.ceo_task t
     where t.title like 'Target miss: ' || p.metric_key || ' (' || p.owner_seat || ')%' and t.state in ('open', 'working', 'blocked')
     order by t.task_id desc limit 1;
    if v_action is null then
      select d.actions[1] into v_action from public.ceo_seat_directive d where d.month = v_m0 and d.seat = p.owner_seat;
      v_action := coalesce(v_action, (select a.action from public.ceo_plan_action a where a.seat = p.owner_seat and v_m0 between a.from_month and a.to_month order by a.id limit 1),
                           'the CEO''s own routine: the daily read, the weekly review and the month plan');
    end if;
    v_rows := v_rows || jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'target', v_exp, 'month_target', p.value,
                                           'actual', v_act, 'gap', v_gap, 'result', v_res, 'action', v_action);
  end loop;
  v_text := 'PLAN AGAINST ACTUAL, month to ' || to_char(p_week_end, 'DD Mon YYYY') || E' (the founder''s year-one path)\n'
    || (select string_agg(format(E'  %s (%s): target %s, actual %s, gap %s, %s\n    Action: %s',
                                 r->>'metric', r->>'owner_seat', r->>'target', coalesce(r->>'actual', 'not measurable'),
                                 coalesce(r->>'gap', 'n/a'), r->>'result', r->>'action'), E'\n' order by r->>'owner_seat', r->>'metric')
          from jsonb_array_elements(v_rows) r);
  return jsonb_build_object('rows', v_rows, 'text', v_text);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_figures(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_prev_from date := p_from - (p_to - p_from) - 1;
  v_prev_to   date := p_from - 1;
  j jsonb;
begin
  select jsonb_build_object(
    'window', jsonb_build_object('from', p_from, 'to', p_to,
                                 'prior_from', v_prev_from, 'prior_to', v_prev_to),

    'money', jsonb_build_object(
      'revenue_week_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between p_from and p_to),
      'revenue_prior_aed', (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between v_prev_from and v_prev_to),
      'revenue_life_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted'),
      -- SPEND COMES FROM THE LEDGER, NOT FROM expense_entries. Those rows carry a raw amount in
      -- the currency the vendor billed (USD and AED are both present), so summing them would add
      -- dollars to dirhams. The GL is already converted and is the accountant's authoritative
      -- figure, which is also where revenue above is read from — one source, one basis.
      'spend_week_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted' and g.entry_date between p_from and p_to),
      'spend_life_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted'),
      'vat_position',      public.fn_accountant_vat_threshold_check(false)),

    'supply', jsonb_build_object(
      'leads_total',       (select count(*) from leads),
      'contactable',       (select count(*) from leads where email is not null and coalesce(invite_status,'') <> 'bounced'),
      'invited_ever',      (select count(*) from leads where invite_status is not null),
      'invited_week',      (select count(*) from leads where invited_at::date between p_from and p_to),
      'registered',        (select count(*) from leads where registration_status is not null),
      'verified',          (select count(*) from leads where verified),
      'matchable',         (select count(*) from supplier_capabilities where confirmed_at is not null),
      -- 14 Sep 2026: suppliers the sales engineer put on matching hold after three consecutive held
      -- quotes were left unanswered (founder_instruction #158). Only the founder lifts it (#160).
      'on_matching_hold',  (select count(*) from leads where matching_block_reason = 'collaboration_hold'),
      'days_since_last_invite', (select case when max(invited_at) is null then null
                                   else (current_date - max(invited_at)::date) end from leads)),

    'demand', jsonb_build_object(
      'customers',         (select count(*) from customers),
      'customers_real',    ((select public.fn_customer_counts())->>'substantiated')::int,
      'inquiries_week',    (select count(*) from inquiries where created_at::date between p_from and p_to),
      'inquiries_ever',    (select count(*) from inquiries),
      'quotes_ever',       (select count(*) from quotes),
      'comparisons_ever',  (select count(*) from quote_comparisons),
      'reveals_ever',      (select count(*) from transactions)),

    'seats', (select jsonb_object_agg(s.seat, jsonb_build_object(
                'runs_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.started_at::date between p_from and p_to),
                'errors_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.status = 'error' and r.started_at::date between p_from and p_to)))
              from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'health', jsonb_build_object(
      'it_findings_open',   (select count(*) from it_watch_finding where status='open'),
      'it_alerts_week',     (select count(*) from notifications where kind like 'it_%' and created_at::date between p_from and p_to),
      'reports_awaiting_ceo',(select count(*) from support_ceo_report where accepted_at is null and status='sent'),
      'founder_instructions_open', (select count(*) from founder_instruction where status='open'))
  ) into j;
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ws date; v_we date; v_key text; v_fig jsonb; v_con jsonb; v_id bigint; v_body text; v_subj text;
  m jsonb; s jsonb; d jsonb; h jsonb;
begin
  v_ws := coalesce(p_week_start, (date_trunc('week', (now() at time zone 'Asia/Dubai')::date - 7))::date);
  v_we := v_ws + 6;
  v_key := 'quotesdone:' || to_char(v_ws, 'IYYY-"W"IW');

  v_fig := public.fn_ceo_weekly_figures(v_ws, v_we);
  v_con := public.fn_ceo_binding_constraint(v_fig);
  m := v_fig->'money'; s := v_fig->'supply'; d := v_fig->'demand'; h := v_fig->'health';

  v_subj := format('QuotesDone weekly - %s to %s - %s',
                   to_char(v_ws,'DD Mon'), to_char(v_we,'DD Mon YYYY'),
                   case when (v_con->>'severity') = 'healthy'
                        then 'AED ' || (m->>'revenue_week_aed') || ' revenue'
                        else 'blocked at ' || replace(v_con->>'stage','_',' ') end);

  v_body :=
    'WHAT IS HOLDING THE COMPANY BACK' || E'\n' ||
    (v_con->>'finding') || E'\n\n' ||
    'Why this outranks everything else: ' || (v_con->>'why_it_outranks_everything') || E'\n\n' ||
    'What to do: ' || (v_con->>'proposal') || E'\n' ||
    'How we will know it worked: ' || (v_con->>'measure_of_success') || E'\n\n' ||
    '--------------------------------------------------' || E'\n' ||
    'MONEY' || E'\n' ||
    format('  Revenue this week   AED %s   (prior week AED %s)', m->>'revenue_week_aed', m->>'revenue_prior_aed') || E'\n' ||
    format('  Revenue to date     AED %s', m->>'revenue_life_aed') || E'\n' ||
    format('  Spend this week     AED %s   (to date AED %s)', m->>'spend_week_aed', m->>'spend_life_aed') || E'\n' ||
    format('  VAT registration    %s (%s%% of the AED %s threshold)',
           (m->'vat_position'->>'band'), (m->'vat_position'->>'pct_of_threshold'), (m->'vat_position'->>'threshold_aed')) || E'\n\n' ||
    'SUPPLY' || E'\n' ||
    format('  On file %s, contactable %s, invited %s, registered %s, verified %s, MATCHABLE %s',
           s->>'leads_total', s->>'contactable', s->>'invited_ever', s->>'registered', s->>'verified', s->>'matchable') || E'\n' ||
    format('  Invited this week %s. Last invitation went out %s days ago.',
           s->>'invited_week', coalesce(s->>'days_since_last_invite','never')) || E'\n\n' ||
    'DEMAND' || E'\n' ||
    format('  Customers %s (with evidence behind them: %s)', d->>'customers', d->>'customers_real') || E'\n' ||
    format('  Requests this week %s, ever %s. Quotes %s. Comparisons %s. Paid reveals %s.',
           d->>'inquiries_week', d->>'inquiries_ever', d->>'quotes_ever', d->>'comparisons_ever', d->>'reveals_ever') || E'\n\n' ||
    'THE SEATS' || E'\n' ||
    (select string_agg(format('  %-17s %s run(s), %s error(s)', k, v->>'runs_week', v->>'errors_week'), E'\n' order by k)
       from jsonb_each(v_fig->'seats') as t(k,v)) || E'\n\n' ||
    'HEALTH' || E'\n' ||
    format('  Open IT findings %s. Alerts sent to you this week %s.', h->>'it_findings_open', h->>'it_alerts_week') || E'\n' ||
    format('  Reports waiting on the CEO %s. Your instructions still open %s.',
           h->>'reports_awaiting_ceo', h->>'founder_instructions_open') || E'\n\n' ||
    'GAME DAY (the IT engineer breaks the company on purpose once a month and times the recovery)' || E'\n' ||
    public.fn_it_game_day_weekly_line() || E'\n\n' ||
    'Every figure above is measured from the ledger and the live tables at the moment of writing. ' ||
    'A zero here means nothing happened, not that nothing was counted.';

  insert into public.ceo_weekly_report
    (iso_year, iso_week, week_start, week_end, report_key, subject, body, figures, constraint_now,
     proposals, status)
  values
    (extract(isoyear from v_ws)::int, extract(week from v_ws)::int, v_ws, v_we, v_key,
     v_subj, v_body, v_fig, v_con, jsonb_build_array(v_con->>'proposal'), 'generated')
  on conflict (report_key, revision) do update
     set subject = excluded.subject, body = excluded.body, figures = excluded.figures,
         constraint_now = excluded.constraint_now, proposals = excluded.proposals, updated_at = now()
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'report_key', v_key,
    'week', v_ws || ' to ' || v_we, 'constraint', v_con->>'stage', 'subject', v_subj);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_attach_pdf(p_id bigint, p_bucket text DEFAULT NULL::text, p_path text DEFAULT NULL::text, p_url text DEFAULT NULL::text, p_bytes integer DEFAULT NULL::integer, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.ceo_weekly_report;
begin
  select * into r from public.ceo_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_report '||p_id); end if;

  if p_path is null or coalesce(p_error,'') <> '' then
    update public.ceo_weekly_report
       set pdf_error = coalesce(nullif(p_error,''), 'pdf_native returned no path'),
           delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'the PDF could not be rendered: '||coalesce(nullif(p_error,''),'no path returned'),
           status = case when founder_submitted_at is null then 'delivery_failed' else status end,
           updated_at = now()
     where id = p_id returning * into r;
    return jsonb_build_object('ok', false, 'report_key', r.report_key, 'retained', true, 'error', r.last_delivery_error);
  end if;

  update public.ceo_weekly_report
     set pdf_bucket = coalesce(p_bucket,'agent-docs'), pdf_path = p_path, pdf_url = p_url, pdf_bytes = p_bytes,
         pdf_generated_at = now(), pdf_error = null, updated_at = now()
   where id = p_id;
  return public.fn_ceo_weekly_report_deliver(p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_carries_the_cash_forecast()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f jsonb; v_txt text;
begin
  if new.body is null or position('CASH FORECAST (90 DAYS)' in new.body) > 0 then return new; end if;
  f := public.fn_accountant_cash_forecast(new.week_end);
  v_txt := 'CASH FORECAST (90 DAYS) - information, not an alarm' || E'\n'
    || '  Opening AED ' || coalesce(f#>>'{opening,aed}', 'missing (' || coalesce(f#>>'{opening,missing}', '') || ')') || E'\n'
    || coalesce((select string_agg(format('  Week %s (%s to %s): in %s, out %s, closing %s', w->>'week', w->>'from', w->>'to',
                                          w->>'in_aed', w->>'out_aed', coalesce(w->>'closing_aed', '?')), E'\n' order by (w->>'week')::int)
                   from jsonb_array_elements(f->'weeks') w), '') || E'\n'
    || case when f#>>'{below_zero,first_week}' is not null
            then format('  The account would go below zero in week %s (from %s). A top-up of AED %s keeps it at or above zero.',
                        f#>>'{below_zero,first_week}', f#>>'{below_zero,week_from}', f#>>'{below_zero,top_up_to_stay_above_zero_aed}')
            else '  ' || coalesce(f#>>'{below_zero,note}', '') end;
  new.body := new.body || E'\n\n' || v_txt;
  new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('cash_forecast_90d', f);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_carries_the_plan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  if new.body is null or position('PLAN AGAINST ACTUAL' in new.body) > 0 then return new; end if;
  v := public.fn_ceo_week_plan_vs_actual(new.week_end);
  new.body := case when position('MONEY' in new.body) > 0
                   then overlay(new.body placing (v->>'text') || E'\n\n' || '--------------------------------------------------' || E'\n' from position('MONEY' in new.body) for 0)
                   else new.body || E'\n\n' || (v->>'text') end;
  new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('plan_vs_actual', v->'rows');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r        public.ceo_weekly_report;
  v_owner  text;
  v_notif  bigint;          -- the notifications.id from RETURNING, never a routine's jsonb answer
  v_file   text;
  v_err    text;
begin
  -- FOR UPDATE (review of #802): two overlapping ticks both read founder_submitted_at null and mailed the
  -- week twice. The row lock makes the second wait for the first to commit, then see it delivered.
  select * into r from public.ceo_weekly_report where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_report '||p_id); end if;
  if r.founder_submitted_at is not null then
    return jsonb_build_object('ok', true, 'report_key', r.report_key, 'status', r.status, 'already', true);
  end if;

  -- THE PDF IS THE DELIVERABLE. Mailing text and closing the week would close it on the wrong thing.
  if r.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; the report is retained and the next tick retries';
  else
    select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
      from public.app_secrets where key = 'admin_emails';
    if v_owner is null then
      v_err := 'no recipient configured in app_secrets.admin_emails';
    else
      v_file := 'QuotesDone_Weekly_Company_Report_'
             || regexp_replace(replace(r.report_key, 'quotesdone:', ''), '[^A-Za-z0-9_-]', '_', 'g')
             || case when r.revision > 1 then '_revision_'||r.revision else '' end || '.pdf';
      begin
        -- kind board_report: allowed by founder_mail_policy and owned by the ceo. The a10 gate decides;
        -- if it refuses, RETURNING yields no row and v_notif stays null, named below.
        insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
        values ('board_report', 'board_report', v_owner, 'admin', 'email', r.subject,
                coalesce(r.body,'') || E'\n\nThe report is attached as ' || v_file || '.',
                jsonb_build_array(jsonb_build_object('bucket', coalesce(r.pdf_bucket,'agent-docs'),
                                                     'path', r.pdf_path, 'filename', v_file)))
        returning id into v_notif;
        if v_notif is null then
          v_err := 'the founder-mail gate did not accept the row (kind board_report)';
        end if;
      exception when others then
        v_err := 'founder submission raised: ' || sqlerrm;
      end;
    end if;
  end if;

  update public.ceo_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_notif is not null then now() else founder_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = v_err,
         status               = case when v_notif is not null then 'delivered' else 'delivery_failed' end,
         updated_at           = now()
   where id = p_id returning * into r;

  -- ok/error at the TOP LEVEL: resilience_ping's failureOf reads nothing deeper, which is how 76 failed
  -- attempts were recorded as a healthy step.
  return jsonb_build_object('ok', v_notif is not null, 'report_key', r.report_key,
    'notification_id', r.notification_id, 'status', r.status, 'pdf_filename', v_file)
    || case when v_err is null then '{}'::jsonb else jsonb_build_object('error', v_err) end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_pdf_blocks(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_array(
           jsonb_build_object('t','h2','text','Weekly company report'),
           jsonb_build_object('t','p','text', to_char(r.week_start,'Dy DD Mon YYYY')||' to '||to_char(r.week_end,'Dy DD Mon YYYY')
                                              ||'  (Asia/Dubai)   ISO '||to_char(r.week_start,'IYYY-"W"IW')||'   Revision '||r.revision),
           jsonb_build_object('t','note','text','Prepared by the CEO seat for the founder. Informational: nothing in this document asks for an approval.'),
           jsonb_build_object('t','space','h',6))
      || coalesce((
           select jsonb_agg(case
                    when l.line ~ '^-{5,}$'              then jsonb_build_object('t','space','h',8)
                    when l.line ~ '^\s{2}'               then jsonb_build_object('t','li','text', btrim(l.line))
                    when l.line ~ '^[A-Z][A-Z ]+[A-Z]$'  then jsonb_build_object('t','h3','text', initcap(l.line))
                    else jsonb_build_object('t','p','text', l.line) end order by l.n)
             from regexp_split_to_table(coalesce(r.body,''), E'\n') with ordinality as l(line, n)
            where btrim(l.line) <> ''), '[]'::jsonb)
    from public.ceo_weekly_report r where r.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_dow int; v_at time; v_ws date; v_key text; v_gen jsonb;
  r public.ceo_weekly_report;
begin
  begin
    select coalesce(nullif(btrim(value),''),'1')::int into v_dow from public.app_secrets where key = 'ceo_weekly_report_local_dow';
  exception when others then v_dow := 1; end;
  begin
    select coalesce(nullif(btrim(value),''),'08:00')::time into v_at from public.app_secrets where key = 'ceo_weekly_report_local_time';
  exception when others then v_at := time '08:00'; end;
  v_dow := coalesce(v_dow, 1); v_at := coalesce(v_at, time '08:00');

  v_ws  := (date_trunc('week', v_local::date) - interval '7 days')::date;   -- the week that closed
  v_key := 'quotesdone:' || to_char(v_ws, 'IYYY-"W"IW');

  select * into r from public.ceo_weekly_report where report_key = v_key order by revision desc limit 1;

  if not found then
    if extract(isodow from v_local)::int < v_dow
       or (extract(isodow from v_local)::int = v_dow and v_local::time < v_at) then
      return jsonb_build_object('fired', false, 'reason', 'before the configured local day/time',
        'report_key', v_key, 'configured_dow', v_dow, 'configured_at', v_at::text);
    end if;
    v_gen := public.fn_ceo_weekly_report(v_ws);
    select * into r from public.ceo_weekly_report where id = (v_gen->>'id')::bigint;
  end if;

  if r.founder_submitted_at is not null then
    return jsonb_build_object('fired', false, 'reason', 'already delivered', 'report_key', v_key, 'id', r.id);
  end if;

  -- A REPORT IN FLIGHT IS FINISHED WHATEVER DAY IT IS (the Monday-only gate abandoned W37).
  if r.pdf_path is null then
    if r.pdf_blocks is null then
      update public.ceo_weekly_report set pdf_blocks = public.fn_ceo_weekly_report_pdf_blocks(r.id), updated_at = now()
       where id = r.id returning * into r;
    end if;
    return jsonb_build_object('fired', true, 'pdf_pending', true, 'id', r.id, 'report_key', r.report_key,
      'revision', r.revision, 'subject', r.subject, 'pdf_blocks', r.pdf_blocks);
  end if;

  return public.fn_ceo_weekly_report_deliver(r.id) || jsonb_build_object('fired', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review(p_week date, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_targets jsonb; t jsonb; i record; v_id bigint; v_task bigint;
  v_open bigint[] := '{}'; v_esc bigint[] := '{}'; v_closed bigint[] := '{}'; v_row public.ceo_weekly_review;
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
begin
  select * into v_row from public.ceo_weekly_review where week = p_week;
  if found then return jsonb_build_object('week', p_week, 'already', true, 'id', v_row.id); end if;

  v_targets := public.fn_ceo_weekly_review_measure(p_at);

  -- 1. CLOSE: the check of each open action, re-read on the same measure
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned') loop
    select x into t from jsonb_array_elements(v_targets) x
     where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1;
    if t is not null and ((t->>'met')::boolean
        or (t->>'key' = 'supply' and (t->>'value')::numeric < (i.evidence->>'value')::numeric)) then
      perform public.fn_ceo_improvement_close(i.id, format('Weekly review of %s: %s. %s', p_week, t->>'actual', i.close_check));
      v_closed := v_closed || i.id;
    end if;
  end loop;

  -- 2. ESCALATE: still open past its due date
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
                                                     and due_on is not null and due_on <= v_today loop
    v_task := public.fn_ceo_task_open(
      format('ESCALATED x%s: %s missed the due date of improvement #%s', i.escalations + 1, i.seat, i.id),
      format(E'%s\nWas due %s. Now due %s. %s\nMeasured this week: %s',
             coalesce(i.evidence->>'action', i.proposal), i.due_on, v_today + 7, i.close_check,
             coalesce((select x->>'actual' from jsonb_array_elements(v_targets) x where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1), 'not measured')));
    update public.ceo_improvement set escalations = escalations + 1, last_escalated_at = p_at, due_on = v_today + 7,
           evidence = evidence || jsonb_build_object('escalation_tasks', coalesce(evidence->'escalation_tasks', '[]'::jsonb) || to_jsonb(v_task))
     where id = i.id;
    v_esc := v_esc || i.id;
  end loop;

  -- 3. OPEN: one action per missed target that has none open
  for t in select x from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean loop
    if exists (select 1 from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
                  and seat = t->>'seat' and evidence->>'target' = t->>'key') then continue; end if;
    v_id := public.fn_ceo_improvement_open('weekly_review', (t->>'key') || ':' || (t->>'seat') || ':' || p_week, t->>'seat',
      format('Weekly review %s, %s missed (%s; target %s). Action: %s Due %s. %s',
             to_char(p_week, 'DD Mon YYYY'), t->>'label', t->>'actual', t->>'target', t->>'action', to_char(p_week + 7, 'DD Mon YYYY'), t->>'close_check'),
      jsonb_build_object('target', t->>'key', 'value', t->'value', 'week', p_week, 'actual', t->>'actual', 'action', t->>'action', 'detail', t->'detail'));
    if v_id is not null then
      update public.ceo_improvement set due_on = p_week + 7, close_check = t->>'close_check' where id = v_id;
      v_open := v_open || v_id;
    end if;
  end loop;

  insert into public.ceo_weekly_review (week, targets, opened, escalated, closed)
  values (p_week, v_targets, v_open, v_esc, v_closed) returning * into v_row;
  update public.ceo_weekly_review set pdf_blocks = public.fn_ceo_weekly_review_pdf_blocks(v_row.id) where id = v_row.id;
  return jsonb_build_object('ok', true, 'week', p_week, 'id', v_row.id, 'opened', cardinality(v_open),
    'escalated', cardinality(v_esc), 'closed', cardinality(v_closed),
    'missed', (select count(*) from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_attach_pdf(p_id bigint, p_bucket text DEFAULT NULL::text, p_path text DEFAULT NULL::text, p_url text DEFAULT NULL::text, p_bytes integer DEFAULT NULL::integer, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists (select 1 from public.ceo_weekly_review where id = p_id) then
    return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_review ' || p_id);
  end if;
  if p_path is null or coalesce(p_error, '') <> '' then
    update public.ceo_weekly_review set pdf_error = coalesce(nullif(p_error, ''), 'pdf_native returned no path'),
           attempts = attempts + 1, last_error = 'the PDF could not be rendered: ' || coalesce(nullif(p_error, ''), 'no path returned'), updated_at = now()
     where id = p_id;
    return jsonb_build_object('ok', false, 'retained', true, 'error', 'the PDF could not be rendered: ' || coalesce(nullif(p_error, ''), 'no path returned'));
  end if;
  update public.ceo_weekly_review set pdf_bucket = coalesce(p_bucket, 'agent-docs'), pdf_path = p_path, pdf_url = p_url,
         pdf_bytes = p_bytes, pdf_error = null, updated_at = now()
   where id = p_id;
  return public.fn_ceo_weekly_review_deliver(p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare w public.ceo_weekly_review; v_res jsonb; v_notif bigint; v_err text; v_file text; v_event text; v_missed int;
begin
  select * into w from public.ceo_weekly_review where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_review ' || p_id); end if;
  if w.delivered_at is not null then return jsonb_build_object('ok', true, 'week', w.week, 'already', true); end if;

  if w.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; retained, the next beat retries';
  else
    v_missed := (select count(*) from jsonb_array_elements(w.targets) x where not (x->>'met')::boolean);
    v_event := 'CEO weekly review, week of ' || to_char(w.week, 'DD Mon YYYY');
    v_file := 'QuotesDone_CEO_Weekly_Review_' || to_char(w.week, 'IYYY-"W"IW') || '.pdf';
    begin
      v_res := public.fn_notify_founder(p_event => v_event,
        p_detail => format(E'%s of %s targets missed this week. Actions: %s opened, %s escalated, %s closed.\nThe one-page review is attached as %s.',
               v_missed, (select count(*) from jsonb_array_elements(w.targets) x where not coalesce((x->>'info_only')::boolean, false)), cardinality(w.opened), cardinality(w.escalated), cardinality(w.closed), v_file),
        p_level => 'info', p_kind => 'ceo_weekly_review', p_dedupe_key => 'ceo_weekly_review:' || w.week, p_owner_agent => 'ceo');
      if coalesce((v_res->>'emailed')::boolean, false) then
        -- fn_notify_founder answers jsonb, not the row id: the email it queued is the one of this kind in THIS transaction.
        update public.notifications n
           set attachments = jsonb_build_array(jsonb_build_object('bucket', coalesce(w.pdf_bucket, 'agent-docs'), 'path', w.pdf_path, 'filename', v_file))
         where n.id = (select max(x.id) from public.notifications x
                        where x.kind = 'ceo_weekly_review' and x.channel = 'email' and x.to_role = 'founder' and x.created_at = now())
        returning n.id into v_notif;
        if v_notif is null then v_err := 'fn_notify_founder said emailed, but no queued email of kind ceo_weekly_review was found to attach the PDF to'; end if;
      else
        v_err := 'fn_notify_founder did not email: ' || coalesce(v_res::text, 'null');
      end if;
    exception when others then
      v_err := 'delivery raised: ' || sqlerrm;
      v_notif := null;
    end;
  end if;

  update public.ceo_weekly_review
     set notification_id = coalesce(v_notif, notification_id), notify = coalesce(v_res, notify),
         delivered_at = case when v_notif is not null then now() end,
         attempts = attempts + 1, last_error = v_err, updated_at = now()
   where id = p_id;
  return jsonb_build_object('ok', v_notif is not null, 'week', w.week, 'notification_id', v_notif, 'pdf_filename', v_file)
    || case when v_err is null then '{}'::jsonb else jsonb_build_object('error', v_err) end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_measure(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
  v_min int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_out jsonb := '[]'::jsonb;
  v_trades int; v_short int; v_top jsonb;
  v_rf jsonb; v_months numeric; v_cash numeric; v_spend numeric;
  v_bud numeric; v_act numeric; v_nbud int; v_over jsonb;
  s record; v_n int; v_ids jsonb;
begin
  -- SUPPLY (sales_engineer)
  select count(*), count(*) filter (where matchable < v_min) into v_trades, v_short
    from public.supply_gap where emirate = 'UAE';
  select coalesce(jsonb_agg(jsonb_build_object('trade', x.trade, 'label', x.label, 'matchable', x.matchable,
           'requests_90d', x.demand_90d, 'uninvited_pool', x.uninvited_pool) order by x.demand_90d desc, x.uninvited_pool desc, x.matchable desc), '[]'::jsonb)
    into v_top
    from (select g.*, coalesce(t.label, g.trade) as label from public.supply_gap g left join public.taxonomy_trade t on t.code = g.trade
           where g.emirate = 'UAE' and g.matchable < v_min
           order by g.demand_90d desc, g.uninvited_pool desc, g.matchable desc limit 5) x;
  v_out := v_out || jsonb_build_object('key', 'supply', 'seat', 'sales_engineer', 'label', 'Suppliers per category',
    'met', v_trades > 0 and v_short = 0, 'value', v_short,
    'target', format('%s matchable suppliers in every category', v_min),
    'actual', case when v_trades = 0 then 'not measured: supply_gap holds no UAE rows (the supply duty has not run)'
                   else format('%s of %s categories at target; %s short', v_trades - v_short, v_trades, v_short) end,
    'action', case when v_trades = 0 then 'Run the supply-gap duty so every category is measured against the target.'
                   else format('Recruit to %s matchable suppliers per category, starting with %s.', v_min,
                     coalesce((select string_agg(e->>'label' || ' (' || (e->>'matchable') || ')', ', ') from (select e from jsonb_array_elements(v_top) e limit 3) z), 'the short categories')) end,
    'close_check', 'Closes when fewer categories are short than when it was opened (or none are).',
    'detail', v_top);

  -- RUNWAY (accountant)
  v_rf := public.fn_accountant_runway_figures(date_trunc('month', v_today)::date);
  v_months := (v_rf->>'runway_months_at_actual_spend')::numeric;
  v_cash := (v_rf->>'available_aed')::numeric; v_spend := (v_rf->>'monthly_spend_aed')::numeric;
  -- INFORMATION ONLY. Founder ruling, 29 Sep 2026 (ledger): there is NO runway target -- he funds the company himself,
  -- with no deadline, until it is profitable. Runway is shown (months at current spend) and is never a missed target,
  -- never opens an improvement and never escalates. Revisit ONLY if investor funding arrives.
  v_out := v_out || jsonb_build_object('key', 'runway', 'seat', 'accountant', 'label', 'Cash and runway',
    'info_only', true, 'met', true, 'value', v_months,
    'target', 'none: information only (founder funds the company until profitable; revisited only if investor funding arrives)',
    'actual', case when v_months is null then 'not measured: ' || coalesce(v_rf->>'missing', 'the books give no runway')
                   else format('AED %s available, AED %s a month, %s months at current spend', to_char(v_cash, 'FM999,999,990.00'), to_char(v_spend, 'FM999,999,990.00'), v_months) end,
    'detail', v_rf);

  -- SPEND AGAINST BUDGET (accountant): expense lines of active budgets for the year, to this month
  select count(distinct b.budget_id), sum(b.budget_amount), sum(b.actual_amount)
    into v_nbud, v_bud, v_act
    from public.budget_vs_actual b join public.budgets bu on bu.id = b.budget_id and bu.status = 'active'
   where b.fiscal_year = extract(year from v_today)::int and b.type = 'expense' and b.period_month <= v_today;
  select coalesce(jsonb_agg(jsonb_build_object('account', x.account_name, 'budget', x.bud, 'actual', x.act) order by x.act - x.bud desc), '[]'::jsonb)
    into v_over
    from (select b.account_name, sum(b.budget_amount) bud, sum(b.actual_amount) act
            from public.budget_vs_actual b join public.budgets bu on bu.id = b.budget_id and bu.status = 'active'
           where b.fiscal_year = extract(year from v_today)::int and b.type = 'expense' and b.period_month <= v_today
           group by b.account_name having sum(b.actual_amount) > sum(b.budget_amount) order by sum(b.actual_amount) - sum(b.budget_amount) desc limit 3) x;
  v_out := v_out || jsonb_build_object('key', 'budget', 'seat', 'accountant', 'label', 'Spend against budget',
    'met', v_nbud > 0 and v_act <= v_bud, 'value', case when v_nbud > 0 then v_act - v_bud end,
    'target', 'expense actuals year to date within an active budget',
    'actual', case when coalesce(v_nbud, 0) = 0 then format('no active budget for %s', extract(year from v_today))
                   else format('AED %s spent against AED %s budgeted year to date', to_char(v_act, 'FM999,999,990'), to_char(v_bud, 'FM999,999,990')) end,
    'action', case when coalesce(v_nbud, 0) = 0 then format('Set the %s expense budget by month and account, activate it, and report spend against it.', extract(year from v_today))
                   else format('Bring spend back inside budget: AED %s over, largest overrun %s.', to_char(v_act - v_bud, 'FM999,999,990'),
                          coalesce(v_over->0->>'account', '(none)')) end,
    'close_check', 'Closes when an active budget exists for the year and expense actuals year to date are within it.',
    'detail', v_over);

  -- RISKS and FINDINGS, per active seat (a row for every seat, met or not, so a closing check always finds its row)
  for s in select role_id from public.org_role where status = 'active' order by role_id loop
    select count(*), coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'risk', left(r.risk, 90), 'review_due', r.review_due) order by r.id), '[]'::jsonb)
      into v_n, v_ids
      from public.risk_register r
     where r.status = 'open'
       and (case when exists (select 1 from public.org_role o where o.role_id = r.owner_agent and o.status = 'active') then r.owner_agent else 'ceo' end) = s.role_id
       and (r.review_due is null or r.review_due < v_today or nullif(btrim(coalesce(r.mitigation, '')), '') is null);
    v_out := v_out || jsonb_build_object('key', 'risks', 'seat', s.role_id, 'label', 'Open risks', 'met', v_n = 0, 'value', v_n,
      'target', 'every open risk owned has a mitigation and a review date not passed',
      'actual', format('%s open risk(s) without a mitigation or past review', v_n),
      'action', format('Review risk(s) %s: write the mitigation and set the next review date.',
                       coalesce((select string_agg('#' || (e->>'id'), ', ') from jsonb_array_elements(v_ids) e), '-')),
      'close_check', 'Closes when every open risk this seat owns has a mitigation and a review date not passed.',
      'detail', v_ids);

    select count(*) filter (where f.started_at < p_at - interval '7 days'), count(*),
           coalesce(jsonb_agg(jsonb_build_object('key', f.issue_key, 'title', left(f.title, 90), 'since', f.started_at::date)
                              order by f.started_at) filter (where f.started_at < p_at - interval '7 days'), '[]'::jsonb)
      into v_n, v_short, v_ids
      from public.it_engineer_finding f
     where f.closed_at is null
       and (case when exists (select 1 from public.org_role o where o.role_id = coalesce(f.evidence->>'owner_seat', f.raised_by) and o.status = 'active')
                 then coalesce(f.evidence->>'owner_seat', f.raised_by) else 'it_engineer' end) = s.role_id;
    v_out := v_out || jsonb_build_object('key', 'findings', 'seat', s.role_id, 'label', 'Open findings', 'met', v_n = 0, 'value', v_n,
      'open_total', v_short,
      'target', 'no finding open more than 7 days',
      'actual', format('%s open, %s of them more than 7 days', v_short, v_n),
      'action', format('Close the %s finding(s) open more than 7 days, oldest first: %s.', v_n,
                       coalesce((select string_agg(e->>'title', '; ') from (select e from jsonb_array_elements(v_ids) e limit 3) z), '-')),
      'close_check', 'Closes when no finding attributed to this seat is open more than 7 days.',
      'detail', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_ids) e limit 5) z));
  end loop;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_pdf_blocks(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare w public.ceo_weekly_review; v jsonb; t jsonb; li jsonb := '[]'::jsonb;
  f jsonb := '{}'::jsonb; v_find text;
begin
  select * into w from public.ceo_weekly_review where id = p_id;
  if not found then return null; end if;
  v := jsonb_build_array(
    jsonb_build_object('t', 'h2', 'text', 'CEO weekly review'),
    jsonb_build_object('t', 'p', 'text', 'Week of ' || to_char(w.week, 'Dy DD Mon YYYY') || ' (Asia/Dubai). '
      || (select count(*) from jsonb_array_elements(w.targets) x where (x->>'met')::boolean and not coalesce((x->>'info_only')::boolean, false)) || ' of '
      || (select count(*) from jsonb_array_elements(w.targets) x where not coalesce((x->>'info_only')::boolean, false)) || ' targets met. Actions: ' || cardinality(w.opened) || ' opened, '
      || cardinality(w.escalated) || ' escalated, ' || cardinality(w.closed) || ' closed.'),
    jsonb_build_object('t', 'h3', 'text', 'Actions assigned'));

  -- escalated first, then the rest still open; each with owner, due date and the check that closes it
  for t in select jsonb_build_object('line',
             case when i.escalations > 0 then 'ESCALATED x' || i.escalations || ' ' else '' end
             || i.seat || ': ' || (select case when length(a) > 200 then left(a, 197) || '...' else a end
                                     from (select coalesce(i.evidence->>'action', i.proposal) as a) z)
             || ' Due ' || to_char(i.due_on, 'DD Mon') || '. ' || coalesce(i.close_check, ''))
             from public.ceo_improvement i
            where i.source_kind = 'weekly_review' and i.status in ('open', 'assigned')
            order by i.escalations desc, i.seat, i.id limit 12 loop
    li := li || jsonb_build_object('t', 'li', 'text', t->>'line');
  end loop;
  if jsonb_array_length(li) = 0 then li := jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'Every target is met; no action is open.')); end if;
  v := v || li;

  for t in select x from jsonb_array_elements(w.targets) x where x->>'key' in ('supply', 'runway', 'budget') loop
    v := v || jsonb_build_array(
      jsonb_build_object('t', 'h3', 'text', t->>'label'),
      jsonb_build_object('t', 'li', 'text', case when coalesce((t->>'info_only')::boolean, false) then 'INFORMATION ONLY. '
                                                        when (t->>'met')::boolean then 'MET. ' else 'MISSED. ' end
        || (t->>'actual') || '. Target: ' || (t->>'target') || '.'));
    if t->>'key' = 'supply' and jsonb_array_length(coalesce(t->'detail', '[]'::jsonb)) > 0 then
      v := v || jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'Shortest where demand is: ' ||
        (select string_agg((e->>'label') || ' ' || (e->>'matchable') || '/' || (select coalesce(category_open_min_suppliers, 10) from public.pricing_config order by id limit 1), ', ')
           from jsonb_array_elements(t->'detail') e)));
    end if;
  end loop;

  v := v || jsonb_build_array(jsonb_build_object('t', 'h3', 'text', 'Open risks'));
  li := coalesce((select jsonb_agg(jsonb_build_object('t', 'li', 'text', '#' || r.id || ' ' || left(r.risk, 110)
          || ' (owner ' || coalesce(r.owner_agent, 'none') || ', ' || r.probability || '/' || r.impact
          || coalesce(', review ' || to_char(r.review_due, 'DD Mon'), ', no review date') || ')') order by r.id)
          from (select * from public.risk_register where status = 'open' order by id limit 5) r), '[]'::jsonb);
  v := v || case when jsonb_array_length(li) = 0 then jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'None open.')) else li end;

  select string_agg((x->>'seat') || ' ' || coalesce(x->>'open_total', '0') || ' (' || (x->>'value') || ' over 7 days)', ', ' order by x->>'seat')
    into v_find from jsonb_array_elements(w.targets) x where x->>'key' = 'findings';
  v := v || jsonb_build_array(jsonb_build_object('t', 'h3', 'text', 'Open findings by seat'),
                              jsonb_build_object('t', 'li', 'text', coalesce(v_find, 'none')),
                              jsonb_build_object('t', 'note', 'text', 'Measured by code, no model. Each action is a tracked improvement; the next review closes it when its check passes, or escalates it.'));
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; v_week date := date_trunc('week', v_local)::date;
  w public.ceo_weekly_review; v_run jsonb;
begin
  select * into w from public.ceo_weekly_review where week = v_week;
  if not found then
    if extract(isodow from v_local) = 1 and v_local::time < time '09:00' then
      return jsonb_build_object('fired', false, 'reason', 'before Monday 09:00 Asia/Dubai', 'week', v_week);
    end if;
    v_run := public.fn_ceo_weekly_review(v_week);
    select * into w from public.ceo_weekly_review where week = v_week;
  end if;
  if w.delivered_at is not null then
    return jsonb_build_object('fired', false, 'reason', 'already delivered', 'week', v_week, 'id', w.id);
  end if;
  if w.pdf_path is null then
    return jsonb_build_object('fired', true, 'pdf_pending', true, 'id', w.id, 'report_key', 'ceo_weekly_review_' || to_char(v_week, 'IYYY-"W"IW'),
      'subject', 'CEO weekly review, week of ' || to_char(v_week, 'DD Mon YYYY'), 'pdf_blocks', w.pdf_blocks, 'run', v_run);
  end if;
  return public.fn_ceo_weekly_review_deliver(w.id) || jsonb_build_object('fired', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ceo_year_plan_status(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with c as (select id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active'),
       m as (select date_trunc('month', p_at at time zone 'Asia/Dubai')::date as m0)
  select jsonb_build_object('month', (select m0 from m),
    'plan', (select to_jsonb(y) from public.ceo_year_plan y, m where y.month = m.m0),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'kind', p.kind,
                 'direction', p.direction, 'month_target', p.value, 'day', v.day, 'expected', v.expected, 'actual', v.actual,
                 'gap_pct', v.gap_pct, 'status', v.status) order by p.owner_seat, p.metric_key)
        from public.target_path p join c on c.id = p.contract_id cross join m
        left join lateral (select * from public.target_daily_verdict d where d.contract_id = p.contract_id and d.metric_key = p.metric_key
                            and d.day <= (p_at at time zone 'Asia/Dubai')::date order by d.day desc limit 1) v on true
       where p.month = m.m0), '[]'::jsonb))
$function$


CREATE OR REPLACE FUNCTION public.fn_challenge(p_proposal text, p_proposed_by text DEFAULT 'founder'::text, p_challenger text DEFAULT 'brief'::text, p_subject jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_opts jsonb; v_held bigint; v_req jsonb; v_q text;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', 'h' || h.id,
           'meaning', 'it conflicts with priority rank ' || h.rank_touched || ' (' || h.principle || '): ' || h.concern)
           order by h.rank_touched, h.id), '[]'::jsonb)
    into v_opts from public.challenge_heuristic h where h.active;
  v_opts := v_opts || coalesce((select jsonb_agg(jsonb_build_object('id', 'm' || m.id,
           'meaning', 'it repeats an earlier attempt that ended ' || m.outcome || ': ' || left(m.headline, 200)) order by m.created_at desc)
      from (select id, headline, outcome, created_at from public.institutional_memory
             where outcome in ('worse', 'improved') order by created_at desc limit 5) m), '[]'::jsonb);
  v_opts := v_opts || jsonb_build_array(jsonb_build_object('id', 'none',
           'meaning', 'it conflicts with none of these principles and repeats none of these attempts'));

  v_q := 'Proposal by ' || coalesce(p_proposed_by, 'unknown') || ': ' || coalesce(p_proposal, '');
  v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.challenge', 'question', left(v_q, 8000),
    'context', jsonb_build_object('audience', 'internal'),
    'decision', jsonb_build_object('name', 'challenge', 'options', v_opts),
    'subject', jsonb_build_object('proposal', p_proposal, 'proposed_by', p_proposed_by, 'challenger', p_challenger) || coalesce(p_subject, '{}'::jsonb),
    'dedupeKey', 'challenge:' || md5(coalesce(p_proposal, '') || '|' || coalesce(p_challenger, '')));
  v_held := public.fn_reason_hold('ceo', 'ceo.challenge', left(v_q, 8000), v_req, '{}'::jsonb, v_req->'subject',
                                  'sql_caller', v_req->>'dedupeKey');
  return jsonb_build_object('id', null, 'stance', 'held', 'held_id', v_held, 'confidence', 0,
    'conflicts_with', null, 'evidence', '[]'::jsonb, 'alternatives', '[]'::jsonb,
    'reasoning', 'The challenge of this proposal is filed for reasoning (held question #' || v_held
      || '); no stance is taken from the words it happens to use.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_channel_requester(p_type text, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text;
begin
  v := case
    when p_type in ('invoice_ready','quote_accepted','reveal_receipt','new_inquiry','new_quote','new_message',
                    'clarification_requested','job_awarded_other','rfq_addendum','rfq_no_supplier',
                    'supplier_registered','registration_received','supplier_ack','supplier_invites',
                    'invite_paused_bounce','quote_coaching','cancel_warning','inquiry_edit_staled_quotes',
                    'licence_renewal','doc_final_notice','supplier_doc_expiry','doc_restored','doc_suspended',
                    'supplier_doc_applied','customer_success','reveal_no_response_notice',
                    'supplier_no_response_chase') then 'sales_engineer'
    when p_type in ('refund_issued','refund_action_failed','dues_paid','registration_paid','subscription_due',
                    'subscription_billing_summary','expense_logged','accountant_weekly_report',
                    'accountant_spend_report') then 'accountant'
    when p_type in ('founder_brief') then 'ceo'
    when p_type in ('it_engineer_handover','smoke_alert','ai_quality_alert','agent_escalation',
                    'wa_templates_ready') then 'it_engineer'
    when p_type in ('rating_request','doc_received','inbound_reply','contact_message') then 'customer_support'
    when p_type in ('login_otp','mobile_otp','voice_otp','email_confirmation_code') then 'platform'
  end;
  -- A founder notification names its seat in founder_mail_policy, the register that already governs it.
  if v is null then
    select f.owner_role into v from public.founder_mail_policy f
     where f.kind = coalesce(nullif(btrim(p_kind), ''), p_type);
  end if;
  if v = 'platform' then return v; end if;
  -- A seat that is not active today cannot be the requester; the channel's own seat stands in.
  if v is null or not exists (select 1 from public.org_role r where r.role_id = v and r.status = 'active') then
    v := 'customer_support';
  end if;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_channel_safe_volume(p_channel_key text, p_required numeric, p_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p record;
  v_safe numeric;
  v_weeks numeric;
begin
  if p_channel_key is null then
    return jsonb_build_object('applies', false);
  end if;

  select * into p from public.outreach_channel_policy where channel_key = p_channel_key;
  if not found then
    -- An unknown channel is not an unlimited one.
    return jsonb_build_object(
      'applies', true, 'ok', false, 'safe_max', 0,
      'reason', format('Channel %s has no policy. An unknown channel carries zero until someone declares its limit.', p_channel_key));
  end if;

  if p.status = 'blocked' then
    return jsonb_build_object(
      'applies', true, 'ok', false, 'safe_max', 0, 'status', p.status,
      'reason', format('Channel %s is BLOCKED. %s', p.channel_label, p.status_reason));
  end if;

  -- A warming channel does not get max_per_day times days. It gets the ramp, which compounds weekly
  -- from a small start. Treating a warming channel as if it were at full throughput on day one is
  -- how a domain gets burned in week one.
  if p.status = 'warming' and p.ramp_start_per_day is not null then
    v_weeks := ceil(p_days / 7.0);
    -- sum of a geometric ramp: start*7 * ((1+g)^weeks - 1) / g
    if coalesce(p.ramp_weekly_growth, 0) > 0 then
      v_safe := p.ramp_start_per_day * 7 *
                ((power(1 + p.ramp_weekly_growth, v_weeks) - 1) / p.ramp_weekly_growth);
    else
      v_safe := p.ramp_start_per_day * p_days;
    end if;
    if p.max_per_day is not null then
      v_safe := least(v_safe, p.max_per_day * p_days);
    end if;
  else
    v_safe := coalesce(p.max_per_day, 0) * greatest(p_days, 0);
    if p.max_per_week is not null then
      v_safe := least(v_safe, p.max_per_week * ceil(p_days / 7.0));
    end if;
  end if;

  return jsonb_build_object(
    'applies', true,
    'ok', p_required <= v_safe,
    'status', p.status,
    'channel_label', p.channel_label,
    'safe_max', round(v_safe, 0),
    'required', round(coalesce(p_required, 0), 0),
    'shares_transactional_reputation', p.shares_transactional_reputation,
    'requires_opt_in', p.requires_opt_in,
    'reason', case
      when p_required <= v_safe then format('%s can safely carry %s over %s days.', p.channel_label, round(v_safe,0), p_days)
      else format('%s can safely carry %s over %s days, but the plan needs %s. %s',
                  p.channel_label, round(v_safe,0), p_days, round(p_required,0),
                  case when p.shares_transactional_reputation
                       then 'This channel shares a reputation with transactional mail, so exceeding it risks sign-in codes and receipts, not just the campaign.'
                       else 'Exceeding a channel''s safe throughput risks the channel itself.' end)
    end
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_check_spend(p_dept text, p_amount numeric, p_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_avail numeric; v_month numeric; v_limit numeric; v_route text; v_afford boolean;
  v_tier text; v_gated boolean := false;
begin
  p_agent := coalesce(public.fn_org_agent_resolve(p_agent), p_agent);
  select coalesce(monthly_aed,0), fn_budget_available(p_dept) into v_month, v_avail
  from department_budget where dept_key = p_dept;

  if v_month is null then
    return jsonb_build_object('ok', false, 'reason',
      'no budget is recorded for department "' || p_dept || '", so no spend can be authorised against it',
      'route_to','finance');
  end if;

  v_afford := coalesce(p_amount,0) <= v_avail;

  select max(threshold_aed) into v_limit
  from employee_authority where agent_key = p_agent;

  -- REPUTATION REACHES THE MOMENT THE MONEY WOULD MOVE.
  -- fn_reputation_recompute already demotes a probation-tier employee's max_tier from 'autonomous'
  -- to 'gated'; until now nothing consulted that at the point of spend, so a demoted employee kept
  -- their nominal ceiling. On probation the personal limit does not apply and the spend goes to a
  -- person — the same decision, applied where it bites.
  select r.tier into v_tier from agent_reputation r where r.agent_key = p_agent;
  if v_tier = 'probation' then v_gated := true; v_limit := 0; end if;

  v_route := case
    when coalesce(p_amount,0) >  10000 then 'founder'
    when coalesce(p_amount,0) >= 1000  then 'brief'
    -- a gated employee is never the approver of their own spend
    when v_gated then 'brief'
    else coalesce(p_agent,'department head') end;

  return jsonb_build_object(
    'ok', v_afford and (v_limit is null or coalesce(p_amount,0) <= v_limit),
    'affordable', v_afford,
    'requested_aed', coalesce(p_amount,0),
    'available_aed', v_avail,
    'monthly_aed', v_month,
    'agent_limit_aed', v_limit,
    'reputation_tier', coalesce(v_tier,'ungraded'),
    'route_to', v_route,
    'reason', case
      when not v_afford then format('Requested AED %s exceeds the AED %s remaining in the %s budget this period. Reduce the scope, defer to next period, or ask Finance to reallocate.', coalesce(p_amount,0), v_avail, p_dept)
      when v_gated then format('Affordable, but %s is on probation in the reputation system, so their personal spending limit does not apply. Route to %s.', coalesce(p_agent,'this employee'), v_route)
      when v_limit is not null and coalesce(p_amount,0) > v_limit then format('Affordable, but AED %s is above %s''s personal limit of AED %s. Route to %s.', coalesce(p_amount,0), p_agent, v_limit, v_route)
      else format('Within budget: AED %s of AED %s available. Approver: %s.', coalesce(p_amount,0), v_avail, v_route) end);
end; $function$


CREATE OR REPLACE FUNCTION public.fn_classify_llm_failure(p_err text, p_http_status integer DEFAULT NULL::integer, p_finish_reason text DEFAULT NULL::text, p_model text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e text := coalesce(p_err, '');
  k text;
  truncated boolean;
begin
  -- ai_gateway slices lastErr to exactly 200 chars. At 200 the evidence stops before `choices`,
  -- so anything read past that point would be a guess. Say so rather than infer.
  truncated := length(e) >= 200;

  k := case
    -- BILLING FIRST (added 14 Aug 2026). Stable across every OpenRouter model, and not
    -- retryable: retrying an out-of-credit request cannot succeed and burns the wall budget.
    when p_http_status = 402
      or e ~* '(requires more credits|insufficient[_ ]credit|can only afford|quota exceeded|payment required)'
      then 'insufficient_credit'
    -- credentials first: deterministic, and must never be retried
    when p_http_status in (401, 403)
      or e ~* '(unauthor|forbidden|invalid api key|no auth credentials|api[_ ]?key missing)'
      then 'unauthorised'
    when p_http_status = 429
      or e ~* '(rate[ _-]?limit|too many requests|quota exceeded|insufficient (credits|quota)|capacity)'
      then 'rate_limited'
    -- our own stopwatch reads as a model failure unless it is named
    when e ~* '(signal has been aborted|aborterror|the operation was aborted|timed? ?out|etimedout|deadline|gateway_deadline)'
      then 'timeout'
    when e ~* '(not a valid model|model not found|no endpoints found|unknown model|no allowed providers)'
      then 'route_not_registered'
    when p_model is not null
      and not exists (select 1 from model_registry r where r.model_id = p_model and r.active)
      then 'route_not_registered'
    -- a REAL provider error object, or a 5xx with no payload
    when e ~ '"error"\s*:' or e ~* '^\s*\{"error"'
      or (p_http_status between 500 and 599 and e !~ '"object"\s*:\s*"chat\.completion"')
      then 'provider_error'
    -- the shape the certification actually hit
    when e ~ '"object"\s*:\s*"chat\.completion"' or e ~ '^\s*\{"id"\s*:\s*"gen-'
      then 'empty_completion'
    when lower(coalesce(p_finish_reason,'')) = 'length'
      or e ~* '(unexpected end of json|unparseable|invalid json|json parse|content_filter)'
      then 'malformed_output'
    when e ~* '(tool[_ ]call|tool result|tool failed|function call failed)'
      then 'tool_failure'
    when e ~* '(embedding|kb_match|retriev|context slice|no chunks)'
      then 'retrieval_failure'
    when e ~* '(pgrst|sqlstate|does not exist|deadlock detected|connection (reset|refused|closed)|relation .* does not exist)'
      then 'database_failure'
    when e ~* '(route_failed|no route|no model policy|budget|spend guard|ladder empty)'
      then 'orchestration_failure'
    when e ~* '(harness|fixture|test runner|seed(ing)? failed)'
      then 'test_runner_failure'
    else 'unclassified'
  end;

  return jsonb_build_object(
    'class_key', k,
    'retryable', (select retryable from llm_failure_class where class_key = k),
    'max_retries', (select max_retries from llm_failure_class where class_key = k),
    'retry_backoff_ms', (select retry_backoff_ms from llm_failure_class where class_key = k),
    'trips_breaker', (select trips_breaker from llm_failure_class where class_key = k),
    'opens_on_first', (select opens_on_first from llm_failure_class where class_key = k),
    -- honesty flag: the caller learns the evidence was cut off, so 'empty_completion' is never
    -- mistaken for a diagnosed root cause
    'evidence_truncated', truncated,
    'latency_ms', p_latency_ms
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_brief(p_max_chars integer DEFAULT 1600)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb; out text; d jsonb;
begin
  s := fn_company_state();
  out := 'COMPANY SELF-KNOWLEDGE (authoritative org facts — you may answer any question about the company from this):'||E'\n'
       ||'Vision: '||(s->>'vision')||E'\n'
       ||'Totals: '||(s->'totals'->>'departments')||' departments, '||(s->'totals'->>'brain_agents')||' brain agents, '
       ||(s->'totals'->>'category_sales_agents')||' category sales agents, '||(s->'totals'->>'tools_wired')||' wired tools, '
       ||(s->'totals'->>'open_objectives')||' open objectives, '||(s->'totals'->>'open_tasks')||' open tasks.'||E'\n'
       ||'Departments (lead · brain agents · north star):'||E'\n';
  -- No departments since 7 Sep 2026: fn_company_state() returns null for them, which is not an array. Read it as
  -- an empty list rather than fail every self-knowledge sync (22023, measured 24 Sep 2026).
  for d in select * from jsonb_array_elements(case when jsonb_typeof(s->'departments') = 'array' then s->'departments' else '[]'::jsonb end) loop
    out := out || '- '||(d->>'name')||' ['||(d->>'dept')||']: lead '||coalesce(d->>'lead_agent','—')
                || ', '||(d->>'headcount')||' agent(s)';
    if jsonb_array_length(d->'brain_agents') > 0 then
      out := out || ' ('||replace(replace(replace((d->'brain_agents')::text,'"',''),'[',''),']','')||')';
    end if;
    out := out || ', north star: '||coalesce(d->>'north_star','—')||E'\n';
    exit when length(out) > p_max_chars;
  end loop;
  return left(out, greatest(p_max_chars, 400));
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_connectivity_register()
 RETURNS TABLE(gap_class text, subject text, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with external_intake(event_type) as (values
       ('inquiry.created'),    -- marketplace edge (supplier_portal / customer intake)
       ('rfq.created'),        -- marketplace edge function
       ('quote.received'),     -- marketplace edge function
       ('lead.qualified'),     -- inbound sales-lead intake (no internal producer until a sales surface exists)
       ('contract.submitted'), -- third-party contract intake (arrives from counterparties)
       ('deploy.completed')    -- CI / deploy hook (scripts/deploy_functions.mjs)
  ),
  -- Event types a non-dispatcher trigger on company_event consumes: a few trigger bodies against
  -- the distinct types, not against every event row.
  trigger_consumed(event_type) as (
    select distinct et.event_type
      from (select distinct ce.event_type from public.company_event ce) et
      join (select p.prosrc from pg_trigger t
              join pg_class c on c.oid = t.tgrelid
              join pg_namespace n on n.oid = c.relnamespace
              join pg_proc p on p.oid = t.tgfoid
             where n.nspname = 'public' and c.relname = 'company_event'
               and not t.tgisinternal and t.tgenabled <> 'D'
               and p.proname <> 'trg_company_event_dispatch') tf
        on tf.prosrc like '%' || et.event_type || '%'
  ),
  -- Every event type some database code can emit: a literal in a routine body, or a literal
  -- argument on a trigger (fn_emit_event reads the type from tg_argv, so the body never names it).
  producer(event_type) as (
    select distinct e.event_type
      from (select distinct ce.event_type from public.company_event ce
            union select es.event_type from public.event_subscription es
            union select w.trigger_event from public.workflow w where w.trigger_event is not null) e
     where exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.prosrc like '%''' || e.event_type || '''%')
        or exists (select 1 from pg_trigger t
                    where not t.tgisinternal
                      and pg_get_triggerdef(t.oid) like '%''' || e.event_type || '''%')
  )
  -- A · a live workflow step with a side-effect action_class and no active executor. Nothing can
  -- perform the step; the workflow stalls at it. (Mirror of v_workflow_side_effects_without_executor.)
  select 'step_without_executor',
         w.workflow_key || ' step ' || s.step_no,
         'action_class ' || s.action_class || ' has no active org_action_executor'
    from public.workflow w
    join public.workflow_step s on s.workflow_key = w.workflow_key
    left join public.org_action_executor e on e.action_class = s.action_class and e.active
   where w.active and s.action_class is not null and e.action_class is null

  union all
  -- B · a live workflow step whose actor_role the RUNTIME resolver (fn_org_agent_resolve, the same
  -- function the dispatcher and handoff paths use) cannot resolve to any agent. Excluded: 'owner' and
  -- 'Director' in the generic employee_task workflow — those are CONTEXTUAL roles resolved per task
  -- from the task's own assigned_agent / manager, never global agents, so a null here is correct.
  select distinct 'actor_role_unresolved',
         s.actor_role,
         'used in active workflow steps; fn_org_agent_resolve() returns null'
    from public.workflow_step s
    join public.workflow w on w.workflow_key = s.workflow_key and w.active
   where s.actor_role is not null
     and s.actor_role not in ('owner', 'Director')                       -- contextual (employee_task)
     and public.fn_org_agent_resolve(s.actor_role) is null

  union all
  -- C · an event_type that has ACTUALLY been emitted into company_event but has no active subscriber.
  -- The dispatcher (fn_event_dispatch) delivers only through event_subscription, so such an event
  -- reaches no one. Excluded: 'task.assigned' — task assignment is delivered by the direct
  -- fn_org_task_assign path (the org_task row IS the delivery); a bus subscriber would double-create.
  -- Excluded since 4 Sep 2026: a RETIRED type — history in company_event, no producer left in the
  -- catalogue, not an external-intake type — because nothing can emit it again. Re-add an emitter
  -- and the row returns.
  select distinct 'event_emitted_no_subscriber',
         ce.event_type,
         'emitted into company_event, no active event_subscription — the dispatcher delivers it nowhere'
    from public.company_event ce
   where ce.event_type <> 'task.assigned'
     and not exists (select 1 from public.event_subscription es
                      where es.active and es.event_type = ce.event_type)
     -- 5 SEP 2026: a consumer is also a TRIGGER on company_event -- one that is not the generic
     -- dispatcher and whose function body names the event type (MASTER_PLAN 4.4 routes
     -- priority.updated to trg_priority_backlog_reorder, a named consumer with no subscription).
     -- 6 SEP 2026: computed ONCE in the trigger_consumed CTE. The first version correlated a
     -- LIKE over every trigger body per company_event row; the register went from seconds to
     -- past the cron's 120s statement_timeout and the red-view alerter's 21:22Z tick failed.
     and not exists (select 1 from trigger_consumed tc where tc.event_type = ce.event_type)
     and (exists (select 1 from producer p where p.event_type = ce.event_type)
          or exists (select 1 from external_intake x where x.event_type = ce.event_type))

  union all
  -- D · an active subscription pointing at an agent that is missing or inactive. The dispatcher joins
  -- company_event -> event_subscription -> org_agents on agent_key (it does NOT run the resolver), so
  -- the event is delivered to a dormant agent and dies there. Repoint to the active successor.
  select 'dead_subscription',
         es.event_type || ' -> ' || es.agent_key,
         case when a.agent_key is null then 'subscriber agent does not exist'
              else 'subscriber agent is inactive' end
    from public.event_subscription es
    left join public.org_agents a on a.agent_key = es.agent_key
   where es.active and (a.agent_key is null or not a.active)

  union all
  -- E · an active rpc executor whose target needs arguments the queue invoker cannot supply AND whose
  -- action_class is actually reachable from a live workflow step. fn_action_invoke_rpc fails any
  -- args>0 target, so a reachable one is a guaranteed runtime failure. (Registry rows for functions
  -- called only directly, never queued from a step, are not gaps and are excluded by the step join.)
  select distinct 'executor_target_needs_args',
         e.action_class || ' -> ' || e.target,
         'rpc target requires ' || (p.pronargs - p.pronargdefaults)::text
           || ' arg(s) with no default; reachable from a live workflow step; the queue invoker cannot call it'
    from public.org_action_executor e
    join pg_proc p on p.proname = e.target and p.pronamespace = 'public'::regnamespace
    join public.workflow_step s on s.action_class = e.action_class
    join public.workflow w on w.workflow_key = s.workflow_key and w.active
   where e.active and e.kind = 'rpc' and (p.pronargs - p.pronargdefaults) > 0
     -- 5 SEP 2026: the invoker now supplies ONE argument -- a single jsonb parameter receives
     -- params || request || {action_execution_id} (fn_action_invoke_rpc, the change_deployment
     -- packet). A target whose only required argument is that one jsonb is callable, and three
     -- such targets (change_deploy_baseline/promote/grade -> fn_change_deployment_execute) were
     -- read as gaps by the old rule and paged the founder on 5 Sep. Any other required argument
     -- is still a gap the invoker cannot fill.
     and not ((p.pronargs - p.pronargdefaults) = 1 and p.pronargs = 1
              and p.proargtypes[0] = 'jsonb'::regtype)

  union all
  -- F · an active workflow whose trigger_event has NO producer, so it can never auto-start. The live
  -- loop starts a workflow only when a company_event.event_type equals a workflow.trigger_event (via
  -- fn_workflow_start_due), so a trigger nothing emits is a workflow that never runs. "Has a producer"
  -- = some db function body or trigger argument contains the event literal (an emitter) OR the event
  -- has already occurred in company_event. Excluded: the declared EXTERNAL-INTAKE events, which arrive
  -- from real inbound traffic (edge functions, sales/contract intake, the CI deploy hook), not an
  -- internal db producer — they are wired at the edge layer and fire when that traffic is real.
  select 'workflow_trigger_has_no_producer',
         w.workflow_key,
         'trigger_event ' || w.trigger_event || ' is emitted by no db function or trigger, has never occurred, and '
           || 'is not a declared external-intake event — the workflow can never auto-start'
    from public.workflow w
   where w.active and w.trigger_event is not null
     and not exists (select 1 from public.company_event ce where ce.event_type = w.trigger_event)
     and not exists (select 1 from producer p where p.event_type = w.trigger_event)
     and not exists (select 1 from external_intake x where x.event_type = w.trigger_event)

  union all
  -- G · an active subscription to an event type NOTHING can emit: no routine body names it, no
  -- trigger argument names it, it has never occurred, and it is not a declared external-intake event.
  -- The dispatcher would wait for it forever (MASTER_PLAN §5.1 "phantom subscriptions").
  select distinct 'subscription_without_producer',
         es.event_type || ' -> ' || es.agent_key,
         'active subscription; no db function or trigger emits this event type, it has never occurred, '
           || 'and it is not a declared external-intake event'
    from public.event_subscription es
   where es.active
     and not exists (select 1 from public.company_event ce where ce.event_type = es.event_type)
     and not exists (select 1 from producer p where p.event_type = es.event_type)
     and not exists (select 1 from external_intake x where x.event_type = es.event_type)
$function$


CREATE OR REPLACE FUNCTION public.fn_company_context(p_max_chars integer DEFAULT 16000, p_audience text DEFAULT 'internal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reg      record;
  v_vis      record;
  v_pct      numeric;
  v_fee      numeric;
  v_freen    int;
  v_starts   date;
  v_core     text;
  v_tail     text := '';
  v_add      text;
  v_seats    text := '';
  v_block    text;
  v_missing  text[] := '{}';
  v_budget   int := greatest(coalesce(p_max_chars, 9000), 4000);
  v_trunc    boolean := false;
  r          record;
  v_pub      boolean := coalesce(lower(btrim(p_audience)), 'internal') = 'public';
begin
  select * into v_reg from public.company_registration order by recorded_at desc nulls last limit 1;
  select vision, mission into v_vis from public.company_vision order by id limit 1;
  select coalesce(standard_reveal_rate, 0.03) * 100, supplier_reg_fee,
         coalesce(supplier_free_count, 1000), supplier_charging_starts
    into v_pct, v_fee, v_freen, v_starts
    from public.pricing_config order by id limit 1;

  -- A MISSING FACT IS NAMED, NEVER PAPERED OVER. A block that silently drops the licence because
  -- the row went missing reads exactly like a block that never had one, and a seat would answer
  -- from memory. 'complete' is what the check asserts on.
  if v_reg.license_no is null then v_missing := v_missing || 'company_registration.license_no'; end if;
  if v_vis.mission   is null then v_missing := v_missing || 'company_vision.mission';           end if;
  if v_pct           is null then v_missing := v_missing || 'pricing_config.standard_reveal_rate'; end if;

  for r in
    select a.agent_key,
           coalesce(nullif(btrim(a.title), ''), ro.display_name, a.agent_key) as display,
           coalesce(nullif(btrim(a.role), ''), '')                            as role_text,
           coalesce(array_to_string(ro.escalation_targets, ', '), '')         as escalates_to
      from public.org_agents a
      left join public.org_role ro
        on ro.runtime_agent_key = a.agent_key and ro.status = 'active'
     where a.active
     order by a.agent_key
  loop
    v_seats := v_seats || '- ' || r.agent_key || ' (' || r.display || ')'
      || case when r.escalates_to <> '' then ' -- escalates to ' || r.escalates_to else '' end
      || case when r.role_text  <> '' then ': ' || left(r.role_text, 220) else '' end
      || E'\n';
  end loop;

  v_core :=
     '# QUOTESDONE -- COMPANY KNOWLEDGE. Every seat carries this block. It is composed from the live'
  || ' operational tables at call time; no figure in it is written into any routine. It is what you'
  || ' answer FROM about the company, and none of it may be relaxed, discounted or improvised on.'
  || E'\n\n'
  || '## 1. WHO WE ARE' || E'\n'
  || 'Trade name: ' || coalesce(v_reg.trade_name, '(not on record)') || '.'
  || ' Owner: ' || coalesce(v_reg.owner_name, '(not on record)')
  || coalesce(' ' || v_reg.owner_share, '') || ' -- he is the founder, Chairman and CEO.' || E'\n'
  || 'Licensing authority: ' || coalesce(v_reg.authority, '(not on record)') || '.'
  || ' Licensed activities: ' || coalesce(v_reg.activities, '(not on record)') || '.' || E'\n'
  || 'Registered contact: ' || coalesce(v_reg.registered_email, '-')
  || ' / ' || coalesce(v_reg.registered_mobile, '-') || '.' || E'\n'
  || 'Online: ' || coalesce(v_reg.e_stores, '-') || E'\n'
  || 'Vision: ' || coalesce(v_vis.vision, '(not on record)') || E'\n'
  || 'Mission: ' || coalesce(v_vis.mission, '(not on record)') || E'\n\n'
  || '## 2. WHAT WE SELL' || E'\n'
  || 'A UAE B2B anonymous quotation marketplace for construction, fit-out and related supply. A buyer'
  || ' posts an RFQ describing a job or a product; verified UAE suppliers submit quotations without'
  || ' either side seeing the other; the buyer compares them FREE of charge and pays a '
  || coalesce(round(v_pct, 2)::text, '3') || '% reveal fee on the value of the quotation it selects to'
  || ' unlock that supplier''s identity and contact details. Suppliers pay NO commission -- ever.'
  || ' Supplier registration is free for the first ' || v_freen || ' registrations and AED '
  || coalesce(v_fee::text, '1000') || ' per year after that'
  || case when v_starts is null
          then ' -- there is NO calendar deadline: charging begins with registration number '
               || (v_freen + 1) || ', whenever that happens (founder ruling, 6 Sep 2026).'
          else ', charged from ' || to_char(v_starts, 'DD Mon YYYY') || '.' end
  -- Internal only (instruction 777): a statement of how many customers exist is a figure.
  || case when v_pub then '' else
     ' The company is PRE-LAUNCH: no real customer, inquiry, quotation or transaction exists yet, and'
  || ' that is a fact about the stage, never a reason to answer as if a capability were missing.' end
  || E'\n\n'
  || '## 3. THE HARD RULES -- the founder''s only rules; no employee may relax them' || E'\n'
  -- The category-opening rule carries an internal supplier threshold (instruction 777); the public
  -- block states the matching rule as a capability instead.
  || case when v_pub
          then regexp_replace(public.fn_company_hard_rules(), '\n5\. CATEGORY OPENING[^\n]*',
                 E'\n5. MATCHING: every request goes only to verified suppliers of its exact trade, never to a'
                 || ' neighbouring one, and new trades are welcome.')
          else public.fn_company_hard_rules() end || E'\n'
  || '## 4. LICENCE, TAX AND AUDIT' || E'\n'
  || 'Licence ' || coalesce(v_reg.license_no, '(none on record)')
  || coalesce(' (' || v_reg.license_type || ')', '')
  || coalesce(', issued ' || to_char(v_reg.issued_on, 'DD Mon YYYY'), '')
  || coalesce(', EXPIRES ' || to_char(v_reg.expires_on, 'DD Mon YYYY'), '')
  || coalesce(', issued by ' || v_reg.authority, '') || '.' || E'\n'
  || coalesce(v_reg.license_class_note || E'\n', '')
  || 'VAT: '
  || case when coalesce(v_reg.vat_registered, false)
          then 'REGISTERED' || coalesce(', TRN ' || v_reg.trn, '') || '.'
          -- The turnover threshold tells a stranger what our revenue is below (instruction 777).
          when v_pub then 'NOT registered; no invoice carries VAT.'
          else 'NOT registered, and registration is NOT required until taxable turnover reaches the'
               || ' AED ' || coalesce(to_char(v_reg.vat_threshold_aed, 'FM999,999,999'), '375,000')
               || ' threshold. No invoice carries VAT and no agent asks the founder about it again'
               || ' (founder ruling, ' || coalesce(to_char(v_reg.vat_ruling_on, 'DD Mon YYYY'), '6 Sep 2026') || ').' end
  || E'\n'
  -- Both notes reason about revenue thresholds and internal roles: internal only (instruction 777).
  || case when v_pub then '' else
        coalesce('Corporate tax: ' || v_reg.corporate_tax_note || E'\n', '')
     || coalesce('Auditor: ' || v_reg.auditor || E'\n', '') end
  || E'\n';

  -- A PUBLIC BLOCK STOPS HERE, AND SAYS SO. Silently ending after section 4 would read to a model
  -- as "this company has four seats' worth of nothing behind it"; naming the boundary tells it the
  -- rest exists and is not its to discuss.
  if coalesce(lower(btrim(p_audience)), 'internal') = 'public' then
    v_block := v_core
      || '## 5. WHAT IS NOT IN THIS BLOCK' || E'\n'
      || 'This is the PUBLIC company block, for a surface a stranger can talk to. The internal'
      || ' sections -- who staffs the company, the founder''s standing decisions and the revenue'
      || ' targets -- are deliberately withheld. Never speculate about them, and never state a'
      || ' company fact that is not written above.' || E'\n';
    return jsonb_build_object(
      'block', v_block, 'chars', length(v_block), 'truncated', false,
      'complete', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
      'audience', 'public', 'as_of', now(), 'fingerprint', md5(v_block),
      'rule', 'The PUBLIC half of the company knowledge: identity, what we sell, the published hard '
           || 'rules, the licence and the tax position, all read from the live tables at call time. '
           || 'Never state a fee, date, licence number, threshold or policy that is not in it.');
  end if;

  v_core := v_core
  || '## 5. THE SEATS -- the whole company. There are no departments: the founder removed the'
  || ' organisation chart totally on 7 September 2026, and no seat may invent another one.' || E'\n'
  || coalesce(nullif(v_seats, ''), '(no active seat on record)')
  || E'\n';

  -- SECTIONS 6 AND 7 ARE THE BUDGETED TAIL. Sections 1-5 are never truncated: they are the answer
  -- to "where do I work and what are the rules", and a block that loses the reveal fee to a
  -- character budget is worse than no block at all.
  v_add := '## 6. THE FOUNDER''S STANDING DECISIONS -- settled; never ask him about any of them again'
        || E'\n';
  for r in
    select decision_key, decision_text
      from public.company_policy_decision
     where coalesce(never_ask_again, true)
     order by decision_key
  loop
    if length(v_core) + length(v_add) + length(r.decision_text) + 8 > v_budget then
      v_trunc := true; exit;
    end if;
    v_add := v_add || '- ' || r.decision_key || ': ' || r.decision_text || E'\n';
  end loop;
  if v_trunc then
    v_add := v_add || '(cut for length -- there are more standing decisions than fit this budget.'
          || ' Read public.company_policy_decision, or call fn_company_context with a larger'
          || ' p_max_chars, before answering anything that turns on one.)' || E'\n';
  end if;
  v_tail := v_tail || v_add || E'\n';

  v_add := '## 7. WHAT THE COMPANY IS AIMING AT' || E'\n';
  declare
    v_cut7 boolean := false;
  begin
  for r in
    select contract_key, objective, deadline, accountable_owner
      from public.target_contract
     where status = 'active'
     order by priority nulls last, contract_key
  loop
    if length(v_core) + length(v_tail) + length(v_add) + length(r.objective) + 60 > v_budget then
      v_trunc := true; v_cut7 := true; exit;
    end if;
    v_add := v_add || '- ' || r.contract_key || ': ' || r.objective
          || ' (by ' || coalesce(r.deadline::text, 'no deadline')
          || ', owned by ' || coalesce(r.accountable_owner, 'unassigned') || ')' || E'\n';
  end loop;
  if v_cut7 then
    v_add := v_add || '(cut for length -- read public.target_contract where status = ''active'','
          || ' or call fn_company_context with a larger p_max_chars.)' || E'\n';
  end if;
  v_tail := v_tail || v_add;
  end;

  v_block := v_core || v_tail;

  return jsonb_build_object(
    'block',       v_block,
    'chars',       length(v_block),
    'truncated',   v_trunc,
    'complete',    cardinality(v_missing) = 0,
    'missing',     to_jsonb(v_missing),
    'audience',    'internal',
    'as_of',       now(),
    'fingerprint', md5(v_block),
    'sources',     jsonb_build_array('company_registration', 'company_vision', 'pricing_config',
                                     'decision_policy', 'company_policy_decision', 'org_agents',
                                     'org_role', 'target_contract',
                                     'fn_company_hard_rules() (pricing_config + decision_policy + pages.legal_supplier_body)'),
    'rule',        'This is the COMPANY knowledge every seat carries, read from the live tables at '
                || 'call time. It is not advisory and it is not rankable: it holds even when the '
                || 'seat''s own retrieval finds nothing, which is exactly when a seat is most '
                || 'tempted to improvise. Never state a fee, date, licence number, threshold or '
                || 'policy that is not in this block.');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_company_facts_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; pct text; capnote text; txt text; regline text;
begin
  select * into c from pricing_config where id=1; if c is null then return; end if;

  pct := trim(to_char(coalesce(c.standard_reveal_rate,0)*100,'FM990.##'))||'%';
  capnote := 'NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal - the founder''s decision of 6 Sep 2026, enforced by a pricing_config constraint';

  -- The registration sentence is DERIVED. 6 Sep 2026 (founder): "dont use a deadline with dates" -
  -- a NULL start date is the rule itself, never a gap to ask him about.
  if c.supplier_charging_starts is null then
    regline := 'Supplier registration is FREE for the first ' || c.supplier_free_count || ' verified registrations, and those '
            || c.supplier_free_count || ' suppliers are exempt PERMANENTLY. Every registration after them pays a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of ' || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || '. There is NO calendar start date and there will not be one: '
            || 'charging begins with registration number ' || (c.supplier_free_count + 1) || ', whenever that happens. '
            || 'Never state a date, never ask the founder for one. ';
  else
    regline := 'Supplier registration is FREE for EVERY supplier until '
            || to_char(c.supplier_charging_starts - 1, 'FMDD FMMonth YYYY') || '. '
            || 'From ' || to_char(c.supplier_charging_starts, 'FMDD FMMonth YYYY') || ' a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of '
            || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || ' applies, and it is NOT charged '
            || 'before that date. The first ' || c.supplier_free_count || ' businesses to register are '
            || 'exempt PERMANENTLY and never pay it - that exemption does not expire. ';
  end if;

  txt := 'PRICING & FEES - LIVE, AUTO-SYNCED FROM pricing_config (authoritative; OVERRIDES any pricing figure stated elsewhere). '
    ||'Customer REVEAL FEE: '||pct||' of the accepted quotation value ('||capnote||'), paid by the customer to unlock their chosen supplier. '
    ||'On top of it the customer pays the CARD PROCESSING FEE (the Stripe fee, grossed up so QuotesDone receives the full '||pct||'); both are shown in full before payment. '
    ||'QuotesDone is NOT VAT registered: NO VAT is charged on the reveal fee - never say the fee is VAT-inclusive or that VAT is added. '
    ||'Suppliers pay NO commission on won jobs. '
    ||regline
    ||'CATEGORY OPENING: a category is OPEN once it has '||coalesce(c.category_open_min_suppliers,10)||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. '
    ||'Non-response window: '||c.refund_window_working_days||' working days from the customer''s payment - if a revealed supplier stays silent through the chase and the CEO''s final call, EVERYTHING the customer paid (the reveal fee) is refunded; the supplier is charged under the Supplier Agreement version it had accepted at the reveal (fn_accountant_nonresponse_charge): under v14 the exact amount refunded + the payment processor fee QuotesDone could not recover + an AED 500 administrative fee + simple interest at 12% a year (the agreed rate) from the due date + if unpaid the official recovery fees; under v13 the refund + AED 500 + 9%; under v12 or earlier the refund + AED 250 + 9%. It is blocked from matching until paid. '
    ||'There is NO 2% fee and NO supplier commission - never quote those. (Auto-updated '||to_char(now(),'YYYY-MM-DD HH24:MI')||' UTC.)';

  update agent_knowledge set content=txt, priority=100, updated_at=now()
    where agent_key='_global' and topic='Pricing & fees (LIVE — auto-synced)';
  if not found then
    insert into agent_knowledge(agent_key,topic,content,priority,updated_at)
      values ('_global','Pricing & fees (LIVE — auto-synced)',txt,100,now());
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_faq_text_change_clears_embedding()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if (new.question is distinct from old.question or new.answer is distinct from old.answer)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_hard_rules()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pct numeric; v_free date; v_fee numeric; v_win int; v_chase int; v_bmin int; v_bmax int; v_admin numeric; v_int numeric;
  v_free_n int; v_cat_min int;
  v_txt text; v_days text; v_aed text; v_mult text; v_src text;
begin
  select round(coalesce(standard_reveal_rate, 0.03) * 100, 2), supplier_charging_starts, supplier_reg_fee,
         refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count, 1000), coalesce(category_open_min_suppliers, 10)
    into v_pct, v_free, v_fee, v_win, v_chase, v_bmin, v_bmax, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  v_pct := coalesce(v_pct, 3); v_win := coalesce(v_win, 5); v_chase := coalesce(v_chase, 3);
  v_free_n := coalesce(v_free_n, 1000); v_cat_min := coalesce(v_cat_min, 10);
  -- 6 Sep 2026: the money side of the ladder, from decision_policy (founder ruling, verbatim there)
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_int   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);

  v_txt := regexp_replace(coalesce((select p.html from public.pages p where p.slug = 'legal_supplier_body'), ''),
                          '<[^>]+>', ' ', 'g');
  v_days := substring(v_txt from 'begin responding to the Customer within\s+([0-9]+)\s+working days');
  v_aed  := substring(v_txt from 'liquidated compensation of AED\s+([0-9,]+)\s+per incident');
  v_mult := substring(v_txt from 'per incident, or\s+([a-z]+ \([0-9]+\)|[0-9]+)\s+times the fee');
  v_src  := case when v_days is not null and v_aed is not null and v_mult is not null
                 then 'read from the published Supplier Agreement and pricing_config just now'
                 else 'pricing_config live; the Supplier Agreement text did not match the expected clause wording, so the last published figures are stated' end;

  return '# THE FOUR HARD RULES - the published Terms and Supplier Agreement; the founder''s ONLY rules ('||v_src||'). No employee may relax them.'||E'\n'
    ||'1. REVEAL FEE: the CUSTOMER pays '||v_pct||'% of the selected quotation value - NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal (founder, 6 Sep 2026; pricing_config forbids them by constraint) - ex-VAT, once per reveal, to reveal a supplier. Comparing quotes is FREE. Suppliers pay NO commission, ever'
    ||case when v_free is not null
           then '; supplier registration is free until '||to_char(v_free - 1, 'DD Mon YYYY')||', then AED '||coalesce(v_fee::text,'1000')||'/year (first '||v_free_n||' registrants permanently exempt)'
           else '; supplier registration is FREE for the first '||v_free_n||' registrations (permanently exempt), then AED '||coalesce(v_fee::text,'1000')||'/year - there is NO calendar start date: charging begins with registration '||(v_free_n + 1)||', whenever that happens (founder, 6 Sep 2026)' end||'.'||E'\n'
    ||'2. TOP-3 COMPARISON REPORT: however many quotations arrive (3 or 100+), the report ranks them ALL and shows the best THREE on technical AND commercial merit - never cheapest-wins.'||E'\n'
    ||'3. SUPPLIER NON-RESPONSE: a revealed supplier must begin responding within '||coalesce(v_days, v_win::text)||' working days of the customer''s PAYMENT (UAE week: Mon-Fri, Sat+Sun off, public holidays excluded). '
    ||'THE LADDER (founder ruling 6 Sep 2026, final; pricing_config): the supplier has '||v_win||' working days from payment. No response by working day '||v_chase||' - the Customer Success Director chases the supplier, customer copied; still silent on working day '||v_win||' - the CEO is notified for the final call; no response to that - the refund is issued. '
    ||'Every refund of any amount is the CEO''s decision and never automatic (founder, 8 Sep 2026: "refunds belong to the CEO from now on" and "all approvals are from CEO. nothing goes to me" - this SUPERSEDES the 6 Sep ruling; public.refunds enforces it with triggers z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval, which refuse a refund with no matching ceo_approval row). The customer gets the FULL reveal fee back (the '||v_pct||'% paid, nothing deducted) and is told banks take '||coalesce(v_bmin,7)||'-'||coalesce(v_bmax,14)||' working days. '
    ||'The supplier then owes the exact amount refunded (the '||v_pct||'%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED '||v_admin||' administrative fee + '||v_int||'% per annum simple interest (the rate AGREED in v14 clauses 31 and 33, Commercial Transactions Law 50/2022 Arts. 73 and 84; a supplier charged under v13 or earlier pays 9%, under v12 or earlier AED 250) + if unpaid the official recovery fees, and is blocked from matching until it is paid. Never ask the founder about any of this again.'||E'\n'
    ||'4. ANTI-CIRCUMVENTION: identities stay anonymous until the reveal and there is no off-platform contact before it. A supplier that takes an introduced customer off-platform within 24 months owes AED '||coalesce(v_aed, '15,000')||' per incident OR '||coalesce(v_mult, 'three (3)')||' times the fee, whichever is higher, plus the unpaid fee.'||E'\n'
    ||'5. CATEGORY OPENING (founder''s standing decision, 6 Sep 2026): a category is OPEN once it has '||v_cat_min||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. Never ask the founder about any figure in these five lines.'||E'\n';
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_knowledge_upsert(p_rid text, p_module text, p_title text, p_content text, p_kw text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.ops_knowledge(
    record_id, scope_type, scope_key, layer, module, record_type, title, content,
    structured_data, source_ids, implementation_status, validation_status, authority_tier,
    risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
    confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status, effective_date)
  values (
    'qd-company:'||p_rid, 'company', 'company_core', 'company_core', p_module, 'md', p_title,
    p_content || E'\n\nYou can answer questions about: ' || array_to_string(p_kw, ', ') || '.',
    '{}'::jsonb, array['fn_company_org_directory_sync'], 'active', 'validated', 'autonomous',
    'low', '1', p_kw, '{}'::text[], '{}'::jsonb, 'UAE', 'current',
    'internal', true, true, 'current', 'pending', current_date)
  on conflict (record_id) do update set
    module=excluded.module, title=excluded.title, content=excluded.content,
    keywords=excluded.keywords, effective_date=excluded.effective_date,
    supersession_state='current', embedding_status='pending';
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_name_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(string_agg(w, '' order by i), '')
    from regexp_split_to_table(
           btrim(regexp_replace(regexp_replace(replace(lower(coalesce(p, '')), '&', ' and '), '[.''’`]', '', 'g'),
                                '[^[:alnum:]]+', ' ', 'g')), ' ') with ordinality t(w, i)
   where w <> '' and w not in ('llc', 'fze', 'fzco', 'fzllc', 'fz', 'dmcc', 'est', 'establishment', 'co', 'company',
                               'ltd', 'limited', 'plc', 'inc', 'and', 'the', 'sole', 'proprietorship', 'br', 'branch',
                               'شذمم', 'ذمم', 'مؤسسة', 'شركة', 'ذات', 'مسؤولية', 'مسئولية', 'محدودة', 'فرع', 'و')
$function$


CREATE OR REPLACE FUNCTION public.fn_company_org_directory_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d record; s record; a_txt text; sec_txt text; v_social text; v_blog text; v_web text; v_cat text;
        v_legal text; v_compl text; v_biz jsonb; v_n int := 0;
begin
  -- 1. THE WHOLE ORG DIRECTORY — one record per department; everyone knows everyone's role, line
  --    manager, what they are measured on and their live rating.
  for d in select dept_key, name, charter, north_star, lead_agent from public.org_departments where active order by dept_key loop
    select string_agg(
             '  - ' || a.agent_key || ' (' || coalesce(a.title, a.role, '') || ') — reports to ' || coalesce(a.manager_key,'—')
             || coalesce((select ' — measured on: ' || string_agg(k.kpi || ' [target ' || coalesce(k.target_value::text,'—')
                          || ', current ' || coalesce(k.actual_value::text,'—') || ']', '; ')
                          from public.employee_kpi k where k.agent_key = a.agent_key and coalesce(k.active,true)), ''),
             E'\n' order by a.agent_key)
      into a_txt from public.org_agents a where a.active and a.department = d.dept_key;
    perform public.fn_company_knowledge_upsert(
      'org-' || d.dept_key, 'organization',
      'QuotesDone Org — the ' || coalesce(d.name, d.dept_key) || ' team',
      'DEPARTMENT: ' || coalesce(d.name, d.dept_key) || ' [' || d.dept_key || ']. Lead: ' || coalesce(d.lead_agent,'—')
      || '. North star: ' || coalesce(d.north_star,'—') || E'\n'
      || 'Members — agent — role — reports to (line manager) — measured on [target, current rating]:' || E'\n'
      || coalesce(a_txt, '(none)'),
      array[d.dept_key, coalesce(d.name,''), 'who works in ' || coalesce(d.name,d.dept_key), 'department team',
            'line manager', 'who reports to whom', 'kpi', 'measured on', 'current rating', 'colleagues',
            'who leads ' || coalesce(d.name,d.dept_key)]);
    v_n := v_n + 1;
  end loop;

  -- 2. THE PUBLISHED FAQ — grouped by section; the 484 answers a colleague could give a customer or supplier.
  for s in select coalesce(nullif(btrim(section),''),'general') sec, string_agg('Q: '||question||E'\n'||'A: '||coalesce(answer,''), E'\n' order by sort nulls last, id) qa
             from public.company_faq where coalesce(public,true) and coalesce(status,'approved') <> 'rejected'
             group by 1 loop
    perform public.fn_company_knowledge_upsert(
      'faq-' || regexp_replace(lower(s.sec),'[^a-z0-9]+','-','g'), 'faq',
      'QuotesDone FAQ — ' || s.sec,
      'FREQUENTLY ASKED (published answers — you may give these to customers and suppliers):' || E'\n' || left(s.qa, 6000),
      array['faq', 'frequently asked', s.sec, 'question', 'answer', 'how do i', 'what is', 'customer question', 'supplier question']);
    v_n := v_n + 1;
  end loop;

  -- 3. SOCIAL, BLOG, WEBSITE — the company's own published content.
  select string_agg('  - ['||to_char(created_at,'DD Mon YYYY')||', '||coalesce(channels::text,'')||', '||coalesce(status,'')||'] '
                    || left(coalesce(content->>'text', content->>'body', content::text), 200), E'\n' order by created_at desc)
    into v_social from public.social_posts;
  perform public.fn_company_knowledge_upsert('content-social','content','QuotesDone — Our Social Media Posts',
    'SOCIAL MEDIA POSTS (most recent first):' || E'\n' || coalesce(v_social,'(none yet)'),
    array['social media','social post','last post','latest post','instagram','linkedin','what did we post','our content','marketing post']);
  v_n := v_n + 1;

  select string_agg('  - ['||coalesce(to_char(published_at,'DD Mon YYYY'),'draft')||', '||coalesce(category,'')||'] '||title
                    ||coalesce(' — '||excerpt,''), E'\n' order by published_at desc nulls last)
    into v_blog from public.blog_posts where published;
  perform public.fn_company_knowledge_upsert('content-blog','content','QuotesDone — Our Blog Articles',
    'BLOG ARTICLES (published):' || E'\n' || left(coalesce(v_blog,'(none yet)'), 6000),
    array['blog','article','blog post','our articles','what have we written','content','seo','latest blog']);
  v_n := v_n + 1;

  select string_agg('  - /'||slug, E'\n' order by slug) into v_web from public.pages;
  perform public.fn_company_knowledge_upsert('content-website','content','QuotesDone — Our Website Pages',
    'WEBSITE PAGES we publish (the public site an agent should know exists):' || E'\n' || coalesce(v_web,'(none)')
    || E'\n\nThe published legal terms, services and marketing copy live on these pages; the terms and commercials are also summarised in the company terms and commercials knowledge.',
    array['website','web page','our site','pages','website content','what is on our website','public site']);
  v_n := v_n + 1;

  -- 4. THE SUPPLIER CATEGORY TAXONOMY — every category an RFQ can be routed to.
  select string_agg('  ' || num || '. ' || name || case when regulated then ' (regulated)' else '' end, E'\n' order by sort, num)
    into v_cat from public.catalog_supplier_categories;
  perform public.fn_company_knowledge_upsert('categories', 'taxonomy',
    'QuotesDone — The Supplier Categories We Cover',
    'SUPPLIER CATEGORIES (' || (select count(*) from public.catalog_supplier_categories)::text
      || ' in total) — every category an RFQ can be routed to, in order:' || E'\n' || coalesce(v_cat, '(none)'),
    array['categories','supplier categories','what do we cover','category list','taxonomy','trades','how many categories','what categories','regulated categories','which category','list the categories']);
  v_n := v_n + 1;

  -- 5. 9 SEP 2026 -- PHASE MACHINERY REMOVED. Section 5 published a company knowledge record
  --    titled "The 30 Workflows We Run", built by reading the programme workflow registry. That registry
  --    is deleted in this sweep, and the company is two agents (ceo, customer_support) with no
  --    departments and no W-numbered programme, so the record described an organisation that does
  --    not exist. The whole section is removed; the already-published copy is deleted below, in
  --    this same transaction, so no agent keeps reciting it out of ops_knowledge. Sections 1-4 and
  --    6-7 are unchanged and the record count in the return value simply drops by one.

  -- 6. LEGAL, COMPLIANCE AND POLICY FRAMEWORK.
  select string_agg('  - ' || coalesce(title, slug) || case when coalesce(category,'') <> '' then ' [' || category || ']' else '' end
         || case when coalesce(summary,'') <> '' then ': ' || left(summary,140) else '' end, E'\n' order by category, title)
    into v_legal from public.legal_documents;
  select string_agg('  - ' || requirement || ' (' || case when present then 'in place' else 'pending' end || ')', E'\n' order by priority nulls last, id)
    into v_compl from public.legal_checklist;
  perform public.fn_company_knowledge_upsert('legal', 'legal_compliance',
    'QuotesDone — Legal, Compliance and Policy Framework',
    'LEGAL & COMPLIANCE. QuotesDone operates under UAE law (Asia/Dubai; PDPL data protection). Published legal documents:' || E'\n'
    || coalesce(v_legal,'(none)') || E'\n' || 'Compliance checklist:' || E'\n' || coalesce(v_compl,'(none)') || E'\n'
    || 'Posture: anonymous marketplace, buyer/supplier identities protected until reveal, EVERY refund is founder-approved, '
    || 'late fees under UAE Federal Decree-Law 50/2022, disputes handled through a defined escalation ladder.',
    array['legal','compliance','regulatory','policy','terms of service','privacy policy','pdpl','data protection','uae law','are we compliant','legal documents','what laws apply','governing law','gdpr']);
  v_n := v_n + 1;

  -- 7. THE BUSINESS ENTITIES — the live customer/supplier/order landscape, and HOW to look up any one.
  begin v_biz := public.fn_business_entity_summary(); exception when others then v_biz := '{}'::jsonb; end;
  perform public.fn_company_knowledge_upsert('business-entities', 'business_data',
    'QuotesDone — Our Customers, Suppliers and Orders (live), and how to look them up',
    'THE BUSINESS RIGHT NOW (live counts):' || E'\n' ||
    '  Customers: ' || coalesce(v_biz->>'customers','0') || ' (with an inquiry: ' || coalesce(v_biz->>'customers_with_inquiry','0') || ')' || E'\n' ||
    '  Suppliers: ' || coalesce(v_biz->>'suppliers_total','0') || ' total — ' || coalesce(v_biz->>'suppliers_approved','0') || ' approved, '
      || coalesce(v_biz->>'suppliers_prospective','0') || ' prospective; sendable pool ' || coalesce(v_biz->>'sendable_supplier_pool','0') || E'\n' ||
    '  Inquiries/RFQs: ' || coalesce(v_biz->>'inquiries','0') || '  ·  Quotes: ' || coalesce(v_biz->>'quotes','0') || '  ·  Transactions/orders: ' || coalesce(v_biz->>'transactions','0') || E'\n' ||
    '  Categories: ' || coalesce(v_biz->>'categories_total','0') || ' (' || coalesce(v_biz->>'categories_at_target','0') || ' at the 10-supplier target)' || E'\n' ||
    'HOW TO KNOW A SPECIFIC ONE (do not memorise the records — look them up live):' || E'\n' ||
    '  - fn_business_entity_lookup(entity, key): one customer/supplier/inquiry/quote/transaction by id, email, company name or phone -> its full profile.' || E'\n' ||
    '  - fn_business_entity_list(entity, filter, limit): list or search them (e.g. all approved suppliers, recent inquiries).' || E'\n' ||
    '  - fn_business_entity_summary(): these live counts. Call these functions directly — you run with the database access to do so.',
    array['customers','suppliers','how many customers','how many suppliers','who are our customers','who are our suppliers','their profiles','their orders','look up a supplier','find a customer','list suppliers','our orders','the crm','business data','inquiries','quotes','transactions','entity lookup']);
  v_n := v_n + 1;

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_registration_name_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with
  -- 1. Arabic: hamza/alef forms, taa marbuta, alef maqsura, tashkeel, tatweel and Arabic digits,
  --    folded by the estate's existing normaliser. 2. Case: lower().
  a as (select lower(public.fn_ar_norm(p)) as s),
  -- 3. HTML ENTITIES. 2,143 of the 22,269 directory names carried one on 24 Sep, scraped from web
  --    pages ("GOLDEN OCEAN ... TRADING &#038; ELEC"). &amp; / &#038; / &#x26; are "&"; the apostrophe
  --    entities are an apostrophe (removed in step 5); any other entity (&#8211; en dash, &nbsp;)
  --    is a separator, like the punctuation it stands for.
  b as (select regexp_replace(
                 regexp_replace(
                   regexp_replace(s, '&(amp|#0*38|#x0*26);', '&', 'g'),
                   '&(apos|rsquo|lsquo|#0*39|#x0*27|#8216|#8217);', '''', 'g'),
                 '&#?[a-z0-9]+;', ' ', 'g') as s from a),
  -- 4. "&" is the word "and": "A & B Glass" = "A and B Glass".
  -- 5. Dots and apostrophes VANISH rather than split: "L.L.C." is "llc", "F.Z.E" is "fze", "Co." is
  --    "co", "Mu'min" is "mumin".
  -- 6. Every other run of non letters/digits (spaces, hyphens, brackets, commas, slashes) is ONE
  --    space: "AL-BARIQ" = "AL BARIQ", "(L.L.C)" = "llc", "FZ-LLC" = "fz llc".
  c as (select btrim(regexp_replace(regexp_replace(replace(s, '&', ' and '), '[.''’‘`]', '', 'g'),
                                    '[^[:alnum:]]+', ' ', 'g')) as s from b),
  -- 7. THE SPELLING OF A LEGAL FORM, KEPT AS PART OF THE KEY (whole words only, \m...\M):
  --      "l l c" -> llc;  "f z e" -> fze;  "f z c o" -> fzco;  "fz llc" / "f z llc" -> fzllc
  --      (after step 6 "FZ-LLC" and "FZ LLC" are both "fz llc", and "FZLLC" is already one word);
  --      "establishment" -> est;  "company" -> co;
  --      Arabic: "ش ذ م م" -> شذمم (single-owner LLC, its own form); "ذ م م" and "ذمم" -> llc,
  --      because ذ.م.م IS the Arabic spelling of L.L.C. The spaced ش form is folded first so its
  --      tail is not read as ذ م م.
  --    Nothing is dropped: "X LLC" and "X FZE" stay two keys.
  d as (select
          regexp_replace(regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(regexp_replace(regexp_replace(s,
            '\ml l c\M', 'llc', 'g'),
            '\mf z e\M', 'fze', 'g'),
            '\mf z c o\M', 'fzco', 'g'),
            '\mf ?z llc\M', 'fzllc', 'g'),
            '\mestablishment\M', 'est', 'g'),
            '\mcompany\M', 'co', 'g'),
            '\mش ذ م م\M', 'شذمم', 'g'),
            '\mذ م م\M', 'llc', 'g'),
            '\mذمم\M', 'llc', 'g') as s from c)
  -- A name with no letters or digits has no key; NULL never conflicts in a unique index.
  select nullif(btrim(s), '') from d
$function$


CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric; v_founder_words text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_supply_owner text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'sales_engineer' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_supply_owner from public.org_role where role_id = 'sales_engineer';
  select display_name into v_co from public.org_role where role_id = 'ceo';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company). 9 SEP 2026 -- PHASE MACHINERY REMOVED: this read
  -- the founder-identity register, which is deleted in this sweep. It was never an authority
  -- check here, only the address printed in the "who we are" knowledge record, so it is read from
  -- app_secrets.founder_email -- the same place fn_page_high_agent_action already reads it -- and
  -- falls back to the same literal the record already carried.
  select value into v_founder from public.app_secrets where key = 'founder_email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count,1000), coalesce(category_open_min_suppliers,10)
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  v_founder_words := (select d.value #>> '{}' from public.decision_policy d where d.key = 'refund_policy_founder_decision_2026_09_06');
  -- 6 SEP 2026: the founder's budget stance and his decisions on record (company_financial_stance,
  -- company_policy_decision), and the category-open count (v_category_open)
  select * into v_stance from public.company_financial_stance where id = 1;
  select string_agg('- ' || upper(decision_key) || ' (decided ' || to_char(decided_on,'DD Mon YYYY') || ' by the ' || decided_by
                    || case when never_ask_again then '; NEVER ask about it again' else '' end || '): ' || decision_text
                    || case when cardinality(applies_to) > 0 then ' [applies to: ' || array_to_string(applies_to, ', ') || ']' else '' end,
                    E'\n' order by decision_key)
    into v_decisions from public.company_policy_decision;
  select count(*) filter (where is_open) || ' of ' || count(*) || ' categories are OPEN today (' ||
         coalesce(max(verified_registered_suppliers),0) || ' is the highest verified-registered count in any category)'
    into v_cat_open from public.v_category_open;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. v_funnel was a listing of W04..W18 read from
  -- the programme workflow registry, appended to the marketplace knowledge record as "The 30 workflows
  -- that run this". The workflow registry is deleted in this sweep and the company is two agents
  -- with no departments and no W-numbered programme, so the sentence is dropped rather than left
  -- describing an organisation that no longer exists. The prose above still explains the funnel in
  -- plain words, which is what an agent answering a question actually needs.

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT, Corporate Tax and the auditor that day; all are
    -- closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'corporate tax registration','CT registration','small business relief','auditor','external auditor','audit firm','who audits us',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.') || E'\n' ||
        'AUDITOR: ' || coalesce(reg.auditor,'not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L) and the Budget Policy',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable',
        'budget','budget limit','budget policy','do we have a budget','budget variance','over budget','spending limit','when do we set budgets','profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.' || E'\n' ||
        'BUDGET POLICY (founder, ' || coalesce(to_char(v_stance.decided_on,'DD Mon YYYY'),'6 Sep 2026') || '): ' ||
          coalesce(v_stance.policy_text, 'No budget limit while costs are subscriptions; budgets come with profitability.') ||
          ' Current stance: ' || case when coalesce(v_stance.is_profitable,false) then 'PROFITABLE - budgets apply and budget-variance alerts are live.'
                                     else 'NOT YET PROFITABLE - budget_mode ' || coalesce(v_stance.budget_mode,'unlimited_until_profitable') ||
                                          '; there is no budget limit, and budget-variance alerts and budget-limit checks are inert. Do not ask the founder for a budget.' end),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then.' ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays',
        'discount','promo','promotion','coupon','free reveal','cap','fee cap','maximum fee','first 1000','first 1,000','open category','category open','when is a category open','how many suppliers to open a category']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one. NO cap, NO discount, NO promotional rate, '
          'NO coupon and NO free reveal exist or may be offered (founder, 6 Sep 2026; pricing_config forbids them by constraint).' || E'\n' ||
        'SUPPLIERS: ' || case when v_charge is null
          then 'registration is FREE for the first ' || v_free_n || ' registrations (those suppliers are exempt permanently); every registration after them pays ' ||
               coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. There is NO calendar start date and never will be: charging begins with registration ' ||
               (v_free_n + 1) || ', whenever that happens (founder, 6 Sep 2026). Never state a date; never ask the founder for one.'
          else 'registration is FREE until ' || to_char(v_charge,'DD Mon YYYY') || ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year.' end ||
          ' Suppliers are auto-approved on a verified file.' || E'\n' ||
        'CATEGORY OPENING: a category is OPEN once it has ' || v_cat_min || ' verified registered suppliers (public.v_category_open); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the Customer Success Director chases the supplier, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the founder is notified for his final call. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the founder''s approval - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (the agreed rate of v14; 9% under v13 or earlier), per the Supplier Agreement version it had accepted at the reveal (fn_accountant_nonresponse_charge). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: ' || v_pct::text || '% per annum simple, the rate agreed in Supplier Agreement v14 clause 31 (Federal Decree-Law 50/2022 Arts. 73 and 84; 9% for amounts due under v13 or earlier).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', founder''s final call on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, founder''s final call at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','founder final call','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (founder ruling 6 Sep 2026, final; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the Customer Success Director (runtime agent followup, customer_experience) chases the supplier by email, customer copied, WhatsApp when opted in, and holds an org_task until the supplier responds. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door) and the founder is notified for his FINAL CALL (founder_mail_policy kind refund_final_call - one of only two refund signals that reach his inbox; the other is the approval itself).' || E'\n' ||
        '  No response to his call: he approves the refund in the OS (fn_refund_decide; every refund, any amount, is his decision, never automatic).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the rate agreed in v14; 9% under v13 or earlier), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase = Customer Success Director (existing owner of supplier follow-up); final call + approval = the founder; execution on Stripe = Payments & Billing Manager; reconciliation = Financial Controller; recovery from the supplier = Accounts Receivable via collections_legal. No new employee was created for this.' || E'\n' ||
        'THE FOUNDER''S WORDS (verbatim, 6 Sep 2026 - never ask him about refunds again): "' || coalesce(v_founder_words, '(decision_policy.refund_policy_founder_decision_2026_09_06)') || '"'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)')),

    -- 6 SEP 2026: the founder's decisions, verbatim in substance, from company_policy_decision. Added at the
    -- END on purpose: the renderer is code-driven and sibling packets (the refund ladder and the brand kit
    -- above, messaging) add their records before it. Whichever packet lands last keeps its record last;
    -- order carries no meaning here.
    jsonb_build_object('rid','decisions','module','founder_decisions',
      'title','QuotesDone — The Founder''s Standing Decisions (never ask about these again)',
      'kw', to_jsonb(array['founder decision','founder decisions','standing decision','ruling','policy decision','what did the founder decide','never ask again',
        'corporate tax','auditor','meta token','daily budget cap','30 aed','cost per lead target','cpl target','openrouter','open router credit','recharge','receipts','expenses email',
        'discount','no discounts','reveal cap','category open','10 suppliers','finance budget','budget limit','profitable','supplier registration fee','first 1000','1000 aed per year','no deadline','no date']),
      'content',
        'THE FOUNDER''S STANDING DECISIONS. Each line is final. None is a question; none is asked again; every table, document and agent head is kept in sync with them.' || E'\n' ||
        coalesce(v_decisions, '(none recorded)'))
,

    -- 6 SEP 2026 (appended at the END, code-driven): the two supplier loops the founder decided on that day.
    jsonb_build_object('rid','supplier-loops','module','supplier_loops',
      'title','QuotesDone — Supplier acquisition loop and weekly sanctions screening (owners, cadence, switch)',
      'kw', to_jsonb(array['supplier acquisition','invite campaign','supplier invites','follow-up','follow up','300 suppliers','suppliers per month',
        'registered suppliers target','lead intake','inbound email','new leads','lead sourcing','supplier_outreach_golive','outreach switch','is outreach on',
        'sanctions','sanctions screening','UN consolidated list','UAE terrorist list','local terrorist list','screening hit','banned supplier',
        'who owns supplier acquisition','who screens suppliers','compliance officer','business development manager','weekly screening','when do we screen']),
      'content',
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_supply_owner, 'Sales Engineer') || ' (org_agents.sales_engineer; there are no departments) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the sales engineer; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake; lead sourcing). '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Chief Executive (AI)') || ' (org_agents.ceo — a confirmed hit removes a supplier and every approval is the CEO''s; '
        'the sales engineer holds the outreach while the decision is open). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE decision task on the ceo with the evidence and ONE hold on the sales engineer — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the ceo decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
        'Open hits right now: ' || v_hits_open || '. Records: screening_run (source, entries, fetched_at, sha256), screening_entry, supplier_screening_hit.'),

    -- 6 SEP 2026 (LAST on purpose — every sibling file of the day restates this function and the last record
    -- is the one a later restatement can carry forward without touching the others): the WhatsApp templates
    -- and their Meta approval status, live from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb;
begin
  s := jsonb_build_object(
    'employees',        (select count(*) from org_agents where active),
    -- THE CUSTOMER BASE, which the snapshot has never recorded. Zero is the measurement today —
    -- 0 customers and 0 inquiries carrying one — and writing it down daily is what makes the day
    -- it stops being zero visible in the replay.
    'customers',              (select count(*) from customers where not is_demo),
    'customers_with_inquiry', (select count(distinct customer_id) from inquiries where customer_id is not null and not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo))),
    'departments',      (select count(*) from org_departments where active),
    'operating_systems',(select count(*) from operating_system where active),
    'kpis',             (select count(*) from employee_kpi where active),
    'kpis_measurable',  (select count(*) from employee_kpi where active and measure_sql is not null),
    'kpi_gaps_open',    (select count(*) from org_tasks where title like 'KPI missed:%' and status<>'done'),
    'open_tasks',       (select count(*) from org_tasks where status<>'done'),
    'needs_founder',    (select count(*) from org_tasks where status<>'done' and needs_founder),
    'approved_suppliers',(select count(*) from leads where approval_status='approved' and not is_demo),
    'sendable_pool',    (select coalesce(sum(sendable),0) from v_supply_gap),
    'categories_at_target',(select count(*) from v_supply_gap where approved>=10),
    'revenue_30d_aed',  (select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) from transactions where revealed_at>now()-interval '30 days' and not exists (select 1 from public.customers dc where dc.id = transactions.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = transactions.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = transactions.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)))),
    'ai_cost_30d_aed',  (select round(coalesce(sum(cost_aed),0),2) from ai_cost_log where occurred_at>now()-interval '30 days'),
    'knowledge_items',  (select count(*) from agent_knowledge),
    'knowledge_quarantined',(select count(*) from agent_knowledge where validation_status='quarantined'),
    'outcomes_pending', (select count(*) from outcome_record where verdict='pending'),
    'outcomes_improved',(select count(*) from outcome_record where verdict='improved'),
    'decisions_7d',     (select count(*) from decision_log where created_at>now()-interval '7 days'),
    'agent_runs_7d',    (select count(*) from agent_runs where started_at>now()-interval '7 days'),
    'error_rate_7d',    (select round(100.0*count(*) filter (where status='error')/nullif(count(*),0),2) from agent_runs where started_at>now()-interval '7 days'),
    'os_health',        (select jsonb_object_agg(os_key,health) from os_review where period=to_char(now(),'IYYY-"W"IW')),
    'indices',          (select jsonb_object_agg(index_name,score) from company_index where measured_on=current_date),
    'autonomy_enabled', (select value from app_secrets where key='agent_autonomy_enabled'),
    'invite_enabled', (select value from app_secrets where key='invite_enabled'),
      -- THE PULSE (3 Sep 2026): the signals the founder's one screen lacked, from the instruments that
      -- already measure them. Liveness (a cron that never fires), what is dead-lettered, what failed in
      -- the last day, what is parked behind the paid-model hold, what paged him, and the ad money.
      'crons_stale',        (select coalesce(jsonb_agg(jobname order by jobname), '[]'::jsonb) from public.v_cron_stale),
      'dead_letters_open',  (select count(*) from public.dead_letter where resolved_at is null),
      'failed_runs_24h',    (select count(*) from public.agent_runs where status = 'error' and started_at > now() - interval '24 hours'),
      'runs_skipped_24h',   (select count(*) from public.agent_runs where status = 'skipped' and started_at > now() - interval '24 hours'),
      'actions_held',       (select count(*) from public.action_execution where status = 'held'),
      'founder_alerts_24h', (select count(*) from public.founder_alerts where channel in ('email','whatsapp') and created_at > now() - interval '24 hours'),
      'ad_spend', jsonb_build_object(
        'active_campaigns', (select count(*) from public.ad_campaign_state where not is_demo and status = 'ACTIVE'),
        'active_daily_aed', (select coalesce(sum(daily_budget_aed), 0) from public.ad_campaign_state where not is_demo and status = 'ACTIVE'),
        'daily_ceiling_aed', public.fn_ad_spend_daily_ceiling(),
        'decisions_pending', (select count(*) from public.ad_decision where executed_at is null),
        'meta_token_present', exists (select 1 from app_secrets where key = 'meta_access_token' and coalesce(value, '') <> '')));

  insert into company_snapshot (snapshot_on, state) values (current_date, s)
  on conflict (snapshot_on) do update set state=excluded.state, created_at=now();

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_snapshot',now(),now(),'ok',jsonb_build_object('keys',(select count(*) from jsonb_object_keys(s))),
    'Company state snapshotted for '||current_date||'. Any past day can now be reconstructed.');
  return s;
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_state()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with depts as (
    select d.dept_key, d.name, d.charter, d.north_star, d.lead_agent, d.active,
           coalesce((select array_agg(a.agent_key order by a.agent_key) from org_agents a where a.department=d.dept_key and a.active), '{}') as brain_agents,
           (select count(*) from org_agents a where a.department=d.dept_key and a.active) as brain_count,
           (select count(*) from org_action_executor e where e.department=d.dept_key and e.active) as tool_count
    from org_departments d where d.active
  )
  select jsonb_build_object(
    'vision', (select vision from company_vision where id=1),
    'mission', (select mission from company_vision where id=1),
    'as_of', now(),
    'totals', jsonb_build_object(
      'departments', (select count(*) from depts),
      'brain_agents', (select count(*) from org_agents where active),
      'category_sales_agents', (select count(*) from category_agents),
      'tools_wired', (select count(*) from org_action_executor where active),
      'open_objectives', (select count(*) from department_objective where active and status not in ('done','cancelled','superseded')),
      'open_tasks', (select count(*) from org_tasks where status in ('assigned','proposed','in_progress'))
    ),
    'departments', (select jsonb_agg(jsonb_build_object(
        'dept', dept_key, 'name', name, 'charter', charter, 'north_star', north_star,
        'lead_agent', lead_agent, 'brain_agents', brain_agents,
        'headcount', brain_count + case when dept_key='procurement' then (select count(*) from category_agents) else 0 end,
        'tools_wired', tool_count) order by dept_key) from depts)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_competitor_scan_ingest(p_scan_id bigint, p_status integer, p_content text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s public.competitor_scan; c public.competitor; v_text text; v_hash text; prev public.competitor_scan; v_held bigint; v_first boolean;
begin
  select * into s from public.competitor_scan where id = p_scan_id for update;
  if not found or s.status <> 'fetching' then return jsonb_build_object('scan', p_scan_id, 'skipped', true); end if;
  select * into c from public.competitor where id = s.competitor_id;
  if p_status is null or p_status not between 200 and 399 or coalesce(btrim(p_content), '') = '' then
    update public.competitor_scan set status = 'failed', http_status = p_status, error = left(coalesce(p_error, 'empty page'), 500) where id = s.id;
    return jsonb_build_object('scan', s.id, 'status', 'failed');
  end if;
  v_text := regexp_replace(p_content, '<script[^>]*>.*?</script>', ' ', 'gi');
  v_text := regexp_replace(v_text, '<style[^>]*>.*?</style>', ' ', 'gi');
  v_text := regexp_replace(v_text, '<[^>]+>', ' ', 'g');
  v_text := replace(replace(replace(replace(v_text, '&nbsp;', ' '), '&amp;', '&'), '&#39;', ''''), '&quot;', '"');
  v_text := left(btrim(regexp_replace(v_text, '\s+', ' ', 'g')), 20000);
  v_hash := md5(v_text);

  select * into prev from public.competitor_scan
   where competitor_id = s.competitor_id and page_kind = s.page_kind and id <> s.id and status in ('unchanged', 'fetched', 'reasoned')
   order by requested_at desc limit 1;
  v_first := prev.id is null;
  if not v_first and prev.content_hash = v_hash then
    update public.competitor_scan set status = 'unchanged', http_status = p_status, content_hash = v_hash where id = s.id;
    update public.competitor set verified_at = (now() at time zone 'Asia/Dubai')::date where id = c.id;
    return jsonb_build_object('scan', s.id, 'status', 'unchanged');
  end if;

  update public.competitor_scan set status = 'fetched', http_status = p_status, content_hash = v_hash, page_text = v_text where id = s.id;
  v_held := public.fn_seat_duty_reason('marketing', 'marketing.competitor_change',
    case when v_first then
      'Read this competitor''s public ' || s.page_kind || ' page for the first time and record its pricing, positioning and features '
        || 'as they stand, so later readings can be compared with it. Say unreadable if the page carries no usable content.'
    else
      'Compare this competitor''s public ' || s.page_kind || ' page with the last reading. Decide whether its pricing, positioning '
        || 'or features changed in a way that matters to QuotesDone (a construction and home-services quotation marketplace in the UAE: '
        || 'best-3 comparison, 3 per cent reveal fee paid by the buyer, no supplier commission). Cosmetic or rotating content is not a change.'
    end,
    case when v_first then
      '[{"id":"profiled","meaning":"the page was read and its pricing, positioning and features are recorded"},{"id":"unreadable","meaning":"the page has no usable content (blocked, empty or only a script shell)"}]'::jsonb
    else
      '[{"id":"no_material_change","meaning":"nothing that matters to us changed"},{"id":"changed","meaning":"pricing, positioning or features changed in a way the CEO should act on"},{"id":"unreadable","meaning":"the page has no usable content (blocked, empty or only a script shell)"}]'::jsonb
    end,
    jsonb_build_object('competitor', to_jsonb(c) - 'watch', 'page_kind', s.page_kind, 'url', s.url, 'page_text', left(v_text, 12000),
                       'last_reading', case when v_first then null else jsonb_build_object('fetched', prev.requested_at, 'fields', prev.fields,
                                                                                          'page_text', left(prev.page_text, 6000)) end),
    jsonb_build_object('scan_id', s.id), 'mkt_competitor:' || s.id);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'pricing', 'question', 'who pays what, as the page states it (or "not published")'),
    jsonb_build_object('key', 'positioning', 'question', 'who it is for and what it claims, in one sentence'),
    jsonb_build_object('key', 'features', 'question', 'the features that compete with QuotesDone'),
    jsonb_build_object('key', 'what_changed', 'question', 'for changed: exactly what changed and why it matters to us')));
  update public.competitor_scan set held_id = v_held where id = s.id;
  return jsonb_build_object('scan', s.id, 'status', 'fetched', 'held', v_held, 'first', v_first);
end $function$


CREATE OR REPLACE FUNCTION public.fn_complaint_clock_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.complaint_tickets; h record; r jsonb;
  v_warn int := public.fn_seat_clock_policy('complaint_seat_warning_working_days', 2)::int;
  v_due timestamptz; v_owed text; v_seat int := 0; v_ceo int := 0; v_closed int := 0; v_refused jsonb := '[]'::jsonb;
begin
  for t in select * from public.complaint_tickets
            where status <> 'final_response' and (p_include_fixtures or not public.fn_is_demo_email(email))
            order by id loop
    if t.acknowledged_at is null then v_due := t.acknowledge_due; v_owed := 'acknowledgement';
    else v_due := t.respond_due; v_owed := 'final response'; end if;
    if public.fn_working_days_between(now(), v_due) > v_warn and now() <= v_due then continue; end if;

    perform public.fn_seat_handoff('customer_support', 'customer_support', 'complaint.due', 'complaint_tickets', t.ticket_no,
      jsonb_build_object('ticket', t.ticket_no, 'due', v_due, 'owed', v_owed, 'status', t.status,
        'waiting_for', 'the ' || v_owed || ' on complaint ' || t.ticket_no || ' (fn_complaint_set_status), due '
                       || to_char(v_due at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai'));
    v_seat := v_seat + 1;

    if now() > v_due then
      r := public.fn_support_report_to_ceo(
        'complaint_overdue:' || t.ticket_no || ':' || replace(v_owed, ' ', '_'), 'elevated',
        'Complaint ' || t.ticket_no || ' is past its ' || v_owed || ' deadline ('
          || to_char(v_due at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        jsonb_build_object('ticket', t.ticket_no, 'created_at', t.created_at, 'due', v_due, 'owed', v_owed, 'status', t.status,
                           'policy', 'Complaints Policy: acknowledgement within 2 working days, substantive response within 10'),
        jsonb_build_array('customer_support has held complaint.due for ' || t.ticket_no || ' since '
                          || v_warn || ' working day(s) before the deadline'),
        'Decide the ' || v_owed || ' on ' || t.ticket_no || ' and have customer_support give it (fn_complaint_set_status). The customer can see the missed date on the status page.',
        p_case_ref => t.ticket_no, p_source_agent => 'customer_support');
      if not coalesce((r->>'ok')::boolean, false) then
        v_refused := v_refused || jsonb_build_array(jsonb_build_object('ticket', t.ticket_no, 'reason', r->>'reason'));
      elsif not coalesce((r->>'duplicate')::boolean, false) then v_ceo := v_ceo + 1;
      end if;
    end if;
  end loop;

  for h in select a.id from public.agent_actions a
             join public.complaint_tickets c on a.target_id = 'complaint.due:' || c.ticket_no
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status not in ('done', 'failed')
              and c.status = 'final_response' loop
    perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('final_response_given', true));
    v_closed := v_closed + 1;
  end loop;

  return jsonb_build_object('ok', jsonb_array_length(v_refused) = 0, 'on_seat_clock', v_seat,
                            'raised_to_ceo', v_ceo, 'closed', v_closed, 'refused', v_refused);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_complaint_due_waits_for_the_response(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('waiting', coalesce(a.detail->>'waiting_for', 'the final response on this complaint'))
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_complaint_lookup(p_ticket_no text, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.complaint_tickets;
begin
  select * into v_row from public.complaint_tickets
   where ticket_no = upper(btrim(coalesce(p_ticket_no,'')))
     and email = lower(btrim(coalesce(p_email,'')));
  if not found then return null; end if;
  return jsonb_build_object(
    'ticket', v_row.ticket_no,
    'status', v_row.status,
    'created_at', v_row.created_at,
    'acknowledge_due', v_row.acknowledge_due,
    'respond_due', v_row.respond_due,
    'acknowledged_at', v_row.acknowledged_at,
    'in_review_at', v_row.in_review_at,
    'final_response_at', v_row.final_response_at,
    'final_response', v_row.final_response,
    -- who decided and the reference to quote; null until a final response exists
    'decision_ref', v_row.decision_ref,
    'decided_by', case when v_row.final_response_at is not null then v_row.handled_by end,
    -- working days still left before each promise falls due (0 once today is the due day or later)
    'acknowledge_days_left', public.fn_working_days_between(now(), v_row.acknowledge_due),
    'respond_days_left', public.fn_working_days_between(now(), v_row.respond_due));
end $function$


CREATE OR REPLACE FUNCTION public.fn_complaint_open(p_email text, p_name text, p_message text, p_contact_message_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 32 symbols, no 0/O/1/I
  v_email text := lower(btrim(coalesce(p_email,'')));
  v_no    text;
  v_bytes bytea;
  v_row   public.complaint_tickets;
  i int;
  attempt int := 0;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'fn_complaint_open: invalid email'; end if;
  if coalesce(btrim(p_message),'') = '' then raise exception 'fn_complaint_open: empty message'; end if;
  loop
    attempt := attempt + 1;
    v_bytes := decode(replace(gen_random_uuid()::text,'-',''),'hex');
    v_no := 'QD-C-';
    for i in 0..5 loop v_no := v_no || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into public.complaint_tickets
        (ticket_no, email, name, message, contact_message_id, status,
         acknowledge_due, respond_due, acknowledged_at)
      values
        (v_no, v_email, nullif(btrim(coalesce(p_name,'')),''), left(p_message, 4000), p_contact_message_id,
         'acknowledged', public.fn_add_working_days(now(), 2), public.fn_add_working_days(now(), 10), now())
      returning * into v_row;
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;
  return jsonb_build_object(
    'ticket', v_row.ticket_no, 'status', v_row.status, 'created_at', v_row.created_at,
    'acknowledge_due', v_row.acknowledge_due, 'respond_due', v_row.respond_due);
end $function$


CREATE OR REPLACE FUNCTION public.fn_complaint_set_status(p_ticket_no text, p_status text, p_final_response text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.complaint_tickets;
  rank_old int; rank_new int;
begin
  select * into v_row from public.complaint_tickets
   where ticket_no = upper(btrim(coalesce(p_ticket_no,''))) for update;
  if not found then raise exception 'fn_complaint_set_status: no ticket %', p_ticket_no; end if;
  rank_old := array_position(array['acknowledged','in_review','final_response'], v_row.status);
  rank_new := array_position(array['acknowledged','in_review','final_response'], p_status);
  if rank_new is null then raise exception 'fn_complaint_set_status: unknown status %', p_status; end if;
  if rank_new <= rank_old then
    raise exception 'fn_complaint_set_status: % is already %; status only moves forward', v_row.ticket_no, v_row.status;
  end if;
  if p_status = 'final_response' and coalesce(btrim(p_final_response),'') = '' then
    raise exception 'fn_complaint_set_status: a final response needs its text';
  end if;
  update public.complaint_tickets set
    status            = p_status,
    in_review_at      = case when p_status = 'in_review' then now() else in_review_at end,
    final_response_at = case when p_status = 'final_response' then now() else final_response_at end,
    final_response    = case when p_status = 'final_response' then btrim(p_final_response) else final_response end
  where id = v_row.id
  returning * into v_row;
  return jsonb_build_object('ticket', v_row.ticket_no, 'status', v_row.status,
    'in_review_at', v_row.in_review_at, 'final_response_at', v_row.final_response_at);
end $function$


CREATE OR REPLACE FUNCTION public.fn_contact_timeline(p_contact text, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_raw text := btrim(coalesce(p_contact, ''));
  v_email text; v_tail text;
  v_cust uuid[]; v_lead bigint[]; v_inq uuid[]; v_txn uuid[]; v_ref bigint[];
  v_events jsonb; v_counts jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);   -- +9715..., 05..., 5...
  else
    return jsonb_build_object('contact', v_raw, 'known', false, 'event_count', 0, 'events', '[]'::jsonb);
  end if;

  select coalesce(array_agg(c.id), '{}') into v_cust from public.customers c
   where (v_email is not null and lower(c.email) = v_email)
      or (v_tail is not null and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail);
  select coalesce(array_agg(l.id), '{}') into v_lead from public.leads l
   where (v_email is not null and (lower(l.email) = v_email or lower(l.claimed_by) = v_email))
      or (v_tail is not null and v_tail in (right(regexp_replace(coalesce(l.phone_e164, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.whatsapp, ''), '[^0-9]', '', 'g'), 9)));
  select coalesce(array_agg(i.id), '{}') into v_inq from public.inquiries i where i.customer_id = any (v_cust);
  select coalesce(array_agg(t.id), '{}') into v_txn from public.transactions t
   where t.customer_id = any (v_cust) or t.supplier_id = any (v_lead);
  select coalesce(array_agg(r.id), '{}') into v_ref from public.refunds r
   where r.customer_id = any (v_cust) or r.supplier_lead_id = any (v_lead) or r.transaction_id = any (v_txn);

  with ev(at, kind, channel, direction, seat, ref, summary) as (
    -- what they asked for
    select i.created_at, 'request', 'portal', 'in', 'sales_engineer', i.id::text,
           coalesce(i.status, '') || ': ' || left(coalesce(i.summary_masked, i.summary, i.category, ''), 140)
      from public.inquiries i where i.id = any (v_inq)
    -- quotes on their requests: state only, never a supplier or an amount (the pre-reveal rule)
    union all
    select q.created_at, 'quote', 'portal', 'in', 'sales_engineer', q.id::text,
           case when exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null)
                then 'released (revealed)' else 'held (' || coalesce(q.status, 'received') || ')' end
      from public.quotes q where q.inquiry_id = any (v_inq)
    -- quotes they submitted, when the contact is a supplier
    union all
    select q.created_at, 'quote_submitted', 'portal', 'out', 'sales_engineer', q.id::text, coalesce(q.status, 'submitted')
      from public.quotes q where q.supplier_id = any (v_lead)
    -- reveals and what was paid
    union all
    select t.revealed_at, 'reveal', 'portal', 'out', 'accountant', t.id::text, 'fee ' || coalesce(t.fee_status, 'unknown')
      from public.transactions t where t.id = any (v_txn) and t.revealed_at is not null
    union all
    select ri.created_at, 'invoice', 'portal', 'out', 'accountant', ri.invoice_no, 'reveal invoice issued'
      from public.reveal_invoices ri where ri.transaction_id = any (v_txn)
    -- refunds, and the CEO's decision on each (the refund loop)
    union all
    select coalesce(r.updated_at, r.created_at), 'refund', 'portal', 'out', 'accountant', r.id::text,
           coalesce(r.status, '') || coalesce(' — ' || r.reason_code, '')
      from public.refunds r where r.id = any (v_ref)
    union all
    select coalesce(rc.updated_at, rc.created_at), 'refund_case', 'internal', 'internal', 'accountant', rc.case_id::text,
           coalesce(rc.state, '') || coalesce(' — ' || rc.decision, '')
      from public.refund_case rc where rc.refund_id = any (v_ref)
    union all
    select a.decided_at, 'ceo_decision', 'internal', 'internal', 'ceo', a.decision_id::text,
           coalesce(a.subject_kind, '') || ': ' || coalesce(a.decision, '')
      from public.ceo_approval a where a.subject_kind ilike 'refund%' and a.subject_id = any (v_ref::text[])
    -- support cases
    union all
    select coalesce(s.last_activity_at, s.opened_at), 'support_case', 'internal', 'internal',
           coalesce(s.owner_role_id, 'customer_support'), s.case_ref, coalesce(s.state, '') || ': ' || left(coalesce(s.subject, ''), 120)
      from public.support_case s
     where (s.party_kind = 'customer' and s.party_id = any (v_cust::text[]))
        or (s.party_kind = 'supplier' and s.party_id = any (v_lead::text[]))
    -- every message the company sent them, and the seat that asked for it
    union all
    select n.created_at, 'message', coalesce(n.channel, 'email'), 'out', coalesce(n.requested_by, 'customer_support'),
           n.id::text, coalesce(n.status, 'queued') || ': ' || left(coalesce(n.subject, n.type, ''), 140)
      from public.notifications n
     where (v_email is not null and lower(n.to_email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or n.lead_id = any (v_lead) or n.inquiry_id = any (v_inq)
    -- every message they sent the company
    union all
    select m.created_at, 'message', 'email', 'in', 'customer_support', m.id::text, left(coalesce(m.subject, ''), 140)
      from public.inbound_messages m
     where (v_email is not null and lower(m.from_email) = v_email) or m.lead_id = any (v_lead)
    union all
    select w.at, 'message', 'whatsapp', w.direction, 'customer_support', w.id::text, left(coalesce(w.transcript, w.body, ''), 140)
      from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
     where (v_tail is not null and right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or (c.party_kind = 'customer' and c.party_id = any (v_cust::text[]))
        or (c.party_kind = 'supplier' and c.party_id = any (v_lead::text[]))
    union all
    select pm.created_at, 'message', 'portal_chat', case when pm.customer_id = any (v_cust) and pm.sender = 'customer' then 'in' else 'out' end,
           'sales_engineer', pm.id::text, left(coalesce(pm.redacted_body, ''), 140)
      from public.messages pm where pm.customer_id = any (v_cust) or pm.supplier_id = any (v_lead)
    -- every handoff between the seats about this party (payments_are_the_accountant_and_it_talks_to_the_
    -- sales_engineer.sql): who handed what to whom, and where it stands, so support reads the money and
    -- the refund loops before it answers — #617's branch, kept here verbatim so the live body is the union
    union all
    select a.created_at, 'handoff', 'internal', 'internal', a.agent, a.id::text,
           coalesce(a.detail->>'type', a.kind) || ' from ' || coalesce(a.detail->>'from', '?') || ' to ' || a.agent || ': ' || a.status
      from public.agent_actions a
     where a.kind = 'handoff'
       and ((a.detail->>'customer_id') = any (v_cust::text[]) or (a.detail->>'supplier_id') = any (v_lead::text[])
            or (a.detail->>'transaction_id') = any (v_txn::text[]) or (a.detail->>'refund_id') = any (v_ref::text[]))
    union all
    select cm.created_at, 'message', 'contact_form', 'in', 'customer_support', cm.id::text, left(coalesce(cm.message, ''), 140)
      from public.contact_messages cm
     where (v_email is not null and lower(cm.email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(cm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
    -- the sales engineer's record of this supplier's collaboration: holds left unanswered at a
    -- decision, resets, the warning, the matching hold and its lifting (founder, 14 Sep 2026)
    union all
    select e.created_at, 'collaboration', 'internal', 'internal', e.actor, e.id::text,
           e.kind || ' — ' || e.consecutive_after || ' in a row' || coalesce(' — RFQ ' || upper(left(e.inquiry_id::text, 8)), '')
      from public.supplier_collaboration_event e where e.lead_id = any (v_lead)
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'channel', e.channel, 'direction', e.direction,
                                               'seat', e.seat, 'ref', e.ref, 'summary', e.summary) order by e.at desc), '[]'::jsonb)
    into v_events
    from (select * from ev where at is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 500))) e;

  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_counts
    from (select x ->> 'kind' k, count(*) n from jsonb_array_elements(v_events) x group by 1) z;

  return jsonb_build_object(
    'contact', coalesce(v_email, v_tail),
    'known', cardinality(v_cust) + cardinality(v_lead) > 0,
    'customer_ids', to_jsonb(v_cust), 'supplier_lead_ids', to_jsonb(v_lead),
    'event_count', jsonb_array_length(v_events), 'counts', v_counts,
    'events', v_events,
    'assembled_by', 'fn_contact_timeline (deterministic; no model)');
end $function$


CREATE OR REPLACE FUNCTION public.fn_control_mode_session_mfa_is_real()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v public.control_mode_challenge%rowtype;
begin
  select * into v from public.control_mode_challenge where id = new.mfa_ref;
  if not found then
    raise exception 'control mode: mfa_ref % is not a challenge', new.mfa_ref using errcode = '23514';
  end if;
  if lower(btrim(v.admin_email)) <> lower(btrim(new.actor_email)) then
    raise exception 'control mode: challenge belongs to %, not %', v.admin_email, new.actor_email using errcode = '23514';
  end if;
  if v.purpose <> 'control_mode' then
    raise exception 'control mode: challenge % was issued for %, not control_mode', v.id, v.purpose using errcode = '23514';
  end if;
  if v.consumed_at is null or coalesce(v.consumed_why,'') <> 'opened' then
    raise exception 'control mode: challenge % was not consumed by an open (consumed_why=%)',
      v.id, coalesce(v.consumed_why,'<null>') using errcode = '23514';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_conversation_archive_pending(p_limit integer DEFAULT 25)
 RETURNS SETOF v_conversation_message
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select v.* from public.v_conversation_message v
   where not v.is_demo
     and not exists (select 1 from public.conversation_archive a
                      where a.source_table = v.source_table and a.source_id = v.source_id)
   order by v.occurred_at
   limit greatest(1, least(coalesce(p_limit, 25), 200));
$function$


CREATE OR REPLACE FUNCTION public.fn_conversation_archived(p_source_table text, p_source_id text, p_path text, p_bytes bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_queued integer;
begin
  if coalesce(p_path, '') !~ '^conversations/' then
    return jsonb_build_object('ok', false, 'reason', 'the PDF must live under backups/conversations/');
  end if;
  insert into public.conversation_archive (source_table, source_id, pdf_path, bytes)
  values (p_source_table, p_source_id, p_path, p_bytes)
  on conflict (source_table, source_id) do update set pdf_path = excluded.pdf_path, bytes = excluded.bytes, archived_at = now();
  v_queued := public.fn_enqueue_doc_backups();
  if v_queued > 0 then perform public.fn_backup_kick('conversation_archived', 'process_only'); end if;
  return jsonb_build_object('ok', true, 'queued_for_dropbox', v_queued);
end $function$


CREATE OR REPLACE FUNCTION public.fn_conversation_party(p_lead bigint, p_customer uuid, p_inquiry uuid, p_email text, p_phone text)
 RETURNS TABLE(party_kind text, party_id text, inquiry_id text, demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
        v_tail text := nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '');
        v_c uuid; v_l bigint;
begin
  if v_tail is not null and length(v_tail) < 7 then v_tail := null; end if;
  v_c := p_customer;
  if v_c is null and p_inquiry is not null then select i.customer_id into v_c from public.inquiries i where i.id = p_inquiry; end if;
  if v_c is not null then
    return query select 'customer'::text, v_c::text, p_inquiry::text,
      coalesce((select c.is_demo or coalesce(c.email, '') ~* 'example\.invalid' from public.customers c where c.id = v_c), false);
    return;
  end if;
  v_l := p_lead;
  if v_l is null and v_email is not null then
    select c.id into v_c from public.customers c where lower(c.email) = v_email limit 1;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo or coalesce(c.email, '') ~* 'example\.invalid' from public.customers c where c.id = v_c), false);
      return;
    end if;
    -- 21 SEP 2026 (it_engineer): TWO LOOKUPS, EACH ON ITS INDEX. The single OR over both columns could use
    -- neither index (uq_leads_email_lower is partial on email <> '', which the OR did not state), so every
    -- call seq-scanned all 22,270 leads: 49.6 ms, measured. The non-empty-email clause admits the partial
    -- index (0.8 ms, generic plan); claimed_by has idx_leads_claimedby. A registered email now wins over a
    -- claimed_by match where both exist; before, the scan order chose.
    select l.id into v_l from public.leads l where lower(l.email) = v_email and l.email <> '' limit 1;
    if v_l is null then
      select l.id into v_l from public.leads l where lower(l.claimed_by) = v_email limit 1;
    end if;
  end if;
  if v_l is null and v_tail is not null then
    -- 14 Sep 2026 (#322): only a CONFIRMED WhatsApp number names a party.
    select o.customer_id, o.lead_id into v_c, v_l from public.fn_whatsapp_owner(p_phone) o;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo from public.customers c where c.id = v_c), false);
      return;
    end if;
  end if;
  if v_l is not null then
    return query select 'supplier'::text, v_l::text, null::text,
      coalesce((select coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid'
                     or coalesce(l.company_name, '') ~* 'ZZ DEMO' from public.leads l where l.id = v_l), false);
    return;
  end if;
  return query select 'company'::text, null::text, null::text, false;
end $function$


CREATE OR REPLACE FUNCTION public.fn_conversation_record(p_contact text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_raw text := btrim(coalesce(p_contact, '')); v_email text; v_tail text;
        v_kind text; v_id text; v_msgs jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if v_raw ~* '^(customer|supplier):.+' then
    v_kind := lower(split_part(v_raw, ':', 1)); v_id := substring(v_raw from position(':' in v_raw) + 1);
  elsif position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);
  else
    return jsonb_build_object('ok', false, 'reason', 'give an email, a phone number, customer:<id> or supplier:<id>');
  end if;
  if v_kind is null then
    select p.party_kind, p.party_id into v_kind, v_id
      from public.fn_conversation_party(null, null, null, v_email, v_tail) p;
    if v_kind = 'company' then v_kind := null; v_id := null; end if;
  end if;

  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_msgs from (
    select jsonb_build_object(
             'at', v.occurred_at, 'channel', v.channel, 'direction', v.direction,
             'from', v.from_addr, 'to', v.to_addr, 'cc', v.cc, 'subject', v.subject,
             'body', v.body, 'has_html', v.html is not null, 'attachments', v.attachments,
             'party', v.party_kind, 'party_id', v.party_id, 'inquiry_id', v.inquiry_id,
             'ref', v.source_table || ':' || v.source_id,
             'pdf', case when a.pdf_path is not null then jsonb_build_object('bucket', a.pdf_bucket, 'path', a.pdf_path) end,
             'dropbox', case when b.id is not null then jsonb_build_object('path', b.dropbox_path, 'status', b.status) end) x
      from public.v_conversation_message v
      left join public.conversation_archive a on a.source_table = v.source_table and a.source_id = v.source_id
      left join public.doc_backups b on b.dedupe_key = 'CONV:' || v.source_table || ':' || v.source_id
     where (v_id is not null and v.party_kind = v_kind and v.party_id = v_id)
        or (v_email is not null and (lower(v.from_addr) = v_email or lower(v.to_addr) = v_email or lower(coalesce(v.cc, '')) like '%' || v_email || '%'))
        or (v_tail is not null and (right(regexp_replace(coalesce(v.from_addr, ''), '[^0-9]', '', 'g'), 9) = v_tail
                                 or right(regexp_replace(coalesce(v.to_addr, ''), '[^0-9]', '', 'g'), 9) = v_tail))
     order by v.occurred_at desc
     limit greatest(1, least(coalesce(p_limit, 200), 2000))) z;

  return jsonb_build_object('ok', true, 'contact', coalesce(v_email, v_tail, v_raw),
    'party', v_kind, 'party_id', v_id, 'message_count', jsonb_array_length(v_msgs), 'messages', v_msgs,
    'assembled_by', 'fn_conversation_record (deterministic; full text from every store; no model)');
end $function$


CREATE OR REPLACE FUNCTION public.fn_conversation_retention_breaches(p_grace interval DEFAULT '02:00:00'::interval)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with unarchived as (
    select v.source_table, v.source_id, v.channel from public.v_conversation_message v
     where not v.is_demo and v.occurred_at < now() - p_grace
       and not exists (select 1 from public.conversation_archive a where a.source_table = v.source_table and a.source_id = v.source_id)),
  unqueued as (
    select a.source_table, a.source_id from public.conversation_archive a
     where a.archived_at < now() - p_grace
       and not exists (select 1 from public.doc_backups b where b.dedupe_key = 'CONV:' || a.source_table || ':' || a.source_id))
  select jsonb_build_object(
    'grace', p_grace::text,
    'emails_without_pdf', (select count(*) from unarchived where channel = 'email'),
    'conversations_without_pdf', (select count(*) from unarchived),
    'pdfs_without_dropbox_row', (select count(*) from unqueued),
    'total', (select count(*) from unarchived) + (select count(*) from unqueued),
    'sample', (select coalesce(jsonb_agg(u.source_table || ':' || u.source_id), '[]'::jsonb)
                 from (select source_table, source_id from unarchived union all select * from unqueued limit 10) u));
$function$


CREATE OR REPLACE FUNCTION public.fn_cron_liveness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'cron', 'pg_temp'
AS $function$
declare
  v_tick  timestamptz;
  v_cron  timestamptz;
  v_last  timestamptz;
  v_src   text;
  v_age   numeric;
begin
  -- The scheduler's own record: the newest COMPLETED resilience_ping tick. Written at the end of a
  -- tick, so the caller's own run is not yet there; the guard keeps that true regardless.
  select max(started_at) into v_tick
    from public.agent_runs
   where agent = 'fn:resilience_ping'
     and started_at < now() - interval '1 minute';

  begin
    select max(start_time) into v_cron from cron.job_run_details;
  exception when others then
    v_cron := null;   -- pg_cron absent or unreadable is not an outage of the live scheduler
  end;

  -- greatest() IGNORES nulls in Postgres, which is what is wanted here: with only one source
  -- populated it returns that one, and with neither it returns null and is handled below.
  v_last := greatest(v_tick, v_cron);
  v_src  := case
              when v_last is null then null
              when v_tick is not null and v_last = v_tick then 'resilience tick (agent_runs fn:resilience_ping)'
              else 'pg_cron (cron.job_run_details)' end;

  if v_last is null then
    -- Said out loud rather than returned as a clean bill: with no scheduler row and no cron
    -- history there is nothing to measure, and "no evidence of a scheduler" is not "healthy".
    return jsonb_build_object(
      'healthy', false, 'newest_run_age_min', null, 'source', null, 'checked_at', now(),
      'note', 'no completed scheduler tick has ever been recorded, in agent_runs (fn:resilience_ping) or in cron.job_run_details');
  end if;

  v_age := extract(epoch from (now() - v_last))/60.0;
  return jsonb_build_object(
    'healthy',             v_age <= 45,     -- the live scheduler runs every 15 min; 45 = three missed ticks
    'newest_run_age_min',  round(v_age,1),
    'source',              v_src,
    'threshold_min',       45,
    'checked_at',          now());
exception when others then
  return jsonb_build_object('healthy', null, 'error', sqlerrm);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_concierge(p_customer uuid, p_category text DEFAULT NULL::text, p_lang text DEFAULT NULL::text, p_inquiry uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lang text; v_cat text := nullif(btrim(coalesce(p_category, '')), ''); v_first boolean; v_lists jsonb; v_specs text;
  v_label text;
begin
  if p_inquiry is not null and v_cat is null then select category into v_cat from public.inquiries where id = p_inquiry; end if;
  v_lang := case when p_lang in ('en', 'ar') then p_lang
                 else coalesce(public.fn_inquiry_locale(p_inquiry), (select c.locale from public.customers c where c.id = p_customer), 'en') end;
  if v_lang <> 'ar' then v_lang := 'en'; end if;
  -- First = no OTHER request of this customer's own (a split's per-trade children are the same request).
  v_first := not exists (select 1 from public.inquiries i where i.customer_id = p_customer and i.parent_inquiry_id is null
                                                        and i.id is distinct from p_inquiry);
  v_lists := case when v_cat is null then '[]'::jsonb else public.fn_customer_concierge_checklists(v_cat, v_lang) end;
  v_label := coalesce((select cs.label from public.category_specs cs where cs.category = v_cat), replace(v_cat, '_', ' '));

  if jsonb_array_length(v_lists) = 0 then
    v_specs := case when v_lang = 'ar'
      then 'اذكروا المقاسات والكميات والمواد أو العلامات التجارية المطلوبة، وأي مواصفة قياسية أو اعتماد لازم.'
      else 'State the sizes, the quantities, the materials or brands you need, and any standard or approval the work must meet.' end;
  elsif v_lang = 'ar' then
    v_specs := 'اذكروا هذه المواصفات، فبها يسعّر الموردون بدقة:' || chr(10)
      || (select string_agg('- ' || (e->>'body'), chr(10)) from jsonb_array_elements(v_lists) e);
  else
    v_specs := 'For ' || coalesce(v_label, 'this trade') || ', suppliers price exactly when you state:' || chr(10)
      || (select string_agg('- ' || (e->>'topic') || ': '
                            || (select string_agg(s, '; ') from jsonb_array_elements_text(e->'specs') s), chr(10))
            from jsonb_array_elements(v_lists) e);
  end if;

  return jsonb_build_object('lang', v_lang, 'first_inquiry', v_first, 'category', v_cat, 'checklists', v_lists,
    'held', case when p_inquiry is null then null else public.fn_customer_concierge_held(p_inquiry) end,
    'steps', case when v_lang = 'ar' then jsonb_build_array(
        jsonb_build_object('key', 'describe', 'title', 'صِفوا العمل',
          'body', 'ما المطلوب تنفيذه، وأين (الإمارة والمنطقة)، ومتى. طلب واحد لكل عمل، وإن شمل أكثر من تخصص فاذكروها ليصل كل جزء إلى الموردين المتخصصين فيه.'),
        jsonb_build_object('key', 'attach', 'title', 'أرفقوا المخططات',
          'body', 'بصيغة PDF أو CAD (DWG أو DXF) فقط، ولا تُقبل ملفات Revit وIFC وDGN وغيرها من ملفات النماذج، فصدّروا اللوحات إلى PDF أو DWG أولًا. ويمكن إرفاق جدول الكميات جدولَ بيانات أو ملف PDF، وتفيد صور الموقع أيضًا.'),
        jsonb_build_object('key', 'specs', 'title', 'اذكروا المواصفات', 'body', v_specs),
        jsonb_build_object('key', 'next', 'title', 'الخطوات التالية',
          'body', 'يقدّم الموردون الموثّقون في الإمارات العاملون في هذا التخصص عروضهم دون أن يعرفوا هويتكم، ونقارنها لكم ونوصي بأفضل ثلاثة منها من حيث القيمة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% من قيمة عرضه إلا حينها.'))
      else jsonb_build_array(
        jsonb_build_object('key', 'describe', 'title', 'Describe the job',
          'body', 'Say what you need done, where (the emirate and area) and by when. One request per job; if it covers several trades, name them so each part reaches the suppliers who specialise in it.'),
        jsonb_build_object('key', 'attach', 'title', 'Attach the drawings',
          'body', 'As PDF or CAD (DWG or DXF) only. Revit, IFC, DGN and other model files are not accepted: export the sheets to PDF or DWG first. A bill of quantities can be a spreadsheet or a PDF, and photos of the site help too.'),
        jsonb_build_object('key', 'specs', 'title', 'Give the specifications', 'body', v_specs),
        jsonb_build_object('key', 'next', 'title', 'What happens next',
          'body', 'Verified UAE suppliers in this trade quote without knowing who you are. We compare the quotes and recommend the top three by value. You reveal only the supplier you choose, and pay 3% of that quote only then.'))
      end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_concierge_checklists(p_category text, p_lang text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- ponytail: at most 6 checklists (a trade has 1-5 today); a longer list would bury the steps, so the cap stands
  -- until a trade needs more.
  select coalesce(jsonb_agg(x.item order by x.entry_id), '[]'::jsonb)
    from (select k.structured_data->>'entry_id' as entry_id,
                 jsonb_build_object('topic_id', k.structured_data->>'entry_id',
                   'topic', regexp_replace(coalesce(k.title, ''), '^Spec checklist:\s*', ''),
                   'specs', coalesce(k.structured_data->'required_specs', '[]'::jsonb),
                   'body', k.content) as item
            from public.sales_knowledge k
           where 'kind:spec_checklist' = any(k.tags)
             and k.structured_data->>'lang' = case when p_lang = 'ar' then 'ar' else 'en' end
             and exists (select 1 from unnest(public.fn_taxonomy_trades_for(array[p_category])) c
                          where ('trade:' || c) = any(k.tags))
           order by k.structured_data->>'entry_id'
           limit 6) x
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_concierge_held(p_inquiry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  i public.inquiries; u public.inquiries; v_ar boolean; v_units uuid[]; v_split boolean; v_fields jsonb;
  v_missing jsonb := '[]'::jsonb; m jsonb; f jsonb; k text; v_pre text; v_lang text;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('held', false, 'finding_suppliers', false, 'reason', 'no such request'); end if;
  v_ar := coalesce(public.fn_inquiry_locale(i.id), (select c.locale from public.customers c where c.id = i.customer_id)) = 'ar';
  v_lang := case when v_ar then 'ar' else 'en' end;
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed') then
    return jsonb_build_object('held', false, 'finding_suppliers', false, 'lang', v_lang);
  end if;
  v_units := array(select c.id from public.inquiries c where c.parent_inquiry_id = i.id order by c.created_at);
  v_split := cardinality(v_units) > 0;
  if not v_split then v_units := array[i.id]; end if;
  if not exists (select 1 from public.inquiry_matches x where x.inquiry_id = any(v_units) or x.inquiry_id = i.id) then
    return jsonb_build_object('held', false, 'finding_suppliers', true, 'lang', v_lang, 'missing', '[]'::jsonb);
  end if;

  for u in select * from public.inquiries x where x.id = any(v_units) and not coalesce(x.rfq_ready, false)
            order by x.created_at loop
    v_pre := case when v_split then coalesce((select cs.label from public.category_specs cs where cs.category = u.category),
                                             replace(coalesce(u.category, ''), '_', ' ')) || ': ' else '' end;
    -- The category's required fields that are still open, in the plain words the intake asks them with.
    select cs.fields into v_fields from public.category_specs cs where cs.category = u.category;
    for m in select value from jsonb_array_elements(coalesce(u.completeness->'category_missing', '[]'::jsonb)) loop
      f := null;
      select value into f from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) where value->>'key' = m->>'key' limit 1;
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', m->>'key', 'inquiry_id', u.id,
        'ask', v_pre || coalesce(nullif(f->>case when v_ar then 'question_plain_ar' else 'question_plain_en' end, ''),
                                 nullif(m->>'question', ''), m->>'key')));
    end loop;
    -- The general score only holds a request when it is below the bar; then each missing part is named.
    if not coalesce((u.completeness->>'generic_ready')::boolean, true) then
      for k in select value from jsonb_array_elements_text(coalesce(u.completeness->'missing', '[]'::jsonb)) loop
        v_missing := v_missing || coalesce((select jsonb_build_array(jsonb_build_object('key', k, 'inquiry_id', u.id, 'ask', v_pre || case when v_ar then g.ar else g.en end))
          from (values
            ('category', 'What kind of work is it (the trade)?', 'ما نوع العمل المطلوب (التخصص)؟'),
            ('emirate', 'Which emirate and area is the work in?', 'في أي إمارة ومنطقة سيُنفَّذ العمل؟'),
            ('scope_detail', 'A fuller description of the work: what, how much and to what standard.', 'وصف أوفى للعمل: ما المطلوب، وبأي كمية، ووفق أي مواصفة.'),
            ('scope_type', 'Is it one trade, or several trades together?', 'هل يشمل تخصصًا واحدًا أم عدة تخصصات معًا؟'),
            ('budget', 'Your budget for the work (a range is fine).', 'الميزانية المرصودة للعمل (يكفي نطاق تقريبي).'),
            ('supporting_detail', 'A drawing (PDF, DWG or DXF), a bill of quantities, or the trades involved.', 'مخطط (PDF أو DWG أو DXF)، أو جدول كميات، أو التخصصات المعنية.')
          ) g(key, en, ar) where g.key = k), '[]'::jsonb);
      end loop;
    end if;
  end loop;
  return jsonb_build_object('held', jsonb_array_length(v_missing) > 0, 'finding_suppliers', false, 'lang', v_lang,
                            'missing', v_missing);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_concierge_message(p_inquiry uuid, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  i public.inquiries; c public.customers; g jsonb; h jsonb; v_ar boolean; v_name text; v_ref text; v_held text := ''; v_find text := '';
  v_steps text; v_subj text; v_body text; v_link text;
begin
  if p_kind not in ('first_request', 'held_for_specs', 'finding_suppliers') then
    raise exception 'a concierge message is first_request, held_for_specs or finding_suppliers, not %', p_kind;
  end if;
  select * into i from public.inquiries where id = p_inquiry;
  if not found then raise exception 'no request %', p_inquiry; end if;
  select * into c from public.customers where id = i.customer_id;
  g := public.fn_customer_concierge(i.customer_id, i.category, null, i.id);
  h := g->'held';
  v_ar := g->>'lang' = 'ar';
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_ref := 'QD-' || public.fn_job_no(i.id);
  v_link := case when v_ar then 'https://quotesdone.com/ar/me' else 'https://quotesdone.com/me' end;

  if coalesce((h->>'held')::boolean, false) then
    v_held := (select string_agg('- ' || (e->>'ask'), chr(10)) from jsonb_array_elements(h->'missing') e) || chr(10) || chr(10)
      || case when v_ar
           then 'يمكنكم تعديل الميزانية والإمارة من حسابكم: ' || v_link || chr(10) || 'ولأي تفاصيل أخرى، يسعدنا أن تردّوا على هذه الرسالة بها.'
           else 'You can change the budget and the emirate from your account: ' || v_link || chr(10) || 'For anything else, reply to this e-mail with the details.' end;
  end if;
  -- NO SUPPLIER HAS IT YET: said as it is, never blamed on the specs (re-review of #1112).
  if coalesce((h->>'finding_suppliers')::boolean, false) then
    v_find := case when v_ar
      then 'نبحث عن موردين في تخصصكم: لا يغطي هذا الطلب أيٌّ من الموردين المسجّلين لدينا حاليًا، ونعمل على دعوة موردين متخصصين فيه. وسنراسلكم فور وصول طلبكم إلى أحدهم، ولا يلزمكم أي إجراء.'
      else 'We are finding suppliers for your trade. None of the suppliers registered with us today covers this request yet, and we are inviting suppliers who do. We will write as soon as one of them has your request; nothing is needed from you.' end;
  end if;
  -- The steps, numbered; only the specs step for a later request (the customer has seen the rest before).
  v_steps := (select string_agg(n || '. ' || (e->>'title') || ': ' || (e->>'body'), chr(10) || chr(10) order by n)
                from jsonb_array_elements(g->'steps') with ordinality s(e, n)
               where p_kind = 'first_request' or e->>'key' = 'specs');

  if p_kind = 'first_request' then
    v_subj := case when v_ar then 'استلمنا طلبكم ' || v_ref || ': الخطوات التالية' else 'We have your request ' || v_ref || ': what happens next' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لطلبكم الأول على QuotesDone، ورقمه ' || v_ref || '.' || chr(10) || chr(10)
        || case when v_held <> '' then 'وقبل أن يتمكّن الموردون من تسعيره، نحتاج منكم إلى التفاصيل التالية:' || chr(10) || v_held || chr(10) || chr(10) else '' end
        || case when v_find <> '' then v_find || chr(10) || chr(10) else '' end
        || 'وللحصول على عروض دقيقة قابلة للمقارنة، إليكم الخطوات:' || chr(10) || chr(10) || v_steps || chr(10) || chr(10)
        || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for your first request on QuotesDone. Its number is ' || v_ref || '.' || chr(10) || chr(10)
        || case when v_held <> '' then 'Before suppliers can price it, we need a few details from you:' || chr(10) || v_held || chr(10) || chr(10) else '' end
        || case when v_find <> '' then v_find || chr(10) || chr(10) else '' end
        || 'Here is how to get exact, comparable quotes, step by step:' || chr(10) || chr(10) || v_steps || chr(10) || chr(10)
        || 'You can follow your request from your account: ' || v_link || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  elsif p_kind = 'finding_suppliers' then
    if v_find = '' then return jsonb_build_object('lang', g->>'lang', 'not_finding', true); end if;
    v_subj := case when v_ar then 'نبحث عن موردين لطلبكم ' || v_ref else 'We are finding suppliers for your request ' || v_ref end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لطلبكم ' || v_ref || '.' || chr(10) || chr(10) || v_find || chr(10) || chr(10)
        || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for your request ' || v_ref || '.' || chr(10) || chr(10) || v_find || chr(10) || chr(10)
        || 'You can follow your request from your account: ' || v_link || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  else
    if v_held = '' then return jsonb_build_object('lang', g->>'lang', 'not_held', true); end if;
    v_subj := case when v_ar then 'طلبكم ' || v_ref || ' يحتاج إلى بعض التفاصيل' else 'Your request ' || v_ref || ' needs a few details' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'يحتاج الموردون الذين وصلهم طلبكم ' || v_ref || ' إلى التفاصيل التالية ليسعّروه بدقة:' || chr(10) || v_held || chr(10) || chr(10)
        || v_steps || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The suppliers who have your request ' || v_ref || ' need the following to price it exactly:' || chr(10) || v_held || chr(10) || chr(10)
        || v_steps || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  end if;
  return jsonb_build_object('lang', g->>'lang', 'subject', v_subj, 'body', v_body, 'held', h, 'first_inquiry', g->'first_inquiry');
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_all int; v_sub int; v_part int; v_none int;
begin
  select count(*) into v_all from public.customers;
  select count(*) filter (where (public.fn_customer_is_substantiated(id)->>'verdict') = 'substantiated'),
         count(*) filter (where (public.fn_customer_is_substantiated(id)->>'verdict') = 'partial'),
         count(*) filter (where (public.fn_customer_is_substantiated(id)->>'verdict') = 'not_substantiated')
    into v_sub, v_part, v_none from public.customers;
  return jsonb_build_object(
    'rows_in_table', v_all,
    'substantiated', v_sub,
    'partial', v_part,
    'not_substantiated', v_none,
    'report_this_one', v_sub,
    'basis', 'rows_in_table counts anything that signed up, including test traffic. Quote '
          || 'substantiated when reporting how many customers the company has.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_decision_support(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  -- A median over fewer than this many quotes is an anecdote wearing a statistic's clothes.
  MIN_PRICE_N constant int := 5;
  v_recommend jsonb;
  v_chase     jsonb;
  v_market    jsonb;
begin
  if p_customer is null then return jsonb_build_object('error','no_customer'); end if;

  -- ── 1. WHICH QUOTE, AND WHY ────────────────────────────────────────────────────────────────
  -- lead_time is free text ('3 weeks', '10-14 days', 'ASAP'). The first integer is taken and
  -- scaled by the unit word; anything that yields no integer is UNKNOWN and never claimed as fast.
  -- A quote with no parseable lead time cannot win the speed comparison, which is the honest
  -- outcome: we would be guessing on the customer's behalf.
  with q as (
    select i.id inq, i.summary, i.category, q.id qid, q.supplier_id,
           coalesce(q.customer_price, q.quote_amount) price,
           q.lead_time,
           case
             when q.lead_time ~ '\d' then
               (regexp_match(q.lead_time, '(\d+)'))[1]::int
               * case when q.lead_time ~* 'week' then 7 when q.lead_time ~* 'month' then 30 else 1 end
             else null
           end days
    from inquiries i
    join quotes q on q.inquiry_id = i.id
    where i.customer_id = p_customer
      and coalesce(q.status,'') not in ('withdrawn','expired','rejected')
      and coalesce(q.customer_price, q.quote_amount) is not null
  ),
  agg as (
    select inq, min(summary) summary, min(category) category, count(*) n,
           min(price) lo, max(price) hi,
           (array_agg(qid order by price asc))[1]                       cheapest_id,
           (array_agg(price order by price asc))[1]                     cheapest_price,
           (array_agg(price order by price asc))[2]                     next_price,
           (array_agg(qid  order by days asc) filter (where days is not null))[1] fastest_id,
           (array_agg(days order by days asc) filter (where days is not null))[1] fastest_days,
           (array_agg(days order by price asc))[1]                      cheapest_days,
           count(*) filter (where days is not null)                     n_with_days
    from q group by inq
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'inquiry_id', inq, 'summary', summary, 'category', category, 'quotes', n,
           'cheapest_quote_id', cheapest_id, 'cheapest_price', cheapest_price,
           'saving_vs_next', case when next_price is not null then next_price - cheapest_price end,
           'fastest_quote_id', fastest_id, 'fastest_days', fastest_days,
           'same_quote_wins', (fastest_id is not null and fastest_id = cheapest_id),
           -- Only a real trade-off gets a trade-off sentence. Null here means either one quote
           -- won both ways, or too few lead times were stated to compare speed at all.
           'days_sooner', case when fastest_id is distinct from cheapest_id and fastest_days is not null
                                 and cheapest_days is not null then cheapest_days - fastest_days end,
           'spread', hi - lo,
           'lead_times_stated', n_with_days
         ) order by n desc), '[]'::jsonb)
    into v_recommend from agg where n >= 2;

  -- ── 2. WHAT A JOB LIKE THIS NORMALLY COSTS ─────────────────────────────────────────────────
  -- Answered per category the customer actually uses, or - for a customer with no requests yet -
  -- left empty rather than filled with the platform average of nothing.
  -- fn_norm_trades is resolved ONCE PER CATEGORY here, not inside the correlated subqueries below.
  -- Called per row it is re-evaluated against all 15,306 supplier_capabilities rows twice over and
  -- the whole function times out - measured, it did.
  with cats as (
    select distinct i.category, i.emirate, public.fn_norm_trades(i.category) norm from inquiries i
    where i.customer_id = p_customer and i.category is not null
  ),
  m as (
    select c.category, c.emirate,
           s.n price_n, s.median, s.p25, s.p75,
           -- THROUGH THE LEXICON, NOT THE RAW CATEGORY. A probe with category 'marble' counted 0
           -- suppliers against 15,306 capability rows, because no supplier lists a trade called
           -- "marble" - fn_norm_trades('marble') is {flooring}, and that is the vocabulary the
           -- capability rows are written in. Comparing the customer's word directly against the
           -- supplier's word is the same defect that left discover() returning nothing while
           -- route_inquiry worked: one path got the lexicon and its sibling did not.
           (select count(*) from supplier_capabilities sc
             where (sc.trades && c.norm or sc.services && c.norm)
               and (c.emirate is null or sc.coverage_emirates && array[c.emirate])) suppliers_covering,
           (select count(*) from supplier_capabilities sc
             where (sc.trades && c.norm or sc.services && c.norm)
               and (c.emirate is null or sc.coverage_emirates && array[c.emirate])
               and sc.review_status = 'confirmed')                                  suppliers_confirmed,
           (select round(avg(extract(epoch from (q.created_at - i2.created_at))/86400)::numeric, 1)
              from inquiries i2 join quotes q on q.inquiry_id = i2.id
             where i2.category = c.category)                                        avg_days_to_quote
    from cats c left join category_price_stats s on s.category = c.category
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'category', category, 'emirate', emirate,
           -- The price block is present ONLY when it rests on enough quotes to mean something.
           -- Absent is a statement; a median over two quotes is a different and false one.
           'price_known', (coalesce(price_n,0) >= MIN_PRICE_N),
           'price_n', coalesce(price_n,0),
           'median', case when coalesce(price_n,0) >= MIN_PRICE_N then median end,
           'p25',    case when coalesce(price_n,0) >= MIN_PRICE_N then p25 end,
           'p75',    case when coalesce(price_n,0) >= MIN_PRICE_N then p75 end,
           'suppliers_covering', suppliers_covering,
           'suppliers_confirmed', suppliers_confirmed,
           'avg_days_to_quote', avg_days_to_quote
         )), '[]'::jsonb)
    into v_market from m;

  -- ── 3. A REQUEST HAS GONE QUIET ────────────────────────────────────────────────────────────
  -- One state per open request, each with the action that actually moves it. The thresholds are
  -- deliberately generous: telling somebody their request is stalled on day one is noise, and a
  -- portal that cries stalled is one a customer stops reading.
  with open_i as (
    select i.id, i.summary, i.category, i.created_at,
           extract(epoch from (now() - i.created_at))/86400 age_days,
           (select count(*) from inquiry_matches m where m.inquiry_id = i.id) invited,
           (select count(*) from quotes q where q.inquiry_id = i.id
              and coalesce(q.status,'') not in ('withdrawn','expired','rejected')) quotes
    from inquiries i
    where i.customer_id = p_customer
      and coalesce(i.status,'open') not in ('closed','cancelled','completed','archived')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'inquiry_id', id, 'summary', summary, 'category', category,
           'age_days', round(age_days::numeric,1), 'invited', invited, 'quotes', quotes,
           -- QUOTE-BEARING STATES ARE TESTED FIRST. Written the other way round, a request that had
           -- collected two quotes but no inquiry_matches row reported 'not_yet_sent' - the portal
           -- telling a customer we had not reached any supplier while two of their quotes sat on
           -- the screen. A quote is proof of delivery; the absence of a match row is only proof
           -- that one path recorded it. Caught by an aborted-transaction probe that seeded exactly
           -- that shape; an empty result would have proved nothing.
           'state', case
             when quotes >= 2 and age_days >= 7              then 'undecided'
             when quotes  = 1 and age_days >= 5              then 'only_one'
             when quotes  = 0 and invited = 0 and age_days >= 1 then 'not_yet_sent'
             when quotes  = 0 and age_days >= 3              then 'no_replies'
             else 'healthy' end
         ) order by age_days desc), '[]'::jsonb)
    into v_chase
    from open_i
   where case
           when quotes >= 2 and age_days >= 7 then true
           when quotes  = 1 and age_days >= 5 then true
           when quotes  = 0 and invited = 0 and age_days >= 1 then true
           when quotes  = 0 and age_days >= 3 then true
           else false end;

  return jsonb_build_object(
    'recommend', v_recommend,
    'market',    v_market,
    'chase',     v_chase,
    'min_price_n', MIN_PRICE_N,
    'as_of', now()
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_document_refs()
 RETURNS TABLE(ref_table text, ref_id text, source text, supplier_id bigint, supplier_name text, revealed boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (
    select c.id
      from public.customers c
     where lower(c.email) = lower(nullif(auth.email(), ''))
        or c.id = auth.uid()
     order by (lower(c.email) = lower(nullif(auth.email(), ''))) desc nulls last
     limit 1
  )
  -- the customer's own uploads
  select 'inquiries'::text, i.id::text, 'inquiry'::text, null::bigint, null::text, true
    from public.inquiries i join me on i.customer_id = me.id
  union all
  -- quotation files sent against their RFQs, and ONLY once the customer has paid to reveal that
  -- quote. A draft quote is not shown to the customer by customer_api, so its attachment is not
  -- shown here either; nor, since 22 Sep 2026, is an unrevealed one's (CP-02).
  select 'quotes'::text, q.id::text, 'quote'::text, q.supplier_id, l.company_name, true
    from public.quotes q
    join public.inquiries i on i.id = q.inquiry_id
    join me on i.customer_id = me.id
    join public.transactions t
      on t.quote_id = q.id and t.customer_id = me.id and t.revealed_at is not null
    left join public.leads l on l.id = q.supplier_id
   where coalesce(q.status, '') <> 'draft'
  union all
  -- supplier documents, and ONLY for a supplier this customer has paid to reveal
  select 'leads'::text, l.id::text, 'supplier'::text, l.id, l.company_name, true
    from public.leads l
   where exists (select 1 from public.transactions t join me on t.customer_id = me.id
                  where t.supplier_id = l.id and t.revealed_at is not null);
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_documents(p_q text DEFAULT NULL::text, p_kind text DEFAULT NULL::text, p_lim integer DEFAULT 50, p_related_refs text[] DEFAULT NULL::text[])
 RETURNS TABLE(id bigint, kind text, file_name text, bucket text, path text, mime text, status text, created_at timestamp with time zone, source text, ref_table text, ref_id text, supplier text, supplier_revealed boolean, expiry_date date, expiry_source text, covers text, covers_source text, summary text, specifications text[], certifications text[], brands text[], extracted_at timestamp with time zone, match_reason text, score real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (
    select nullif(btrim(coalesce(p_q, '')), '') as qtext,
           (select nullif(string_agg('''' || replace(l.lexeme, '''', '''''') || '''', ' | '), '')::tsquery
              from unnest(to_tsvector('english', coalesce(p_q, ''))) l) as tsq,
           coalesce(p_related_refs, '{}'::text[]) as rel
  ),
  base as (
    select d.id, d.kind, d.file_name, d.bucket, d.path, d.mime, d.status, d.created_at,
           d.processed_at, r.source, d.ref_table, d.ref_id,
           case when r.revealed then r.supplier_name end as supplier,
           coalesce(r.revealed, false) as supplier_revealed,
           l.license_expiry, l.insurance_expiry, l.iso_expiry, l.manufacturer_auth_expiry,
           l.license_activity, l.iso_certifications,
           -- THE QUOTE'S OWN WARRANTY. The supplier typed it into the quote; the file they attached
           -- is not where the platform keeps it, so the extraction cannot be asked for it.
           nullif(btrim(coalesce(qt.warranty, '')), '') as quote_warranty,
           case when jsonb_typeof(d.extracted) = 'object' then d.extracted else '{}'::jsonb end as ex
      from public.documents d
      join public.fn_customer_document_refs() r
        on r.ref_table = d.ref_table and r.ref_id = d.ref_id
      left join public.leads l on r.revealed and l.id = r.supplier_id
      left join public.quotes qt on d.ref_table = 'quotes' and qt.id::text = d.ref_id
  ),
  arr as (
    select b.*,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.ex->'specifications') = 'array' then b.ex->'specifications'
                   else '[]'::jsonb end) x) as specs,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.ex->'certifications') = 'array' then b.ex->'certifications'
                   else '[]'::jsonb end) x) as certs,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.ex->'brands') = 'array' then b.ex->'brands'
                   else '[]'::jsonb end) x) as brnds,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.iso_certifications) = 'array' then b.iso_certifications
                   else '[]'::jsonb end) x) as iso_certs
      from base b
  ),
  shaped as (
    select a.id, a.kind, a.file_name, a.bucket, a.path, a.mime, a.status, a.created_at,
           a.source, a.ref_table, a.ref_id, a.supplier, a.supplier_revealed,
           coalesce(
             case when a.ex->>'expiry_date' ~ '^\d{4}-\d{2}-\d{2}$' then (a.ex->>'expiry_date')::date end,
             case when a.ex->>'valid_until' ~ '^\d{4}-\d{2}-\d{2}$' then (a.ex->>'valid_until')::date end,
             case when a.kind in ('licence', 'license') then a.license_expiry end,
             case when a.kind = 'insurance' then a.insurance_expiry end,
             case when a.kind in ('iso', 'certificate') then a.iso_expiry end,
             case when a.kind = 'manufacturer' then a.manufacturer_auth_expiry end
           ) as expiry_date,
           case
             when a.ex->>'expiry_date' ~ '^\d{4}-\d{2}-\d{2}$' then 'extracted.expiry_date'
             when a.ex->>'valid_until' ~ '^\d{4}-\d{2}-\d{2}$' then 'extracted.valid_until'
             when a.kind in ('licence', 'license') and a.license_expiry is not null then 'leads.license_expiry'
             when a.kind = 'insurance' and a.insurance_expiry is not null then 'leads.insurance_expiry'
             when a.kind in ('iso', 'certificate') and a.iso_expiry is not null then 'leads.iso_expiry'
             when a.kind = 'manufacturer' and a.manufacturer_auth_expiry is not null then 'leads.manufacturer_auth_expiry'
           end as expiry_source,
           -- COVERAGE: the quote's warranty first for a quote document, then the extractor's key.
           coalesce(
             a.quote_warranty,
             nullif(btrim(coalesce(a.ex->>'covers', '')), ''),
             nullif(btrim(coalesce(a.ex->>'coverage', '')), ''),
             case when a.kind in ('licence', 'license') then nullif(btrim(coalesce(a.license_activity, '')), '') end,
             case when a.kind in ('iso', 'certificate') then nullif(array_to_string(a.iso_certs, ', '), '') end,
             nullif(array_to_string(a.certs, ', '), '')
           ) as covers,
           case
             when a.quote_warranty is not null then 'quotes.warranty'
             when nullif(btrim(coalesce(a.ex->>'covers', '')), '') is not null then 'extracted.covers'
             when nullif(btrim(coalesce(a.ex->>'coverage', '')), '') is not null then 'extracted.coverage'
             when a.kind in ('licence', 'license')
              and nullif(btrim(coalesce(a.license_activity, '')), '') is not null then 'leads.license_activity'
             when a.kind in ('iso', 'certificate')
              and nullif(array_to_string(a.iso_certs, ', '), '') is not null then 'leads.iso_certifications'
             when nullif(array_to_string(a.certs, ', '), '') is not null then 'extracted.certifications'
           end as covers_source,
           left(nullif(btrim(coalesce(a.ex->>'text', '')), ''), 600) as summary,
           a.specs, a.certs, a.brnds, a.processed_at,
           to_tsvector('english',
             regexp_replace(coalesce(a.file_name, ''), '[^a-zA-Z0-9]+', ' ', 'g') || ' ' ||
             coalesce(a.kind, '') || ' ' || coalesce(a.supplier, '') || ' ' ||
             coalesce(a.license_activity, '') || ' ' ||
             coalesce(a.quote_warranty, '') || ' warranty')
           || jsonb_to_tsvector('english', a.ex, '["string"]') as hay
      from arr a
  ),
  ranked as (
    select s.*,
           case when q.qtext is null then 'all'
                when s.hay @@ q.tsq then 'text'
                else 'related_request' end as mreason,
           case when q.qtext is null then 0::real else ts_rank(s.hay, q.tsq) end as rank_score
      from shaped s, q
     where (p_kind is null or s.kind = lower(btrim(p_kind)))
       and (q.qtext is null
            or s.hay @@ q.tsq
            or (s.ref_table || ':' || s.ref_id) = any (q.rel))
  )
  select z.id, z.kind, z.file_name, z.bucket, z.path, z.mime, z.status, z.created_at,
         z.source, z.ref_table, z.ref_id, z.supplier, z.supplier_revealed,
         z.expiry_date, z.expiry_source, z.covers, z.covers_source,
         z.summary, z.specs, z.certs, z.brnds, z.processed_at, z.mreason, z.rank_score
    from ranked z
   order by z.rank_score desc, z.created_at desc nulls last
   limit greatest(1, coalesce(p_lim, 50));
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_followup_answer(p_token uuid, p_hired text, p_stars integer DEFAULT NULL::integer, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f public.customer_followup; t public.transactions; v_comment text; v_reason text; v_out jsonb := '{}'::jsonb;
begin
  if p_hired is null or p_hired not in ('yes', 'no', 'not_yet') then
    raise exception 'hired is yes, no or not_yet' using errcode = '22023';
  end if;
  if p_stars is not null and p_stars not between 1 and 5 then
    raise exception 'stars are 1 to 5' using errcode = '22023';
  end if;
  select * into f from public.customer_followup where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  -- the first definite answer stands; a second tap on an old e-mail changes nothing
  if f.hired in ('yes', 'no') then return jsonb_build_object('ok', true, 'already', true, 'hired', f.hired); end if;
  select * into t from public.transactions where id = f.transaction_id;
  v_comment := nullif(left(btrim(coalesce(p_comment, '')), 1000), '');

  if p_hired in ('yes', 'no') then
    v_reason := 'customer answered on ' || replace(f.stage, '_', ' ') || ': '
      || case when p_hired = 'yes' then 'hired the revealed supplier' else 'did not hire the revealed supplier' end
      || coalesce(', rated ' || p_stars || '/5', '') || coalesce(': ' || left(v_comment, 300), '');
    if t.inquiry_id is not null then
      v_out := v_out || jsonb_build_object('inquiry', public.fn_outcome_record('inquiries', t.inquiry_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'inquiry', null));
    end if;
    if t.quote_id is not null then
      v_out := v_out || jsonb_build_object('quote', public.fn_outcome_record('quotes', t.quote_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'quote', null));
    end if;
    if p_hired = 'yes' and t.inquiry_id is not null then
      update public.inquiries set hired_supplier_id = t.supplier_id where id = t.inquiry_id and hired_supplier_id is null;
    end if;
  end if;

  -- HOW WAS THE SUPPLIER: one rating per reveal. reviews_reason_required wants ten characters or no comment.
  if p_stars is not null and not exists (select 1 from public.reviews r where r.transaction_id = t.id) then
    insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
    values (t.supplier_id, t.customer_id, t.inquiry_id, t.id, p_stars, case when length(v_comment) >= 10 then v_comment end);
    v_out := v_out || jsonb_build_object('review', true);
  end if;

  update public.customer_followup
     set answered_at = now(), hired = p_hired, stars = coalesce(p_stars, stars), comment = coalesce(v_comment, comment), outcome = v_out
   where id = f.id;
  return jsonb_build_object('ok', true, 'hired', p_hired, 'recorded', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_followup_copy(p_stage text, p_lang text, p_name text, p_company text, p_rfq_no integer, p_trade text, p_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ar boolean := p_lang = 'ar'; v_name text; v_co text; v_when_en text; v_when_ar text;
begin
  v_name := coalesce(nullif(btrim(p_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_co := coalesce(nullif(btrim(p_company), ''), case when v_ar then 'المورّد' else 'the supplier' end);
  v_when_en := case when p_stage = 'day_three' then 'A few days ago' else 'Two weeks ago' end;
  v_when_ar := case when p_stage = 'day_three' then 'قبل أيام' else 'قبل أسبوعين' end;
  if v_ar then
    return jsonb_build_object('lang', 'ar',
      'subject', 'هل تعاقدتم مع ' || v_co || '؟',
      'body', 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || v_when_ar || ' كشفتم بيانات ' || v_co || ' لطلبكم رقم ' || coalesce(p_rfq_no::text, '-')
        || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. هل تعاقدتم معه، وكيف كانت تجربتكم مع المورّد؟' || chr(10) || chr(10)
        || 'أخبرونا بنقرة واحدة: ' || p_link || chr(10) || chr(10)
        || 'تساعدنا إجابتكم على مطابقتكم، ومطابقة كل عميل بعدكم، مع موردين أفضل.' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،');
  end if;
  return jsonb_build_object('lang', 'en',
    'subject', 'Did you hire ' || v_co || '?',
    'body', 'Dear ' || v_name || ',' || chr(10) || chr(10)
      || v_when_en || ' you revealed ' || v_co || ' for your request RFQ-' || coalesce(p_rfq_no::text, '-')
      || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. Did you hire them, and how was the supplier?' || chr(10) || chr(10)
      || 'Tell us with one tap: ' || p_link || chr(10) || chr(10)
      || 'Your answer helps us match you, and every customer after you, with better suppliers.' || chr(10) || chr(10)
      || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_followup_view(p_token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((
    select jsonb_build_object('ok', true, 'lang', f.lang, 'stage', f.stage, 'company', l.company_name,
             'rfq_no', i.rfq_no, 'trade', public.fn_trade_label(coalesce(i.category, i.trades[1]), f.lang),
             'answered', f.answered_at is not null, 'hired', f.hired, 'stars', f.stars)
      from public.customer_followup f
      join public.transactions t on t.id = f.transaction_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where f.token = p_token), jsonb_build_object('ok', false, 'reason', 'not_found'))
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_forecast(p_customer uuid, p_horizon_days integer DEFAULT 365)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rfqs int; v_months int; v_first timestamptz; v_last timestamptz;
  v_spend numeric; v_span_days numeric;
  v_series jsonb; v_by_cat jsonb; v_predictions jsonb;
  v_sufficient boolean; v_reason text;
  v_proj_rfqs numeric; v_proj_spend numeric;
begin
  select count(*), min(i.created_at), max(i.created_at),
         count(distinct date_trunc('month', i.created_at))
    into v_rfqs, v_first, v_last, v_months
    from inquiries i
   where i.customer_id = p_customer and i.parent_inquiry_id is null;

  select coalesce(sum(coalesce(t.quote_amount, 0)), 0) into v_spend
    from transactions t
   where t.customer_id = p_customer and coalesce(t.refund_status, '') <> 'approved';

  -- No history at all. Say so; do not project.
  if coalesce(v_rfqs, 0) = 0 then
    return jsonb_build_object(
      'customer_id', p_customer, 'as_of', now(), 'horizon_days', p_horizon_days,
      'basis', 'no_history', 'sufficient_data', false,
      'empty_reason', 'No requests recorded on this account yet. This forecast is derived from your own past RFQs and orders, so there is nothing to project from until you post your first request.',
      'observed', jsonb_build_object('rfqs', 0, 'months_active', 0, 'spend_aed', 0,
                                     'first_rfq', null, 'last_rfq', null),
      'series', '[]'::jsonb,
      'next_year', jsonb_build_object('horizon_days', p_horizon_days, 'projected_rfqs', null,
                                      'projected_spend_aed', null, 'by_category', '[]'::jsonb),
      'predictions', '[]'::jsonb);
  end if;

  -- The observed window only. The series starts at the customer's FIRST request, never at a padded
  -- twelve months back, so a three-month-old account shows three points and not nine empty ones.
  with months as (
    select generate_series(date_trunc('month', v_first), date_trunc('month', now()), interval '1 month') m
  ), actual as (
    select date_trunc('month', i.created_at) m, count(*) c,
           round(coalesce(sum(i.expected_value), 0), 0) v
      from inquiries i
     where i.customer_id = p_customer and i.parent_inquiry_id is null
     group by 1
  )
  select jsonb_agg(jsonb_build_object('month', to_char(months.m, 'Mon YY'),
                                      'rfqs', coalesce(actual.c, 0),
                                      'value_aed', coalesce(actual.v, 0)) order by months.m)
    into v_series
    from months left join actual on actual.m = months.m;

  -- Two months of activity and three requests is the floor for a run-rate projection. Below it the
  -- figures are null and the reason is printed rather than a straight line drawn through one point.
  v_span_days  := greatest(30, extract(epoch from (now() - v_first)) / 86400.0);
  v_sufficient := v_rfqs >= 3 and v_months >= 2;
  if v_sufficient then
    v_proj_rfqs  := round((v_rfqs::numeric / v_span_days) * p_horizon_days, 1);
    v_proj_spend := round((coalesce(v_spend, 0) / v_span_days) * p_horizon_days, 0);
    v_reason     := null;
  else
    v_proj_rfqs  := null;
    v_proj_spend := null;
    v_reason     := format('Only %s request(s) across %s active month(s) so far. A run-rate projection needs at least 3 requests spanning 2 months, so the next-year figures are withheld rather than extrapolated from a single point.',
                           v_rfqs, v_months);
  end if;

  -- Category mix, projected forward at the same run rate. Shares come from the customer's own
  -- requests, so a customer who only ever bought joinery is not shown an HVAC line.
  with cat as (
    select coalesce(i.category, 'uncategorised') c, count(*) n,
           round(coalesce(sum(i.expected_value), 0), 0) v
      from inquiries i
     where i.customer_id = p_customer and i.parent_inquiry_id is null
     group by 1
  )
  select jsonb_agg(jsonb_build_object(
           'category', c,
           'observed_rfqs', n,
           'observed_value_aed', v,
           'share_pct', round(100.0 * n / nullif(v_rfqs, 0), 1),
           'projected_rfqs', case when v_sufficient
                                  then round(v_proj_rfqs * n / nullif(v_rfqs, 0), 1) end,
           'projected_spend_aed', case when v_sufficient
                                  then round(v_proj_spend * n / nullif(v_rfqs, 0), 0) end
         ) order by n desc, c)
    into v_by_cat from cat;

  -- ── §20: what this customer will likely need next, and by when ────────────────────────────────
  -- Derived, never guessed: for each of the customer's OPEN projects that has a target open date,
  -- the categories they have procured on their other projects and have not yet raised here. The
  -- horizon is that project's own deadline minus the lead time this customer has actually observed
  -- in that category (median days between raising a request and the project's target open date).
  with own as (
    select i.project_id, coalesce(i.category, 'uncategorised') c, i.created_at, p.target_open_date
      from inquiries i join projects p on p.id = i.project_id
     where i.customer_id = p_customer and i.project_id is not null
  ), lead_time as (
    select c, percentile_cont(0.5) within group (
             order by (target_open_date - created_at::date)) med_days
      from own where target_open_date is not null
     group by c
  ), history as (
    select c, count(distinct project_id) projects_used, max(created_at) last_used
      from own group by c
  ), open_projects as (
    select p.id, p.name, p.target_open_date
      from projects p
     where p.customer_id = p_customer
       and coalesce(p.status, 'active') not in ('completed', 'archived', 'cancelled')
       and p.target_open_date is not null
  ), gaps as (
    select op.id project_id, op.name project_name, op.target_open_date, h.c category,
           h.projects_used, lt.med_days,
           greatest(0, (op.target_open_date - current_date)
                       - coalesce(round(lt.med_days)::int, 0)) within_days
      from open_projects op
      cross join history h
      left join lead_time lt on lt.c = h.c
     where not exists (select 1 from inquiries i2
                        where i2.project_id = op.id
                          and coalesce(i2.category, 'uncategorised') = h.c)
  )
  select jsonb_agg(jsonb_build_object(
           'project_id', project_id,
           'project_name', project_name,
           'category', category,
           'target_open_date', target_open_date,
           'within_days', within_days,
           'expected_by', current_date + within_days,
           'confidence', case when projects_used >= 2 and med_days is not null then 'high'
                              when projects_used >= 1 and med_days is not null then 'medium'
                              else 'low' end,
           'reason', format('You have procured %s on %s of your other project(s)%s, and %s has no %s request yet.',
                            category, projects_used,
                            case when med_days is null then ''
                                 else format(', typically %s days before the target open date', round(med_days)) end,
                            project_name, category),
           'recommended_action', case
             when within_days = 0 then format('Post the %s RFQ now — the lead time you have historically needed has already started.', category)
             else format('Contact suppliers and post the %s RFQ within %s day(s) to keep %s on its target open date of %s.',
                         category, within_days, project_name, target_open_date) end
         ) order by within_days, category)
    into v_predictions from gaps;

  return jsonb_build_object(
    'customer_id', p_customer, 'as_of', now(), 'horizon_days', p_horizon_days,
    'basis', 'history', 'sufficient_data', v_sufficient, 'empty_reason', v_reason,
    'observed', jsonb_build_object('rfqs', v_rfqs, 'months_active', v_months,
                                   'spend_aed', round(coalesce(v_spend, 0), 0),
                                   'first_rfq', v_first, 'last_rfq', v_last),
    'series', coalesce(v_series, '[]'::jsonb),
    'next_year', jsonb_build_object('horizon_days', p_horizon_days,
                                    'projected_rfqs', v_proj_rfqs,
                                    'projected_spend_aed', v_proj_spend,
                                    'by_category', coalesce(v_by_cat, '[]'::jsonb)),
    'predictions', coalesce(v_predictions, '[]'::jsonb));
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_is_substantiated(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; v_for text[] := '{}'; v_against text[] := '{}'; v_activity int;
begin
  select * into c from public.customers where id = p_customer_id;
  if c.id is null then
    return jsonb_build_object('verdict','unknown','reason','no such customer');
  end if;

  -- Evidence FOR a real person
  if coalesce(trim(c.full_name),'') <> ''   then v_for := v_for || 'has a name'::text;        else v_against := v_against || 'no name'::text; end if;
  if coalesce(trim(c.phone),'')     <> ''   then v_for := v_for || 'has a mobile'::text;      else v_against := v_against || 'no mobile'::text; end if;
  if c.tos_accepted_at is not null          then v_for := v_for || 'accepted the terms'::text;else v_against := v_against || 'never accepted the terms'::text; end if;
  if c.phone_verified                       then v_for := v_for || 'verified a mobile'::text; end if;

  select (select count(*) from public.inquiries  i where i.customer_id = c.id)
       + (select count(*) from public.transactions t where t.customer_id = c.id)
    into v_activity;
  if v_activity > 0 then v_for := v_for || (v_activity || ' business record(s)')::text;
                    else v_against := v_against || 'no inquiry and no transaction, ever'::text; end if;

  -- The marker test is kept, but ONLY as an additional way to be fake — never as a way to be real.
  if c.full_name ilike 'ZZ DEMO%' or c.email ilike '%@example.invalid' then
    v_against := v_against || 'carries an explicit demo marker'::text;
  end if;

  return jsonb_build_object(
    'verdict', case when array_length(v_for,1) is null then 'not_substantiated'
                    when array_length(v_against,1) is null then 'substantiated'
                    else 'partial' end,
    'evidence_for', coalesce(to_jsonb(v_for), '[]'::jsonb),
    'evidence_against', coalesce(to_jsonb(v_against), '[]'::jsonb),
    'basis', 'Scored on evidence that this is a real buyer. The absence of a ZZ DEMO name or an '
          || '@example.invalid address is NOT evidence of realness — that inference is what caused a '
          || 'test signup to be reported to the founder as the company''s first customer on 9 Sep 2026.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_mandatory_check(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; miss text[] := '{}'; have text[] := '{}';
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No such customer.');
  end if;

  if coalesce(btrim(c.full_name),'') = '' then miss := array_append(miss,'Name');
  else have := array_append(have,'Name'); end if;

  -- The founder said "mobile" for a customer without naming a country, so this checks that a number
  -- exists and has been verified, rather than imposing a UAE prefix he did not ask for. A buyer may
  -- reasonably be abroad; a supplier holding a UAE trade licence may not.
  if coalesce(btrim(c.phone),'') = '' then miss := array_append(miss,'Mobile number');
  elsif not coalesce(c.phone_verified,false) then miss := array_append(miss,'Mobile number (not yet verified)');
  else have := array_append(have,'Mobile number'); end if;

  if coalesce(btrim(c.email),'') = '' then miss := array_append(miss,'Email address');
  elsif not coalesce(c.email_verified,false) then miss := array_append(miss,'Email address (not yet verified)');
  else have := array_append(have,'Email address'); end if;

  if coalesce(btrim(c.signed_terms_path),'') = '' and c.tos_accepted_at is null
  then miss := array_append(miss,'Signed terms and conditions');
  else have := array_append(have,'Signed terms and conditions'); end if;

  return jsonb_build_object(
    'ok', true, 'party_kind','customer', 'id', p_customer_id::text, 'name', c.full_name,
    'complete', coalesce(array_length(miss,1),0) = 0,
    'have', to_jsonb(have), 'missing', to_jsonb(miss),
    'missing_count', coalesce(array_length(miss,1),0),
    'mandatory_total', 4
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_message_lang(p_inquiry uuid, p_customer_locale text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text;
begin
  -- the language chosen for the request; the registered one only when the request carries none.
  -- ponytail: fn_inquiry_locale is looked up at run time so this file can be replayed (seat-duty probes) before
  -- #1065 is applied; once #1065 is live the lookup always succeeds and this is a plain call.
  if to_regprocedure('public.fn_inquiry_locale(uuid)') is not null then
    execute 'select public.fn_inquiry_locale($1)' into v using p_inquiry;
  end if;
  return coalesce(v, case when p_customer_locale = 'ar' then 'ar' else 'en' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_orders(p_customer uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'po_no', o.po_no, 'status', o.status,
      'order_date', o.order_date, 'expected_date', o.expected_date,
      'currency', o.currency, 'subtotal', o.subtotal, 'memo', o.memo,
      'inquiry_id', o.inquiry_id, 'quote_id', o.quote_id, 'project_id', o.project_id,
      'approved_at', o.approved_at,
      'lines', coalesce((select jsonb_agg(jsonb_build_object(
                  'line_no', l.line_no, 'description', l.description, 'qty', l.qty,
                  'unit_price', l.unit_price, 'qty_received', l.qty_received) order by l.line_no)
                from public.po_lines l where l.po_id = o.id), '[]'::jsonb))
      order by o.order_date desc, o.id desc), '[]'::jsonb)
    from public.po_orders o
   where o.customer_id = p_customer;
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_preference_learn(p_customer_id uuid, p_stated jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_consent timestamptz;
  v_existing jsonb;
  v_inferred jsonb;
begin
  if p_customer_id is null then return 0; end if;

  -- CONSENT IS THE GATE, and it reuses the consent the customer already gave. No new column, no
  -- new UI, no second consent vocabulary.
  --
  -- WITHDRAWAL DELETES. The fixture caught this: clearing customer_preference.consented_at is not
  -- withdrawing consent, because consent lives on customers.tos_accepted_at and the next inquiry
  -- simply re-learned and restored the copy. So the absence of consent actively REMOVES the
  -- profile rather than merely declining to refresh it — row absent is indistinguishable from
  -- never consented, which is the property the readers rely on.
  select c.tos_accepted_at into v_consent from customers c where c.id = p_customer_id;
  if v_consent is null then
    delete from customer_preference where customer_id = p_customer_id;
    return 0;
  end if;

  select p.preferences into v_existing from customer_preference p where p.customer_id = p_customer_id;

  -- The same aggregates fn_ws_customer_360 computes live today, persisted instead of recomputed.
  select jsonb_build_object(
           'categories', coalesce(jsonb_agg(distinct i.category) filter (where i.category is not null), '[]'::jsonb),
           'emirates',   coalesce(jsonb_agg(distinct i.emirate)  filter (where i.emirate  is not null), '[]'::jsonb),
           'scope_type', mode() within group (order by i.scope_type),
           'budget_aed_avg', round(avg(nullif(i.expected_value, 0))::numeric, 2),
           'rfqs_seen', count(*))
    into v_inferred
    from inquiries i where i.customer_id = p_customer_id;

  insert into customer_preference (customer_id, preferences, consented_at, updated_at)
  values (p_customer_id,
          jsonb_build_object(
            -- stated is merged, never replaced: an inference must not clear a typed choice.
            'stated',   coalesce(v_existing->'stated', '{}'::jsonb) || coalesce(p_stated, '{}'::jsonb),
            'inferred', coalesce(v_inferred, '{}'::jsonb),
            'source',   'fn_customer_preference_learn'),
          v_consent, now())
  on conflict (customer_id) do update
    set preferences = excluded.preferences,
        consented_at = excluded.consented_at,
        updated_at   = now();
  return 1;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_savings(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_min_sample int;
  v_rows int;
  v_by_cat jsonb;
  v_spread numeric; v_bench numeric;
begin
  select coalesce((p.policy ->> 'min_sample')::int, 4) into v_min_sample
    from supplier_negotiation_policy p where p.scope = 'default';
  v_min_sample := coalesce(v_min_sample, 4);

  select count(*) into v_rows
    from quotes q join inquiries i on i.id = q.inquiry_id
   where i.customer_id = p_customer and coalesce(q.status, '') <> 'draft'
     and q.quote_amount is not null and q.quote_amount > 0;

  if v_rows = 0 then
    return jsonb_build_object(
      'customer_id', p_customer, 'as_of', now(), 'min_sample', v_min_sample,
      'by_category', '[]'::jsonb,
      'total_spread_saving_aed', null, 'total_benchmark_saving_aed', null,
      'quotes_considered', 0,
      'empty_reason', 'No quotes on your requests yet. Potential savings are measured from the quotes you actually hold — the spread between them, and each one against the market median for its category — so there is nothing to compute until suppliers respond.');
  end if;

  with live as (
    select q.id, q.inquiry_id, q.quote_amount, coalesce(i.category, 'uncategorised') category
      from quotes q join inquiries i on i.id = q.inquiry_id
     where i.customer_id = p_customer and coalesce(q.status, '') <> 'draft'
       and q.quote_amount is not null and q.quote_amount > 0
       and coalesce(i.status, '') not in ('completed', 'cancelled', 'closed')
  ), per_rfq as (
    select inquiry_id, category, count(*) n_quotes,
           max(quote_amount) - min(quote_amount) spread, min(quote_amount) cheapest
      from live group by inquiry_id, category
  ), bench as (
    select l.category, l.inquiry_id, min(l.quote_amount) cheapest, s.median, s.n
      from live l left join category_price_stats s on s.category = l.category
     group by l.category, l.inquiry_id, s.median, s.n
  )
  select jsonb_agg(x order by x ->> 'category'), sum((x ->> 'spread_saving_aed')::numeric),
         sum(coalesce((x ->> 'benchmark_saving_aed')::numeric, 0))
    into v_by_cat, v_spread, v_bench
    from (
      select jsonb_build_object(
               'category', p.category,
               'rfqs', count(distinct p.inquiry_id),
               'quotes', sum(p.n_quotes),
               'spread_saving_aed', round(sum(case when p.n_quotes >= 2 then p.spread else 0 end), 0),
               'market_median', max(b.median),
               'market_sample_n', max(b.n),
               'benchmark_saving_aed', case when max(b.n) >= v_min_sample
                 then round(greatest(0, sum(b.cheapest) - sum(b.median)), 0) end,
               'benchmark_basis', case when coalesce(max(b.n), 0) >= v_min_sample
                 then format('cheapest quote(s) held against a market median over %s comparable quote(s)', max(b.n))
                 else format('no market benchmark: only %s comparable quote(s) recorded in this category, and %s are needed',
                             coalesce(max(b.n), 0), v_min_sample) end
             ) x
        from per_rfq p join bench b on b.inquiry_id = p.inquiry_id and b.category = p.category
       group by p.category
    ) z;

  return jsonb_build_object(
    'customer_id', p_customer, 'as_of', now(), 'min_sample', v_min_sample,
    'by_category', coalesce(v_by_cat, '[]'::jsonb),
    'total_spread_saving_aed', v_spread,
    'total_benchmark_saving_aed', case when v_bench > 0 then v_bench end,
    'quotes_considered', v_rows,
    'empty_reason', case when coalesce(v_bench, 0) = 0
      then format('No market benchmark saving is shown: no category on your open requests yet has the %s comparable quotes this house policy requires before it will quote a market median.', v_min_sample) end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_spec_guide(p_trade text)
 RETURNS TABLE(trade text, body_en text, body_ar text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select g.trade, g.body_en, g.body_ar
    from public.customer_spec_guide g
   where g.trade = p_trade and g.status = 'published';
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_stats(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; v_inq int; v_open int; v_quotes int; v_deals int; v_spend numeric; v_list jsonb; v_hist jsonb;
begin
  select count(*) into v_inq from inquiries where customer_id=p_customer and parent_inquiry_id is null;
  select count(*) into v_open from inquiries where customer_id=p_customer and parent_inquiry_id is null and coalesce(status,'') not in ('completed','closed','cancelled','split');
  select count(*) into v_quotes from quotes q where q.status <> 'draft' and q.inquiry_id in (select id from inquiries where customer_id=p_customer);
  select count(*) into v_deals from transactions where customer_id=p_customer;
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0) into v_spend from transactions where customer_id=p_customer and coalesce(refund_status,'')<>'approved';
  select jsonb_agg(x order by (x->>'created_at') desc) into v_list from (
    select jsonb_build_object(
      'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
      'created_at', i.created_at, 'pipeline_stage', i.pipeline_stage, 'outcome', i.outcome,
      'has_drawing', (i.drawing_file_path is not null), 'boq_confidence', i.boq_confidence,
      'quotes_count', (select count(*) from quotes q where q.inquiry_id=i.id and q.status <> 'draft'),
      'minutes_since', round(extract(epoch from (now()-i.created_at))/60.0)::int,
      'editable', (i.status='sent') and (now()-i.created_at) < interval '60 minutes',
      'edit_minutes_left', greatest(0, 60 - round(extract(epoch from (now()-i.created_at))/60.0)::int)
    ) x from inquiries i where i.customer_id=p_customer and i.parent_inquiry_id is null
  ) t;
  with months as (select date_trunc('month',(now()-(n||' month')::interval)) m from generate_series(0,11) n),
  ib as (select date_trunc('month',created_at) m, count(*) c from inquiries where customer_id=p_customer and parent_inquiry_id is null group by 1)
  select jsonb_agg(jsonb_build_object('month',to_char(months.m,'Mon YY'),'inquiries',coalesce(ib.c,0)) order by months.m)
    into v_hist from months left join ib on ib.m=months.m;
  v := jsonb_build_object(
    'customer_id', p_customer,'inquiries_total', v_inq,'open_inquiries', v_open,
    'quotes_received', v_quotes,'avg_quotes_per_inquiry', round(v_quotes::numeric/nullif(v_inq,0),1),
    'deals', v_deals,'total_spend', v_spend,
    'inquiries', coalesce(v_list,'[]'::jsonb),'history_12m', v_hist);
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_supplier_score(p_customer uuid, p_supplier bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sent int; v_quoted int; v_awarded int; v_reveals int; v_acked int; v_refunds int;
  v_avg_quote numeric; v_resp_hours numeric; v_last timestamptz;
  v_rating numeric; v_dims jsonb; v_reviews int;
  v_responsiveness numeric; v_award_rate numeric; v_delivery numeric;
  v_quality numeric; v_refund_free numeric;
  v_parts jsonb := '[]'::jsonb; v_sum numeric := 0; v_wt numeric := 0;
  v_global jsonb; v_supplier text;
  -- each component contributes only when the customer's history actually carries it, so a single
  -- review does not become the whole verdict and a missing dimension does not read as a zero
  v_method text := 'weighted mean over the components with data';
begin
  select l.company_name into v_supplier from leads l where l.id = p_supplier;
  if v_supplier is null then
    return jsonb_build_object('error', 'unknown_supplier', 'supplier_id', p_supplier);
  end if;

  select count(*) into v_sent
    from inquiry_matches m join inquiries i on i.id = m.inquiry_id
   where m.supplier_id = p_supplier and i.customer_id = p_customer;

  select count(*), round(avg(q.quote_amount), 0),
         round(avg(extract(epoch from (q.created_at - i.created_at)) / 3600.0)::numeric, 1),
         max(q.created_at)
    into v_quoted, v_avg_quote, v_resp_hours, v_last
    from quotes q join inquiries i on i.id = q.inquiry_id
   where q.supplier_id = p_supplier and i.customer_id = p_customer
     and coalesce(q.status, '') <> 'draft';

  select count(*) into v_awarded
    from inquiries i
   where i.customer_id = p_customer and i.hired_supplier_id = p_supplier;

  select count(*),
         count(*) filter (where t.supplier_ack_at is not null),
         count(*) filter (where coalesce(t.refund_status, '') = 'approved')
    into v_reveals, v_acked, v_refunds
    from transactions t
   where t.customer_id = p_customer and t.supplier_id = p_supplier;

  select count(*), round(avg(r.rating)::numeric, 2),
         jsonb_build_object(
           'communication', round(avg(r.r_communication)::numeric, 2),
           'quality', round(avg(r.r_quality)::numeric, 2),
           'punctuality', round(avg(r.r_punctuality)::numeric, 2),
           'documentation', round(avg(r.r_documentation)::numeric, 2),
           'after_sales', round(avg(r.r_after_sales)::numeric, 2),
           'compliance', round(avg(r.r_compliance)::numeric, 2))
    into v_reviews, v_rating, v_dims
    from reviews r
   where r.customer_id = p_customer and r.supplier_id = p_supplier;

  select jsonb_build_object('reliability', s.reliability, 'quality_rating', s.quality_rating,
                            'price_index', s.price_index, 'response_rate', s.response_rate,
                            'avg_response_hours', s.avg_response_hours,
                            'quotes_submitted', s.quotes_submitted, 'quotes_won', s.quotes_won,
                            'computed_at', s.computed_at)
    into v_global from supplier_score s where s.lead_id = p_supplier;

  -- Nothing shared: report the global figures and refuse to invent a relationship.
  if coalesce(v_sent, 0) = 0 and coalesce(v_quoted, 0) = 0 and coalesce(v_reveals, 0) = 0
     and coalesce(v_reviews, 0) = 0 then
    return jsonb_build_object(
      'customer_id', p_customer, 'supplier_id', p_supplier, 'supplier_name', v_supplier,
      'basis', 'no_shared_history', 'relationship_score', null,
      'empty_reason', format('You have not worked with %s yet. A relationship score is built from your own RFQs, quotes, orders and reviews with a supplier, so there is nothing to score until the first one.', v_supplier),
      'history', jsonb_build_object('rfqs_sent', 0, 'quotes_received', 0, 'orders', 0,
                                    'reveals', 0, 'reviews', 0),
      'delivery_pct', null, 'quality_pct', null, 'win_rate_pct', null,
      'avg_response_hours', null, 'avg_quote_aed', null, 'last_interaction_at', null,
      'your_rating', null, 'your_rating_dimensions', null,
      'components', '[]'::jsonb,
      'platform_wide', coalesce(v_global, 'null'::jsonb));
  end if;

  if v_sent > 0 then
    v_responsiveness := round(least(100, 100.0 * v_quoted / v_sent), 1);
    v_parts := v_parts || jsonb_build_object('name', 'responsiveness', 'value', v_responsiveness,
      'weight', 30, 'basis', format('%s of %s RFQs you sent came back with a quote', v_quoted, v_sent));
    v_sum := v_sum + v_responsiveness * 30; v_wt := v_wt + 30;
  end if;

  if v_quoted > 0 then
    v_award_rate := round(100.0 * v_awarded / v_quoted, 1);
    v_parts := v_parts || jsonb_build_object('name', 'award_rate', 'value', v_award_rate,
      'weight', 15, 'basis', format('you awarded %s of their %s quote(s)', v_awarded, v_quoted));
    v_sum := v_sum + v_award_rate * 15; v_wt := v_wt + 15;
  end if;

  if v_reveals > 0 then
    v_delivery      := round(100.0 * v_acked / v_reveals, 1);
    v_refund_free   := round(100.0 * (v_reveals - v_refunds) / v_reveals, 1);
    v_parts := v_parts || jsonb_build_object('name', 'delivery', 'value', v_delivery,
      'weight', 30, 'basis', format('%s of %s reveal(s) were acknowledged by the supplier', v_acked, v_reveals));
    v_parts := v_parts || jsonb_build_object('name', 'no_refund', 'value', v_refund_free,
      'weight', 10, 'basis', format('%s of %s reveal(s) ended in a refund', v_refunds, v_reveals));
    v_sum := v_sum + v_delivery * 30 + v_refund_free * 10; v_wt := v_wt + 40;
  end if;

  if v_reviews > 0 and v_rating is not null then
    v_quality := round(100.0 * v_rating / 5.0, 1);
    v_parts := v_parts || jsonb_build_object('name', 'your_rating', 'value', v_quality,
      'weight', 25, 'basis', format('your %s review(s) average %s out of 5', v_reviews, v_rating));
    v_sum := v_sum + v_quality * 25; v_wt := v_wt + 25;
  end if;

  return jsonb_build_object(
    'customer_id', p_customer, 'supplier_id', p_supplier, 'supplier_name', v_supplier,
    'basis', 'shared_history', 'empty_reason', null,
    'relationship_score', case when v_wt > 0 then round(v_sum / v_wt, 0)::int end,
    'score_method', v_method,
    'history', jsonb_build_object('rfqs_sent', v_sent, 'quotes_received', v_quoted,
                                  'orders', v_awarded, 'reveals', v_reveals, 'reviews', v_reviews),
    'delivery_pct', v_delivery,
    'quality_pct', v_quality,
    'win_rate_pct', v_award_rate,
    'avg_response_hours', v_resp_hours,
    'avg_quote_aed', v_avg_quote,
    'last_interaction_at', v_last,
    'your_rating', v_rating,
    'your_rating_dimensions', case when v_reviews > 0 then v_dims end,
    'components', v_parts,
    'platform_wide', coalesce(v_global, 'null'::jsonb));
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_activation_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_ar boolean; v_name text; v_signup int := 0; v_noquote int := 0; v_stalled int := 0;
begin
  -- a) signed up three days ago or more, never posted a request
  for r in select c.id, c.full_name, c.email, c.locale from public.customers c
            where c.created_at < now() - interval '3 days' and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.inquiries i where i.customer_id = c.id)
            order by c.created_at limit 200 loop
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v := public.fn_customer_support_duty_send('activation.first_request', r.id::text, 'customer', r.email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'طلبكم الأول على QuotesDone' else 'Your first request on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لانضمامكم إلى QuotesDone. لم تنشروا طلبكم الأول بعد، انشروا طلبكم مرة واحدة، وأرفقوا المخطط أو جدول الكميات إن توفّر، فيقدّم الموردون الموثّقون في الإمارات العاملون في هذا التخصص عروضهم، ونقارنها لكم ونوصي بأفضل ثلاثة منها من حيث القيمة في تقرير المقارنة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها.' || chr(10) || chr(10)
        || 'ابدؤوا من هنا: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'وإن واجهتم ما يمنعكم من البدء، يسعدنا أن تردّوا على هذه الرسالة لنساعدكم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for joining QuotesDone. You have not posted a request yet. Post your request once, with a drawing or a bill of quantities if you have one; verified UAE suppliers in that trade quote, and we compare them and recommend the top three by value in your comparison report. You reveal only the one you choose, and pay 3% only then.' || chr(10) || chr(10)
        || 'Start here: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'If something stopped you, reply to this e-mail and we will help.' end,
      r.id);
    if (v->>'sent')::boolean then v_signup := v_signup + 1; end if;
  end loop;

  -- b) a request five days old with no quote, and c) ten days old with none: the second is a judgement
  for r in select i.id, i.rfq_no, i.created_at, i.category, i.emirate, i.trades, i.rfq_ready, i.completeness,
                  i.summary_masked, c.id as cid, c.full_name, c.email, c.locale
             from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.created_at < now() - interval '5 days' and i.created_at > now() - interval '60 days'
              and i.completed_at is null and i.hired_supplier_id is null and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
            order by i.created_at limit 200 loop
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v := public.fn_customer_support_duty_send('activation.no_quote', r.id::text, 'customer', r.email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'طلبكم لم يصله عرض سعر بعد' else 'Your request has no quote yet' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'لم يصل بعدُ أي عرض سعر على طلبكم المنشور بتاريخ ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY')
        || '، وما زلنا ندعو الموردين العاملين في هذا المجال. ويساعد الموردين على التسعير بسرعة أن يتضمّن الطلب نطاق العمل والكميات والمخطط، ويمكنكم إضافتها من حسابكم: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'ولأي مساعدة، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Your request posted on ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ' has not received a quote yet, and we are still inviting suppliers who work in this trade. A clear scope, quantities and a drawing help suppliers price quickly; you can add them from your account: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'Reply to this e-mail if you would like help.' end,
      r.cid, null, r.id);
    if (v->>'sent')::boolean then v_noquote := v_noquote + 1; end if;

    if r.created_at < now() - interval '10 days'
       and not exists (select 1 from public.customer_support_duty_message m where m.stage = 'activation.stalled' and m.subject_key = r.id::text)
       and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'stalled_request:' || r.id) then
      perform public.fn_seat_duty_reason('customer_support', 'customer_support.stalled_request',
        case when v_fx then 'ZZ DEMO ' else '' end
        || 'A customer''s request has had no quote for ' || extract(day from now() - r.created_at)::int
        || ' days. From the facts of the request, which message should customer support send the customer?',
        jsonb_build_array(
          jsonb_build_object('id', 'add_details', 'meaning', 'the request lacks what a supplier needs to price it; ask the customer for the missing scope, quantities or drawing'),
          jsonb_build_object('id', 'widen_scope', 'meaning', 'the request is priceable but too narrow for the suppliers available; suggest widening the emirate, the trade or the delivery window'),
          jsonb_build_object('id', 'keep_waiting', 'meaning', 'the request is sound; tell the customer it is still with suppliers and when to expect news')),
        jsonb_build_object('inquiry_id', r.id, 'rfq_no', r.rfq_no, 'posted_at', r.created_at, 'category', r.category,
          'emirate', r.emirate, 'trades', to_jsonb(r.trades), 'rfq_ready', r.rfq_ready, 'completeness', r.completeness,
          'summary', r.summary_masked, 'quotes', 0),
        jsonb_build_object('inquiry_id', r.id), 'stalled_request:' || r.id);
      v_stalled := v_stalled + 1;
    end if;
  end loop;
  return jsonb_build_object('first_request', v_signup, 'no_quote', v_noquote, 'stalled_filed', v_stalled);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; v_ar boolean; v_subject text; v_body text; v_nid bigint; v_fan jsonb; v_cc text[]; v_res jsonb;
  p public.notifications; v_before bigint; v_from text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; v_from := d->>'from';
  if d->>'type' <> 'delivery.request' then raise exception 'customer_support has no handler for %', d->>'type'; end if;

  if d ? 'prepared' then
    p := jsonb_populate_record(null::public.notifications, d->'prepared');
    if p.to_role in ('customer', 'supplier') and v_from not in ('sales_engineer', 'customer_support') then
      raise exception 'only the sales engineer and support address customers and suppliers; % may address the founder only', v_from;
    end if;
    -- The caller chooses the words and the address. It never chooses the status, the sender or the
    -- requester: those are support's record of what it was asked and what it did.
    -- Tracked by THIS request, so the adoption trigger (section 5) must not open a second one.
    perform set_config('app.qd_delivery_tracked', 'on', true);
    insert into public.notifications (type, kind, to_email, cc_emails, to_role, to_phone, lead_id, inquiry_id, quote_id,
                                      channel, subject, body, html, attachments, lang, status, requested_by)
    values (p.type, p.kind, p.to_email, coalesce(p.cc_emails, '{}'), p.to_role, p.to_phone, p.lead_id, p.inquiry_id, p.quote_id,
            coalesce(p.channel, 'email'), p.subject, p.body, p.html, p.attachments, p.lang, 'queued', v_from)
    returning id into v_nid;
    select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.channel = 'whatsapp' and n.id > v_nid and n.created_at = now() and n.type = p.type
       and n.to_email is not distinct from p.to_email;
    perform set_config('app.qd_delivery_tracked', 'off', true);
    return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                              'channel', coalesce(p.channel, 'email'), 'prepared', true);
  end if;

  if d->>'recipient_role' = 'founder' then
    -- A NEW BUG WAITS FOR THE DIGEST (the_founder_gets_one_it_digest_per_tick.sql). 55 requests in one
    -- minute were 55 emails and 55 WhatsApp messages; fn_customer_support_sends_the_it_digest sends them
    -- as one. 'waiting' keeps the request pending, so the watch does not read it until it is sent.
    if d->>'kind' = 'it_new_bug' then
      return jsonb_build_object('channel', 'founder', 'digest', 'pending', 'event', d->>'event',
                                'waiting', 'the next IT digest (fn_customer_support_sends_the_it_digest)');
    end if;
    -- A TEST NEVER REACHES HIM. The fixture ladder sets app.qd_stub_founder_notify; the probe also
    -- aborts its transaction, so even the queued rows are never committed.
    if coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on' then
      return jsonb_build_object('channel', 'founder', 'stubbed', true, 'event', d->>'event');
    end if;
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => d->>'event', p_detail => d->>'detail', p_level => coalesce(d->>'level', 'high'),
                                      p_kind => d->>'kind', p_dedupe_key => d->>'dedupe_key', p_owner_agent => 'customer_support');
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
    return jsonb_build_object('channel', 'founder', 'notify', v_res, 'notification_ids', v_fan,
                              'notification_id', v_fan->0);
  end if;

  if v_from <> 'sales_engineer' then
    raise exception 'only the sales engineer addresses customers and suppliers; % may address the founder only', v_from;
  end if;
  if coalesce(d->>'to_email', '') !~ '@' then
    return jsonb_build_object('delivered', false, 'reason', 'no email address on file for the ' || coalesce(d->>'recipient_role', 'recipient'));
  end if;

  v_ar := d->>'locale' = 'ar' and d->>'body_ar' is not null;
  v_subject := case when v_ar then coalesce(d->>'subject_ar', d->>'subject_en') else d->>'subject_en' end;
  v_body    := case when v_ar then d->>'body_ar' else d->>'body_en' end;
  select coalesce(array_agg(x), '{}') into v_cc from jsonb_array_elements_text(coalesce(d->'cc', '[]'::jsonb)) x;

  perform set_config('app.qd_delivery_tracked', 'on', true);
  -- requested_by names the seat that asked (customer_support_is_the_only_sender_on_email_and_whatsapp.sql);
  -- sender stays customer_support by that file's default and check.
  insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
  values (d->>'msg_type', d->>'msg_type', d->>'to_email', v_cc, d->>'recipient_role',
          (d->>'supplier_id')::bigint, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, 'email', v_subject, v_body, 'queued',
          v_from)
  returning id into v_nid;
  select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
   where n.channel = 'whatsapp' and n.type = d->>'msg_type' and n.id > v_nid
     and n.to_email = d->>'to_email' and n.created_at >= now() - interval '1 minute';
  perform set_config('app.qd_delivery_tracked', 'off', true);

  return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                            'language', case when v_ar then 'ar' else 'en' end,
                            'watch_until', d->'watch_until', 'watching', (d->>'watch_until') is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_adopts_untracked_send()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_from text; v_id bigint;
begin
  if coalesce(current_setting('app.qd_delivery_tracked', true), '') = 'on' then return null; end if;
  if coalesce(NEW.requested_by, '') = 'platform' then return null; end if;
  v_from := coalesce(nullif(btrim(NEW.requested_by), ''), 'customer_support');
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, detail, evidence, target_table, target_id, decided_at, decided_by)
    values ('customer_support', 'handoff', 'done', 'low',
            left('delivery.request from ' || v_from || ' about notifications ' || NEW.id, 200),
            jsonb_build_object('type', 'delivery.request', 'from', v_from, 'from_name', v_from, 'to', 'customer_support',
                               'subject_table', 'notifications', 'subject_id', NEW.id::text, 'adopted', true,
                               'msg_type', NEW.type, 'recipient_role', NEW.to_role, 'to_email', NEW.to_email,
                               'supplier_id', NEW.lead_id, 'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id),
            jsonb_build_object('queued', true, 'adopted', true, 'notification_id', NEW.id, 'channel', NEW.channel),
            'notifications', 'delivery.request:notification:' || NEW.id, now(), 'customer_support')
    returning id into v_id;
    perform public.fn_seat_handoff_event(v_id, 'sent');
    perform public.fn_seat_handoff_event(v_id, 'done');
  exception when others then
    begin
      perform public.fn_support_report_to_ceo('adoption_failed:' || NEW.id, 'serious',
        'A ' || coalesce(NEW.type, 'notice') || ' left the outbox without a loop: adopting it failed',
        jsonb_build_object('notification_id', NEW.id, 'requested_by', NEW.requested_by, 'error', left(sqlerrm, 500)),
        jsonb_build_array('the send itself was kept'),
        'Find why fn_customer_support_adopts_untracked_send failed and track this notification by hand.',
        'notifications#' || NEW.id);
    exception when others then
      raise warning 'fn_customer_support_adopts_untracked_send: notification % not adopted and not reported: %', NEW.id, sqlerrm;
    end;
    return null;
  end;
  -- a seat the register does not list: filed under its own name above, and the gap raised once
  if v_from <> 'customer_support' and not exists (select 1 from public.fn_seat_handoff_types() t
       where t.type = 'delivery.request' and t.from_seat = v_from and t.to_seat = 'customer_support') then
    perform public.fn_support_report_to_ceo('unregistered_sender:' || v_from, 'elevated',
      v_from || ' sends notices but has no delivery conversation with customer_support',
      jsonb_build_object('seat', v_from, 'first_notification_id', NEW.id, 'request_id', v_id),
      jsonb_build_array('the request was filed under ' || v_from || ', not reassigned'),
      'Add delivery.request (' || v_from || ' -> customer_support) and delivery.result (customer_support -> ' || v_from || ') to fn_seat_handoff_types.',
      'agent_actions#' || v_id);
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_campaign_list_attach(p_id bigint, p_bucket text DEFAULT NULL::text, p_path text DEFAULT NULL::text, p_url text DEFAULT NULL::text, p_bytes integer DEFAULT NULL::integer, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.supplier_campaign_daily_list; v_nid bigint; v_to text;
begin
  select * into r from public.supplier_campaign_daily_list where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such supplier_campaign_daily_list ' || p_id); end if;
  if r.notification_id is not null then return jsonb_build_object('ok', true, 'already_sent', true, 'notification_id', r.notification_id); end if;
  if p_path is null or coalesce(p_error, '') <> '' then
    update public.supplier_campaign_daily_list set pdf_error = coalesce(nullif(p_error, ''), 'pdf_native returned no path'),
           attempts = attempts + 1, updated_at = now() where id = p_id;
    return jsonb_build_object('ok', false, 'retained', true, 'error', coalesce(nullif(p_error, ''), 'pdf_native returned no path'));
  end if;
  if not coalesce((select allowed_to_email from public.founder_mail_policy where kind = 'supplier_campaign_daily_list'), false) then
    return jsonb_build_object('ok', false, 'error', 'founder_mail_policy does not allow supplier_campaign_daily_list');
  end if;
  v_to := lower(btrim(coalesce(nullif(split_part((select value from public.app_secrets where key = 'admin_emails'), ',', 1), ''), 'management@quotesdone.com')));
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, attachments, requested_by)
  values ('supplier_campaign_daily_list', 'supplier_campaign_daily_list', v_to, 'founder', left(r.subject, 200), r.body, 'queued', 'email',
          jsonb_build_array(jsonb_build_object('bucket', coalesce(p_bucket, 'agent-docs'), 'path', p_path,
            'filename', 'Suppliers to invite ' || to_char(r.send_day, 'YYYY-MM-DD') || '.pdf')), 'customer_support')
  returning id into v_nid;
  update public.supplier_campaign_daily_list set pdf_path = p_path, pdf_error = null, notification_id = v_nid, updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'notification_id', v_nid, 'to', v_to);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_campaign_list_tick(p_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := coalesce(p_now, now()) at time zone 'Asia/Dubai'; v_at time; r public.supplier_campaign_daily_list;
  v_l jsonb; v_c jsonb; v_win text; v_gen_n int := 0; v_gen_d text; v_gen text; v_subj text; v_body text; v_blocks jsonb; v_state text; v_send text;
begin
  begin
    select coalesce(nullif(btrim(value), ''), '18:00')::time into v_at from public.app_secrets where key = 'supplier_campaign_list_local_time';
  exception when others then v_at := time '18:00'; end;
  v_at := coalesce(v_at, time '18:00');
  if v_local::time < v_at then return jsonb_build_object('due', false, 'reason', 'before ' || to_char(v_at, 'HH24:MI') || ' Dubai'); end if;

  -- ONLY ON THE EVENING BEFORE A SENDING DAY (24 Sep 2026, ledger 993): nothing goes on Friday or Saturday evening,
  -- nor on the eve of a company_calendar public holiday; Sunday evening and the last evening of a holiday do.
  if public.fn_supplier_invites_hold_reason(v_local::date + 1) is not null then
    return jsonb_build_object('due', false, 'reason', 'tomorrow is not a sending day: ' || public.fn_supplier_invites_hold_reason(v_local::date + 1));
  end if;
  select * into r from public.supplier_campaign_daily_list where list_day = v_local::date;
  if r.notification_id is not null then return jsonb_build_object('due', false, 'reason', 'already sent today', 'id', r.id); end if;
  if r.id is not null and r.attempts >= 8 then return jsonb_build_object('due', false, 'ok', false, 'reason', 'render failed 8 times today', 'error', r.pdf_error); end if;

  if r.id is null then
    v_l := public.fn_supplier_campaign_next_list(v_local::date);
    v_c := public.fn_supplier_campaign_day_counts(v_local::date);
    -- the sending window, read from the setting the sender reads (invite_warmup), so the email cannot drift from it
    select to_char(make_time(coalesce((nullif(value, '')::jsonb->>'window_start_hour')::int, 9), 0, 0), 'HH24:MI') || ' to '
           || to_char(make_time(coalesce((nullif(value, '')::jsonb->>'window_end_hour')::int, 17), 0, 0), 'HH24:MI') || ' Dubai'
      into v_win from public.app_secrets where key = 'invite_warmup';
    v_win := coalesce(v_win, '09:00 to 17:00 Dubai');
    -- NEVER SILENT (ledger 993): leads held back only because their address is on a GENERIC platform domain (a plain
    -- word a real company could own) are counted and named in this email. Same rule as fn_supplier_invite_eligible.
    select count(*), string_agg(distinct g.domain, ', ') into v_gen_n, v_gen_d
      from public.leads l join public.email_platform_domain g
        on g.generic and g.domain = split_part(lower(btrim(l.email)), '@', 2)
     where l.invite_status is null and coalesce(l.claimed, false) = false and coalesce(l.is_demo, false) = false
       and g.domain is distinct from lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(l.website), ''), l.maps_website, '')),
                                          '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi'));
    v_gen := case when v_gen_n > 0 then 'Held back, possibly a company''s own address: ' || v_gen_n
                  || ' lead(s) on a generic domain treated as a platform (' || v_gen_d
                  || '). If one is the company''s own, set its website to that domain and it becomes eligible.' end;
    v_send := to_char((v_l->>'send_day')::date, 'FMDay DD FMMonth YYYY');
    v_state := case when (v_l->>'switch_on')::boolean
                    then 'The campaign is ON: these ' || (v_l->>'planned') || ' supplier(s) will be invited on ' || v_send || ', sent from ' || v_win || ', evenly spaced.'
                    else 'The campaign is SWITCHED OFF (' || (v_l->>'held_because') || '): NOTHING will be sent on ' || v_send
                         || '. This is the list that WOULD be sent if it were on (from ' || v_win || ').' end;
    v_subj := 'Supplier campaign: ' || case when (v_l->>'switch_on')::boolean then '' else 'OFF — would invite ' end
              || (v_l->>'planned') || ' supplier(s) on ' || to_char((v_l->>'send_day')::date, 'Dy DD Mon');
    v_body := v_state || E'\n\n'
      || 'Today (' || to_char(v_local::date, 'Dy DD Mon') || '): ' || (v_c->>'sent') || ' invitation(s) sent, ' || (v_c->>'bounced') || ' bounced, '
      || (v_c->>'unsubscribed') || ' unsubscribed, ' || (v_c->>'registered') || ' supplier(s) registered.' || E'\n\n'
      || 'The attached PDF lists each supplier: company, emirate, language and email (masked). It is produced by code from the same '
      || 'selection the sender uses (cap ' || (v_l->>'cap') || ', eligible pool ' || (v_l->>'pool') || '). The morning warm-up may move the cap, '
      || 'and a supplier who registers, bounces or unsubscribes overnight drops out.'
      || coalesce(E'\n\n' || v_gen, '')
      || coalesce(E'\n\nNo sending on: ' || (select string_agg(to_char((s->>'day')::date, 'Dy DD Mon') || ' (' || (s->>'why') || ')', ', ')
                                               from jsonb_array_elements(v_l->'skipped') s), '');
    v_blocks := jsonb_build_array(
        jsonb_build_object('t', 'h2', 'text', 'Suppliers to be invited on ' || v_send),
        jsonb_build_object('t', 'p', 'text', v_state),
        jsonb_build_object('t', 'p', 'text', 'Today (' || to_char(v_local::date, 'Dy DD Mon YYYY') || '): sent ' || (v_c->>'sent') || ', bounced ' || (v_c->>'bounced')
                                              || ', unsubscribed ' || (v_c->>'unsubscribed') || ', registered ' || (v_c->>'registered') || '.'),
        jsonb_build_object('t', 'note', 'text', 'Selection: fn_supplier_invite_candidates(' || (v_l->>'planned') || '), the sender''s own; cap ' || (v_l->>'cap')
                                              || ', eligible pool ' || (v_l->>'pool') || '. Emails are masked. Prepared by customer_support, by code.'),
        jsonb_build_object('t', 'note', 'text', coalesce(v_gen, 'No lead held back on a generic platform domain.')),
        jsonb_build_object('t', 'space', 'h', 6),
        jsonb_build_object('t', 'table', 'head', jsonb_build_array('#', 'Company', 'Emirate', 'Language', 'Email'),
          'widths', jsonb_build_array(0.06, 0.44, 0.14, 0.1, 0.26),
          'rows', coalesce((select jsonb_agg(jsonb_build_array((x->>'n'), x->>'company', x->>'emirate', upper(x->>'language'), x->>'email') order by (x->>'n')::int)
                              from jsonb_array_elements(v_l->'rows') x), '[]'::jsonb)));
    insert into public.supplier_campaign_daily_list (list_day, send_day, switch_on, held_because, planned, rows, counts, subject, body, pdf_blocks)
    values (v_local::date, (v_l->>'send_day')::date, (v_l->>'switch_on')::boolean, v_l->>'held_because', (v_l->>'planned')::int,
            v_l->'rows', v_c, v_subj, v_body, v_blocks)
    returning * into r;
  end if;
  return jsonb_build_object('due', true, 'pdf_pending', true, 'id', r.id, 'subject', r.subject,
                            'report_key', 'supplier_list_' || to_char(r.send_day, 'YYYY-MM-DD'), 'pdf_blocks', r.pdf_blocks,
                            'planned', r.planned, 'switch_on', r.switch_on);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_case_review_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_from timestamptz := now() - interval '7 days';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_founder text[]; v_email jsonb; v_wa jsonb; v_chat jsonb; v_repeat jsonb; v_complaints jsonb; v_knowledge jsonb;
  v_metrics jsonb; g record; v_gap jsonb; v_filed int := 0;
  -- a machine is not a person: bounces and auto-senders are neither a support contact nor a repeat one
  v_robot text := '^(mailer-daemon|postmaster|no-?reply|do-?not-?reply|bounces?)([+.-][^@]*)?@';
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- email: the same mailbox scope as fn_support_reply_watch_tick (not the expenses mailbox, not the accountant's)
  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where m.replied_at is not null),
           'unanswered', count(*) filter (where m.replied_at is null),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60))::numeric),
           'p90_first_reply_minutes', round((percentile_cont(0.9) within group (order by extract(epoch from m.replied_at - m.created_at) / 60))::numeric))
    into v_email
    from public.inbound_messages m
   where m.created_at >= v_from and coalesce(m.from_email, '') !~* v_robot
     and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
     and public.fn_is_demo_email(m.from_email) = v_fx;

  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where w.reply is not null and coalesce(w.sent, false)),
           'unanswered', count(*) filter (where w.reply is null or not coalesce(w.sent, false)),
           'first_reply_minutes', null,
           'first_reply_minutes_note', 'not recorded: wa_messages writes the reply on the inbound''s row with no reply time')
    into v_wa
    from public.wa_messages w
   where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> ''
     and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
     and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = v_fx;

  select jsonb_build_object('questions', count(*), 'answered', count(*) filter (where g2.answered),
                            'not_answered', count(*) filter (where not g2.answered))
    into v_chat
    from public.assistant_logs g2
   where g2.created_at >= v_from and (coalesce(g2.message, '') like 'ZZ DEMO%') = v_fx;

  -- repeat contact: the same person on two or more distinct Dubai days of the week
  select jsonb_build_object('people', count(*), 'contacts', coalesce(sum(r.days), 0))
    into v_repeat
    from (select who, count(distinct d) days from (
            select 'email:' || lower(btrim(m.from_email)) who, (m.created_at at time zone 'Asia/Dubai')::date d
              from public.inbound_messages m
             where m.created_at >= v_from and coalesce(btrim(m.from_email), '') <> '' and m.from_email !~* v_robot
               and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
               and public.fn_is_demo_email(m.from_email) = v_fx
            union all
            select 'whatsapp:' || right(regexp_replace(w.wa_from, '[^0-9]', '', 'g'), 9), (w.created_at at time zone 'Asia/Dubai')::date
              from public.wa_messages w
             where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> '' and coalesce(btrim(w.wa_from), '') <> ''
               and not (right(regexp_replace(w.wa_from, '[^0-9]', '', 'g'), 9) = any (v_founder))
               and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = v_fx) c
          group by who having count(distinct d) >= 2) r;

  select jsonb_build_object('opened', count(*) filter (where t.created_at >= v_from),
                            'final_response_given', count(*) filter (where t.final_response_at >= v_from),
                            'past_respond_due', count(*) filter (where t.final_response_at is null and t.respond_due < now()))
    into v_complaints
    from public.complaint_tickets t
   where public.fn_is_demo_email(t.email) = v_fx
     and (t.created_at >= v_from or t.final_response_at >= v_from or t.final_response_at is null);

  -- UNANSWERED QUESTIONS BECOME KNOWLEDGE REQUESTS, through the one door, once.
  for g in select a.id, a.message from public.assistant_logs a
            where a.answered = false and a.gap_task_id is null and a.created_at >= v_from
              and coalesce(btrim(a.message), '') <> '' and (coalesce(a.message, '') like 'ZZ DEMO%') = v_fx
            order by a.id for update of a skip locked loop
    v_gap := public.fn_support_knowledge_gap(g.message, 'weekly_case_review', 'website_widget');
    if coalesce((v_gap->>'ok')::boolean, false) and v_gap->>'task_id' is not null then
      update public.assistant_logs set gap_task_id = (v_gap->>'task_id')::bigint where id = g.id;
      v_filed := v_filed + 1;
    end if;
  end loop;

  select jsonb_build_object('opened_this_week', count(*) filter (where k.first_asked_at >= v_from),
                            'asked_again_this_week', count(*) filter (where k.first_asked_at < v_from and k.last_asked_at >= v_from),
                            'still_open', count(*) filter (where k.status = 'open'),
                            'filed_by_this_review', v_filed)
    into v_knowledge
    from public.sales_knowledge_gap k
   where (k.question like 'ZZ DEMO%') = v_fx and (k.last_asked_at >= v_from or k.status = 'open');

  v_metrics := jsonb_build_object('from', v_from, 'to', now(), 'email', v_email, 'whatsapp', v_wa, 'chat', v_chat,
                                  'repeat_contacts', v_repeat, 'complaints', v_complaints, 'knowledge', v_knowledge);
  -- a fixture run never overwrites the real week's row
  if not v_fx or not exists (select 1 from public.customer_support_case_review where week_ending = v_week and not fixture) then
    insert into public.customer_support_case_review (week_ending, metrics, knowledge_filed, fixture)
    values (v_week, v_metrics, v_filed, v_fx)
    on conflict (week_ending) do update
      set metrics = excluded.metrics, knowledge_filed = customer_support_case_review.knowledge_filed + excluded.knowledge_filed,
          fixture = excluded.fixture, reviewed_at = now();
  end if;
  return jsonb_build_object('week_ending', v_week, 'knowledge_filed', v_filed, 'fixture', v_fx) || v_metrics;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_concierge_confirm(p_inquiry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.inquiries; c public.customers; g jsonb; m jsonb; v_kind text; v_sent jsonb;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('sent', false, 'reason', 'no such request'); end if;
  -- A split's per-trade child is part of its parent's request: the customer hears about the request once.
  if i.parent_inquiry_id is not null then return jsonb_build_object('sent', false, 'reason', 'a per-trade part of a combined request'); end if;
  select * into c from public.customers where id = i.customer_id;
  if not found or coalesce(c.banned, false) then return jsonb_build_object('sent', false, 'reason', 'no customer to write to'); end if;
  g := public.fn_customer_concierge(i.customer_id, i.category, null, i.id);
  v_kind := case when coalesce((g->>'first_inquiry')::boolean, false) then 'first_request'
                 when coalesce((g#>>'{held,finding_suppliers}')::boolean, false) then 'finding_suppliers'
                 when coalesce((g#>>'{held,held}')::boolean, false) then 'held_for_specs' end;
  -- The first confirmation already carried the held details or the search for suppliers: one message per request.
  if v_kind in ('held_for_specs', 'finding_suppliers') and exists (select 1 from public.customer_support_duty_message d
       where d.stage = 'concierge.first_request' and d.subject_key = i.id::text) then v_kind := null; end if;
  if v_kind is null then return jsonb_build_object('sent', false, 'reason', 'not a first request, held or waiting for suppliers', 'concierge', g); end if;
  m := public.fn_customer_concierge_message(i.id, v_kind);
  v_sent := public.fn_customer_support_duty_send('concierge.' || v_kind, i.id::text, 'customer', c.email,
    m->>'lang', m->>'subject', m->>'body', c.id, null, i.id);
  return v_sent || jsonb_build_object('stage', 'concierge.' || v_kind, 'concierge', g);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_concierge_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_first int := 0; v_held int := 0; v_find int := 0;
begin
  -- ponytail: a 3-day window; a request older than that has had the activation duty's no-quote message (day 5)
  -- and a guide arriving later would read as noise. Widen it if the tick is ever down for longer.
  for r in select i.id from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.parent_inquiry_id is null and i.created_at > now() - interval '3 days'
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.customer_support_duty_message d
                               where d.stage in ('concierge.first_request', 'concierge.held_for_specs', 'concierge.finding_suppliers')
                                 and d.subject_key = i.id::text)
            order by i.created_at limit 200 loop
    v := public.fn_customer_support_concierge_confirm(r.id);
    if v->>'stage' = 'concierge.first_request' then v_first := v_first + 1;
    elsif v->>'stage' = 'concierge.held_for_specs' then v_held := v_held + 1;
    elsif v->>'stage' = 'concierge.finding_suppliers' then v_find := v_find + 1; end if;
  end loop;
  return jsonb_build_object('first_request', v_first, 'held_for_specs', v_held, 'finding_suppliers', v_find);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_delivery_watch(p_request_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  q record; n public.notifications; tx public.transactions; sup record; v_since timestamptz;
  v_reply jsonb; v_result text; v_evidence jsonb; v_retries int; v_nid bigint; v_done int := 0; v_waiting int := 0; v_retried int := 0;
  v_overdue int := 0; v_rep jsonb; v_failed int := 0;
begin
  for q in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status in ('done', 'failed')
       and a.detail->>'type' = 'delivery.request'
       and (a.detail->>'result_handoff_id') is null
       and (p_request_id is null or a.id = p_request_id)
     order by a.id
  loop
    v_nid := coalesce((q.detail->>'retry_notification_id')::bigint, (q.evidence->>'notification_id')::bigint);
    n := null;
    select * into n from public.notifications where id = v_nid;

    -- NOT TERMINAL IN TIME IS A FINDING, whatever else is true of the request.
    if n.id is not null and n.status in ('pending', 'queued') and n.created_at < now() - interval '24 hours'
       and (q.detail->>'overdue_report_id') is null then
      v_rep := public.fn_support_report_to_ceo(
        'delivery_overdue:' || q.id, 'elevated',
        'A ' || coalesce(q.detail->>'msg_type', 'notice') || ' for the ' || coalesce(n.to_role, 'recipient') || ' has not left the outbox in 24 hours',
        jsonb_build_object('request_id', q.id, 'asked_by', q.detail->>'from', 'notification_id', n.id, 'status', n.status,
                           'queued_at', n.created_at, 'attempts', n.attempts, 'last_error', n.last_error),
        jsonb_build_array('queued by customer_support', 'watched every heartbeat since'),
        'Find why the outbox is not draining this row (dispatcher down, sending disabled, cap) and get it out, or tell the asking seat it will not go.',
        'agent_actions#' || q.id);
      update public.agent_actions set detail = detail || jsonb_build_object('overdue_report_id', v_rep->'report_id') where id = q.id;
      v_overdue := v_overdue + 1;
    end if;

    if q.status = 'done' and (q.detail->>'watch_until') is not null then
      -- ── the watched path, carried over unchanged ──
      select * into tx from public.transactions where id = (q.detail->>'transaction_id')::uuid;
      select l.id, lower(coalesce(l.claimed_by, l.email)) as email,
             regexp_replace(coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') as phone
        into sup from public.leads l where l.id = (q.detail->>'supplier_id')::bigint;
      v_since := coalesce(tx.revealed_at, q.created_at);
      v_retries := coalesce((q.detail->>'retries')::int, 0);

      -- ANY CHANNEL, EVERY TIME. The first thing that came back wins.
      select jsonb_build_object('channel', ch, 'at', at, 'ref', ref) into v_reply from (
        select 'portal' ch, m.created_at at, 'messages#' || m.id ref from public.messages m
         where tx.id is not null and m.inquiry_id = tx.inquiry_id and m.supplier_id = tx.supplier_id
           and m.sender = 'supplier' and coalesce(m.blocked, false) = false and m.created_at > v_since
        union all
        select 'supplier_ack', tx.supplier_ack_at, 'transactions.supplier_ack_at' where tx.supplier_ack_at > v_since
        union all
        select coalesce(w.response_channel, 'recorded'), w.first_response_at, coalesce(w.response_ref, 'supplier_response_watch#' || w.id)
          from public.supplier_response_watch w where tx.id is not null and w.transaction_id = tx.id and w.first_response_at > v_since
        union all
        select 'email', im.created_at, 'inbound_messages#' || im.id from public.inbound_messages im
         where sup.email is not null and lower(im.from_email) = sup.email and im.created_at > v_since
        union all
        select 'whatsapp', wm.created_at, 'wa_messages#' || wm.id from public.wa_messages wm
         where length(coalesce(sup.phone, '')) >= 8 and regexp_replace(coalesce(wm.wa_from, ''), '[^0-9]', '', 'g') = sup.phone
           and wm.created_at > v_since
        order by 2 limit 1) z;

      if v_reply is not null and q.detail->>'recipient_role' = 'supplier' then
        v_result := 'proof_of_response';
        v_evidence := jsonb_build_object('reply', v_reply);
      elsif n.id is null or n.status in ('failed', 'bounced', 'error') then
        if v_retries < 1 and n.id is not null then
          perform set_config('app.qd_delivery_tracked', 'on', true);   -- the retry is tracked by this request (retry_notification_id)
          insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
          values (n.type, n.kind, n.to_email, n.cc_emails, n.to_role, n.lead_id, n.inquiry_id, n.quote_id, 'email', n.subject, n.body, 'queued', n.requested_by)
          returning id into v_nid;
          perform set_config('app.qd_delivery_tracked', 'off', true);
          update public.agent_actions
             set detail = detail || jsonb_build_object('retries', v_retries + 1, 'retry_notification_id', v_nid,
                                                       'first_failure', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error))
           where id = q.id;
          perform public.fn_seat_handoff_event(q.id, 'retried');
          v_retried := v_retried + 1;
          continue;
        end if;
        v_result := 'no_response_confirmation';
        v_evidence := jsonb_build_object('delivered', false, 'retries', v_retries,
          'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error),
          'first_failure', q.detail->'first_failure');
      elsif now() >= (q.detail->>'watch_until')::timestamptz then
        v_result := 'no_response_confirmation';
        v_evidence := jsonb_build_object('delivered', n.status = 'sent' or n.sent_at is not null,
          'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'sent_at', n.sent_at,
                                         'provider_message_id', n.provider_message_id, 'attempts', n.attempts),
          'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status, 'sent_at', w.sent_at,
                                                                    'provider_message_id', w.provider_message_id)), '[]'::jsonb)
                         from public.notifications w
                        where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)),
          'window_closed_at', q.detail->'watch_until',
          'channels_checked', jsonb_build_array('portal', 'supplier_ack', 'recorded_reply', 'email', 'whatsapp'));
      else
        v_waiting := v_waiting + 1;
        continue;
      end if;
    else
      -- ── every other request: one result when the send is terminal ──
      v_evidence := jsonb_build_object('notification', case when n.id is null then null else jsonb_build_object(
                      'id', n.id, 'status', n.status, 'channel', n.channel, 'to_role', n.to_role, 'sent_at', n.sent_at,
                      'provider_message_id', n.provider_message_id, 'attempts', n.attempts, 'last_error', n.last_error,
                      -- what Twilio reported, and its error in plain words (null for email)
                      'provider_status', n.provider_status, 'provider_error_code', n.provider_error_code,
                      'provider_error_explained', public.fn_twilio_error_in_plain_words(n.provider_error_code)) end,
                    'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status,
                                                   'provider_message_id', w.provider_message_id, 'provider_status', w.provider_status,
                                                   'provider_error_code', w.provider_error_code)), '[]'::jsonb)
                                   from public.notifications w
                                  where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)));
      if q.status = 'failed' then
        v_result := 'not_queued';
        v_evidence := v_evidence || jsonb_build_object('error', q.detail->>'error');
      elsif coalesce((q.evidence->>'stubbed')::boolean, false) then
        v_result := 'stubbed';
      elsif n.id is null and q.evidence ? 'notify' then
        v_result := 'routed';
        v_evidence := v_evidence || jsonb_build_object('notify', q.evidence->'notify');
      -- 22 SEP 2026 (it_engineer, UNSOLVED-06) — "NOTHING WAS QUEUED" WAS THREE DIFFERENT THINGS.
      -- MEASURED: support_ceo_report 3075, 3076, 3084 and 3085 each read 'A supplier_invite for the supplier
      -- did not arrive (not_sent)' with reason 'nothing was queued'. Their requests (agent_actions 42578,
      -- 42579, 42595, 42596) each carry evidence.queued = true and evidence.notification_id 36988/36989/
      -- 37002/37003, and NONE of those notification rows exists any more: every one addressed a
      -- zz-demo-supplier-invite-…@example.invalid fixture and the demo hygiene sweep deleted them between
      -- being queued at 19:11-19:15Z and the watch tick at 19:30Z on 21 Sep. So support DID queue the
      -- message; its record was removed afterwards. (The 22 Sep audit read these as invitations held by
      -- app_secrets.supplier_outreach_golive=false. They are not: the hold path
      -- (the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day.sql) writes an
      -- invite_schedule row with status 'pending' and a supplier_invites agent_run, and asks for no
      -- delivery at all — so a held invitation never reaches this watch.)
      -- The three cases now answer differently, and only the first is a fault:
      --   nothing was ever queued and nothing explains it  -> 'not_sent'  (escalates, as before)
      --   the campaign is held by the founder's own switch  -> 'held'     (recorded, never escalated)
      --   the row it queued has since been deleted         -> 'record_removed'
      elsif n.id is null and coalesce(q.detail->>'msg_type', '') like '%invite%'
            and not public.fn_supplier_outreach_golive() then
        v_result := 'held';
        v_evidence := v_evidence || jsonb_build_object('reason',
          'the supplier campaign is held: app_secrets.supplier_outreach_golive is false, so no invitation is sent. This is the founder''s switch, not a delivery failure.');
      elsif n.id is null and coalesce((q.evidence->>'notification_id'), '') <> '' then
        v_result := 'record_removed';
        v_evidence := v_evidence || jsonb_build_object('reason',
          'the notification this request queued (id ' || (q.evidence->>'notification_id')
          || ') no longer exists, so its delivery cannot be read. A queued message whose row was deleted afterwards - the demo hygiene sweep does this to fixture rows - is not a message that was never sent.');
      elsif n.id is null then
        v_result := 'not_sent';
        v_evidence := v_evidence || jsonb_build_object('reason', coalesce(q.evidence->>'reason', 'nothing was queued'));
      elsif n.status = 'sent' and n.channel in ('whatsapp', 'sms') and coalesce(btrim(n.provider_message_id), '') <> '' then
        -- 22 SEP 2026: a Twilio SID proves only that Twilio ACCEPTED the message. Meta or the carrier can
        -- still refuse it, and that arrives later as a status report (wa_status). So a WhatsApp or SMS
        -- waits for delivered/read; a failure has already turned the row 'failed' (below); and a message
        -- with no final report 24 hours on is returned as unconfirmed rather than claimed as delivered.
        if n.provider_status in ('delivered', 'read') then
          v_result := 'delivered';
        elsif n.sent_at < now() - interval '24 hours' then
          v_result := 'sent_unconfirmed';
          v_evidence := v_evidence || jsonb_build_object('reason',
            'Twilio accepted it but reported no delivery within 24 hours: neither its status callback nor the backstop poll gave a final status');
        else
          v_waiting := v_waiting + 1;
          continue;
        end if;
      elsif n.status = 'sent' then
        v_result := case when coalesce(btrim(n.provider_message_id), '') <> '' then 'delivered' else 'sent_unconfirmed' end;
      elsif n.status in ('failed', 'bounced', 'error') then v_result := 'failed';
      elsif n.status in ('held', 'suppressed', 'skipped', 'cancelled') then v_result := n.status;
      elsif n.status = 'digest' then v_result := 'digested';
      else
        v_waiting := v_waiting + 1;
        continue;
      end if;
    end if;

    -- ONE RESULT, TO WHOEVER ASKED. A result the handoff register refuses must not stop the rest of the
    -- queue: it is recorded on the request and in the stream, and counted.
    -- The result is acted on at once, and the asking seat's close writes THIS request row (its loop,
    -- closed_by, the retry). So the handoff is sent first and its id written after, in a statement of
    -- its own: calling fn_seat_handoff inside the UPDATE of the same row failed with "tuple to be updated
    -- was already modified by an operation triggered by the current command" (measured 14 Sep 2026).
    begin
      update public.agent_actions set detail = detail || jsonb_build_object('result', v_result) where id = q.id;
      v_nid := public.fn_seat_handoff('customer_support', q.detail->>'from', 'delivery.result', 'agent_actions', q.id::text,
                 jsonb_build_object('request_id', q.id, 'result', v_result, 'evidence', v_evidence,
                                    'msg_type', q.detail->>'msg_type', 'recipient_role', q.detail->>'recipient_role',
                                    'retry_of', q.detail->'retry_of',
                                    'step', q.detail->>'step', 'refund_id', q.detail->>'refund_id',
                                    'transaction_id', q.detail->>'transaction_id', 'supplier_id', q.detail->>'supplier_id',
                                    'remediation_id', q.detail->>'remediation_id'));
      update public.agent_actions set detail = detail || jsonb_build_object('result_handoff_id', v_nid) where id = q.id;
      v_done := v_done + 1;
    exception when others then
      update public.agent_actions set detail = detail || jsonb_build_object('result_error', left(sqlerrm, 500)) where id = q.id;
      perform public.fn_seat_handoff_event(q.id, 'result_failed');
      v_failed := v_failed + 1;
    end;
  end loop;
  return jsonb_build_object('results_returned', v_done, 'still_watching', v_waiting, 'retried', v_retried,
                            'overdue_raised', v_overdue, 'results_failed', v_failed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_dispute_consider(p_transaction_id uuid, p_party text, p_message text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; v_demo boolean;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  if p_party not in ('customer', 'supplier') then raise exception 'the party is the customer or the supplier, not %', p_party; end if;
  select coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email) into v_demo from public.customers c where c.id = t.customer_id;
  return public.fn_seat_duty_reason('customer_support', 'customer_support.dispute_intake',
    case when v_demo then 'ZZ DEMO ' else '' end
    || 'A party to a revealed job wrote to customer support. Does the message raise a dispute with the other party that needs a case, or is it something support answers directly?',
    jsonb_build_array(
      jsonb_build_object('id', 'dispute', 'meaning', 'the party complains about the other party''s conduct or work on this job and wants it put right'),
      jsonb_build_object('id', 'not_dispute', 'meaning', 'a question, feedback or a request support can answer without involving the other party')),
    jsonb_build_object('party', p_party, 'message', left(p_message, 4000), 'revealed_at', t.revealed_at,
                       'transaction_id', t.id, 'inquiry_id', t.inquiry_id),
    jsonb_build_object('transaction_id', t.id, 'party', p_party, 'statement', left(p_message, 4000)),
    'dispute_intake:' || t.id || ':' || md5(p_party || coalesce(p_message, '')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_dispute_evidence(p_id bigint, p_party text, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_party not in ('customer', 'supplier') then raise exception 'the party is the customer or the supplier, not %', p_party; end if;
  update public.post_reveal_dispute
     set customer_evidence = case when p_party = 'customer' then coalesce(customer_evidence, '{}'::jsonb) || jsonb_build_object('reply', p_evidence, 'at', now()) else customer_evidence end,
         supplier_evidence = case when p_party = 'supplier' then coalesce(supplier_evidence, '{}'::jsonb) || jsonb_build_object('reply', p_evidence, 'at', now()) else supplier_evidence end
   where id = p_id and stage = 'evidence';
  if not found then raise exception 'dispute % is not taking evidence', p_id; end if;
  return jsonb_build_object('dispute_id', p_id, 'recorded', p_party);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_dispute_open(p_transaction_id uuid, p_raised_by text, p_statement text, p_intake_question_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; d public.post_reveal_dispute; c record; s record; v_ref text; v_rfq text; v_due text;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  select * into d from public.post_reveal_dispute where transaction_id = t.id and stage <> 'decided';
  if found then return jsonb_build_object('dispute_id', d.id, 'opened', false, 'reason', 'a case is already open on this job'); end if;
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement,
                                          evidence_due, intake_question_id)
  values (t.id, t.inquiry_id, t.customer_id, t.supplier_id, p_raised_by, left(p_statement, 4000),
          public.fn_add_working_days(now(), 5), p_intake_question_id)
  returning * into d;
  if p_raised_by = 'customer' then d.customer_evidence := jsonb_build_object('statement', d.statement, 'at', now());
  else d.supplier_evidence := jsonb_build_object('statement', d.statement, 'at', now()); end if;
  update public.post_reveal_dispute set customer_evidence = d.customer_evidence, supplier_evidence = d.supplier_evidence where id = d.id;

  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');
  select coalesce(i.rfq_no::text, left(i.id::text, 8)) into v_rfq from public.inquiries i where i.id = t.inquiry_id;
  v_due := to_char(d.evidence_due at time zone 'Asia/Dubai', 'DD/MM/YYYY HH24:MI');
  select c2.email, c2.locale into c from public.customers c2 where c2.id = t.customer_id;
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = t.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.opened', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'فُتحت القضية ' || v_ref || ' بشأن مشروعكم على QuotesDone'
           else 'Dispute ' || v_ref || ' opened on your QuotesDone job' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'فُتحت القضية ' || v_ref || ' بشأن المشروع المرتبط بالطلب رقم ' || coalesce(v_rfq, '') || '، ولن يُتخذ أي قرار قبل الاستماع إلى الطرفين. '
        || 'نرجو الرد على هذه الرسالة بروايتكم لما حدث، مع ما يدعمها من مستندات أو صور أو مراسلات، في موعد أقصاه ' || v_due || ' بتوقيت دبي. '
        || 'وإن لم يصلنا شيء حتى ذلك الموعد، فستُراجَع القضية بناءً على ما لدينا.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'Dispute ' || v_ref || ' has been opened about the job for request ' || coalesce(v_rfq, '') || '. Nothing will be decided before both sides are heard. '
        || 'Please reply to this e-mail with your account of what happened and any documents, photos or messages that support it by ' || v_due || ' Dubai time. '
        || 'If nothing arrives by then, the case is reviewed on what we already have.' end,
      case when role = 'customer' then t.customer_id end, case when role = 'supplier' then t.supplier_id end, t.inquiry_id)
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(t.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'opened', true, 'evidence_due', d.evidence_due);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_duty_send(p_stage text, p_key text, p_to_role text, p_email text, p_lang text, p_subject text, p_body text, p_customer uuid DEFAULT NULL::uuid, p_lead bigint DEFAULT NULL::bigint, p_inquiry uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_to text := lower(nullif(btrim(coalesce(p_email, '')), '')); v_ok jsonb; v_res jsonb; v_h bigint;
begin
  insert into public.customer_support_duty_message (stage, subject_key, customer_id, lead_id, to_email)
  values (p_stage, p_key, p_customer, p_lead, v_to)
  on conflict (stage, subject_key) do nothing;
  if not found then return jsonb_build_object('sent', false, 'reason', 'already written at this stage'); end if;
  v_ok := public.fn_email_sendable(v_to);
  if not coalesce((v_ok->>'ok')::boolean, false) then
    update public.customer_support_duty_message set outcome = 'not_sendable: ' || (v_ok->>'reason')
     where stage = p_stage and subject_key = p_key;
    return jsonb_build_object('sent', false, 'reason', v_ok->>'reason');
  end if;
  v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'duty_' || replace(p_stage, '.', '_'), 'requested_by', 'customer_support', 'channel', 'email',
    'to_email', v_to, 'to_role', p_to_role, 'lead_id', p_lead, 'inquiry_id', p_inquiry,
    'lang', case when p_lang = 'ar' then 'ar' else 'en' end,
    'dedupe_key', 'duty:' || p_stage || ':' || p_key, 'subject', p_subject, 'body', p_body)));
  v_h := (v_res->0->>'handoff_id')::bigint;
  update public.customer_support_duty_message set outcome = 'queued', handoff_id = v_h
   where stage = p_stage and subject_key = p_key;
  return jsonb_build_object('sent', true, 'handoff_id', v_h);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_followup_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb; m jsonb;
  v_stage text; v_lang text; v_tok uuid; v_seen int := 0; v_sent int := 0;
begin
  for r in select t.id as tx, t.inquiry_id, t.revealed_at, c.id as cid, c.full_name, c.email, c.locale as customer_locale,
                  l.company_name, i.rfq_no, coalesce(i.category, i.trades[1]) as trade,
                  case when t.revealed_at <= now() - interval '14 days' then 'day_fourteen' else 'day_three' end as stage
             from public.transactions t
             join public.customers c on c.id = t.customer_id
             left join public.leads l on l.id = t.supplier_id
             left join public.inquiries i on i.id = t.inquiry_id
            where t.revealed_at is not null
              and ((t.revealed_at <= now() - interval '3 days' and t.revealed_at > now() - interval '7 days')
                or (t.revealed_at <= now() - interval '14 days' and t.revealed_at > now() - interval '30 days'))
              -- a refund or a dispute is its own conversation. refund_status is 'window_open' on every reveal
              -- (trg_reveal_window), so a refund in play is named, not "any status".
              and t.refund_requested_at is null
              and coalesce(t.refund_status, '') not in ('requested', 'pending', 'approved', 'processing', 'refunded', 'succeeded')
              and not exists (select 1 from public.post_reveal_dispute d where d.transaction_id = t.id)
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              -- a definite answer (hired or not) closes the question; "not yet" leaves day 14 to ask again
              and not exists (select 1 from public.customer_followup f where f.transaction_id = t.id and f.hired in ('yes', 'no'))
              and not exists (select 1 from public.customer_followup f where f.transaction_id = t.id
                                 and f.stage = case when t.revealed_at <= now() - interval '14 days' then 'day_fourteen' else 'day_three' end)
            order by t.revealed_at limit 200 loop
    v_seen := v_seen + 1;
    v_stage := r.stage;
    -- the CUSTOMER's language (their request's, else their registered one); the lead joined above only names the
    -- supplier in the copy, and nothing here is ever sent to a supplier
    v_lang := public.fn_customer_message_lang(r.inquiry_id, r.customer_locale);
    v_tok := gen_random_uuid();
    m := public.fn_customer_followup_copy(v_stage, v_lang, r.full_name, r.company_name, r.rfq_no,
           public.fn_trade_label(r.trade, v_lang), 'https://quotesdone.ae/u/followup?t=' || v_tok);
    v := public.fn_customer_support_duty_send('followup.' || v_stage, r.tx::text, 'customer', r.email, v_lang,
           m->>'subject', m->>'body', r.cid, null, r.inquiry_id);
    -- a question counts as asked only when it went out; a suppressed address is recorded by duty_send, not here
    if coalesce((v->>'sent')::boolean, false) then
      insert into public.customer_followup (transaction_id, stage, token, lang) values (r.tx, v_stage, v_tok, v_lang)
      on conflict (transaction_id, stage) do nothing;
      v_sent := v_sent + 1;
    end if;
  end loop;
  return jsonb_build_object('due', v_seen, 'asked', v_sent);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_held_money_message(p_hold_id bigint, p_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h public.money_move_hold; c public.customers; v_type text := p_type; v_ar boolean; v_name text;
  v_rfq text; v_inq uuid; v_subj text; v_body text;
begin
  if p_type not in ('fraud.money_held', 'fraud.money_released') then raise exception 'no money-hold message of type %', p_type; end if;
  select * into h from public.money_move_hold where id = p_hold_id;
  if not found then return jsonb_build_object('not_sent', 'the hold no longer exists'); end if;
  select * into c from public.customers where id = h.customer_id;
  if not found then return jsonb_build_object('not_sent', 'no customer waits on this move'); end if;
  -- The request the customer knows: the quote's request for a reveal, the refund's request for a refund.
  -- A refund row may carry no inquiry_id: its transaction's request is the one the customer knows, so the
  -- reference is never blank (re-review of #1110).
  if h.move = 'reveal' then
    select q.inquiry_id into v_inq from public.quotes q where q.id::text = h.ref;
  else
    select coalesce(r.inquiry_id, t.inquiry_id) into v_inq
      from public.refunds r left join public.transactions t on t.id = r.transaction_id where r.id::text = h.ref;
  end if;
  if v_inq is not null then v_rfq := 'QD-' || public.fn_job_no(v_inq); end if;
  -- The request's own language first (founder, 28 Sep 2026: every message about a request is in the language it
  -- was made in), the registered one otherwise.
  v_ar := coalesce(public.fn_inquiry_locale(v_inq), c.locale) = 'ar';
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);

  if v_type = 'fraud.money_held' and h.move = 'reveal' then
    v_subj := case when v_ar then 'طلب الكشف قيد المراجعة' else 'Your reveal is being checked' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'قبل كشف أي مورّد نُجري تحققًا اعتياديًا على الحسابات المعنية، ويحتاج أحد هذه التحققات إلى مراجعة من أحد موظفينا، لذا أوقفنا مؤقتًا كشف المورّد على الطلب '
        || coalesce(v_rfq, '') || '، ولم يُخصم منكم أي مبلغ.' || chr(10) || chr(10)
        || 'لا يلزمكم أي إجراء. سنراسلكم فور اكتمال المراجعة، وعادةً خلال يومي عمل، وبعدها يمكنكم كشف المورّد كالمعتاد.' || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Before a supplier is revealed we run a routine check on the accounts involved, and one of those checks needs a person to look at it. The reveal on request '
        || coalesce(v_rfq, '') || ' is paused until then, and you have not been charged.' || chr(10) || chr(10)
        || 'Nothing is needed from you. We will write as soon as the check is complete, normally within two working days, and you can then reveal the supplier as usual.' || chr(10) || chr(10)
        || 'If you have a question, reply to this e-mail.' end;
  elsif v_type = 'fraud.money_held' then
    v_subj := case when v_ar then 'طلب الاسترداد قيد المراجعة' else 'Your refund is being checked' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'قبل صرف أي مبلغ مسترد نُجري تحققًا اعتياديًا على الحسابات المعنية، ويحتاج أحد هذه التحققات إلى مراجعة من أحد موظفينا، لذا أوقفنا مؤقتًا صرف المبلغ المسترد على الطلب '
        || coalesce(v_rfq, '') || ' حتى تكتمل المراجعة.' || chr(10) || chr(10)
        || 'لا يلزمكم أي إجراء. سنراسلكم فور اكتمال المراجعة، وعادةً خلال يومي عمل.' || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Before a refund is paid we run a routine check on the accounts involved, and one of those checks needs a person to look at it. The refund on request '
        || coalesce(v_rfq, '') || ' is paused until the check is complete.' || chr(10) || chr(10)
        || 'Nothing is needed from you. We will write as soon as the check is complete, normally within two working days.' || chr(10) || chr(10)
        || 'If you have a question, reply to this e-mail.' end;
  elsif h.move = 'reveal' then
    v_subj := case when v_ar then 'يمكنكم الآن كشف المورّد' else 'You can now reveal the supplier' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'اكتملت المراجعة، ويمكنكم الآن كشف المورّد على الطلب ' || coalesce(v_rfq, '') || ' من حسابكم: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'شكرًا لصبركم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The check is complete. You can now reveal the supplier on request ' || coalesce(v_rfq, '') || ' from your account: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'Thank you for your patience.' end;
  else
    v_subj := case when v_ar then 'اكتملت مراجعة طلب الاسترداد' else 'The check on your refund is complete' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'اكتملت المراجعة، ويواصل طلب الاسترداد على الطلب ' || coalesce(v_rfq, '') || ' مساره المعتاد، وسنؤكد لكم فور صرف المبلغ.' || chr(10) || chr(10)
        || 'شكرًا لصبركم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The check is complete, and the refund on request ' || coalesce(v_rfq, '') || ' continues through the usual process. We will confirm as soon as it is paid.' || chr(10) || chr(10)
        || 'Thank you for your patience.' end;
  end if;

  return jsonb_build_object('lang', case when v_ar then 'ar' else 'en' end, 'subject', v_subj, 'body', v_body, 'ref', v_rfq,
                            'inquiry_id', v_inq, 'customer_id', c.id, 'email', c.email, 'hold_id', h.id, 'move', h.move);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_monthly_self_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  -- the last COMPLETE Dubai calendar month
  v_month date := (date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date;
  v_from timestamptz := v_month::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (v_month + interval '1 month')::timestamp at time zone 'Asia/Dubai';
  v_m jsonb; v_below text[] := '{}';
begin
  select jsonb_build_object(
           'month', v_month, 'replies', count(*),
           'readability_avg', round(avg(r.score), 1), 'tone_avg', round(avg(r.tone), 1),
           'first_time_pass_share', round(avg(case when r.path = 'reasoned' and not r.rewritten and r.score = 100 and r.issues = '{}' then 1 else 0 end)
                                          filter (where r.path = 'reasoned' or r.reason like 'readability:%'), 3),
           'rewritten', count(*) filter (where r.rewritten),
           'canned_because_unreadable', count(*) filter (where r.reason like 'readability:%'),
           'canned_because_no_model', count(*) filter (where r.path = 'fallback' and coalesce(r.reason, '') not like 'readability:%'),
           'by_channel', (select coalesce(jsonb_object_agg(c.channel, jsonb_build_object('replies', c.n, 'readability_avg', c.s, 'tone_avg', c.t)), '{}')
                            from (select channel, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from public.support_reply_readability
                                   where created_at >= v_from and created_at < v_to and demo = v_fx group by channel) c),
           'by_language', (select coalesce(jsonb_object_agg(l.lang, jsonb_build_object('replies', l.n, 'readability_avg', l.s, 'tone_avg', l.t)), '{}')
                             from (select lang, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from public.support_reply_readability
                                    where created_at >= v_from and created_at < v_to and demo = v_fx group by lang) l),
           'top_issues', (select coalesce(jsonb_agg(jsonb_build_object('issue', i.k, 'count', i.n) order by i.n desc), '[]')
                            from (select split_part(x, ':', 1) k, count(*) n
                                    from public.support_reply_readability, unnest(issues) x
                                   where created_at >= v_from and created_at < v_to and demo = v_fx
                                   group by 1 order by 2 desc limit 5) i))
    into v_m
    from public.support_reply_readability r
   where r.created_at >= v_from and r.created_at < v_to and r.demo = v_fx;

  if (v_m->>'replies')::int > 0 then
    if (v_m->>'readability_avg')::numeric < 90 then v_below := array_append(v_below, 'readability_avg<90'); end if;
    if (v_m->>'tone_avg')::numeric < 90 then v_below := array_append(v_below, 'tone_avg<90'); end if;
    if (v_m->>'first_time_pass_share')::numeric < 0.8 then v_below := array_append(v_below, 'first_time_pass<80%'); end if;
  end if;

  -- a fixture run never overwrites the real month's row
  if not v_fx or not exists (select 1 from public.customer_support_monthly_review where month = v_month and not fixture) then
    insert into public.customer_support_monthly_review (month, metrics, below_target, fixture)
    values (v_month, v_m, v_below, v_fx)
    on conflict (month) do update set metrics = excluded.metrics, below_target = excluded.below_target,
                                      fixture = excluded.fixture, reviewed_at = now();
  end if;
  return v_m || jsonb_build_object('below_target', to_jsonb(v_below), 'fixture', v_fx);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_reminds_supplier_of_portfolio(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; l public.leads; v_gaps jsonb; v_to text; v_fix boolean; v_why text; m jsonb; v jsonb;
  d public.agent_actions; n public.notifications; v_wa_id bigint; v_tmpl text; v_wa jsonb; v_nid bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'supplier.portfolio_incomplete';
  if not found then raise exception 'fn_customer_support_reminds_supplier_of_portfolio: % is not a supplier.portfolio_incomplete handoff', p_id; end if;
  select * into l from public.leads where id = (a.detail->>'lead_id')::bigint;
  if not found then return jsonb_build_object('not_sent', 'the supplier no longer exists'); end if;
  if not (coalesce(l.verified, false) and l.approval_status = 'approved') or coalesce(l.banned, false) then
    return jsonb_build_object('not_sent', 'the supplier is no longer verified');
  end if;

  -- SEND TIME, NOT DETECTION TIME: the portfolio is read again here. Whatever the sales engineer saw.
  v_gaps := public.fn_supplier_portfolio_gaps(l.id);
  if jsonb_array_length(v_gaps) = 0 then
    return jsonb_build_object('not_sent', 'the portfolio was complete when customer_support came to send',
                              'gaps_at_detection', a.detail->'gaps_at_detection');
  end if;

  -- The portal account's own address. leads.email is a directory listing's address, not necessarily
  -- the person who signed in, and this message is about his portal account.
  v_to := lower(btrim(coalesce(l.claimed_by, '')));
  if v_to = '' then return jsonb_build_object('not_sent', 'the supplier has no portal account address (claimed_by)', 'gaps', v_gaps); end if;
  v_fix := public.fn_seat_clock_lead_is_fixture(l);
  v_why := public.fn_seat_clock_refusal(v_fix, v_to, 'supplier_portfolio_incomplete');
  if v_why is not null then return jsonb_build_object('not_sent', v_why, 'gaps', v_gaps); end if;

  m := public.fn_supplier_portfolio_reminder_compose(l, v_gaps);
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'supplier_portfolio_incomplete', 'requested_by', 'customer_support', 'channel', 'email',
    'to_email', v_to, 'to_role', 'supplier', 'lead_id', l.id, 'lang', m->>'lang',
    'subject', m->>'subject', 'body', m->>'body',
    'dedupe_key', 'supplier_portfolio_reminder:' || (a.detail->>'subject_id'))));
  if coalesce(v->0->>'status', '') = 'failed' then
    return jsonb_build_object('not_sent', 'the delivery request failed: ' || coalesce(v->0->>'error', 'no error recorded'), 'gaps', v_gaps);
  end if;

  select * into d from public.agent_actions where id = (v->0->>'handoff_id')::bigint;
  v_nid := (d.evidence->>'notification_id')::bigint;
  v_wa_id := (d.evidence->'whatsapp_ids'->>0)::bigint;

  -- THE WHATSAPP LEG, AS IT IS AND NOT AS HOPED. The twin is attempted for app_secrets.wa_stale_hours
  -- (24): send_whatsapp checks staleness before the template, so while supplier_account_notice is not
  -- approved the row expires to 'held' after a day and never sends. The row says so from the start.
  if v_wa_id is null then
    v_wa := jsonb_build_object('state', 'no_whatsapp', 'reason',
      case when l.whatsapp_opt = 'none' then 'the supplier chose not to receive WhatsApp messages'
           else 'the supplier has not confirmed a WhatsApp number' end);
  else
    select * into n from public.notifications where id = v_wa_id;
    select t.status into v_tmpl from public.messaging_template t
     where t.sid = (select s.value::jsonb #>> array['supplier_account_notice', coalesce(n.lang, m->>'lang')]
                      from public.app_secrets s where s.key = 'wa_template_sids')
     order by t.last_checked_at desc nulls last limit 1;
    if n.status in ('queued', 'pending') and coalesce(v_tmpl, 'unregistered') <> 'approved' then
      update public.notifications
         set last_error = 'awaiting template: supplier_account_notice is ' || coalesce(v_tmpl, 'unregistered')
                          || ' at Meta (Twilio ticket 29665983). This copy is tried until it is '
                          || coalesce((select value from public.app_secrets where key = 'wa_stale_hours'), '24')
                          || ' hours old and then expires (held as stale) if the template is still not approved. The email carried this reminder.'
       where id = v_wa_id;
      v_wa := jsonb_build_object('state', 'pending_template', 'notification_id', v_wa_id,
                                 'template', 'supplier_account_notice', 'template_status', coalesce(v_tmpl, 'unregistered'));
    elsif n.status in ('queued', 'pending') then
      v_wa := jsonb_build_object('state', 'queued', 'notification_id', v_wa_id, 'template', 'supplier_account_notice');
    else
      v_wa := jsonb_build_object('state', n.status, 'notification_id', v_wa_id, 'reason', n.last_error);
    end if;
  end if;

  return jsonb_build_object('sent', true, 'lang', m->>'lang', 'gaps', v_gaps,
                            'delivery_handoff_id', d.id, 'notification_id', v_nid, 'whatsapp', v_wa);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_root_cause_week()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_from timestamptz := now() - interval '7 days';
  v_min int := greatest(1, public.fn_seat_clock_policy('support_root_cause_min_cases', 2)::int);
  v_mw int := greatest(1, public.fn_seat_clock_policy('support_root_cause_measure_weeks', 2)::int);
  r record; v_id bigint; v_hid bigint; v_after numeric; v_weeks numeric; v_verdict text;
  n_open int := 0; n_hand int := 0; n_meas int := 0; n_fell int := 0;
begin
  -- a case still unset is support's to classify
  update public.support_case c set category = 'uncategorised'
   where c.category is null and c.opened_at >= v_from
     and (c.subject like '%ZZ DEMO%' or exists (select 1 from public.support_customer_profile p
                                                where p.id = c.customer_profile_id and public.fn_is_demo_email(p.email))) = v_fx;

  -- a. group the week by cause
  delete from public.support_cause_week where week_ending = v_week and fixture = v_fx;
  insert into public.support_cause_week (week_ending, cause_key, category, topic_tag, owner_seat, cases, reopened, fixture)
  select v_week, x.category || '/' || x.tag, x.category, x.tag, sc.owner_seat, count(*), count(*) filter (where x.reopen_count > 0), v_fx
    from (select c.case_id, c.category, c.reopen_count, t.tag
            from public.support_case c
            left join public.support_customer_profile p on p.id = c.customer_profile_id
            cross join lateral unnest(case when cardinality(c.topic_tags) = 0 then array['-'] else c.topic_tags end) t(tag)
           where c.opened_at >= v_from and c.category is not null
             and (c.subject like '%ZZ DEMO%' or coalesce(public.fn_is_demo_email(p.email), false)) = v_fx
          union all
          -- a formal complaint (Complaints Policy ticket) is a complaint cause of its own
          select null, 'complaint', 0, 'complaint_ticket' from public.complaint_tickets t
           where t.created_at >= v_from and public.fn_is_demo_email(t.email) = v_fx) x
    join public.support_category sc on sc.category = x.category
   group by x.category, x.tag, sc.owner_seat;

  -- b. a recurring cause opens one root cause
  for r in select w.*, sc.support_fixes from public.support_cause_week w join public.support_category sc on sc.category = w.category
            where w.week_ending = v_week and w.fixture = v_fx and w.cases >= v_min
              and not exists (select 1 from public.support_root_cause rc where rc.cause_key = w.cause_key and rc.fixture = v_fx
                                 and rc.status in ('open', 'handed_off', 'measuring', 'not_fallen'))
            order by w.cases desc loop
    insert into public.support_root_cause (cause_key, category, topic_tag, owner_seat, support_fixes, opened_week, baseline_per_week, fixture)
    values (r.cause_key, r.category, r.topic_tag, r.owner_seat, r.support_fixes, v_week, r.cases, v_fx)
    returning id into v_id;
    n_open := n_open + 1;
    if not r.support_fixes then
      v_hid := public.fn_seat_handoff('customer_support', r.owner_seat, 'support.root_cause', 'support_root_cause', v_id::text,
        jsonb_build_object('root_cause_id', v_id, 'cause_key', r.cause_key, 'category', r.category, 'topic_tag', r.topic_tag,
                           'cases_this_week', r.cases, 'reopened', r.reopened, 'week_ending', v_week));
      update public.support_root_cause set status = 'handed_off', handoff_id = v_hid, acted_at = now() where id = v_id;
      n_hand := n_hand + 1;
    end if;
  end loop;

  -- c. measure every acted cause once its window has passed
  for r in select * from public.support_root_cause
            where fixture = v_fx and status in ('handed_off', 'measuring') and acted_at <= now() - make_interval(weeks => v_mw) loop
    v_weeks := greatest(1, floor(extract(epoch from now() - r.acted_at) / 604800));
    if r.topic_tag = 'complaint_ticket' then
      select count(*) / v_weeks into v_after from public.complaint_tickets t
       where t.created_at > r.acted_at and public.fn_is_demo_email(t.email) = r.fixture;
    else
      select count(*) / v_weeks into v_after
        from public.support_case c left join public.support_customer_profile p on p.id = c.customer_profile_id
       where c.category = r.category and c.opened_at > r.acted_at
         and ((r.topic_tag = '-' and cardinality(c.topic_tags) = 0) or r.topic_tag = any (c.topic_tags))
         and (c.subject like '%ZZ DEMO%' or coalesce(public.fn_is_demo_email(p.email), false)) = r.fixture;
    end if;
    v_verdict := case when v_after < r.baseline_per_week then 'fell' else 'not_fallen' end;
    update public.support_root_cause
       set measurements = measurements || jsonb_build_array(jsonb_build_object('at', now(), 'weeks', v_weeks,
                            'after_per_week', round(v_after, 2), 'baseline_per_week', r.baseline_per_week, 'verdict', v_verdict)),
           status = case when v_verdict = 'fell' then 'fell' when r.support_fixes then 'not_fallen' else 'handed_off' end,
           closed_at = case when v_verdict = 'fell' then now() end,
           acted_at = case when v_verdict = 'fell' or r.support_fixes then acted_at else now() end
     where id = r.id;
    n_meas := n_meas + 1;
    if v_verdict = 'fell' then
      n_fell := n_fell + 1;
      if r.handoff_id is not null then
        perform set_config('qd.handoff_closer', 'customer_support', true);
        perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object('verified_by', 'customer_support', 'root_cause_id', r.id,
          'baseline_per_week', r.baseline_per_week, 'after_per_week', round(v_after, 2)));
        perform set_config('qd.handoff_closer', '', true);
      end if;
    elsif r.handoff_id is not null then
      update public.agent_actions set detail = detail || jsonb_build_object('last_measurement',
               jsonb_build_object('at', now(), 'after_per_week', round(v_after, 2), 'baseline_per_week', r.baseline_per_week, 'verdict', 'not_fallen'))
       where id = r.handoff_id;
    end if;
  end loop;

  return jsonb_build_object('week_ending', v_week, 'fixture', v_fx,
    'causes', (select count(*) from public.support_cause_week where week_ending = v_week and fixture = v_fx),
    'root_causes_opened', n_open, 'handed_off', n_hand, 'measured', n_meas, 'fell', n_fell,
    'support_to_fix', (select count(*) from public.support_root_cause where fixture = v_fx and status in ('open', 'not_fallen')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_self_review()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'customer_support') $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_sends_the_it_digest(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_hour  constant time := time '19:00';                         -- the founder's fixed local time
  v_stub  boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_local timestamp := p_now at time zone 'Asia/Dubai';
  v_key   text := 'it_daily_digest:' || to_char(p_now at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  x record; f public.it_engineer_finding; v_why text; v_his boolean; v_items jsonb := '[]'::jsonb;
  v_event text; v_detail text; v_res jsonb; v_fan jsonb := '[]'::jsonb; v_before bigint;
  n_dec int := 0; n_flt int := 0; n_int int := 0; n_fixed int := 0; n_wait int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('fn_customer_support_sends_the_it_digest'));
  if v_local::time < c_hour then
    return jsonb_build_object('sent', false, 'reason', 'the IT digest leaves at 19:00 Dubai', 'digest_key', v_key);
  end if;
  if exists (select 1 from public.founder_alerts where dedupe_key = v_key) then
    return jsonb_build_object('sent', false, 'reason', 'today''s IT digest was already decided', 'digest_key', v_key);
  end if;

  for x in select a.id, a.detail, a.evidence from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'pending'
              and a.detail->>'type' = 'delivery.request' and a.detail->>'recipient_role' = 'founder'
              and a.detail->>'kind' = 'it_new_bug' and a.evidence->>'digest' = 'pending'
            order by a.id loop
    -- Anything that is not "a new bug nobody could fix" (today: the CEO-silence reports) is the CEO's.
    if coalesce(x.detail->>'dedupe_key', '') !~ '^it_new_bug:' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'instruction 642: kept internal; the CEO is asked every tick until it answers',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    select * into f from public.it_engineer_finding where issue_key = regexp_replace(x.detail->>'dedupe_key', '^it_new_bug:', '');
    if not found or f.closed_at is not null then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'fixed',
        'why', 'closed before the digest: ' || coalesce(f.close_note, 'no finding row'),
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_fixed := n_fixed + 1; continue;
    end if;
    -- His ruling that something is NOT his wins over any pattern that would ask him.
    select c.why, c.to_founder into v_why, v_his from public.it_founder_decision_class c where f.issue_key like c.issue_key_like
     order by c.to_founder, length(c.issue_key_like) desc limit 1;
    if found and not v_his then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', v_why, 'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; v_why := null; continue;
    end if;
    if not found then v_why := null; end if;
    if v_why is null and f.started_at > p_now - interval '24 hours' then
      n_wait := n_wait + 1; continue;                          -- still young: judged again tomorrow
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'decision', v_why is not null, 'key', f.issue_key,
      'family', case when regexp_replace(f.issue_key, ':[^:]*$', '') ~ ':' then regexp_replace(f.issue_key, ':[^:]*$', '') else f.issue_key end,
      'title', regexp_replace(left(f.title, 140), '[.\s]+$', ''), 'since', f.started_at,
      'owner', coalesce(f.evidence->>'owner_seat', 'it_engineer'), 'why', v_why);
    if v_why is not null then n_dec := n_dec + 1; else n_flt := n_flt + 1; end if;
  end loop;

  if jsonb_array_length(v_items) = 0 then
    if not v_stub then
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      values ('info', 'IT daily digest: nothing needs the founder today',
              jsonb_build_object('fixed', n_fixed, 'internal', n_int, 'waiting', n_wait)::text, 'os', v_key);
    end if;
    return jsonb_build_object('sent', false, 'reason', 'nothing needs him today', 'digest_key', v_key,
                              'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'stubbed', v_stub);
  end if;

  -- One sentence per decision; faults of one family raised together are one sentence with their count.
  select string_agg(line, E'\n' order by decision desc, first_id)
    into v_detail
    from (select bool_or((i->>'decision')::boolean) decision, min((i->>'id')::bigint) first_id,
                 case when bool_or((i->>'decision')::boolean) then
                   '- DECISION: ' || min(i->>'title') || '. Only you can decide this: ' || min(i->>'why')
                   || '. The CEO keeps it open until you answer (reference ' || min(i->>'key') || ').'
                 else
                   '- ' || case when count(*) > 1 then count(*) || ' problems of one kind, e.g. ' else '' end
                   || min(i->>'title') || ', open since '
                   || to_char(min((i->>'since')::timestamptz) at time zone 'Asia/Dubai', 'DD Mon') || '. Nothing inside the company fixed it; the '
                   || replace(min(i->>'owner'), '_', ' ') || ' has it, the engineers are making the code or configuration change, and the IT engineer re-checks it every 15 minutes and closes it when it is gone (reference '
                   || case when count(*) > 1 then min(i->>'family') || ':...' else min(i->>'key') end || ').'
                 end line
            from jsonb_array_elements(v_items) i
           group by case when (i->>'decision')::boolean then i->>'key' else i->>'family' end) g;
  v_event := 'IT today: ' || case when n_dec > 0 then n_dec || ' decision' || case when n_dec > 1 then 's' else '' end || ' for you' else '' end
             || case when n_dec > 0 and n_flt > 0 then ', ' else '' end
             || case when n_flt > 0 then n_flt || ' fault' || case when n_flt > 1 then 's' else '' end || ' open more than a day' else '' end;
  v_detail := 'The one IT message of the day. It carries only what needs you: decisions only you can make, and faults '
           || 'the company could not fix that have been open more than 24 hours. Everything else stays with the CEO and the seats.'
           || E'\n\n' || v_detail;

  if v_stub then
    v_res := jsonb_build_object('stubbed', true);               -- A TEST NEVER REACHES HIM
  else
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_detail, p_level => 'normal',
                                      p_kind => 'it_daily_digest', p_dedupe_key => v_key, p_owner_agent => 'customer_support');
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
  end if;
  -- Each item told is completed with the digest's notification ids; the delivery watch takes it from there.
  for x in select (i->>'id')::bigint id from jsonb_array_elements(v_items) i loop
    perform public.fn_seat_handoff_complete(x.id, (select (a.evidence - 'waiting') from public.agent_actions a where a.id = x.id)
      || jsonb_build_object('digest', 'sent', 'digest_key', v_key, 'notify', v_res, 'notification_ids', v_fan, 'notification_id', v_fan->0)
      || case when v_stub then jsonb_build_object('stubbed', true) else '{}'::jsonb end);
  end loop;

  return jsonb_build_object('sent', true, 'digest_key', v_key, 'event', v_event, 'detail', v_detail,
                            'decisions', n_dec, 'faults', n_flt, 'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_takes_delivery(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r jsonb; v_seat text; v_id bigint; h public.agent_actions; v_out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'fn_customer_support_takes_delivery takes an array of notification rows';
  end if;
  for r in select x from jsonb_array_elements(p_rows) x loop
    if coalesce(btrim(r->>'type'), '') = '' then raise exception 'a delivery request must name its type'; end if;
    v_seat := coalesce(nullif(btrim(r->>'requested_by'), ''), public.fn_channel_requester(r->>'type', r->>'kind'));
    if v_seat = 'platform' then
      raise exception 'a sign-in code (%) is sent by the platform OTP service, never queued through support', r->>'type';
    end if;
    v_id := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications',
      coalesce(nullif(btrim(r->>'dedupe_key'), ''),
               (r->>'type') || ':' || coalesce(r->>'to_email', r->>'to_phone', r->>'to_role', 'nobody') || ':' || gen_random_uuid()::text),
      jsonb_build_object('prepared', r - 'dedupe_key' - 'requested_by' - 'status' - 'sender',
                         'msg_type', r->>'type', 'recipient_role', r->>'to_role', 'to_email', r->>'to_email',
                         'supplier_id', r->'lead_id', 'inquiry_id', r->'inquiry_id', 'quote_id', r->'quote_id'));
    select * into h from public.agent_actions where id = v_id;
    v_out := v_out || jsonb_build_array(jsonb_build_object('handoff_id', v_id, 'seat', v_seat, 'status', h.status,
      'notification_id', h.evidence->'notification_id', 'error', h.detail->>'error'));
  end loop;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_tells_the_customer_about_held_money(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; m jsonb; v_res jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff'
     and detail->>'type' in ('fraud.money_held', 'fraud.money_released');
  if not found then raise exception 'fn_customer_support_tells_the_customer_about_held_money: % is not a money-hold handoff', p_id; end if;
  m := public.fn_customer_support_held_money_message((a.detail->>'hold_id')::bigint, a.detail->>'type');
  if m ? 'not_sent' then return m; end if;
  -- The stage is the handoff type ('fraud.money_held' / 'fraud.money_released'): once per hold, per stage.
  v_res := public.fn_customer_support_duty_send(a.detail->>'type', m->>'hold_id', 'customer', m->>'email',
    m->>'lang', m->>'subject', m->>'body', (m->>'customer_id')::uuid, null, (m->>'inquiry_id')::uuid);
  return v_res || jsonb_build_object('hold_id', (m->>'hold_id')::bigint, 'move', m->>'move', 'lang', m->>'lang', 'ref', m->>'ref');
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_waits_for_a_person(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('waiting', coalesce(a.detail ->> 'waiting_for', 'a person to answer'))
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_customer_support_winback_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb;
  v_lang text; v_ar boolean; v_name text; v_labels text; v_first text; v_n int; v_sent int := 0; v_seen int := 0;
begin
  -- 29 Sep 2026 (founder_instruction 1013): "inactive" is no request and no reveal for 60 days, and the message is
  -- about the trades the customer actually asked for, in the language of their last request. Until this date it
  -- was 60-90 days after a reveal only, generic copy, customers.locale.
  for r in select c.id, c.full_name, c.email, c.locale as customer_locale, x.last_at, x.last_inquiry, x.trades
             from public.customers c
             cross join lateral (
               select greatest((select max(i.created_at) from public.inquiries i where i.customer_id = c.id),
                               (select max(t.revealed_at) from public.transactions t where t.customer_id = c.id)) as last_at,
                      (select i.id from public.inquiries i where i.customer_id = c.id order by i.created_at desc limit 1) as last_inquiry,
                      -- their trades: the most frequent request categories, most recent first on a tie, at most three
                      array(select k from (select lower(btrim(coalesce(i.category, i.trades[1]))) as k, count(*) as n, max(i.created_at) as at
                                             from public.inquiries i where i.customer_id = c.id
                                              and coalesce(i.category, i.trades[1]) is not null group by 1) g
                             order by n desc, at desc limit 3) as trades) x
            where x.last_at between now() - interval '90 days' and now() - interval '60 days'
              and x.last_inquiry is not null
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by x.last_at limit 200 loop
    v_seen := v_seen + 1;
    v_lang := public.fn_customer_message_lang(r.last_inquiry, r.customer_locale);
    v_ar := v_lang = 'ar';
    v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    select string_agg(public.fn_trade_label(k, v_lang), case when v_ar then '، ' else ', ' end order by o)
      into v_labels from unnest(r.trades) with ordinality as u(k, o);
    v_first := public.fn_trade_label(r.trades[1], v_lang);
    -- how many verified suppliers quote for their first trade today (the rule supply_gap counts by)
    select count(*) into v_n from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and r.trades[1] = any (sc.trades) and not coalesce(l.is_demo, false)
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes);
    v := public.fn_customer_support_duty_send('winback.dormant', r.id || ':' || to_char(r.last_at, 'YYYYMMDD'), 'customer',
      r.email, v_lang,
      case when v_ar then 'مشروعكم القادم في ' || coalesce(v_first, 'QuotesDone') else 'Your next ' || coalesce(v_first, 'project') || ' job on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'مضى بعض الوقت على آخر طلب لكم معنا' || coalesce(' في ' || v_labels, '') || '.'
        || case when v_n > 0 then ' ويقدّم اليوم ' || v_n || ' من الموردين الموثّقين في الإمارات عروضهم في ' || v_first || '.' else '' end
        || ' وحين يحين مشروعكم القادم، يكفي أن تنشروه مرة واحدة، فنقارن العروض ونوصي بأفضل ثلاثة منها من حيث القيمة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها: https://quotesdone.ae/ar/me' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'It has been a while since your last request with us' || coalesce(' for ' || v_labels, '') || '.'
        || case when v_n > 0 then ' Today ' || v_n || ' verified UAE supplier' || case when v_n = 1 then ' quotes' else 's quote' end || ' for ' || v_first || '.' else '' end
        || ' When the next job comes up, post it once; we compare the quotes and recommend the top three by value. You reveal only the one you choose, and pay 3% only then: https://quotesdone.ae/me' || chr(10) || chr(10)
        || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.' end,
      r.id, null, r.last_inquiry);
    if coalesce((v->>'sent')::boolean, false) then v_sent := v_sent + 1; end if;
  end loop;
  return jsonb_build_object('dormant', v_seen, 'written', v_sent);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_terms_accept(p_customer_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c            public.customers%rowtype;
  v_slug       text := 'customer-terms';
  v_version    text;
  v_digest     text;
  v_owner      text := p_customer_id::text;
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such customer ' || p_customer_id);
  end if;

  -- The currently published document: newest effective_date wins (version is a label, not an
  -- order). The version and digest are read here and never trusted from the caller.
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_version, v_digest
    from public.legal_documents d where d.slug = v_slug
    order by d.effective_date desc nulls last, d.version desc limit 1;
  if v_version is null then
    return jsonb_build_object('ok', false, 'reason', 'no published document for slug ' || v_slug);
  end if;

  -- Idempotent: a second acceptance does not move the first acceptance's timestamp.
  update public.customers
     set tos_accepted_at = coalesce(tos_accepted_at, now()),
         tos_version = v_version,
         tos_ip = coalesce(nullif(btrim(p_ip),''), tos_ip)
   where id = p_customer_id;

  return jsonb_build_object(
    'ok', true,
    'acceptance_ref', v_owner || ':' || v_version,
    'terms_version', v_version,
    'terms_hash', v_digest,
    'document_slug', v_slug,
    -- Kept null so existing callers keep parsing. See the header above.
    'run_id', null,
    'step_run_id', null,
    'dispatch_outcome', 'dispatch_removed',
    'effect_id', null,
    'dispatch', null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_terms_accepted_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v jsonb;
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  begin
    v := public.fn_customer_terms_accept(new.id, new.tos_ip);
    if coalesce((v->>'ok')::boolean, false) is not true then
      insert into public.error_events (source, kind, severity, detail)
      values ('customer_terms_accepted_trg', 'acceptance_record_not_written', 'high',
              jsonb_build_object('customer_id', new.id, 'result', v));
    end if;
  exception when others then
    insert into public.error_events (source, kind, severity, detail)
    values ('customer_terms_accepted_trg', 'acceptance_record_failed', 'high',
            jsonb_build_object('customer_id', new.id, 'sqlstate', sqlstate, 'error', left(sqlerrm, 500)));
  end;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_welcome_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(new.email),'') <> '' then
    begin
      perform public.fn_customer_welcome(new.id, true);
    exception when others then
      -- Never let onboarding courtesy break account creation.
      null;
    end;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customers_board(p_search text DEFAULT ''::text, p_limit integer DEFAULT 80, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb;
begin
  with base as (
    select c.id::text as id, coalesce(nullif(trim(c.full_name),''),'(unnamed)') as full_name, c.email, c.phone,
      coalesce(c.email_verified,false) as email_verified, coalesce(c.phone_verified,false) as phone_verified, c.banned, c.created_at,
      case when c.banned then 'banned' when coalesce(c.email_verified,false) or coalesce(c.phone_verified,false) then 'verified' else 'new' end as stage
    from customers c
    where coalesce(p_search,'')='' or c.full_name ilike '%'||p_search||'%' or c.email ilike '%'||p_search||'%' or c.phone ilike '%'||p_search||'%'
  ), ranked as (select *, row_number() over (partition by stage order by created_at desc) rn from base),
  sc as (select stage, count(*) c from base group by stage)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'stages',(select jsonb_agg(jsonb_build_object('key',s.key,'label',s.label,'count',coalesce((select c from sc where sc.stage=s.key),0),
      'cards',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'full_name',r.full_name,'email',r.email,'phone',r.phone,'email_verified',r.email_verified,'banned',r.banned) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
      order by s.ord)
      from (values ('new','New',1),('verified','Verified',2),('banned','Banned',3)) s(key,label,ord)),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'full_name',b.full_name,'email',b.email,'phone',b.phone,'email_verified',b.email_verified,'phone_verified',b.phone_verified,'banned',b.banned,'stage',b.stage,'created_at',b.created_at) order by b.created_at desc),'[]'::jsonb)
             from (select * from base order by created_at desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b)
  ) into out; return out;
end $function$


