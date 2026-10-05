CREATE OR REPLACE FUNCTION public.fn_identify_contact(p_phone text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_d text; v_tail text; v_name text; v_sid bigint; v_cid text; v_claimed boolean; v_appr boolean; v_kind text; v_cuid uuid;
begin
  v_d := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if length(v_d) < 7 then return json_build_object('audience','unknown'); end if;
  v_tail := right(v_d, 9);   -- tolerate +9715..., 05..., 5... variants

  -- THE FOUNDER. Before suppliers and customers: he is neither, and a number that is both his and
  -- a lead's must still be treated as his.
  if exists (
    select 1 from unnest(string_to_array(coalesce((select value from app_secrets where key='admin_mfa_phone'),''), ',')) p
     where length(regexp_replace(p,'[^0-9]','','g')) >= 9
       and right(regexp_replace(p,'[^0-9]','','g'), 9) = v_tail)
  then
    return json_build_object('audience','founder',
      'name', split_part(coalesce((select value from app_secrets where key='admin_emails'),''), ',', 1));
  end if;

  -- 14 Sep 2026 (#322): a supplier or customer is recognised only by a CONFIRMED WhatsApp number.
  select o.party_kind, o.lead_id, o.customer_id into v_kind, v_sid, v_cuid from public.fn_whatsapp_owner(p_phone) o;
  if v_kind = 'supplier' then
    select company_name, coalesce(claimed,false), (approval_status='approved') into v_name, v_claimed, v_appr from leads where id = v_sid;
  end if;
  if v_sid is not null then
    return json_build_object('audience','supplier','name',v_name,'claimed',v_claimed,'approved',coalesce(v_appr,false));
  end if;

  if v_kind = 'customer' then select id::text, full_name into v_cid, v_name from customers where id = v_cuid; end if;
  if v_cid is not null then
    return json_build_object('audience','customer','name',v_name);
  end if;

  return json_build_object('audience','unknown');
end $function$


CREATE OR REPLACE FUNCTION public.fn_identity_policy_is_a_live_seat_and_a_known_model()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_bad text;
begin
  if not exists (select 1 from public.org_agents a where a.agent_key = new.identity_key) then
    raise exception
      'model_policy_by_identity.identity_key % is not a live seat. The router can only be reached with an agent key a live seat passes; a row for anything else is a route nobody can take.',
      new.identity_key;
  end if;

  for v_bad in
    select m from unnest(array[new.primary_model, new.fallback_model, new.escalation_model]) m
    where m is not null and m <> 'none/deterministic'
  loop
    if not exists (select 1 from public.model_registry r where r.model_id = v_bad) then
      raise exception
        'model_policy_by_identity names % which is not in model_registry. fn_ai_route would silently substitute another model and write the warning into a `why` nobody reads.',
        v_bad;
    end if;
    if not exists (select 1 from public.llm_route_health h where h.model_id = v_bad) then
      raise exception
        'model_policy_by_identity names % which has no llm_route_health row, so the founder''s hold does not cover it.',
        v_bad;
    end if;
  end loop;

  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_inbox_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- owner_role is null: a row a department owns is that department's work, never the founder's inbox (6 Sep 2026)
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'needs_review', (select count(*) from public.inbound_messages where needs_review=true and replied_at is null and owner_role is null
                        and created_at >= public.fn_os_fresh_start_at()),
      'untriaged', (select count(*) from public.inbound_messages where needs_review=true and triaged_at is null and replied_at is null and owner_role is null
                     and created_at >= public.fn_os_fresh_start_at()),
      'replied_7d', (select count(*) from public.inbound_messages where replied_at > now()-interval '7 days')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'from_email',from_email,'subject',subject,'body',left(coalesce(body,''),1200),
        'category',ai_category,'summary',ai_summary,'draft',ai_draft_reply,
        'triaged_at',triaged_at,'created_at',created_at) order by created_at desc)
      from (select * from public.inbound_messages
             where needs_review=true and replied_at is null and owner_role is null
               and created_at >= public.fn_os_fresh_start_at()
             order by created_at desc limit 50) m),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_inbox_send(p_id bigint, p_body text, p_by text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m public.inbound_messages%rowtype;
begin
  select * into m from public.inbound_messages where id=p_id;
  if m.id is null then return jsonb_build_object('error','message not found'); end if;
  if m.from_email is null then return jsonb_build_object('error','no sender address'); end if;
  if coalesce(trim(p_body),'')='' then return jsonb_build_object('error','empty reply'); end if;

  insert into public.notifications(type,to_email,to_role,channel,subject,body,in_reply_to)
    values('inbound_reply', m.from_email, null, 'email',
           case when coalesce(m.subject,'') ilike 're:%' then m.subject else 'Re: '||coalesce(nullif(m.subject,''),'your message') end,
           p_body, nullif(btrim(m.raw->>'message_id'), ''));

  update public.inbound_messages set replied_at=now(), replied_by=coalesce(p_by,'founder'), needs_review=false where id=p_id;
  update public.agent_actions set status='approved', decided_by=coalesce(p_by,'founder'), decided_at=now()
   where target_table='inbound_messages' and target_id=p_id::text
     and status in ('pending','held_for_review','proposed','open');
  return jsonb_build_object('ok',true, 'to', m.from_email);
end $function$


CREATE OR REPLACE FUNCTION public.fn_inquiries_lang_default()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- a request created without a language (an import, a fixture, an older client) takes the customer's
  -- registered language; one created from the composer carries the page language it was written in.
  if new.lang is null or new.lang not in ('en', 'ar') then
    new.lang := coalesce(public.fn_registered_locale('customer', new.customer_id), 'en');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_inquiry_add_missing_specs(p_inquiry uuid, p_customer uuid, p_answers jsonb, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  i public.inquiries; v_missing jsonb; v_add jsonb := '{}'::jsonb; v_lines text := ''; e record; v_val text; v_ask text;
  v_note bigint; v_after public.inquiries; v_told int := 0; l record; v_res jsonb;
begin
  if p_source not in ('customer_portal', 'email_reply') then raise exception 'missing specs come from customer_portal or email_reply, not %', p_source; end if;
  if p_source = 'customer_portal' and p_customer is null then raise exception 'a portal answer names its customer'; end if;
  select * into i from public.inquiries where id = p_inquiry for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'inquiry_not_found'); end if;
  if p_customer is not null and i.customer_id is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_inquiry'); end if;
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed') then return jsonb_build_object('ok', false, 'error', 'inquiry_closed'); end if;
  if jsonb_typeof(p_answers) is distinct from 'object' then return jsonb_build_object('ok', false, 'error', 'answers_required'); end if;

  -- Only what is missing NOW, keyed as the check reads it; anything else is not this door's to write.
  v_missing := public.fn_inquiry_missing_specs(i.id, 'en')->'missing';
  for e in select a.key, a.value from jsonb_each_text(p_answers) a loop
    v_val := left(btrim(coalesce(e.value, '')), 300);
    select m->>'ask' into v_ask from jsonb_array_elements(v_missing) m where m->>'key' = lower(btrim(e.key));
    if v_ask is null or not public._rfq_answered(v_val) then continue; end if;
    v_add := v_add || jsonb_build_object(lower(btrim(e.key)), v_val);
    v_lines := v_lines || case when v_lines = '' then '' else chr(10) end || v_ask || ' ' || v_val;
  end loop;
  if v_add = '{}'::jsonb then return jsonb_build_object('ok', false, 'error', 'nothing_to_add', 'missing', v_missing); end if;

  -- The row's own trigger (trg_rfq_complete) re-runs the hold check on this write. Budget and emirate are the
  -- request's own columns; every other answer is a spec under its key.
  update public.inquiries
     set spec = case when jsonb_typeof(spec) = 'object' then spec else '{}'::jsonb end || (v_add - 'budget' - 'emirate'),
         budget = coalesce(v_add->>'budget', budget),
         emirate = coalesce(v_add->>'emirate', emirate)
   where id = i.id returning * into v_after;

  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
  values (i.id, null, 'note',
          case when p_source = 'email_reply' then 'The customer replied with the details this trade needs:' else 'The customer added the details this trade needs:' end
          || chr(10) || v_lines, now(), 'missing_specs')
  returning id into v_note;

  -- Every supplier already invited is told, through customer_support's door (suppliers are written in English).
  for l in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email
             from public.inquiry_matches x join public.leads le on le.id = x.supplier_id
            where x.inquiry_id = i.id and not coalesce(le.banned, false)
              and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%' loop
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'rfq_addendum', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', l.to_email,
      'to_role', 'supplier', 'lead_id', l.id, 'inquiry_id', i.id, 'lang', 'en',
      'subject', 'The customer added detail to a request you were invited to quote',
      'body', 'The customer added this to the ' || coalesce(i.category, '') || coalesce(' job in ' || nullif(i.emirate, ''), ' job')
              || ' you were invited to quote:' || chr(10) || chr(10) || v_lines || chr(10) || chr(10)
              || 'It is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.',
      'dedupe_key', 'missing_specs:' || v_note || ':' || l.id)));
    v_told := v_told + 1;
  end loop;

  v_missing := public.fn_inquiry_missing_specs(i.id, null);
  return jsonb_build_object('ok', true, 'added', (select jsonb_agg(k) from jsonb_object_keys(v_add) k),
    'ready', coalesce(v_after.rfq_ready, false), 'still_missing', v_missing->'missing',
    'reached_suppliers', (v_missing->>'reached_suppliers')::boolean, 'suppliers_told', v_told, 'note_id', v_note);
end $function$


CREATE OR REPLACE FUNCTION public.fn_inquiry_is_demo(p_inquiry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((
    select coalesce(c.is_demo, false)
           or coalesce(i.provenance ? 'qd_run', false)
           or coalesce(i.brief_source, '') = 'qd_demo_fixture'
      from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.id = p_inquiry), false)
$function$


CREATE OR REPLACE FUNCTION public.fn_inquiry_locale(p_inquiry uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- null when no inquiry is named or it has no language: the caller falls back to the registered one.
  select case when i.lang = 'ar' then 'ar' when i.lang = 'en' then 'en' end
    from public.inquiries i where i.id = p_inquiry
$function$


CREATE OR REPLACE FUNCTION public.fn_inquiry_missing_specs(p_inquiry uuid, p_lang text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.inquiries; v_ar boolean; v_chk jsonb; v_fields jsonb; v_missing jsonb := '[]'::jsonb; m jsonb; f jsonb;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('held', false, 'reason', 'no such request'); end if;
  v_ar := coalesce(case when p_lang in ('en', 'ar') then p_lang end, public.fn_inquiry_locale(i.id),
                   (select c.locale from public.customers c where c.id = i.customer_id)) = 'ar';
  -- A combined (split) request's specs belong to its per-trade parts, each checked and completed on its own; the
  -- parent carries none (the concierge re-review of #1112 judges a parent by its children the same way).
  if exists (select 1 from public.inquiries c where c.parent_inquiry_id = i.id) then
    return jsonb_build_object('held', false, 'lang', case when v_ar then 'ar' else 'en' end, 'missing', '[]'::jsonb,
                              'reason', 'a combined request: each trade is completed on its own part');
  end if;
  v_chk := public.fn_rfq_required_check(i);
  select cs.fields into v_fields from public.category_specs cs where lower(cs.category) = lower(coalesce(i.category, '')) limit 1;
  for m in select value from jsonb_array_elements(coalesce(v_chk->'missing', '[]'::jsonb)) loop
    f := null;
    select value into f from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) where lower(value->>'key') = m->>'key' limit 1;
    v_missing := v_missing || jsonb_build_array(jsonb_build_object(
      'key', m->>'key',
      'ask', coalesce(nullif(f->>case when v_ar then 'question_plain_ar' else 'question_plain_en' end, ''), nullif(m->>'question', ''), m->>'key'),
      'type', coalesce(f->>'type', m->>'type', 'text'),
      'options', coalesce(f->'options', '[]'::jsonb)));
  end loop;
  -- The general score also holds a request below its bar (fn_rfq_score: generic_ready). Of its parts, the two a
  -- customer can state in a field are asked too, so completing the page can release the request.
  if not coalesce((public.fn_rfq_score(i)->>'generic_ready')::boolean, true) then
    if i.budget is null then
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', 'budget', 'type', 'text', 'options', '[]'::jsonb,
        'ask', case when v_ar then 'الميزانية المرصودة للعمل (يكفي نطاق تقريبي).' else 'Your budget for the work (a range is fine).' end));
    end if;
    if coalesce(i.emirate, '') = '' then
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', 'emirate', 'type', 'text', 'options', '[]'::jsonb,
        'ask', case when v_ar then 'في أي إمارة ومنطقة سيُنفَّذ العمل؟' else 'Which emirate and area is the work in?' end));
    end if;
  end if;
  return jsonb_build_object(
    'held', coalesce(i.status, '') not in ('cancelled', 'closed', 'completed') and jsonb_array_length(v_missing) > 0,
    'lang', case when v_ar then 'ar' else 'en' end, 'ready', coalesce(i.rfq_ready, false), 'missing', v_missing,
    'reached_suppliers', exists (select 1 from public.inquiry_matches x where x.inquiry_id = i.id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_intake_slug_for_catalog(p_catalog_slug text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The reverse of fn_category_knowledge: catalogue slug -> the legacy intake slug that owns the
  -- checklist. It is 1-to-many (flooring-suppliers is reached by carpets, epoxy-flooring, flooring,
  -- marble-granite and tiling), so the choice has to be deterministic or the same customer wording
  -- would land on a different checklist run to run.
  --
  -- Prefer a key the catalogue slug actually BEGINS with - 'flooring' for flooring-suppliers,
  -- 'aluminium' for aluminium-and-glass-suppliers, 'mep' for mep-suppliers-electromechanical.
  -- That picks the base trade over a facet of it. Where none prefixes, the shortest wins, which
  -- also prefers the base ('carpentry' over 'carpentry-joinery', 'fitout' over
  -- 'commercial-retail-fitout'). Only keys that exist in category_specs are eligible, because the
  -- answer has to be something the checklist lookup can actually use.
  --
  -- 14 Sep 2026: two catalogues whose checklist key is already another catalogue's in lead_trade_map
  -- (its primary key is trade_key) are named here; see the header of this file.
  select coalesce(
    (select v.intake
       from (values ('fire-alarm-and-life-safety-suppliers', 'safety'),
                    ('elv-and-security-systems-suppliers',   'security')) as v(slug, intake)
       join (select distinct category from public.category_specs) cs on cs.category = v.intake
      where v.slug = p_catalog_slug),
    (select m.trade_key
       from public.lead_trade_map m
       join (select distinct category from public.category_specs) cs on cs.category = m.trade_key
      where m.catalog_slug = p_catalog_slug
      order by (p_catalog_slug like m.trade_key || '%') desc, length(m.trade_key) asc, m.trade_key asc
      limit 1));
$function$


CREATE OR REPLACE FUNCTION public.fn_internal_auth(p_secret text, p_function text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare c public.internal_credential%rowtype; v_hash text; v_fn text;
begin
  v_fn := lower(btrim(coalesce(p_function, '')));
  if v_fn = '' then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'no_function_named', p_function);
    return jsonb_build_object('ok', false, 'error', 'no_function_named',
      'message', 'The verifier was called without naming the function being invoked, so it cannot check scope.');
  end if;

  if coalesce(btrim(p_secret), '') = '' then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'no_credential_presented', v_fn);
    return jsonb_build_object('ok', false, 'error', 'no_credential_presented');
  end if;

  v_hash := public.fn_internal_credential_hash(p_secret);
  select * into c from public.internal_credential where secret_hash = v_hash;

  if not found then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'unknown_credential', v_fn);
    return jsonb_build_object('ok', false, 'error', 'unknown_credential');
  end if;

  if not c.active or c.retired_at is not null then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, false, 'credential_retired');
    return jsonb_build_object('ok', false, 'error', 'credential_retired', 'context', c.context);
  end if;

  if c.expires_at is not null and c.expires_at <= now() then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, false, 'credential_expired');
    return jsonb_build_object('ok', false, 'error', 'credential_expired', 'context', c.context,
      'expired_at', c.expires_at);
  end if;

  if not (c.scope @> array['*'] or c.scope @> array[v_fn]) then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason, detail)
    values (c.id, c.context, v_fn, false, 'out_of_scope', jsonb_build_object('scope', c.scope));
    return jsonb_build_object('ok', false, 'error', 'out_of_scope', 'context', c.context,
      'message', format('The %s credential is not scoped to call %s.', c.context, v_fn));
  end if;

  -- THE STAMP, AT MOST ONCE A MINUTE PER FUNCTION (CONN-08). See the header: this same UPDATE, run on
  -- every one of 60,527 calls a day against a handful of shared rows, was 5,048 s of database time.
  if c.last_used_at is null or c.last_used_at < now() - interval '1 minute'
     or c.last_function is distinct from v_fn then
    update public.internal_credential
       set last_used_at = now(), last_function = v_fn, use_count = use_count + 1
     where id = c.id;
  end if;

  -- THE ADDITION. Legacy only.
  if c.is_legacy then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, true, 'legacy_secret_used');
  end if;

  return jsonb_build_object('ok', true, 'context', c.context, 'credential_id', c.id,
                            'legacy', c.is_legacy, 'scope_all', c.scope @> array['*']);
end $function$


CREATE OR REPLACE FUNCTION public.fn_internal_credential_audit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  raise exception 'internal_credential_audit is append-only; % is not permitted', TG_OP using errcode = '42501';
end $function$


CREATE OR REPLACE FUNCTION public.fn_internal_credential_hash(p_secret text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select encode(extensions.hmac(p_secret,
           (select value from public.app_secrets where key = 'internal_credential_hmac_key'),
           'sha256'), 'hex');
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_campaign_pause(p_source text, p_why text, p_evidence jsonb, p_counts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_cancelled int;
begin
  if coalesce(btrim(p_source), '') = '' or coalesce(btrim(p_why), '') = '' then
    raise exception 'fn_invite_campaign_pause(source, why, evidence, counts): a source and a reason are required';
  end if;
  update app_secrets set value = 'false' where key = 'invite_enabled';
  update notifications set status = 'cancelled'
   where type = 'supplier_invite' and status = 'queued';
  get diagnostics v_cancelled = row_count;

  insert into it_watch_finding(detector_key, detector, subject, state, severity, title, evidence)
  values ('deliverability:supplier_invite', 'deliverability', 'supplier_invite', 'paused', 'high',
          'Supplier invitations auto-paused: ' || p_why,
          coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled, 'paused_by', p_source,
                             'resume', 'set app_secrets.invite_enabled=true after reading the bounces/complaints'))
  on conflict (detector_key) do update
     set state = excluded.state, severity = excluded.severity, title = excluded.title, evidence = excluded.evidence,
         last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values (p_source, 'error', coalesce(p_counts, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled),
          'PAUSED: ' || p_why || '; invite_enabled=false, ' || v_cancelled || ' queued invitation(s) cancelled, it_engineer finding opened.', now());
  return jsonb_build_object('paused', true, 'cancelled_queued', v_cancelled, 'source', p_source);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_lane_sent(p_lead_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.notifications n
                  where n.lead_id = p_lead_id and n.type = 'supplier_invite' and n.status = 'sent')
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_lane_since()
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_on boolean; v_since timestamptz;
begin
  v_on := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_lane_enabled'), false);
  if not v_on then return '-infinity'::timestamptz; end if;
  begin
    v_since := nullif(btrim((select value from public.app_secrets where key = 'invite_lane_since')), '')::timestamptz;
  exception when others then v_since := null;
  end;
  -- ON with no readable stamp: count nothing before now, so the lane starts at day 1 rather than inheriting.
  return coalesce(v_since, now());
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_cutoff(p_day date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_invite_placement_deadline(p_day) + interval '2 hours';
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_day_closed(p_now timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when extract(isodow from (p_now at time zone 'Asia/Dubai')) in (6, 7) then 'the UAE weekend'
    when exists (select 1 from public.company_calendar c
                  where c.kind = 'public_holiday'
                    and (p_now at time zone 'Asia/Dubai')::date between c.starts_on and coalesce(c.ends_on, c.starts_on))
      then 'a company_calendar public holiday'
    when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
    when coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_enabled'), 'false') <> 'true'
      then 'invite_enabled is false'
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_deadline(p_day date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select (p_day + make_interval(hours => coalesce(
            (select (nullif(value,'')::jsonb ->> 'window_start_hour')::int from app_secrets where key = 'invite_warmup'), 10)))
         at time zone 'Asia/Dubai';
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_due(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_day date := (p_now at time zone 'Asia/Dubai')::date;
  v_deadline timestamptz := public.fn_invite_placement_deadline(v_day);
  v_cutoff timestamptz := public.fn_invite_placement_cutoff(v_day);
  r public.invite_placement_check;
  v_closed text; v_token text; v_subject text; v_body text; v_site text; v_from text;
  v_g bigint; v_o bigint; v_sg text; v_so text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;

  if r.dubai_day is null then
    -- Queued from 04:30 UTC; not later than 30 minutes before the cutoff, which leaves beats to read it.
    if p_now < v_deadline - interval '90 minutes' or p_now >= v_cutoff - interval '30 minutes' then
      return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'reason', 'outside the seed window');
    end if;
    v_closed := public.fn_invite_placement_day_closed(p_now);
    if v_closed is not null then
      return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'reason', v_closed);
    end if;

    select coalesce(max(value) filter (where key = 'invite_subject'), ''),
           coalesce(max(value) filter (where key = 'invite_body'), ''),
           coalesce(nullif(max(value) filter (where key = 'public_site_url'), ''), 'https://quotesdone.com')
      into v_subject, v_body, v_site
      from public.app_secrets where key in ('invite_subject', 'invite_body', 'public_site_url');
    v_from := public.fn_invite_placement_sender();
    -- The body exactly as scripts/invitation_inbox_check.mjs inviteBody() fills it: a ZZ DEMO company and a
    -- zero portal token. The token goes in the subject, the one field both the Gmail and Graph APIs match
    -- without a full-text index lag.
    v_token := 'QD' || upper(substr(md5(gen_random_uuid()::text), 1, 10));
    v_subject := v_subject || ' (ref ' || v_token || ')';
    v_body := replace(replace(v_body, '{{company}}', 'ZZ DEMO Supplier'),
                      '{{link}}', v_site || '/en/portal?t=00000000-0000-0000-0000-000000000000');

    insert into public.invite_placement_check(dubai_day, token, from_address, subject, gmail_to, outlook_to, queued_at)
    values (v_day, v_token, v_from, v_subject, 'ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com', p_now)
    returning * into r;

    insert into public.notifications (type, to_email, to_role, subject, body, lang, status, requested_by)
    values ('supplier_invite_seed', r.gmail_to, 'supplier', v_subject, v_body, 'en', 'queued', 'it_engineer')
    returning id into v_g;
    insert into public.notifications (type, to_email, to_role, subject, body, lang, status, requested_by)
    values ('supplier_invite_seed', r.outlook_to, 'supplier', v_subject, v_body, 'en', 'queued', 'it_engineer')
    returning id into v_o;
    update public.invite_placement_check set gmail_notification_id = v_g, outlook_notification_id = v_o
     where dubai_day = v_day;
    return jsonb_build_object('action', 'queued', 'dubai_day', v_day);
  end if;

  if r.verdict <> 'pending' then
    return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'verdict', r.verdict);
  end if;
  if p_now >= v_cutoff then
    return jsonb_build_object('action', 'settled', 'dubai_day', v_day, 'verdict', public.fn_invite_placement_settle(v_day, p_now));
  end if;

  select status into v_sg from public.notifications where id = r.gmail_notification_id;
  select status into v_so from public.notifications where id = r.outlook_notification_id;
  return jsonb_build_object('action', 'read', 'dubai_day', v_day, 'token', r.token, 'since', r.queued_at,
    'sender', lower(coalesce(substring(r.from_address from '<([^<>[:space:]]+@[^<>[:space:]]+)>'), btrim(r.from_address))),
    'gmail', jsonb_build_object('to', r.gmail_to, 'sent', v_sg = 'sent', 'folder', r.gmail_folder),
    'outlook', jsonb_build_object('to', r.outlook_to, 'sent', v_so = 'sent', 'folder', r.outlook_folder));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_finding(p_day date, p_verdict text, p_why text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key constant text := 'deliverability:inbox_placement';
begin
  if exists (select 1 from public.it_engineer_finding
              where issue_key = v_key and closed_at is null
                and evidence ->> 'dubai_day' = p_day::text and evidence ->> 'verdict' = p_verdict) then
    return;
  end if;
  perform public.fn_it_engineer_finding_upsert(v_key,
    left(case when p_verdict in ('spam', 'elsewhere') then 'Supplier invitation seed misplaced (batch still sending): '
              else 'Supplier invitations held: ' end || p_why, 300),
    'supplier invitation inbox placement: the daily seed to the Gmail and Microsoft 365 seed inboxes',
    'customer_facing', 1,
    coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('dubai_day', p_day, 'verdict', p_verdict),
    array['the seed goes through the real path: send_outbox, the effective From (invitation lane or email_from_supplier), Reply-To and frame'],
    case p_verdict
      when 'unread' then array['whether the Gmail / Microsoft Graph credentials in app_secrets are present and still consented',
                               'whether the itintegrations heartbeat step ran between 04:30 and 08:00 UTC']
      when 'not_sent' then array['why send_outbox did not send the seed (email_enabled, supplier_emails_enabled, the daily cap)',
                                 'invite_lane_domain_unverified: with the invitation lane on, send_outbox holds the seed while the lane''s domain is not verified in Resend']
      when 'no_check' then array['whether the itintegrations heartbeat step ran between 04:30 and 08:00 UTC, or resilience_ping is deployed without the placement code',
                                 'invite_lane_domain_unverified, if the lane is on']
      when 'not_found' then array['whether a mailbox rule moved or deleted the seed', 'whether the seed arrived from a different From than the one recorded']
      else array['which content, sender or domain signal the mailbox provider acted on'] end,
    'it_engineer');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_gate(p_day date DEFAULT NULL::date, p_now timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_day date := coalesce(p_day, (p_now at time zone 'Asia/Dubai')::date);
  r public.invite_placement_check; v text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;
  if r.dubai_day is null then
    if p_now < public.fn_invite_placement_cutoff(v_day) then return 'wait'; end if;
    if public.fn_invite_placement_day_closed(p_now) is null then
      perform public.fn_invite_placement_finding(v_day, 'no_check',
        'no inbox placement check ran on ' || v_day || ', an open sending day',
        jsonb_build_object('checked_at', p_now, 'sender', public.fn_invite_placement_sender()));
    end if;
    return 'fail:no_check';
  end if;
  v := r.verdict;
  if v = 'pending' then
    if p_now < public.fn_invite_placement_cutoff(v_day) then return 'wait'; end if;
    v := public.fn_invite_placement_settle(v_day, p_now);
  end if;
  -- A measured placement lets the batch go, junk included (ledger 1001); only a failure to measure holds it.
  if v not in ('inbox', 'spam', 'elsewhere') then return 'fail:' || v; end if;
  if public.fn_invite_placement_sender() is distinct from r.from_address then return 'fail:from_changed'; end if;
  return 'pass';
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_record(p_day date, p_gmail jsonb, p_outlook jsonb, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_g text := nullif(p_gmail ->> 'folder', ''); v_o text := nullif(p_outlook ->> 'folder', ''); v text;
begin
  update public.invite_placement_check
     set gmail_folder   = case when v_g is null or (v_g = 'not_found' and gmail_folder is not null and gmail_folder <> 'not_found')
                               then gmail_folder else v_g end,
         outlook_folder = case when v_o is null or (v_o = 'not_found' and outlook_folder is not null and outlook_folder <> 'not_found')
                               then outlook_folder else v_o end,
         gmail_detail   = case when p_gmail is null then gmail_detail else coalesce(p_gmail -> 'detail', '{}'::jsonb) end,
         outlook_detail = case when p_outlook is null then outlook_detail else coalesce(p_outlook -> 'detail', '{}'::jsonb) end,
         reads = reads + 1, last_read_at = p_now
   where dubai_day = p_day and verdict = 'pending';
  if not found then
    return jsonb_build_object('recorded', false, 'dubai_day', p_day, 'reason', 'no pending check for this day');
  end if;
  v := public.fn_invite_placement_settle(p_day, p_now);
  return jsonb_build_object('recorded', true, 'dubai_day', p_day, 'verdict', v);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_sender()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_lane_enabled'), 'false') = 'true'
     and coalesce((select btrim(value) from public.app_secrets where key = 'invite_lane_from'), '') <> ''
      then (select btrim(value) from public.app_secrets where key = 'invite_lane_from')
    else coalesce(nullif((select btrim(value) from public.app_secrets where key = 'email_from_supplier'), ''),
                  'QuotesDone <supplier@quotesdone.com>')
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_placement_settle(p_day date, p_now timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.invite_placement_check;
  v text; v_sent_g text; v_sent_o text; v_why text; v_ev jsonb; v_lane text; v_handoff bigint; h record;
begin
  select * into r from public.invite_placement_check where dubai_day = p_day for update;
  if r.dubai_day is null or r.verdict <> 'pending' then return r.verdict; end if;

  if 'spam' in (r.gmail_folder, r.outlook_folder) then v := 'spam';
  elsif r.gmail_folder in ('trash', 'other') or r.outlook_folder in ('trash', 'other') then v := 'elsewhere';
  elsif r.gmail_folder = 'inbox' and r.outlook_folder = 'inbox' then v := 'inbox';
  elsif p_now >= public.fn_invite_placement_cutoff(p_day) then
    select status into v_sent_g from public.notifications where id = r.gmail_notification_id;
    select status into v_sent_o from public.notifications where id = r.outlook_notification_id;
    v := case when coalesce(v_sent_g, '') <> 'sent' or coalesce(v_sent_o, '') <> 'sent' then 'not_sent'
              when r.gmail_folder is null or r.outlook_folder is null then 'unread'
              else 'not_found' end;
  else
    return 'pending';
  end if;

  if v = 'inbox' then
    update public.invite_placement_check set verdict = v, decided_at = p_now where dubai_day = p_day;
    perform public.fn_it_engineer_finding_close('deliverability:inbox_placement',
      'the seed of ' || p_day || ' landed in the Inbox of both seed mailboxes (token ' || r.token || ')');
    -- The fix is proved by a placement: it_engineer closes marketing's open placement handoffs.
    for h in select a.id from public.agent_actions a
              where a.kind = 'handoff' and a.agent = 'marketing' and a.status <> 'done'
                and a.detail ->> 'type' = 'deliverability.inbox_placement' and a.detail ->> 'from' = 'it_engineer'
    loop
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'it_engineer', 'verified_at', now(),
        'proof', 'the seed of ' || p_day || ' landed in the Inbox of both seed mailboxes'));
      perform set_config('qd.handoff_closer', '', true);
    end loop;
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v),
            'Inbox placement ' || p_day || ': Gmail inbox, Outlook inbox; the batch may send.', now(), now());
    return v;
  end if;

  v_why := 'the inbox placement seed of ' || p_day || ' '
    || case v when 'spam' then 'landed in spam/junk'
              when 'elsewhere' then 'did not land in the Inbox'
              when 'not_sent' then 'was not sent by the read cutoff'
              when 'unread' then 'could not be read back from a seed mailbox'
              else 'was not found in a seed mailbox' end
    || ' (Gmail ' || coalesce(r.gmail_folder, 'unread') || ', Outlook ' || coalesce(r.outlook_folder, 'unread') || ')';
  v_lane := case when coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_lane_enabled'), '') = 'true'
                 then 'invitation_lane' else 'email_from_supplier' end;
  v_ev := jsonb_build_object('token', r.token, 'from', r.from_address, 'sender_lane', v_lane, 'subject', r.subject,
            'diagnosis', jsonb_build_object('gmail', coalesce(r.gmail_detail -> 'messages', '[]'::jsonb),
                                            'outlook', coalesce(r.outlook_detail -> 'messages', '[]'::jsonb)),
            'gmail', jsonb_build_object('to', r.gmail_to, 'folder', r.gmail_folder, 'detail', r.gmail_detail,
                                        'notification_id', r.gmail_notification_id, 'status', v_sent_g),
            'outlook', jsonb_build_object('to', r.outlook_to, 'folder', r.outlook_folder, 'detail', r.outlook_detail,
                                          'notification_id', r.outlook_notification_id, 'status', v_sent_o),
            'reads', r.reads);
  update public.invite_placement_check set verdict = v, decided_at = p_now, paused = false where dubai_day = p_day;
  perform public.fn_invite_placement_finding(p_day, v, v_why, v_ev);
  if v in ('spam', 'elsewhere') then
    -- A provider's placement: diagnose and hand the cause to marketing; the batch sends (ledger 1001).
    v_handoff := public.fn_seat_handoff('it_engineer', 'marketing', 'deliverability.inbox_placement',
      'invite_placement_check', p_day::text, v_ev || jsonb_build_object('dubai_day', p_day, 'verdict', v, 'why', v_why));
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'warn', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v, 'paused', false,
                                                      'handoff_id', v_handoff, 'sender_lane', v_lane),
            'MISPLACED: ' || v_why || '; the day''s batch still sends, diagnosis filed in deliverability:inbox_placement, marketing handoff ' || v_handoff || ' opened.', now(), now());
  else
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'warn', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v, 'paused', false),
            'HELD: ' || v_why || '; the day''s batch does not go, invite_enabled untouched, finding deliverability:inbox_placement filed.', now(), now());
  end if;
  return v;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_ramp()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_base int     := coalesce((c->>'base_cap')::int, 30);
  v_ceiling int  := coalesce((c->>'ceiling_cap')::int, 200);
  v_growth numeric := coalesce((c->>'growth_factor')::numeric, 1.5);
  v_used_pct numeric := coalesce((c->>'grow_if_used_pct')::numeric, 0.8);
  v_ok_b numeric := coalesce((c->>'grow_max_bounce_rate')::numeric, 0.02);
  v_ok_c numeric := coalesce((c->>'grow_max_complaint_rate')::numeric, 0.001);
  v_back_b numeric := coalesce((c->>'backoff_bounce_rate')::numeric, 0.035);
  v_back_n int   := coalesce((c->>'backoff_min_sends')::int, 20);
  v_pause_c numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_pause_n int  := coalesce((c->>'pause_min_complaints')::int, 2);
  v_cur int; v_new int; v_note text; v_status text := 'ok';
  v_sent_total int; v_last_sent timestamptz; v_last_day date; v_last_day_sent int;
  v_s48 int; v_b48 int; v_c48 int; v_br numeric; v_cr numeric;
  v_restart boolean := false; v_prev_restart boolean; v_grew_since boolean; v_uncontacted int;
  -- THE LANE'S OWN HISTORY (24 Sep 2026): '-infinity' while invite_lane_enabled is off (every scope below is
  -- then a no-op); the activation stamp while it is on, so the new subdomain restarts at day 1.
  v_since timestamptz := public.fn_invite_lane_since();
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key = 'invite_daily_cap'), v_base);

  -- PAUSED IS A REPORTABLE STATE: a paused campaign files a row and leaves the cap alone. The daily tick
  -- calls this only on open days, so the previous body's daily "campaign paused" warning (which, called
  -- every day of a founder's deliberate hold, would page him daily) is not carried over.
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    select count(*) into v_uncontacted from leads where invited_at is null and coalesce(btrim(email),'') <> '';
    insert into agent_runs(agent, status, counts, note, finished_at)
    values ('invite_ramp', 'ok', jsonb_build_object('paused', true, 'cap', v_cur, 'uncontacted_with_email', v_uncontacted),
            'PAUSED: invite_enabled is false; cap left at ' || v_cur || '.', now());
    return v_cur;
  end if;

  select count(*), max(invited_at) into v_sent_total, v_last_sent from leads where invited_at is not null and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
  -- THE 48 h HEALTH READ IS NOT LANE-SCOPED (review of #963): complaints and bounces reflect the list and the
  -- copy, not the domain, so switching the lane on must never hide yesterday's complaints from the pause.
  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_s48, v_b48, v_c48
    from leads where invited_at > now() - interval '48 hours' and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
  v_br := v_b48::numeric / greatest(v_s48, 1);
  v_cr := v_c48::numeric / greatest(v_s48, 1);

  if v_c48 >= v_pause_n and v_cr >= v_pause_c then
    -- SPAM COMPLAINTS STOP THE CAMPAIGN. Gmail and Yahoo reject bulk senders above 0.3%; two people
    -- pressing "spam" inside 48 hours is not noise at this volume.
    update app_secrets set value = 'false' where key = 'invite_enabled';
    v_new := v_base; v_status := 'error';
    v_note := 'PAUSED ON COMPLAINTS: ' || v_c48 || ' spam complaint(s) on ' || v_s48 || ' invitation(s) in 48 h ('
              || round(v_cr * 100, 2) || '% >= ' || round(v_pause_c * 100, 2) || '%). invite_enabled set to false; cap reset to base '
              || v_base || '.';
    if not exists (select 1 from founder_alerts where event = 'invite_paused_complaints' and created_at > now() - interval '24 hours') then
      insert into founder_alerts(level, event, detail, channel)
      values ('crit', 'invite_paused_complaints', 'Supplier invites AUTO-PAUSED: ' || v_note || ' Read the complaints before resuming.', 'system');
    end if;
  elsif v_last_sent is null or v_last_sent < now() - interval '3 days' then
    -- A RESTART, NOT A STALL. After days of silence the domain is cold again, so it starts at the base.
    -- It is a stall only if the previous run was ALSO a restart and still nothing has been issued.
    -- A lane that has just been switched on has issued nothing yet, so it lands here: day 1 of its own ramp.
    v_restart := true; v_new := v_base;
    select coalesce((a.counts->>'restart')::boolean, false) into v_prev_restart
      from agent_runs a where a.agent = 'invite_ramp' and coalesce((a.counts->>'paused')::boolean, false) = false
     order by a.id desc limit 1;
    v_note := 'restart: nothing issued since ' || coalesce(to_char(v_last_sent at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z', 'ever')
              || case when v_since > '-infinity'::timestamptz
                      then ' on the invitation lane (switched on ' || to_char(v_since at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z)' else '' end
              || '; cap set to the base ' || v_base || '.';
    if coalesce(v_prev_restart, false) then
      v_status := 'error';
      v_note := 'STALLED: the previous run was already a restart and nothing has been issued since. ' || v_note;
      if not exists (select 1 from founder_alerts where event = 'invite_sender_stalled' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_sender_stalled', 'Supplier invites: ' || v_note || ' invite_enabled is true, so the enqueuer or the outbox is failing.', 'system');
      end if;
    end if;
  elsif v_s48 >= v_back_n and (v_br >= v_back_b or v_c48 >= 1) then
    v_new := greatest(v_base, floor(v_cur * 0.5)::int);
    v_note := 'back off: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaints ' || v_c48
              || '; cap ' || v_cur || '->' || v_new || '.';
    if v_new = v_cur then
      v_status := 'error';
      if not exists (select 1 from founder_alerts where event = 'invite_throttle_exhausted' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_throttle_exhausted', 'Supplier invites: ' || v_note || ' The cap is already at its base; the hard brake pauses at '
                || round(coalesce((select nullif(value,'')::numeric from app_secrets where key = 'invite_max_bounce_rate'), 0.05) * 100, 1) || '%.', 'system');
      end if;
    end if;
  elsif v_br >= v_ok_b or v_cr >= v_ok_c then
    v_new := v_cur;
    v_note := 'hold: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaint ' || round(v_cr * 100, 2)
              || '% — growth needs bounce < ' || round(v_ok_b * 100, 1) || '% and complaint < ' || round(v_ok_c * 100, 2) || '%.';
  else
    -- GROW ON VOLUME ISSUED, ONCE PER SEND DAY. Weekends and holidays run no batch, so a calendar-based
    -- ladder would ratchet on days the domain sent nothing.
    select max((invited_at at time zone 'Asia/Dubai')::date) into v_last_day from leads where invited_at is not null and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
    select count(*) into v_last_day_sent from leads where (invited_at at time zone 'Asia/Dubai')::date = v_last_day and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
    select exists (select 1 from agent_runs a where a.agent = 'invite_ramp' and a.finished_at > v_last_sent
                     and (a.counts->>'new_cap')::int > (a.counts->>'old_cap')::int) into v_grew_since;
    if v_grew_since then
      v_new := v_cur; v_note := 'hold: already grew once since the last send day.';
    elsif v_last_day_sent < ceil(v_cur * v_used_pct) then
      v_new := v_cur; v_note := 'hold: the last send day (' || v_last_day || ') issued ' || v_last_day_sent || ' of a cap of ' || v_cur
                                || '; growth needs ' || round(v_used_pct * 100) || '%.';
    else
      v_new := least(v_ceiling, ceil(v_cur * v_growth)::int);
      v_note := 'healthy: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaints ' || v_c48
                || '; last send day issued ' || v_last_day_sent || '; cap ' || v_cur || '->' || v_new || '.';
    end if;
  end if;

  v_new := greatest(v_base, least(v_new, v_ceiling));
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key = 'invite_daily_cap';
  end if;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_ramp', v_status,
          jsonb_build_object('old_cap', v_cur, 'new_cap', v_new, 'sent_total', v_sent_total, 'restart', v_restart,
                             'sent_48h', v_s48, 'bounced_48h', v_b48, 'complained_48h', v_c48,
                             'bounce_pct_48h', round(v_br * 100, 2), 'complaint_pct_48h', round(v_cr * 100, 3))
          || case when v_since > '-infinity'::timestamptz then jsonb_build_object('lane_since', v_since) else '{}'::jsonb end,
          v_note, now());
  if v_new < v_cur and not v_restart then
    insert into founder_alerts(level, event, detail, channel)
    values ('warn', 'invite_cap_throttled', 'Supplier-invite cap reduced ' || v_cur || '->' || v_new || ' — ' || v_note, 'system');
  end if;
  return v_new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_same_day_brake()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_br_max numeric := coalesce((c->>'same_day_pause_bounce_rate')::numeric, 0.05);
  v_b_min  int     := coalesce((c->>'same_day_pause_min_bounces')::int, 3);
  v_cr_max numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_c_min  int     := coalesce((c->>'same_day_pause_min_complaints')::int, 1);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_sent int; v_b int; v_c int; v_why text;
begin
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    return null;  -- already stopped; nothing more to stop
  end if;

  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_sent, v_b, v_c
    from leads
   where invited_at is not null and (invited_at at time zone 'Asia/Dubai')::date = v_day;

  if v_c >= v_c_min and v_c::numeric / greatest(v_sent, 1) >= v_cr_max then
    v_why := v_c || ' spam complaint(s) on ' || v_sent || ' invitation(s) today';
  elsif v_b >= v_b_min and v_b::numeric / greatest(v_sent, 1) >= v_br_max then
    v_why := v_b || ' bounce(s) on ' || v_sent || ' invitation(s) today (' || round(v_b * 100.0 / greatest(v_sent, 1), 1) || '%)';
  else
    return null;
  end if;

  perform public.fn_invite_campaign_pause('invite_same_day_brake', v_why,
    jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c),
    jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c));
  return null;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_invite_week_activate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.kind = 'invite_campaign_week'
     and NEW.status in ('approved','done','auto_done','accepted','resolved','closed','completed')
     and coalesce(OLD.status,'') is distinct from NEW.status then
    update invite_schedule set status='approved' where status='pending' and day >= (now() at time zone 'UTC')::date;
    update app_secrets set value='true' where key in ('invite_enabled','supplier_emails_enabled');
    insert into founder_alerts(level,event,detail,channel)
      values('info','invite_week_approved','Supplier invite week approved in OS — schedule activated and sending enabled.','system');
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_is_demo_email(p_email text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select coalesce(btrim(p_email), '') ~* '@([a-z0-9_-]+[.])*(example[.](com|net|org)|test|example|invalid|localhost)$'
$function$


CREATE OR REPLACE FUNCTION public.fn_is_demo_phone(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') ~ '^(971|0)5000000[0-9]{2}$'
$function$


CREATE OR REPLACE FUNCTION public.fn_is_matchable(p_verified boolean, p_banned boolean, p_matching_blocked boolean, p_approval_status text, p_permanently_closed boolean, p_chat_strikes integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_verified, false)                                        -- verified
     and coalesce(p_approval_status, '') = 'approved'                       -- and approved by the sales engineer
     and coalesce(p_banned, false) = false
     and coalesce(p_matching_blocked, false) = false                        -- expired documents, reconciled daily by
                                                                            -- fn_sales_engineer_supplier_documents_tick
     and coalesce(p_permanently_closed, false) = false                      -- never RFQ a closed business
     and coalesce(p_chat_strikes, 0) < public.fn_matching_strike_limit();   -- the no-response exception
$function$


CREATE OR REPLACE FUNCTION public.fn_is_sanctioned_lead(p_lead bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.sanctions_ban b where b.lead_id = p_lead);
$function$


CREATE OR REPLACE FUNCTION public.fn_is_working_day(p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select extract(isodow from p_date) < 6
     and not exists (select 1 from public.public_holidays h where h.holiday_date = p_date);
$function$


CREATE OR REPLACE FUNCTION public.fn_it_accepted_report_review(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rep public.support_ceo_report;
  v_family text; v_gone boolean; v_note text;
  -- HOW a report closed, never collapsed into one number (22 Sep 2026, review of PR #852):
  --   'measured'     the cause was measured GONE — a provider id, a delivered status, a confirmed
  --                  twin, coverage ok, a closed handoff.
  --   'unmeasurable' the cause can never be re-checked because its subject is not there: the
  --                  report names no notification, or the notification row no longer exists. That
  --                  is the ABSENCE of evidence, not evidence, and an auditor reading the
  --                  completion record must be able to tell the two apart.
  v_kind text;
  v_closed_measured int := 0; v_closed_unmeasurable int := 0;
  v_cov jsonb; v_cov_read boolean := false; v_loop_run boolean := false;
  v_nid bigint; v_notif public.notifications; v_twin public.notifications;
  v_status text; v_open bigint[] := '{}'; v_closed int := 0; v_due int := 0;
begin
  for rep in select * from public.support_ceo_report
              where status = 'accepted' and next_review_at is not null and next_review_at < now()
              order by id loop
    v_due := v_due + 1;
    v_family := split_part(rep.idempotency_key, ':', 1);
    v_gone := false; v_note := null; v_kind := null;

    if v_family = 'delivery_undelivered' then
      v_nid := coalesce((rep.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                        (rep.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
      if v_nid is null then
        v_gone := true; v_kind := 'unmeasurable';
        v_note := 'the report names no notification at all, so its delivery can never be re-checked; '
                  || 'nothing is left to deliver and nothing can recur under this id.';
      else
        select * into v_notif from public.notifications where id = v_nid;
        if v_notif.id is null then
          v_gone := true; v_kind := 'unmeasurable';
          v_note := 'notification ' || v_nid || ' no longer exists in public.notifications, so its delivery can never be re-checked.';
        elsif coalesce(btrim(v_notif.provider_message_id), '') <> ''
              or v_notif.provider_status in ('delivered', 'read') then
          v_gone := true; v_kind := 'measured';
          v_note := 'notification ' || v_nid || ' (' || v_notif.channel || ') now carries provider id '
                    || coalesce(v_notif.provider_message_id, '-') || ' and provider status '
                    || coalesce(v_notif.provider_status, '-') || ': the alert reached the founder.';
        else
          select * into v_twin from public.notifications t
           where t.channel = 'email' and t.type = v_notif.type and t.created_at = v_notif.created_at
             and t.to_role is not distinct from v_notif.to_role and t.id <> v_notif.id and t.status = 'sent'
           order by t.id limit 1;
          if v_twin.id is not null and coalesce(btrim(v_twin.provider_message_id), '') <> '' then
            v_gone := true; v_kind := 'measured';
            v_note := 'notification ' || v_nid || ' is still unconfirmed on ' || v_notif.channel
                      || ', but its email twin ' || v_twin.id || ' was sent and confirmed ('
                      || v_twin.provider_message_id || '): the alert reached the founder.';
          end if;
        end if;
      end if;

    elsif v_family in ('dropbox_backup_escalation', 'dropbox_backup_daily', 'backup_escalation') then
      if not v_cov_read then
        -- once per run: this reads the whole backup queue and rolls back its own enqueue probe
        begin v_cov := public.fn_backup_coverage();
        exception when others then v_cov := jsonb_build_object('ok', null, 'error', left(sqlerrm, 200)); end;
        v_cov_read := true;
      end if;
      if coalesce((v_cov ->> 'ok')::boolean, false) then
        v_gone := true; v_kind := 'measured';
        v_note := 'backup coverage measured ok at review (' || left(v_cov::text, 400) || ').';
      end if;

    elsif v_family = 'it_loop' then
      if not p_dry_run and not v_loop_run then
        begin perform public.fn_it_loop_reverify(); exception when others then null; end;
        v_loop_run := true;
      end if;
      select status into v_status from public.support_ceo_report where id = rep.id;
      if v_status = 'completed' then v_closed := v_closed + 1; v_closed_measured := v_closed_measured + 1; continue; end if;
      -- still accepted: its handoff has not closed, so the finding behind it is still open
    end if;

    if v_gone then
      v_closed := v_closed + 1;
      if v_kind = 'unmeasurable' then v_closed_unmeasurable := v_closed_unmeasurable + 1;
      else v_closed_measured := v_closed_measured + 1; end if;
      if not p_dry_run then
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer reviewed this accepted report at its review date ('
                 || to_char(now() at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai, closed as ' || v_kind || '): ' || v_note
         where id = rep.id and status = 'accepted';
      end if;
    else
      v_open := v_open || rep.id;
      if not p_dry_run then
        update public.support_ceo_report set next_review_at = now() + interval '24 hours' where id = rep.id;
      end if;
    end if;
  end loop;

  -- ONE finding for everything still unanswered, named by id so the CEO can answer them.
  if cardinality(v_open) > 0 and not p_dry_run then
    perform public.fn_it_engineer_finding_upsert(
      'monitor:ceo_accepted_report_review_overdue',
      cardinality(v_open) || ' accepted CEO report(s) passed their review date and their cause is still there',
      'public.support_ceo_report (status accepted, next_review_at past)', 'agent_facing', cardinality(v_open),
      jsonb_build_object('report_ids', to_jsonb(v_open), 'owner_seat', 'ceo',
        'measured', 'the cause each report was about was measured at review and is still present; each review date moved 24 h',
        'fix', 'the CEO answers each report — complete it with what changed, or say what is still being done and why'),
      '{}'::text[], array['what the CEO intends to do about each report still open'], 'fn_it_accepted_report_review');
  end if;

  return jsonb_build_object('due', v_due, 'closed', v_closed,
                            'closed_measured', v_closed_measured, 'closed_unmeasurable', v_closed_unmeasurable,
                            'still_open', cardinality(v_open),
                            'open_ids', to_jsonb(v_open), 'dry_run', p_dry_run,
                            'coverage_read', v_cov_read, 'coverage_ok', v_cov -> 'ok');
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_access_accept(p_system text, p_principal text, p_reason text, p_accepted_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_reason), '') = '' or coalesce(btrim(p_accepted_by), '') = '' then
    raise exception 'fn_it_access_accept: accepting access needs a reason and who accepted it';
  end if;
  insert into public.it_access_known (system, principal, reason, accepted_by)
  values (p_system, p_principal, p_reason, p_accepted_by)
  on conflict (system, principal) do update set reason = excluded.reason, accepted_by = excluded.accepted_by, accepted_at = now();
  return jsonb_build_object('ok', true, 'system', p_system, 'principal', p_principal);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_access_items(p_access jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; e jsonb; v_items jsonb := '[]'::jsonb; k public.it_access_known;
begin
  for x in select key, value from jsonb_each(p_access) loop
    continue when coalesce(x.value->>'basis', '') <> 'measured';
    for e in select p from jsonb_array_elements(coalesce(x.value->'principals', '[]'::jsonb)) p loop
      select * into k from public.it_access_known where system = x.key and principal = e->>'principal';
      if k.principal is null then
        v_items := v_items || jsonb_build_object('item', x.key || ':' || (e->>'principal'), 'owner_seat', 'ceo', 'subject', x.key,
          'title', (e->>'principal') || ' has ' || coalesce(e->>'role', 'access') || ' on ' || x.key || ' and nobody has accepted it',
          'blast', 'security', 'affected', 1,
          'evidence', jsonb_build_object('system', x.key, 'principal', e->>'principal', 'role', e->>'role',
                                         'accept', 'select public.fn_it_access_accept(system, principal, reason, accepted_by)'));
      else
        update public.it_access_known set last_seen_at = now() where system = k.system and principal = k.principal;
        if k.accepted_at < now() - make_interval(days => public.fn_it_threshold('access_reconfirm_days')::int) then
          v_items := v_items || jsonb_build_object('item', x.key || ':' || k.principal || ':reconfirm', 'owner_seat', 'ceo', 'subject', x.key,
            'title', k.principal || '''s access on ' || x.key || ' was accepted on ' || k.accepted_at::date || ' and is due to be reconfirmed',
            'blast', 'agent_facing', 'affected', 0, 'evidence', to_jsonb(k));
        end if;
      end if;
    end loop;
  end loop;
  return v_items;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_attach_learning(p_handoff_id bigint, p_cause text, p_fix text, p_regression_check text, p_playbook_class text DEFAULT NULL::text, p_not_automatable_reason text DEFAULT NULL::text, p_recorded_by text DEFAULT 'it_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.it_incident; h public.agent_actions; f public.it_engineer_finding; v_closed boolean := false;
begin
  if coalesce(btrim(p_cause), '') = '' or coalesce(btrim(p_fix), '') = '' or coalesce(btrim(p_regression_check), '') = '' then
    raise exception 'fn_it_attach_learning: the cause, the fix and the regression check are all required';
  end if;
  if p_playbook_class is null and coalesce(btrim(p_not_automatable_reason), '') = '' then
    raise exception 'fn_it_attach_learning: name the playbook entry for this failure class, or say why it cannot be automated';
  end if;
  if p_playbook_class is not null and not exists (select 1 from public.it_playbook where failure_class = p_playbook_class) then
    raise exception 'fn_it_attach_learning: no playbook entry %; add it to public.it_playbook first', p_playbook_class;
  end if;
  update public.it_incident
     set cause = p_cause, fix = p_fix, regression_check = p_regression_check, playbook_class = p_playbook_class,
         not_automatable_reason = p_not_automatable_reason, recorded_by = p_recorded_by, updated_at = now()
   where handoff_id = p_handoff_id
  returning * into i;
  if not found then raise exception 'fn_it_attach_learning: handoff % has no incident record', p_handoff_id; end if;

  select * into h from public.agent_actions where id = p_handoff_id;
  select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
  if h.status <> 'done' and (f.issue_key is null or f.closed_at is not null
                             or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz) then
    perform set_config('qd.handoff_closer', 'it_engineer', true);
    perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
      'verified_by', 'it_engineer', 'verified_at', now(), 'incident_id', i.id, 'learning_recorded_by', p_recorded_by));
    perform set_config('qd.handoff_closer', '', true);
    update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where id = i.id;
    v_closed := true;
  end if;
  return jsonb_build_object('ok', true, 'incident_id', i.id, 'closed', v_closed,
    'note', case when v_closed then 'recorded and closed' else 'recorded; the loop closes it once the IT engineer sees the finding gone' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_check(p_results jsonb, p_job text DEFAULT 'dropbox_daily_check'::text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r jsonb; v_id bigint; v_out text; f jsonb := '[]'::jsonb; x record; d public.doc_backups;
  n_ok int := 0; n_unver int := 0; n_err int := 0; v_h bigint; v_status text; c jsonb;
  v_weekly boolean := exists (select 1 from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) e where e->>'why' = 'weekly');
begin
  if p_error is not null then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'error', jsonb_build_object('job', p_job, 'stage', 'fatal'),
            left('The IT engineer''s Dropbox check did not run: ' || p_error || '. Retried after 6 hours.', 500), now(), now());
    return jsonb_build_object('ok', false, 'error', p_error);
  end if;

  -- (2) doc_backups vs Dropbox
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    v_id := (r->>'id')::bigint; v_out := r->>'outcome';
    if v_out = 'ok' then
      update public.doc_backups set dropbox_content_hash = r->>'hash', dropbox_size = (r->>'size')::bigint, verified_at = now()
       where id = v_id and status = 'done';
      n_ok := n_ok + 1;
    elsif v_out in ('missing', 'changed') then
      update public.doc_backups set verified_at = null,
             error = case when v_out = 'missing' then 'it_engineer: missing in Dropbox' else 'it_engineer: size/content_hash in Dropbox differs' end
       where id = v_id returning * into d;
      if found then
        f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', case when v_out = 'missing' then 'missing_in_dropbox' else 'mismatch' end,
               'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path, 'bucket', d.bucket, 'path', d.path, 'demo', d.entity = 'zz_demo');
      end if;
    elsif v_out = 'unverifiable' then n_unver := n_unver + 1;
    else n_err := n_err + 1;
    end if;
  end loop;

  if p_job = 'dropbox_daily_check' then
    -- (1) expected vs doc_backups: never queued, past a 24-hour grace
    for x in select * from public.fn_it_backup_expected_status() s
              where s.doc_backup_id is null and s.since < now() - interval '24 hours' loop
      f := f || jsonb_build_object('key', 'exp:' || x.item_key, 'reason', 'never_queued', 'item_key', x.item_key, 'kind', x.kind,
             'bucket', x.bucket, 'path', x.path, 'gen_kind', x.gen_kind, 'gen_ref', x.gen_ref, 'owner', x.owner, 'demo', false);
    end loop;
    -- (3) the uploader gave up
    for d in select * from public.doc_backups b
              where b.entity <> 'zz_demo' and ((b.status = 'error' and b.attempts >= 5) or b.status = 'skipped_large') loop
      f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', 'upload_failed', 'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path,
             'bucket', d.bucket, 'path', d.path, 'error', d.error, 'demo', false);
    end loop;
  end if;

  -- a file already in an open refile or remediation is not handed over twice
  select coalesce(jsonb_agg(e), '[]'::jsonb) into f
    from jsonb_array_elements(f) e
   where not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' in ('backup.refile', 'backup.remediate')
                        and exists (select 1 from jsonb_array_elements(a.detail->'files') g where g->>'key' = e->>'key'));

  if jsonb_array_length(f) > 0 then
    v_h := public.fn_seat_handoff('it_engineer', 'sales_engineer', 'backup.refile', 'doc_backups',
             'check:' || p_job || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
             jsonb_build_object('files', f, 'job', p_job, 'refile_attempts', 0));
  end if;

  c := jsonb_build_object('job', p_job, 'weekly', v_weekly, 'checked', jsonb_array_length(coalesce(p_results, '[]'::jsonb)),
         'confirmed', n_ok, 'unverifiable', n_unver, 'read_errors', n_err, 'findings', jsonb_array_length(f),
         'by_reason', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select e->>'reason' k, count(*) n from jsonb_array_elements(f) e group by 1) z),
         'handoff', v_h);
  v_status := case when jsonb_array_length(f) + n_err > 0 then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, c,
          left('IT engineer Dropbox check (' || p_job || '): ' || (c->>'checked') || ' read in Dropbox, ' || n_ok || ' confirmed, '
               || jsonb_array_length(f) || ' finding(s) ' || (c->>'by_reason')
               || case when v_h is not null then ', handed to the sales engineer as handoff ' || v_h else '' end || '.', 500),
          now(), now());
  return c || jsonb_build_object('status', v_status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_expected()
 RETURNS TABLE(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with rl as (select * from public.leads where not coalesce(is_demo, false)),
       rc as (select * from public.customers where not coalesce(is_demo, false)),
       ri as (select i.* from public.inquiries i join rc on rc.id = i.customer_id),
  base as (
  select 'obj:' || o.bucket_id || ':' || o.name as item_key, 'storage' as kind, o.bucket_id as bucket, o.name as path,
         null::text as gen_kind, null::text as gen_ref, x.owner, o.created_at as since
    from storage.objects o
    cross join lateral (select case
      when o.bucket_id = 'supplier-docs' then (select 'supplier:' || l.id from rl l
             where l.id::text = split_part(o.name, '/', 2)
                or o.name in (l.license_doc_path, l.egr_doc_path, l.insurance_doc_path, l.vat_doc_path,
                              l.iso_doc_path, l.manufacturer_auth_doc_path, l.company_profile_doc_path)
                or o.name = any(coalesce(l.catalog_doc_paths, '{}')) limit 1)
      when o.bucket_id = 'signed-terms' then coalesce(
             (select 'customer:' || c.id from rc c where c.signed_terms_path = o.name limit 1),
             (select 'supplier:' || l.id from rl l where l.signed_terms_path = o.name limit 1))
      when o.bucket_id = 'drawing-files' then (select 'inquiry:' || i.id from ri i
             where i.id::text = split_part(o.name, '/', 2) or i.drawing_file_path = o.name limit 1)
      when o.bucket_id = 'finance-docs' then (select 'transaction:' || t.id from public.transactions t where t.doc_path = o.name limit 1)
    end as owner) x
   where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r where r.kind = 'bucket' and r.backed_up)
     and x.owner is not null and o.name !~* 'zz[_ -]?demo'
  union all
  -- a Stripe invoice the transaction names but storage no longer holds is still expected
  select 'obj:finance-docs:' || t.doc_path, 'invoice', 'finance-docs', t.doc_path, null, null, 'transaction:' || t.id, t.revealed_at
    from public.transactions t
    -- transactions carries no is_demo of its own: a sale is demo when either party is (review of
    -- #628). Without this, a purged demo invoice would read never_queued forever and escalate.
    left join public.customers tc on tc.id = t.customer_id
    left join public.leads tl on tl.id = t.supplier_id
   where t.doc_path is not null
     and not coalesce(tc.is_demo, false) and not coalesce(tl.is_demo, false)
     and coalesce(tc.email, '') !~* 'example\.invalid' and coalesce(tl.email, '') !~* 'example\.invalid'
     and not exists (select 1 from storage.objects o where o.bucket_id = 'finance-docs' and o.name = t.doc_path)
  union all
  select 'msg:' || m.source_table || ':' || m.source_id, 'conversation', c.pdf_bucket, c.pdf_path, null, null,
         coalesce(m.party_kind || ':' || m.party_id, 'company'), m.occurred_at
    from public.v_conversation_message m
    left join public.conversation_archive c on c.source_table = m.source_table and c.source_id = m.source_id
   where not m.is_demo
  union all
  select 'gen:supplier_details:' || l.id, 'generated', null, null, 'supplier_details', l.id::text, 'supplier:' || l.id, l.created_at
    from rl l
   where l.approved_at is not null or l.registration_submitted_at is not null or l.signed_terms_path is not null
      or l.company_profile_doc_path is not null or l.license_doc_path is not null or coalesce(l.claimed, false)
  union all
  select 'gen:customer_details:' || c.id, 'generated', null, null, 'customer_details', c.id::text, 'customer:' || c.id, c.created_at from rc c
  union all
  select 'gen:inquiry_summary:' || i.id, 'generated', null, null, 'inquiry_summary', i.id::text, 'inquiry:' || i.id, i.created_at from ri i
  union all
  -- ── ACCOUNTING (14 Sep 2026, accountant duty 4): what fn_enqueue_doc_backups files under Finance ──
  select 'obj:' || c.pdf_bucket || ':' || v.path, 'storage', c.pdf_bucket, v.path, null, null,
         'finance:close:' || to_char(c.month, 'YYYY-MM'), c.rendered_at
    from public.accountant_month_close c cross join lateral (values (c.pdf_path), (c.csv_path)) v(path)
   where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path, '')) > 0
  union all
  select 'obj:' || split_part(b.doc_path, '/', 1) || ':' || substr(b.doc_path, strpos(b.doc_path, '/') + 1), 'storage',
         split_part(b.doc_path, '/', 1), substr(b.doc_path, strpos(b.doc_path, '/') + 1), null, null,
         'finance:bank_statement:' || b.source_ref, b.received_at
    from public.bank_statement_intake b
   where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  union all
  select 'obj:' || split_part(d.file_path, '/', 1) || ':' || substr(d.file_path, strpos(d.file_path, '/') + 1), 'storage',
         split_part(d.file_path, '/', 1), substr(d.file_path, strpos(d.file_path, '/') + 1), null, null,
         'finance:issued:' || d.id, d.issued_at
    from public.accountant_issued_document d
   where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  union all
  select 'obj:' || (f->>'bucket') || ':' || (f->>'path'), 'storage', f->>'bucket', f->>'path', null, null,
         'finance:year_end:' || p.year, p.rendered_at
    from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
   where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  union all
  -- ── TABLE EXPORTS (14 Sep 2026): each Asia/Dubai day from the first the revived writer ran ──
  -- due from 03:00 Dubai that day; the expected-status grace then decides when a gap is a finding
  select 'obj:backups:' || f.path, 'storage', 'backups', f.path, null, null,
         'company:table_export:' || to_char(d.day, 'YYYY-MM-DD'), (d.day::date + time '03:00') at time zone 'Asia/Dubai'
    from generate_series((select min(r.stamp) from public.table_export_run r),
                         (now() at time zone 'Asia/Dubai')::date, interval '1 day') d(day)
    -- a day removed under the retention rules is no longer expected (15 Sep 2026)
    join lateral (select not exists (select 1 from public.table_export_run pr
                                      where pr.stamp = d.day::date and pr.pruned_at is not null) as kept) k on k.kept
    cross join lateral (
      select to_char(d.day, 'YYYY-MM-DD') || '/_manifest.json' as path
      -- 22 SEP 2026: a FINISHED day expects exactly the pages its own run recorded writing
      -- (table_export_run.state->'tables': table -> pages), page_0000 .. page_<pages-1>. It used to
      -- expect page_0000 of every table fn_table_export_list() names TODAY, so a table added to the
      -- list on 22 Sep (table_export_change) was "never queued" on every earlier day -- seven files
      -- that never existed, refiled every run. A day with no finished run keeps the whole list.
      union select to_char(d.day, 'YYYY-MM-DD') || '/' || t.key || '/page_' || lpad(g::text, 4, '0') || '.json'
              from public.table_export_run r
              cross join lateral jsonb_each(r.state->'tables') t
              cross join lateral generate_series(0, coalesce((t.value->>'pages')::int, 1) - 1) g
             where r.stamp = d.day::date and r.status = 'done' and jsonb_typeof(r.state->'tables') = 'object'
      union select to_char(d.day, 'YYYY-MM-DD') || '/' || x.table_name || '/page_0000.json' from public.fn_table_export_list() x
             where not exists (select 1 from public.table_export_run r
                                where r.stamp = d.day::date and r.status = 'done' and jsonb_typeof(r.state->'tables') = 'object')
      union select o.name from storage.objects o where o.bucket_id = 'backups' and o.name like to_char(d.day, 'YYYY-MM-DD') || '/%') f
  )
  select * from base
  union all
  -- ── STORAGE SWEEP (15 Sep 2026): every other stored file the registry sweeps ──
  select 'obj:' || s.bucket || ':' || s.path, 'storage', s.bucket, s.path, null, null, s.entity || ':' || s.entity_id, s.created_at
    from public.fn_backup_sweep_objects() s
   where not exists (select 1 from base b where b.item_key = 'obj:' || s.bucket || ':' || s.path);
$function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_expected_status()
 RETURNS TABLE(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamp with time zone, doc_backup_id bigint, status text, attempts integer, verified_at timestamp with time zone, error text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select e.*, d.id, d.status, d.attempts, d.verified_at, d.error
    from public.fn_it_backup_expected() e
    left join lateral (
      select * from public.doc_backups d
       where (e.kind <> 'generated' and e.bucket is not null and d.bucket = e.bucket and d.path = e.path)
          or (e.kind = 'generated' and d.gen_kind = e.gen_kind and d.gen_ref = e.gen_ref)
       order by (d.status = 'done') desc, d.id desc limit 1) d on true;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_recheck()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h public.agent_actions; s record; d public.doc_backups; v_since timestamptz; v_files jsonb; v_state text;
  n_ok int; n_fail int; n_wait int; v_att int; v_rep jsonb; n_closed int := 0; n_retry int := 0; n_esc int := 0;
  n_orphaned int := 0;
begin
  -- 1. A backup whose source row is gone can never be filed. Measured 21 Sep 2026: two Stripe invoice
  --    rows for TEST transactions the nightly journey tore down. The reason carries the date and the id.
  update public.doc_backups b
     set status = 'abandoned',
         error = left('abandoned: source transaction ' || b.entity_id || ' no longer exists (measured '
                      || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai; last error: '
                      || coalesce(b.error, 'none') || ')', 300)
   where b.entity = 'transaction' and b.status <> 'done' and b.status <> 'abandoned'
     and not exists (select 1 from public.transactions t where t.id::text = b.entity_id);
  get diagnostics n_orphaned = row_count;

  for h in select * from public.agent_actions
            where kind = 'handoff' and agent = 'sales_engineer' and status = 'pending'
              and detail->>'type' in ('backup.refile', 'backup.remediate') order by id loop
    v_since := coalesce((h.detail->>'refiled_at')::timestamptz, h.created_at);
    v_files := '[]'::jsonb; n_ok := 0; n_fail := 0; n_wait := 0;
    for s in select e from jsonb_array_elements(coalesce(h.detail->'files', '[]'::jsonb)) e loop
      d := null;
      select * into d from public.doc_backups where id = (s.e->>'doc_backup_id')::bigint;
      v_state := case
        when d.id is null then case when h.detail ? 'sales_done_at' then 'failing' else 'waiting' end
        when d.status = 'done' and d.verified_at > v_since then 'ok'
        -- 2. Abandoned with its reason on the row: settled, the same reading fn_backup_coverage gives it.
        when d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%' then 'ok'
        when d.status in ('skipped_large', 'abandoned') or (d.status = 'error' and d.attempts >= 5) then 'failing'
        else 'waiting' end;
      if v_state = 'ok' then n_ok := n_ok + 1; elsif v_state = 'failing' then n_fail := n_fail + 1; else n_wait := n_wait + 1; end if;
      v_files := v_files || (s.e || jsonb_build_object('state', v_state, 'status', d.status, 'attempts', d.attempts, 'error', d.error));
    end loop;
    v_att := coalesce((h.detail->>'refile_attempts')::int, 0);

    if n_fail = 0 and n_wait = 0 then
      perform set_config('qd.backup_closer', 'it_engineer', true);
      perform set_config('qd.backup_closer_routine', 'fn_it_backup_recheck', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'it_engineer', 'files', v_files, 'verified_at', now()));
      perform set_config('qd.backup_closer', '', true);
      perform set_config('qd.backup_closer_routine', '', true);
      update public.agent_actions set decided_by = 'it_engineer' where id = h.id;
      n_closed := n_closed + 1;
    elsif h.detail->>'type' = 'backup.refile' and not (h.detail ? 'escalated_report_id') then
      if n_fail > 0 and v_att < 2 then
        perform public.fn_seat_handoff_act(h.id);          -- the second refile
        n_retry := n_retry + 1;
      elsif n_fail > 0 or h.created_at < now() - interval '48 hours' then
        v_rep := public.fn_support_report_to_ceo(
          'backup_escalation:' || h.id, 'serious',
          'Dropbox backup: ' || (n_fail + n_wait) || ' file(s) still not backed up after ' || v_att || ' refile(s)'
            || case when h.created_at < now() - interval '48 hours' then ' and 48 hours' else '' end,
          jsonb_build_object('handoff_id', h.id, 'files', v_files, 'refile_attempts', v_att, 'opened_at', h.created_at),
          jsonb_build_array(jsonb_build_object('action', 'handed to sales_engineer to refile', 'handoff_id', h.id, 'attempts', v_att,
                                               'last_refile_at', h.detail->>'refiled_at')),
          'Send the sales engineer instructions for these files, or record that they cannot be backed up and why. The IT engineer re-checks each file and closes only when it is verified in Dropbox.',
          p_review_in => interval '1 day', p_source_agent => 'it_engineer');
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', v_rep->'report_id', 'escalated_at', now())
         where id = h.id;
        perform public.fn_ceo_backup_escalation_decide((v_rep->>'report_id')::bigint);
        n_esc := n_esc + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'second_refiles', n_retry, 'escalated', n_esc, 'orphaned_abandoned', n_orphaned);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_refile_close()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_it_backup_recheck();
$function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_stage_failed(p_stage text, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  insert into public.agent_runs(agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'backup_tick', 'stage', p_stage),
          'backup tick stage ' || p_stage || ' failed: ' || left(coalesce(p_error, ''), 300));
  if not exists (select 1 from public.agent_actions
                  where agent = 'it_engineer' and kind = 'backup_tick_stage_failed' and detail->>'stage' = p_stage
                    and coalesce(status, '') in ('pending', 'needs_review') and created_at > now() - interval '20 hours') then
    insert into public.agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values ('it_engineer', 'backup_tick_stage_failed', 'pending', 'medium',
            'Backup check stage "' || p_stage || '" is failing',
            'The it_engineer''s ' || p_stage || ' stage threw: ' || left(coalesce(p_error, ''), 300)
              || '. Until it runs cleanly this part of the backup is not being checked.',
            'doc_backups', jsonb_build_object('stage', p_stage, 'error', left(coalesce(p_error, ''), 500)))
    returning id into v_id;
  end if;
  return jsonb_build_object('error', left(coalesce(p_error, ''), 200), 'finding_id', v_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_backup_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o jsonb := '{}'::jsonb;
begin
  begin o := o || jsonb_build_object('enqueue', public.fn_backup_enqueue_watch());
  exception when others then o := o || jsonb_build_object('enqueue', public.fn_it_backup_stage_failed('enqueue', sqlerrm)); end;
  begin o := o || jsonb_build_object('recheck', public.fn_it_backup_recheck());
  exception when others then o := o || jsonb_build_object('recheck', public.fn_it_backup_stage_failed('recheck', sqlerrm)); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_backup_escalation_sweep());
  exception when others then o := o || jsonb_build_object('ceo', public.fn_it_backup_stage_failed('ceo', sqlerrm)); end;
  begin o := o || jsonb_build_object('watch', public.fn_backup_watch());
  exception when others then o := o || jsonb_build_object('watch', public.fn_it_backup_stage_failed('watch', sqlerrm)); end;
  begin o := o || jsonb_build_object('queue', public.fn_dropbox_queue_stale());
  exception when others then o := o || jsonb_build_object('queue', public.fn_it_backup_stage_failed('queue', sqlerrm)); end;
  begin o := o || jsonb_build_object('daily', public.fn_dropbox_backup_daily_report());
  exception when others then o := o || jsonb_build_object('daily', public.fn_it_backup_stage_failed('daily', sqlerrm)); end;
  return o || jsonb_build_object('reconcile', public.fn_dropbox_reconcile_due());
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_cap_set(p_key text, p_value numeric, p_by text, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(p_key, '') !~ '^(cap|floor)_[a-z0-9_]+$' or p_key = 'cap_warn_ratio' then
    raise exception 'fn_it_cap_set sets a provider cap (cap_*) or floor (floor_*), not %', coalesce(p_key, 'nothing');
  end if;
  if p_by is null or p_by not in ('accountant', 'ceo', 'founder', 'it_engineer') then
    raise exception 'a cap is set by the accountant, the ceo, the founder or the it_engineer, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_source), '') = '' then raise exception 'say where the cap comes from: the plan page or the invoice'; end if;
  if p_value is not null and p_value <= 0 then raise exception 'a cap must be above zero, or NULL for not recorded'; end if;
  update public.it_threshold
     set value = p_value,
         basis = left(case when p_value is null
                           then 'not recorded: ' || p_source || ' (noted by the ' || p_by || ' on '
                                || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ')'
                           else 'set by the ' || p_by || ' on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY')
                                || ' from: ' || p_source end, 500)
   where key = p_key;
  if not found then raise exception 'no cap % in public.it_threshold', p_key; end if;
  return jsonb_build_object('key', p_key, 'value', p_value, 'set_by', p_by);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_ceo_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.support_ceo_report; n_told int := 0; n_answered int := 0; v_window interval; v_dec jsonb; v_status text;
        v_review jsonb;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  if v_window is null then
    raise exception 'fn_it_ceo_silence_watch: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent'
              and least(next_review_at, created_at + v_window) < now()
            order by id loop
    begin
      v_dec := public.fn_ceo_decide_report(r.id);
    exception when others then
      v_dec := jsonb_build_object('ok', false, 'reason', 'decider raised: ' || sqlerrm);
    end;
    select status into v_status from public.support_ceo_report where id = r.id;
    if v_status <> 'sent' then n_answered := n_answered + 1; continue; end if;

    -- the founder hears about a report once; the CEO keeps being asked every tick
    continue when exists (select 1 from public.agent_actions a
                           where a.kind = 'handoff' and a.target_id = 'delivery.request:' || r.id);

    perform public.fn_seat_handoff('it_engineer', 'customer_support', 'delivery.request', 'support_ceo_report', r.id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
        'event', 'The CEO has not answered an IT report: ' || left(r.subject, 120),
        'detail', 'The IT engineer reported this to the CEO at '
                  || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai) and it was due an answer by '
                  || to_char(least(r.next_review_at, r.created_at + v_window) at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || E'. Nobody has answered.\n\n'
                  || 'Report: ' || r.subject || E'\n\nThe CEO''s decider said: ' || coalesce(v_dec ->> 'reason', 'nothing')
                  || E'.\n\nIt stays open until the CEO answers it. Reference: support_ceo_report ' || r.id || '.',
        'dedupe_key', 'it_ceo_silent:' || split_part(r.idempotency_key, ':', 1) || ':'
                      || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD')));
    n_told := n_told + 1;
  end loop;
  -- ADDED 22 Sep 2026 (SEATS-01): an ACCEPTED report is reviewed too. Swallowed on purpose — the
  -- silence watch must keep answering 'sent' reports even if the review pass hits a bad row.
  begin v_review := public.fn_it_accepted_report_review();
  exception when others then v_review := jsonb_build_object('error', left(sqlerrm, 300)); end;
  return jsonb_build_object('founder_told', n_told, 'ceo_answered_first', n_answered, 'accepted_review', v_review);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_change_accept(p_txid bigint, p_by text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_by is null or p_by not in ('ceo', 'founder') then
    raise exception 'an unsigned change is accepted by the ceo or the founder, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'say why the change is accepted'; end if;
  if not exists (select 1 from public.routine_change_log where txid = p_txid) then
    raise exception 'no routine change was recorded in transaction %', p_txid;
  end if;
  insert into public.it_change_acceptance (txid, accepted_by, reason) values (p_txid, p_by, p_reason)
  on conflict (txid) do nothing;
  return public.fn_it_change_watch();
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_change_revisions_due()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(rev order by first_seen_at), '[]'::jsonb) from (
    select rev, first_seen_at from public.it_change_revision
     where verdict in ('pending', 'open_pr', 'not_on_main') and first_seen_at > now() - interval '30 days'
       and (checked_at is null or checked_at < now() - interval '10 minutes')
     order by first_seen_at limit 20) z
$function$


CREATE OR REPLACE FUNCTION public.fn_it_change_revisions_record(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p) is distinct from 'array' then
    raise exception 'fn_it_change_revisions_record takes the array verifyRevisions returns';
  end if;
  for x in select e from jsonb_array_elements(p) e loop
    if x->>'verdict' in ('on_main', 'merged_pr', 'open_pr', 'not_on_main') then
      update public.it_change_revision
         set verdict = x->>'verdict', pr_number = (x->>'pr_number')::int, checked_at = now(),
             detail = coalesce(x->'detail', '{}'::jsonb)
       where rev = x->>'rev';
      n := n + 1;
    else
      -- No verdict: the revision stays pending, but what GitHub answered is kept, so "could not be
      -- asked" names its cause. Applied 14 Sep 2026: the first live tick asked about 7cd70b4 and left
      -- nothing but verdict 'pending', checked never.
      update public.it_change_revision
         set checked_at = now(), detail = coalesce(x->'detail', '{}'::jsonb) || jsonb_build_object('no_verdict_at', now())
       where rev = x->>'rev';
    end if;
  end loop;
  return jsonb_build_object('recorded', n) || public.fn_it_change_watch();
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_change_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.it_change_revision; f record; v_items jsonb := '[]'::jsonb; v_tx bigint; v_note text; n_closed int := 0; v_rev jsonb;
begin
  for r in select * from public.it_change_revision
            where first_seen_at > now() - interval '30 days' and verdict not in ('on_main', 'merged_pr') loop
    -- In flight, not a fault: GitHub has not answered yet ('pending'), or the pull request carrying the
    -- revision is still open ('open_pr') -- the estate applies before it merges (22 Sep 2026).
    continue when r.verdict in ('pending', 'open_pr') and r.first_seen_at > now() - interval '2 hours';
    -- SETTLED: every change this revision made was re-applied from a reviewed revision or accepted.
    continue when exists (select 1 from public.routine_change_log c
                           where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev)
             and not exists (
                   select 1 from public.routine_change_log c
                    where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev
                      and not exists (select 1 from public.it_change_acceptance a where a.txid = c.txid)
                      and not exists (select 1 from public.routine_change_log s
                                        join public.it_change_revision rv
                                          on rv.rev = substring(s.application_name from '^qd-apply ([0-9a-f]{7,40}) ')
                                       where s.object_identity = c.object_identity and s.at > c.at
                                         and rv.verdict in ('on_main', 'merged_pr')));
    v_items := v_items || jsonb_build_object('item', 'rev:' || r.rev, 'owner_seat', 'ceo', 'subject', 'routine_change_log',
      'title', case r.verdict
                 when 'open_pr' then 'Routines were applied to production from ' || r.rev || ', which is in pull request #'
                                     || coalesce(r.pr_number::text, '?') || ' and has not been merged into main for over two hours'
                 when 'not_on_main' then 'Routines were applied to production from ' || r.rev
                                     || ', a revision that is not on main and in no merged or open pull request'
                 else 'Routines were applied from ' || r.rev || ' and GitHub could not yet be asked whether it is on main' end,
      'blast', case when r.verdict = 'not_on_main' then 'security' else 'agent_facing' end,
      'affected', case when r.verdict = 'not_on_main' then 1 else 0 end,
      'evidence', jsonb_build_object('rev', r.rev, 'verdict', r.verdict, 'pr_number', r.pr_number, 'checked_at', r.checked_at,
        'detail', r.detail,
        'objects', (select jsonb_agg(distinct c.command_tag || ' ' || c.object_identity) from public.routine_change_log c
                     where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        -- who applied it: 'qd-apply <rev> <seat> <worktree> <file>' since 22 Sep 2026
        'applied_as', (select jsonb_agg(distinct c.application_name) from public.routine_change_log c
                        where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        'txids', (select jsonb_agg(distinct c.txid) from public.routine_change_log c
                   where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        'close', 'Merge the pull request, re-apply each routine from a reviewed revision, or the ceo or the founder accepts its transaction with public.fn_it_change_accept(txid, who, why).'));
  end loop;
  v_rev := public.fn_it_duty_settle('unsigned_revision', v_items);

  for f in select issue_key, evidence from public.it_engineer_finding
            where closed_at is null and issue_key like 'duty:unsigned\_change:tx%' loop
    v_tx := (f.evidence->>'txid')::bigint;
    continue when v_tx is null;
    select 'accepted by the ' || accepted_by || ': ' || reason into v_note from public.it_change_acceptance where txid = v_tx;
    if v_note is null and not exists (
         select 1 from public.routine_change_log c
          where c.txid = v_tx
            and not exists (select 1 from public.routine_change_log s
                              join public.it_change_revision rv
                                on rv.rev = substring(s.application_name from '^qd-apply ([0-9a-f]{7,40}) ')
                             where s.object_identity = c.object_identity and s.at > c.at
                               and rv.verdict in ('on_main', 'merged_pr'))) then
      v_note := 'every routine it touched has since been re-applied from a reviewed revision';
    end if;
    if v_note is not null then
      perform public.fn_it_engineer_finding_close(f.issue_key, v_note);
      n_closed := n_closed + 1;
    end if;
  end loop;
  return jsonb_build_object('unsigned_revision', v_rev, 'unsigned_changes_closed', n_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_cost_jumped(p_this numeric, p_prior numeric)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_this, 0) - coalesce(p_prior, 0) >= public.fn_it_threshold('cost_watch_floor_aed')
     and coalesce(p_this, 0) > coalesce(p_prior, 0) * public.fn_it_threshold('cost_watch_jump_multiple')
$function$


CREATE OR REPLACE FUNCTION public.fn_it_cost_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now timestamptz := now();
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_fx numeric := public.fn_it_threshold('usd_aed_rate');
  v_items jsonb := '[]'::jsonb; v_rows jsonb := '[]'::jsonb;
  p text; v_this numeric; v_prior numeric; v_days int; v_basis text; v_owner text; v_cause text; v_detail jsonb;
  v_top record; v_n int;
begin
  foreach p in array array['openrouter', 'twilio', 'supabase', 'vercel', 'resend'] loop
    v_detail := '{}'::jsonb; v_cause := null; v_top := null;
    if p = 'openrouter' then
      v_days := 7; v_basis := 'ai_cost_log';
      select coalesce(sum(cost_aed) filter (where occurred_at >= v_now - interval '7 days'), 0),
             coalesce(sum(cost_aed) filter (where occurred_at < v_now - interval '7 days'), 0), count(*)
        into v_this, v_prior, v_n
        from public.ai_cost_log where occurred_at >= v_now - interval '14 days' and occurred_at < v_now;
      if v_n = 0 then v_basis := 'unavailable'; end if;
      select coalesce(seat, agent_key, 'unnamed') seat, coalesce(task_class, '?') task_class, coalesce(model_used, '?') model,
             round(coalesce(sum(cost_aed) filter (where occurred_at >= v_now - interval '7 days'), 0), 2) now_aed,
             round(coalesce(sum(cost_aed) filter (where occurred_at < v_now - interval '7 days'), 0), 2) before_aed
        into v_top
        from public.ai_cost_log where occurred_at >= v_now - interval '14 days' and occurred_at < v_now
       group by 1, 2, 3
       order by coalesce(sum(cost_aed) filter (where occurred_at >= v_now - interval '7 days'), 0)
              - coalesce(sum(cost_aed) filter (where occurred_at < v_now - interval '7 days'), 0) desc
       limit 1;
      v_owner := case when v_top.seat in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing')
                      then v_top.seat else 'ceo' end;
      if v_top.seat is not null then
        v_cause := format('%s / %s on %s rose from AED %s to AED %s', v_top.seat, v_top.task_class, v_top.model, v_top.before_aed, v_top.now_aed);
        v_detail := jsonb_build_object('top_rise', to_jsonb(v_top));
      end if;
    elsif p = 'twilio' then
      v_days := 7; v_basis := 'usage_api'; v_owner := 'customer_support';
      select coalesce(sum(d.amount_minor / 100.0 * case when upper(d.currency) = 'AED' then 1 else v_fx end)
                        filter (where d.day > v_week - 7), 0),
             coalesce(sum(d.amount_minor / 100.0 * case when upper(d.currency) = 'AED' then 1 else v_fx end)
                        filter (where d.day <= v_week - 7), 0), count(*)
        into v_this, v_prior, v_n
        from public.it_spend_daily d where d.source = 'twilio' and d.day > v_week - 14 and d.day <= v_week;
      if v_n = 0 then v_basis := 'unavailable'; end if;
      select d.day, round(d.amount_minor / 100.0, 2) amount, upper(d.currency) currency into v_top
        from public.it_spend_daily d where d.source = 'twilio' and d.day > v_week - 7 and d.day <= v_week
       order by d.amount_minor desc limit 1;
      v_detail := jsonb_build_object('costliest_day', to_jsonb(v_top),
        'whatsapp_replies_sent_this_week', (select count(*) from public.wa_messages w where w.created_at >= v_now - interval '7 days' and w.reply is not null and coalesce(w.sent, false)),
        'whatsapp_replies_sent_week_before', (select count(*) from public.wa_messages w where w.created_at >= v_now - interval '14 days' and w.created_at < v_now - interval '7 days' and w.reply is not null and coalesce(w.sent, false)));
      if v_top.day is not null then
        v_cause := format('the costliest day was %s (%s %s); WhatsApp replies sent %s this week against %s the week before',
                          v_top.day, v_top.amount, v_top.currency, v_detail->>'whatsapp_replies_sent_this_week', v_detail->>'whatsapp_replies_sent_week_before');
      end if;
    else
      v_days := 30; v_basis := 'journals';
      v_owner := case when p = 'resend' then 'customer_support' else 'it_engineer' end;
      select coalesce(sum(l.debit - l.credit) filter (where j.entry_date > v_week - 30), 0),
             coalesce(sum(l.debit - l.credit) filter (where j.entry_date <= v_week - 30), 0), count(*)
        into v_this, v_prior, v_n
        from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
       where j.status = 'posted' and l.account_code like '6%'
         and j.entry_date > v_week - 60 and j.entry_date <= v_week
         and (coalesce(l.memo, '') ~* ('\m' || p || '\M') or coalesce(j.memo, '') ~* ('\m' || p || '\M'));
      if v_n = 0 then v_basis := 'unavailable'; v_this := null; v_prior := null; end if;
      v_detail := jsonb_build_object('entries_this_period', (
        select coalesce(jsonb_agg(jsonb_build_object('entry_no', j.entry_no, 'date', j.entry_date, 'memo', left(coalesce(l.memo, j.memo), 120),
                                                     'aed', l.debit - l.credit) order by l.debit - l.credit desc), '[]'::jsonb)
          from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
         where j.status = 'posted' and l.account_code like '6%' and j.entry_date > v_week - 30 and j.entry_date <= v_week
           and (coalesce(l.memo, '') ~* ('\m' || p || '\M') or coalesce(j.memo, '') ~* ('\m' || p || '\M'))));
      if jsonb_array_length(v_detail->'entries_this_period') > 0 then
        v_cause := 'the journal entries of the period: ' || (select string_agg(format('%s %s AED %s', e->>'date', e->>'memo', e->>'aed'), '; ')
                                                               from (select e from jsonb_array_elements(v_detail->'entries_this_period') e limit 3) s);
      end if;
    end if;

    v_rows := v_rows || jsonb_build_object('provider', p, 'basis', v_basis, 'period_days', v_days,
      'this_aed', round(v_this, 2), 'prior_aed', round(v_prior, 2),
      'jumped', v_basis <> 'unavailable' and public.fn_it_cost_jumped(v_this, v_prior),
      'owner_seat', v_owner, 'cause', v_cause, 'detail', v_detail);

    insert into public.it_cost_watch_week (week_ending, provider, basis, period_days, this_aed, prior_aed, jumped, owner_seat, cause, detail, measured_at)
    values (v_week, p, v_basis, v_days, round(v_this, 2), round(v_prior, 2),
            v_basis <> 'unavailable' and public.fn_it_cost_jumped(v_this, v_prior), v_owner, v_cause, v_detail, v_now)
    on conflict (week_ending, provider) do update
      set basis = excluded.basis, period_days = excluded.period_days, this_aed = excluded.this_aed, prior_aed = excluded.prior_aed,
          jumped = excluded.jumped, owner_seat = excluded.owner_seat, cause = excluded.cause, detail = excluded.detail,
          measured_at = excluded.measured_at;

    if v_basis <> 'unavailable' and public.fn_it_cost_jumped(v_this, v_prior) then
      v_items := v_items || jsonb_build_object(
        'item', p, 'subject', p, 'owner_seat', v_owner, 'blast', 'agent_facing', 'affected', 1,
        'title', left(format('%s cost AED %s over the last %s days against AED %s the %s before: %s',
                             p, round(v_this, 2), v_days, round(v_prior, 2), v_days, coalesce(v_cause, 'no cause recorded')), 300),
        'evidence', jsonb_build_object('this_aed', round(v_this, 2), 'prior_aed', round(v_prior, 2), 'period_days', v_days,
                                       'basis', v_basis, 'cause', v_cause, 'detail', v_detail,
                                       'no_cap', 'founder rule: this watches and explains, it never blocks'));
    end if;
  end loop;

  return jsonb_build_object('week_ending', v_week, 'providers', v_rows,
                            'settled', public.fn_it_duty_settle('cost_watch', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_credential_founder_required(p_issue_key text, p_title text DEFAULT NULL::text, p_evidence jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text := regexp_replace(coalesce(p_issue_key, ''), '^duty:', ''); v_x text;
begin
  if s ~ '^renewal:' then
    v_x := regexp_replace(regexp_replace(s, '^renewal:', ''), ':date_unknown$', '');
    return exists (select 1 from public.it_credential_class where rotation = 'founder_required' and expiry_item = v_x);
  elsif s ~ '^credential:' then
    v_x := regexp_replace(s, '^credential:', '');
    return exists (select 1 from public.it_credential_class where rotation = 'founder_required' and v_x = any (integrations));
  elsif s ~ '^integration(_social)?:' then
    v_x := split_part(regexp_replace(s, '^integration(_social)?:', ''), ':', 1);
    if not exists (select 1 from public.it_credential_class where rotation = 'founder_required' and v_x = any (integrations)) then
      return false;
    end if;
    -- Only a credential failure is a renewal. An outage on the same integration keeps its path.
    return coalesce(p_evidence->>'reconnect_link', '') <> ''
        -- What broke only: the title's "Tried:" and "Needs:" tail is registry prose and would match any row.
        or concat_ws(' ', split_part(coalesce(p_title, ''), '. Tried:', 1), p_evidence->>'what_broke')
           ~* '(HTTP 40[13]|"code":\s*(20003|70004|190)\M|\(#190\)|invalid_grant|unauthorized_client|OAuthException|refused the company''s (API )?key|invalid.{0,20}(api key|token|credential)|expired.{0,20}token|token.{0,20}expired|not connected)';
  end if;
  return false;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_credential_reverify()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.it_credential_rotation; o public.internal_credential; n public.internal_credential;
        v_items jsonb := '[]'::jsonb; n_ret int := 0; n_held int := 0; v_overlap interval; v_cadence interval;
begin
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  for r in select * from public.it_credential_rotation where status in ('overlap', 'held') and provider is null order by id for update loop
    -- Locked, so a use of the old credential between this read and the retire cannot be missed.
    select * into o from public.internal_credential where id = r.old_id for update;
    select * into n from public.internal_credential where id = r.new_id;
    if o.last_used_at is null or o.last_used_at < r.rotated_at then
      if now() >= r.overlap_until then
        update public.internal_credential set active = false, retired_at = now() where id = r.old_id;
        update public.it_credential_rotation set status = 'retired', closed_at = now(),
               note = 'old credential quiet since rotation; new used ' || coalesce(n.use_count, 0) || ' time(s)' where id = r.id;
        n_ret := n_ret + 1;
      end if;
    elsif now() >= r.overlap_until then
      -- Still presented after the rotation: keep it valid past the NEXT run, which decides again.
      update public.internal_credential set expires_at = now() + v_overlap + 2 * v_cadence where id = r.old_id;
      update public.it_credential_rotation set status = 'held', overlap_until = now() + v_overlap,
             note = 'old credential still used by ' || coalesce(o.last_function, '?') || ' at ' || o.last_used_at where id = r.id;
      v_items := v_items || jsonb_build_object('item', r.context, 'subject', o.last_function,
        'title', 'After rotating ' || r.context || ', ' || coalesce(o.last_function, 'a caller') || ' still presents the old credential',
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('rotation_id', r.id, 'old_last_used_at', o.last_used_at, 'last_function', o.last_function,
                                       'fix', 'the caller must read ' || r.secret_key || ' from app_secrets at call time'));
      n_held := n_held + 1;
    end if;
  end loop;
  return jsonb_build_object('retired', n_ret, 'held', n_held,
                            'settle', public.fn_it_duty_settle('rotation', v_items),
                            'key_age', public.fn_it_key_age_refresh());
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_credential_rotate(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare c public.internal_credential; v_key text; v_secret text; v_new bigint; v_overlap interval; v_cadence interval;
begin
  select * into c from public.internal_credential where id = p_id and active and retired_at is null for update;
  if not found then raise exception 'fn_it_credential_rotate: no active credential %', p_id; end if;
  if c.is_legacy then raise exception 'fn_it_credential_rotate: % is legacy and is never rotated automatically', c.context; end if;
  v_key := 'cred_' || replace(c.context, '.', '_');
  if not exists (select 1 from public.app_secrets where key = v_key) then
    raise exception 'fn_it_credential_rotate: % has no app_secrets key %, so no caller would receive a new secret', c.context, v_key;
  end if;
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active, rotated_at, expires_at)
  values (c.context, c.label, public.fn_internal_credential_hash(v_secret), c.scope, false, true, now(),
          now() + make_interval(days => (coalesce(public.fn_it_threshold('credential_rotate_days'), 90) + 30)::int))
  returning id into v_new;
  -- Every caller reads this key at call time, so this one write moves them all to the new secret.
  update public.app_secrets set value = v_secret, updated_at = now() where key = v_key;
  -- overlap_until is when reverify may first decide; the old credential is still accepted for TWO
  -- more cadences of the duty after that, so the run that decides comes before it is refused even
  -- when that run is late or one run is missed (review of #709: one cadence left no margin at all).
  update public.internal_credential set expires_at = now() + v_overlap + 2 * v_cadence where id = c.id;
  insert into public.it_credential_rotation (context, old_id, new_id, secret_key, overlap_until)
  values (c.context, c.id, v_new, v_key, now() + v_overlap);
  return jsonb_build_object('context', c.context, 'old_id', c.id, 'new_id', v_new, 'overlap_until', now() + v_overlap,
                            'old_valid_until', now() + v_overlap + 2 * v_cadence);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_daily_line()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_day   text := to_char(v_local, 'YYYY-MM-DD');
  v_since timestamptz := (date_trunc('day', v_local) at time zone 'Asia/Dubai');
  v_ev jsonb; v_rep jsonb; n_done int;
begin
  update public.support_ceo_report
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer saw the CEO''s receipt: ' || acceptance_receipt
   where source_agent = 'it_engineer' and idempotency_key like 'it_daily:%' and status = 'accepted';
  get diagnostics n_done = row_count;

  if v_local::time < time '19:00'
     or exists (select 1 from public.support_ceo_report where idempotency_key = 'it_daily:' || v_day) then
    return jsonb_build_object('filed', false, 'completed_after_receipt', n_done);
  end if;

  select jsonb_build_object(
    'day', v_day,
    'open_findings', (select count(*) from public.it_engineer_finding where closed_at is null),
    'open_findings_actionable', (select count(*) from public.it_engineer_finding
                                  where closed_at is null and public.fn_it_engineer_severity(blast, affected, started_at) <> 'warn'),
    'open_loops', (select count(*) from public.agent_actions
                    where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')),
    'open_loops_by_seat', coalesce((select jsonb_object_agg(agent, n) from (
                      select agent, count(*) n from public.agent_actions
                       where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')
                       group by agent) x), '{}'::jsonb),
    'loops_closed_today', (select count(*) from public.agent_actions
                            where kind = 'handoff' and detail->>'from' = 'it_engineer' and status = 'done' and decided_at >= v_since),
    'escalated_today', (select count(*) from public.support_ceo_report
                         where source_agent = 'it_engineer' and idempotency_key like 'it_loop:%' and created_at >= v_since),
    'founder_emails_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'email' and created_at >= v_since),
    'repeats_folded_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'deduped' and created_at >= v_since),
    -- Duty 17: failure classes the company fixed on its own versus new ones.
    'auto_fixed_today', (select count(*) from public.agent_actions a
                          where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.decided_at >= v_since
                            and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)),
    'playbook_runs_today', (select count(*) from public.agent_runs
                             where agent = 'it_engineer' and counts->>'job' = 'playbook' and started_at >= v_since),
    'new_bugs_today', (select count(*) from public.it_incident where created_at >= v_since),
    'awaiting_learning', (select count(*) from public.agent_actions
                           where kind = 'handoff' and detail->>'type' = 'it.finding' and status <> 'done' and detail ? 'awaiting_learning'),
    -- Instruction 979: what the integration watch fixed itself today (recorded here, never mailed), and what is down.
    'integrations_fixed_today', coalesce((select jsonb_agg(distinct counts->'fix'->>'integration') from public.agent_runs
                           where agent = 'it_engineer' and counts->>'job' = 'integration_self_fix' and started_at >= v_since), '[]'::jsonb),
    'integrations_failing', coalesce((select jsonb_agg(regexp_replace(issue_key, '^duty:', '') order by issue_key) from public.it_engineer_finding
                           where closed_at is null and issue_key like 'duty:integration%'), '[]'::jsonb),
    'integrations_waiting_on_external', coalesce((select jsonb_agg(jsonb_build_object('integration', integration, 'party', external_party,
                           'ticket', ticket_ref, 'opened_on', opened_on, 'last_reply_at', last_reply_at,
                           'reply_needs_founder', reply_needs_founder, 'last_checked_at', last_checked_at) order by integration)
                           from public.it_integration_external_cause where closed_at is null), '[]'::jsonb),
    -- The newest Gmail Postmaster reading (duty 'postmaster'); null until the first read. Its numbers are Postmaster's
    -- day (stats_day), 1-2 days behind read_on; a number Postmaster did not publish is null, never 0.
    'gmail_postmaster', (select jsonb_build_object('domain', p.domain, 'read_on', p.read_on, 'basis', p.basis, 'stats_day', p.stats_day,
                           'spam_ratio', p.spam_ratio, 'spam_lower', p.spam_lower, 'spam_upper', p.spam_upper, 'reputation', p.reputation,
                           'spf_ratio', p.spf_ratio, 'dkim_ratio', p.dkim_ratio, 'dmarc_ratio', p.dmarc_ratio, 'reason', p.reason,
                           'paused_at', p.paused_at, 'line', p.line)
                           from public.it_postmaster_reading p order by p.read_on desc, p.read_at desc limit 1))
  into v_ev;

  v_rep := public.fn_support_report_to_ceo('it_daily:' || v_day, 'routine',
    'IT engineer daily line ' || v_day || ': ' || (v_ev->>'open_loops') || ' open loop(s), '
      || (v_ev->>'loops_closed_today') || ' closed today, ' || (v_ev->>'founder_emails_today') || ' founder email(s), '
      || (v_ev->>'repeats_folded_today') || ' repeat(s) folded, '
      || jsonb_array_length(v_ev->'integrations_fixed_today') || ' integration(s) fixed without anyone, '
      || jsonb_array_length(v_ev->'integrations_failing') || ' integration(s) down ('
      || jsonb_array_length(v_ev->'integrations_waiting_on_external') || ' waiting on a provider''s ticket). '
      || coalesce(v_ev->'gmail_postmaster'->>'line', 'Gmail Postmaster: not read yet (duty postmaster has not run)'),
    v_ev, '[]'::jsonb,
    'Acknowledge the day''s IT position. Nothing else is requested; anything that needs a decision reaches you as its own report.',
    p_review_in => interval '3 hours', p_source_agent => 'it_engineer');
  if not coalesce((v_rep->>'ok')::boolean, false) then
    raise exception 'fn_it_daily_line: the CEO report was refused: %', v_rep->>'reason';
  end if;
  return jsonb_build_object('filed', true, 'report', v_rep, 'completed_after_receipt', n_done);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_deliberation_independence_items(p_include_demo boolean DEFAULT false, p_window interval DEFAULT '30 days'::interval, p_min_reviews integer DEFAULT 10, p_threshold numeric DEFAULT 0.90)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with fin as (
    select d.id, d.reviewer_seat, d.author_seat,
           (select t.verdict from public.seat_deliberation_turn t where t.deliberation_id = d.id and t.phase = 'compare'
               and t.status = 'recorded' order by t.round desc limit 1) final_verdict,
           (select t.verdict from public.seat_deliberation_turn t where t.deliberation_id = d.id and t.phase = 'blind'
               and t.status = 'recorded' order by t.round limit 1) blind_verdict,
           (select string_agg(distinct t.model, ', ') from public.seat_deliberation_turn t where t.deliberation_id = d.id
               and t.phase in ('blind', 'compare') and t.status = 'recorded') reviewer_models
      from public.seat_deliberation d
     where d.opened_at >= now() - p_window and (p_include_demo or not d.demo)
  ), pair as (
    select reviewer_seat, author_seat, count(*) n,
           count(*) filter (where final_verdict = 'approve') approvals,
           count(*) filter (where blind_verdict = final_verdict) blind_matched,
           string_agg(distinct reviewer_models, ', ') models
      from fin where final_verdict is not null group by reviewer_seat, author_seat
  ), stamp as (
    select jsonb_build_object(
             'item', 'rubber_stamp:' || reviewer_seat || ':' || author_seat, 'owner_seat', 'ceo', 'subject', 'seat_deliberation',
             'title', reviewer_seat || ' approved ' || approvals || ' of ' || n || ' proposals from ' || author_seat
                      || ' in ' || p_window || ' (' || round(100.0 * approvals / n) || '%); its blind verdict matched the final one '
                      || blind_matched || ' of ' || n || ' times. A reviewer that approves almost everything is a failed check '
                      || '(founder_instruction 873) - read the steelmans before the next approval.',
             'blast', 'agent_facing', 'affected', n,
             'evidence', jsonb_build_object('reviews', n, 'approvals', approvals, 'approval_rate', round(1.0 * approvals / n, 4),
                           'blind_matched', blind_matched, 'blind_match_rate', round(1.0 * blind_matched / n, 4),
                           'threshold', p_threshold, 'min_reviews', p_min_reviews, 'window', p_window::text, 'reviewer_models', models,
                           'look_at', 'select * from public.seat_deliberation_turn where deliberation_id in (select id from public.seat_deliberation where reviewer_seat = '''
                                      || reviewer_seat || ''' and author_seat = ''' || author_seat || ''') order by id')) x
      from pair where n >= p_min_reviews and approvals >= p_threshold * n
  ), noind as (
    select jsonb_build_object(
             'item', 'no_independent_reviewer:' || reviewer_seat || ':' || author_seat, 'owner_seat', 'ceo', 'subject', 'seat_deliberation',
             'title', count(*) || ' deliberation(s) from ' || author_seat || ' to ' || reviewer_seat
                      || ' have no independent reviewer: no healthy model outside the author''s family. They were not '
                      || 'reviewed on the same family instead; close them or restore a reviewer.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('deliberation_ids', jsonb_agg(id order by id))) x
      from public.seat_deliberation d
     where d.status = 'no_independent_reviewer' and (p_include_demo or not d.demo)
     group by reviewer_seat, author_seat
  ), failing as (
    select jsonb_build_object(
             'item', 'review_failing:' || reviewer_seat || ':' || author_seat, 'owner_seat', 'ceo', 'subject', 'seat_deliberation',
             'title', count(*) || ' deliberation(s) from ' || author_seat || ' to ' || reviewer_seat
                      || ' stopped after three failed review turns in one round; read the why on each failed turn.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('deliberation_ids', jsonb_agg(id order by id))) x
      from public.seat_deliberation d
     where d.status = 'open' and (p_include_demo or not d.demo)
       and (select count(*) from public.seat_deliberation_turn t
             where t.deliberation_id = d.id and t.round = d.round and t.status = 'failed') >= 3
     group by reviewer_seat, author_seat
  )
  select coalesce((select jsonb_agg(x) from stamp), '[]'::jsonb) || coalesce((select jsonb_agg(x) from noind), '[]'::jsonb)
         || coalesce((select jsonb_agg(x) from failing), '[]'::jsonb);
$function$


CREATE OR REPLACE FUNCTION public.fn_it_deliberation_independence_watch(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_items jsonb := public.fn_it_deliberation_independence_items(p_include_demo);
begin
  -- A demo deliberation's escalation is judged with the demo rows included and settled under its own duty,
  -- so a rolled-back probe can never close or open the real duty's findings.
  return jsonb_build_object('items', jsonb_array_length(v_items),
    'settle', public.fn_it_duty_settle(case when p_include_demo then 'deliberation_independence_demo' else 'deliberation_independence' end, v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_dependency_ingest(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
begin
  if jsonb_typeof(p_r->'advisories') is distinct from 'array' then
    raise exception 'fn_it_dependency_ingest takes {advisories:[...]} from scripts/it/report_dependency_audit.mjs';
  end if;
  for e in select a from jsonb_array_elements(p_r->'advisories') a loop
    v_items := v_items || jsonb_build_object('item', (e->>'ecosystem') || ':' || (e->>'package') || ':' || coalesce(e->>'id', '?'),
      'owner_seat', case when e->>'ecosystem' = 'app' then 'ceo' else coalesce(e->>'owner_seat', 'ceo') end,
      'subject', coalesce(e->>'function', e->>'package'),
      'title', upper(coalesce(e->>'severity', '?')) || ' advisory in ' || (e->>'package') || ': ' || left(coalesce(e->>'title', ''), 120),
      'blast', case when lower(e->>'severity') in ('high', 'critical') then 'security' else 'internal' end,
      'affected', case when lower(e->>'severity') in ('high', 'critical') then 1 else 0 end,
      'evidence', e || jsonb_build_object('no_founder_email', lower(e->>'severity') not in ('high', 'critical')));
  end loop;
  v_res := public.fn_it_duty_settle('dependency', v_items);
  perform public.fn_it_duty_ran('dependency', v_res);
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_detect(p_web jsonb DEFAULT NULL::jsonb, p_persist boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- The window is one hour and the baseline is the seven days BEFORE it. The window has to be
  -- long enough that a 30-minute job appears in it and short enough that a fault is news.
  c_win       constant interval := interval '60 minutes';
  c_base      constant interval := interval '7 days';
  -- Statuses agent_runs uses for "this run did its job". Anything else, NULL included, is a
  -- failure: a run that started and never recorded an outcome is not a success.
  c_ok        constant text[] := array['ok','success','completed','skipped','warn','held','noop'];
  -- D0 (21 Sep 2026). The newest c_cap rows per agent are the slice every arm reads. One subject's
  -- flood (fn:ai_gateway, 40,368 rows in 7 days) took this routine from 5.9 s to 11.0 s and past
  -- PostgREST's 8 s cancel, and the estate went blind for 50 hours. See the file header.
  c_cap       constant int := 5000;
  v_capped    int;
  v_slice     int;
  v_now       timestamptz := now();
  -- Whatever lock_timeout the caller arrived with, so D5 can put it back exactly (see D5).
  v_lock_prev text;
  v_find      jsonb := '[]'::jsonb;
  v_notes     jsonb := '{}'::jsonb;
  v_keys      text[] := '{}';
  v_worst     text := 'none';
  r           record;
  v_rate      numeric;
  v_brate     numeric;
  v_state     text;
  v_sev       text;
  v_key       text;
  v_prev      timestamptz;
  v_gap       numeric;
  v_cnt       bigint;
  -- D5's drain arm: rows this queue completed in the last hour, and the depth divided by it.
  v_drain     bigint;
  v_hours     numeric;
  v_oldest    timestamptz;
  v_age       numeric;
  v_basis     jsonb;
  v_opened    int := 0;
  v_resolved  int := 0;
  v_watched   int;
  v_site_ms   integer;
  v_site_st   integer;
  -- D8, the backup chain. Read from pg_stat_archiver, which needs no credential.
  v_arch_n       bigint;
  v_arch_at      timestamptz;
  v_arch_fail    bigint;
  v_arch_fail_at timestamptz;
  v_arch_reset   timestamptz;
  v_arch_age     numeric;
  -- D9, polite refusals. It carries its own window and floor; the reasons are written at D9.
  c_ref_win   constant interval := interval '24 hours';
  c_ref_min   constant int := 20;
  v_share     numeric;
  v_bshare    numeric;
  v_ref_eval  int := 0;
  v_ref_thin  int := 0;
begin

-- ══ D0. ONE SLICE OF agent_runs, READ ONCE, BOUNDED PER SUBJECT ════════════════════════════
-- Reads: public.agent_runs, seven days of it — ONCE. D1, D2, D6 and D9 used to each scan the
-- same seven days and D1, D6 and D9 each re-ran fn_it_run_is_refusal per row (three passes,
-- ~100,000 calls each on 18 Sep). The two per-row predicates are evaluated here exactly once.
-- The cap is per AGENT (the raw name, before the fn: prefix is stripped), newest rows first, so
-- a subject that logs 6,000 rows an hour keeps a baseline of its own most recent history and
-- every other subject keeps all of its seven days. A cap that fired is published in notes.slice;
-- silence there means no subject was cut.
--
-- 21 SEP 2026 (evening) — THE ROW RULES ARE EVALUATED AS SETS, NOT AS ~140,000 FUNCTION CALLS.
-- Measured on 46,700 slice rows: the two per-row predicates below cost 2,740 ms of this block
-- (2,960 ms with them, 221 ms without), and D9's per-row rehearsal-window test another ~2,300 ms.
-- None of the four helpers can be inlined by the planner: each has a pinned SET search_path AND an
-- EXISTS sub-select, and either one alone forbids SQL-function inlining. So every row paid a full
-- function invocation, and D9's rehearsal test additionally scanned all 266 rehearsal_window rows
-- per row. The SAME rules are written here as set expressions over the same tables:
--   held       = fn_it_run_is_held: the founder-hold arm (some 'HELD BY THE FOUNDER%' route whose
--                open_until is after the run) is exactly "the run started before the latest such
--                open_until", read once; the signature arm is the same EXISTS, reached only for the
--                subjects it_hold_signature names.
--   refused0   = fn_it_run_is_refusal, the same four telemetry shapes and the same ±5 s neighbour.
--   rehearsal  = fn_rehearsal_window_covers: the windows (open ones run six hours) are folded once
--                into one multirange and each row is a containment test. A window that ends before
--                it starts covers no instant in either form and is left out, because a range
--                cannot be built from it.
-- Proved equal on the live slice before this was written, 21 Sep 2026: 46,618 rows, 0 mismatches
-- on each flag (643 held, 999 refused, 32,565 in a rehearsal window, 151 policy). (That comparison
-- lives in the_it_detector_evaluates_its_row_rules_as_sets_not_as_function_calls.sql; this file
-- ends with a verdict row that RUNS fn_it_detect unpersisted and requires ok.)
drop table if exists pg_temp.it_runs7;
create temp table it_runs7 on commit drop as
  select x.agent, regexp_replace(x.agent, '^fn:', '') subject, x.started_at, x.finished_at,
         x.status, x.counts, x.note,
         coalesce(x.started_at < h.hold_until
           and regexp_replace(coalesce(x.agent, ''), '^fn:', '') = any (h.subjects)
           and exists (select 1 from public.it_hold_signature s
                        where s.subject = regexp_replace(coalesce(x.agent, ''), '^fn:', '')
                          and coalesce(x.counts, '{}'::jsonb) @> s.counts_match
                          and (s.note_like is null or coalesce(x.note, '') like s.note_like)), false) held,
         coalesce(
              (x.counts ->> 'http') ~ '^4[0-9][0-9]$'
           or (x.counts ->> 'signal') in ('forbidden','bad_secret')
           or (x.counts ->> 'authorised') = '0'
           or coalesce(nullif(x.counts ->> 'forbidden','')::int, 0) > 0
           or (x.agent not like 'fn:%' and exists (
                select 1 from public.agent_runs t
                 where t.agent = 'fn:' || x.agent
                   and t.started_at between x.started_at - interval '5 seconds' and x.started_at + interval '5 seconds'
                   and (t.counts ->> 'http') ~ '^4[0-9][0-9]$')), false) refused0,
         coalesce(x.started_at <@ rw.covered, false) rehearsal
    from (select a.*, row_number() over (partition by a.agent order by a.started_at desc) rn
            from public.agent_runs a where a.started_at > v_now - c_base) x
   cross join (select max(l.open_until) hold_until,
                      (select coalesce(array_agg(distinct s.subject), '{}') from public.it_hold_signature s) subjects
                 from public.llm_route_health l
                where l.opened_reason like 'HELD BY THE FOUNDER%') h
   cross join (select range_agg(tstzrange(w.started_at, coalesce(w.ended_at, w.started_at + interval '6 hours'), '[]')) covered
                 from public.rehearsal_window w
                where w.started_at is not null
                  and coalesce(w.ended_at, w.started_at + interval '6 hours') >= w.started_at) rw
   where x.rn <= c_cap;
select count(*) into v_slice from it_runs7;
select count(*) into v_capped from (
  select agent from public.agent_runs where started_at > v_now - c_base
   group by agent having count(*) > c_cap) z;
v_notes := v_notes || jsonb_build_object('slice', jsonb_build_object(
  'basis', 'measured', 'rows', v_slice, 'cap_per_subject', c_cap, 'subjects_capped', v_capped));

-- ══ D1. EDGE FUNCTIONS / AGENTS FAILING, OR FAILING MORE THAN USUAL ═════════════════════════
-- Reads: public.agent_runs (window vs the 7 days before it), public.it_watch_subject.
-- Fires when every attempt in the window failed ('stopped'), or when the window's failure rate is
-- at least 20 percentage points above this subject's own baseline rate ('degraded').
-- ON AN IDLE ESTATE: an agent with no runs in the window is not evaluated at all, and an agent
-- whose runs all succeeded produces nothing. Silence here means "nothing failed", and D2 below is
-- what stops that being confused with "nothing ran".
-- The `fn:<name>` telemetry rows and the bare `<name>` semantic rows are two logs of the SAME
-- subject, so the prefix is stripped before grouping: otherwise one function appears as two, and
-- neither half can be looked up in it_watch_subject to find out whether it is customer-facing.
for r in
  with runs as (
    select subject, agent, started_at,
           coalesce(status,'error') <> all (c_ok)                  bad,
           -- A run the founder's hold refused is neither the caller turned away nor the subject's
           -- fault: it leaves both sides of the rate and is reported apart as window_held.
           refused0 or held                                        refused,
           held
    from it_runs7),
  w as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f,
           count(*) filter (where refused and not held)::int     refused,
           count(*) filter (where held)::int                     held
    from runs where started_at > v_now - c_win group by subject),
  b as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f
    from runs where started_at <= v_now - c_win group by subject)
  select w.subject agent, w.n, w.f, w.refused, w.held, coalesce(b.n,0) bn, coalesce(b.f,0) bf,
         coalesce(s.public_surface,false) pub, (s.subject is not null) known
  from w
  left join b on b.subject = w.subject
  left join public.it_watch_subject s on s.subject = w.subject
  where w.f > 0 and w.n > 0
loop
  v_rate  := r.f::numeric / r.n;
  v_brate := case when r.bn >= 10 then r.bf::numeric / r.bn else null end;
  v_state := case
               when r.f = r.n then 'stopped'
               when r.n >= 3 and (v_rate - coalesce(v_brate, 0)) >= 0.20 then 'degraded'
               else null end;
  continue when v_state is null;
  v_sev := public.fn_it_severity(v_state, r.pub);
  v_key := 'run_failure:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'run_failure', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', case when v_state = 'stopped'
                  then r.agent || ' failed every one of its ' || r.n || ' attempts in the last hour'
                  else r.agent || ' is failing ' || round(v_rate*100) || '% of attempts, against a baseline of '
                       || coalesce(round(coalesce(v_brate,0)*100)::text,'?') || '%' end,
    'evidence', jsonb_build_object(
      'window_runs', r.n, 'window_failed', r.f, 'window_rate', round(v_rate,4),
      -- Counted, reported, and excluded from the rate above. A caller turned away is not a fault
      -- of this subject; a SURGE of them is a signal the security build owns, not this one.
      'window_refused', r.refused,
      'window_held', r.held,
      'baseline_runs', r.bn, 'baseline_failed', r.bf,
      'baseline_rate', case when v_brate is null then null else round(v_brate,4) end,
      'baseline_basis', case when r.bn >= 10 then 'measured' else 'insufficient_history' end,
      'public_surface', r.pub,
      'surface_basis', case when r.known then 'supabase/config.toml verify_jwt'
                            else 'subject not in it_watch_subject; treated as internal' end));
end loop;

-- ══ D2. A SUBJECT THAT HAS STOPPED RUNNING WHEN IT SHOULD BE RUNNING ═══════════════════════
-- Reads: public.agent_runs, seven days of it.
-- The hard part is telling a SCHEDULED subject from an EVENT-DRIVEN one, because a subject that
-- only runs when a customer does something is supposed to be silent on a quiet day, and a
-- detector that cannot tell the difference is the "guard that fires when the system works" this
-- estate keeps paying for. Measured 9 Sep 2026, sales_engineer had 105 runs about a minute apart
-- inside a single two-hour burst and had then been silent for four hours — legitimately, because
-- it is event-driven. So a subject qualifies for silence monitoring only when its own history
-- shows a RHYTHM, on all three counts:
--   >= 10 gaps      — enough samples for a median to mean anything
--   >= 12 distinct hours with a run over 7 days — it recurs across time, it is not one burst
--   p90 gap <= 3x p50 gap — the gaps are TIGHT; a bursty subject has p90 far above p50
-- Then it is silent when it has been quiet for more than 4x its own median gap (floor 30 min).
-- ON AN IDLE ESTATE, measured on the live data: exactly ONE of the eight subjects in agent_runs
-- qualifies today — send_outbox (37 distinct hours, p50 30.1 min, p90 45.0 min, ratio 1.5).
-- login_otp (ratio 187), sales_engineer and accountant (2 and 4 distinct hours) are correctly
-- excluded as event-driven. The count of qualifying subjects is reported in notes.cadence, so
-- "no silence findings" can never be mistaken for "nothing is being watched".
v_watched := 0;
for r in
  with s0 as (
    select subject agent, started_at
    from it_runs7),
  g as (
    select agent, started_at,
           extract(epoch from (started_at - lag(started_at) over (partition by agent order by started_at)))/60 gap
    from s0),
  c as (
    select agent,
           count(*) filter (where gap > 0)::int                                   samples,
           count(distinct date_trunc('hour', started_at))::int                    hours,
           (percentile_cont(0.5) within group (order by gap) filter (where gap > 0))::numeric p50,
           (percentile_cont(0.9) within group (order by gap) filter (where gap > 0))::numeric p90,
           max(started_at)                                                        last_run
    from g group by agent)
  select c.*, coalesce(s.public_surface,false) pub,
         extract(epoch from (v_now - c.last_run))/60 silent_min
  from c left join public.it_watch_subject s on s.subject = c.agent
  where c.samples >= 10 and c.hours >= 12 and c.p50 > 0 and c.p90 <= c.p50 * 3
loop
  v_watched := v_watched + 1;
  continue when r.silent_min <= greatest(r.p50 * 4, 30);
  v_sev := public.fn_it_severity('stopped', r.pub);
  v_key := 'run_silent:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'run_silent', 'subject', r.agent,
    'state', 'stopped', 'severity', v_sev,
    'title', r.agent || ' has not run for ' || round(r.silent_min) || ' minutes; it normally runs every '
             || round(r.p50) || ' minutes',
    'evidence', jsonb_build_object(
      'silent_minutes', round(r.silent_min,1), 'last_run', r.last_run,
      'cadence_p50_min', round(r.p50,2), 'cadence_p90_min', round(r.p90,2),
      'cadence_samples', r.samples, 'distinct_hours_7d', r.hours,
      'threshold_min', round(greatest(r.p50 * 4, 30),1),
      'basis', 'measured from this subject''s own inter-run gaps over 7 days',
      'public_surface', r.pub));
end loop;
v_notes := v_notes || jsonb_build_object('cadence', jsonb_build_object(
  'subjects_with_a_measurable_rhythm', v_watched,
  'basis', case when v_watched = 0
                then 'no subject in agent_runs yet recurs regularly enough to have a cadence; silence cannot be detected for any subject'
                else 'measured' end));

-- ══ D3. THE SCHEDULER ITSELF ════════════════════════════════════════════════════════════════
-- Reads: public.agent_runs, the scheduler's own rows.  (Was: public.it_watch_tick. See below.)
-- The live scheduler is Vercel cron -> /api/resilience-ping -> resilience_ping, every 15 minutes.
-- pg_cron is dead by founder instruction (one inactive job; 234 deleted on 7 Sep), so any check
-- that reads cron.job_run_details to judge scheduler health is reading a table nothing writes.
--
-- 18 SEP 2026 — THE SCHEDULER WAS NEVER DOWN. THIS DETECTOR WAS, AND IT PUT ITS OWN NAME ON THE
-- FOUNDER'S 03:47Z "SCHEDULER DOWN — automation stalled" MAIL.
--   it_watch_tick has exactly ONE writer, and it is this function. Measured:
--     select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.prokind = 'f'
--        and pg_get_functiondef(p.oid) like '%insert into public.' || 'it_watch_tick%';
--     -> fn_it_detect, and nothing else.
--   So a hole in it_watch_tick never meant "the scheduler missed a tick". It meant "this function
--   did not reach its own last line" — a statement timeout, or a wait behind somebody's lock.
--   Measured over the exact hour the page covers, 18 Sep 2026:
--     it_watch_tick   03:15:38 -> 04:15:48         ONE row, a 60.2-minute hole
--     agent_runs      03:15:21, 03:30:21, 03:45:21, 04:00:22, 04:15:22  (fn:resilience_ping)
--     worst gap between two consecutive scheduler runs in the six hours around it: 15.01 minutes
--   Five consecutive ticks, none missed, none late by a second. Every one of them ran this
--   function; three of them did not get to the end of it, because the same six hours hold
--   resilience_ping wall times of 107 s, 141 s and 133 s against a 110 s deadline while the daily
--   export copied a 9.1 GB table. The detector reported its own three failures as the death of the
--   whole scheduler, at the top severity, to the founder.
--   The subject of a measurement is the thing measured. The scheduler is now read from the
--   scheduler's runs, and this function's own missed ticks keep a separate, lower-severity key, so
--   a detector that cannot finish says THAT, and never again says the company's automation stopped.
--
-- ON AN IDLE ESTATE: silent, because the scheduler ticks on an idle estate. On an estate with no
-- scheduler run recorded at all this does NOT go quiet: the scheduler demonstrably runs, so an
-- empty read means this detector has lost its subject (a renamed agent), and it says so.
select max(started_at) into v_prev from public.agent_runs
 where agent = 'fn:resilience_ping' and started_at > v_now - c_base;
if v_prev is null then
  -- Not a clean bill. 691 runs landed under this name in the seven days to 18 Sep 2026, so zero
  -- rows means the name moved, not that the scheduler is fine. Raised, not noted away.
  v_sev := public.fn_it_severity('degraded', false);
  v_key := 'scheduler_unreadable';
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'scheduler_gap', 'subject', 'scheduler',
    'state', 'degraded', 'severity', v_sev,
    'title', 'the scheduler cannot be read: no fn:resilience_ping run in 7 days, so its health is unknown',
    'evidence', jsonb_build_object(
      'agent_read', 'fn:resilience_ping', 'window_days', 7, 'rows_found', 0,
      'path','Vercel cron -> /api/resilience-ping -> resilience_ping',
      'basis','measured: agent_runs holds no row under the name this detector reads'));
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','unreadable','detail','no fn:resilience_ping run in agent_runs in 7 days'));
else
  v_gap := extract(epoch from (v_now - v_prev))/60;
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','measured','gap_minutes', round(v_gap,1), 'expected_minutes', 15, 'threshold_minutes', 45));
  if v_gap > 45 then
    v_sev := public.fn_it_severity('stopped', false);
    v_key := 'scheduler_gap';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'scheduler_gap', 'subject', 'scheduler',
      'state', 'stopped', 'severity', v_sev,
      'title', 'the 15-minute scheduler went ' || round(v_gap) || ' minutes without a tick — at least three were missed',
      'evidence', jsonb_build_object(
        'gap_minutes', round(v_gap,1), 'previous_tick', v_prev, 'expected_every_minutes', 15,
        'path','Vercel cron -> /api/resilience-ping -> resilience_ping',
        'basis','measured from the last fn:resilience_ping run in agent_runs — the scheduler''s own record, not this detector''s'));
  end if;
end if;

-- ── D3b. AND THIS DETECTOR'S OWN MISSED TICKS, UNDER THEIR OWN NAME ──────────────────────────
-- The old reading was not worthless, it was mislabelled: a hole in it_watch_tick is a real fault,
-- it is just this function's fault and not the scheduler's. It keeps its own key and 'degraded',
-- because the estate is still ticking and every other duty still ran; what is lost is detection.
select max(ran_at) into v_prev from public.it_watch_tick;
if v_prev is not null then
  v_gap := extract(epoch from (v_now - v_prev))/60;
  v_notes := v_notes || jsonb_build_object('detector_self', jsonb_build_object(
    'basis','measured','gap_minutes', round(v_gap,1), 'expected_minutes', 15, 'threshold_minutes', 45));
  if v_gap > 45 then
    v_sev := public.fn_it_severity('degraded', false);
    v_key := 'it_detector_ticks_missed';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'it_detector_ticks_missed', 'subject', 'fn_it_detect',
      'state', 'degraded', 'severity', v_sev,
      'title', 'the IT detector recorded no tick for ' || round(v_gap) || ' minutes: it ran and did not finish, so nothing was being detected',
      'evidence', jsonb_build_object(
        'gap_minutes', round(v_gap,1), 'previous_tick', v_prev, 'expected_every_minutes', 15,
        'look_at','agent_runs for fn:resilience_ping over the same window: if the ticks are there, the scheduler is fine and this function timed out or waited on a lock',
        'basis','measured from the interval between the last two it_watch_tick rows — this function''s own record'));
  end if;
end if;

-- ══ D4. DATABASE AND FUNCTION ERRORS ════════════════════════════════════════════════════════
-- Reads: public.error_events (the capture a sibling build is filling right now).
-- THIS IS THE DETECTOR MOST AT RISK OF THE "zero cannot tell a dead guard from an idle system"
-- failure, because error_events has held 0 rows for its entire existence. So it never reports a
-- clean bill from emptiness: capture_alive is computed from whether ANY row landed in seven days,
-- and while that is false the engine says 'no_capture_yet' out loud.
select count(*) into v_cnt from public.error_events where created_at > v_now - c_base;
v_notes := v_notes || jsonb_build_object('error_capture', jsonb_build_object(
  'capture_alive', v_cnt > 0, 'rows_7d', v_cnt,
  'basis', case when v_cnt > 0 then 'measured'
                else 'no_capture_yet — error_events is empty, so an absence of findings here proves nothing' end));
for r in
  select e.source, e.kind,
         count(*)::int n,
         count(*) filter (where lower(coalesce(e.severity,'error')) in ('critical','fatal'))::int crit,
         coalesce(s.public_surface,false) pub
  from public.error_events e
  left join public.it_watch_subject s on s.subject = e.source
  where e.created_at > v_now - c_win
    and lower(coalesce(e.severity,'error')) <> all (array['info','debug','notice','warn','warning'])
  group by e.source, e.kind, s.public_surface
loop
  v_state := case when r.crit > 0 then 'stopped' else 'degraded' end;
  v_sev   := public.fn_it_severity(v_state, r.pub);
  v_key   := 'error_events:' || coalesce(r.source,'?') || ':' || coalesce(r.kind,'?');
  v_keys  := v_keys || v_key;
  v_find  := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'error_events', 'subject', coalesce(r.source,'unknown'),
    'state', v_state, 'severity', v_sev,
    'title', r.n || ' ' || coalesce(r.kind,'error') || ' error(s) from ' || coalesce(r.source,'an unnamed source')
             || ' in the last hour' || case when r.crit > 0 then ', ' || r.crit || ' of them critical' else '' end,
    'evidence', jsonb_build_object(
      'window_errors', r.n, 'critical', r.crit, 'kind', r.kind,
      'public_surface', r.pub, 'basis','measured from error_events rows in the window'));
end loop;

-- ══ D5. A QUEUE NOBODY IS DRAINING ══════════════════════════════════════════════════════════
-- Reads: public.it_watch_queue, and each registered table by its own predicate.
-- The test is the AGE of the oldest pending row against that queue's own threshold — never the
-- depth. A backlog of 400 rows that is one minute old is a busy queue; one row that is nine weeks
-- old is a dead consumer.
-- ON AN IDLE ESTATE: a queue with nothing pending is skipped before any threshold is consulted,
-- so an empty estate produces nothing. The two queues that are genuinely stalled today
-- (exec_reports at status='new' since 6 July, doc_backups at status='error' since 11 July) do
-- fire, correctly — they are real, and neither is a business volume.
-- 18 SEP 2026 — A LOCK HELD BY SOMEBODY ELSE MUST NOT TAKE THE DETECTOR DOWN. Each read below is
-- a dynamic count over a watched table; measured 18 Sep, the doc_backups one costs 2–4 ms. Twice
-- that day the SAME read sat for 118,425 ms and 45,497 ms and the whole of fn_it_detect with it,
-- behind a writer on public.doc_backups (the Dropbox enqueue was split into a fast path and
-- fn_enqueue_doc_backups_backfill that morning). PostgREST cancels at 8 s, so the detector persisted
-- NOTHING — the 14 Sep outage this routine's own check names, arriving by a different road. The
-- handler below already turns an unreadable queue into a note and carries on; it never got the
-- chance, because waiting is not an error. 250 ms is the same bound fn_it_duties_scheduled's table
-- drill took on 14 Sep for the same reason.
--   RESTORED, NOT ZEROED (database review, 18 Sep): `set local lock_timeout = 0` would mean
--   "wait forever", and PostgREST's `authenticator` role carries `lock_timeout=8s` as a role
--   default (measured: rolconfig = statement_timeout=8s,lock_timeout=8s). Zeroing it would have
--   left D6-D8, which have no handler of their own, LESS protected than before this change. So the
--   caller's own value is captured and put back verbatim.
v_lock_prev := current_setting('lock_timeout');
perform set_config('lock_timeout', '250ms', true);
for r in select * from public.it_watch_queue where enabled order by queue_key loop
  begin
    execute format('select count(*), min(%I) from public.%I where %s', r.ts_column, r.table_name, r.pending_predicate)
      into v_cnt, v_oldest;
  exception when others then
    v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key,
      jsonb_build_object('basis','unreadable','error', sqlerrm));
    continue;
  end;
  continue when coalesce(v_cnt,0) = 0 or v_oldest is null;
  v_age := extract(epoch from (v_now - v_oldest))/60;

  -- DEPTH, DIVIDED BY THE QUEUE'S OWN MEASURED DRAIN. (18 Sep 2026, it_engineer.)
  -- The age arm below is deliberately not a depth test and that is right: on 18 Sep 2026 the
  -- Dropbox queue held 4,273 rows whose oldest was under two hours old, and it was a busy queue,
  -- not a broken one — 204 of them completed in the 17 minutes that were measured, 720 an hour,
  -- clearing the whole backlog in under six. A fixed row count would have paged the founder about
  -- a queue that was working, which is what an earlier depth rule did to notifications_whatsapp
  -- 226 times on 17 Sep.
  -- But age alone cannot see the one shape that matters: a queue filling faster than it empties.
  -- Every row in such a queue is young, and it still never clears. So where a queue records WHEN a
  -- row completed (it_watch_queue.drain_column), this arm divides the depth by the rows that
  -- actually completed in the last hour and reports the HOURS TO CLEAR.
  -- The threshold is not a row count somebody guessed. It is 24 hours, because every queue
  -- registered here is refilled at least daily, so a queue that cannot clear inside a day is a
  -- queue that never clears.
  -- A drain of ZERO with rows pending is the same statement with the division removed, and it is
  -- RAISED, not skipped: zero cannot tell a dead consumer from an idle one, so the pending rows
  -- decide — there is work, and in a whole hour nothing did any of it.
  -- drain_column NULL leaves this arm off for that queue, and the note says so rather than
  -- reporting a clean bill it did not measure.
  if r.drain_column is null then
    v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key || '_drain',
      jsonb_build_object('basis','not_measured',
        'detail','no drain_column registered for this queue, so its rate of clearing is unknown; only the age of its oldest row is checked'));
  else
    begin
      execute format('select count(*) from public.%I where %I > $1', r.table_name, r.drain_column)
        into v_drain using v_now - interval '1 hour';
    exception when others then
      v_drain := null;
      v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key || '_drain',
        jsonb_build_object('basis','unreadable','error', sqlerrm));
    end;
    if v_drain is not null then
      -- NULL hours means "never at this rate", and the test below treats it as past the threshold.
      v_hours := case when v_drain > 0 then v_cnt::numeric / v_drain else null end;
      v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key || '_drain',
        jsonb_build_object('basis','measured','pending', v_cnt, 'drained_last_hour', v_drain,
          'hours_to_clear', round(v_hours,1), 'threshold_hours', 24, 'drain_column', r.drain_column));
      -- 29 Sep 2026 (incidents 495, 554): a drain of ZERO says nothing about rows younger than the hour it
      -- was counted over. doc_backups is filled in a daily batch (~23:12 UTC) and drained within ~20 minutes;
      -- the arm fired 4 minutes after the batch landed. Zero now counts only once the oldest pending row has
      -- waited the full hour: a dead consumer is still raised, one tick later.
      if (v_hours is null or v_hours > 24) and not (v_drain = 0 and v_age < 60) then
        v_state := case when v_drain = 0 then 'stopped' else 'degraded' end;
        v_sev   := public.fn_it_severity(v_state, r.surface = 'customer');
        v_key   := 'queue_not_draining:' || r.queue_key;
        v_keys  := v_keys || v_key;
        v_find  := v_find || jsonb_build_object(
          'detector_key', v_key, 'detector', 'queue_not_draining', 'subject', r.queue_key,
          'state', v_state, 'severity', v_sev,
          'title', r.table_name || ': ' || v_cnt || ' row(s) waiting and ' || v_drain
                   || ' cleared in the last hour — '
                   || case when v_drain = 0 then 'nothing is draining this queue'
                           else round(v_hours) || ' hours to clear, past the 24-hour threshold' end,
          'evidence', jsonb_build_object(
            'pending_rows', v_cnt, 'drained_last_hour', v_drain,
            'hours_to_clear', round(v_hours,1), 'threshold_hours', 24,
            'drain_column', r.drain_column, 'predicate', r.pending_predicate,
            'oldest_pending', v_oldest, 'public_surface', r.surface = 'customer',
            'basis','measured: the depth now, divided by the rows this queue completed in the last hour'));
      end if;
    end if;
  end if;

  continue when v_age <= r.stall_minutes;
  v_state := case when v_age > r.stall_minutes * 4 then 'stopped' else 'degraded' end;
  v_sev   := public.fn_it_severity(v_state, r.surface = 'customer');
  v_key   := 'queue_stalled:' || r.queue_key;
  v_keys  := v_keys || v_key;
  v_find  := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'queue_stalled', 'subject', r.queue_key,
    'state', v_state, 'severity', v_sev,
    'title', r.table_name || ': ' || v_cnt || ' undrained row(s), the oldest waiting '
             || round(v_age/60) || ' hours against a ' || round(r.stall_minutes/60.0) || '-hour threshold',
    'evidence', jsonb_build_object(
      'pending_rows', v_cnt, 'oldest_pending', v_oldest, 'oldest_age_minutes', round(v_age,1),
      'threshold_minutes', r.stall_minutes, 'predicate', r.pending_predicate,
      'public_surface', r.surface = 'customer',
      'basis','measured from the age of the oldest row matching the predicate'));
end loop;
perform set_config('lock_timeout', v_lock_prev, true);

-- ══ D6. LATENCY — THE FOUNDER'S OWN EXAMPLE ═════════════════════════════════════════════════
-- Reads: public.agent_runs, finished_at - started_at.
-- "Lagging" is meaningless without a baseline, so the baseline is each subject's own trailing
-- seven days ENDING at the start of the window (the window cannot pollute its own reference).
-- A departure has to clear three bars at once, and the three exist to stop three different false
-- positives: above the subject's own p95 (not just above typical), at least double its median
-- (not a 5% drift), and at least one second in absolute terms (so a 2ms -> 5ms move on a subject
-- that does nothing is not an incident).
--
-- WHAT IT DOES ON DAY ONE, said plainly rather than implied. Measured on the live data, 9 Sep:
--   send_outbox   65 samples, p50 9,956ms, p95 21,320ms -> 'measured'. Armed. Fires above ~21.3s.
--   sales_engineer / accountant / compliance_archive — every duration is exactly 0ms, because
--       their writer sets finished_at = started_at. Zero spread is not a fast subject, it is NO
--       SIGNAL, and it is reported as 'no_latency_signal' rather than as a healthy baseline.
--   login_otp / dropbox_backup / quote_extract / doc_extract — under 20 samples ->
--       'insufficient_history'.
-- So exactly ONE subject has a real latency baseline today. Every subject the sibling build
-- instruments with timing will arm itself here automatically once it has 20 runs; nothing needs
-- editing. The per-subject basis is returned in notes.latency every tick, so the founder's
-- "the comparison report is lagging" can be answered with either a departure or an honest "there
-- is not enough history of that report yet to know", and never with a false all-clear.
v_basis := '{}'::jsonb;
for r in
  -- A 403 returned in four milliseconds is not a measurement of how long this subject's work
  -- takes, so refusals are excluded from the baseline as well as from the failure rate. Left in,
  -- they would drag the baseline down and make ordinary work look like a departure.
  with d as (
    select subject agent, started_at,
           extract(epoch from (finished_at - started_at)) * 1000 ms
    from it_runs7
    where finished_at is not null and finished_at >= started_at
      and not refused0),
  b as (
    select agent, count(*)::int n,
           (percentile_cont(0.50) within group (order by ms))::numeric p50,
           (percentile_cont(0.95) within group (order by ms))::numeric p95,
           min(ms)::numeric mn, max(ms)::numeric mx
    from d where started_at <= v_now - c_win group by agent),
  w as (
    select agent, count(*)::int n,
           (percentile_cont(0.50) within group (order by ms))::numeric p50
    from d where started_at > v_now - c_win group by agent)
  select b.agent, b.n bn, b.p50 bp50, b.p95 bp95, b.mn bmn, b.mx bmx,
         w.n wn, w.p50 wp50, coalesce(s.public_surface,false) pub
  from b
  left join w on w.agent = b.agent
  left join public.it_watch_subject s on s.subject = b.agent
loop
  v_state := null;
  if r.bn < 20 then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','insufficient_history','baseline_samples', r.bn, 'samples_needed', 20));
  elsif r.bmx = r.bmn then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','no_latency_signal','constant_ms', round(r.bmn),
      'detail','every recorded duration is identical, so this subject reports no timing to depart from'));
  elsif coalesce(r.wn,0) < 3 then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','insufficient_window','window_samples', coalesce(r.wn,0), 'samples_needed', 3,
      'baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95)));
  else
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','measured','baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95),
      'window_p50_ms', round(r.wp50), 'window_samples', r.wn,
      'fires_above_ms', round(greatest(r.bp95, r.bp50 * 2, 1000))));
    if r.wp50 > r.bp95 and r.wp50 >= r.bp50 * 2 and r.wp50 >= 1000 then
      v_state := 'delayed';
    end if;
  end if;
  continue when v_state is null;
  v_sev  := public.fn_it_severity(v_state, r.pub);
  v_key  := 'latency:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'latency', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', r.agent || ' is taking ' || round(r.wp50) || 'ms, against its own baseline of '
             || round(r.bp50) || 'ms (p95 ' || round(r.bp95) || 'ms)',
    'evidence', jsonb_build_object(
      'window_p50_ms', round(r.wp50), 'window_samples', r.wn,
      'baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95), 'baseline_samples', r.bn,
      'rule','window p50 > baseline p95 AND >= 2x baseline p50 AND >= 1000ms',
      'public_surface', r.pub, 'basis','measured against this subject''s own trailing 7 days'));
end loop;
v_notes := v_notes || jsonb_build_object('latency', v_basis);

-- ══ D7. THE WEBSITE ═════════════════════════════════════════════════════════════════════════
-- Reads: p_web, the reading the caller took this tick. Postgres cannot fetch, so the tick fetches
-- and Postgres judges — the same division this estate already uses for the OpenRouter meter.
-- Four separate questions, because they fail separately:
--   is it up            home.status outside 2xx/3xx, or a fetch that threw   -> stopped -> CRITICAL
--   did a deploy fail   latest production deployment state ERROR/CANCELED    -> degraded -> HIGH
--   runtime errors      Vercel's runtime error count in the window           -> degraded -> HIGH
--   is it slow          home.ms against the site's own history in it_watch_tick -> delayed
-- The website is public_surface = true by definition, which is why a site that does not answer
-- outranks everything else the engine can find.
-- ON AN IDLE ESTATE: an idle site still answers, so silence here means the site answered. When no
-- reading was taken it reports 'not_probed_this_tick' and NEVER reads as a clean bill.
if p_web is null then
  v_notes := v_notes || jsonb_build_object('website', jsonb_build_object(
    'basis','not_probed_this_tick',
    'detail','no reading was passed to fn_it_detect; the site was not checked and is NOT being reported as healthy'));
else
  v_site_st := nullif(p_web #>> '{home,status}','')::int;
  v_site_ms := nullif(p_web #>> '{home,ms}','')::numeric::int;

  if v_site_st is null or v_site_st < 200 or v_site_st >= 400 then
    v_sev  := public.fn_it_severity('stopped', true);
    v_key  := 'website_down';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'website_down', 'subject', 'website',
      'state','stopped','severity', v_sev,
      'title', case when v_site_st is null
                    then 'the website did not answer at all: ' || coalesce(p_web #>> '{home,error}','no status and no error was reported')
                    else 'the website answered HTTP ' || v_site_st end,
      'evidence', jsonb_build_object(
        'status', v_site_st, 'url', p_web #>> '{home,url}', 'error', p_web #>> '{home,error}',
        'ms', v_site_ms, 'public_surface', true, 'basis','measured by HTTP request this tick'));
  end if;

  if upper(coalesce(p_web #>> '{deployment,state}','')) in ('ERROR','CANCELED') then
    v_sev  := public.fn_it_severity('degraded', true);
    v_key  := 'website_deploy_failed';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'website_deploy_failed', 'subject', 'website',
      'state','degraded','severity', v_sev,
      'title', 'the latest production deployment is ' || (p_web #>> '{deployment,state}')
               || ' — the site is still serving the previous build, so new work is not live',
      'evidence', jsonb_build_object(
        'deployment', p_web -> 'deployment', 'public_surface', true,
        'basis','measured from the Vercel deployments API this tick'));
  end if;

  -- Runtime errors. Probed 9 Sep 2026 with the stored app_secrets.vercel_token: there is no
  -- runtime-log endpoint this token can read — /v1/projects/<id>/runtime-logs,
  -- /v1/deployments/<uid>/runtime-logs and /v1/observability/runtime-logs all return 404, and the
  -- deployment `events` endpoints return BUILD output only. So the caller may legitimately be
  -- unable to supply a count, and when it cannot, THIS IS SAID rather than counted as zero: a
  -- monitor that reports "no runtime errors" because it could not look is the exact failure this
  -- whole file is built to avoid.
  if (p_web -> 'runtime_errors') ? 'count' then
    v_notes := v_notes || jsonb_build_object('website_runtime_errors', jsonb_build_object(
      'basis','measured', 'count', (p_web #>> '{runtime_errors,count}')::int,
      'window_minutes', coalesce(p_web #>> '{runtime_errors,window_minutes}','60')));
    if (p_web #>> '{runtime_errors,count}')::int > 0 then
      v_sev  := public.fn_it_severity('degraded', true);
      v_key  := 'website_runtime_errors';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'website_runtime_errors', 'subject', 'website',
        'state','degraded','severity', v_sev,
        'title', (p_web #>> '{runtime_errors,count}') || ' runtime error(s) on the website in the last '
                 || coalesce(p_web #>> '{runtime_errors,window_minutes}','60') || ' minutes',
        'evidence', jsonb_build_object(
          'runtime_errors', p_web -> 'runtime_errors', 'public_surface', true,
          'basis','measured from the Vercel runtime error API this tick'));
    end if;
  else
    v_notes := v_notes || jsonb_build_object('website_runtime_errors', jsonb_build_object(
      'basis', coalesce(p_web #>> '{runtime_errors,basis}', 'not_reported'),
      'reason', coalesce(p_web #>> '{runtime_errors,reason}',
                'the caller supplied no runtime error count; the website''s runtime errors were NOT checked and are NOT being reported as absent')));
  end if;

  -- Site latency, on the same terms as D6: the site's own history, or an honest refusal.
  -- The samples are the site_ms column of this very table, which is why the tick stores it.
  if v_site_ms is null then
    v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
      'basis','not_timed','detail','the reading carried no home.ms'));
  else
    declare
      s_n int; s_p50 numeric; s_p95 numeric;
    begin
      select count(*)::int,
             (percentile_cont(0.50) within group (order by site_ms))::numeric,
             (percentile_cont(0.95) within group (order by site_ms))::numeric
        into s_n, s_p50, s_p95
      from public.it_watch_tick
      where ran_at > v_now - c_base and ran_at <= v_now - c_win and site_ms is not null and site_status between 200 and 399;
      if coalesce(s_n,0) < 20 then
        v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
          'basis','insufficient_history','samples', coalesce(s_n,0), 'samples_needed', 20,
          'current_ms', v_site_ms,
          'detail','the site has no baseline yet; it needs 20 timed ticks, which is about five hours at one tick every fifteen minutes'));
      else
        v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
          'basis','measured','baseline_p50_ms', round(s_p50), 'baseline_p95_ms', round(s_p95),
          'current_ms', v_site_ms, 'samples', s_n,
          'fires_above_ms', round(greatest(s_p95, s_p50 * 2, 1000))));
        if v_site_ms > s_p95 and v_site_ms >= s_p50 * 2 and v_site_ms >= 1000 then
          v_sev  := public.fn_it_severity('delayed', true);
          v_key  := 'website_slow';
          v_keys := v_keys || v_key;
          v_find := v_find || jsonb_build_object(
            'detector_key', v_key, 'detector', 'website_slow', 'subject', 'website',
            'state','delayed','severity', v_sev,
            'title','the website answered in ' || v_site_ms || 'ms, against its own baseline of '
                    || round(s_p50) || 'ms (p95 ' || round(s_p95) || 'ms)',
            'evidence', jsonb_build_object(
              'current_ms', v_site_ms, 'baseline_p50_ms', round(s_p50), 'baseline_p95_ms', round(s_p95),
              'baseline_samples', s_n, 'public_surface', true,
              'rule','current > baseline p95 AND >= 2x baseline p50 AND >= 1000ms',
              'basis','measured against the site''s own timed ticks over 7 days'));
        end if;
      end if;
    end;
  end if;
end if;

-- ══ D8. THE DATABASE BACKUP CHAIN ═══════════════════════════════════════════════════════════
-- Reads: pg_stat_archiver. Added 9 September 2026.
--
-- WHY THIS DETECTOR EXISTS. fn_backup_watch spent its whole life reading `agent_runs where
-- agent = 'backup'` — a name nothing has ever written — so it reported "no successful backup for
-- as long as there are records" on every single call, at severity critical. That was fixed the
-- same day, and fixing it exposed the real hole underneath: NOTHING watched the Postgres backups
-- at all. The document mirror had a watcher. The database that holds the company did not.
--
-- WHY pg_stat_archiver AND NOT THE MANAGEMENT API. The daily physical backups are taken outside
-- this database and their status is only readable through the Supabase management API, which needs
-- a personal access token this estate does not hold and which would give an edge function full
-- project admin. But those backups are built on continuous WAL archiving, and pg_stat_archiver is
-- the archiver's own counter, readable from inside with no credential at all. If archiving stops,
-- the backup chain stops, and this sees it within the hour. It is the mechanism rather than the
-- report, which makes it earlier and cheaper — and it is honest about being a proxy.
--
-- WHAT IT CANNOT SEE, SAID OUT LOUD: whether a nightly snapshot COMPLETED. Healthy archiving with
-- a broken snapshot pipeline would read clean here. That gap is real and is named in the note
-- rather than left for someone to discover the way I discovered the last one.
--
-- ON AN IDLE ESTATE. archived_count is cumulative since stats_reset, so a database that has never
-- archived a segment reports 0 — and 0 means "this instrument has never seen the thing work",
-- which is exactly the shape that produced today's false critical. So zero is NOT a finding here.
-- It goes to notes as unproven, and the detector declines to conclude.
begin
  select archived_count, last_archived_time, failed_count, last_failed_time, stats_reset
    into v_arch_n, v_arch_at, v_arch_fail, v_arch_fail_at, v_arch_reset
    from pg_stat_archiver;

  if v_arch_n is null or v_arch_n = 0 then
    -- POSITIVE CONTROL, and the whole lesson of the backup watcher in one branch: an instrument
    -- that has never once seen success cannot tell you about failure.
    v_notes := v_notes || jsonb_build_object('wal_archiving', jsonb_build_object(
      'basis','unproven',
      'detail','pg_stat_archiver reports no archived segment since ' || coalesce(v_arch_reset::text,'(no reset recorded)')
            || '. That means this instrument has never observed archiving working, so it declines to '
            || 'report a fault it could not distinguish from its own blindness.'));
  else
    v_arch_age := extract(epoch from (v_now - v_arch_at))/60;

    -- FAILING NOW: the archiver recorded a failure inside the window. failed_count is cumulative
    -- and would be true forever after one bad hour in May, so the test is the TIME of the last
    -- failure, not the count.
    if v_arch_fail_at is not null and v_arch_fail_at > v_now - c_win then
      v_key  := 'backup_chain:wal_archiving_failing';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'backup_chain', 'subject', 'wal_archiving',
        'state', 'stopped', 'severity', 'critical',
        'title', 'WAL archiving failed at ' || v_arch_fail_at::text
                 || ' — the database backup chain is breaking, and every daily snapshot is built on it',
        'evidence', jsonb_build_object(
          'archived_count', v_arch_n, 'last_archived_time', v_arch_at,
          'failed_count', v_arch_fail, 'last_failed_time', v_arch_fail_at,
          'stats_reset', v_arch_reset, 'public_surface', false,
          'basis','measured from pg_stat_archiver; the test is the TIME of the last failure inside the window, never the cumulative count',
          'not_covered','whether a nightly physical snapshot COMPLETED — that is only readable through the management API'));

    -- STALLED: nothing archived for an hour. Over the recorded life of this instrument the estate
    -- archives roughly one segment every few minutes, so an hour of silence is not quiet traffic.
    elsif v_arch_age > 60 then
      v_key  := 'backup_chain:wal_archiving_stalled';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'backup_chain', 'subject', 'wal_archiving',
        'state', case when v_arch_age > 240 then 'stopped' else 'degraded' end,
        'severity', case when v_arch_age > 240 then 'critical' else 'high' end,
        'title', 'No WAL segment archived for ' || round(v_arch_age/60) || ' hour(s) — the backup chain may have stopped',
        'evidence', jsonb_build_object(
          'archived_count', v_arch_n, 'last_archived_time', v_arch_at,
          'age_minutes', round(v_arch_age,1), 'threshold_minutes', 60,
          'failed_count', v_arch_fail, 'stats_reset', v_arch_reset, 'public_surface', false,
          'basis','measured from pg_stat_archiver.last_archived_time',
          'not_covered','whether a nightly physical snapshot COMPLETED — that is only readable through the management API'));
    else
      v_notes := v_notes || jsonb_build_object('wal_archiving', jsonb_build_object(
        'basis','measured','archived_count', v_arch_n,
        'last_archived_minutes_ago', round(v_arch_age,1),
        'failures_ever', v_arch_fail,
        'not_covered','whether a nightly physical snapshot COMPLETED — only the management API can say'));
    end if;
  end if;
exception when others then
  -- pg_stat_archiver is a system view; if it ever becomes unreadable that is worth SEEING rather
  -- than swallowing, but it must not take the other seven detectors down with it.
  v_notes := v_notes || jsonb_build_object('wal_archiving',
    jsonb_build_object('basis','unreadable','error', sqlerrm));
end;

-- ══ D9. POLITE REFUSALS — A CUSTOMER TURNED AWAY IS INVISIBLE EVERYWHERE ELSE ════════
-- Reads: public.agent_runs (a 24-hour window against the 7 days before it), public.it_watch_subject.
-- Added 9 September 2026 on founder instruction 18: "Every polite refusal is invisible to IT."
--
-- WHY NOTHING ELSE SEES THIS, and why neither half of the blindness was a mistake.
--   supabase/functions/_shared/observe.ts records status='warn' for EVERY 4xx response, and 'warn'
--   is on D1's c_ok list, so a refused request is not 'bad'. Then fn_it_run_is_refusal removes 4xx
--   rows from D1's numerator AND its denominator, so they cannot move the rate either. Both are
--   correct FOR D1: turning away a malformed or unauthenticated request is not that subject's
--   fault, and counting it would make every secret-gated internal function look broken. The
--   consequence is that a subject can refuse everybody and D1 computes a failure rate of exactly
--   0.00. Measured today on the live table: login_otp, which is customer sign-in, returned
--   skipped 88 / 404 24 / 409 6 / 400 1 / 200 6 over seven days — 119 of 125 attempts turned away —
--   and D1 reported nothing whatsoever, because not one of those statuses is 'bad'. 'skipped' is on
--   the success list too, so even the handler's own "I refused a real customer" row read as health.
--
-- WHY THIS IS NOT "COUNT THE 4xx". Refusing a bad request is right most of the time, so a count
-- would fire on every secret-gated function the moment anything probed it, and an engine that
-- fires on everything is as useless as one that fires on nothing. The test is a SHARE, and it may
-- only conclude in two shapes:
--   dominance — a PUBLIC surface (it_watch_subject.public_surface) whose refusals are at least half
--               its traffic. A path a customer opens that turns away most callers is a broken front
--               door whatever the reason; there is no benign version of that number on a public
--               surface. Above 90% it is 'stopped' rather than 'degraded'.
--   departure — ANY subject, public or internal, whose refusal share is 30 points above its own
--               trailing baseline. This is the arm that catches a path that USED to work; without
--               it a rise from 2% to 40% on a private function stays silent forever.
-- Neither arm looks at an absolute count, and severity runs through fn_it_severity(state, public),
-- so the same departure is 'medium' internally and 'high' on a customer surface.
--
-- WHY 24 HOURS AND NOT THE 60-MINUTE WINDOW EVERY OTHER DETECTOR USES. Measured, not assumed: the
-- whole login_otp refusal burst ran 07:34–08:36 today, and the tick that would have judged it runs
-- at 17:4x. A one-hour window sees ZERO of those 125 attempts and returns a clean bill on the exact
-- fault this detector exists for. A refusal pattern is a customer-experience aggregate rather than
-- an outage; the unit that matters is "how many people did we turn away today". The baseline is the
-- seven days ENDING where this window starts, so the window cannot pollute its own reference.
--
-- WHY 'skipped' COUNTS AS A REFUSAL, BUT ONLY ON A PUBLIC SURFACE. This is the one judgement in the
-- detector, so it is written down instead of left inside a predicate. On an internal scheduled job
-- 'skipped' means "there was nothing to do", which is the healthiest thing a drainer can say, and
-- counting it would fire on every idle queue in the estate. On a surface a customer opens, a run
-- exists only because a customer arrived, so 'skipped' means "a real person asked and we said no".
-- login_otp's own note says exactly that — "refused an SMS sign-in because more than one customer
-- account carries this mobile number" — and that row is currently counted as a success. public_
-- surface is precisely the line between the two meanings, it is already in it_watch_subject, and it
-- needs no new column and no per-subject allowlist.
--
-- THE DOUBLE LOG, and why it had to be handled before any share could be trusted. This estate
-- writes TWO rows for one refused request: the handler's semantic row (agent 'login_otp', status
-- 'skipped') and observe.ts's telemetry row (agent 'fn:login_otp', status 'warn', counts.http 404),
-- milliseconds apart. A SUCCESS writes only the telemetry row. Counting both logs would therefore
-- inflate every refusal share while leaving successes alone. A semantic row that has a telemetry
-- twin within five seconds is dropped — the same ±5s pairing fn_it_run_is_refusal already relies on.
-- Measured effect on login_otp today: 118 rows become 106 attempts, and the share falls from a
-- false 1.0000 to a true 0.9434.
--
-- WHAT THIS DETECTOR CANNOT SEE. Stated here rather than left for somebody to discover:
--   1. A refusal that never reaches the handler. The platform's own JWT gate, a CORS preflight, a
--      gateway 429 and a cold-start 5xx each turn a customer away WITHOUT writing an agent_runs
--      row, so they are invisible to this detector and to every other one in this file. ZERO IS
--      AMBIGUOUS here: it cannot distinguish "nobody was turned away" from "nobody arrived" from
--      "the logging itself stopped".
--   2. Whether the refusal was RIGHT, and WHO was refused. A surface under a bot flood and a
--      surface with a broken identity lookup produce identical numbers; so do a real customer and
--      a rehearsal probe, because agent_runs carries no caller identity at all. That matters for
--      the very finding this detector was built to raise: login_otp's 106 attempts today are a
--      seeded burst as much as they are real people, and this engine cannot separate the two. It
--      reports that a customer-facing surface is turning callers away. Whether those callers were
--      customers is a question only the surface itself could answer, and it does not record it.
--      (22 Sep 2026: login_otp now does answer it for the fixture block — counts.fixture, excluded below.
--      Every other surface still does not.)
--   3. Anything under 20 logged attempts in 24 hours. customer_api refused 7 of 7 callers today and
--      sits below that floor, so it is NOT evaluated. The number of subjects skipped for thin
--      traffic is published in notes.refusals every tick so that silence can never be read as
--      health.
--   4. An internal path that has ALWAYS refused everything. It has no baseline to depart from and
--      it is not a public surface, so neither arm can fire. That is deliberate — a secret-gated
--      function refusing anonymous probes is correct — but a permanently broken internal auth path
--      reads clean here, and only a person noticing the constant would ever catch it.
v_ref_eval := 0;
v_ref_thin := 0;
for r in
  with rows0 as (
    select a.subject, a.agent, a.started_at, a.status, a.counts
    from it_runs7 a
    where true
      -- 14 Sep 2026: a request made inside a rehearsal window is the test harness, not a customer.
      -- Measured: all 264 non-policy login_otp refusals of the day fell inside e2e rehearsal windows and
      -- none outside, and the finding they raised was hours from emailing the founder. The demo
      -- hygiene duty closes any window left open past six hours, which bounds what this can hide.
      -- (the rehearsal flag is computed once per row in D0, as a set; see D0)
      and not a.rehearsal
      -- 22 Sep 2026: a run the SERVER marked as fixture traffic (login_otp: the number is in the reserved
      -- block +971 50 000 00xx, which no real person holds) is our harness or a probe, window or no window.
      -- Measured: all 58 refusals behind "login_otp turned away 58 of 69" carried fixture numbers.
      and not (a.counts ? 'fixture')
      -- drop the semantic half of a double-logged request; see THE DOUBLE LOG above
      and not (a.agent not like 'fn:%' and exists (
        select 1 from public.agent_runs t
        where t.agent = 'fn:' || a.agent
          and t.started_at between a.started_at - interval '5 seconds'
                               and a.started_at + interval '5 seconds'))),
  j as (
    select r0.subject, r0.started_at,
           coalesce(s.public_surface,false) pub, (s.subject is not null) known,
           -- fn_it_run_is_refusal's four telemetry shapes, MINUS its ±5s neighbour arm. That arm
           -- exists to lend a 4xx to a semantic row whose own counts say nothing; applied to a
           -- telemetry row inside a burst it marks a genuine 200 as refused because a NEIGHBOURING
           -- request 4xx'd two seconds later. Measured: it turned login_otp's six real successes
           -- into refusals and reported a share of 1.0000 instead of 0.9434. The paired rows are
           -- already removed above, so the arm has nothing left to do here.
           ((r0.counts ->> 'http') ~ '^4[0-9][0-9]$'
            or (r0.counts ->> 'signal') in ('forbidden','bad_secret')
            or (r0.counts ->> 'authorised') = '0'
            or coalesce(nullif(r0.counts ->> 'forbidden','')::int, 0) > 0
            or (coalesce(s.public_surface,false) and r0.status = 'skipped'))
           -- ...AND IT IS NOT THE PLATFORM ENFORCING A RULE. Added within the hour of D9 shipping,
           -- because D9's first live read raised a CRITICAL finding that login_otp turns away 94%
           -- of callers -- and 81 of those 100 refusals were two registered guards doing exactly
           -- what the founder specified ("a phone may confirm, never select; email is the
           -- identity"). A detector built to stop real refusals being ignored was about to page him
           -- because his own rules are being obeyed. The exemption is a REGISTER, not the log's own
           -- word for itself: it_refusal_policy holds an explicit (subject, reason) pair with the
           -- rule it enforces written in the row, so opting out of monitoring takes a reviewable
           -- act rather than a flattering sentence in a note.
           -- fn_it_refusal_is_policy's rule, as the same EXISTS written inline (see D0 for why).
           and not exists (select 1 from public.it_refusal_policy p
                            where p.subject = regexp_replace(coalesce(r0.subject,''), '^fn:', '')
                              and coalesce(r0.counts, '{}'::jsonb) ? p.reason_key) refused
    from rows0 r0
    left join public.it_watch_subject s on s.subject = r0.subject),
  w as (
    select subject, pub, known, count(*)::int n, count(*) filter (where refused)::int ref
    from j where started_at > v_now - c_ref_win group by 1,2,3),
  b as (
    select subject, count(*)::int n, count(*) filter (where refused)::int ref
    from j where started_at <= v_now - c_ref_win group by 1)
  select w.subject agent, w.pub, w.known, w.n, w.ref,
         coalesce(b.n,0) bn, coalesce(b.ref,0) bref
  from w left join b on b.subject = w.subject
  order by w.subject
loop
  -- Thin traffic is NOT a clean bill. It is counted and published, never silently dropped.
  if r.n < c_ref_min then
    v_ref_thin := v_ref_thin + 1;
    continue;
  end if;
  v_ref_eval := v_ref_eval + 1;
  v_share  := r.ref::numeric / r.n;
  v_bshare := case when r.bn >= c_ref_min then r.bref::numeric / r.bn else null end;
  v_state := case
               -- the absolute arm only while the surface has no measured baseline of its own
               when r.pub and v_bshare is null and v_share >= 0.90 then 'stopped'
               when r.pub and v_bshare is null and v_share >= 0.50 then 'degraded'
               -- a baselined public surface that departs AND is refusing nearly everything is still 'stopped'
               when r.pub and v_share >= 0.90 and (v_share - v_bshare) >= 0.30 then 'stopped'
               when v_bshare is not null and (v_share - v_bshare) >= 0.30 then 'degraded'
               else null end;
  continue when v_state is null;
  v_sev  := public.fn_it_severity(v_state, r.pub);
  v_key  := 'refusal_rate:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'refusal_rate', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', r.agent || ' turned away ' || r.ref || ' of the ' || r.n
             || ' callers it logged in the last 24 hours (' || round(v_share*100) || '%'
             || case when v_bshare is null then ', with no comparable baseline of its own'
                     else ', against its own baseline of ' || round(v_bshare*100) || '%' end || ')'
             || case when r.pub then ' — and this is a surface a customer opens' else '' end,
    'evidence', jsonb_build_object(
      'window_hours', 24, 'window_attempts', r.n, 'window_refused', r.ref,
      'window_refusal_share', round(v_share,4),
      'baseline_attempts', r.bn, 'baseline_refused', r.bref,
      'baseline_refusal_share', case when v_bshare is null then null else round(v_bshare,4) end,
      'baseline_basis', case when r.bn >= c_ref_min then 'measured' else 'insufficient_history' end,
      'arm', case when r.pub and v_bshare is null and v_share >= 0.50
                  then 'dominance: a public surface refusing at least half of its logged traffic'
                  else 'departure: refusal share at least 30 points above this subject''s own baseline' end,
      'public_surface', r.pub,
      'surface_basis', case when r.known then 'it_watch_subject.public_surface'
                            else 'subject not in it_watch_subject; treated as internal' end,
      'refusal_definition','counts.http 4xx, or counts.signal forbidden/bad_secret, or counts.authorised=0, or counts.forbidden>0, or status=''skipped'' on a public surface',
      'basis','measured from agent_runs over 24 hours, with semantic rows that have a telemetry twin removed',
      'not_covered','a refusal that never reaches the handler (platform JWT gate, CORS preflight, gateway 429, cold-start 5xx) writes no agent_runs row and is invisible here'));
end loop;
v_notes := v_notes || jsonb_build_object('refusals', jsonb_build_object(
  'window_hours', 24, 'minimum_attempts', c_ref_min,
  'subjects_evaluated', v_ref_eval,
  'subjects_below_minimum', v_ref_thin,
  'basis', case when v_ref_eval = 0
                then 'no subject logged ' || c_ref_min || ' or more attempts in 24 hours, so NOTHING was evaluated and an absence of refusal findings proves nothing'
                else 'measured' end,
  'not_covered','refusals that never reach the handler write no agent_runs row; and this detector cannot tell a correct refusal from a broken one'));

-- ══ THE VERDICT ═════════════════════════════════════════════════════════════════════════════
select coalesce(
  (select f ->> 'severity' from jsonb_array_elements(v_find) f
    order by case f ->> 'severity' when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end
    limit 1), 'none')
into v_worst;

-- ══ THE LEDGER — open while true, resolved the tick after it stops being true ═══════════════
if p_persist then
  insert into public.it_watch_finding
    (detector_key, detector, subject, state, severity, title, evidence, opened_at, last_seen_at, seen_count, status, resolved_at)
  select f ->> 'detector_key', f ->> 'detector', f ->> 'subject', f ->> 'state', f ->> 'severity',
         f ->> 'title', f -> 'evidence', v_now, v_now, 1, 'open', null
  from jsonb_array_elements(v_find) f
  on conflict (detector_key) do update set
    -- A finding that reappears after being resolved is a NEW occurrence, so opened_at restarts.
    -- One that never closed keeps its original opened_at, which is what makes "how long has this
    -- been broken" answerable.
    opened_at    = case when public.it_watch_finding.status = 'resolved' then excluded.opened_at
                        else public.it_watch_finding.opened_at end,
    seen_count   = case when public.it_watch_finding.status = 'resolved' then 1
                        else public.it_watch_finding.seen_count + 1 end,
    detector     = excluded.detector,
    subject      = excluded.subject,
    state        = excluded.state,
    severity     = excluded.severity,
    title        = excluded.title,
    evidence     = excluded.evidence,
    last_seen_at = excluded.last_seen_at,
    status       = 'open',
    resolved_at  = null;
  get diagnostics v_opened = row_count;

  update public.it_watch_finding
     set status = 'resolved', resolved_at = v_now
   where status = 'open' and not (detector_key = any (v_keys));
  get diagnostics v_resolved = row_count;

  insert into public.it_watch_tick (ran_at, findings, worst, site_ms, site_status, detail)
  values (v_now, jsonb_array_length(v_find), v_worst, v_site_ms, v_site_st,
          jsonb_build_object('findings', v_find, 'notes', v_notes, 'web', p_web));
end if;

return jsonb_build_object(
  'ok', true,
  'at', v_now,
  'window_minutes', 60,
  'baseline_days', 7,
  'worst', v_worst,
  'finding_count', jsonb_array_length(v_find),
  'findings', v_find,
  'notes', v_notes,
  'persisted', p_persist,
  'ledger_upserted', v_opened,
  'ledger_resolved', v_resolved);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_it_digest_hold_ends(p_created_at timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select ((date_trunc('day', (p_created_at + interval '24 hours') at time zone 'Asia/Dubai')
           + interval '19 hours'
           + case when ((p_created_at + interval '24 hours') at time zone 'Asia/Dubai')::time > time '19:00'
                  then interval '1 day' else interval '0' end)
          at time zone 'Asia/Dubai') + interval '2 hours';
$function$


CREATE OR REPLACE FUNCTION public.fn_it_dnsbl_listed(p_list text, p_answers jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(bool_or(
           case when p_list = 'dbl.spamhaus.org' then m[1]::int = 1 and m[2]::int between 2 and 254
                else m[1]::int = 0 and m[2]::int between 2 and 254 end), false)
    from jsonb_array_elements_text(case when jsonb_typeof(p_answers) = 'array' then p_answers else '[]'::jsonb end) a,
         regexp_match(a, '^127\.0\.(\d{1,3})\.(\d{1,3})$') m
$function$


CREATE OR REPLACE FUNCTION public.fn_it_dropbox_health_due()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select not exists (select 1 from public.agent_runs r where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_health'
                        and r.status in ('ok', 'warn') and r.started_at > now() - interval '1 day'
                        and (r.started_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date)
     and not exists (select 1 from public.agent_runs r where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_health'
                        and r.status = 'error' and r.started_at > now() - interval '2 hours');
$function$


CREATE OR REPLACE FUNCTION public.fn_it_dropbox_health_record(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_quiet numeric := coalesce(public.fn_it_threshold('dropbox_space_quiet_pct'), 70);
  v_loud  numeric := coalesce(public.fn_it_threshold('dropbox_space_loud_pct'), 85);
  v_ok boolean; v_cls text; v_pct numeric; v_status text;
  v_login jsonb := '[]'::jsonb; v_space jsonb := '[]'::jsonb; v_login_out jsonb; v_space_out jsonb;
  v_classes constant text[] := array['auth', 'quota', 'rate_limit', 'provider_outage', 'network', 'internal'];
begin
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'fn_it_dropbox_health_record: the reading must be a json object'; end if;

  v_ok := p->>'error' is null and coalesce((p->>'write_ok')::boolean, false) and coalesce((p->>'read_ok')::boolean, false)
          and coalesce((p->>'delete_ok')::boolean, false);
  if not v_ok then
    -- a class the edge did not name, or named wrongly, is ours to explain: internal
    v_cls := case when p->>'class' = any (v_classes) then p->>'class' else 'internal' end;
    v_login := jsonb_build_array(jsonb_build_object('item', v_cls,
      'title', case v_cls
        when 'auth'            then 'Dropbox refused the company''s stored login; backups are not reaching Dropbox'
        when 'quota'           then 'Dropbox refused the daily probe write because the account is full'
        when 'rate_limit'      then 'Dropbox rate-limited the daily probe'
        when 'provider_outage' then 'Dropbox answered the daily probe with a server error'
        when 'network'         then 'Dropbox could not be reached for the daily probe'
        else                        'The daily Dropbox probe failed for an internal reason' end,
      'blast', case when v_cls in ('rate_limit', 'provider_outage', 'network') then 'internal' else 'agent_facing' end,
      'affected', 1, 'owner_seat', 'ceo', 'subject', 'dropbox_backup',
      'evidence', jsonb_build_object('class', v_cls, 'error', left(p->>'error', 300), 'auth_ok', p->'auth_ok',
                                     'write_ok', p->'write_ok', 'read_ok', p->'read_ok', 'delete_ok', p->'delete_ok',
                                     'look_at', 'dropbox_backup op health; agent_runs job dropbox_health')));
  end if;
  v_login_out := public.fn_it_duty_settle('dropbox_login', v_login);

  if coalesce(p->>'allocated', '') ~ '^[0-9]+(\.[0-9]+)?$' and coalesce(p->>'used', '') ~ '^[0-9]+(\.[0-9]+)?$'
     and (p->>'allocated')::numeric > 0 then
    v_pct := round((p->>'used')::numeric * 100 / (p->>'allocated')::numeric, 1);
    if v_pct >= v_loud then
      v_space := jsonb_build_array(jsonb_build_object('item', 'space_loud',
        'title', 'Dropbox is ' || v_pct || '% full (loud at ' || v_loud || '%); at 100% new documents stop reaching Dropbox',
        'blast', 'agent_facing', 'affected', 1, 'owner_seat', 'ceo', 'subject', 'dropbox_backup',
        'evidence', jsonb_build_object('pct_used', v_pct, 'used', p->'used', 'allocated', p->'allocated', 'plan', p->'plan', 'threshold', v_loud)));
    elsif v_pct >= v_quiet then
      v_space := jsonb_build_array(jsonb_build_object('item', 'space_quiet',
        'title', 'Dropbox is ' || v_pct || '% full (quiet at ' || v_quiet || '%, loud at ' || v_loud || '%)',
        'blast', 'internal', 'affected', 0, 'owner_seat', 'ceo', 'subject', 'dropbox_backup',
        'evidence', jsonb_build_object('pct_used', v_pct, 'used', p->'used', 'allocated', p->'allocated', 'plan', p->'plan', 'threshold', v_quiet)));
    end if;
    v_space_out := public.fn_it_duty_settle('dropbox_space', v_space);
  elsif v_ok then
    -- the login works and the space did not read: say so, and leave what the last reading found open
    perform public.fn_it_engineer_finding_upsert('duty:dropbox_space:space_unread',
      'The Dropbox login works but the space used could not be read', 'IT engineer duty: dropbox_space',
      'internal', 0, jsonb_build_object('duty', 'dropbox_space', 'owner_seat', 'ceo', 'subject', 'dropbox_backup', 'demo', false,
        'space_error', left(p->>'space_error', 300), 'space_class', p->>'space_class'),
      '{}'::text[], '{}'::text[], 'it_engineer.dropbox_space');
  else
    -- login probe AND space read both failed: any open dropbox_space finding is deliberately left untouched this tick; the login finding is already loud, and space is re-evaluated on the next good reading
    null;
  end if;

  v_status := case when not v_ok then 'error'
                   when v_pct is null or v_pct >= v_quiet then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, jsonb_build_object('job', 'dropbox_health', 'pct_used', v_pct, 'class', v_cls) || p,
          left('Dropbox health: write ' || coalesce(p->>'write_ok', 'false') || ', read ' || coalesce(p->>'read_ok', 'false')
               || ', delete ' || coalesce(p->>'delete_ok', 'false') || '; '
               || coalesce(v_pct::text || '% of the ' || coalesce(p->>'plan', 'unknown') || ' plan used', 'space not read')
               || coalesce('; ' || v_cls || ': ' || (p->>'error'), ''), 500), now(), now());
  return jsonb_build_object('status', v_status, 'pct_used', v_pct, 'class', v_cls, 'login', v_login_out, 'space', v_space_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_duties(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_out jsonb := '{}'::jsonb; v_items jsonb; x record; s jsonb; v_mode text; v_hook jsonb; v_missing text[];
  v_p95 numeric; v_hour int;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_it_duties takes the readings object from _shared/it_duty_readings.ts';
  end if;

  -- ── 2. LIVE == CODE ──
  -- Reads: the latest main commit's GitHub check runs ('checks', 'deploy functions') and the Vercel
  -- production deployment for that commit. The canonical routine manifest itself runs inside the
  -- 'checks' workflow, so its conclusion is the drift verdict. Cannot see: drift introduced after the
  -- last merge by a live apply with no commit (the manifest check in the next CI run catches that).
  if (p_r->'github'->>'basis') = 'measured' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(coalesce(p_r->'github'->'conclusions', '{}'::jsonb)) loop
      if x.value #>> '{}' not in ('success', 'skipped', 'neutral', 'in_progress', 'queued') then
        v_items := v_items || jsonb_build_object('item', 'ci:' || x.key, 'owner_seat', 'ceo', 'subject', 'github',
          'title', 'On main ' || left(p_r->'github'->>'sha', 7) || ', "' || x.key || '" ended ' || (x.value #>> '{}')
                   || ' — what is live may not be what is merged',
          'blast', 'agent_facing', 'affected', 1, 'evidence', p_r->'github');
      end if;
    end loop;
    if (p_r->'vercel'->>'basis') = 'measured' and coalesce(p_r->'vercel'->>'state', '') not in ('READY', 'BUILDING', 'QUEUED', 'INITIALIZING') then
      v_items := v_items || jsonb_build_object('item', 'vercel', 'owner_seat', 'ceo', 'subject', 'website',
        'title', 'The website deployment for main ' || left(p_r->'github'->>'sha', 7) || ' is ' || coalesce(p_r->'vercel'->>'state', 'missing'),
        'blast', 'customer_facing', 'affected', 0, 'evidence', p_r->'vercel');
    end if;
    v_out := v_out || jsonb_build_object('live_code', public.fn_it_duty_settle('live_code', v_items));
  else
    v_out := v_out || jsonb_build_object('live_code', jsonb_build_object('basis', coalesce(p_r->'github'->>'basis', 'not_read'), 'reason', p_r->'github'->>'reason'));
  end if;

  -- ── 3. EXPIRIES ──
  -- Reads: it_expiry (licences from the founder, domains from RDAP, TLS from crt.sh), internal_credential
  -- expires_at, and each provider credential answering a harmless authenticated GET. Cannot see: a
  -- provider key's own expiry date — Stripe, Resend, Twilio and Dropbox do not publish one, so the
  -- test is whether the key still works today. Credentials used to rotate on a pg_cron job that went
  -- with the 7 Sep removal and no routine rotates them now, so an expiry inside 30 days is handed on.
  for x in select key, value from jsonb_each(coalesce(p_r->'expiries', '{}'::jsonb)) loop
    if (x.value->>'expires_on') is not null then
      update public.it_expiry set expires_on = (x.value->>'expires_on')::date, checked_at = now() where item = x.key;
    end if;
  end loop;
  v_items := '[]'::jsonb;
  -- Certificates only: licences, domains and tokens are warned to the accountant at 60 and 30 days by
  -- fn_it_renewal_watch (renewals_warn_the_accountant_at_sixty_and_thirty_days.sql).
  for x in select * from public.it_expiry where kind = 'tls' and expires_on is not null and expires_on < current_date + 30 loop
    v_items := v_items || jsonb_build_object('item', x.item, 'owner_seat', x.owner_seat, 'subject', x.item,
      'title', x.item || ' expires on ' || x.expires_on || ' (' || (x.expires_on - current_date) || ' days)',
      'blast', case when x.expires_on < current_date + 7 then 'customer_facing' else 'agent_facing' end, 'affected', 1,
      'evidence', jsonb_build_object('route', x.route, 'source', x.source, 'checked_at', x.checked_at));
  end loop;
  -- Only what cannot rotate itself: a legacy credential, or one whose secret has no app_secrets key
  -- (duty 15, the_it_engineer_takes_on_seven_more_duties.sql, rotates the rest 30 days ahead).
  for x in select ic.context, ic.expires_at from public.internal_credential ic
            where ic.active and ic.expires_at is not null and ic.expires_at < now() + interval '30 days'
              and (ic.is_legacy or not exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'))) loop
    v_items := v_items || jsonb_build_object('item', 'credential:' || x.context, 'owner_seat', 'ceo', 'subject', x.context,
      'title', 'Internal credential ' || x.context || ' expires ' || to_char(x.expires_at, 'DD Mon YYYY') || ' and cannot be rotated automatically',
      'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('expires_at', x.expires_at));
  end loop;
  v_out := v_out || jsonb_build_object('expiry', public.fn_it_duty_settle('expiry', v_items));

  -- Provider credentials are their own duty so a tick without the providers reading leaves them as
  -- they were instead of closing them.
  if jsonb_typeof(p_r->'providers') = 'object' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(p_r->'providers') loop
      if (x.value->>'basis') = 'measured' and (x.value->>'status')::int in (401, 403) then
        v_items := v_items || jsonb_build_object('item', x.key,
          'owner_seat', coalesce(x.value->>'owner_seat', 'ceo'), 'subject', x.key,
          'title', 'The ' || x.key || ' credential was refused (HTTP ' || (x.value->>'status') || ')',
          'blast', 'customer_facing', 'affected', 1, 'evidence', x.value);
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('credential', public.fn_it_duty_settle('credential', v_items));
  end if;

  -- ── 4. DELIVERY CONFIRMATION ──
  -- Reads: the delivery loop (customer_support's build) — every delivery.request gets a delivery.result
  -- back to its originator, which records detail.loop. What IT watches is that the loop CLOSED: a request
  -- older than two hours with no loop verdict, and an email marked sent with no provider id.
  v_items := '[]'::jsonb;
  for x in select a.id, a.detail->>'from' frm, a.created_at from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'type' = 'delivery.request'
              and a.created_at < now() - interval '2 hours' and a.created_at > now() - interval '7 days'
              and not (a.detail ? 'loop') and a.title not ilike '%ZZ DEMO%'
              -- 22 Sep 2026: a founder-bound request customer_support holds for the 19:00 Dubai IT digest
              -- is waiting on a schedule, not lost. It is late only once the digest could have taken it.
              and not (a.status = 'pending' and a.evidence->>'digest' = 'pending'
                       -- 29 Sep 2026 (incident 484): the digest ages a new bug by its FINDING's started_at
                       -- ("still young: judged again tomorrow"), and a finding that re-opened restarts that
                       -- clock. Handoff 80605 was created 23 Sep 12:31Z for duty:handoff_sla:it.finding:ceo:unclosed;
                       -- the finding re-opened 24 Sep 07:00Z, so the 24 Sep digest held it as young and took it
                       -- on 25 Sep, while this duty, timing from the handoff, called it late at 29 hours. The
                       -- hold now runs from the later of the two clocks, the one the digest actually obeys.
                       and now() < public.fn_it_digest_hold_ends(greatest(a.created_at, coalesce(
                         (select f.started_at from public.it_engineer_finding f
                           where f.issue_key = regexp_replace(a.detail->>'dedupe_key', '^it_new_bug:', '')
                             and f.closed_at is null), a.created_at)))) loop
    v_items := v_items || jsonb_build_object('item', 'request:' || x.id, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
      'title', 'Delivery request ' || x.id || ' from ' || x.frm || ' has had no confirmed outcome for '
               || round(extract(epoch from now() - x.created_at) / 3600) || ' hours',
      'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('handoff_id', x.id));
  end loop;
  for x in select n.id, n.to_role, n.sent_at from public.notifications n
            where n.status = 'sent' and n.channel = 'email' and coalesce(btrim(n.provider_message_id), '') = ''
              and n.sent_at > now() - interval '48 hours' loop
    v_items := v_items || jsonb_build_object('item', 'notification:' || x.id, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
      'title', 'Email ' || x.id || ' to the ' || coalesce(x.to_role, 'recipient') || ' is marked sent but the provider never gave it an id',
      'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('notification_id', x.id, 'sent_at', x.sent_at));
  end loop;
  v_out := v_out || jsonb_build_object('delivery', public.fn_it_duty_settle('delivery', v_items));

  -- ── 4b. EVERY HANDOFF IS ANSWERED ──
  -- Reads: every pending handoff against its seat_handoff_kind.reply_within (every_handoff_is_answered_
  -- within_its_window.sql). Cannot see: a conversation that was never started -- only one that stalled.
  v_out := v_out || jsonb_build_object('handoff_sla', public.fn_it_duty_settle('handoff_sla', public.fn_it_handoff_sla_items()));

  -- ── 5. PAYMENT RECONCILIATION ──
  -- Reads: Stripe live and test — completed Checkout Sessions and refunds of the last 72 hours, and the
  -- webhook endpoints' enabled events against HANDLED_STRIPE_EVENTS (passed in from
  -- _shared/stripe_events.ts, the list the webhook itself branches on). IT checks the wiring; the
  -- accountant owns the money and answers every mismatch. A mode whose key is absent is reported, not
  -- treated as matched.
  v_items := '[]'::jsonb;
  for v_mode in select unnest(array['live', 'test']) loop
    s := p_r->'stripe'->v_mode;
    continue when coalesce(s->>'basis', '') <> 'measured';
    for x in select e from jsonb_array_elements(coalesce(s->'paid_sessions', '[]'::jsonb)) e loop
      if not exists (select 1 from public.transactions t
                      where t.payment_ref in (x.e->>'id', x.e->>'payment_intent')) then
        v_items := v_items || jsonb_build_object('item', v_mode || ':session:' || (x.e->>'id'), 'owner_seat', 'accountant',
          'subject', 'stripe_webhook',
          'title', 'Stripe ' || v_mode || ' took AED ' || round(coalesce((x.e->>'amount_total')::numeric, 0) / 100, 2)
                   || ' in session ' || (x.e->>'id') || ' and no transaction records it',
          'blast', 'customer_facing', 'affected', 1, 'demo', v_mode = 'test', 'evidence', x.e);
      end if;
    end loop;
    for x in select e from jsonb_array_elements(coalesce(s->'refunds', '[]'::jsonb)) e loop
      if not exists (select 1 from public.refunds r where r.stripe_refund_id = x.e->>'id')
         and not exists (select 1 from public.transactions t where t.refund_stripe_id = x.e->>'id') then
        v_items := v_items || jsonb_build_object('item', v_mode || ':refund:' || (x.e->>'id'), 'owner_seat', 'accountant',
          'subject', 'stripe_webhook',
          'title', 'Stripe ' || v_mode || ' refunded ' || (x.e->>'id') || ' and our books do not record it',
          'blast', 'customer_facing', 'affected', 1, 'demo', v_mode = 'test', 'evidence', x.e);
      end if;
    end loop;
    v_hook := (select e from jsonb_array_elements(coalesce(s->'webhooks', '[]'::jsonb)) e
                where e->>'url' like '%/functions/v1/stripe_webhook%' and e->>'status' = 'enabled' limit 1);
    select array_agg(h) into v_missing from jsonb_array_elements_text(coalesce(p_r->'stripe'->'handled', '[]'::jsonb)) h
     where v_hook is null or not (v_hook->'enabled_events' ? h or v_hook->'enabled_events' ? '*');
    if v_missing is not null then
      v_items := v_items || jsonb_build_object('item', v_mode || ':webhook', 'owner_seat', 'accountant', 'subject', 'stripe_webhook',
        'title', case when v_hook is null then 'No enabled Stripe ' || v_mode || ' webhook points at stripe_webhook'
                      else 'The Stripe ' || v_mode || ' webhook does not send ' || array_to_string(v_missing, ', ') end,
        'blast', 'customer_facing', 'affected', 0, 'demo', v_mode = 'test',
        'evidence', jsonb_build_object('missing', to_jsonb(v_missing), 'endpoint', v_hook));
    end if;
  end loop;
  if coalesce(p_r->'stripe'->'live'->>'basis', '') = 'measured' or coalesce(p_r->'stripe'->'test'->>'basis', '') = 'measured' then
    v_out := v_out || jsonb_build_object('payment', public.fn_it_duty_settle('payment', v_items));
  else
    v_out := v_out || jsonb_build_object('payment', jsonb_build_object('basis', 'not_read', 'reading', p_r->'stripe'));
  end if;

  -- ── 6. SECURITY SWEEP ──
  -- Reads: the catalogue (routines anon/authenticated may execute with the definer's rights, tables with
  -- RLS off or on with no policy) against it_security_baseline, and sign-in codes sent in the last hour
  -- against this estate's own hourly p95 over seven days. Cannot see: the Supabase security advisors
  -- (management API, run in CI by security_advisors_match_the_baseline.mjs). A known fix — a revoke or
  -- a pinned search_path — is shipped only as a file with a MANIFEST line in a PR, never live.
  v_items := '[]'::jsonb;
  for x in select e.object, e.kind from public.fn_it_security_exposures() e
            where not exists (select 1 from public.it_security_baseline b where b.object = e.object and b.kind = e.kind) loop
    v_items := v_items || jsonb_build_object('item', x.kind || ':' || x.object, 'owner_seat', 'ceo', 'subject', x.object,
      'title', case x.kind when 'anon_executable_definer' then 'Anyone, signed in or not, can run ' || x.object || ' with the definer''s rights'
                           when 'authenticated_executable_definer' then 'Any signed-in user can run ' || x.object || ' with the definer''s rights, and it never checks who they are'
                           when 'rls_off' then 'Table ' || x.object || ' has row security switched off'
                           else 'Table ' || x.object || ' has row security on and no policy, and a browser role can read it' end,
      'blast', 'security', 'affected', 1,
      'evidence', jsonb_build_object('kind', x.kind, 'baseline_size', (select count(*) from public.it_security_baseline),
                                     'fix', 'a file with a MANIFEST line in a PR: revoke execute / enable RLS and add a policy'));
  end loop;
  select coalesce(percentile_cont(0.95) within group (order by n), 0) into v_p95
    from (select date_trunc('hour', created_at) h, count(*) n from public.customer_phone_otps
           where created_at > now() - interval '7 days' and created_at <= now() - interval '1 hour' group by 1) z;
  select count(*) into v_hour from public.customer_phone_otps where created_at > now() - interval '1 hour';
  if v_hour > greatest(10, 3 * v_p95) then
    v_items := v_items || jsonb_build_object('item', 'otp_spike', 'owner_seat', 'ceo', 'subject', 'login_otp',
      'title', v_hour || ' sign-in codes were sent in the last hour against an hourly p95 of ' || round(v_p95),
      'blast', 'security', 'affected', 1, 'evidence', jsonb_build_object('last_hour', v_hour, 'p95_hourly_7d', v_p95));
  end if;
  v_out := v_out || jsonb_build_object('security', public.fn_it_duty_settle('security', v_items));

  -- ── 7. UPTIME ──
  -- Reads: each public origin answered this hour. fn_it_detect already judges the edge functions'
  -- failure rates (D1, with the founder's hold now counted as held) and public_site_url's latency; this
  -- adds the other origins. Cannot see: that a UAE visitor is really sent to .ae — the redirect keys on
  -- Vercel's x-vercel-ip-country, which an outside request cannot set. What is checked is its other
  -- half: that quotesdone.ae itself serves the site.
  if jsonb_typeof(p_r->'sites') = 'array' then
    v_items := '[]'::jsonb;
    for x in select e from jsonb_array_elements(p_r->'sites') e loop
      if coalesce((x.e->>'status')::int, 0) not between 200 and 399 then
        v_items := v_items || jsonb_build_object('item', x.e->>'url', 'owner_seat', 'ceo', 'subject', 'website',
          'title', x.e->>'url' || ' ' || coalesce('answered HTTP ' || (x.e->>'status'), 'did not answer: ' || coalesce(x.e->>'error', 'no status')),
          'blast', 'customer_facing', 'affected', 1, 'evidence', x.e);
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('uptime', public.fn_it_duty_settle('uptime', v_items));
  end if;

  -- ── 8. DEMO HYGIENE ──
  -- Reads: demo customers and suppliers (is_demo, or the harness's qd-<tag>- address) created more
  -- than six hours ago outside an open rehearsal window. A leftover is a demo row that can reach a
  -- count; the harness purges its own tag, so one that survives is a teardown fault. Cannot see: a
  -- dashboard that counts demo rows while none exist — with zero leftovers there is nothing to leak.
  v_items := '[]'::jsonb;
  -- THE FOUNDER'S STANDING DEMO IS NOT A LEFTOVER (22 Sep 2026, PR #831; see the file header).
  for x in select 'customers' t, count(*) n, (array_agg(c.id::text order by c.created_at))[1:10] ids from public.customers c
            where (c.is_demo or c.email like 'qd-%@example.invalid') and c.created_at < now() - interval '6 hours'
              and coalesce(c.email, '') not like 'qd-founderdemo-%'
           union all
           select 'leads', count(*), (array_agg(l.id::text order by l.created_at))[1:10] from public.leads l
            where (l.is_demo or l.email like 'qd-%@example.invalid') and l.created_at < now() - interval '6 hours'
              and coalesce(l.email, '') not like 'qd-founderdemo-%' loop
    -- Only a run still in progress excuses leftovers. Measured on the proof: four e2e windows and one
    -- from 5 Sep were never closed, and "any open window" silenced this check for good.
    if x.n > 0 and not exists (select 1 from public.rehearsal_window w
                                where w.ended_at is null and w.started_at > now() - interval '6 hours') then
      v_items := v_items || jsonb_build_object('item', x.t, 'owner_seat', 'ceo', 'subject', 'e2e_harness',
        'title', x.n || ' demo ' || x.t || ' row(s) outlived their run by more than six hours',
        'blast', 'internal', 'affected', 1, 'demo', true,
        'evidence', jsonb_build_object('table', x.t, 'rows', x.n, 'ids', to_jsonb(x.ids), 'purge', 'node scripts/e2e/run.mjs --purge-tag <tag>'));
    end if;
  end loop;
  -- A rehearsal window left open is a run that never tore down.
  for x in select w.id, w.run_tag, w.opened_by, w.started_at from public.rehearsal_window w
            where w.ended_at is null and w.started_at < now() - interval '6 hours' loop
    v_items := v_items || jsonb_build_object('item', 'window:' || x.id, 'owner_seat', 'ceo', 'subject', 'e2e_harness',
      'title', 'Rehearsal window ' || x.run_tag || ' (' || x.opened_by || ') has been open since '
               || to_char(x.started_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
      -- agent_facing, so it is handed on at once: an open window already silences the failed-run pager.
      'blast', 'agent_facing', 'affected', 1, 'demo', true,
      'evidence', jsonb_build_object('rehearsal_window_id', x.id, 'close', 'update public.rehearsal_window set ended_at = now() where id = ' || x.id));
  end loop;
  v_out := v_out || jsonb_build_object('demo', public.fn_it_duty_settle('demo', v_items));

  -- ── 1. THE NIGHTLY JOURNEY'S HEARTBEAT ──
  -- The run itself reports through fn_it_journey_ingest. Silence for 26 hours is its own finding —
  -- but only once this tick has itself been running for 26 hours. Measured 14 Sep 2026: the first cut
  -- raised "no run" the hour it was deployed, before nightly-journey.yml's first 22:00 UTC schedule
  -- had come round (the repository secret it uses has existed since 7 Sep).
  v_items := '[]'::jsonb;
  if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duties'
              and started_at < now() - interval '26 hours')
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'journey'
                  and started_at > now() - interval '26 hours') then
    v_items := jsonb_build_array(jsonb_build_object('item', 'no_run', 'owner_seat', 'ceo', 'subject', 'e2e_harness',
      'title', 'The nightly full-journey test has not reported for 26 hours',
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('workflow', '.github/workflows/nightly-journey.yml',
        'look_at', 'the workflow''s runs in GitHub Actions: not triggered, failed, or failed to report')));
  end if;
  v_out := v_out || jsonb_build_object('journey_heartbeat', public.fn_it_duty_settle('journey_heartbeat', v_items));

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'duties', 'result', v_out), null);
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_duties_due()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duties'
                      and started_at > now() - interval '55 minutes')
$function$


CREATE OR REPLACE FUNCTION public.fn_it_duties_scheduled(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_due text[] := public.fn_it_scheduled_due(); v_out jsonb := '{}'::jsonb; v_items jsonb; x record; e jsonb;
  d public.doc_backups; v_n numeric; v_d numeric; v_rate numeric; v_mult numeric; v_floor numeric;
  v_p90 numeric; v_max int; v_lim numeric; v_used numeric; c record; v_rot int := 0;
begin
  if jsonb_typeof(coalesce(p_r, '{}'::jsonb)) <> 'object' then
    raise exception 'fn_it_duties_scheduled takes the readings object from _shared/it_scheduled_readings.ts';
  end if;
  v_out := v_out || jsonb_build_object('workflow_heartbeat', public.fn_it_workflow_heartbeats());

  -- ── 9a. RESTORE DRILL ──
  -- Reads: the sample the tick downloaded — each file opened from Dropbox (content hash and size) and
  -- from Supabase storage (size) — against what doc_backups recorded when it was backed up.
  if 'restore' = any (v_due) and jsonb_typeof(p_r->'restore'->'samples') = 'array' then
    v_items := '[]'::jsonb;
    for e in select s from jsonb_array_elements(p_r->'restore'->'samples') s loop
      select * into d from public.doc_backups where id = (e->>'doc_backup_id')::bigint;
      if d.id is null then continue; end if;
      -- Duty 19 (founder, 14 Sep 2026: "add all for accountant and IT"): a restored copy must also open.
      -- Compared as text so a reading taken before duty 19 (no 'opens' key) is not failed for it.
      if not coalesce((e->'dropbox'->>'ok')::boolean, false)
         or (e->'dropbox'->>'opens') = 'false'
         or (d.dropbox_content_hash is not null and e->'dropbox'->>'content_hash' is distinct from d.dropbox_content_hash)
         or (d.dropbox_size is not null and (e->'dropbox'->>'size')::bigint is distinct from d.dropbox_size) then
        v_items := v_items || jsonb_build_object('item', 'dropbox:' || d.id, 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
          'title', 'Restore drill: ' || coalesce(d.file_name, d.dropbox_path) || ' did not come back intact from Dropbox',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('doc_backup_id', d.id, 'dropbox_path', d.dropbox_path, 'recorded_hash', d.dropbox_content_hash,
                                         'recorded_size', d.dropbox_size, 'restored', e->'dropbox'));
      end if;
      -- Duty 19: the storage copy must open and must be the same file as the Dropbox copy.
      if d.bucket is not null and (not coalesce((e->'storage'->>'ok')::boolean, false)
         or (e->'storage'->>'opens') = 'false'
         or (e->'storage'->>'content_hash' is not null and e->'dropbox'->>'content_hash' is not null
             and e->'storage'->>'content_hash' <> e->'dropbox'->>'content_hash')
         or (d.bytes is not null and (e->'storage'->>'size')::bigint is distinct from d.bytes)) then
        v_items := v_items || jsonb_build_object('item', 'storage:' || d.id, 'owner_seat', 'sales_engineer', 'subject', 'storage',
          'title', 'Restore drill: ' || coalesce(d.file_name, d.path) || ' did not come back intact from Supabase storage',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('doc_backup_id', d.id, 'bucket', d.bucket, 'path', d.path, 'recorded_bytes', d.bytes,
                                         'restored', e->'storage'));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('restore', public.fn_it_duty_settle('restore', v_items));
    perform public.fn_it_duty_ran('restore', v_out->'restore');
  end if;

  -- ── 9b. OPEN GAPS IN THE BACKUP REGISTRY ──
  -- 15 Sep 2026: a reasoned EXEMPT is not a gap (it raised all 51 before: the destination column, the
  -- PDPL ledger, repository paths ...). A gap is (a) a registry source not backed up and not EXEMPT --
  -- an OPEN GAP, or a row nobody classified -- and (b) per swept bucket, the stored files over a day old
  -- that still have no doc_backups row. No item key carries ':', so every finding is
  -- 'duty:backup_gap:<item>' and the founder's digest shows the family as one line with its count.
  if 'backup_gap' = any (v_due) then
    v_items := '[]'::jsonb;
    for x in select * from public.fn_backup_source_registry() r
              where not r.backed_up and coalesce(r.reason, '') !~ '^EXEMPT' loop
      v_items := v_items || jsonb_build_object('item', replace(x.source, ':', '/'), 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
        'title', 'Not backed up to Dropbox: ' || x.source || coalesce(' — ' || x.reason, ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('source', x.source, 'kind', x.kind, 'bucket', x.bucket));
    end loop;
    for x in select s.bucket, count(*) as n, round(sum(s.bytes) / 1048576.0, 2) as mb, min(s.path) as sample
               from public.fn_backup_sweep_objects() s
              where s.created_at < now() - interval '24 hours'
                and not exists (select 1 from public.doc_backups db where db.bucket = s.bucket and db.path = s.path)
              group by s.bucket loop
      v_items := v_items || jsonb_build_object('item', 'storage/' || x.bucket, 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
        'title', 'Not backed up to Dropbox: ' || x.n || ' stored file(s) in ' || x.bucket || ' still have no backup row after 24 hours',
        'blast', 'agent_facing', 'affected', x.n,
        'evidence', jsonb_build_object('bucket', x.bucket, 'files', x.n, 'mb', x.mb, 'sample', x.sample));
    end loop;
    v_out := v_out || jsonb_build_object('backup_gap', public.fn_it_duty_settle('backup_gap', v_items));
    perform public.fn_it_duty_ran('backup_gap', v_out->'backup_gap');
  end if;

  -- ── 10. SENDER HEALTH ──
  -- Reads: DNS (SPF, DMARC, DKIM) and blocklists by DNS-over-HTTPS, Resend's own verdict on each
  -- domain record, Twilio's WhatsApp sender quality and template approvals — and from our own tables
  -- the hard bounces and complaints resend_webhook recorded against the emails we sent.
  if 'sender' = any (v_due) and jsonb_typeof(p_r->'sender') = 'object' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(coalesce(p_r->'sender'->'dns', '{}'::jsonb)) loop
      if coalesce(x.value->>'basis', '') = 'measured' then
        if not coalesce((x.value->>'spf')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'spf:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no SPF record that includes our sender', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
        if not coalesce((x.value->>'dmarc')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'dmarc:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no DMARC record', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
        if not coalesce((x.value->>'dkim')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'dkim:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no DKIM key published for our sender', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
      end if;
    end loop;
    for e in select b from jsonb_array_elements(coalesce(p_r->'sender'->'blocklists', '[]'::jsonb)) b loop
      if e->>'basis' = 'measured' and public.fn_it_dnsbl_listed(e->>'list', e->'answers') then
        v_items := v_items || jsonb_build_object('item', 'blocklist:' || (e->>'list') || ':' || (e->>'target'), 'owner_seat', 'customer_support',
          'subject', 'send_outbox', 'title', (e->>'target') || ' is listed on ' || (e->>'list'),
          'blast', 'customer_facing', 'affected', 1, 'evidence', e);
      end if;
    end loop;
    if coalesce(p_r->'sender'->'resend'->>'basis', '') = 'measured' and coalesce(p_r->'sender'->'resend'->>'status', '') <> 'verified' then
      v_items := v_items || jsonb_build_object('item', 'resend_domain', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
        'title', 'Resend reports the sending domain as ' || coalesce(p_r->'sender'->'resend'->>'status', 'unknown'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'resend');
    end if;
    if coalesce(p_r->'sender'->'whatsapp'->>'basis', '') = 'measured'
       and upper(coalesce(p_r->'sender'->'whatsapp'->>'quality', '')) not in ('HIGH', 'GREEN', 'UNKNOWN') then
      v_items := v_items || jsonb_build_object('item', 'whatsapp_quality', 'owner_seat', 'customer_support', 'subject', 'send_whatsapp',
        'title', 'The WhatsApp number''s quality rating is ' || (p_r->'sender'->'whatsapp'->>'quality'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'whatsapp');
    end if;
    for e in select t from jsonb_array_elements(coalesce(p_r->'sender'->'templates', '[]'::jsonb)) t loop
      if e->>'basis' = 'measured' and lower(coalesce(e->>'status', '')) not in ('approved') then
        v_items := v_items || jsonb_build_object('item', 'template:' || (e->>'name'), 'owner_seat', 'customer_support', 'subject', 'send_whatsapp',
          'title', 'WhatsApp template ' || (e->>'name') || ' is ' || coalesce(e->>'status', 'unknown'),
          'blast', 'customer_facing', 'affected', 0, 'evidence', e);
      end if;
    end loop;
    select count(*) into v_d from public.notifications
     where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
    if v_d >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20) then
      select count(*) filter (where reason like 'hard_bounce%'), count(*) filter (where reason = 'spam_complaint')
        into v_n, v_rate from public.email_suppressions
       where source = 'resend_webhook' and created_at > now() - interval '7 days';
      v_items := v_items || public.fn_it_sender_rate_items(v_d, v_n, v_rate);
    end if;
    -- DMARC aggregate reports (rua) read by _shared/it_scheduled_readings.ts dmarcReports(). An
    -- 'unavailable' reading (no report arrived) raises nothing: an absence is not a clean bill.
    if coalesce(p_r->'sender'->'dmarc_reports'->>'basis', '') = 'measured'
       and coalesce((p_r->'sender'->'dmarc_reports'->>'messages')::numeric, 0) > 0
       and (p_r->'sender'->'dmarc_reports'->>'failed')::numeric / (p_r->'sender'->'dmarc_reports'->>'messages')::numeric
           > public.fn_it_threshold('sender_dmarc_fail_rate_max') then
      v_items := v_items || jsonb_build_object('item', 'dmarc_fail_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
        'title', round(100 * (p_r->'sender'->'dmarc_reports'->>'failed')::numeric / (p_r->'sender'->'dmarc_reports'->>'messages')::numeric, 2)
                 || '% of the mail receivers saw from our domain failed DMARC',
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'dmarc_reports');
    end if;
    v_out := v_out || jsonb_build_object('sender', public.fn_it_duty_settle('sender', v_items));
    perform public.fn_it_duty_ran('sender', v_out->'sender');
  end if;

  -- ── 11a. SPEND ──
  -- Reads: yesterday's cost per provider the tick could read (Twilio usage, Stripe fees), stored in
  -- it_spend_daily; each source is compared with its own trailing 14 days. The Supabase and Vercel
  -- bills are not readable with the tokens this estate holds, and the reading says so.
  if 'spend' = any (v_due) and jsonb_typeof(p_r->'spend') = 'array' then
    for e in select s from jsonb_array_elements(p_r->'spend') s loop
      if e->>'basis' = 'measured' then
        insert into public.it_spend_daily (day, source, amount_minor, currency)
        values ((e->>'day')::date, e->>'source', (e->>'amount_minor')::bigint, e->>'currency')
        on conflict (day, source) do update set amount_minor = excluded.amount_minor, recorded_at = now();
      end if;
    end loop;
    v_items := '[]'::jsonb;
    v_mult := public.fn_it_threshold('spend_anomaly_multiple'); v_floor := public.fn_it_threshold('spend_floor_aed');
    for x in select s.source, s.day, s.amount_minor, s.currency,
                    (select percentile_cont(0.9) within group (order by b.amount_minor) from public.it_spend_daily b
                      where b.source = s.source and b.day between s.day - 14 and s.day - 1) p90,
                    (select count(*) from public.it_spend_daily b where b.source = s.source and b.day between s.day - 14 and s.day - 1) n
               from public.it_spend_daily s
              where s.day = (select max(day) from public.it_spend_daily t where t.source = s.source) loop
      -- Fewer than seven days of history is not a baseline; the source is reported, not judged.
      continue when x.n < 7;
      if x.amount_minor / 100.0 >= v_floor and x.amount_minor > v_mult * x.p90 then
        v_items := v_items || jsonb_build_object('item', x.source, 'owner_seat', 'accountant', 'subject', x.source,
          'title', x.source || ' cost ' || round(x.amount_minor / 100.0, 2) || ' ' || x.currency || ' on ' || x.day
                   || ', over ' || v_mult || 'x its 14-day p90 of ' || round(x.p90 / 100.0, 2),
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('day', x.day, 'amount_minor', x.amount_minor, 'p90_minor', x.p90, 'history_days', x.n));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('spend', public.fn_it_duty_settle('spend', v_items),
                                         'spend_readings', p_r->'spend');
    perform public.fn_it_duty_ran('spend', v_out->'spend');
  end if;

  -- ── 11b. OTP PUMPING — the IT engineer's own playbook ──
  -- Reads: codes issued in the last hour (phone_verifications from login_otp, customer_phone_otps from
  -- mobile_otp) per 5-digit prefix. A burst to a country we do not serve is blocked for
  -- otp_block_hours at once and reported; a burst inside a served country is handed to the CEO,
  -- because blocking it could lock real customers out. The block is re-verified next hour.
  if 'otp' = any (v_due) then
    v_items := '[]'::jsonb;
    v_max := coalesce(public.fn_it_threshold('otp_burst_per_prefix_hour'), 5)::int;
    -- n_dead: codes that were never used and have already expired. Pumping sends codes nobody enters;
    -- a registration day sends codes people enter within minutes (registration-day surge review,
    -- 21 Sep 2026). A code still inside its 10 minutes is neither, so it is not counted as dead.
    for x in select left(regexp_replace(phone, '\D', '', 'g'), 5) prefix, count(*) n,
                    count(*) filter (where not used and expires_at < now()) n_dead
               from (select phone, created_at, used_at is not null used, expires_at from public.phone_verifications
                     union all select phone, created_at, coalesce(consumed, false), expires_at from public.customer_phone_otps) z
              where created_at > now() - interval '1 hour' and phone is not null
              group by 1 having count(*) > v_max loop
      -- A prefix the CEO or founder allowed is never auto-blocked again; its burst is handed on instead.
      if not exists (select 1 from public.otp_served_country s where x.prefix like s.prefix || '%')
         and not exists (select 1 from public.otp_prefix_allowed a where x.prefix like a.prefix || '%') then
        insert into public.otp_blocked_prefix (prefix, reason, blocked_by, expires_at)
        values (x.prefix, x.n || ' codes in an hour to a country we do not serve', 'it_engineer',
                now() + make_interval(hours => coalesce(public.fn_it_threshold('otp_block_hours'), 24)::int))
        on conflict (prefix) do update set expires_at = excluded.expires_at, reason = excluded.reason;
        -- agent_facing with nobody stuck: recorded, and handed on only if it is still happening in six hours.
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n || ' sign-in codes in an hour to +' || x.prefix || '…, a country we do not serve — prefix blocked by the IT engineer',
          'blast', 'agent_facing', 'affected', 0,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n, 'remedy', 'otp_blocked_prefix'));
      -- INSIDE A SERVED COUNTRY, VOLUME IS NOT THE SIGNAL. The UAE has a handful of mobile prefixes
      -- (+97150, +97152, +97154, +97155, +97156, +97158), so six suppliers verifying on +97150 in one
      -- hour crossed the 5-code line and raised a 'security' finding to the CEO for the system working —
      -- on a campaign day, one per prefix every tick. Raised now only when more than v_max of the codes
      -- died unused AND they are at least half of what was sent: the shape of pumping, not of sign-ups.
      elsif x.n_dead > v_max and x.n_dead * 2 >= x.n then
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n_dead || ' of ' || x.n || ' sign-in codes in an hour to +' || x.prefix || '… were never used, inside a country we serve',
          'blast', 'security', 'affected', 1,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n, 'codes_never_used', x.n_dead,
                                         'why_not_blocked', 'a served country: blocking could lock real customers out'));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('otp', public.fn_it_duty_settle('otp', v_items));
    perform public.fn_it_duty_ran('otp', v_out->'otp');
  end if;

  -- ── 13. ACCESS REVIEW ──
  -- Reads: who each provider lists (GitHub collaborators and deploy keys, Vercel team members, the
  -- Dropbox account; Supabase members arrive through fn_it_platform_ingest). A principal not accepted
  -- in it_access_known, or accepted longer ago than access_reconfirm_days, is raised to the CEO.
  -- Stripe publishes no team-member API; the reading says so.
  if 'access' = any (v_due) and jsonb_typeof(p_r->'access') = 'object' then
    v_items := public.fn_it_access_items(p_r->'access');
    v_out := v_out || jsonb_build_object('access', public.fn_it_duty_settle('access', v_items));
    perform public.fn_it_duty_ran('access', v_out->'access');
  end if;

  -- ── 14. DATABASE HEALTH ──
  if 'db_health' = any (v_due) then
    v_items := '[]'::jsonb;
    -- THE SLOW STATEMENTS OF THE LAST INTERVAL, NOT OF THE DATABASE'S WHOLE LIFE.
    -- pg_stat_statements counters are cumulative since stats_reset and never decay, so
    -- s.mean_exec_time is a lifetime average: a statement that was slow in August and has not run
    -- since keeps the same mean for ever and is re-raised on every run. The interval is measured
    -- against public.it_query_stat_snapshot, written at the end of this block.
    --   INNER join, not left. A statement with no snapshot row has no interval -- it is not a
    --   statement that ran for a long time, it is a statement nobody has measured yet. Reading a
    --   missing baseline as zero would make its whole lifetime the first interval, which is exactly
    --   the lifetime rule this block replaces, and it would come back every time
    --   pg_stat_statements is reset or an entry is evicted and re-created. The upsert below gives it
    --   a baseline in this same run, so it is judged on the next one, one interval later.
    --   The two <= clauses keep counters that went BACKWARDS from producing a negative interval:
    --   a re-created entry can pass calls and still be behind on total_exec_time, or the reverse.
    --   Neither can be true of the same statement continuing, so both must hold or there is no
    --   comparable baseline and the row waits a run.
    -- The view is keyed on (userid, dbid, toplevel, queryid), so it is summed per queryid first --
    -- one statement's cost is what it cost, whoever ran it -- and min(query) picks one of the
    -- identical texts those rows share. That text can be NULL (pg_stat_statements can lose the text
    -- file, and a role that may not read it gets null), and a null title makes fn_it_duty_settle
    -- raise, which would abort every duty after this one: hence the coalesce.
    for x in with s as (
               select ss.queryid, sum(ss.calls) calls, sum(ss.total_exec_time) total_exec_time,
                      coalesce(min(left(regexp_replace(ss.query, '\s+', ' ', 'g'), 200)),
                               '(query text unavailable)') q,
                      -- An operator's session, not the product (21 Sep 2026): the management API
                      -- stamps every statement it runs with its own route in a trailing comment.
                      bool_and(coalesce(ss.query, '') like '%/v1/projects/:ref/database/query%') operator_session,
                      -- A schema change, not the product (24 Sep 2026): the stamp above is a
                      -- TRAILING comment, so in an applied multi-statement file only the last
                      -- statement carries it. A statement whose first word after its leading
                      -- comments is a DDL verb is an apply or a CI dry run, never product traffic.
                      bool_and(regexp_replace(coalesce(ss.query, ''), '^(\s*--[^\n]*)*\s*', '')
                               ~* '^(create|alter|drop|grant|revoke|comment)\s') schema_change
                 from extensions.pg_stat_statements ss
                where ss.queryid is not null
                group by ss.queryid)
             select s.queryid, s.q,
                    (s.calls - p.calls) d_calls,
                    round(((s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0))::numeric, 1) d_mean_ms,
                    round((s.total_exec_time - p.total_exec_time)::numeric / 1000, 1) d_total_s,
                    p.taken_at since
               from s
               join public.it_query_stat_snapshot p
                 on p.queryid = s.queryid and p.calls <= s.calls and p.total_exec_time <= s.total_exec_time
              where not s.operator_session and not s.schema_change
                and (s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0)
                    > public.fn_it_threshold('slow_query_mean_ms')
                -- Either the interval carried the call volume the threshold asks for, OR the
                -- statement burned that much time whatever its volume. Without the second arm a
                -- nightly export taking 60 s once could never be raised at all: the old rule could
                -- reach 50 calls across four months, one interval cannot. min_calls * mean_ms is
                -- not a new knob -- it is the time the first arm already has to accumulate before
                -- it fires (50 x 500 ms = 25 s), stated for the case where one call does it alone.
                and (s.calls - p.calls >= public.fn_it_threshold('slow_query_min_calls')
                     or s.total_exec_time - p.total_exec_time
                        > public.fn_it_threshold('slow_query_min_calls') * public.fn_it_threshold('slow_query_mean_ms'))
              order by 5 desc limit 10 loop
      v_items := v_items || jsonb_build_object('item', 'slow:' || x.queryid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'A statement averaged ' || x.d_mean_ms || ' ms over ' || x.d_calls || ' calls since the last check ('
                 || x.d_total_s || ' s in total): ' || left(x.q, 90),
        'blast', 'internal', 'affected', 1,
        'evidence', jsonb_build_object('queryid', x.queryid, 'query', x.q, 'calls', x.d_calls, 'mean_ms', x.d_mean_ms,
                                       'interval_total_s', x.d_total_s, 'interval_started_at', x.since,
                                       'interval_minutes', round((extract(epoch from (now() - x.since)) / 60)::numeric, 1),
                                       'basis', 'measured over the interval between this run and the previous db_health run, from public.it_query_stat_snapshot'));
    end loop;
    -- The reading this run measured against the next one. Every statement is recorded, not only the
    -- slow ones, or a statement that is fast today and slow tomorrow would have no baseline.
    -- The where clause keeps the snapshot MONOTONIC: two db_health runs overlapping would otherwise
    -- let the one that READ first COMMIT last and write its older reading over the newer, and the
    -- next interval would then re-count work already measured.
    insert into public.it_query_stat_snapshot (queryid, calls, total_exec_time, taken_at)
    select ss.queryid, sum(ss.calls), sum(ss.total_exec_time), now()
      from extensions.pg_stat_statements ss
     where ss.queryid is not null
     group by ss.queryid
      on conflict (queryid) do update
         set calls = excluded.calls, total_exec_time = excluded.total_exec_time, taken_at = excluded.taken_at
       where excluded.calls >= public.it_query_stat_snapshot.calls;
    -- A queryid pg_stat_statements has evicted will never return; keeping its row would make the
    -- table grow for ever and would give a re-created entry a stale baseline.
    delete from public.it_query_stat_snapshot p
     where not exists (select 1 from extensions.pg_stat_statements ss where ss.queryid = p.queryid);
    insert into public.it_table_size_daily (day, relid, bytes)
    -- The alias is pc, not c: c is this function's rotation-loop record, and plpgsql would read c.oid
    -- as that (unassigned) record instead of the table.
    select current_date, pc.oid::regclass::text, pg_total_relation_size(pc.oid)
      from pg_class pc join pg_namespace n on n.oid = pc.relnamespace
     where n.nspname = 'public' and pc.relkind = 'r'
    on conflict (day, relid) do update set bytes = excluded.bytes;
    for x in select t.relid, t.bytes, o.bytes old_bytes from public.it_table_size_daily t
               join public.it_table_size_daily o on o.relid = t.relid and o.day = current_date - 7
              where t.day = current_date
                and t.bytes > public.fn_it_threshold('table_growth_7d_multiple') * o.bytes
                and t.bytes - o.bytes > public.fn_it_threshold('table_growth_min_bytes')
                -- A registered backfill is growth the company chose, not a fault: it is skipped until its
                -- end date. Past that date the same growth is raised again, so a backfill cannot hide a leak.
                and not exists (select 1 from public.it_expected_table_growth g
                                 where g.relid = t.relid and current_date <= g.until) loop
      v_items := v_items || jsonb_build_object('item', 'growth:' || x.relid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', x.relid || ' grew from ' || pg_size_pretty(x.old_bytes) || ' to ' || pg_size_pretty(x.bytes) || ' in a week',
        'blast', 'internal', 'affected', 1, 'evidence', jsonb_build_object('bytes', x.bytes, 'bytes_7d_ago', x.old_bytes));
    end loop;
    select count(*) into v_used from pg_stat_activity;
    v_lim := current_setting('max_connections')::numeric;
    if v_used > public.fn_it_threshold('connections_ratio_max') * v_lim then
      v_items := v_items || jsonb_build_object('item', 'connections', 'owner_seat', 'ceo', 'subject', 'database',
        'title', v_used || ' of ' || v_lim || ' database connections are in use',
        'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('in_use', v_used, 'max', v_lim));
    end if;
    v_lim := public.fn_it_threshold('db_disk_limit_bytes');
    if v_lim is not null and pg_database_size(current_database()) > public.fn_it_threshold('disk_ratio_max') * v_lim then
      v_items := v_items || jsonb_build_object('item', 'disk', 'owner_seat', 'accountant', 'subject', 'database',
        'title', 'The database uses ' || pg_size_pretty(pg_database_size(current_database())) || ' of ' || pg_size_pretty(v_lim::bigint),
        'blast', 'customer_facing', 'affected', 0,
        'evidence', jsonb_build_object('bytes', pg_database_size(current_database()), 'limit_bytes', v_lim,
                                       'route', 'the accountant approves a larger disk or plan'));
    end if;
    -- Published every run, so the exclusion is a number on the record and never a silent gap.
    select count(*) into v_n from (
      select ss.queryid from extensions.pg_stat_statements ss where ss.queryid is not null
       group by ss.queryid having bool_and(coalesce(ss.query, '') like '%/v1/projects/:ref/database/query%')) z;
    v_out := v_out || jsonb_build_object('db_health_operator_statements_excluded', v_n);
    v_out := v_out || jsonb_build_object('db_health', public.fn_it_duty_settle('db_health', v_items),
                                         'disk_limit_basis', case when v_lim is null then 'not_measured_yet' else 'measured' end);
    perform public.fn_it_duty_ran('db_health', v_out->'db_health');
  end if;

  -- ── 15. ROTATION ──
  if 'rotation' = any (v_due) then
    for c in select ic.id from public.internal_credential ic
              where ic.active and ic.retired_at is null and not ic.is_legacy
                and exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'))
                and not exists (select 1 from public.it_credential_rotation r where r.context = ic.context and r.status in ('overlap', 'held'))
                and (coalesce(ic.rotated_at, ic.created_at) < now() - make_interval(days => public.fn_it_threshold('credential_rotate_days')::int)
                     or ic.expires_at < now() + interval '30 days')
              order by coalesce(ic.rotated_at, ic.created_at)
              limit public.fn_it_threshold('credential_rotations_per_run')::int
              -- Two ticks at the same instant must not rotate one credential twice: the first holds the
              -- row until its rotation row ('overlap') exists, and the second skips what is held.
              for update of ic skip locked loop
      perform public.fn_it_credential_rotate(c.id);
      v_rot := v_rot + 1;
    end loop;
    v_out := v_out || jsonb_build_object('rotation', jsonb_build_object('rotated', v_rot, 'reverify', public.fn_it_credential_reverify()));
    perform public.fn_it_duty_ran('rotation', v_out->'rotation');
  end if;

  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_duty_ran(p_duty text, p_result jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'duty:' || p_duty, 'result', p_result), null)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_duty_settle(p_duty text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text; v_config boolean;
        n_held int := 0;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_it_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_it_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    v_key := 'duty:' || p_duty || ':' || (x->>'item');
    v_keys := v_keys || v_key;

    -- A CARRIED ITEM WAS NOT OBSERVED THIS TICK (22 Sep 2026): its step failed earlier and has not run
    -- since. An open finding is held exactly as it stands; a closed one falls through and reopens.
    if coalesce((x->>'carried')::boolean, false) and exists (select 1 from public.it_engineer_finding f
                                                             where f.issue_key = v_key and f.closed_at is null) then
      n_held := n_held + 1;
      continue;
    end if;

    -- A CONFIGURATION GAP IS NOT NEWS ON THE SECOND TICK. Nothing about the running system changed
    -- between one reading and the next; what is missing is a number or a date nobody has entered yet.
    -- The key stays in v_keys so the sweep below does NOT close it - the gap is still open, and closes
    -- the moment the cap or the date is recorded and the producer stops emitting the item. Recognised
    -- from the item key both producers already use, or from an explicit 'config' flag for future ones.
    v_config := coalesce((x->>'config')::boolean, false)
                or (x->>'item') ~ '(^|:)cap_unknown:' or (x->>'item') ~ ':date_unknown$';
    -- A CLOSED configuration finding is NOT held: it falls through to the upsert and reopens, because a
    -- gap that was filled and has come back is news. Only an already-open one is held.
    if v_config and exists (select 1 from public.it_engineer_finding f
                             where f.issue_key = v_key and f.closed_at is null) then
      -- The reading itself moves even though the gap does not: supabase storage was 34 GB when the
      -- finding was raised and will be more when somebody reads it. So the title and the evidence are
      -- refreshed to today's measurement while seen_count, last_seen_at and started_at stand still -
      -- the row says what is true now without claiming anything happened this tick.
      update public.it_engineer_finding f
         set title = left(x->>'title', 300),
             evidence = coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
               'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
               'demo', coalesce((x->>'demo')::boolean, false), 'reading_refreshed_at', now())
       where f.issue_key = v_key and f.closed_at is null;
      n_held := n_held + 1;
      continue;
    end if;

    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'IT engineer duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
        'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'it_engineer.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the ' || p_duty || ' duty no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0),
                            'closed', n_closed, 'configuration_already_recorded', n_held);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_alert_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_gap_min numeric; v_last_beat timestamptz; r record;
  v_monitor int := 0; v_errors jsonb := '[]'::jsonb; v_ingest jsonb := '{}'::jsonb; v_loop jsonb := '{}'::jsonb;
begin
  ---------------------------------------------------------------------------------------------
  -- 0. PULL FROM THE DETECTORS FIRST. The detection engine writes to it_watch_finding; this ledger
  --    holds only what the founder has been told. Without this call the tick reports
  --    monitor_findings: 0 — true of the table it reads, and false about the estate.
  --    Wrapped: a failed intake must not take the alerting down, but it must be VISIBLE, because a
  --    tick that quietly saw nothing looks exactly like a tick with nothing to see.
  ---------------------------------------------------------------------------------------------
  begin
    v_ingest := public.fn_it_engineer_ingest_watch_findings();
  exception when others then
    v_ingest := jsonb_build_object('ok', false, 'error', sqlerrm);
    v_errors := v_errors || to_jsonb('ingest failed: ' || sqlerrm);
    begin
      insert into public.founder_alerts (level, event, detail, channel)
      values ('high','it_engineer:ingest_failed',
              'fn_it_engineer_ingest_watch_findings raised (' || sqlerrm || '), so this tick decided '
              || 'what to send you from a ledger that may be missing newly detected faults.','os');
    exception when others then null; end;
  end;

  ---------------------------------------------------------------------------------------------
  -- A0. THE DETECTOR PERSISTED A TICK RECENTLY, OR THAT IS ITSELF THE FINDING. Measured 14 Sep 2026:
  --    fn_it_detect ran past PostgREST's 8 s statement timeout from 14:35 to 15:55 UTC. resilience_ping
  --    swallowed the error and kept reporting ok, and no detector finding could say so, because the
  --    detector was the thing failing. This reads only public.it_watch_tick, which fn_it_detect writes
  --    on every persisted tick, and it runs here because resilience_ping calls this tick separately,
  --    after the detect call, whether or not that call succeeded.
  ---------------------------------------------------------------------------------------------
  begin
    select extract(epoch from (now() - max(ran_at))) / 60.0 into v_gap_min from public.it_watch_tick;
    if v_gap_min is null or v_gap_min > 40 then
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'detect_tick', 'gap_minutes', round(coalesce(v_gap_min, -1))),
              'fn_it_detect has persisted no tick for ' || coalesce(round(v_gap_min)::text, 'ever') || ' minutes');
      perform public.fn_it_engineer_finding_upsert(
        'monitor:detect_tick_blind',
        'The IT engineer''s detector has persisted no tick for ' || coalesce(round(v_gap_min)::text, 'any') || ' minutes',
        'public.fn_it_detect, called from supabase/functions/resilience_ping (itDetectTick)',
        'monitor', 1,
        jsonb_build_object('gap_minutes', round(coalesce(v_gap_min, -1)), 'expected_every', '15 minutes', 'owner_seat', 'ceo',
                           'look_at', 'the itdetect field of resilience_ping''s response: a timeout or an error from fn_it_detect'),
        '{}'::text[], array['why fn_it_detect fails or runs past the 8 s statement timeout'], 'fn_it_engineer_alert_tick');
    else
      perform public.fn_it_engineer_finding_close('monitor:detect_tick_blind', 'fn_it_detect persisted a tick ' || round(v_gap_min) || ' minutes ago');
    end if;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','detect_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- A. THE MONITOR WATCHES ITSELF FIRST. A blind detection engine is an alert, not a quiet night.
  --    The gap is read BEFORE this tick's own beat is stamped, or it would always read zero.
  --    (What this cannot catch is the tick never running again at all. That is not left uncovered:
  --    it is the platform_down / uptime_alert path -- resilience_ping via Vercel cron every 15 min
  --    and the once-a-day GitHub Action outside both Supabase and Vercel -- which already emails
  --    him under kinds that are already allowed. This does not duplicate that.)
  ---------------------------------------------------------------------------------------------
  begin
    select last_beat_at into v_last_beat from public.it_engineer_scanner where scanner = 'it_engineer_alert_tick';
    if v_last_beat is not null then
      v_gap_min := extract(epoch from (now() - v_last_beat)) / 60.0;
      if v_gap_min > 60 then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:alert_tick_blind',
          'The IT engineer''s alert tick did not run for ' || round(v_gap_min) || ' minutes',
          'public.fn_it_engineer_alert_tick, called from supabase/functions/resilience_ping',
          'monitor', 1,
          jsonb_build_object('gap_minutes', round(v_gap_min), 'last_beat_at', v_last_beat,
                             'expected_every', '15 minutes (Vercel cron -> /api/resilience-ping)'),
          array['the tick is running now, so the routine itself still executes'],
          array['whether any finding was raised and missed during the gap',
                'whether the 15-minute Vercel cron or the whole edge function was the part that stopped'],
          'fn_it_engineer_alert_tick');
      else
        perform public.fn_it_engineer_finding_close('monitor:alert_tick_blind', 'the tick is running on cadence again');
      end if;
    end if;
    perform public.fn_it_engineer_scanner_beat('it_engineer_alert_tick', null, 60);
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','self_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- B. EVERY REGISTERED SCANNER. Stale beat OR a recorded error becomes a finding of its own.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_scanner where scanner <> 'it_engineer_alert_tick' loop
      if r.last_error is not null then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:' || r.scanner,
          'Detector ' || r.scanner || ' is failing, so its silence proves nothing',
          'IT engineer scanner ' || r.scanner, 'monitor', 1,
          jsonb_build_object('last_error', r.last_error, 'last_beat_at', r.last_beat_at, 'last_ok_at', r.last_ok_at),
          array['the scanner is still being invoked -- it beat at ' || to_char(r.last_beat_at at time zone 'UTC','YYYY-MM-DD HH24:MI') || ' UTC'],
          array['what this detector would have found while it was erroring'],
          'fn_it_engineer_alert_tick');
        v_monitor := v_monitor + 1;
      elsif now() - r.last_beat_at > make_interval(mins => r.max_gap_minutes) then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:' || r.scanner,
          'Detector ' || r.scanner || ' has not reported for ' || round(extract(epoch from (now() - r.last_beat_at))/60.0) || ' minutes',
          'IT engineer scanner ' || r.scanner, 'monitor', 1,
          jsonb_build_object('gap_minutes', round(extract(epoch from (now() - r.last_beat_at))/60.0),
                             'max_gap_minutes', r.max_gap_minutes, 'last_beat_at', r.last_beat_at),
          array['nothing -- this detector has reported nothing to rule anything out with'],
          array['everything this detector covers is currently unwatched'],
          'fn_it_engineer_alert_tick');
        v_monitor := v_monitor + 1;
      else
        perform public.fn_it_engineer_finding_close('monitor:' || r.scanner, 'the detector is reporting on cadence and without error');
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','scanner_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- C. EVERY ACTIONABLE FINDING GOES ROUND THE LOOP. Until 14 Sep 2026 this section emailed each
  --    high/critical finding straight to the founder and emailed him again when it cleared, with no
  --    seat asked to act and no reply awaited. The owning seat now answers, the IT engineer
  --    re-verifies and closes, and the founder hears only of a new bug nobody could fix
  --    (the_it_engineer_closes_every_loop_it_opens.sql). fn_it_loop_tick reports its own failures.
  ---------------------------------------------------------------------------------------------
  begin
    v_loop := public.fn_it_loop_tick();
    if not coalesce((v_loop->>'ok')::boolean, false) then
      v_errors := v_errors || jsonb_build_object('section','loop','errors', v_loop->'errors');
    end if;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','loop','error', sqlerrm);
  end;

  -- A tick that half-failed must SAY so rather than returning a clean-looking zero.
  if jsonb_array_length(v_errors) > 0 then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values ('high', 'it_engineer:alert_tick_partial', v_errors::text, 'os', 'it_tick_partial');
  end if;

  return jsonb_build_object('ok', jsonb_array_length(v_errors) = 0,
                            'loop', v_loop,
                            'monitor_findings', v_monitor, 'ingested_from_detectors', v_ingest,
                            'errors', v_errors);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_assist(p_text text, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.83, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_min_overlap numeric DEFAULT 0.60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  v_wide      int := greatest(v_k * 4, 20);
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq        tsquery;
  v_lex       text[];
  v_nlex      int;
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_lex  int;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  -- The greater of 60% and two lexemes, so a short question cannot be admitted on one common word.
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  create temporary table if not exists _ite_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate refuses an unqualified DELETE, and a WHERE-less delete on a
  -- scratch table is exactly the shape that guard exists to catch elsewhere.
  truncate table _ite_cand;

  -- it_engineer_knowledge -- the seat's own body.
  if p_embedding is not null then
    insert into _ite_cand
    select 'it_engineer_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || ' · ' || k.epistemic_status,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from it_engineer_knowledge k
     where k.embedding_gte is not null and k.runtime_index_eligible
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _ite_cand
  select 'it_engineer_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, '') || ' · ' || k.epistemic_status,
         null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from it_engineer_knowledge k
   where k.embedding_gte is null and k.runtime_index_eligible and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge -- the 165 it_security_deep rows plus how this company actually operates.
  if p_embedding is not null then
    insert into _ite_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.layer, '') || case when o.module is null then '' else ' · ' || o.module end
             || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- ADMISSION. The cosine floor is a hard AND for every vector-bearing row; corroboration may come
  -- from either the all-terms rank or literal lexeme overlap, and one of the two is required.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity
             and (c.lexical_rank >= p_min_rank or c.lex_hits >= v_need))     as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)             as ok_lexical
      from _ite_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      'lex_hits', r.lex_hits, 'lex_needed', v_need,
      'corroborated', case when r.has_vector then (r.lexical_rank >= p_min_rank or r.lex_hits >= v_need)
                           else r.lexical_rank >= c_lex_only end,
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank), max(lex_hits)
    into v_best_sim, v_best_rank, v_best_lex from _ite_cand;
  select corpus into v_best_corp from _ite_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _ite_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;
    v_handoff :=
      'I do not have a sourced answer to that, and I will not guess during an incident. '
      || 'If the question is whether a specific published vulnerability reaches this estate, that '
      || 'is deliberately not held in my knowledge: I hold no CVE identifier, no version-specific '
      || 'vulnerability claim and no patch level, because I cannot read a vulnerability feed and an '
      || 'invented one is worse than none. Determine it against the component''s own advisory and '
      || 'the version the platform actually reports. If the question is about live state, read the '
      || 'live state: the answer is in the database, the edge logs or the deploy history, not here.';
  end if;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('it_engineer_knowledge', 'ops_knowledge'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'min_overlap', p_min_overlap, 'lexemes_in_question', v_nlex, 'lexeme_overlap_needed', v_need,
      'best_similarity', round(v_best_sim, 4), 'best_lexical_rank', round(v_best_rank, 4),
      'best_lex_hits', v_best_lex, 'nearest_corpus', v_best_corp, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor -- always -- AND corroborate literally by one of two routes: the all-terms lexical query at ts_rank >= min_rank, or at least lexeme_overlap_needed of the question''s own lexemes present verbatim in the row. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. A nearest neighbour is always found; a literal match is not.'),
    'refusal', v_refusal,
    'handoff', v_handoff);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_backup_objectives()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rpo numeric := coalesce(public.fn_it_threshold('backup_rpo_hours'), 26);
  v_rto numeric := coalesce(public.fn_it_threshold('backup_rto_hours'), 4);
  v_every int := coalesce(public.fn_it_threshold('restore_drill_every_days'), 7)::int;
  v_newest timestamptz; v_age_h numeric; v_gap_h numeric;
  v_pass public.it_restore_drill_result; v_last public.it_restore_drill_result; v_pick timestamptz; v_rto_s numeric;
  v_items jsonb := '[]'::jsonb;
begin
  -- RPO: hours since the newest finished export, and the widest gap between finished exports in 7 days
  select max(finished_at) into v_newest from public.table_export_run where status = 'done';
  v_age_h := round((extract(epoch from now() - v_newest) / 3600)::numeric, 1);
  select round(max(extract(epoch from g) / 3600)::numeric, 1) into v_gap_h from (
    select finished_at - lag(finished_at) over (order by finished_at) g
      from public.table_export_run where status = 'done' and finished_at > now() - interval '7 days') x;
  if v_newest is null or v_age_h > v_rpo or coalesce(v_gap_h, 0) > v_rpo then
    v_items := v_items || jsonb_build_object('item', 'rpo', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', case when v_newest is null then 'No finished table export exists, so the ' || v_rpo || ' h RPO cannot be met'
               else 'Achieved RPO ' || greatest(v_age_h, coalesce(v_gap_h, 0)) || ' h is over the ' || v_rpo || ' h target' end,
      'evidence', jsonb_build_object('newest_export_finished_at', v_newest, 'hours_since', v_age_h,
                                     'widest_gap_7d_hours', v_gap_h, 'target_hours', v_rpo));
  end if;

  -- RTO: the last drill that restored rows and passed, timed from its pick to its record
  select * into v_last from public.it_restore_drill_result order by id desc limit 1;
  select * into v_pass from public.it_restore_drill_result
   where ok and coalesce((detail->>'restored')::int, 0) > 0 order by id desc limit 1;
  if v_pass.id is not null then
    select max(started_at) into v_pick from public.agent_runs
     where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick' and started_at <= v_pass.ran_at;
    v_rto_s := round(extract(epoch from v_pass.ran_at - v_pick)::numeric, 1);
  end if;
  if v_pass.id is null or v_pass.ran_at < now() - make_interval(days => v_every + 2) then
    v_items := v_items || jsonb_build_object('item', 'rto_unproven', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'No restore drill has restored rows and passed in the last ' || (v_every + 2) || ' days'
               || coalesce(' (last pass ' || to_char(v_pass.ran_at at time zone 'Asia/Dubai', 'DD Mon') || ')', ' (none ever)')
               || ', so the ' || v_rto || ' h RTO is unproven',
      'evidence', jsonb_build_object('last_pass_id', v_pass.id, 'last_pass_at', v_pass.ran_at,
                                     'last_drill_id', v_last.id, 'last_drill_at', v_last.ran_at, 'last_drill_ok', v_last.ok));
  elsif v_rto_s is not null and v_rto_s > v_rto * 3600 then
    v_items := v_items || jsonb_build_object('item', 'rto', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'The restore drill took ' || v_rto_s || ' s, over the ' || v_rto || ' h RTO',
      'evidence', jsonb_build_object('drill_id', v_pass.id, 'seconds', v_rto_s, 'target_hours', v_rto));
  end if;
  if v_last.id is null or v_last.ran_at < now() - make_interval(days => v_every + 2) then
    v_items := v_items || jsonb_build_object('item', 'drill_stale', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'The weekly restore drill has not run for ' || coalesce(extract(day from now() - v_last.ran_at)::int || ' days', 'ever'),
      'evidence', jsonb_build_object('last_drill_at', v_last.ran_at, 'every_days', v_every,
                                     'look_at', 'resilience_ping restore_table step; fn_it_restore_table_due'));
  end if;

  return jsonb_build_object('rpo', jsonb_build_object('target_hours', v_rpo, 'hours_since_export', v_age_h, 'widest_gap_7d_hours', v_gap_h),
                            'rto', jsonb_build_object('target_hours', v_rto, 'last_pass_id', v_pass.id, 'sample_restore_seconds', v_rto_s),
                            'drill', jsonb_build_object('last_id', v_last.id, 'last_at', v_last.ran_at, 'every_days', v_every),
                            'settled', public.fn_it_duty_settle('backup_objectives', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_capacity_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_warn numeric := coalesce(public.fn_it_threshold('cap_warn_ratio'), 0.8);
  v_db bigint := pg_database_size(current_database());
  v_db_cap numeric := public.fn_it_threshold('db_disk_limit_bytes');
  v_st bigint; v_st_cap numeric := public.fn_it_threshold('cap_supabase_storage_bytes');
  v_items jsonb := '[]'::jsonb;
begin
  select coalesce(sum((metadata->>'size')::bigint), 0) into v_st from storage.objects;
  if v_db_cap is null or v_db > v_db_cap * v_warn then
    v_items := v_items || jsonb_build_object('item', 'database', 'owner_seat', 'it_engineer', 'subject', 'capacity',
      'config', v_db_cap is null,
      'title', case when v_db_cap is null then 'No database size cap is recorded (it_threshold db_disk_limit_bytes)'
               else 'The database is ' || round(v_db / 1e9, 2) || ' GB, ' || round(100.0 * v_db / v_db_cap) || '% of its cap' end,
      'evidence', jsonb_build_object('bytes', v_db, 'cap_bytes', v_db_cap, 'warn_ratio', v_warn));
  end if;
  if v_st_cap is null or v_st > v_st_cap * v_warn then
    v_items := v_items || jsonb_build_object('item', 'storage', 'owner_seat', 'it_engineer', 'subject', 'capacity',
      'config', v_st_cap is null,
      'title', case when v_st_cap is null then 'No storage cap is recorded (it_threshold cap_supabase_storage_bytes)'
               else 'Storage holds ' || round(v_st / 1e9, 2) || ' GB, ' || round(100.0 * v_st / v_st_cap) || '% of its cap' end,
      'evidence', jsonb_build_object('bytes', v_st, 'cap_bytes', v_st_cap, 'warn_ratio', v_warn));
  end if;
  return jsonb_build_object('db_bytes', v_db, 'db_cap', v_db_cap, 'storage_bytes', v_st, 'storage_cap', v_st_cap,
                            'settled', public.fn_it_duty_settle('capacity_review', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_code_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_unpinned text[]; v_nopolicy text[]; v_failing text[]; v_items jsonb := '[]'::jsonb;
begin
  select coalesce(array_agg(p.oid::regprocedure::text order by 1), '{}') into v_unpinned
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search\_path=%');
  select coalesce(array_agg(c.relname::text order by 1), '{}') into v_nopolicy
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
     and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid);
  select coalesce(array_agg(duty order by duty), '{}') into v_failing
    from public.seat_duty where enabled and failures >= 3;
  if cardinality(v_unpinned) > 0 then
    v_items := v_items || jsonb_build_object('item', 'search_path', 'owner_seat', 'it_engineer', 'subject', 'code_health',
      'title', cardinality(v_unpinned) || ' SECURITY DEFINER routine(s) in public have no pinned search_path',
      'evidence', jsonb_build_object('routines', to_jsonb(v_unpinned)));
  end if;
  if cardinality(v_nopolicy) > 0 then
    v_items := v_items || jsonb_build_object('item', 'rls_no_policy', 'owner_seat', 'it_engineer', 'subject', 'code_health',
      'title', cardinality(v_nopolicy) || ' public table(s) have RLS on and no policy',
      'evidence', jsonb_build_object('tables', to_jsonb(v_nopolicy)));
  end if;
  if cardinality(v_failing) > 0 then
    v_items := v_items || jsonb_build_object('item', 'failing_duties', 'owner_seat', 'it_engineer', 'subject', 'code_health',
      'title', cardinality(v_failing) || ' seat duty(ies) have failed 3 or more times in a row',
      'evidence', jsonb_build_object('duties', to_jsonb(v_failing)));
  end if;
  return jsonb_build_object('unpinned', cardinality(v_unpinned), 'rls_no_policy', cardinality(v_nopolicy),
                            'failing_duties', cardinality(v_failing), 'settled', public.fn_it_duty_settle('code_health', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_credential_rotation_age()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days int := coalesce(public.fn_it_threshold('credential_rotate_days'), 90)::int;
  v_grace int := 7; c record; v_items jsonb := '[]'::jsonb; n_over int := 0; n_unrec int := 0;
begin
  for c in
    select ic.id, ic.context, coalesce(ic.rotated_at, ic.created_at) since
      from public.internal_credential ic
     where ic.active and ic.retired_at is null
       and coalesce(ic.rotated_at, ic.created_at) < now() - make_interval(days => v_days + v_grace)
       and not exists (select 1 from public.it_credential_rotation r where r.context = ic.context and r.status in ('overlap', 'held'))
  loop
    n_over := n_over + 1;
    v_items := v_items || jsonb_build_object('item', 'overdue:' || c.context, 'owner_seat', 'it_engineer', 'subject', 'credentials',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'Credential ' || c.context || ' is ' || extract(day from now() - c.since)::int || ' days since rotation; the limit is '
               || v_days || ' (+' || v_grace || ' grace) and the rotation duty has not rotated it',
      'evidence', jsonb_build_object('credential_id', c.id, 'since', c.since, 'rotate_days', v_days,
                                     'look_at', 'it_duty_schedule rotation; fn_it_credential_rotate; app_secrets cred_ key for this context'));
  end loop;
  for c in
    select ic.id, ic.context, ic.rotated_at from public.internal_credential ic
     where ic.rotated_at is not null and ic.active and ic.retired_at is null
       and not exists (select 1 from public.it_credential_rotation r where r.new_id = ic.id)
  loop
    n_unrec := n_unrec + 1;
    v_items := v_items || jsonb_build_object('item', 'unrecorded:' || c.context, 'owner_seat', 'it_engineer', 'subject', 'credentials',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'Credential ' || c.context || ' shows a rotation on ' || to_char(c.rotated_at, 'YYYY-MM-DD') || ' with no it_credential_rotation record',
      'evidence', jsonb_build_object('credential_id', c.id, 'rotated_at', c.rotated_at));
  end loop;
  return jsonb_build_object('rotate_days', v_days, 'grace_days', v_grace, 'overdue', n_over, 'unrecorded', n_unrec,
                            'settled', public.fn_it_duty_settle('credential_rotation_age', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_data_quality()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_items jsonb := '[]'::jsonb; n int; ids jsonb; v_chk record; v_counts jsonb := '{}'::jsonb;
begin
  for v_chk in
    select * from (values
      ('demo_quote_crosses_real', 'sales_engineer', 'quotes join a ZZ DEMO party to a real one (customer and supplier disagree on demo)',
       $q$select q.id from public.quotes q join public.inquiries i on i.id = q.inquiry_id
            join public.customers cu on cu.id = i.customer_id join public.leads l on l.id = q.supplier_id
          where cu.is_demo is distinct from l.is_demo$q$),
      ('demo_transaction_crosses_real', 'accountant', 'transactions join a ZZ DEMO party to a real one (customer and supplier disagree on demo)',
       $q$select t.id from public.transactions t join public.customers cu on cu.id = t.customer_id join public.leads l on l.id = t.supplier_id
          where cu.is_demo is distinct from l.is_demo$q$),
      ('orphan_quotes', 'sales_engineer', 'quotes point at an inquiry or a supplier that no longer exists',
       $q$select q.id from public.quotes q where not exists (select 1 from public.inquiries i where i.id = q.inquiry_id)
            or (q.supplier_id is not null and not exists (select 1 from public.leads l where l.id = q.supplier_id))$q$),
      ('orphan_inquiries', 'sales_engineer', 'inquiries point at a customer that no longer exists',
       $q$select i.id from public.inquiries i where i.customer_id is not null and not exists (select 1 from public.customers c where c.id = i.customer_id)$q$),
      ('orphan_transactions', 'accountant', 'transactions point at a quote, inquiry, customer or supplier that no longer exists',
       $q$select t.id from public.transactions t
          where (t.quote_id is not null and not exists (select 1 from public.quotes q where q.id = t.quote_id))
             or (t.inquiry_id is not null and not exists (select 1 from public.inquiries i where i.id = t.inquiry_id))
             or (t.customer_id is not null and not exists (select 1 from public.customers c where c.id = t.customer_id))
             or (t.supplier_id is not null and not exists (select 1 from public.leads l where l.id = t.supplier_id))$q$),
      ('transaction_quote_mismatch', 'accountant', 'transactions disagree with the quote they were revealed from (amount, inquiry or supplier)',
       $q$select t.id from public.transactions t join public.quotes q on q.id = t.quote_id
          where t.quote_amount is distinct from q.quote_amount or t.inquiry_id is distinct from q.inquiry_id
             or t.supplier_id is distinct from q.supplier_id$q$)
    ) v(cls, owner, what, q)
  loop
    execute 'select count(*), coalesce(jsonb_agg(id) filter (where rn <= 20), ''[]'') from (select id, row_number() over (order by id) rn from ('
            || v_chk.q || ') s) z' into n, ids;
    v_counts := v_counts || jsonb_build_object(v_chk.cls, n);
    if n > 0 then
      v_items := v_items || jsonb_build_object('item', v_chk.cls, 'owner_seat', v_chk.owner, 'subject', v_chk.cls, 'affected', n,
        'blast', case when v_chk.owner = 'accountant' then 'customer_facing' else 'internal' end,
        'title', n || ' ' || v_chk.what, 'evidence', jsonb_build_object('ids', ids, 'count', n));
    end if;
  end loop;

  return jsonb_build_object('counts', v_counts, 'settled', public.fn_it_duty_settle('data_quality', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_dr_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_last public.it_restore_drill_result; v_items jsonb := '[]'::jsonb;
begin
  select * into v_last from public.it_restore_drill_result
   where subject like 'full\_database into %' and ok order by id desc limit 1;
  if v_last.id is null or v_last.ran_at < now() - interval '92 days' then
    v_items := v_items || jsonb_build_object('item', 'full_restore', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'No full-database restore has compared equal in the last 92 days'
               || coalesce(' (last ' || to_char(v_last.ran_at, 'YYYY-MM-DD') || ')', ' (never)'),
      'evidence', jsonb_build_object('last_id', v_last.id, 'runbook', 'docs/it/BACKUP_RPO_RTO.md',
                                     'compare', 'select public.fn_it_full_restore_compare(''<scratch schema>'') on the branch'));
  end if;
  if (select count(*) from public.it_threshold where key in ('backup_rpo_hours', 'backup_rto_hours', 'restore_drill_every_days')) <> 3 then
    v_items := v_items || jsonb_build_object('item', 'targets', 'owner_seat', 'it_engineer', 'subject', 'table_backup', 'config', true,
      'title', 'The RPO/RTO/drill targets are missing from it_threshold');
  end if;
  return jsonb_build_object('last_full_restore', v_last.ran_at, 'settled', public.fn_it_duty_settle('dr_review', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_duty_knowledge_exam()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select jsonb_build_object('asked', 0, 'retired', 'the model exam files no question (24 Sep 2026)') $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_duty_pause_expiry()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p record; v_stakes text; v_out jsonb := '[]'::jsonb; v_closed int;
begin
  for p in select dp.* from public.duty_pause dp where dp.paused_at < now() - interval '7 days' order by dp.paused_at loop
    v_stakes := public.fn_duty_pause_stakes(p.duty);
    perform public.fn_it_engineer_finding_upsert(
      'duty_pause_expired:' || p.duty,
      'Duty ' || p.duty || ' (' || v_stakes || ') has been paused for ' || extract(day from now() - p.paused_at)::int
        || ' days, since ' || to_char(p.paused_at at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' by ' || p.paused_by || ': ' || p.reason,
      'public.duty_pause / ' || p.duty,
      case when v_stakes in ('money', 'security') then 'security' else 'agent_facing' end,
      1,
      jsonb_build_object('duty', p.duty, 'stakes', v_stakes, 'paused_at', p.paused_at, 'paused_by', p.paused_by,
                         'reason', p.reason, 'limit', '7 days'),
      '{}'::text[],
      array['whether the pause is still meant: resume = delete from public.duty_pause where duty = ''' || p.duty || ''''],
      'it_engineer');
    v_out := v_out || jsonb_build_object('duty', p.duty, 'stakes', v_stakes);
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the pause was lifted or renewed (fn_it_engineer_duty_pause_expiry)'
   where f.issue_key like 'duty_pause_expired:%' and f.closed_at is null
     and not exists (select 1 from public.duty_pause dp
                      where 'duty_pause_expired:' || dp.duty = f.issue_key and dp.paused_at < now() - interval '7 days');
  get diagnostics v_closed = row_count;
  return jsonb_build_object('expired', v_out, 'closed', v_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_finding_chase()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f public.it_engineer_finding; o public.agent_actions; n_chased int := 0; n_opened int := 0; v_day int; v_id bigint;
        v_seats jsonb := '{}'::jsonb;
begin
  for f in
    select * from public.it_engineer_finding
     where closed_at is null and started_at < now() - interval '24 hours'
       and issue_key not like 'duty:handoff_sla:%'
       and title not ilike '%ZZ DEMO%' and not coalesce((evidence->>'demo')::boolean, false)
     order by started_at limit 40
  loop
    select * into o from public.agent_actions
     where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
       and detail->>'issue_key' = f.issue_key and not coalesce((detail->>'chase')::boolean, false)
     order by id desc limit 1;
    if not found then
      perform public.fn_it_loop_open(f.issue_key);   -- no loop yet: open the ordinary one, owner resolved there
      n_opened := n_opened + 1;
      continue;
    end if;
    v_day := floor(extract(epoch from now() - f.started_at) / 86400)::int;
    v_id := public.fn_seat_handoff('it_engineer', o.agent, 'it.finding', 'it_engineer_finding',
      f.issue_key || '@' || floor(extract(epoch from f.started_at))::bigint || '@chase' || v_day,
      jsonb_build_object(
        'issue_key', f.issue_key, 'occurrence_started_at', f.started_at, 'duty', coalesce(o.detail->>'duty', 'fault'),
        'subject', o.detail->>'subject', 'title', 'Open ' || v_day || ' day(s): ' || f.title, 'where_it_is', f.where_it_is,
        'chase', true, 'age_hours', round(extract(epoch from now() - f.started_at) / 3600),
        'original_handoff_id', o.id, 'finding_severity', public.fn_it_engineer_severity(f.blast, f.affected, f.started_at),
        'escalated_report_id', o.detail->'escalated_report_id'));
    n_chased := n_chased + 1;
    v_seats := jsonb_set(v_seats, array[o.agent], to_jsonb(coalesce((v_seats->>o.agent)::int, 0) + 1));
  end loop;
  return jsonb_build_object('chased', n_chased, 'loops_opened', n_opened, 'by_seat', v_seats);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_finding_close(p_issue_key text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.it_engineer_finding;
begin
  update public.it_engineer_finding
     set closed_at = coalesce(closed_at, now()), close_note = left(coalesce(p_note, close_note), 2000)
   where issue_key = p_issue_key
  returning * into v;
  if v.issue_key is null then return jsonb_build_object('closed', false, 'reason', 'no such issue_key'); end if;
  -- the RESOLVED note is not sent here: fn_it_engineer_alert_tick sends it, and only if he was
  -- actually emailed about this issue. Closing something he never heard about is not news.
  return jsonb_build_object('closed', true, 'issue_key', v.issue_key,
                            'was_alerted', v.alert_count > 0, 'open_for', (v.closed_at - v.started_at)::text);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_finding_upsert(p_issue_key text, p_title text, p_where text, p_blast text, p_affected integer DEFAULT 0, p_evidence jsonb DEFAULT '{}'::jsonb, p_ruled_out text[] DEFAULT '{}'::text[], p_undetermined text[] DEFAULT '{}'::text[], p_raised_by text DEFAULT 'it_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.it_engineer_finding; v_reopened boolean := false;
begin
  if coalesce(btrim(p_issue_key),'') = '' then
    raise exception 'fn_it_engineer_finding_upsert: p_issue_key is the dedupe identity and cannot be blank';
  end if;

  select * into v from public.it_engineer_finding where issue_key = p_issue_key;
  v_reopened := (v.issue_key is not null and v.closed_at is not null);

  insert into public.it_engineer_finding as f
    (issue_key, title, where_it_is, blast, affected, evidence, ruled_out, undetermined, raised_by)
  values
    (p_issue_key, left(p_title, 300), left(p_where, 300), p_blast, greatest(coalesce(p_affected,0),0),
     coalesce(p_evidence,'{}'::jsonb), coalesce(p_ruled_out,'{}'), coalesce(p_undetermined,'{}'),
     coalesce(nullif(btrim(p_raised_by),''),'it_engineer'))
  on conflict (issue_key) do update set
    title         = excluded.title,
    where_it_is   = excluded.where_it_is,
    blast         = excluded.blast,
    affected      = excluded.affected,
    evidence      = excluded.evidence,
    ruled_out     = excluded.ruled_out,
    undetermined  = excluded.undetermined,
    raised_by     = excluded.raised_by,
    last_seen_at  = now(),
    seen_count    = f.seen_count + 1,
    -- A RECURRENCE IS NEWS. Reopening restarts the clock and the alert state, so a problem that
    -- came back is told once more rather than being suppressed by the alert he got last week.
    started_at        = case when f.closed_at is not null then now() else f.started_at end,
    closed_at         = null,
    close_note        = null,
    alerted_at        = case when f.closed_at is not null then null else f.alerted_at end,
    alerted_severity  = case when f.closed_at is not null then null else f.alerted_severity end,
    alerted_affected  = case when f.closed_at is not null then null else f.alerted_affected end,
    -- alert_count is deliberately NOT reset: it is how the tick knows a reopened issue is a
    -- RECURRENCE rather than a first sighting, and says so on the face of the email.
    close_notified_at = null
  returning * into v;

  return jsonb_build_object(
    'issue_key', v.issue_key, 'reopened', v_reopened, 'seen_count', v.seen_count,
    'started_at', v.started_at,
    'severity', public.fn_it_engineer_severity(v.blast, v.affected, v.started_at));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_game_day()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_month date := date_trunc('month', (now() at time zone 'Asia/Dubai')::date)::date;
  s text; r jsonb; v_left int; v_out jsonb := '[]'::jsonb; v_key text;
begin
  if (select count(*) from public.it_game_day_run where run_month = v_month) >= 5 then
    return jsonb_build_object('ran', false, 'reason', 'this month''s game day is recorded', 'month', v_month);
  end if;
  foreach s in array array['email_provider_down', 'whatsapp_down', 'edge_function_slow', 'db_connection', 'credential_expired'] loop
    continue when exists (select 1 from public.it_game_day_run where run_month = v_month and scenario = s);
    execute format('select public.%I()', 'fn_it_game_day_' || s) into r;
    v_left := public.fn_it_game_day_leftovers();
    if v_left > 0 then
      r := r || jsonb_build_object('passed', false, 'error', coalesce(r->>'error' || '; ', '') || v_left || ' fixture row(s) left behind');
    end if;
    insert into public.it_game_day_run (run_month, scenario, detected, recovered, passed, detection_ms, recovery_ms, checks, error)
    values (v_month, s, coalesce((r->>'detected')::boolean, false), coalesce((r->>'recovered')::boolean, false),
            coalesce((r->>'passed')::boolean, false), (r->>'detection_ms')::numeric, (r->>'recovery_ms')::numeric,
            coalesce(r->'checks', '{}'::jsonb) || jsonb_build_object('leftovers', v_left), r->>'error');

    v_key := 'game_day:' || s;
    if coalesce((r->>'passed')::boolean, false) then
      update public.it_engineer_finding set closed_at = now(), close_note = 'the ' || to_char(v_month, 'Mon YYYY') || ' game day passed'
       where issue_key = v_key and closed_at is null;
    else
      perform public.fn_it_engineer_finding_upsert(v_key,
        'Game day ' || to_char(v_month, 'Mon YYYY') || ': ' || replace(s, '_', ' ') || ' failed ('
          || case when r->>'error' is not null then left(r->>'error', 150)
                  when not coalesce((r->>'detected')::boolean, false) then 'the injected fault was not detected'
                  when not coalesce((r->>'recovered')::boolean, false) then 'the alert did not clear after the fix'
                  else 'a recovery check failed' end || ')',
        'public.it_game_day_run / fn_it_game_day_' || s, 'customer_facing', 1,
        r || jsonb_build_object('month', v_month, 'owner_seat', 'it_engineer'),
        '{}'::text[], array['why the detector or the recovery path did not behave as the scenario expects'], 'it_engineer');
    end if;
    v_out := v_out || jsonb_build_object('scenario', s, 'passed', r->'passed', 'detection_ms', r->'detection_ms', 'recovery_ms', r->'recovery_ms');
  end loop;
  return jsonb_build_object('ran', true, 'month', v_month, 'scenarios', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_ingest_watch_findings()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row      record;
  v_ingested int := 0;
  v_closed   int := 0;
  v_blast    text;
  v_affected int;
  v_errors   text[] := '{}';
begin
  -- OPEN FINDINGS BECOME, OR STAY, ISSUES.
  for v_row in
    select * from public.it_watch_finding where status = 'open'
     order by case severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,
              opened_at
  loop
    begin
      -- The detector's severity, reproduced through the alert's own rule rather than asserted.
      -- 'blast' is what fn_it_engineer_severity reasons about; these are the classes that make its
      -- output match what the detector already decided from the numbers.
      v_blast := case v_row.severity
        when 'critical' then 'customer_facing'   -- critical here means a public surface is affected
        when 'high'     then 'agent_facing'      -- the machine is degraded; people are not yet stuck
        when 'medium'   then 'internal'
        else 'internal' end;

      -- AFFECTED IS A COUNT OF SUBJECTS, NOT A COUNT OF ROWS. A queue holding 1,433 items is one
      -- broken queue, not 1,433 casualties, and feeding the row count in would make every stalled
      -- queue read as a catastrophe and drown the one that is.
      v_affected := case when v_row.severity in ('critical','high') then 1 else 0 end;

      perform public.fn_it_engineer_finding_upsert(
        'watch:' || v_row.detector_key,
        v_row.title,
        v_row.detector || ' / ' || coalesce(v_row.subject, '(no subject)'),
        v_blast,
        v_affected,
        coalesce(v_row.evidence, '{}'::jsonb)
          || jsonb_build_object(
               'detector', v_row.detector,
               'detector_state', v_row.state,
               'detector_severity', v_row.severity,
               'first_detected', v_row.opened_at,
               'times_seen', v_row.seen_count),
        -- NOTHING was ruled out. A detector measures; it does not eliminate causes, and a
        -- fabricated "already checked" line is worse than an empty one because it would be believed.
        array[]::text[],
        array[
          'This came from an automatic detector (' || v_row.detector || '). It established the '
          || 'SYMPTOM and not the cause — no hypothesis has been tested and nothing has been ruled out.',
          'The detector''s own row, including anything seen since this was sent: '
          || 'select * from public.it_watch_finding where detector_key = ' || quote_literal(v_row.detector_key) || ';'
        ],
        'it_engineer.' || v_row.detector);

      v_ingested := v_ingested + 1;
    exception when others then
      v_errors := v_errors || (v_row.detector_key || ': ' || sqlerrm);
    end;
  end loop;

  -- RESOLVED FINDINGS CLOSE THEIR ISSUE. Without this the founder is told a fault appeared and
  -- never told it went away, which is how a person learns to ignore the sender.
  for v_row in
    select w.* from public.it_watch_finding w
     join public.it_engineer_finding f on f.issue_key = 'watch:' || w.detector_key
    where w.status <> 'open' and f.closed_at is null
  loop
    begin
      perform public.fn_it_engineer_finding_close('watch:' || v_row.detector_key,
        'The detector no longer sees it: ' || v_row.detector || ' resolved '
        || coalesce(v_row.resolved_at::text, 'at an unrecorded time') || '.');
      v_closed := v_closed + 1;
    exception when others then
      v_errors := v_errors || (v_row.detector_key || ' (close): ' || sqlerrm);
    end;
  end loop;

  return jsonb_build_object(
    'ingested', v_ingested,
    'closed', v_closed,
    'errors', to_jsonb(v_errors),
    'basis', 'Bridges public.it_watch_finding (what the detectors measured) to '
          || 'public.it_engineer_finding (what the founder has been told). The detector owns '
          || 'whether a fault is present; the alert owns only whether he has heard about it.');
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_exam(p_per_seat integer DEFAULT 2)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text; i record; v_id bigint; v_q text; v_held bigint; v_n int := 0;
begin
  foreach s in array array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'] loop
    for i in
      select k.item_key, k.title, k.content from public.fn_seat_knowledge_items(s) k
       where not exists (select 1 from public.seat_knowledge_exam e
                          where e.seat = s and e.item_key = k.item_key and e.asked_at > now() - interval '90 days')
       order by md5(k.item_key || current_date::text)          -- a different sample each day, reproducible within it
       limit greatest(1, least(coalesce(p_per_seat, 2), 5))
    loop
      v_q := 'Knowledge check for the ' || replace(s, '_', ' ') || ' seat. As the senior member of staff in this role, '
          || 'explain what we know and apply about: ' || coalesce(nullif(btrim(i.title), ''), left(i.content, 160));
      insert into public.seat_knowledge_exam (seat, item_key, question, reference)
      values (s, i.item_key, v_q, left(i.content, 6000)) returning id into v_id;
      -- Asked in the SEAT'S OWN queue, answered by think() from its own knowledge (no research: this measures what
      -- the seat already knows). Replayed the moment the model hold lifts.
      v_held := public.fn_reason_hold(s, s || '.knowledge_exam', v_q,
        jsonb_build_object('seat', s, 'surface', s || '.knowledge_exam', 'question', v_q,
          'context', jsonb_build_object('audience', 'internal'), 'research', false, 'stakes', 'normal',
          'subject', jsonb_build_object('exam_id', v_id), 'dedupeKey', 'kexam:' || v_id),
        jsonb_build_object('filed_by', 'it_engineer.knowledge_exam'), jsonb_build_object('exam_id', v_id), 'seat_duty', 'kexam:' || v_id);
      update public.seat_knowledge_exam set asked_held_id = v_held where id = v_id;
      v_n := v_n + 1;
    end loop;
  end loop;
  return jsonb_build_object('asked', v_n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_exam_answered(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; e public.seat_knowledge_exam; v_grade bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.seat_knowledge_exam where id = (r.subject->>'exam_id')::bigint for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no exam row'); end if;
  if e.answered_at is not null then return jsonb_build_object('applied', true, 'already', e.id); end if;
  update public.seat_knowledge_exam set answer = left(coalesce(p_result->>'answer', ''), 6000), answer_model = p_result->>'model',
         answered_at = now() where id = e.id;
  v_grade := public.fn_seat_duty_reason('it_engineer', 'it_engineer.knowledge_grade',
    'Grade a seat''s answer against the reference knowledge item it was examined on. Judge the MEANING: does the '
      || 'answer state what the reference states, without contradicting it? Wording does not matter.',
    ('[{"id":"correct","meaning":"the answer states the substance of the reference and contradicts nothing in it"},'
    || '{"id":"partial","meaning":"the answer is right as far as it goes but misses a material part of the reference"},'
    || '{"id":"wrong","meaning":"the answer contradicts the reference or states something materially false"},'
    || '{"id":"not_covered","meaning":"the answer does not address the subject of the reference, or declines to"}]')::jsonb,
    jsonb_build_object('seat', e.seat, 'question', e.question, 'reference', left(e.reference, 3000),
                       'answer', left(coalesce(p_result->>'answer', ''), 3000)),
    jsonb_build_object('exam_id', e.id), 'kgrade:' || e.id);
  update public.seat_knowledge_exam set grade_held_id = v_grade where id = e.id;
  return jsonb_build_object('applied', true, 'exam_id', e.id, 'grade_held_id', v_grade);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_pass_rate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; v_out jsonb := '[]'::jsonb; v_raised int := 0; v_refiled int := 0; e record; v_gate jsonb; v_open boolean;
begin
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  v_open := coalesce(v_gate->>'rule', '') not in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state');
  for s in
    select seat,
           count(*) filter (where graded_at > now() - interval '30 days') as n30,
           count(*) filter (where graded_at > now() - interval '30 days' and verdict = 'correct') as ok30,
           count(*) filter (where graded_at <= now() - interval '30 days' and graded_at > now() - interval '60 days') as nprev,
           count(*) filter (where graded_at <= now() - interval '30 days' and graded_at > now() - interval '60 days' and verdict = 'correct') as okprev,
           count(*) filter (where graded_at is null and asked_at < now() - interval '7 days') as ungraded_week
      from public.seat_knowledge_exam group by seat
  loop
    declare r30 numeric := case when s.n30 > 0 then round(s.ok30::numeric / s.n30, 3) end;
            rprev numeric := case when s.nprev > 0 then round(s.okprev::numeric / s.nprev, 3) end;
            v_bad boolean;
    begin
      v_bad := s.n30 >= 5 and (r30 < 0.70 or (rprev is not null and s.nprev >= 5 and rprev - r30 >= 0.10));
      v_out := v_out || jsonb_build_object('seat', s.seat, 'rate_30d', r30, 'graded_30d', s.n30, 'rate_prev_30d', rprev, 'raised', v_bad);
      if v_bad then
        v_raised := v_raised + 1;
        perform public.fn_it_engineer_finding_upsert('knowledge_pass_rate:' || s.seat,
          'The ' || s.seat || ' seat''s knowledge pass rate is ' || round(r30 * 100) || '% over the last 30 days'
            || case when rprev is not null then ' (was ' || round(rprev * 100) || '%)' else '' end,
          'public.seat_knowledge_exam', 'agent_facing', (s.n30 - s.ok30)::int,
          jsonb_build_object('seat', s.seat, 'rate_30d', r30, 'rate_prev_30d', rprev, 'graded_30d', s.n30, 'owner_seat', 'ceo'),
          '{}'::text[], array['which items it answered wrong and why'], 'it_engineer');
        perform public.fn_seat_handoff('it_engineer', 'ceo', 'it.finding', 'seat_knowledge_exam',
          'knowledge_pass_rate:' || s.seat || ':' || to_char(now(), 'IYYY-IW'),
          jsonb_build_object('duty', 'knowledge_pass_rate', 'issue_key', 'knowledge_pass_rate:' || s.seat, 'subject', s.seat || ' knowledge',
                             'title', 'The ' || replace(s.seat, '_', ' ') || ' seat''s knowledge pass rate dropped to ' || round(r30 * 100) || '%; its missed items are filed for re-research in its queue, and holding the seat to the bar is yours'));
        -- THE SEAT ACTS: every item it missed in the window is re-researched in its own queue.
        for e in select * from public.seat_knowledge_exam
                  where seat = s.seat and verdict in ('wrong', 'partial', 'not_covered') and graded_at > now() - interval '30 days' and refiled_at is null loop
          perform public.fn_reason_hold(e.seat, e.seat || '.knowledge_refresh',
            'Re-research and correct our knowledge on: ' || e.question || ' — the answer given was graded ' || e.verdict || '.',
            jsonb_build_object('seat', e.seat, 'surface', e.seat || '.knowledge_refresh',
              'question', 'Re-research and correct our knowledge on: ' || e.question, 'research', true, 'stakes', 'high',
              'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('reference', left(e.reference, 2000), 'grade', e.grade_reason)),
              'subject', jsonb_build_object('item_key', e.item_key, 'exam_id', e.id), 'dedupeKey', 'krefile:' || e.id),
            jsonb_build_object('filed_by', 'it_engineer.knowledge_pass_rate'), jsonb_build_object('item_key', e.item_key, 'exam_id', e.id),
            'seat_duty', 'krefile:' || e.id);
          update public.seat_knowledge_exam set refiled_at = now() where id = e.id;
          v_refiled := v_refiled + 1;
        end loop;
      else
        update public.it_engineer_finding set closed_at = now(), close_note = 'pass rate back within bounds (knowledge_pass_rate)'
         where issue_key = 'knowledge_pass_rate:' || s.seat and closed_at is null;
      end if;
      -- An exam nobody could grade for a week WHILE a model can reason is a broken monitor, not a quiet one.
      if v_open and s.ungraded_week > 0 then
        perform public.fn_it_engineer_finding_upsert('knowledge_pass_rate:unmeasured:' || s.seat,
          s.ungraded_week || ' knowledge exam(s) of ' || s.seat || ' asked over a week ago are still ungraded while the model gate is open',
          'public.seat_knowledge_exam / reasoning_held_question', 'agent_facing', s.ungraded_week::int,
          jsonb_build_object('seat', s.seat), '{}'::text[], array['whether the replay or the apply fails'], 'it_engineer');
      else
        update public.it_engineer_finding set closed_at = now(), close_note = 'exams are being graded (or the model hold explains it)'
         where issue_key = 'knowledge_pass_rate:unmeasured:' || s.seat and closed_at is null;
      end if;
    end;
  end loop;
  return jsonb_build_object('seats', v_out, 'raised', v_raised, 'refiled', v_refiled, 'model_gate_open', v_open);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_recall_exam()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_day date := (now() at time zone 'Asia/Dubai')::date; s record; q record; p public.seat_knowledge_recall;
  v_floor numeric; v_bad text; v_out jsonb := '[]'::jsonb; v_raised int := 0; v_scored int := 0; v_left int;
  v_missing int; v_due int; v_t timestamptz := clock_timestamp();
begin
  if not exists (select 1 from public.seat_knowledge_eval_question) then
    perform public.fn_it_engineer_finding_upsert('knowledge_recall:no_questions',
      'The daily knowledge exam has no questions loaded, so no seat''s knowledge is being examined',
      'public.seat_knowledge_eval_question', 'agent_facing', 6, jsonb_build_object('owner_seat', 'it_engineer'),
      '{}'::text[], array['run node scripts/kb/load_knowledge_eval_questions.mjs'], 'it_engineer');
    return jsonb_build_object('day', v_day, 'questions', 0, 'raised', 1);
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'questions are loaded (knowledge_recall)'
   where issue_key = 'knowledge_recall:no_questions' and closed_at is null;

  -- Nothing is scored while any question lacks its ml vector. Only a question already loaded at now() can be owed
  -- one: a question loaded later did not exist at that instant (what a replay at a past instant reads), so it is
  -- not missing anything then. Live, every question was loaded in the past, so this counts every missing question.
  select count(*), count(*) filter (where loaded_at <= now()) into v_missing, v_due
    from public.seat_knowledge_eval_question where embedding_ml is null;
  if v_missing > 0 then
    if v_due > 0 then
      perform public.fn_it_engineer_finding_upsert('knowledge_recall:no_ml_vectors',
        v_due || ' exam questions have no multilingual vector, so the bilingual path the seats read is not being examined',
        'public.seat_knowledge_eval_question.embedding_ml', 'agent_facing', v_due,
        jsonb_build_object('owner_seat', 'it_engineer', 'missing', v_due),
        '{}'::text[], array['run node scripts/kb/load_knowledge_eval_questions.mjs --ml'], 'it_engineer');
    end if;
    return jsonb_build_object('day', v_day, 'missing_ml', v_missing, 'raised', (v_due > 0)::int);
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'every question has its ml vector (knowledge_recall)'
   where issue_key = 'knowledge_recall:no_ml_vectors' and closed_at is null;

  if exists (select 1 from public.seat_knowledge_recall where day = v_day and path = 'ml') then
    return jsonb_build_object('day', v_day, 'done', true);
  end if;

  -- one time-bound beat: score today's unscored questions until 4 s have passed (67 ms a call warm, measured)
  for q in select * from public.seat_knowledge_eval_question q
            where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = q.id)
            order by q.id limit 150
  loop
    exit when clock_timestamp() - v_t > interval '4 seconds';
    insert into public.seat_knowledge_recall_answer (day, question_id, seat, lang, recall)
    select v_day, q.id, q.seat, q.lang,
           (select count(distinct regexp_replace(x->>'id', '@ar$', ''))
              from jsonb_array_elements(public.fn_reason_retrieve_ml(q.seat, q.embedding_ml, q.embedding, 6)) with ordinality t(x, n)
             where n <= 5 and regexp_replace(x->>'id', '@ar$', '') = any(q.expected))::numeric
           / (select count(distinct e) from unnest(q.expected) e)
    on conflict do nothing;
    v_scored := v_scored + 1;
  end loop;
  select count(*) into v_left from public.seat_knowledge_eval_question q
   where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = q.id);
  if v_left > 0 then
    return jsonb_build_object('day', v_day, 'scored', v_scored, 'left', v_left);
  end if;

  for s in
    select seat, count(*) filter (where lang = 'en') as questions,
           round(avg(recall) filter (where lang = 'en'), 3) as en, round(avg(recall) filter (where lang = 'ar'), 3) as ar
      from public.seat_knowledge_recall_answer where day = v_day group by seat
  loop
    select * into p from public.seat_knowledge_recall where seat = s.seat and day < v_day and path = 'ml' order by day desc limit 1;
    insert into public.seat_knowledge_recall (day, seat, questions, recall_en, recall_ar, path)
    values (v_day, s.seat, s.questions, s.en, s.ar, 'ml')
    on conflict (day, seat) do update set questions = excluded.questions, recall_en = excluded.recall_en,
                                          recall_ar = excluded.recall_ar, path = 'ml', measured_at = now();
    -- the Arabic floor: set once, by the first 'ml' day, to the 0.05 at or below it; never lowered here
    if s.ar is not null then
      insert into public.seat_knowledge_recall_floor (seat, lang, floor, set_on, set_from)
      values (s.seat, 'ar', floor(s.ar * 20) / 20, v_day, s.ar) on conflict (seat, lang) do nothing;
    end if;
    select f.floor into v_floor from public.seat_knowledge_recall_floor f where f.seat = s.seat and f.lang = 'ar';
    v_bad := case when s.en is null or s.en < 0.35 then 'English under the floor 0.35'
                  when p.recall_en is not null and p.recall_en - s.en >= 0.10 then 'English down from ' || p.recall_en || ' on ' || p.day
                  when s.ar is null or s.ar < greatest(v_floor, 0.10) then 'Arabic under the floor ' || greatest(v_floor, 0.10)
                  when p.recall_ar is not null and p.recall_ar - s.ar >= 0.10 then 'Arabic down from ' || p.recall_ar || ' on ' || p.day end;
    if v_bad is not null then
      v_raised := v_raised + 1;
      perform public.fn_it_engineer_finding_upsert('knowledge_recall:' || s.seat,
        'The ' || s.seat || ' seat finds its own knowledge less: recall@5 EN ' || coalesce(s.en::text, 'unmeasured')
          || ', AR ' || coalesce(s.ar::text, 'unmeasured') || ' (' || v_bad || ')',
        'public.seat_knowledge_recall / public.fn_reason_retrieve_ml', 'agent_facing', s.questions::int,
        jsonb_build_object('seat', s.seat, 'owner_seat', 'it_engineer', 'recall_en', s.en, 'recall_ar', s.ar,
                           'floor_ar', v_floor, 'previous', to_jsonb(p)),
        '{}'::text[], array['which pack''s questions stopped finding their entries, and whether rows lost their vectors'], 'it_engineer');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'recall back within bounds (knowledge_recall)'
       where issue_key = 'knowledge_recall:' || s.seat and closed_at is null;
    end if;
    v_out := v_out || jsonb_build_object('seat', s.seat, 'questions', s.questions, 'recall_en', s.en, 'recall_ar', s.ar,
                                         'floor_ar', v_floor, 'raised', v_bad is not null);
  end loop;
  delete from public.seat_knowledge_recall_answer where day < v_day - 7;
  return jsonb_build_object('day', v_day, 'path', 'ml', 'seats', v_out, 'raised', v_raised);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_refresh()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text; i record; v_q date := date_trunc('quarter', (now() at time zone 'Asia/Dubai'))::date; v_items jsonb; v_held bigint;
  v_opened int := 0; v_verified int := 0; v_overdue int := 0; f record; v_text text;
begin
  foreach s in array array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'] loop
    if not exists (select 1 from public.seat_knowledge_refresh where seat = s and quarter = v_q) then
      v_items := '[]'::jsonb;
      for i in select k.item_key, k.title, k.content from public.fn_seat_knowledge_items(s) k
                order by k.updated_at nulls first, k.item_key limit 5 loop
        v_text := 'Quarterly knowledge refresh (' || to_char(v_q, 'YYYY "Q"Q') || '). Is this still correct and current in the '
               || 'UAE today? Check the authoritative source and state precisely what has changed, if anything. Item: '
               || coalesce(i.title, '') || E'\n' || left(i.content, 1500);
        v_held := public.fn_reason_hold(s, s || '.knowledge_refresh', v_text,
          jsonb_build_object('seat', s, 'surface', s || '.knowledge_refresh', 'question', v_text, 'research', true, 'stakes', 'high',
            'context', jsonb_build_object('audience', 'internal'),
            'subject', jsonb_build_object('item_key', i.item_key, 'quarter', v_q), 'dedupeKey', 'krefresh:' || v_q || ':' || i.item_key),
          jsonb_build_object('filed_by', 'it_engineer.knowledge_refresh'), jsonb_build_object('item_key', i.item_key, 'quarter', v_q),
          'seat_duty', 'krefresh:' || v_q || ':' || i.item_key);
        v_items := v_items || jsonb_build_object('item_key', i.item_key, 'title', left(i.title, 200), 'held_id', v_held, 'done_at', null);
      end loop;
      insert into public.seat_knowledge_refresh (seat, quarter, items) values (s, v_q, v_items);
      v_opened := v_opened + 1;
    end if;
  end loop;

  -- VERIFY: a quarter is refreshed when every item it filed was reasoned (the apply stamps done_at).
  update public.seat_knowledge_refresh r set verified_at = now()
   where verified_at is null and jsonb_array_length(items) > 0
     and not exists (select 1 from jsonb_array_elements(r.items) x where x->>'done_at' is null);
  get diagnostics v_verified = row_count;
  for f in select * from public.seat_knowledge_refresh where verified_at is null and opened_at < now() - interval '45 days' loop
    v_overdue := v_overdue + 1;
    perform public.fn_it_engineer_finding_upsert('knowledge_refresh:' || f.seat || ':' || f.quarter,
      'The ' || f.seat || ' seat''s knowledge refresh for ' || to_char(f.quarter, 'YYYY "Q"Q') || ' is not complete after 45 days',
      'public.seat_knowledge_refresh', 'agent_facing',
      (select count(*)::int from jsonb_array_elements(f.items) x where x->>'done_at' is null),
      jsonb_build_object('seat', f.seat, 'quarter', f.quarter, 'owner_seat', f.seat), '{}'::text[],
      array['whether the model hold or a failing research step keeps the questions held'], 'it_engineer');
  end loop;
  update public.it_engineer_finding fi set closed_at = now(), close_note = 'the quarter''s refresh completed'
   where fi.issue_key like 'knowledge_refresh:%' and fi.closed_at is null
     and exists (select 1 from public.seat_knowledge_refresh r
                  where 'knowledge_refresh:' || r.seat || ':' || r.quarter = fi.issue_key and r.verified_at is not null);
  return jsonb_build_object('quarter', v_q, 'opened', v_opened, 'verified', v_verified, 'overdue', v_overdue);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_refreshed(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_n int;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'quarter') is null then
    -- a re-research filed by the pass-rate monitor: the exam row carries it
    return jsonb_build_object('applied', true, 'refiled_exam', r.subject->>'exam_id', 'sources', jsonb_array_length(coalesce(p_result->'sources', '[]'::jsonb)));
  end if;
  update public.seat_knowledge_refresh k
     set items = (select jsonb_agg(case when x->>'item_key' = r.subject->>'item_key' and x->>'done_at' is null
                                        then x || jsonb_build_object('done_at', now(), 'sources', jsonb_array_length(coalesce(p_result->'sources', '[]'::jsonb)))
                                        else x end order by o)
                    from jsonb_array_elements(k.items) with ordinality t(x, o))
   where k.seat = r.seat and k.quarter = (r.subject->>'quarter')::date;
  get diagnostics v_n = row_count;
  return jsonb_build_object('applied', v_n > 0, 'item_key', r.subject->>'item_key');
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_search_vector()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.content,'')), 'C');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_latency_slo()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; j jsonb; v_owner text; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb;
        v_site numeric; v_site_n int;
begin
  for x in
    with r as (
      select substring(r.agent from 4) fn, r.started_at, (r.counts->>'ms')::numeric ms,
             (r.counts->>'budget_ms')::int budget,
             r.status, (coalesce((r.counts->>'http')::int, 0) >= 500 or r.status = 'error') srv_err
        from public.agent_runs r
       where r.agent like 'fn:%' and r.started_at > now() - interval '30 days'
         and r.counts ? 'budget_ms'
         and coalesce(r.counts->>'http', '') <> '204' and coalesce(r.counts->>'method', '') <> 'OPTIONS'
         and coalesce(r.counts->>'region', '') not like 'us-%'
         -- OUR OWN HARNESS IS NOT A USER (29 Sep 2026): a run the SERVER marked fixture (a reserved test identity,
         -- _shared/demo_identity.ts; our launch-path probe) spends no error budget - the key refusal_rate already skips.
         and not (r.counts ? 'fixture'))
    select fn, max(budget) budget,
           count(*) filter (where d1 and status = 'ok') n,
           percentile_cont(0.95) within group (order by ms) filter (where d1 and status = 'ok') p95,
           count(*) filter (where d1) runs_24h,
           count(*) filter (where d1 and (srv_err or ms > budget)) bad_24h,
           count(*) runs_30d,
           count(*) filter (where srv_err or ms > budget) bad_30d,
           count(*) filter (where srv_err) err_30d,
           percentile_cont(0.95) within group (order by ms) p95_30d
      from (select r.*, r.started_at > now() - interval '24 hours' d1 from r) z
     group by fn
  loop
    j := public.fn_it_slo_judge(x.runs_24h::int, x.p95::numeric, x.budget::int, x.bad_24h::int, x.runs_30d::int, x.bad_30d::int);
    v_owner := coalesce((select o.owner from public.function_owner o where o.function_slug = x.fn), 'it_engineer');
    v_out := v_out || jsonb_build_object('fn', x.fn, 'runs', x.n, 'p95_ms', round(x.p95), 'budget_ms', x.budget,
      'runs_30d', x.runs_30d, 'availability_30d', j->'availability',
      'error_rate_30d', case when x.runs_30d > 0 then round(x.err_30d::numeric / x.runs_30d, 4) end,
      'p95_30d_ms', round(x.p95_30d), 'error_budget_spent', j->'budget_spent', 'burn_rate_24h', j->'burn_rate_24h');
    if (j->>'p95_breach')::boolean then
      v_items := v_items || jsonb_build_object('item', x.fn, 'subject', x.fn, 'blast', 'customer_facing', 'affected', x.n,
        'owner_seat', v_owner,
        'title', x.fn || ' answered in ' || round(x.p95) || ' ms at p95 over the last 24 h (' || x.n || ' runs'
                 || case when (j->>'small_sample')::boolean then ', a small sample' else '' end
                 || '); the budget is ' || x.budget || ' ms',
        'evidence', jsonb_build_object('p95_ms', round(x.p95), 'runs', x.n, 'budget_ms', x.budget, 'window', '24 hours'));
    end if;
    if (j->>'budget_breach')::boolean then
      v_items := v_items || jsonb_build_object('item', x.fn || ':error_budget', 'subject', x.fn, 'blast', 'customer_facing',
        'affected', x.bad_24h, 'owner_seat', v_owner,
        'title', x.fn || ' is burning its error budget at ' || (j->>'burn_rate_24h') || 'x over 24 h; 30-day availability '
                 || round((j->>'availability')::numeric * 100, 2) || ' % against a 99.9 % objective',
        'evidence', j || jsonb_build_object('runs_24h', x.runs_24h, 'bad_24h', x.bad_24h, 'runs_30d', x.runs_30d,
                                            'bad_30d', x.bad_30d, 'server_errors_30d', x.err_30d));
    end if;
  end loop;

  select percentile_cont(0.95) within group (order by site_ms), count(site_ms) into v_site, v_site_n
    from public.it_watch_tick where ran_at > now() - interval '24 hours' and site_ms is not null;
  if v_site_n >= 30 and v_site > 2500 then
    v_items := v_items || jsonb_build_object('item', 'site_home', 'subject', 'website', 'blast', 'customer_facing', 'owner_seat', 'it_engineer',
      'title', 'The website home page answered in ' || round(v_site) || ' ms at p95 over the last 24 h; the budget is 2500 ms',
      'evidence', jsonb_build_object('p95_ms', round(v_site), 'samples', v_site_n));
  end if;

  return jsonb_build_object('functions', v_out, 'site_p95_ms', round(v_site), 'site_samples', v_site_n,
                            'settled', public.fn_it_duty_settle('latency_slo', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_licence_expiry_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_asks jsonb; v_before int; v_after int; v_fix json; v_ids jsonb;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_asks := public.fn_licence_expiry_sweep(false);

  -- THE INVARIANT, measured here and not trusted to the routine that sets it: an approved supplier whose licence
  -- or insurance is past its date is not matchable (fn_is_matchable reads matching_blocked).
  select count(*) into v_before from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry < v_today or l.insurance_expiry < v_today);
  if v_before > 0 then v_fix := public.fn_reconcile_doc_blocks(0); end if;   -- pauses them AND tells each supplier
  select count(*), coalesce(jsonb_agg(l.id order by l.id), '[]'::jsonb) into v_after, v_ids from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry < v_today or l.insurance_expiry < v_today);

  if v_after > 0 then
    perform public.fn_it_engineer_finding_upsert('licence_expiry:matchable_after_expiry',
      v_after || ' approved supplier(s) with an expired licence or insurance are still matchable after the pause ran',
      'public.leads / fn_reconcile_doc_blocks', 'customer_facing', v_after, jsonb_build_object('lead_ids', v_ids, 'owner_seat', 'sales_engineer'),
      '{}'::text[], array['why fn_reconcile_doc_blocks skipped them (a manual block reason it will not overwrite?)'], 'it_engineer');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'no expired supplier is matchable (licence_expiry_watch)'
     where issue_key = 'licence_expiry:matchable_after_expiry' and closed_at is null;
  end if;
  return jsonb_build_object('renewal_asks', v_asks - 'sample', 'expired_matchable_before', v_before,
                            'paused', v_fix, 'expired_matchable_after', v_after);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_model_spend()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; v_items jsonb := '[]'::jsonb;
begin
  -- a think() surface is listed by construction (it lives in reasoning_held_question); ai_cost_log fn:task_class must be registered
  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, count(*) n, max(a.seat) seat from public.ai_cost_log a
            where a.occurred_at > now() - interval '24 hours' and a.fn is not null
              and not public.fn_it_model_consumer_listed(a.fn, a.task_class)
            group by 1 loop
    v_items := v_items || jsonb_build_object('item', 'unlisted:' || x.k, 'owner_seat', 'ceo', 'subject', x.k, 'blast', 'internal', 'affected', x.n,
      'title', x.k || ' called a model ' || x.n || ' time(s) in 24 h and is not in the model-consumer inventory (it_model_consumer)',
      'evidence', jsonb_build_object('calls_24h', x.n, 'seat', x.seat));
  end loop;

  for x in with h as (select a.fn || ':' || coalesce(a.task_class, 'unclassified') k,
                             count(*) filter (where a.occurred_at > now() - interval '1 hour') last_hour,
                             count(*) filter (where a.occurred_at <= now() - interval '1 hour') / 168.0 mean_hour
                        from public.ai_cost_log a where a.occurred_at > now() - interval '7 days 1 hour' and a.fn is not null group by 1)
           select h.*, c.owner_seat from h left join public.it_model_consumer c on c.consumer = h.k
            where h.last_hour > greatest(30, 5 * h.mean_hour) loop
    v_items := v_items || jsonb_build_object('item', 'runaway:' || x.k, 'owner_seat', coalesce(x.owner_seat, 'ceo'), 'subject', x.k,
      'blast', 'internal', 'affected', x.last_hour,
      'title', x.k || ' made ' || x.last_hour || ' model calls in the last hour against a usual ' || round(x.mean_hour, 1) || ' an hour: a loop until shown otherwise',
      'evidence', jsonb_build_object('last_hour', x.last_hour, 'mean_hour_7d', round(x.mean_hour, 2)));
  end loop;

  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, a.cache_hit_key key, count(*) n, max(c.owner_seat) owner_seat
             from public.ai_cost_log a left join public.it_model_consumer c on c.consumer = a.fn || ':' || coalesce(a.task_class, 'unclassified')
            where a.occurred_at > now() - interval '1 hour' and not a.cached and a.cache_hit_key is not null
            group by 1, 2 having count(*) >= 5 loop
    v_items := v_items || jsonb_build_object('item', 'repeat:' || x.k || ':' || left(md5(x.key), 12), 'owner_seat', coalesce(x.owner_seat, 'ceo'),
      'subject', x.k, 'blast', 'internal', 'affected', x.n,
      'title', x.k || ' paid for the same uncached call ' || x.n || ' times in the last hour',
      'evidence', jsonb_build_object('cache_hit_key', x.key, 'calls', x.n));
  end loop;

  return jsonb_build_object('settled', public.fn_it_duty_settle('model_spend', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_postmortem()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; v_inc bigint; p public.it_playbook; v_since timestamptz; n_open int := 0; n_play int := 0; n_asked int := 0;
        v_hist int; v_late int; v_ids jsonb; v_items jsonb := '[]'::jsonb; f public.it_engineer_finding;
begin
  select created_at into v_since from public.seat_duty where duty = 'it_engineer.postmortem';
  v_since := coalesce(v_since, now());

  for h in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
       and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
       and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
     order by a.id limit 50
  loop
    v_inc := public.fn_it_incident_open(h.id);
    n_open := n_open + 1;
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, h.decided_at, now()),
           fix = coalesce(fix, 'Closed: ' || coalesce(f.close_note, 'the ' || h.agent || ' answered and the finding cleared')),
           updated_at = now() where id = v_inc;
    select * into p from public.it_playbook where (h.detail->>'issue_key') like issue_prefix || '%'
     order by length(issue_prefix) desc limit 1;
    if found then
      update public.it_incident set playbook_class = p.failure_class,
             cause = coalesce(cause, p.typical_cause, 'Known failure class ' || p.failure_class || ': ' || coalesce(p.remedy, p.not_automatable_reason)),
             regression_check = coalesce(regression_check, p.regression_check), recorded_by = 'it_engineer.postmortem', updated_at = now()
       where id = v_inc;
      n_play := n_play + 1;
    end if;
  end loop;

  -- A class the playbook has never seen: its root cause is asked once, three incidents a run, oldest first. Asked from
  -- the incident (not the pass that opened it) so an incident past one run's cap is asked on the next.
  for h in
    select i.id inc_id, a.detail, a.evidence from public.it_incident i join public.agent_actions a on a.id = i.handoff_id
     where i.created_at >= v_since and i.playbook_class is null and coalesce(btrim(i.cause), '') = ''
       and not exists (select 1 from public.reasoning_held_question q where q.dedupe_key = 'postmortem:' || i.id)
     order by i.id limit 3
  loop
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    perform public.fn_reason_hold('it_engineer', 'it_engineer.postmortem',
      'Postmortem: what was the root cause of this fault, in two or three sentences? ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
      jsonb_build_object('seat', 'it_engineer', 'surface', 'it_engineer.postmortem', 'research', false, 'stakes', 'normal',
        'question', 'Root cause of: ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
        'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('handoff', h.detail, 'answer', h.evidence,
          'finding', to_jsonb(f) - 'evidence')),
        'subject', jsonb_build_object('incident_id', h.inc_id), 'dedupeKey', 'postmortem:' || h.inc_id),
      jsonb_build_object('filed_by', 'it_engineer.postmortem'), jsonb_build_object('incident_id', h.inc_id), 'seat_duty', 'postmortem:' || h.inc_id);
    n_asked := n_asked + 1;
  end loop;

  select count(*) into v_hist from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.detail->>'severity' in ('critical', 'high')
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id);

  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]') into v_late, v_ids
    from (select i.id, row_number() over (order by i.id) rn from public.it_incident i
           where i.ended_at < now() - interval '72 hours' and i.created_at >= v_since
             and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.regression_check), '') = '')) z;
  if v_late > 0 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'incomplete', 'owner_seat', 'it_engineer', 'blast', 'internal', 'affected', v_late,
      'title', v_late || ' closed incident(s) have no root cause or no regression check 72 hours after they closed',
      'evidence', jsonb_build_object('incident_ids', v_ids)));
  end if;

  return jsonb_build_object('opened', n_open, 'from_playbook', n_play, 'asked', n_asked,
                            'historical_without_postmortem', v_hist, 'settled', public.fn_it_duty_settle('postmortem', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_scanner_beat(p_scanner text, p_error text DEFAULT NULL::text, p_max_gap_minutes integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.it_engineer_scanner;
begin
  insert into public.it_engineer_scanner as s (scanner, last_beat_at, last_ok_at, last_error, max_gap_minutes)
  values (p_scanner, now(), case when p_error is null then now() end, left(p_error, 1000),
          least(greatest(coalesce(p_max_gap_minutes,60), 5), 1440))
  on conflict (scanner) do update set
    last_beat_at    = now(),
    last_ok_at      = case when p_error is null then now() else s.last_ok_at end,
    last_error      = left(p_error, 1000),
    max_gap_minutes = least(greatest(coalesce(p_max_gap_minutes, s.max_gap_minutes), 5), 1440)
  returning * into v;
  return jsonb_build_object('scanner', v.scanner, 'ok', p_error is null, 'max_gap_minutes', v.max_gap_minutes);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_self_review()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'it_engineer') $function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_severity(p_blast text, p_affected integer, p_started_at timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    -- data or credentials exposed: there is no count at which this waits
    when p_blast = 'security' then 'critical'
    -- a customer cannot complete something. Someone is actually stuck -> critical;
    -- the path is broken but nobody has hit it yet -> high (still same-day work)
    when p_blast = 'customer_facing' then case when coalesce(p_affected,0) > 0 then 'critical' else 'high' end
    -- a blind detector. High from the first tick, because its silence is now worthless;
    -- critical once we have been blind for 6h, because by then "nothing was reported" means nothing
    when p_blast = 'monitor' then case when now() - p_started_at >= interval '6 hours' then 'critical' else 'high' end
    -- an agent cannot do its job: no customer is stuck yet, but work is not happening
    when p_blast = 'agent_facing' then case when coalesce(p_affected,0) > 0 or now() - p_started_at >= interval '6 hours' then 'high' else 'warn' end
    -- internal only. Quiet by default; a thing still broken six hours later is not routine
    else case when coalesce(p_affected,0) > 0 and now() - p_started_at >= interval '6 hours' then 'high' else 'warn' end
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_engineer_uptime_slo()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb; v_pruned int;
begin
  for x in
    select substring(fn_key from 8) url, count(*) n, count(*) filter (where verdict = 'up') up
      from public.edge_health_probe
     where fn_key like 'uptime:%' and checked_at > now() - interval '30 days'
     group by 1
  loop
    v_out := v_out || jsonb_build_object('url', x.url, 'samples', x.n, 'up', x.up,
                                         'uptime_pct', round(100.0 * x.up / x.n, 3));
    if x.n >= 96 and x.up::numeric / x.n < 0.999 then
      v_items := v_items || jsonb_build_object('item', x.url, 'subject', 'website', 'blast', 'customer_facing',
        'owner_seat', 'it_engineer', 'affected', x.n - x.up,
        'title', x.url || ' was up ' || round(100.0 * x.up / x.n, 3) || '% of ' || x.n
                 || ' external checks over 30 days; the target is 99.9%',
        'evidence', jsonb_build_object('samples', x.n, 'up', x.up, 'down', x.n - x.up, 'target', 0.999, 'window', '30 days'));
    end if;
  end loop;

  delete from public.edge_health_probe
   where id in (select id from public.edge_health_probe where checked_at < now() - interval '90 days' limit 5000);
  get diagnostics v_pruned = row_count;

  return jsonb_build_object('urls', v_out, 'pruned', v_pruned, 'settled', public.fn_it_duty_settle('uptime_slo', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_expiry_measured(p_expiries jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; n_date int := 0; n_never int := 0; n_seen int := 0;
begin
  if jsonb_typeof(coalesce(p_expiries, 'null'::jsonb)) is distinct from 'object' then
    raise exception 'fn_it_expiry_measured takes the expiries object from takeDutyReadings';
  end if;
  for x in select key, value from jsonb_each(p_expiries) loop
    -- A reading that was not taken settles nothing: an unreachable RDAP server must not clear a date.
    continue when x.value->>'basis' is distinct from 'measured';
    if (x.value->>'expires_on') is not null then
      update public.it_expiry
         set expires_on = (x.value->>'expires_on')::date, never_expires = false, checked_at = now()
       where item = x.key;
      if found then n_date := n_date + 1; end if;
    elsif coalesce((x.value->>'never_expires')::boolean, false) then
      -- The source line is written only on the transition, so a row that has been settled for months
      -- does not rewrite its own provenance with today's date on every tick.
      update public.it_expiry
         set never_expires = true, expires_on = null, checked_at = now(),
             source = left('the provider reports no expiry (measured '
                           || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || '): ' || source, 500)
       where item = x.key and never_expires is distinct from true;
      if found then n_never := n_never + 1; end if;
      update public.it_expiry set checked_at = now() where item = x.key;
    else
      -- Read, and the provider gave no date and did not say there is none: still unknown, but the row
      -- records that it was looked at today, so a stale checked_at means the reading stopped running.
      update public.it_expiry set checked_at = now() where item = x.key;
    end if;
    n_seen := n_seen + 1;
  end loop;
  return jsonb_build_object('read', n_seen, 'dated', n_date, 'never_expires', n_never);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_external_cause_close(p_integration text, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.it_integration_external_cause set closed_at = now(), close_note = p_note
   where integration = p_integration and closed_at is null;
  if not found then return false; end if;
  delete from public.it_founder_decision_class where issue_key_like = 'duty:integration%:' || p_integration and not to_founder;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_external_cause_open(p_integration text, p_party text, p_ticket text, p_opened_on date, p_thread text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_owner text DEFAULT 'it_engineer'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  if coalesce(btrim(p_integration), '') = '' or coalesce(btrim(p_party), '') = '' or coalesce(btrim(p_ticket), '') = '' or p_opened_on is null then
    raise exception 'fn_it_external_cause_open(integration, party, ticket, opened_on): all four are required';
  end if;
  insert into public.it_integration_external_cause (integration, external_party, ticket_ref, opened_on, thread_hint, note, owner_seat)
  values (p_integration, p_party, p_ticket, p_opened_on, p_thread, p_note, coalesce(p_owner, 'it_engineer'))
  on conflict (integration) where closed_at is null do update
     set external_party = excluded.external_party, ticket_ref = excluded.ticket_ref, opened_on = excluded.opened_on,
         thread_hint = coalesce(excluded.thread_hint, it_integration_external_cause.thread_hint),
         note = coalesce(excluded.note, it_integration_external_cause.note)
  returning id into v_id;
  -- The digest's register reads this key as NOT his while the cause is open (the more specific row wins).
  insert into public.it_founder_decision_class (issue_key_like, to_founder, why)
  values ('duty:integration%:' || p_integration, false,
          'waiting on ' || p_party || ' (ticket ' || p_ticket || ', opened ' || to_char(p_opened_on, 'DD Mon') || '); the IT engineer follows it up and nothing is needed from you')
  on conflict (issue_key_like) do update set to_founder = false, why = excluded.why;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_external_cause_reply(p_integration text, p_at timestamp with time zone, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.it_integration_external_cause; v_needs boolean := public.fn_it_external_reply_needs_founder(p_text);
begin
  select * into c from public.it_integration_external_cause where integration = p_integration and closed_at is null;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open external cause for ' || p_integration); end if;
  if c.last_reply_at is not null and p_at <= c.last_reply_at then
    return jsonb_build_object('ok', true, 'unchanged', true);
  end if;
  update public.it_integration_external_cause
     set last_reply_at = p_at, last_reply_excerpt = left(p_text, 1500), reply_needs_founder = v_needs,
         founder_told_at = case when v_needs then null else founder_told_at end, last_checked_at = now()
   where id = c.id;
  return jsonb_build_object('ok', true, 'needs_founder', v_needs);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_external_reply_needs_founder(p_text text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_text, '') ~* '(please|kindly|could you|can you|we need you to|you will need to|you need to)[^.?!]{0,80}\m(provide|share|send|confirm|verify|complete|reply|respond|approve|upload|screenshot|log ?in|sign ?in|re-?register|delete|update|resubmit)'
      or coalesce(p_text, '') ~* '(action required|awaiting your (reply|response|update|confirmation)|pending your (reply|response|update))'
$function$


CREATE OR REPLACE FUNCTION public.fn_it_full_restore_compare(p_schema text, p_only text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t text; v_live bigint; v_rest bigint; c_live text; c_rest text; v_rows jsonb := '[]'::jsonb;
        n_bad int := 0; n_missing int := 0; v_start timestamptz := clock_timestamp(); v_ok boolean; v_out jsonb;
begin
  if p_schema is null or p_schema in ('public', 'auth', 'storage', 'extensions', 'vault', 'cron', 'realtime')
     or p_schema like 'pg\_%' or not exists (select 1 from pg_namespace where nspname = p_schema) then
    raise exception 'fn_it_full_restore_compare: % is not a scratch schema holding a restore', coalesce(p_schema, 'null');
  end if;
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and (p_only is null or c.relname = any (p_only)) order by 1 loop
    if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = p_schema and c.relname = t and c.relkind = 'r') then
      n_missing := n_missing + 1;
      v_rows := v_rows || jsonb_build_object('table', t, 'missing', true);
      continue;
    end if;
    execute format('select count(*), md5(coalesce(string_agg(h, '''' order by h), '''')) from (select md5(x::text) h from public.%I x) s', t)
      into v_live, c_live;
    execute format('select count(*), md5(coalesce(string_agg(h, '''' order by h), '''')) from (select md5(x::text) h from %I.%I x) s', p_schema, t)
      into v_rest, c_rest;
    if v_live <> v_rest or c_live <> c_rest then
      n_bad := n_bad + 1;
      v_rows := v_rows || jsonb_build_object('table', t, 'live_rows', v_live, 'restored_rows', v_rest, 'checksum_equal', c_live = c_rest);
    end if;
  end loop;
  v_ok := n_bad = 0 and n_missing = 0;
  v_out := jsonb_build_object('schema', p_schema, 'mismatched', n_bad, 'missing', n_missing, 'differences', v_rows,
                              'compare_seconds', round(extract(epoch from clock_timestamp() - v_start)::numeric, 1));
  -- A partial comparison (p_only, used by the probe) is not a full restore and is never recorded as one.
  if p_only is null then
    insert into public.it_restore_drill_result (subject, ok, detail) values ('full_database into ' || p_schema, v_ok, v_out);
  end if;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_credential_expired()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_id bigint; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean;
  k constant text := 'duty:expiry:credential:zz_game_day.expired';
begin
  begin
    t_inj := clock_timestamp();
    insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active, expires_at)
    values ('zz_game_day.expired', 'ZZ DEMO game day', 'zz-game-day-' || gen_random_uuid(), array['zz_game_day'], true, true, now() - interval '1 hour')
    returning id into v_id;
    perform public.fn_it_duties('{}'::jsonb);
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    t_fix := clock_timestamp();
    update public.internal_credential set active = false, retired_at = now() where id = v_id;   -- the fix: retired
    perform public.fn_it_duties('{}'::jsonb);
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('expiry_alert', v_det, 'cleared_after_retire', v_rec));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_db_connection()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_old numeric; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean;
  k constant text := 'duty:db_health:connections';
begin
  begin
    select value into v_old from public.it_threshold where key = 'connections_ratio_max';
    if v_old is null then raise exception 'it_threshold connections_ratio_max is not set, so the detector has nothing to compare against'; end if;
    update public.it_duty_schedule set every = interval '5 minutes' where duty = 'db_health';   -- due now, and due again
    t_inj := clock_timestamp();
    update public.it_threshold set value = 0 where key = 'connections_ratio_max';
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    t_fix := clock_timestamp();
    update public.it_threshold set value = v_old where key = 'connections_ratio_max';
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('saturation_alert', v_det, 'cleared', v_rec, 'ratio_max', v_old,
        'in_use', (select count(*) from pg_stat_activity), 'max', current_setting('max_connections')::int));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_edge_function_slow()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean;
  k constant text := 'duty:latency_slo:zz_game_day_slow';
begin
  begin
    t_inj := clock_timestamp();
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    select 'fn:zz_game_day_slow', 'ok', now() - make_interval(secs => g), now() - make_interval(secs => g),
           jsonb_build_object('ms', 9000, 'budget_ms', 1000, 'http', 200, 'method', 'POST', 'game_day', true), 'ZZ DEMO game day'
      from generate_series(1, 30) g;
    perform public.fn_it_engineer_latency_slo();
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    t_fix := clock_timestamp();
    delete from public.agent_runs where agent = 'fn:zz_game_day_slow';
    perform public.fn_it_engineer_latency_slo();
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('sli_fired', v_det, 'sli_cleared', v_rec, 'runs', 30, 'p95_ms', 9000, 'budget_ms', 1000));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_email_provider_down()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; n public.notifications; v_id bigint; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz;
  v_det boolean; v_rec boolean; v_pre boolean;
begin
  begin
    v_pre := public.fn_it_game_day_open('duty:integration:resend');
    t_inj := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('resend') || jsonb_build_array(
      jsonb_build_object('item', 'resend', 'title', 'ZZ DEMO game day: Resend answered HTTP 503', 'owner_seat', 'customer_support',
        'subject', 'resend', 'blast', 'customer_facing', 'affected', 1, 'evidence', jsonb_build_object('game_day', true, 'notify', false))));
    v_det := public.fn_it_game_day_open('duty:integration:resend');
    t_det := clock_timestamp();

    -- a notice written during the outage, then send_outbox's failure transition
    insert into public.notifications (channel, status, type, to_email, to_role, subject, body, lang, requested_by)
    values ('email', 'queued', 'zz_game_day', 'zz-game-day@example.invalid', 'customer', 'ZZ DEMO game day', 'ZZ DEMO game day', 'en', 'customer_support')
    returning id into v_id;
    update public.notifications set attempts = attempts + 1, status = 'queued', last_error = 'ZZ DEMO game day: Resend 503'
     where id = v_id;
    select * into n from public.notifications where id = v_id;

    t_fix := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('resend'));
    v_rec := not public.fn_it_game_day_open('duty:integration:resend');
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('alert_opened', v_det, 'alert_was_already_open', v_pre, 'alert_closed', v_rec,
        'notice_kept', n.id is not null, 'notice_unsent', n.sent_at is null and n.status <> 'sent',
        'attempts_counted', n.attempts = 1, 'notice_status', n.status));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean
        and (v#>>'{checks,notice_kept}')::boolean and (v#>>'{checks,notice_unsent}')::boolean and (v#>>'{checks,attempts_counted}')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_integration_items(p_except text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('item', substring(f.issue_key from length('duty:integration:') + 1),
                                               'title', f.title, 'carried', true)), '[]'::jsonb)
    from public.it_engineer_finding f
   where f.closed_at is null and f.issue_key like 'duty:integration:%'
     and f.issue_key <> 'duty:integration:' || p_except
$function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_leftovers()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select (select count(*) from public.notifications where type = 'zz_game_day' or subject = 'ZZ DEMO game day')::int
       + (select count(*) from public.agent_runs where agent = 'fn:zz_game_day_slow')::int
       + (select count(*) from public.internal_credential where context like 'zz_game_day.%')::int
       + (select count(*) from public.it_engineer_finding where title like 'ZZ DEMO game day%' or issue_key like '%zz_game_day%')::int
$function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_open(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.it_engineer_finding where issue_key = p_key and closed_at is null)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_weekly_line()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with last as (select max(run_month) m from public.it_game_day_run)
  select case when (select m from last) is null then '  No game day has run yet.'
    else format('  %s: %s of %s scenarios passed.', to_char((select m from last), 'Mon YYYY'),
                count(*) filter (where g.passed), count(*)) || E'\n' ||
         string_agg(format('  %-20s %s  detected in %s ms, recovered in %s ms%s', g.scenario,
                           case when g.passed then 'PASS' else 'FAIL' end,
                           coalesce(g.detection_ms::text, '-'), coalesce(g.recovery_ms::text, '-'),
                           case when g.error is not null then '  (' || left(g.error, 80) || ')' else '' end),
                    E'\n' order by g.scenario)
    end
    from public.it_game_day_run g where g.run_month = (select m from last)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_game_day_whatsapp_down()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_wa bigint; v_mail bigint; v_twins int; v_wa_status text; v_mail_status text; v_mail_before text;
  t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean; v_pre boolean;
  k constant text := 'duty:integration:twilio_whatsapp_sender';
begin
  begin
    -- one notice, the way producers write it: an email twin and a WhatsApp row, both to fixture identities
    insert into public.notifications (channel, status, type, to_email, to_role, subject, body, lang, requested_by)
    values ('email', 'queued', 'zz_game_day', 'zz-game-day@example.invalid', 'customer', 'ZZ DEMO game day', 'ZZ DEMO game day', 'en', 'customer_support')
    returning id into v_mail;
    insert into public.notifications (channel, status, type, to_phone, to_email, to_role, subject, body, lang, requested_by)
    values ('whatsapp', 'queued', 'zz_game_day', '+971500000099', 'zz-game-day@example.invalid', 'customer', 'ZZ DEMO game day', 'ZZ DEMO game day', 'en', 'customer_support')
    returning id into v_wa;
    select status into v_mail_before from public.notifications where id = v_mail;

    v_pre := public.fn_it_game_day_open(k);
    t_inj := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('twilio_whatsapp_sender') || jsonb_build_array(
      jsonb_build_object('item', 'twilio_whatsapp_sender', 'title', 'ZZ DEMO game day: the WhatsApp sender is OFFLINE', 'owner_seat', 'customer_support',
        'subject', 'twilio_whatsapp_sender', 'blast', 'customer_facing', 'affected', 1, 'evidence', jsonb_build_object('game_day', true, 'notify', false))));
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    -- what send_whatsapp does for each row while the finding is open; twice, as two overlapping runs would
    perform public.fn_wa_sms_twin(v_wa, 'ZZ DEMO game day sms', 'game day: WhatsApp down');
    perform public.fn_wa_sms_twin(v_wa, 'ZZ DEMO game day sms', 'game day: WhatsApp down');
    select count(*) into v_twins from public.notifications where failover_of = v_wa and channel = 'sms';
    select status into v_wa_status from public.notifications where id = v_wa;
    select status into v_mail_status from public.notifications where id = v_mail;

    t_fix := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('twilio_whatsapp_sender'));
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('alert_opened', v_det, 'alert_was_already_open', v_pre, 'alert_closed', v_rec,
        'sms_twins', v_twins, 'whatsapp_left_queue', v_wa_status not in ('queued', 'sending'), 'whatsapp_status', v_wa_status,
        'email_twin_untouched', v_mail_status is not distinct from v_mail_before, 'email_status', v_mail_status));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean
        and (v#>>'{checks,sms_twins}')::int = 1 and (v#>>'{checks,whatsapp_left_queue}')::boolean
        and (v#>>'{checks,email_twin_untouched}')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_handoff_sla_items(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with h as (
    select a.id, a.agent, a.created_at, a.detail->>'type' t, a.detail ? 'replied_at' replied,
           coalesce(k.reply_within, interval '1 hour') w,
           -- The contract's own clock: a month directive is closed by the CEO at its due_at (month end),
           -- so it is late only after that, never two days after it was sent.
           coalesce((a.detail->>'due_at')::timestamptz, a.created_at) due,
           -- A review step held by the model hold has not been answered; it waits on the hold, which is
           -- the founder's standing OpenRouter limit and is reported by the review_independence duty.
           coalesce(a.evidence#>>'{step,action}', '') = 'held' held,
           f.closed_at f_closed,
           (f.issue_key is null or f.closed_at is not null
            or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz) cleared
      from public.agent_actions a
      left join public.seat_handoff_kind k
        on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
      left join public.it_engineer_finding f
        on a.detail->>'type' = 'it.finding' and f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.status in ('pending', 'failed')
       and a.detail->>'type' <> 'delivery.request'
       and (p_include_demo or (a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true'))
  ), late as (
    select h.*, case
        when not h.replied and now() > h.created_at + h.w then 'unanswered'
        when h.replied and h.t = 'it.finding' and h.cleared
             and now() > greatest(h.created_at, coalesce(h.f_closed, h.created_at)) + h.w then 'unclosed'
        -- ponytail: other originator-closed types get a flat 24 h past their window, because
        -- fn_originators_reverify_handoffs escalates them to the CEO at the window first. Per-type
        -- rules belong in seat_handoff_kind if one of them ever needs a different allowance.
        when h.replied and h.t <> 'it.finding' and not h.held and now() > h.due + h.w + interval '24 hours' then 'unclosed'
        -- 23 Sep 2026: answered, the problem is still there, and a day has gone by.
        when h.replied and h.t = 'it.finding' and not h.cleared and now() > h.created_at + interval '24 hours' then 'open_over_24h'
      end state
      from h)
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', g.t || ':' || g.agent || ':' || g.state,
           'owner_seat', case when g.state = 'unanswered' and g.agent in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'marketing')
                              then g.agent else 'ceo' end,
           'subject', 'agent_actions',
           'title', g.n || ' ' || g.t || ' handoff(s) to ' || g.agent
                    || case g.state when 'unanswered' then ' have had no reply'
                                    when 'open_over_24h' then ' were answered more than 24 hours ago and the problem is still open'
                       else ' were answered but never closed by the seat that sent them' end
                    || case when g.state = 'open_over_24h' then '' else ' past the ' || g.w || ' window' end
                    || '; the oldest is #' || g.oldest_id || ' from '
                    || to_char(g.oldest_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
           'blast', 'agent_facing', 'affected', g.n,
           'evidence', jsonb_build_object('state', g.state, 'type', g.t, 'seat', g.agent, 'reply_within', g.w::text,
                                          'handoff_ids', g.ids, 'oldest_at', g.oldest_at,
                                          'look_at', 'select id, detail, evidence from public.agent_actions where id in (<handoff_ids>)'))
           order by g.t, g.agent, g.state), '[]'::jsonb)
    from (select t, agent, state, min(w) w, count(*) n, min(id) oldest_id, min(created_at) oldest_at,
                 jsonb_agg(id order by id) ids
            from late where state is not null group by t, agent, state) g;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_incident_open(p_handoff_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.agent_actions; v_id bigint; v_pub boolean;
begin
  select * into h from public.agent_actions where id = p_handoff_id and kind = 'handoff' and detail->>'type' = 'it.finding';
  if not found then raise exception 'fn_it_incident_open: % is not an it.finding handoff', p_handoff_id; end if;
  v_pub := coalesce((h.detail->'finding_evidence'->>'public_surface')::boolean, false)
           or h.detail->>'severity' = 'critical';
  insert into public.it_incident (handoff_id, issue_key, title, what, impact, started_at)
  values (h.id, h.detail->>'issue_key', coalesce(h.detail->>'title', h.detail->>'issue_key'),
          coalesce(h.detail->>'title', h.detail->>'issue_key') || ' (' || coalesce(h.detail->>'where_it_is', h.detail->>'subject', 'not recorded') || ').',
          case when v_pub then 'Customer-facing: something a customer or supplier opens was affected.'
               else 'Internal: an agent''s work was affected; no customer-facing surface was.' end
            || ' Severity ' || coalesce(h.detail->>'severity', 'unrecorded') || '; the ' || h.agent || ' had no remedy within its reply window.',
          (h.detail->>'occurrence_started_at')::timestamptz)
  on conflict (handoff_id) do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from public.it_incident where handoff_id = p_handoff_id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_incident_pdf_blocks(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.it_incident; p public.it_playbook;
begin
  select * into i from public.it_incident where id = p_id;
  if not found then raise exception 'no incident %', p_id; end if;
  select * into p from public.it_playbook where failure_class = i.playbook_class;
  return jsonb_build_object('title', 'Incident record ' || i.id || ': ' || left(i.title, 80), 'blocks', jsonb_build_array(
    jsonb_build_object('t', 'h2', 'text', 'Incident record ' || i.id),
    jsonb_build_object('t', 'kv', 'pairs', jsonb_build_array(
      jsonb_build_array('Reference', i.issue_key),
      jsonb_build_array('Started', to_char(i.started_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)'),
      jsonb_build_array('Ended', coalesce(to_char(i.ended_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)', 'Still open')),
      jsonb_build_array('Duration', coalesce(to_char(i.ended_at - i.started_at, 'DD "days" HH24 "h" MI "min"'), 'Still open')),
      jsonb_build_array('Recorded by', coalesce(i.recorded_by, 'Not yet recorded')))),
    jsonb_build_object('t', 'h3', 'text', 'What happened'), jsonb_build_object('t', 'p', 'text', i.what),
    jsonb_build_object('t', 'h3', 'text', 'Impact'), jsonb_build_object('t', 'p', 'text', i.impact),
    jsonb_build_object('t', 'h3', 'text', 'Cause'), jsonb_build_object('t', 'p', 'text', coalesce(i.cause, 'Not yet recorded.')),
    jsonb_build_object('t', 'h3', 'text', 'Fix'), jsonb_build_object('t', 'p', 'text', coalesce(i.fix, 'Not yet recorded.')),
    jsonb_build_object('t', 'h3', 'text', 'Regression check'),
    jsonb_build_object('t', 'p', 'text', coalesce(i.regression_check, 'Not yet recorded.')),
    jsonb_build_object('t', 'h3', 'text', 'Playbook entry'),
    jsonb_build_object('t', 'p', 'text', case
      when p.failure_class is not null then p.failure_class || ': ' || coalesce(p.remedy, p.not_automatable_reason)
      when i.not_automatable_reason is not null then 'Not automatable: ' || i.not_automatable_reason
      else 'Not yet recorded.' end)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_integration_settle(p_duty text, p_items jsonb, p_fixed jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb; f public.it_engineer_finding;
  v_stub boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_link text; v_detail text; v_dedupe text; v_note jsonb; n_mail int := 0; n_fixed int := 0;
  v_mailed jsonb := '[]'::jsonb; c public.it_integration_external_cause; m record; v_recovered text[] := '{}';
begin
  if p_duty not in ('integration', 'integration_social') then
    raise exception 'fn_it_integration_settle: duty must be integration or integration_social, not %', p_duty;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_typeof(coalesce(p_fixed, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_it_integration_settle(duty, items[], fixed[]): items and fixed must be arrays';
  end if;
  -- EVERY PROBE LEAVES A ROW (28 Sep 2026): one per integration measured this beat, passing or failing.
  insert into public.edge_health_probe (fn_key, last_beat_at, silent_minutes, verdict, note)
  select p_duty || ':' || (e->>'item'),
         case when coalesce((e->>'recovered')::boolean, false) then now() end,
         case when coalesce((e->>'recovered')::boolean, false) then 0 end,
         case when coalesce((e->>'recovered')::boolean, false) then 'ALIVE' else 'FAILING' end,
         case when coalesce((e->>'recovered')::boolean, false) then null else left(e->>'title', 500) end
    from jsonb_array_elements(p_items) e
   where not coalesce((e->>'carried')::boolean, false) and coalesce(e->>'item', '') <> '';
  -- A carried item holds an OPEN finding; one whose finding is closed is dropped, never reopened.
  -- A RECOVERED item is a successful re-probe, not a failure: it is kept out of the settle and remembered.
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce((x->>'recovered')::boolean, false) then v_recovered := v_recovered || (x->>'item'); continue; end if;
    if coalesce((x->>'carried')::boolean, false) and not exists (select 1 from public.it_engineer_finding
         where issue_key = 'duty:' || p_duty || ':' || (x->>'item') and closed_at is null) then
      continue;
    end if;
    v_items := v_items || x;
  end loop;
  v_res := public.fn_it_duty_settle(p_duty, v_items);
  -- The closed finding of an integration that answered its probe this beat says so. The evidence is replaced
  -- whenever the finding reopens, so the mark never outlives the closure it describes.
  update public.it_engineer_finding
     set evidence = evidence || jsonb_build_object('recovered', true, 'recovered_at', now())
   where closed_at is not null
     and issue_key = any (select 'duty:' || p_duty || ':' || r from unnest(v_recovered) r);

  -- What the company fixed itself: the IT daily line, never the founder.
  for x in select e from jsonb_array_elements(coalesce(p_fixed, '[]'::jsonb)) e loop
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'integration_self_fix', 'duty', p_duty, 'fix', x),
            left('fixed ' || coalesce(x->>'integration', '?') || ' itself: ' || coalesce(x->>'what_broke', ''), 500));
    n_fixed := n_fixed + 1;
  end loop;

  -- A KNOWN EXTERNAL CAUSE: follow the ticket up, and close the cause ONLY on a genuine recovery: the finding
  -- is closed AND a successful re-probe stamped it recovered. Any other closure (a sweep, a manual close) keeps
  -- the cause open, or the founder path would re-open without the provider having fixed anything.
  for c in select * from public.it_integration_external_cause where closed_at is null loop
    continue when not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:' || p_duty || ':' || c.integration);
    if exists (select 1 from public.it_engineer_finding where issue_key = 'duty:' || p_duty || ':' || c.integration
                  and closed_at is not null and closed_at >= c.created_at
                  and coalesce((evidence->>'recovered')::boolean, false)) then
      perform public.fn_it_external_cause_close(c.integration, 'the integration answers again; ' || c.external_party || ' ticket ' || c.ticket_ref || ' can be closed');
      continue;
    end if;
    -- The provider's reply, if it reached a company inbox: the newest inbound message naming the ticket.
    select i.created_at, coalesce(i.subject, '') || E'\n' || coalesce(i.body, '') txt into m
      from public.inbound_messages i
     where i.created_at > greatest(coalesce(c.last_reply_at, c.opened_on::timestamptz), c.opened_on::timestamptz)
       -- A literal substring, case-blind: a pattern match would read % and _ in a provider's reference as wildcards.
       and (strpos(lower(coalesce(i.subject, '')), lower(c.ticket_ref)) > 0
            or strpos(lower(coalesce(i.body, '')), lower(c.ticket_ref)) > 0)
     order by i.created_at desc limit 1;
    if found then perform public.fn_it_external_cause_reply(c.integration, m.created_at, m.txt); end if;
    update public.it_integration_external_cause set last_checked_at = now() where id = c.id;
  end loop;

  -- What it could not fix: the founder, once per open finding, after two beats.
  for f in select * from public.it_engineer_finding
            where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and seen_count >= 2
              and coalesce(evidence->>'notify', 'true') <> 'false' loop
    -- FOUNDER RULING 1090 (30 Sep 2026): a credential only the founder can renew (Meta, an OAuth sign-in, a
    -- console-only key) is never his reminder. The finding stays open and the IT engineer's, marked so the OS
    -- shows why nobody was told; a failure that is not a credential refusal still takes the path below.
    if public.fn_it_credential_founder_required(f.issue_key, f.title, f.evidence) then
      update public.it_engineer_finding
         set evidence = evidence || jsonb_build_object('founder_required_credential', true, 'founder_told', false,
                                                       'why_silent', 'founder ruling 1090: recorded, never rotated or reminded')
       where issue_key = f.issue_key and closed_at is null;
      continue;
    end if;
    select * into c from public.it_integration_external_cause
     where closed_at is null and 'duty:' || p_duty || ':' || integration = f.issue_key;
    if found then
      -- WAITING ON THE PROVIDER: he is told only when they replied AND the reply asks something of him, once.
      continue when not c.reply_needs_founder or c.founder_told_at is not null;
      v_dedupe := 'integration:' || f.issue_key || ':reply:' || to_char(c.last_reply_at, 'YYYYMMDDHH24MI');
      v_detail := c.external_party || ' replied on ticket ' || c.ticket_ref || ' about ' || c.integration
        || ', and the reply asks something of you.' || E'\n\n'
        || 'What broke: ' || f.title || E'\n'
        || 'Their reply (' || to_char(c.last_reply_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai): '
        || left(coalesce(c.last_reply_excerpt, ''), 900) || E'\n'
        || 'Where the thread is: ' || coalesce(c.thread_hint, 'the ticket ' || c.ticket_ref) || E'\n\n'
        || 'The IT engineer keeps re-checking every 15 minutes and closes this the moment it answers again (reference ' || f.issue_key || ').';
      if v_stub then v_note := jsonb_build_object('stubbed', true);
      else
        v_note := public.fn_notify_founder(p_event => 'IT engineer: ' || c.external_party || ' needs something from you on ' || c.integration,
          p_detail => v_detail, p_level => 'normal', p_kind => 'integration_reauth_needed', p_dedupe_key => v_dedupe,
          p_owner_agent => 'it_engineer');
      end if;
      update public.it_integration_external_cause set founder_told_at = now() where id = c.id;
      v_mailed := v_mailed || jsonb_build_object('key', f.issue_key, 'detail', v_detail, 'notice', v_note, 'external', true);
      n_mail := n_mail + 1;
      continue;
    end if;
    -- A KEY THE COMPANY ROTATED ITSELF: a permission refusal inside the rotation's overlap is the IT engineer's
    -- (probe endpoint or key scope), never a reconnect for the founder (29 Sep 2026, notification 78020).
    continue when (f.title ~* '(HTTP 40[13]|"code":\s*(20003|70004))' or coalesce(f.evidence->>'what_broke', '') ~* '(HTTP 40[13]|"code":\s*(20003|70004))')
      and exists (select 1 from public.it_credential_rotation r
                   where r.provider = regexp_replace(f.issue_key, '^duty:[a-z_]+:', '')
                     and r.status = 'overlap' and r.overlap_until > now());
    -- ONCE PER OPEN FINDING: the key is the finding and the moment it (re)opened. The finding's evidence is
    -- rewritten on every beat, so the record of having told him is founder_alerts, which fn_notify_founder writes.
    v_dedupe := 'integration:' || f.issue_key || ':' || to_char(f.started_at, 'YYYYMMDDHH24MI');
    continue when exists (select 1 from public.founder_alerts where dedupe_key = v_dedupe);
    v_link := coalesce(f.evidence->>'reconnect_url', '');
    if f.evidence->>'reconnect_link' in ('youtube', 'linkedin') and coalesce(f.evidence->>'connect_base', '') <> '' then
      v_link := (f.evidence->>'connect_base') || public.fn_marketing_social_connect_link(f.evidence->>'reconnect_link')
                || ' (one-time link, valid 24 hours)';
    end if;
    v_detail := 'The IT engineer found an integration down that the company could not fix itself.' || E'\n\n'
      || 'Integration: ' || coalesce(f.evidence->>'integration', f.evidence->>'channel', regexp_replace(f.issue_key, '^duty:[a-z_]+:', '')) || E'\n'
      || 'What broke: ' || f.title || E'\n'
      || 'What was tried: ' || coalesce((select string_agg(t, '; ') from jsonb_array_elements_text(f.evidence->'tried') t),
                                        'nothing the company can do: only the account holder can sign in again') || E'\n'
      || 'What you need to do: ' || coalesce(f.evidence->>'action', 'sign in again at the link') || E'\n'
      || 'Link: ' || coalesce(nullif(v_link, ''), 'none recorded') || E'\n\n'
      || 'Down since ' || to_char(f.started_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai. The IT engineer re-checks every 15 minutes and closes it the moment it answers again (reference ' || f.issue_key || ').';
    if v_stub then
      v_note := jsonb_build_object('stubbed', true);
    else
      -- The mail names its seat: customer_support is the only SENDER (founder, 14 Sep 2026; CHECK
      -- notifications_sender_is_customer_support), and the row's requested_by is it_engineer from
      -- founder_mail_policy.owner_role. The subject says who is asking so he reads it as the IT engineer's.
      v_note := public.fn_notify_founder(p_event => 'IT engineer: reconnect needed: ' || left(regexp_replace(f.issue_key, '^duty:[a-z_]+:', ''), 60),
        p_detail => v_detail, p_level => 'normal', p_kind => 'integration_reauth_needed', p_dedupe_key => v_dedupe,
        p_owner_agent => 'it_engineer');
    end if;
    v_mailed := v_mailed || jsonb_build_object('key', f.issue_key, 'detail', v_detail, 'notice', v_note);
    n_mail := n_mail + 1;
  end loop;
  return v_res || jsonb_build_object('fixed', n_fixed, 'founder_mailed', n_mail, 'mailed', v_mailed, 'stubbed', v_stub);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_journey_ingest(p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_items jsonb := '[]'::jsonb; x jsonb; v_owner text; v_letter text; v_res jsonb;
  -- Absent means complete: reports written before the harness had a deadline could not be truncated.
  v_complete boolean := coalesce((p_report->>'complete')::boolean, true);
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'tag'), '') = '' then
    raise exception 'fn_it_journey_ingest takes {tag, steps:[...]} from scripts/e2e/report_to_it_engineer.mjs';
  end if;
  for x in select e from jsonb_array_elements(p_report->'steps') e where e->>'status' = 'FAIL' loop
    v_letter := left(coalesce(x->>'journey', ''), 1);
    -- a/b/c/f drive the portals, the intake, the quotes and the comparison — the sales engineer's
    -- (function_owner: customer_portal, supplier_portal, inquiry_intake, quote_compare). d/e are the
    -- payment and the invoice — the accountant's (stripe_checkout, reveal_invoice). Fixtures, safety
    -- and cleanup are the harness itself, which the ceo owns.
    v_owner := case when v_letter in ('a', 'b', 'c', 'f') then 'sales_engineer'
                    when v_letter in ('d', 'e') then 'accountant' else 'ceo' end;
    v_items := v_items || jsonb_build_object(
      'item', coalesce(x->>'journey', '?') || ':' || left(regexp_replace(coalesce(x->>'name', '?'), '[^a-zA-Z0-9]+', '_', 'g'), 80),
      'owner_seat', v_owner, 'subject', 'journey ' || coalesce(x->>'journey', '?'),
      'title', 'Nightly journey failed: [' || coalesce(x->>'journey', '?') || '] ' || coalesce(x->>'name', '?'),
      'blast', 'customer_facing', 'affected', 0,
      'demo', coalesce((p_report->>'demo')::boolean, false),
      'evidence', jsonb_build_object('tag', p_report->>'tag', 'detail', left(x->>'detail', 600)));
  end loop;
  if v_complete then
    -- Looked at everything: raise what fails and close what no longer does.
    v_res := public.fn_it_duty_settle('journey', v_items);
  else
    -- Looked at part of it: raise what fails, close NOTHING. A step this run never reached says
    -- nothing about whether the defect it would have found is still there.
    for x in select e from jsonb_array_elements(v_items) e loop
      perform public.fn_it_engineer_finding_upsert(
        'duty:journey:' || (x->>'item'), x->>'title', 'IT engineer duty: journey',
        coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
        coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
          'duty', 'journey', 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
          'demo', coalesce((x->>'demo')::boolean, false), 'run_complete', false),
        '{}'::text[], '{}'::text[], 'it_engineer.journey');
    end loop;
    v_res := jsonb_build_object('duty', 'journey', 'failing', jsonb_array_length(v_items),
                                'closed', 0, 'complete', false,
                                'note', 'the run stopped before it saw every journey, so nothing was closed on its silence');
  end if;
  -- THE HEARTBEAT, WRITTEN ON EVERY PATH. duty:journey_heartbeat:no_run reads this row; a run that
  -- was cut short has still reported, and must not be counted as a missing run.
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer',
          case when jsonb_array_length(v_items) = 0 and v_complete then 'ok' else 'warn' end, now(), now(),
          jsonb_build_object('job', 'journey', 'tag', p_report->>'tag', 'failed', jsonb_array_length(v_items),
                             'steps', jsonb_array_length(p_report->'steps'), 'leftovers', p_report->'leftovers',
                             'complete', v_complete),
          case when v_complete then null
               else 'the journey run stopped at its deadline before seeing every journey; failures were raised, nothing was closed' end);
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_key_age_refresh()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e public.it_expiry; v_val text; v_upd timestamptz; v_fp text; v_seen timestamptz;
        n_new int := 0; n_missing int := 0; n_same int := 0;
begin
  for e in select * from public.it_expiry where kind = 'token' and item like 'key:%' order by item for update loop
    v_val := null; v_upd := null;
    select s.value, s.updated_at into v_val, v_upd from public.app_secrets s where s.key = substr(e.item, 5);
    if coalesce(btrim(v_val), '') = '' then
      -- No value to age: the renewal watch reports the unknown date to the accountant.
      update public.it_expiry set expires_on = null, secret_fingerprint = null, secret_seen_since = null,
             checked_at = now() where item = e.item;
      n_missing := n_missing + 1;
      continue;
    end if;
    v_fp := public.fn_internal_credential_hash(v_val);
    if e.secret_fingerprint is distinct from v_fp then
      v_seen := case when e.secret_fingerprint is null then coalesce(v_upd, now()) else now() end;
      update public.it_expiry set secret_fingerprint = v_fp, secret_seen_since = v_seen,
             expires_on = (v_seen + interval '1 year')::date, checked_at = now() where item = e.item;
      n_new := n_new + 1;
    else
      update public.it_expiry set checked_at = now() where item = e.item;
      n_same := n_same + 1;
    end if;
  end loop;
  return jsonb_build_object('changed_or_first_seen', n_new, 'unchanged', n_same, 'missing', n_missing);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_learning_from_playbook(p_handoff_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.it_playbook; v_key text; i public.it_incident;
begin
  -- A handoff id that is not an it.finding handoff is a caller's mistake, not a refusal, and is said
  -- so out loud: fn_it_loop_reverify only ever passes ids from its own filtered query, so this cannot
  -- fire from the loop. null is reserved for the two REFUSALS below -- no incident, no playbook class.
  select h.detail->>'issue_key' into v_key from public.agent_actions h
   where h.id = p_handoff_id and h.kind = 'handoff' and h.detail->>'type' = 'it.finding';
  if v_key is null then
    raise exception 'fn_it_learning_from_playbook: % is not an open it.finding handoff', p_handoff_id;
  end if;

  p := public.fn_it_playbook_for(v_key);
  if p.failure_class is null then return null; end if;

  update public.it_incident
     set cause                  = coalesce(nullif(btrim(cause), ''), p.typical_cause),
         fix                    = coalesce(nullif(btrim(fix), ''), nullif(btrim(p.remedy), ''), p.not_automatable_reason),
         regression_check       = coalesce(nullif(btrim(regression_check), ''), p.regression_check),
         playbook_class         = coalesce(playbook_class, p.failure_class),
         not_automatable_reason = coalesce(not_automatable_reason, p.not_automatable_reason),
         recorded_by            = coalesce(recorded_by, 'it_engineer (playbook: ' || p.failure_class || ')'),
         updated_at             = now()
   where handoff_id = p_handoff_id
  returning * into i;
  -- No incident row -- the handoff never became a new bug. Nothing to learn, and nothing is wrong.
  -- Tested on FOUND rather than on a separate exists() before the update: two statements with no lock
  -- between them can disagree, and the record `i` would then be all-NULL and read as "incomplete".
  if not found then return null; end if;

  -- it_playbook.regression_check is NOT NULL and a CHECK constraint makes remedy-or-reason non-empty,
  -- so a matched row always leaves a complete incident. If a later migration ever weakens that, this
  -- must NOT raise: fn_it_loop_reverify runs it inside a `for` loop with no per-row trap, so one
  -- poisoned incident would stop every OTHER handoff in the tick from closing or escalating -- and,
  -- ordered by id, would do it again on every tick after. It warns, returns null, and the handoff
  -- stays parked for a human, which is the same answer as an unknown class.
  if coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = '' then
    raise warning 'fn_it_learning_from_playbook: playbook % left incident % incomplete; leaving it parked', p.failure_class, i.id;
    return null;
  end if;
  return p.failure_class;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_loop_open(p_issue_key text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f public.it_engineer_finding; v_owner text; v_duty text; v_subject text;
begin
  select * into f from public.it_engineer_finding where issue_key = p_issue_key and closed_at is null;
  if not found then raise exception 'fn_it_loop_open: no open finding %', p_issue_key; end if;

  -- A detector finding ('watch:<detector_key>') names its subject on the detector's own row.
  v_subject := coalesce(nullif(f.evidence->>'subject', ''),
                        (select w.subject from public.it_watch_finding w where 'watch:' || w.detector_key = f.issue_key));
  v_owner := coalesce(nullif(f.evidence->>'owner_seat', ''),
                      (select o.owner from public.function_owner o where o.function_slug = v_subject));
  -- 'website' and any retired role are not seats; a finding nobody else owns is the CEO's.
  if not exists (select 1 from public.fn_seat_handoff_types() t
                  where t.type = 'it.finding' and t.from_seat = 'it_engineer' and t.to_seat = v_owner) then
    v_owner := 'ceo';
  end if;
  v_duty := coalesce(nullif(f.evidence->>'duty', ''), 'fault');

  return public.fn_seat_handoff('it_engineer', v_owner, 'it.finding', 'it_engineer_finding',
    f.issue_key || '@' || floor(extract(epoch from f.started_at))::bigint,
    jsonb_build_object(
      'issue_key', f.issue_key, 'occurrence_started_at', f.started_at, 'duty', v_duty,
      'subject', v_subject, 'title', f.title, 'where_it_is', f.where_it_is,
      'severity', public.fn_it_engineer_severity(f.blast, f.affected, f.started_at),
      'finding_evidence', f.evidence,
      'demo', f.title ilike '%ZZ DEMO%' or coalesce((f.evidence->>'demo')::boolean, false)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_loop_reverify()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h public.agent_actions; f public.it_engineer_finding; v_window interval; v_rep jsonb; v_cleared boolean;
  n_closed int := 0; n_esc int := 0; n_wait int := 0; n_playbook int := 0; v_class text; n_reports int := 0;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Review finding, 18 Sep 2026: with no such row v_window is null, `now() > created_at + null` is
  -- null, and EVERY handoff fell quietly into 'waiting' -- the loop would never escalate again and
  -- would say nothing about why. A missing conversation row is a configuration fault, not a default.
  if v_window is null then
    raise exception 'fn_it_loop_reverify: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  -- 22 Sep 2026: a handoff closed anywhere but the close branch below -- fn_it_attach_learning is the
  -- one other door -- left its CEO report 'accepted' for good. The report follows its handoff here.
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer re-verified: handoff ' || a.id || ' is closed ('
           || coalesce(a.evidence->>'verdict', 'learning recorded by ' || coalesce(a.evidence->>'learning_recorded_by', 'an unnamed recorder')) || ').'
    from public.agent_actions a
   where r.status = 'accepted' and r.idempotency_key ~ '^it_loop:[0-9]+$'
     and a.id = substr(r.idempotency_key, 9)::bigint and a.kind = 'handoff' and a.status = 'done';
  get diagnostics n_reports = row_count;

  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    -- The occurrence this loop tracked is over when the finding is closed, or when it has since
    -- closed and reopened (a later started_at is a different occurrence with its own loop).
    v_cleared := f.issue_key is null or f.closed_at is not null
                 or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;

    if v_cleared then
      -- A new bug that has cleared needs what was learned (trigger z62). Where the playbook already
      -- covers this failure class, the IT engineer records it from there and closes now; where it
      -- does not, the handoff waits for a human, which is what the gate is for.
      v_class := public.fn_it_learning_from_playbook(h.id);
      if v_class is not null then n_playbook := n_playbook + 1; end if;
    end if;

    if v_cleared and exists (select 1 from public.it_incident i where i.handoff_id = h.id
                              and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = ''
                                   or coalesce(btrim(i.regression_check), '') = ''
                                   or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''))) then
      if not (h.detail ? 'awaiting_learning') then
        update public.agent_actions set detail = detail || jsonb_build_object('awaiting_learning', now()) where id = h.id;
        update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where handoff_id = h.id and ended_at is null;
      end if;
      n_wait := n_wait + 1;
    elsif v_cleared then
      update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, now()), updated_at = now() where handoff_id = h.id;
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', coalesce(f.close_note, 'the finding is no longer open'),
        'learning_from_playbook', v_class,
        'reply_before_close', h.detail ? 'replied_at'));
      perform set_config('qd.handoff_closer', '', true);
      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: ' || coalesce(f.close_note, 'the finding is no longer open') || ' (handoff ' || h.id || ').'
       where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id') and now() > h.created_at + v_window then
      v_rep := public.fn_support_report_to_ceo(
        'it_loop:' || h.id,
        case when h.detail->>'severity' = 'critical' then 'critical' else 'serious' end,
        'Still broken after ' || h.agent || '''s reply window: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 160),
        jsonb_build_object('handoff_id', h.id, 'issue_key', h.detail->>'issue_key', 'seat', h.agent,
                           'reply', h.evidence, 'finding', to_jsonb(f)),
        jsonb_build_array(jsonb_build_object('action', 'handed to ' || h.agent, 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Decide the remedy, or record that this is a new bug for the founder. The IT engineer keeps re-checking and closes the loop only when the finding is gone.',
        p_review_in => interval '2 hours', p_source_agent => 'it_engineer');
      if not coalesce((v_rep->>'ok')::boolean, false) then
        raise exception 'fn_it_loop_reverify: the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
      end if;
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
       where id = h.id;
      perform public.fn_ceo_it_escalation_decide((v_rep->>'report_id')::bigint);
      n_esc := n_esc + 1;
    else
      n_wait := n_wait + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'escalated', n_esc, 'waiting', n_wait, 'learned_from_playbook', n_playbook,
                            'reports_completed', n_reports);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_loop_stage(p_step text, p_error text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_step), '') = '' then raise exception 'fn_it_loop_stage: a stage name is required'; end if;
  if p_error is null then
    perform public.fn_it_engineer_finding_close('monitor:it_loop:' || p_step, 'the ' || p_step || ' stage of the IT loop ran cleanly');
    return;
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'it_loop', 'stage', p_step), left(p_error, 600));
  perform public.fn_it_engineer_finding_upsert('monitor:it_loop:' || p_step,
    'The ' || p_step || ' stage of the IT engineer''s loop is failing', 'public.fn_it_loop_tick', 'monitor', 1,
    jsonb_build_object('stage', p_step, 'error', left(p_error, 600), 'owner_seat', 'ceo'),
    '{}'::text[], array['why the stage raises: ' || left(p_error, 300)], 'fn_it_loop_tick');
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_loop_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f record; o jsonb := '{}'::jsonb; n_open int := 0; v_err jsonb := '[]'::jsonb; v_step text; x jsonb;
begin
  -- ONE DEFINITION OF OPEN, CALLED, NOT COPIED (22 Sep 2026, it_engineer, UNSOLVED-11). The predicate
  -- (unclosed, and not 'warn' by fn_it_engineer_severity) now lives in fn_it_open_findings, defined in
  -- the_founder_gets_one_it_digest_per_tick.sql, which the founder's brief counts as well — the brief used
  -- to keep its own copy and said 9-10 where this loop said 8. The extra condition below is this loop's own
  -- and stays here: it is about what to RAISE on this tick, not about what is open.
  for f in select q.issue_key, q.started_at from public.fn_it_open_findings() q
            where not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.detail->>'type' = 'it.finding'
                                 and a.detail->>'issue_key' = q.issue_key
                                 and (a.detail->>'occurrence_started_at')::timestamptz = q.started_at)
            order by q.started_at loop
    begin
      continue when public.fn_it_playbook_first(f.issue_key, f.started_at);
      perform public.fn_it_loop_open(f.issue_key);
      n_open := n_open + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('step', 'open', 'issue_key', f.issue_key, 'error', sqlerrm);
    end;
  end loop;
  o := o || jsonb_build_object('opened', n_open);

  begin o := o || jsonb_build_object('reverify', public.fn_it_loop_reverify());
  exception when others then v_err := v_err || jsonb_build_object('step', 'reverify', 'error', sqlerrm); end;
  begin
    x := public.fn_originators_reverify_handoffs();
    o := o || jsonb_build_object('originators', x);
    if jsonb_array_length(coalesce(x->'errors', '[]'::jsonb)) > 0 then
      v_err := v_err || jsonb_build_object('step', 'originators', 'error', left((x->'errors')::text, 600));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'originators', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_it_reports_sweep());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;
  begin
    x := public.fn_ceo_sales_engineer_reports_sweep();
    o := o || jsonb_build_object('ceo_sales', x, 'sales_engineer_completed', public.fn_sales_engineer_reports_complete());
    if jsonb_array_length(coalesce(x->'errors', '[]'::jsonb)) > 0 then
      v_err := v_err || jsonb_build_object('step', 'ceo_sales', 'error', left((x->'errors')::text, 600));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_sales', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_accountant', public.fn_ceo_accountant_reports_sweep(),
                                     'accountant_completed', public.fn_accountant_reports_complete());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_accountant', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_silence', public.fn_it_ceo_silence_watch());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_silence', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('daily', public.fn_it_daily_line());
  exception when others then v_err := v_err || jsonb_build_object('step', 'daily', 'error', sqlerrm); end;
  -- Last, so everything this tick escalated leaves in the one message.
  begin o := o || jsonb_build_object('digest', public.fn_customer_support_sends_the_it_digest());
  exception when others then v_err := v_err || jsonb_build_object('step', 'digest', 'error', sqlerrm); end;

  foreach v_step in array array['open', 'reverify', 'originators', 'ceo', 'ceo_sales', 'ceo_accountant', 'ceo_silence', 'daily', 'digest'] loop
    perform public.fn_it_loop_stage(v_step,
      (select string_agg(coalesce(e->>'issue_key' || ': ', '') || (e->>'error'), '; ')
         from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_model_consumer_inventory()
 RETURNS TABLE(consumer text, owner_seat text, listed boolean, why_a_model text, calls_30d bigint, cost_aed_30d numeric, last_call timestamp with time zone, held_waiting bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with seen as (
    select a.fn || ':' || coalesce(a.task_class, 'unclassified') consumer, count(*) n, sum(coalesce(a.cost_aed, 0)) aed,
           max(a.occurred_at) last, max(a.seat) seat, bool_and(public.fn_it_model_consumer_listed(a.fn, a.task_class)) listed
      from public.ai_cost_log a where a.occurred_at > now() - interval '30 days' and a.fn is not null group by 1),
  held as (
    select h.surface consumer, count(*) n, max(h.seat) seat from public.reasoning_held_question h
     where h.applied_at is null and h.status is distinct from 'expired' group by 1),
  keys as (select c.consumer from public.it_model_consumer c union select consumer from seen union select consumer from held)
  select k.consumer, coalesce(c.owner_seat, s.seat, h.seat), c.consumer is not null or h.consumer is not null or coalesce(s.listed, false),
         coalesce(c.why_a_model, case when h.consumer is not null then 'a think() surface: reasoned in its seat''s queue' end),
         coalesce(s.n, 0), coalesce(s.aed, 0), s.last, coalesce(h.n, 0)
    from keys k left join public.it_model_consumer c using (consumer) left join seen s using (consumer) left join held h using (consumer)
   order by coalesce(s.n, 0) + coalesce(h.n, 0) desc, 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_model_consumer_listed(p_fn text, p_class text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.it_model_consumer c
                  where c.consumer = p_fn || ':' || coalesce(p_class, 'unclassified')
                     or (c.consumer = p_fn || ':think'
                         and p_class in ('agent_reasoning', 'knowledge_validation', 'customer_communication', 'supplier_communication',
                                 'routine_employee_reasoning', 'internal_judgement')))
$function$


CREATE OR REPLACE FUNCTION public.fn_it_open_findings()
 RETURNS SETOF it_engineer_finding
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select f.* from public.it_engineer_finding f
   where f.closed_at is null
     and public.fn_it_engineer_severity(f.blast, f.affected, f.started_at) <> 'warn'
$function$


CREATE OR REPLACE FUNCTION public.fn_it_otp_unblock(p_prefix text, p_reason text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if coalesce(p_by, '') not in ('ceo', 'founder') then
    raise exception 'fn_it_otp_unblock: only the ceo or the founder lifts a prefix block (got %)', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'fn_it_otp_unblock: a reason is required'; end if;
  if coalesce(p_prefix, '') !~ '^[0-9]{3,8}$' then raise exception 'fn_it_otp_unblock: % is not a digits-only prefix', p_prefix; end if;
  delete from public.otp_blocked_prefix where prefix = p_prefix;
  get diagnostics n = row_count;
  insert into public.otp_prefix_allowed (prefix, reason, allowed_by) values (p_prefix, p_reason, p_by)
  on conflict (prefix) do update set reason = excluded.reason, allowed_by = excluded.allowed_by, allowed_at = now();
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'otp_unblock', 'prefix', p_prefix, 'by', p_by, 'lifted', n), p_reason);
  return jsonb_build_object('ok', true, 'prefix', p_prefix, 'lifted', n, 'allowed_by', p_by);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_platform_ingest(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_items jsonb := '[]'::jsonb; v_out jsonb := '{}'::jsonb; v_pitr_decision text;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then raise exception 'fn_it_platform_ingest takes the platform readings object'; end if;
  if p_r->'backups'->>'basis' = 'measured' then
    if not coalesce((p_r->'backups'->>'pitr_enabled')::boolean, false) then
      select split_part(d.decision_key, ':', 2) into v_pitr_decision
        from public.company_policy_decision d
       where d.decision_key in ('supabase_pitr_addon:declined', 'supabase_pitr_addon:approved')
       order by d.recorded_at desc limit 1;
      if v_pitr_decision is null then
        v_items := v_items || jsonb_build_object('item', 'pitr', 'owner_seat', 'ceo', 'subject', 'database',
          'title', 'Point-in-time recovery is off: a paid Supabase add-on (from ~$100/month) awaiting the founder''s decision',
          'blast', 'agent_facing', 'affected', 1, 'config', true,
          'evidence', coalesce(p_r->'backups', '{}'::jsonb) || jsonb_build_object(
            'awaiting', 'founder decision on a paid add-on',
            'price_usd_per_month', jsonb_build_object('7_days', 100, '14_days', 200, '28_days', 400),
            'price_usd_per_hour', jsonb_build_object('7_days', 0.137, '14_days', 0.274, '28_days', 0.55),
            'requires', 'Pro plan or above and at least the Small compute add-on; not covered by the Spend Cap',
            'source', 'https://supabase.com/docs/guides/platform/backups (read 2026-09-21)',
            'decide_with', 'insert into public.company_policy_decision (decision_key, decided_on, decision_text) values (''supabase_pitr_addon:declined'' or ''supabase_pitr_addon:approved'', current_date, ''<his words>'')'));
      elsif v_pitr_decision = 'approved' then
        v_items := v_items || jsonb_build_object('item', 'pitr', 'owner_seat', 'ceo', 'subject', 'database',
          'title', 'Point-in-time recovery is still off although the founder approved the add-on',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', coalesce(p_r->'backups', '{}'::jsonb) || jsonb_build_object('decision', 'supabase_pitr_addon:approved'));
      end if;
      -- 'declined': no item. fn_it_duty_settle closes duty:db_backup:pitr as no longer found, and
      -- the decision row is where the reason lives.
    end if;
    if (p_r->'backups'->>'latest_backup_at') is null or (p_r->'backups'->>'latest_backup_at')::timestamptz < now() - interval '26 hours' then
      v_items := v_items || jsonb_build_object('item', 'daily_backup', 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'The newest database backup is ' || coalesce('from ' || (p_r->'backups'->>'latest_backup_at'), 'missing'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'backups');
    end if;
    v_out := v_out || jsonb_build_object('db_backup', public.fn_it_duty_settle('db_backup', v_items));
  end if;
  if p_r->'disk'->>'basis' = 'measured' and (p_r->'disk'->>'size_bytes') is not null then
    update public.it_threshold set value = (p_r->'disk'->>'size_bytes')::numeric,
           basis = 'management API disk size, read ' || now()::date where key = 'db_disk_limit_bytes';
  end if;
  if p_r->'members'->>'basis' = 'measured' then
    v_out := v_out || jsonb_build_object('supabase_access',
      public.fn_it_duty_settle('supabase_access', public.fn_it_access_items(jsonb_build_object('supabase', p_r->'members'))));
  end if;
  perform public.fn_it_duty_ran('platform', v_out);
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_playbook_first(p_issue_key text, p_started_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.it_playbook;
begin
  select * into p from public.it_playbook
   where p_issue_key like issue_prefix || '%' and remedy_routine is not null
   order by length(issue_prefix) desc limit 1;
  if not found then return false; end if;
  if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'playbook'
              and counts->>'issue_key' = p_issue_key and started_at >= p_started_at) then
    return false;                              -- already tried for this occurrence: hand it on
  end if;
  if to_regprocedure('public.' || p.remedy_routine || '()') is null then
    raise exception 'playbook % names % but no such routine exists', p.failure_class, p.remedy_routine;
  end if;
  execute format('select public.%I()', p.remedy_routine);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(),
          jsonb_build_object('job', 'playbook', 'issue_key', p_issue_key, 'failure_class', p.failure_class), p.remedy);
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_playbook_for(p_issue_key text)
 RETURNS it_playbook
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select p.* from (
    select b.* from public.it_playbook b
     where left(p_issue_key, length(b.issue_prefix)) = b.issue_prefix
     order by length(b.issue_prefix) desc, b.failure_class limit 1) p
   where coalesce(btrim(p.typical_cause), '') <> '';
$function$


CREATE OR REPLACE FUNCTION public.fn_it_postmaster_record(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dom   text := coalesce(nullif(btrim(p_r->>'domain'), ''), 'quotesdone.com');
  v_basis text := p_r->>'basis';
  v_on    date := (now() at time zone 'Asia/Dubai')::date;
  v_stats date := nullif(p_r->>'stats_day', '')::date;
  v_items jsonb := '[]'::jsonb;
  v_pause jsonb := null;
  v_res   jsonb;
  f record;
begin
  if v_basis is null or v_basis not in ('measured', 'no_data', 'unavailable') or coalesce(btrim(p_r->>'line'), '') = '' then
    raise exception 'fn_it_postmaster_record: a reading needs basis measured|no_data|unavailable and a line (%)', left(p_r::text, 200);
  end if;

  insert into public.it_postmaster_reading as t (domain, read_on, basis, stats_day, spam_ratio, spam_lower, spam_upper, reputation,
                                                spf_ratio, dkim_ratio, dmarc_ratio, reason, verdict, line)
  values (v_dom, v_on, v_basis, v_stats, (p_r->>'spam_ratio')::numeric, (p_r->>'spam_lower')::numeric, (p_r->>'spam_upper')::numeric,
          p_r->>'reputation', (p_r->>'spf')::numeric, (p_r->>'dkim')::numeric, (p_r->>'dmarc')::numeric,
          p_r->>'reason', coalesce(p_r->'verdict', '{}'::jsonb), p_r->>'line')
  on conflict (domain, read_on) do update
     set basis = excluded.basis, stats_day = excluded.stats_day, spam_ratio = excluded.spam_ratio, spam_lower = excluded.spam_lower,
         spam_upper = excluded.spam_upper, reputation = excluded.reputation, spf_ratio = excluded.spf_ratio,
         dkim_ratio = excluded.dkim_ratio, dmarc_ratio = excluded.dmarc_ratio, reason = excluded.reason,
         verdict = excluded.verdict, line = excluded.line, read_at = now(),
         -- paused_at belongs to the stats day that paused; a rerun that returns a different day does not inherit it.
         paused_at = case when t.stats_day is not distinct from excluded.stats_day then t.paused_at end;

  if v_basis = 'measured' and coalesce((p_r->'verdict'->>'finding')::boolean, false) then
    v_items := v_items || jsonb_build_object('item', 'deliverability:' || v_dom, 'owner_seat', 'it_engineer', 'subject', v_dom,
      'blast', 'customer_facing',
      'title', 'Gmail Postmaster ' || v_dom || ' ' || v_stats || ': '
               || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(p_r->'verdict'->'reasons') x), 'over threshold'),
      'evidence', p_r - 'line');
  elsif v_basis <> 'measured' then
    -- Postmaster silent or unreadable: an open deliverability finding is held as it stands, not closed.
    for f in select issue_key, title from public.it_engineer_finding
              where closed_at is null and issue_key = 'duty:postmaster:deliverability:' || v_dom loop
      v_items := v_items || jsonb_build_object('item', 'deliverability:' || v_dom, 'title', f.title, 'carried', true,
                                               'owner_seat', 'it_engineer', 'subject', v_dom);
    end loop;
  end if;
  if v_basis = 'unavailable' then
    v_items := v_items || jsonb_build_object('item', 'unreadable:' || v_dom, 'config', true, 'owner_seat', 'it_engineer',
      'blast', 'monitor', 'subject', v_dom,
      'title', 'Gmail Postmaster could not be read for ' || v_dom || ': ' || coalesce(p_r->>'reason', '?'), 'evidence', p_r - 'line');
  end if;

  -- The pause: only a RUNNING campaign (invite_enabled = 'true'; stopping a stopped one would only write an error
  -- run and rewrite the #943 finding), and once per Postmaster day -- a stats day that already paused the
  -- invitations never pauses them again, so a hand resume is not overridden by the same stale day. A NEW
  -- Postmaster day still over the line pauses again, deliberately: a trailing LOW/BAD reputation repeats on every
  -- day it lasts, and each day must keep the campaign stopped even over a manual resume. The finding above is
  -- filed either way; paused_at is set only when a pause actually happened.
  if v_basis = 'measured' and coalesce((p_r->'verdict'->>'pause')::boolean, false) and v_stats is not null
     and coalesce((select value from public.app_secrets where key = 'invite_enabled'), 'false') = 'true'
     and not exists (select 1 from public.it_postmaster_reading
                      where domain = v_dom and stats_day = v_stats and paused_at is not null) then
    v_pause := public.fn_invite_campaign_pause('it_engineer_postmaster',
      coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(p_r->'verdict'->'reasons') x), 'Gmail Postmaster over threshold')
        || ' (Postmaster day ' || v_stats || ')',
      jsonb_build_object('source', 'gmail_postmaster', 'domain', v_dom, 'stats_day', v_stats, 'spam_ratio', p_r->'spam_ratio',
                         'spam_lower', p_r->'spam_lower', 'spam_upper', p_r->'spam_upper', 'reputation', p_r->'reputation'),
      jsonb_build_object('stats_day', v_stats, 'spam_ratio', p_r->'spam_ratio', 'reputation', p_r->'reputation'));
    update public.it_postmaster_reading set paused_at = now() where domain = v_dom and read_on = v_on;
  end if;

  v_res := public.fn_it_duty_settle('postmaster', v_items) || jsonb_build_object('basis', v_basis, 'paused', v_pause is not null);
  perform public.fn_it_duty_ran('postmaster', v_res);
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_rotation_baseline(p_provider text, p_ref text, p_created_at timestamp with time zone)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k text[] := public.fn_it_provider_rotation_keys(p_provider); v_id bigint;
begin
  if k is null then raise exception 'no rotation is defined for provider %', p_provider; end if;
  if coalesce(p_ref, '') = '' or p_created_at is null or p_created_at > now() then
    raise exception 'a baseline needs the current key id and a creation date that is not in the future';
  end if;
  perform pg_advisory_xact_lock(hashtext('it_provider_rotation:' || p_provider));
  if exists (select 1 from public.it_credential_rotation where provider = p_provider) then return null; end if;
  insert into public.it_credential_rotation (context, provider, old_ref, new_ref, secret_key, rotated_at, overlap_until, status, closed_at, note)
  values (p_provider || '.api_key', p_provider, null, p_ref, array_to_string(k, ','), p_created_at, p_created_at, 'baseline', now(),
          'baseline: the key in use before the estate rotated anything, created at the provider '
            || to_char(p_created_at at time zone 'UTC', 'YYYY-MM-DD') || '; the rotation schedule counts from this date')
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_rotation_claim(p_provider text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_last timestamptz; v_days int;
begin
  if public.fn_it_provider_rotation_keys(p_provider) is null then
    return jsonb_build_object('due', false, 'reason', 'no rotation is defined for provider ' || coalesce(p_provider, 'null'));
  end if;
  perform pg_advisory_xact_lock(hashtext('it_provider_rotation:' || p_provider));
  if not exists (select 1 from public.it_credential_rotation where provider = p_provider) then
    return jsonb_build_object('due', false, 'baseline_needed', true,
      'reason', 'no baseline yet: the current key''s creation date is recorded first, and the schedule counts from it');
  end if;
  if exists (select 1 from public.it_credential_rotation where provider = p_provider and status in ('overlap', 'held')) then
    return jsonb_build_object('due', false, 'reason', 'a rotation of ' || p_provider || ' is still in its overlap');
  end if;
  v_days := coalesce(public.fn_it_threshold('credential_rotate_days'), 90)::int;
  select max(rotated_at) into v_last from public.it_credential_rotation where provider = p_provider;
  if v_last is not null and v_last > now() - make_interval(days => v_days) then
    return jsonb_build_object('due', false, 'reason', 'rotated ' || to_char(v_last, 'YYYY-MM-DD') || ', next after ' || v_days || ' days');
  end if;
  -- A claim in the last 20 hours that recorded nothing is a failed attempt: the next day retries, not the next tick.
  if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'provider_rotation_claim'
               and counts->>'provider' = p_provider and started_at > now() - interval '20 hours') then
    return jsonb_build_object('due', false, 'reason', 'claimed within the last 20 hours');
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'provider_rotation_claim', 'provider', p_provider), null);
  return jsonb_build_object('due', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_rotation_keys(p_provider text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case p_provider when 'twilio' then array['twilio_api_key_sid', 'twilio_api_key_secret'] end;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_rotation_record(p_provider text, p_old_ref text, p_new_ref text, p_new_secret text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k text[] := public.fn_it_provider_rotation_keys(p_provider); v_id bigint; v_overlap interval; v_cadence interval;
begin
  if k is null then raise exception 'no rotation is defined for provider %', p_provider; end if;
  if coalesce(p_new_ref, '') = '' or coalesce(p_new_secret, '') = '' then raise exception 'a rotation needs the new key id and its secret'; end if;
  -- Never under 24 hours, whatever the threshold says: the old key must outlive every cache of it by a day.
  v_overlap := greatest(make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int), interval '24 hours');
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  insert into public.app_secrets (key, value, updated_at) values (k[1], p_new_ref, now()), (k[2], p_new_secret, now())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
  insert into public.it_credential_rotation (context, provider, old_ref, new_ref, secret_key, overlap_until, status, note)
  values (p_provider || '.api_key', p_provider, p_old_ref, p_new_ref, array_to_string(k, ','), now() + v_overlap + 2 * v_cadence,
          case when p_old_ref is null then 'retired' else 'overlap' end,
          'rotated by the provider API; the new key authenticated before it was stored')
  returning id into v_id;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(),
          jsonb_build_object('job', 'duty:rotation:provider', 'provider', p_provider, 'rotation_id', v_id, 'old_ref', p_old_ref, 'new_ref', p_new_ref), null);
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_rotation_retire_due(p_provider text)
 RETURNS TABLE(id bigint, old_ref text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.id, r.old_ref from public.it_credential_rotation r
   where r.provider = p_provider and r.status in ('overlap', 'held') and r.overlap_until <= now() and r.old_ref is not null
   order by r.id;
$function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_rotation_retired(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  update public.it_credential_rotation set status = 'retired', closed_at = now(), note = left(p_note, 500)
   where id = p_id and provider is not null and status in ('overlap', 'held');
$function$


CREATE OR REPLACE FUNCTION public.fn_it_provider_watch(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; v_items jsonb := '[]'::jsonb; fw jsonb := coalesce(p_r->'firewall', '{}'::jsonb); v_res jsonb;
begin
  for x in select e from jsonb_array_elements(coalesce(p_r->'providers', '[]'::jsonb)) e loop
    if x->>'basis' = 'unavailable' then
      v_items := v_items || jsonb_build_object('item', 'unreadable:' || (x->>'provider'), 'config', true, 'owner_seat', 'it_engineer',
        'title', 'The ' || (x->>'provider') || ' status page could not be read: ' || coalesce(x->>'reason', '?'), 'blast', 'monitor',
        'subject', x->>'provider', 'evidence', x);
    elsif x->>'indicator' in ('major', 'critical') then
      v_items := v_items || jsonb_build_object('item', x->>'provider', 'owner_seat', 'it_engineer', 'subject', x->>'provider',
        'title', initcap(x->>'provider') || ' reports a ' || (x->>'indicator') || ' incident on its status page: ' || coalesce(x->>'description', ''),
        'blast', case when x->>'provider' = 'dropbox' then 'internal' else 'customer_facing' end, 'evidence', x);
    end if;
  end loop;

  if fw->>'basis' = 'unavailable' or fw->'config'->>'basis' = 'unavailable' then
    v_items := v_items || jsonb_build_object('item', 'firewall:unreadable', 'config', true, 'owner_seat', 'it_engineer', 'blast', 'monitor',
      'title', 'The Vercel firewall could not be read: ' || coalesce(fw->>'reason', fw->'config'->>'reason', '?'), 'evidence', fw);
  elsif (fw->'config'->>'enabled')::boolean is false then
    v_items := v_items || jsonb_build_object('item', 'firewall:off', 'owner_seat', 'it_engineer', 'blast', 'security',
      'title', 'The Vercel firewall is switched off for the site', 'evidence', fw);
  end if;
  if fw->'attack'->>'basis' = 'measured' and (fw->'attack'->>'under_attack')::boolean then
    v_items := v_items || jsonb_build_object('item', 'firewall:attack', 'owner_seat', 'it_engineer', 'blast', 'security',
      'title', 'Vercel reports an active attack on the site', 'evidence', fw);
  end if;

  v_res := public.fn_it_duty_settle('provider_status', v_items);
  perform public.fn_it_duty_ran('provider_status', v_res);
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_refusal_is_policy(p_subject text, p_counts jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1 from public.it_refusal_policy p
     where p.subject = regexp_replace(coalesce(p_subject,''), '^fn:', '')
       and coalesce(p_counts, '{}'::jsonb) ? p.reason_key)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_renewal_recorded(p_item text, p_expires_on date, p_by text, p_evidence text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e public.it_expiry;
begin
  if p_by is null or p_by not in ('accountant', 'ceo', 'founder') then
    raise exception 'a renewal is recorded by the accountant, the ceo or the founder, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_evidence), '') = '' then
    raise exception 'say what proves the renewal (the certificate number, the receipt, the registrar page)';
  end if;
  select * into e from public.it_expiry where item = p_item;
  if not found then raise exception 'no renewal item % in public.it_expiry', p_item; end if;
  if p_expires_on is null or p_expires_on <= coalesce(e.expires_on, current_date) then
    raise exception 'the new expiry (%) must be later than the one on record (%)', p_expires_on, coalesce(e.expires_on::text, 'today');
  end if;
  update public.it_expiry
     set expires_on = p_expires_on, checked_at = now(),
         source = left('renewed, recorded by ' || p_by || ' on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ': ' || p_evidence, 500)
   where item = p_item;
  return jsonb_build_object('item', p_item, 'was', e.expires_on, 'now', p_expires_on, 'by', p_by,
                            'watch', public.fn_it_renewal_watch());
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_renewal_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h public.agent_actions; e public.it_expiry; v_window interval; v_rep jsonb; v_items jsonb := '[]'::jsonb;
  v_days int; v_stage int; n_closed int := 0; n_esc int := 0; v_key text;
begin
  select reply_within into v_window from public.seat_handoff_kind
   where type = 'renewal.due' and from_seat = 'it_engineer' and to_seat = 'accountant';
  -- The row is the accountant's build's; without it `created_at + NULL` would never escalate anything.
  v_window := coalesce(v_window, interval '3 days');

  -- 1. RE-VERIFY: a handoff closes when the date it was about has moved (the item was renewed).
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'renewal.due' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    e := null;
    select * into e from public.it_expiry where item = h.detail->>'item';
    v_key := 'renewal:' || (h.detail->>'item') || '@' || (h.detail->>'expires_on');
    -- FOUNDER RULING 1090: a reminder already out about a credential only the founder can renew is withdrawn.
    if public.fn_it_credential_founder_required('duty:renewal:' || (h.detail->>'item')) then
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', 'withdrawn: founder ruling 1090 - a credential only the founder can renew is never rotated or reminded'));
      perform set_config('qd.handoff_closer', '', true);
      begin
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'Withdrawn by founder ruling 1090: ' || (h.detail->>'item') || ' is a founder-required credential (handoff ' || h.id || ').'
         where idempotency_key = v_key and status in ('sent', 'accepted');
      exception when others then null;
      end;
      n_closed := n_closed + 1;
      continue;
    end if;
    if e.item is null or e.expires_on is distinct from (h.detail->>'expires_on')::date then
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', case when e.item is null then 'the item is no longer watched'
                        else 'renewed: expiry moved from ' || (h.detail->>'expires_on') || ' to ' || coalesce(e.expires_on::text, 'unknown') end));
      perform set_config('qd.handoff_closer', '', true);
      -- A ceo report about this date is finished by the renewal, answered or not.
      begin
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer re-verified: ' || (h.detail->>'item') || ' now expires ' || coalesce(e.expires_on::text, 'unknown') || ' (handoff ' || h.id || ').'
         where idempotency_key = v_key and status in ('sent', 'accepted');
      exception when others then null;  -- the handoff is closed either way; the report stays for the ceo
      end;
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id')
          and (h.detail->>'stage')::int = (select min(w) from unnest(e.warn_days) w)
          and now() > h.created_at + v_window then
      -- 2. ESCALATE: the last warning's window has passed and the date has not moved.
      v_rep := public.fn_support_report_to_ceo(
        v_key, 'serious',
        'Renewal not closed: ' || e.item || ' expires ' || e.expires_on || ' (' || (e.expires_on - current_date) || ' days)',
        jsonb_build_object('item', e.item, 'kind', e.kind, 'expires_on', e.expires_on, 'route', e.route, 'source', e.source,
                           'handoff_id', h.id, 'accountant_reply', h.evidence),
        jsonb_build_array(jsonb_build_object('action', 'accountant warned at ' || (h.detail->>'stage') || ' days', 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Renew it or direct who does. The IT engineer closes this only when it reads the new expiry date back.',
        p_review_in => interval '2 days', p_source_agent => 'it_engineer');
      if coalesce((v_rep->>'ok')::boolean, false) then
        update public.agent_actions
           set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_esc := n_esc + 1;
      else
        raise exception 'fn_it_renewal_watch: the ceo report for % was refused: %', e.item, v_rep->>'reason';
      end if;
    end if;
  end loop;

  -- 3. WARN: every item inside a stage gets its handoff; the ledger records what is due.
  -- A never_expires item is settled, not overdue: there is no renewal to arrange and no date to chase.
  for e in select * from public.it_expiry where kind <> 'tls' and not never_expires order by item loop
    -- FOUNDER RULING 1090: a credential only the founder can renew gets no handoff, no report, no reminder.
    -- Inside a warning stage, past its date or undated, it is one silent IT engineer finding, so the OS shows it.
    if public.fn_it_credential_founder_required('duty:renewal:' || e.item) then
      v_days := e.expires_on - current_date;
      select min(w) into v_stage from unnest(e.warn_days) w where v_days <= w;
      if e.expires_on is null or v_stage is not null then
        v_items := v_items || jsonb_build_object('item', e.item || case when e.expires_on is null then ':date_unknown' else '' end,
          'owner_seat', 'it_engineer', 'subject', e.item, 'blast', 'internal', 'affected', 0,
          'title', e.item || ' (founder-required credential) ' || case when e.expires_on is null then 'has no known date'
                   when v_days < 0 then 'passed its date ' || e.expires_on else 'is dated ' || e.expires_on || ' (' || v_days || ' days)' end
                   || ': recorded only, never rotated or reminded (founder ruling 1090)',
          'evidence', jsonb_build_object('founder_required_credential', true, 'founder_told', false, 'expires_on', e.expires_on));
      end if;
      continue;
    end if;
    if e.expires_on is null then
      v_items := v_items || jsonb_build_object('item', e.item || ':date_unknown', 'owner_seat', 'accountant', 'subject', e.item,
        'title', 'The renewal date of ' || e.item || ' is not known (' || e.source || ')',
        'blast', 'internal', 'affected', 0, 'config', true,
        'evidence', jsonb_build_object('route', e.route, 'source', e.source));
      continue;
    end if;
    v_days := e.expires_on - current_date;
    select min(w) into v_stage from unnest(e.warn_days) w where v_days <= w;
    continue when v_stage is null;
    v_items := v_items || jsonb_build_object('item', e.item, 'owner_seat', 'accountant', 'subject', e.item,
      'title', e.item || case when v_days < 0 then ' EXPIRED on ' || e.expires_on
                              else ' expires on ' || e.expires_on || ' (' || v_days || ' days): inside the ' || v_stage || '-day warning' end,
      -- quiet in the ledger while it is being renewed; an item past its date goes round the IT loop as well
      'blast', case when v_days < 0 then 'agent_facing' else 'internal' end, 'affected', case when v_days < 0 then 1 else 0 end,
      'evidence', jsonb_build_object('stage', v_stage, 'days_left', v_days, 'route', e.route, 'source', e.source));
    perform public.fn_seat_handoff('it_engineer', 'accountant', 'renewal.due', 'it_expiry',
      e.item || '@' || e.expires_on || '@' || v_stage,
      jsonb_build_object('item', e.item, 'kind', e.kind, 'expires_on', e.expires_on, 'days_left', v_days,
                         'stage', v_stage, 'route', e.route));
  end loop;
  return jsonb_build_object('renewal', public.fn_it_duty_settle('renewal', v_items), 'closed', n_closed, 'escalated', n_esc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_restore_table_due()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET lock_timeout TO '250ms'
AS $function$
begin
  return ('restore_table' = any (public.fn_it_scheduled_due())
          -- no passing drill yet this calendar month: run, and retry at most once every 20 hours until one passes
          or (not exists (select 1 from public.it_restore_drill_result d
                           where d.ok and coalesce((d.detail->>'restored')::int, 0) > 0
                             and d.ran_at >= date_trunc('month', now()))
              and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                               and started_at > now() - interval '20 hours'))
          or (exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key like 'duty:restore\_table:%')
              and (not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                                and started_at > now() - interval '20 hours')
                   -- a finished export newer than the one the last drill read: re-check at once, so a
                   -- stale-export finding closes the tick after the export lands, inside the loop's window
                   or exists (select 1 from public.table_export_run r
                               where r.status = 'done' and r.stamp::text > coalesce(
                                 (select d.detail->>'newest_export_day' from public.it_restore_drill_result d order by d.id desc limit 1), '')))))
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick'
                      and started_at > now() - interval '6 hours');
exception when lock_not_available then
  -- In the postgres log, which the db_health duty reads: a skipped tick is never silent.
  raise warning 'fn_it_restore_table_due: a lock held elsewhere outlived lock_timeout 250ms; not due this tick (55P03)';
  return false;   -- another transaction holds a lock on something this reads: not due this tick
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_restore_table_overdue()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET lock_timeout TO '250ms'
AS $function$
declare v_last timestamptz; v_window interval := interval '33 days';
begin
  select max(started_at) into v_last from public.agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table' and started_at > now() - v_window;
  if v_last is not null then
    perform public.fn_it_engineer_finding_close('duty:restore_table:overdue',
      'a restore drill completed at ' || to_char(v_last at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai');
    return jsonb_build_object('overdue', false, 'last_drill', v_last);
  end if;
  -- Limit: this gate keys off ANY scheduled duty's age, not this drill's own start; a duty added long after the others needs its own start date.
  if not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' like 'duty:%'
                  and started_at < now() - v_window) then
    return jsonb_build_object('overdue', false, 'reason', 'the scheduled duties are younger than the window');
  end if;
  perform public.fn_it_engineer_finding_upsert('duty:restore_table:overdue',
    'No monthly restore drill has completed in ' || extract(day from v_window) || ' days',
    'resilience_ping -> fn_it_restore_table_due / _pick / _record', 'monitor', 1,
    jsonb_build_object('duty', 'restore_table', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'last_drill', (select max(started_at) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'),
      'look_at', 'the postgres log for "fn_it_restore_table_due: a lock held elsewhere", and resilience_ping''s restore_table step'),
    '{}'::text[], array['whether the due-check is being skipped by locks or the drill itself is failing'], 'it_engineer.restore_table');
  return jsonb_build_object('overdue', true);
exception when lock_not_available then
  raise warning 'fn_it_restore_table_overdue: a lock held elsewhere outlived lock_timeout 250ms; checked again next tick (55P03)';
  return jsonb_build_object('overdue', null, 'reason', 'lock timeout');
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_restore_table_pick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_newest text; v_manifest jsonb; v_tab text; v_prev timestamptz;
  v_full date; v_chain_tab text; v_chain jsonb;
begin
  select max(started_at) into v_prev from public.agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick';
  if v_prev is not null and v_prev < now() - interval '1 hour'
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                      and started_at >= v_prev) then
    perform public.fn_it_engineer_finding_upsert('duty:restore_heartbeat:unrecorded',
      'The table restore drill started at ' || to_char(v_prev at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai and never recorded a result',
      'resilience_ping -> _shared/it_restore_drill.ts', 'monitor', 1,
      jsonb_build_object('duty', 'restore_heartbeat', 'owner_seat', 'ceo', 'subject', 'resilience_ping', 'picked_at', v_prev),
      '{}'::text[], array['why the edge tick stopped between the pick and the record: read resilience_ping''s logs'], 'it_engineer.restore_table');
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'restore_table_pick'), null);

  select r.stamp::text, r.manifest into v_newest, v_manifest
    from public.table_export_run r where r.status = 'done' and r.manifest is not null
   order by r.stamp desc limit 1;
  if v_newest is null then            -- before #664's first finished day: the pre-7-Sep layout
    select max(split_part(o.name, '/', 1)) into v_newest
      from storage.objects o where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/';
  end if;

  -- ── the incremental chain, when there is one ──
  select max(r.stamp) into v_full from public.table_export_run r where r.kind = 'full' and r.status = 'done';
  if v_full is not null then
    select x.table_name into v_chain_tab
      from public.table_export_change_tracked x
      join storage.objects o on o.bucket_id = 'backups'
                           and o.name = to_char(v_full, 'YYYY-MM-DD') || '/' || x.table_name || '/page_0000.json'
     order by random() limit 1;
  end if;
  if v_chain_tab is not null then
    select jsonb_build_object(
      'table', v_chain_tab,
      'full_day', to_char(v_full, 'YYYY-MM-DD'),
      'base', to_char(v_full, 'YYYY-MM-DD') || '/' || v_chain_tab || '/page_0000.json',
      'increments', coalesce((select jsonb_agg(o.name order by o.name)
                                from public.table_export_run r
                                join storage.objects o on o.bucket_id = 'backups'
                                 and o.name like r.stamp::text || '/' || v_chain_tab || '/page\_%.json'
                               where r.status = 'done' and r.stamp > v_full), '[]'::jsonb),
      'changes', coalesce((select jsonb_agg(o.name order by o.name)
                             from public.table_export_run r
                             join storage.objects o on o.bucket_id = 'backups'
                              and o.name like r.stamp::text || '/table_export_change/page\_%.json'
                            where r.status = 'done' and r.stamp > v_full), '[]'::jsonb))
      into v_chain;
  end if;

  select t.table_name into v_tab
    from public.it_restore_drill_table t
    join storage.objects o on o.bucket_id = 'backups' and o.name = v_newest || '/' || t.table_name || '/page_0000.json'
    left join pg_class pc on pc.oid = to_regclass('public.' || t.table_name)
   where v_manifest is null
      or (v_manifest->'tables' ? t.table_name
          and coalesce(v_manifest->'tables'->t.table_name->>'mode', 'full') not like 'changes_since%')
   -- 23 Sep 2026: a page the export says has rows first; reltuples counts demo rows the export excludes.
   order by coalesce((v_manifest->'tables'->t.table_name->>'rows') ~ '^[1-9][0-9]*$', false) desc,
            (coalesce(pc.reltuples, 0) > 0) desc, random() limit 1;
  return jsonb_build_object('newest_export_day', v_newest,
    'sample_rows', coalesce(public.fn_it_threshold('restore_table_sample_rows'), 50),
    'chain', v_chain,
    'table', case when v_tab is not null
                  then jsonb_build_object('table', v_tab, 'path', v_newest || '/' || v_tab || '/page_0000.json', 'day', v_newest) end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_restore_table_record(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t jsonb := p->'table'; v_items jsonb := '[]'::jsonb; v_key text; v_tab text := p->'table'->>'table';
  n_rest int := 0; n_match int := 0; n_changed int := 0; n_missing int := 0; v_err text; v_age int; v_max int;
  v_ok boolean; v_detail jsonb; v_out jsonb; v_drop text[]; v_full date; v_last date; v_gaps text; v_live_empty boolean;
  c jsonb := p->'chain'; v_rebuild jsonb; v_rebuild_ok boolean := true;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'fn_it_restore_table_record takes the drill reading from _shared/it_restore_drill.ts';
  end if;

  -- ── THE AGE OF THE NEWEST FINISHED EXPORT ──
  v_max := coalesce(public.fn_it_threshold('restore_export_max_age_days'), 2)::int;
  v_age := current_date - (p->>'newest_export_day')::date;
  if v_age is null or v_age > v_max then
    v_items := v_items || jsonb_build_object('item', 'export_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', case when v_age is null then 'There is no finished table export in the backups bucket at all'
                    else 'The newest finished table backup is from ' || (p->>'newest_export_day') || ' (' || v_age || ' days old)' end,
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('newest_export_day', p->>'newest_export_day', 'age_days', v_age, 'max_age_days', v_max,
        'writer', 'supabase/functions/backup, claimed by resilience_ping through fn_table_export_due'));
  end if;

  -- ── THE CHAIN: the latest full day plus every day after it ──
  if exists (select 1 from public.table_export_run) then
    select max(stamp) into v_full from public.table_export_run where kind = 'full' and status = 'done';
    select max(stamp) into v_last from public.table_export_run where status = 'done';
    if v_full is null or v_full < current_date - 7 then
      v_items := v_items || jsonb_build_object('item', 'full_copy_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'the change-tracked tables have no finished full copy in the last 7 days' || coalesce(' (the last is ' || v_full || ')', ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('last_full_day', v_full));
    else
      select string_agg(d::date::text, ', ' order by d) into v_gaps
        from generate_series(v_full, v_last, interval '1 day') d
       where not exists (select 1 from public.table_export_run r where r.stamp = d::date and r.status = 'done');
      if v_gaps is not null then
        v_items := v_items || jsonb_build_object('item', 'chain_broken', 'owner_seat', 'ceo', 'subject', 'table_backup',
          'title', 'a change-tracked table restores only from the full copy of ' || v_full || ' plus every later day, and ' || v_gaps || ' did not finish',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('last_full_day', v_full, 'last_done_day', v_last, 'missing_or_failed', v_gaps));
      end if;
    end if;
  end if;

  -- ── THE REBUILD FROM BASE + INCREMENTS + DELETES ──
  if c is not null and jsonb_typeof(c) = 'object' then
    if c->>'error' is not null then
      v_rebuild := jsonb_build_object('table', c->>'table', 'error', c->>'error');
      v_rebuild_ok := false;
    else
      begin
        v_rebuild := public.fn_table_export_replay(c->>'table', coalesce(c->'base_rows', '[]'::jsonb),
                                                   coalesce(c->'increment_rows', '[]'::jsonb),
                                                   coalesce(c->'change_rows', '[]'::jsonb));
      exception when others then
        v_rebuild := jsonb_build_object('table', c->>'table', 'error', 'the rebuild failed: ' || sqlerrm);
      end;
      v_rebuild_ok := coalesce((v_rebuild->>'rebuilt')::int, 0) > 0
                  and coalesce((v_rebuild->>'lost_rows')::int, 1) = 0
                  and v_rebuild->>'error' is null;
    end if;
    v_rebuild := v_rebuild || jsonb_build_object('full_day', c->>'full_day', 'base', c->>'base',
                                                 'increment_files', c->'increments', 'change_files', c->'changes');
    if not v_rebuild_ok then
      v_items := v_items || jsonb_build_object('item', 'rebuild', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'The restore drill could not rebuild ' || coalesce(c->>'table', 'a change-tracked table')
                 || ' from its full copy of ' || coalesce(c->>'full_day', '?') || ' plus the later days'
                 || coalesce(': ' || (v_rebuild->>'error'),
                      ' (' || coalesce(v_rebuild->>'lost_rows', '?') || ' live row(s) in the rebuilt key window are in no backup file)'),
        'blast', 'agent_facing', 'affected', 1, 'evidence', v_rebuild);
    end if;
  end if;

  -- ── THE SINGLE FULL PAGE RESTORED INTO SCRATCH ──
  select key_column into v_key from public.it_restore_drill_table where table_name = v_tab;
  if t is null or v_tab is null then
    v_err := 'no full-copy page_0000.json of any table in it_restore_drill_table in the newest finished export';
  elsif v_key is null then
    v_err := v_tab || ' is not in it_restore_drill_table';
  elsif t->>'error' is not null then
    v_err := t->>'error';
  else
    select coalesce(array_agg(c2.column_name::text), '{}') into v_drop
      from information_schema.columns c2
     where c2.table_schema = 'public' and c2.table_name = v_tab
       and not (coalesce(t->'rows'->0, '{}'::jsonb) ? c2.column_name);
    begin
      execute format('create temp table it_restore_scratch (like public.%I) on commit drop', v_tab);
      execute format('insert into it_restore_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', v_tab)
        using coalesce(t->'rows', '[]'::jsonb);
      get diagnostics n_rest = row_count;
      execute format(
        'select count(*) filter (where l.%1$I is not null and (to_jsonb(l) - $1) = (to_jsonb(s) - $1)),
                count(*) filter (where l.%1$I is not null and (to_jsonb(l) - $1) <> (to_jsonb(s) - $1)),
                count(*) filter (where l.%1$I is null)
           from it_restore_scratch s left join public.%2$I l on l.%1$I = s.%1$I', v_key, v_tab)
        into n_match, n_changed, n_missing using v_drop;
      drop table it_restore_scratch;
    exception when others then v_err := 'restore into scratch failed: ' || sqlerrm;
    end;
  end if;
  if v_err is null and n_rest = 0 and v_key is not null then
    if coalesce((t->>'rows_in_file')::int, -1) = 0 then
      -- 23 Sep 2026: an empty page restores nothing, so it proves nothing -- a failure, not a pass.
      execute format('select not exists (select 1 from public.%I)', v_tab) into v_live_empty;
      v_err := 'the picked page of ' || v_tab || ' holds 0 rows, so nothing was restored and nothing was proved'
               || case when v_live_empty then ' (live is empty too)' else '' end;
    else
      v_err := 'the export holds ' || coalesce(t->>'rows_in_file', 'an unknown number of') || ' row(s) and none reached the restore';
    end if;
  end if;
  v_ok := v_err is null and n_rest > 0 and n_match > 0;
  v_detail := jsonb_build_object('table', v_tab, 'path', t->>'path', 'rows_in_file', t->'rows_in_file', 'restored', n_rest,
                                 'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_missing,
                                 'not_compared', to_jsonb(v_drop), 'error', v_err,
                                 'newest_export_day', p->>'newest_export_day', 'age_days', v_age,
                                 'last_full_day', v_full, 'chain_gaps', v_gaps, 'rebuild', v_rebuild);
  insert into public.it_restore_drill_result (subject, ok, detail)
  values (coalesce(v_tab, 'no table') || coalesce(' from ' || (t->>'path'), ''), v_ok and v_rebuild_ok and jsonb_array_length(v_items) = 0, v_detail);
  if not v_ok then
    v_items := v_items || jsonb_build_object('item', 'restore', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', 'The monthly restore drill could not restore a table sample' || coalesce(' of ' || v_tab, '') || ': '
               || coalesce(v_err, n_rest || ' row(s) restored and none identical to live (' || n_changed || ' changed, ' || n_missing || ' gone)'),
      'blast', 'agent_facing', 'affected', 1, 'evidence', v_detail);
  end if;

  v_out := jsonb_build_object('restore_table', public.fn_it_duty_settle('restore_table', v_items), 'drill', v_detail);
  perform public.fn_it_engineer_finding_close('duty:restore_heartbeat:unrecorded', 'the table restore drill recorded a result');
  perform public.fn_it_duty_ran('restore_table', v_out);
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_review_independence_items()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with held as (
    select jsonb_build_object(
             'item', 'review_held:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) HELD: no healthy reviewer outside the authors'' families (not even a '
                      || 'last-resort family), or the chosen reviewer failed. Nothing ran unreviewed or same-family; restore a reviewer or decide the held work.',
             'blast', 'agent_facing', 'affected', sum(times_held),
             'evidence', jsonb_build_object('review_hold_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.review_hold where closed_at is null group by task_class
  ), third as (
    select jsonb_build_object(
             'item', 'third_family_review:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) in 7 days ran on a LAST-RESORT family ('
                      || string_agg(distinct model_used, ', ') || ') because the authors spanned both judgement families.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id))) x
      from public.ai_cost_log
     where reviewer_tier = 'third_family_fallback' and occurred_at > now() - interval '7 days'
     group by task_class
  ), unknown_author as (
    select jsonb_build_object(
             'item', 'review_author_unknown:' || coalesce(fn, task_class), 'owner_seat', 'it_engineer', 'subject', 'review_independence',
             'title', count(*) || ' ' || coalesce(task_class, '?') || ' review(s) from ' || coalesce(fn, '?') || ' in 7 days named an author '
                      || 'model that is not in model_registry (or ''unknown''), so they could not be routed. Fix what the caller records '
                      || 'about the author; the model comparison was withheld, not skipped silently.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.ai_cost_log
     where coalesce(model_used, 'none') = 'none' and model_selected_because like 'AUTHOR UNKNOWN:%'
       and occurred_at > now() - interval '7 days'
     group by coalesce(fn, task_class), task_class, fn
  )
  select coalesce((select jsonb_agg(x) from held), '[]'::jsonb) || coalesce((select jsonb_agg(x) from third), '[]'::jsonb)
         || coalesce((select jsonb_agg(x) from unknown_author), '[]'::jsonb);
$function$


CREATE OR REPLACE FUNCTION public.fn_it_review_independence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_closed int; v_items jsonb;
begin
  -- A hold closes only once the same class, over the same authors, RAN ON A MODEL independently after it. The gateway's
  -- own refusal row for the held call (model_used 'none', ok true) is not a review and must not close it.
  update public.review_hold h set closed_at = now(), close_note = 'reviewed independently after the hold: ai_cost_log '
         || (select min(l.id) from public.ai_cost_log l
              where l.task_class = h.task_class and l.counterpart_model = h.counterpart_model and l.ok
                and coalesce(l.model_used, 'none') <> 'none'
                and l.review_violation is null and l.occurred_at > h.last_held_at)
   where h.closed_at is null
     and exists (select 1 from public.ai_cost_log l
                  where l.task_class = h.task_class and l.counterpart_model = h.counterpart_model and l.ok
                    and coalesce(l.model_used, 'none') <> 'none'
                    and l.review_violation is null and l.occurred_at > h.last_held_at);
  get diagnostics v_closed = row_count;
  v_items := public.fn_it_review_independence_items();
  return jsonb_build_object('closed_holds', v_closed, 'items', jsonb_array_length(v_items),
                            'settle', public.fn_it_duty_settle('review_independence', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_run_is_held(p_agent text, p_started timestamp with time zone, p_counts jsonb, p_note text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
       exists (select 1 from public.it_hold_signature h
                where h.subject = regexp_replace(coalesce(p_agent, ''), '^fn:', '')
                  and coalesce(p_counts, '{}'::jsonb) @> h.counts_match
                  and (h.note_like is null or coalesce(p_note, '') like h.note_like))
   and exists (select 1 from public.llm_route_health r
                where r.opened_reason like 'HELD BY THE FOUNDER%' and r.open_until > p_started)
  , false)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_run_is_refusal(p_agent text, p_started timestamp with time zone, p_counts jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
       (p_counts ->> 'http') ~ '^4[0-9][0-9]$'
    or (p_counts ->> 'signal') in ('forbidden','bad_secret')
    or (p_counts ->> 'authorised') = '0'
    or coalesce(nullif(p_counts ->> 'forbidden','')::int, 0) > 0
    or (p_agent not like 'fn:%' and exists (
         select 1 from public.agent_runs t
         where t.agent = 'fn:' || p_agent
           and t.started_at between p_started - interval '5 seconds' and p_started + interval '5 seconds'
           and (t.counts ->> 'http') ~ '^4[0-9][0-9]$'))
  , false)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_scheduled_due()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(s.duty order by s.duty), '{}')
    from public.it_duty_schedule s
   where not exists (select 1 from public.agent_runs r
                      where r.agent = 'it_engineer' and r.counts->>'job' = 'duty:' || s.duty
                        and r.started_at > now() - s.every + interval '5 minutes')
$function$


CREATE OR REPLACE FUNCTION public.fn_it_security_exposures()
 RETURNS TABLE(object text, kind text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Review of #639: this used to call a routine anon-executable when anon OR authenticated could run
  -- it, and so flagged the two portal RPCs fn_customer_documents and fn_customer_document_refs, which
  -- are authenticated-only (anon_exec false, measured). The two are different findings now:
  --   anon_executable_definer          anyone at all can run it with the definer's rights — always raised
  --   authenticated_executable_definer a signed-in user can, and the body never asks who they are
  --                                    (no auth.uid(), auth.email() or auth.jwt()) — raised
  -- A signed-in RPC that scopes itself by the caller's identity is the portals working, not a finding.
  select p.oid::regprocedure::text, 'anon_executable_definer'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select p.oid::regprocedure::text, 'authenticated_executable_definer'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.prosrc !~* 'auth\.(uid|email|jwt)\s*\('
     -- Scoping by delegation counts: fn_customer_documents asks no identity itself and joins
     -- fn_customer_document_refs(), which does (measured 14 Sep 2026). One level of call is followed.
     and not exists (select 1 from pg_proc q join pg_namespace qn on qn.oid = q.pronamespace
                      where qn.nspname = 'public' and q.oid <> p.oid
                        and q.prosrc ~* 'auth\.(uid|email|jwt)\s*\('
                        and p.prosrc ~* ('public\.' || q.proname || '\s*\('))
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select c.oid::regclass::text, case when not c.relrowsecurity then 'rls_off' else 'rls_no_policy' end
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (not c.relrowsecurity or not exists (select 1 from pg_policy pl where pl.polrelid = c.oid))
     -- Only what a browser role can actually read: an RLS-less table nobody is granted is not exposed.
     and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select'))
$function$


CREATE OR REPLACE FUNCTION public.fn_it_sender_health_record(p_sender jsonb)
 RETURNS it_sender_health_daily
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sent int; v_bounce int; v_compl int; v_listed int; v_wa text; r public.it_sender_health_daily;
begin
  select count(*) into v_sent from public.notifications
   where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
  select count(*) filter (where reason like 'hard_bounce%'), count(*) filter (where reason = 'spam_complaint')
    into v_bounce, v_compl from public.email_suppressions
   where source = 'resend_webhook' and created_at > now() - interval '7 days';
  select count(*) into v_listed from jsonb_array_elements(coalesce(p_sender->'blocklists', '[]'::jsonb)) b
   where b->>'basis' = 'measured' and coalesce((b->>'listed')::boolean, false);
  v_wa := case when p_sender->'whatsapp'->>'basis' = 'measured' then p_sender->'whatsapp'->>'quality' end;

  insert into public.it_sender_health_daily as t
    (day, sent_7d, hard_bounces_7d, complaints_7d, bounce_rate, complaint_rate, whatsapp_quality, blocklisted, dmarc, breaches)
  values (current_date, v_sent, v_bounce, v_compl,
          round(v_bounce::numeric / nullif(v_sent, 0), 5), round(v_compl::numeric / nullif(v_sent, 0), 5),
          v_wa, v_listed,
          jsonb_build_object('published', (select jsonb_object_agg(key, value->'dmarc') from jsonb_each(coalesce(p_sender->'dns', '{}'::jsonb))),
                             'aggregate', jsonb_build_object('basis', 'unavailable',
                               'reason', 'the rua mailbox is not a store this estate reads')),
          public.fn_it_sender_health_verdict(v_sent, v_bounce, v_compl, v_wa, v_listed))
  on conflict (day) do update set
    sent_7d = excluded.sent_7d, hard_bounces_7d = excluded.hard_bounces_7d, complaints_7d = excluded.complaints_7d,
    bounce_rate = excluded.bounce_rate, complaint_rate = excluded.complaint_rate,
    whatsapp_quality = excluded.whatsapp_quality, blocklisted = excluded.blocklisted,
    dmarc = excluded.dmarc, breaches = excluded.breaches, recorded_at = now()
  returning * into r;
  return r;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_sender_health_verdict(p_sent numeric, p_hard_bounces numeric, p_complaints numeric, p_whatsapp_quality text, p_blocklisted integer)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select array_remove(array[
    case when p_sent >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20)
          and p_complaints / nullif(p_sent, 0) > coalesce(public.fn_it_threshold('sender_complaint_rate_max'), 0.003)
         then 'complaint_rate' end,
    case when p_sent >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20)
          and p_hard_bounces / nullif(p_sent, 0) > coalesce(public.fn_it_threshold('sender_bounce_rate_max'), 0.02)
         then 'bounce_rate' end,
    case when upper(coalesce(p_whatsapp_quality, 'UNKNOWN')) not in ('HIGH', 'GREEN', 'UNKNOWN')
         then 'whatsapp_quality' end,
    case when coalesce(p_blocklisted, 0) > 0 then 'blocklisted' end
  ], null)
$function$


CREATE OR REPLACE FUNCTION public.fn_it_sender_rate_items(p_sent numeric, p_hard_bounces numeric, p_complaints numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(i), '[]'::jsonb) from (
    select jsonb_build_object('item', 'bounce_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
             'title', round(100 * p_hard_bounces / p_sent, 2) || '% of last week''s emails hard-bounced', 'blast', 'customer_facing', 'affected', 1,
             'evidence', jsonb_build_object('hard_bounces', p_hard_bounces, 'sent', p_sent, 'max', public.fn_it_threshold('sender_bounce_rate_max'))) i
     where p_sent > 0 and p_hard_bounces / p_sent > public.fn_it_threshold('sender_bounce_rate_max')
    union all
    select jsonb_build_object('item', 'complaint_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
             'title', round(100 * p_complaints / p_sent, 3) || '% of last week''s emails were reported as spam', 'blast', 'customer_facing', 'affected', 1,
             'evidence', jsonb_build_object('complaints', p_complaints, 'sent', p_sent, 'max', public.fn_it_threshold('sender_complaint_rate_max')))
     where p_sent > 0 and p_complaints / p_sent > public.fn_it_threshold('sender_complaint_rate_max')) z
$function$


CREATE OR REPLACE FUNCTION public.fn_it_severity(p_state text, p_public boolean)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_state = 'stopped'  and p_public then 'critical'
    when p_state = 'stopped'               then 'high'
    when p_state = 'degraded' and p_public then 'high'
    when p_state = 'degraded'              then 'medium'
    when p_state = 'delayed'  and p_public then 'medium'
    when p_state = 'delayed'               then 'low'
    else 'low'
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_it_slo_judge(p_runs_24h integer, p_p95_ms numeric, p_budget_ms integer, p_bad_24h integer, p_runs_30d integer, p_bad_30d integer)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- MIN_RUNS 5, SLO 99.9 % (error budget 0.001), burn-rate alarm 2x. One place for every threshold.
  select jsonb_build_object(
    'p95_breach',   coalesce(p_runs_24h, 0) >= 5 and p_p95_ms > p_budget_ms,
    'small_sample', coalesce(p_runs_24h, 0) between 5 and 29,
    'availability', case when p_runs_30d > 0 then round(1 - p_bad_30d::numeric / p_runs_30d, 4) end,
    'budget_spent', case when p_runs_30d > 0 then round((p_bad_30d::numeric / p_runs_30d) / 0.001, 2) end,
    'burn_rate_24h', case when p_runs_24h > 0 then round((p_bad_24h::numeric / p_runs_24h) / 0.001, 2) end,
    'budget_breach', (case when coalesce(p_runs_24h, 0) >= 5 then p_bad_24h::numeric / p_runs_24h / 0.001 >= 2 else false end)
                     or (case when coalesce(p_runs_30d, 0) >= 5 then p_bad_30d::numeric / p_runs_30d > 0.001 else false end));
$function$


CREATE OR REPLACE FUNCTION public.fn_it_smoke_ingest(p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_owner text; v_owners jsonb; x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
  -- Absent means complete, exactly as fn_it_journey_ingest reads it.
  v_complete boolean := coalesce((p_report->>'complete')::boolean, true);
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'sha'), '') = '' then
    raise exception 'fn_it_smoke_ingest takes {sha, changed_files, steps} from scripts/e2e/report_to_it_engineer.mjs --smoke';
  end if;
  with files as (
    select f from jsonb_array_elements_text(coalesce(p_report->'changed_files', '[]'::jsonb)) f),
  owned as (
    select case when o.owner in (select t.to_seat from public.fn_seat_handoff_types() t where t.type = 'it.finding')
                then o.owner else 'ceo' end seat
      from files
      left join public.function_owner o on o.function_slug = substring(files.f from '^supabase/functions/([^/_][^/]*)/'))
  select coalesce(jsonb_object_agg(seat, n), '{}'::jsonb) into v_owners
    from (select seat, count(*) n from owned group by seat) z;
  select key into v_owner from jsonb_each_text(v_owners) order by value::int desc, key limit 1;
  for x in select e from jsonb_array_elements(p_report->'steps') e where e->>'status' = 'FAIL' loop
    v_items := v_items || jsonb_build_object(
      'item', coalesce(x->>'journey', '?') || ':' || left(regexp_replace(coalesce(x->>'name', '?'), '[^a-zA-Z0-9]+', '_', 'g'), 80),
      'owner_seat', coalesce(v_owner, 'ceo'), 'subject', 'merge ' || left(p_report->>'sha', 7),
      'title', 'After merge ' || left(p_report->>'sha', 7) || ', the smoke test failed: [' || coalesce(x->>'journey', '?') || '] ' || coalesce(x->>'name', '?'),
      'blast', 'customer_facing', 'affected', 0, 'demo', coalesce((p_report->>'demo')::boolean, false),
      'evidence', jsonb_build_object('sha', p_report->>'sha', 'owners', v_owners, 'changed_files', p_report->'changed_files',
                                     'tag', p_report->>'tag', 'detail', left(x->>'detail', 600)));
  end loop;
  if v_complete then
    v_res := public.fn_it_duty_settle('smoke', v_items);
  else
    -- Looked at part of it: raise what fails, close NOTHING (the rule fn_it_journey_ingest already keeps).
    for x in select e from jsonb_array_elements(v_items) e loop
      perform public.fn_it_engineer_finding_upsert(
        'duty:smoke:' || (x->>'item'), x->>'title', 'IT engineer duty: smoke',
        coalesce(x->>'blast', 'customer_facing'), coalesce((x->>'affected')::int, 0),
        coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
          'duty', 'smoke', 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
          'demo', coalesce((x->>'demo')::boolean, false), 'run_complete', false),
        '{}'::text[], '{}'::text[], 'it_engineer.smoke');
    end loop;
    v_res := jsonb_build_object('duty', 'smoke', 'failing', jsonb_array_length(v_items), 'closed', 0, 'complete', false,
                                'note', 'the run stopped before it saw every journey, so nothing was closed on its silence');
  end if;
  perform public.fn_it_duty_ran('smoke', v_res || jsonb_build_object('sha', p_report->>'sha'));
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_threshold(p_key text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select value from public.it_threshold where key = p_key
$function$


CREATE OR REPLACE FUNCTION public.fn_it_usage_watch(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_vals jsonb; v_not jsonb := '{}'::jsonb; v_prov text; v_items jsonb; t public.it_threshold; v_metric text;
  v_floor boolean; v numeric; v_ratio numeric; v_fmt text; v_lim text; v_out jsonb := '{}'::jsonb;
  v_unjudged jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_it_usage_watch takes the readings object from takeUsageReadings';
  end if;
  v_ratio := coalesce(public.fn_it_threshold('cap_warn_ratio'), 0.8);
  v_vals := jsonb_build_object(
    'supabase_storage_bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o),
    'resend_emails_month', (select count(*) from public.notifications n
                             where n.channel = 'email' and n.status = 'sent' and n.sent_at >= date_trunc('month', now())),
    'resend_emails_day',   (select count(*) from public.notifications n
                             where n.channel = 'email' and n.status = 'sent' and n.sent_at >= date_trunc('day', now())));
  if p_r->'twilio'->>'basis' = 'measured' then
    v_vals := v_vals || jsonb_build_object('twilio_balance', (p_r->'twilio'->>'balance')::numeric);
  else
    v_not := v_not || jsonb_build_object('twilio', coalesce(p_r->'twilio'->>'reason', 'no reading'));
  end if;
  if p_r->'vercel'->>'basis' = 'measured' then
    v_vals := v_vals || jsonb_build_object('vercel_charges_month', (p_r->'vercel'->>'charges_month')::numeric);
  else
    v_not := v_not || jsonb_build_object('vercel', coalesce(p_r->'vercel'->>'reason', 'no reading'));
  end if;

  for v_prov in select distinct split_part(regexp_replace(key, '^(cap|floor)_', ''), '_', 1) from public.it_threshold
                 where key ~ '^(cap|floor)_' and key <> 'cap_warn_ratio' order by 1 loop
    -- A provider none of whose figures were read settles nothing: its open findings stay as they were.
    continue when not exists (select 1 from jsonb_object_keys(v_vals) k where k like v_prov || '\_%');
    v_items := '[]'::jsonb;
    for t in select * from public.it_threshold where key ~ ('^(cap|floor)_' || v_prov || '_') order by key loop
      v_metric := regexp_replace(t.key, '^(cap|floor)_', '');
      v_floor := t.key like 'floor\_%';
      v := (v_vals->>v_metric)::numeric;
      continue when v is null;
      v_fmt := case when t.unit = 'bytes' then pg_size_pretty(v) else round(v, 2)::text || ' ' || t.unit end;
      if t.value is null then
        -- 22 Sep 2026, instruction 639: nobody set a number, so there is nothing to judge. The reading is
        -- kept, with where the number would come from, and nothing is raised.
        v_unjudged := v_unjudged || jsonb_build_object(v_metric, jsonb_build_object('value', v, 'unit', t.unit, 'basis', t.basis));
      elsif (not v_floor and v >= v_ratio * t.value) or (v_floor and v <= t.value) then
        v_lim := case when t.unit = 'bytes' then pg_size_pretty(t.value) else round(t.value, 2)::text || ' ' || t.unit end;
        v_items := v_items || jsonb_build_object('item', v_metric, 'owner_seat', 'accountant', 'subject', v_prov,
          'title', case when v_floor
                        then replace(v_metric, '_', ' ') || ' is down to ' || v_fmt || ', at or below the floor of ' || v_lim
                        else replace(v_metric, '_', ' ') || ' is at ' || coalesce(round(100 * v / nullif(t.value, 0))::text, '?')
                             || '% of its cap (' || v_fmt || ' of ' || v_lim || ')' end,
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('value', v, 'cap', t.value, 'unit', t.unit, 'key', t.key, 'warn_ratio', v_ratio, 'basis', t.basis));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('usage_' || v_prov, public.fn_it_duty_settle('usage_' || v_prov, v_items));
  end loop;

  perform public.fn_it_duty_ran('usage', v_out || jsonb_build_object('values', v_vals, 'not_read', v_not, 'unjudged', v_unjudged));
  return v_out || jsonb_build_object('not_read', v_not, 'unjudged', v_unjudged);
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_whatsapp_delivery_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  x record; v_items jsonb := '[]'::jsonb; v_rates jsonb := '{}'::jsonb; v_out jsonb;
  v_min numeric := coalesce(public.fn_it_threshold('whatsapp_min_final_7d'), 10);
  v_max numeric := coalesce(public.fn_it_threshold('whatsapp_failure_rate_max'), 0.05);
begin
  for x in
    select n.channel,
           count(*) filter (where n.provider_status in ('delivered', 'read')) as delivered,
           count(*) filter (where n.provider_status = 'read') as read,
           count(*) filter (where n.provider_status in ('failed', 'undelivered')) as failed,
           -- 22 Sep 2026: a message we asked Twilio about c_give_up times and could not read is no longer
           -- counted as "no report yet" — that read as a message still in flight. It is counted as
           -- unreadable and raised on its own, so the two causes are never added into one number.
           count(*) filter (where public.fn_twilio_status_rank(n.provider_status) < 4
                              and coalesce(n.provider_status, '') <> 'unreadable'
                              and n.sent_at < now() - interval '24 hours') as unknown,
           count(*) filter (where n.provider_status = 'unreadable') as unreadable,
           count(*) as accepted
      from public.notifications n
     where n.channel in ('whatsapp', 'sms') and coalesce(btrim(n.provider_message_id), '') <> ''
       and n.sent_at > now() - interval '7 days'
     group by n.channel
  loop
    v_rates := v_rates || jsonb_build_object(x.channel, jsonb_build_object('accepted', x.accepted, 'delivered', x.delivered,
      'read', x.read, 'failed', x.failed, 'no_final_status_after_24h', x.unknown, 'unreadable', x.unreadable,
      -- Sends this estate can NEVER get a status for: no provider_message_id was stored (every send before
      -- the 21 Sep SID fix). Counted here so the rate above is read against what it actually covers.
      'sent_without_a_provider_id', (select count(*) from public.notifications m
                                      where m.channel = x.channel and m.status in ('sent', 'failed')
                                        and coalesce(btrim(m.provider_message_id), '') = ''
                                        and m.sent_at > now() - interval '7 days'),
      'errors', (select coalesce(jsonb_object_agg(coalesce(e.code, 'none'),
                                   jsonb_build_object('count', e.c, 'means', public.fn_twilio_error_in_plain_words(e.code))), '{}'::jsonb)
                   from (select m.provider_error_code code, count(*) c from public.notifications m
                          where m.channel = x.channel and m.provider_status in ('failed', 'undelivered')
                            and m.sent_at > now() - interval '7 days' group by 1) e)));
    if x.delivered + x.failed >= v_min and x.failed::numeric / (x.delivered + x.failed) > v_max then
      v_items := v_items || jsonb_build_object('item', 'failure_rate:' || x.channel, 'owner_seat', 'customer_support', 'subject', 'wa_status',
        'title', round(100 * x.failed::numeric / (x.delivered + x.failed), 1) || '% of last week''s ' || x.channel
                 || ' messages were refused after Twilio accepted them',
        'blast', 'customer_facing', 'affected', x.failed,
        'evidence', (v_rates->x.channel) || jsonb_build_object('max', v_max, 'min_final', v_min));
    end if;
    if x.unknown > 0 then
      v_items := v_items || jsonb_build_object('item', 'no_final_status:' || x.channel, 'owner_seat', 'customer_support', 'subject', 'wa_status',
        'title', x.unknown || ' ' || x.channel || ' message(s) sent over 24 hours ago have no delivery report from Twilio',
        'blast', 'customer_facing', 'affected', x.unknown,
        'evidence', (v_rates->x.channel) || jsonb_build_object('why_it_matters',
          'the status callback (wa_status) and its 30-minute backstop poll are both silent, so delivery is unknown'));
    end if;
    if x.unreadable > 0 then
      v_items := v_items || jsonb_build_object('item', 'status_unreadable:' || x.channel, 'owner_seat', 'customer_support', 'subject', 'wa_status',
        'title', x.unreadable || ' ' || x.channel || ' message(s) were asked of Twilio until the poll gave up: their delivery is unknown',
        'blast', 'customer_facing', 'affected', x.unreadable,
        'evidence', (v_rates->x.channel) || jsonb_build_object('why_it_matters',
          'the backstop poll could not read Twilio for these messages (notifications.last_error carries the HTTP status and Twilio code of the last attempt), so no delivery can be claimed for them'));
    end if;
  end loop;
  v_out := jsonb_build_object('settled', public.fn_it_duty_settle('whatsapp_delivery', v_items), 'rates', v_rates);
  perform public.fn_it_duty_ran('whatsapp_delivery', v_out);
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_it_workflow_heartbeats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_items jsonb := '[]'::jsonb; x record; v_running interval;
begin
  -- How long the scheduled duties have been running at all. The original guard asked this as an
  -- EXISTS per subject over the same set, so asking it once is the same test, and it now reads as
  -- what it is. Note what it is NOT: it is global, not per subject. A subject added today borrows
  -- its grace period from the oldest duty row of any kind — months — so it is judged from the first
  -- tick rather than after its own interval. That is why every key above was read out of production
  -- before it was added, and why kb_embed's "never beaten" is documented as expected rather than
  -- discovered in the finding ledger.
  select now() - min(started_at) into v_running
    from public.agent_runs where agent = 'it_engineer' and counts->>'job' like 'duty:%';
  if v_running is null then return public.fn_it_duty_settle('workflow_heartbeat', '[]'::jsonb); end if;

  for x in
    select 'dependency'::text job, interval '8 days' every,
           '.github/workflows/it-weekly-readings.yml'::text wf,
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:dependency') last
    union all
    select 'platform', interval '8 days', '.github/workflows/it-weekly-readings.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:platform')
    union all
    select 'smoke', interval '7 days', '.github/workflows/it-post-deploy-smoke.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:smoke')
    union all
    select 'kb_embed', interval '36 hours', '.github/workflows/kb-embed-backfill.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:kb_embed')
    union all
    -- The second scheduler kicks every 6 hours; 12 h is two missed kicks, not one late one.
    select 'dropbox_kick', interval '12 hours', '.github/workflows/dropbox-backup-second-scheduler.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'backup_kick' and counts->>'reason' = 'github_actions')
    union all
    -- project-parity.yml runs daily AND on every pull request, and the advisor refresh step stamps
    -- last_seen_at on each of the 563 baseline rows.
    -- SAY WHAT THIS DOES NOT CATCH. The key cannot tell a scheduled run from a pull-request run, and
    -- this repository merges most days, so a permanently broken `schedule:` trigger — a cron run has
    -- no PR context and a different token scope, so it can fail on its own — would stay hidden behind
    -- the PR runs indefinitely. What this subject DOES catch is the whole workflow going quiet: no
    -- parity run of any kind for 36 hours, which is the weekend, the quiet day, and a deleted or
    -- disabled workflow. It is deliberately not claimed as coverage of the schedule itself; closing
    -- that would need the refresh step to record which trigger it ran under, and it does not.
    select 'parity', interval '36 hours', '.github/workflows/project-parity.yml',
           (select max(last_seen_at) from public.security_advisor_baseline)
  loop
    continue when v_running <= x.every;   -- the schedule has not had time to come round yet
    if x.last is null then
      -- NEVER BEAT. Zero cannot tell a dead guard from an idle system, so this is said in its own
      -- words rather than reported as "late": nothing has ever written the row this reads.
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'Nothing has ever reported a ' || x.job || ' run, so its workflow cannot be seen to fail',
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'every', x.every::text, 'last', null,
          'look_at', 'the workflow''s runs in GitHub Actions, then whether the step that reports back is present and reached'));
    elsif x.last < now() - x.every then
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'The ' || x.job || ' readings from GitHub have not arrived for ' || x.every,
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'every', x.every::text, 'last', x.last,
          'look_at', 'the workflow''s runs in GitHub Actions: not triggered, failed, or failed to report'));
    end if;
  end loop;
  return public.fn_it_duty_settle('workflow_heartbeat', v_items);
end $function$


CREATE OR REPLACE FUNCTION public.fn_job_no(p_inquiry uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select i.rfq_no::text from public.inquiries i where i.id = p_inquiry
$function$


CREATE OR REPLACE FUNCTION public.fn_jsonb_text_array(j jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when j is null or jsonb_typeof(j) <> 'array' then null
              else (select array_agg(x) from jsonb_array_elements_text(j) x) end;
$function$


CREATE OR REPLACE FUNCTION public.fn_judgement_decided(p_id bigint, p_status text, p_decision text, p_confidence numeric, p_model text, p_followed bigint[] DEFAULT NULL::bigint[])
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_recalled bigint[]; v_stray bigint[];
begin
  if p_followed is not null then
    select coalesce(array_agg((c->>'case_id')::bigint), '{}') into v_recalled
      from public.seat_judgement j, jsonb_array_elements(coalesce(j.recall->'cases', '[]'::jsonb)) c
     where j.id = p_id;
    select coalesce(array_agg(x), '{}') into v_stray from unnest(p_followed) x where not (x = any (coalesce(v_recalled, '{}')));
    if cardinality(v_stray) > 0 then
      raise exception 'judgement % did not recall case(s) %, so it cannot have followed them', p_id, v_stray using errcode = '22023';
    end if;
  end if;
  update public.seat_judgement
     set status = p_status, decision = left(p_decision, 2000), confidence = p_confidence, model = p_model, decided_at = now(),
         -- array_agg over nothing is null, and '{}' (no precedent followed) must stay distinct from null (not said)
         followed_case_ids = case when p_followed is not null
                                  then coalesce((select array_agg(distinct x order by x) from unnest(p_followed) x), '{}') end
   where id = p_id and p_status in ('answered','held');
  return found;
end $function$


CREATE OR REPLACE FUNCTION public.fn_judgement_outcome(p_table text, p_id text, p_outcome text, p_correct boolean, p_finalised boolean DEFAULT true, p_seat text DEFAULT NULL::text, p_kind text DEFAULT NULL::text, p_situation text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  update public.seat_judgement
     set outcome = left(p_outcome, 1000), outcome_correct = p_correct, finalised = finalised or coalesce(p_finalised, true), outcome_at = now()
   where subject_table = p_table and subject_id = p_id;
  get diagnostics n = row_count;
  if p_seat is not null then
    update public.seat_case_memory
       set outcome = left(p_outcome, 1000), finalised = finalised or coalesce(p_finalised, true),
           finalised_at = coalesce(finalised_at, case when p_finalised then now() end), updated_at = now()
     where source_table = p_table and source_id = p_id;
    if not found and p_situation is not null then
      perform public.fn_case_remember(p_seat, coalesce(p_kind, p_table), p_table, p_id, null, p_situation,
        null, null, p_outcome, coalesce(p_finalised, true), '{}', null,
        case when p_correct is false then 'Went wrong: ' || p_outcome end);
    end if;
  end if;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_judgement_record(p_seat text, p_surface text, p_subject jsonb, p_question text, p_recall jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; s record;
begin
  if p_recall is null or jsonb_typeof(p_recall) <> 'object' or not (p_recall ? 'available') then
    raise exception 'a judgement is recorded with its recall, or not at all' using errcode = '22023';
  end if;
  select * into s from public.fn_judgement_subject(p_subject);
  insert into public.seat_judgement (seat, surface, subject, subject_table, subject_id, question, recall)
  values (p_seat, p_surface, p_subject, s.t, s.i, left(p_question, 2000), p_recall)
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_judgement_subject(p jsonb, OUT t text, OUT i text)
 RETURNS record
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when p ? 'table' and p ? 'id' then p->>'table'
              when p ? 'quote_id' then 'quotes'
              when p ? 'inquiry_id' then 'inquiries'
              when p ? 'intake_id' then 'inquiry_intake'
              when p ? 'command_id' then 'ceo_command'
              when p ? 'notification_id' then 'notifications'
              when p ? 'expense_id' then 'expense_entries'
              when p ? 'issue_key' then 'it_engineer_finding'
              when p ? 'message_id' then 'social_message' end,
         coalesce(p->>'id', p->>'quote_id', p->>'inquiry_id', p->>'intake_id', p->>'command_id',
                  p->>'notification_id', p->>'expense_id', p->>'issue_key', p->>'message_id')
   where p is not null and jsonb_typeof(p) = 'object'
$function$


CREATE OR REPLACE FUNCTION public.fn_judgement_without_recall()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'judgements', count(*),
    'without_recall', count(*) filter (where recall is null or jsonb_typeof(recall) <> 'object' or not (recall ? 'available')),
    'recall_unavailable', count(*) filter (where recall ? 'available' and (recall->>'available')::boolean is false),
    'ids', coalesce((jsonb_agg(id order by id) filter (where recall is null or jsonb_typeof(recall) <> 'object' or not (recall ? 'available'))), '[]'::jsonb))
  from public.seat_judgement
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_approve(p_revision bigint, p_reviewer text, p_notes text DEFAULT NULL::text, p_publish boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_rows int := 0; v_status text; v_applied boolean := false;
begin
  select * into r from public.kb_revisions where id = p_revision;
  if r is null then return jsonb_build_object('error', 'revision not found'); end if;

  if p_publish and r.entry_kind = 'agent_knowledge' and position(' :: ' in r.entry_ref) > 0 then
    update agent_knowledge set content = r.content
     where agent_key = split_part(r.entry_ref, ' :: ', 1)
       and topic     = split_part(r.entry_ref, ' :: ', 2);
    get diagnostics v_rows = row_count;
    v_applied := v_rows > 0;
  end if;

  -- THE STATUS FOLLOWS THE EFFECT, not the intent.
  v_status := case
    when not p_publish then 'approved'
    when r.entry_kind = 'agent_knowledge' and position(' :: ' in r.entry_ref) > 0 and not v_applied
      then 'approved_unapplied'
    else 'published' end;

  update public.kb_revisions
     set status = v_status, reviewer = p_reviewer, review_notes = p_notes, decided_at = now()
   where id = p_revision;

  return jsonb_build_object(
    'ok', true, 'revision', p_revision, 'status', v_status,
    'live_rows_updated', v_rows,
    'note', case when v_status = 'approved_unapplied'
                 then 'Approved, but NOT applied: no live agent_knowledge row matches "'
                      || r.entry_ref || '". The employee''s knowledge is unchanged.'
                 else null end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_embed_backlog()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'estimated_unembedded', (select round(c.reltuples * coalesce(s.null_frac, 0))::bigint
                               from pg_class c
                               left join pg_stats s on s.schemaname = 'public' and s.tablename = 'kb_chunks' and s.attname = 'embedding_gte'
                              where c.oid = 'public.kb_chunks'::regclass),
    'estimated_total', (select reltuples::bigint from pg_class where oid = 'public.kb_chunks'::regclass),
    'stats_as_of', (select greatest(last_analyze, last_autoanalyze) from pg_stat_user_tables where schemaname = 'public' and relname = 'kb_chunks'),
    'frontier_created_at', (select min(created_at) from public.kb_chunks where embedding_gte is null),
    'measured_at', now());
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_embed_claim(p_limit integer DEFAULT 5, p_source_kinds text[] DEFAULT NULL::text[], p_categories text[] DEFAULT NULL::text[], p_newest boolean DEFAULT false)
 RETURNS TABLE(id bigint, title text, content text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_lim int := greatest(1, least(coalesce(p_limit, 5), 8));
begin
  if coalesce(p_newest, false) then
    return query
      with pick as (
        select k.id
          from public.kb_chunks k
         where k.embedding_gte is null
           and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
           and (p_source_kinds is null or k.source_kind = any(p_source_kinds))
           and (p_categories is null or k.category = any(p_categories))
         order by k.created_at desc
         limit v_lim
           for update skip locked)
      update public.kb_chunks k set embed_claimed_at = now()
        from pick where k.id = pick.id
      returning k.id, k.title, k.content;
  elsif p_source_kinds is not null then
    -- 6 SEP 2026: a kind-filtered pick reads kb_chunks_unembedded_kind_created_idx (source_kind, created_at)
    -- where embedding_gte is null. Ordered by kind first so the index serves the order and the array
    -- key: the planner otherwise walks the whole un-embedded set in date order (2.56M rows, 370k pages
    -- read from disk, 23 s) because it cannot see that only a handful of these kinds remain.
    return query
      with pick as (
        select k.id
          from public.kb_chunks k
         where k.embedding_gte is null
           and k.source_kind = any(p_source_kinds)
           and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
           and (p_categories is null or k.category = any(p_categories))
         order by k.source_kind asc, k.created_at asc
         limit v_lim
           for update skip locked)
      update public.kb_chunks k set embed_claimed_at = now()
        from pick where k.id = pick.id
      returning k.id, k.title, k.content;
  else
    return query
      with pick as (
        select k.id
          from public.kb_chunks k
         where k.embedding_gte is null
           and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
           and (p_source_kinds is null or k.source_kind = any(p_source_kinds))
           and (p_categories is null or k.category = any(p_categories))
         order by k.created_at asc
         limit v_lim
           for update skip locked)
      update public.kb_chunks k set embed_claimed_at = now()
        from pick where k.id = pick.id
      returning k.id, k.title, k.content;
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_embed_dispatch(p_limit integer DEFAULT 200, p_max_tier integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_lim     int := greatest(1, least(coalesce(p_limit, 200), 1000));
  v_url     text;
  v_secret  text;
  v_queued  int := 0;
  v_cap     constant int := 150;   -- see the header: the in-flight ceiling, not the normal bound
  v_inflight int;
begin
  select 'https://' || value || '.supabase.co/functions/v1/ai_gateway' into v_url
    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_ai';
  if v_url is null or coalesce(v_secret, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_project_ref_or_cred_fn_ai');
  end if;

  -- CONCURRENCY CAP. Three minutes, matching the claim lease below, so "in flight" means the same
  -- thing in both places.
  select count(*) into v_inflight from public.kb_embed_inflight i
   where i.queued_at > now() - interval '3 minutes';
  v_lim := least(v_lim, greatest(0, v_cap - v_inflight));
  if v_lim = 0 then
    return jsonb_build_object('ok', true, 'queued', 0, 'inflight', v_inflight, 'cap', v_cap,
      'held', 'the gateway already has the in-flight ceiling of embed requests; nothing was claimed', 'at', now());
  end if;

  -- The claim. Same lease discipline as fn_kb_embed_claim -- FOR UPDATE SKIP LOCKED, a three-minute
  -- expiry stamped into embed_claimed_at -- so concurrent dispatches take disjoint slices and a
  -- dispatch that dies costs three minutes rather than its rows.
  with pick as (
    select k.id, k.title, k.content
      from public.kb_chunks k
      left join public.kb_embed_priority p on p.category = k.category
     where k.embedding_gte is null
       and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
       and coalesce(p.tier, 3) <= greatest(1, least(coalesce(p_max_tier, 4), 4))
     order by coalesce(p.tier, 3) asc, k.created_at asc
     limit v_lim
     for update of k skip locked
  ), claimed as (
    update public.kb_chunks k set embed_claimed_at = now()
      from pick where k.id = pick.id
    returning k.id, pick.title, pick.content
  ), sent as (
    select c.id,
           net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := jsonb_build_object(
                       '__secret', v_secret,
                       'fn', 'kb_embed_dispatch',
                       'action', 'embed',
                       -- 1,200 characters is the window kb_embed used and the window every existing
                       -- kb_chunks vector was built from. Changing it would make new rows
                       -- incomparable with the 166,093 already embedded.
                       'text', left(coalesce(c.title, '') || E'\n' || coalesce(c.content, ''), 1200)),
             timeout_milliseconds := 25000) as request_id
      from claimed c
  )
  insert into public.kb_embed_inflight (request_id, chunk_id)
  select s.request_id, s.id from sent s
  on conflict (request_id) do nothing;

  get diagnostics v_queued = row_count;
  return jsonb_build_object('ok', true, 'queued', v_queued, 'inflight_before', v_inflight, 'cap', v_cap,
                            'max_tier', p_max_tier, 'at', now());
end
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_embed_harvest()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_written int := 0;
  v_failed  int := 0;
  v_expired int := 0;
begin
  with done as (
    select f.request_id, f.chunk_id, r.status_code, r.content
      from public.kb_embed_inflight f
      join net._http_response r on r.id = f.request_id
  ), good as (
    select d.chunk_id, ((d.content::jsonb) ->> 'embedding') as vec
      from done d
     where d.status_code = 200
       and (d.content::jsonb) ->> 'embedding' is not null
  ), upd as (
    update public.kb_chunks k
       set embedding_gte = g.vec::vector, embed_claimed_at = null
      from good g
     where k.id = g.chunk_id and k.embedding_gte is null
    returning k.id
  ), del as (
    delete from public.kb_embed_inflight f
     using done d where f.request_id = d.request_id
    returning d.status_code
  )
  select (select count(*) from upd), (select count(*) from del where status_code is distinct from 200)
    into v_written, v_failed;

  -- A request pg_net never resolved: free the chunk so a later dispatch picks it up again.
  with stale as (
    delete from public.kb_embed_inflight
     where queued_at < now() - interval '1 hour'
    returning chunk_id
  )
  update public.kb_chunks k set embed_claimed_at = null
    from stale s where k.id = s.chunk_id and k.embedding_gte is null;
  get diagnostics v_expired = row_count;

  return jsonb_build_object('ok', true, 'embedded', v_written, 'failed', v_failed,
                            'expired_and_released', v_expired,
                            'still_inflight', (select count(*) from public.kb_embed_inflight),
                            'at', now());
end
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_embed_tick(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_h jsonb; v_d jsonb;
begin
  v_h := public.fn_kb_embed_harvest();
  v_d := public.fn_kb_embed_dispatch(p_limit, 4);
  return jsonb_build_object('ok', true, 'harvest', v_h, 'dispatch', v_d,
    'unembedded_remaining', (select round(c.reltuples * coalesce(s.null_frac, 0))::bigint
                               from pg_class c
                               left join pg_stats s on s.schemaname = 'public' and s.tablename = 'kb_chunks'
                                                   and s.attname = 'embedding_gte'
                              where c.oid = 'public.kb_chunks'::regclass));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_gov_approve(p_kind text, p_id text, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if p_kind = 'regulation' then
    update regulations set approved_at = now(), approved_by = p_by where id::text = p_id and approved_at is null;
    get diagnostics n = row_count;
    perform kb_sync();
    update agent_actions set status='approved', decided_at=now(), decided_by=p_by
      where kind='knowledge_approval' and detail->>'ref'=p_id and detail->>'kind'='regulation' and status in ('pending','needs_review');
    return jsonb_build_object('approved', n, 'kind', p_kind, 'id', p_id);
  end if;
  return jsonb_build_object('error','unsupported_kind', 'kind', p_kind);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_jurisdiction_file(p_limit integer DEFAULT 50)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; n integer := 0; v_req jsonb; v_opts jsonb; v_go text; v_cap integer; v_today integer;
begin
  perform pg_advisory_xact_lock(hashtext('public.fn_kb_jurisdiction_file'));   -- two callers cannot both spend the cap
  select value into v_go from public.app_secrets where key = 'kb_jurisdiction_backfill';
  if coalesce(v_go, '') <> 'go' then return 0; end if;
  select coalesce((value #>> '{}')::int, 12) into v_cap from public.decision_policy where key = 'kb_jurisdiction_daily_cap';
  v_cap := coalesce(v_cap, 12);
  select count(*) into v_today from public.reasoning_held_question
   where surface = 'ceo.kb_jurisdiction' and created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  p_limit := least(coalesce(p_limit, 50), greatest(v_cap - v_today, 0));
  if p_limit <= 0 then return 0; end if;
  v_opts := jsonb_build_array(
    jsonb_build_object('id', 'quotesdone',    'meaning', 'written by QuotesDone itself'),
    jsonb_build_object('id', 'uae',           'meaning', 'issued by or adopted by a UAE federal or emirate authority, free zone, municipality, civil defence or UAE utility'),
    jsonb_build_object('id', 'gcc',           'meaning', 'issued by a GCC body (e.g. GSO) or another GCC state''s authority'),
    jsonb_build_object('id', 'international', 'meaning', 'an international or European/British standard (ISO, IEC, EN, BS, Eurocode, CIBSE ...) that UAE specifications commonly adopt'),
    jsonb_build_object('id', 'us',            'meaning', 'United States law, a US agency or a US standards body, not cited as adopted by a UAE authority — out of scope'),
    jsonb_build_object('id', 'other_foreign', 'meaning', 'any other country''s law or body, or material unrelated to UAE construction and procurement'));
  for c in
    select distinct on (md5(k.citation)) md5(k.citation) as h, k.citation
      from public.kb_chunks k
     where k.citation is not null and btrim(k.citation) <> ''
       and public.fn_kb_purge_clause(k.source_kind, k.category, null) <> 1
       and not exists (select 1 from public.kb_citation_jurisdiction j where j.citation_md5 = md5(k.citation))
       and not exists (select 1 from public.reasoning_held_question q where q.dedupe_key = 'kb_jurisdiction:' || md5(k.citation))
     limit p_limit
  loop
    v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.kb_jurisdiction',
      'question', 'Which jurisdiction does this knowledge-library citation belong to? Citation: ' || left(c.citation, 2000),
      'context', jsonb_build_object('audience', 'internal'),
      'decision', jsonb_build_object('name', 'jurisdiction', 'options', v_opts),
      'subject', jsonb_build_object('citation_md5', c.h, 'citation', left(c.citation, 4000)),
      'dedupeKey', 'kb_jurisdiction:' || c.h);
    perform public.fn_reason_hold('ceo', 'ceo.kb_jurisdiction', v_req->>'question', v_req, '{}'::jsonb, v_req->'subject',
                                  'sql_caller', v_req->>'dedupeKey');
    n := n + 1;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_purge_batch(p_limit integer DEFAULT 2000)
 RETURNS TABLE(batch_no integer, deleted_count bigint, deleted_bytes bigint, cursor_from bigint, cursor_to bigint, remaining_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET enable_seqscan TO 'off'
 SET max_parallel_workers_per_gather TO '0'
 SET lock_timeout TO '2s'
AS $function$
declare
  v_planned bigint;
  v_done    bigint;
  v_from    bigint;
  v_to      bigint;
  v_batch   integer;
  v_deleted bigint;
  v_bytes   bigint;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_kb_purge_batch: p_limit must be 1..5000 (got %) — scripts/sql/the_purge_cannot_take_the_database_down.sql', p_limit;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then
    raise exception 'fn_kb_purge_batch: another purge batch is running — refusing to overlap it';
  end if;

  select sum(l.rows) into v_planned
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.clause = 5 and l.batch_no is null;
  if v_planned is null then
    raise exception 'fn_kb_purge_batch: no census in kb_purge_ledger — run scripts/kb/purge_kb_bulk.mjs, which writes it before the first batch';
  end if;

  select coalesce(max(l.id_to), 0), coalesce(max(l.batch_no), 0), coalesce(sum(l.rows), 0)
    into v_from, v_batch, v_done
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.batch_no is not null;
  v_batch := v_batch + 1;

  perform set_config('qd.export_change_bulk', 'kb_chunks', true);

  with pick as (
    select k.id
      from public.kb_chunks k
      left join public.kb_citation_jurisdiction j on j.citation_md5 = md5(k.citation)
     where k.id > v_from
       and public.fn_kb_purge_clause(k.source_kind, k.category, j.jurisdiction) = 5
       and k.id not in (select split_part(x, ':', 2)::bigint
                          from public.sales_decision_log s, unnest(s.cited) x
                         where x ~ '^kb_chunks:[0-9]+$')            -- clause 2 (a row-id FORMAT, not a meaning)
     order by k.id
     limit p_limit
  ), del as (
    delete from public.kb_chunks k
     using pick p
     where k.id = p.id
    returning k.id, k.source_kind, k.category, octet_length(k.content) as b
  ), rec as (
    insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, bytes, batch_no, id_from, id_to)
    select 'DELETE', 5, d.source_kind, d.category, count(*), sum(d.b), v_batch, v_from, (select max(id) from del)
      from del d
     group by d.source_kind, d.category
    returning rows, bytes, id_to
  )
  select coalesce(sum(r.rows), 0), coalesce(sum(r.bytes), 0), coalesce(max(r.id_to), v_from)
    into v_deleted, v_bytes, v_to
    from rec r;

  return query select v_batch, v_deleted, v_bytes, v_from, v_to,
                      greatest(v_planned - v_done - v_deleted, 0);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_purge_clause(p_source_kind text, p_category text, p_jurisdiction text)
 RETURNS smallint
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select (case
    -- 1. KEEP — QuotesDone-authored (the source kind we wrote, our own category key namespaces, or reasoned ours)
    when p_source_kind in ('qd_kb_pack','company_faq','memory','generated','trade','material','document','library')
      or split_part(coalesce(p_category, ''), ':', 1) in ('cat', 'exec')
      or p_jurisdiction = 'quotesdone' then 1
    -- 2. KEEP — ever cited: a row-id join, applied by the caller (see fn_kb_purge_batch)
    -- 3. KEEP — a UAE or GCC authority
    when p_jurisdiction in ('uae', 'gcc') then 3
    -- 5. DELETE — US law or a US standard (founder instruction 535), or any other foreign body
    when p_jurisdiction in ('us', 'other_foreign') then 5
    -- 4. UNSURE, KEPT — an international standard a UAE document may adopt, or NOT YET REASONED
    else 4 end)::smallint;
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_purge_load()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'wal_bytes',        (select coalesce(sum(w.size), 0)::bigint from pg_ls_waldir() w),
    'active_others',    (select count(*)::int from pg_stat_activity a
                          where a.backend_type = 'client backend' and a.state <> 'idle' and a.pid <> pg_backend_pid()),
    'longest_active_s', (select coalesce(max(extract(epoch from now() - a.query_start)), 0)::int from pg_stat_activity a
                          where a.backend_type = 'client backend' and a.state = 'active' and a.pid <> pg_backend_pid()
                            and a.query not ilike '%fn_kb_purge_load%'),
    'purge_running',    (select count(*)::int from pg_stat_activity a
                          where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.query ilike '%fn_kb_purge_batch(%'),
    'export_running',   exists (select 1 from public.table_export_run r
                                 where r.status = 'running' and r.heartbeat_at > now() - interval '10 minutes'),
    'dubai_time',       to_char(now() at time zone 'Asia/Dubai', 'HH24:MI'));
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_route_activation_blocked(p_catalog_num integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_reasons text[] := '{}';
begin
  select * into r from public.kb_operational_route where catalog_num = p_catalog_num;
  if not found then
    return jsonb_build_object('blocked', true, 'reasons', array['no such route']);
  end if;

  if r.regulatory_coverage_status <> 'confirmed_none'
     and r.regulatory_coverage_status <> 'confirmed_covered' then
    v_reasons := v_reasons || ('regulatory coverage is ' || r.regulatory_coverage_status)::text;
  end if;

  if not exists (select 1 from public.kb_operational_route_map m where m.catalog_num = p_catalog_num) then
    v_reasons := v_reasons || 'no mapped subcategory'::text;
  end if;

  if not exists (select 1 from public.kb_operational_alias a
                  where a.catalog_num = p_catalog_num and a.language = 'ar') then
    v_reasons := v_reasons || 'no Arabic alias'::text;
  end if;

  return jsonb_build_object('blocked', array_length(v_reasons, 1) is not null,
                            'reasons', coalesce(v_reasons, '{}'),
                            'regulatory_coverage_status', r.regulatory_coverage_status,
                            'route', r.catalog_name);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_route_decide(p_text text, p_catalog_num integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_open jsonb; v_cat record; v_rules jsonb; v_blocked boolean;
begin
  -- The categories a route may land on: every catalogue category whose activation is not blocked.
  select coalesce(jsonb_agg(jsonb_build_object('catalog_num', c.num, 'live_slug', c.slug, 'live_name', c.name) order by c.num), '[]'::jsonb)
    into v_open
    from public.catalog_supplier_categories c
   where not coalesce((public.fn_kb_route_activation_blocked(c.num)->>'blocked')::boolean, true);

  if p_catalog_num is null then
    -- NEEDS REASONING. The customer's wording is read by the caller's think() over these categories;
    -- nothing here matches it against an alias.
    return jsonb_build_object(
      'action', 'needs_reasoning', 'catalog_num', null, 'candidates', v_open, 'rules', '[]'::jsonb,
      'reason', 'the customer''s wording is reasoned by the caller (think()) over the activated categories, never matched on words',
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".');
  end if;

  select c.num, c.slug, c.name into v_cat from public.catalog_supplier_categories c where c.num = p_catalog_num;
  v_blocked := coalesce((public.fn_kb_route_activation_blocked(p_catalog_num)->>'blocked')::boolean, true);
  if v_cat.num is null or v_blocked then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'catalog_num', null, 'candidates', v_open, 'rules', '[]'::jsonb,
      'reason', case when v_cat.num is null then 'no such catalogue category' else 'that category is not activated for live use' end,
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rule_id', d.rule_id, 'type', d.rule_type, 'priority', d.priority,
           'when', d.when_json, 'then', d.then_json,
           'requires_human_review', d.requires_human_review,
           'confidence', d.confidence) order by d.priority desc nulls last, d.rule_id), '[]'::jsonb)
    into v_rules
    from (select * from kb_stage.decision_rules dr
           where dr.category_slug in (select m.package_slug from public.kb_operational_route_map m where m.catalog_num = p_catalog_num)
           order by dr.priority desc nulls last, dr.rule_id
           limit 5) d;

  return jsonb_build_object(
    'action', 'route_or_ask_scope_details', 'catalog_num', v_cat.num,
    'candidates', jsonb_build_array(jsonb_build_object('catalog_num', v_cat.num, 'live_slug', v_cat.slug, 'live_name', v_cat.name)),
    'reason', 'the category was reasoned by the caller', 'clarification', null, 'rules', coalesce(v_rules, '[]'::jsonb));
end $function$


CREATE OR REPLACE FUNCTION public.fn_kernel_paid_provider_gate(p_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_switch  boolean;
  v_routes  bigint;
  v_held    bigint;
  v_model   text := nullif(btrim(coalesce(p_model, '')), '');
  v_reg     boolean;
  v_open    timestamptz;
begin
  -- An EMPTY STRING is not a deterministic path, it is a caller that did not say. Denied, with its
  -- own rule name, because "I passed you nothing" and "I am not calling a provider" are different
  -- statements and a gate that conflates them has a hole shaped like a typo.
  if p_model is not null and v_model is null then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'model_unspecified',
      'reason', 'an empty model string is not a deterministic path; pass NULL or ''none'' to declare '
             || 'that no provider call is being made', 'model', p_model);
  end if;

  -- A deterministic path is not a provider call and never was. It is named explicitly rather than
  -- reached by falling off the end of the checks.
  if v_model is null or v_model in ('none', 'none/deterministic') then
    return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
      'rule', 'deterministic_path', 'reason', 'no provider call is being made', 'model', p_model);
  end if;

  -- 1. the explicit switch
  select exists (select 1 from public.app_secrets
                  where key = 'no_paid_ai' and lower(coalesce(value,'')) in ('1','true','yes','on'))
    into v_switch;
  if v_switch then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'no_paid_ai_switch', 'reason', 'app_secrets.no_paid_ai is set; paid inference is off',
      'model', v_model);
  end if;

  -- 2. empty route state is DENIED, not permitted. An absent hold is not a permission — this is the
  --    "what does it print when its input is absent?" case, answered on purpose.
  select count(*) into v_routes from public.llm_route_health;
  if v_routes = 0 then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'empty_route_state',
      'reason', 'llm_route_health holds no rows; with no route state there is no evidence that any '
             || 'route is permitted', 'model', v_model);
  end if;

  -- 3. the founder's hold, on ANY route. He held the whole estate on 15 Aug 2026; holding one route
  --    and leaving the others open would not be what he asked for.
  select count(*) into v_held from public.llm_route_health where open_until is not null and open_until > now();
  if v_held > 0 then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'founder_hold',
      'reason', v_held || ' of ' || v_routes || ' routes are held open-circuit until '
             || (select max(open_until)::text from public.llm_route_health where open_until > now()),
      'held', v_held, 'routes', v_routes, 'model', v_model);
  end if;

  -- 4. the route must be registered and active
  select exists (select 1 from public.model_registry r where r.model_id = v_model and r.active) into v_reg;
  if not v_reg then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_not_registered',
      'reason', 'model ' || v_model || ' is not an active row in model_registry', 'model', v_model);
  end if;

  -- 5. this route's own breaker
  select open_until into v_open from public.llm_route_health where model_id = v_model;
  if v_open is not null and v_open > now() then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_open', 'reason', 'circuit open until ' || v_open::text, 'model', v_model);
  end if;

  return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
    'rule', 'registered_breaker_closed', 'reason', 'switch off, no hold, route registered, breaker closed',
    'model', v_model);
exception
  -- The gate itself failing is the most dangerous case, because it is the one a try/catch upstream
  -- used to swallow. It answers DENIED, in its own voice, rather than throwing into a caller that
  -- might interpret an exception as "carry on".
  when others then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'gate_unreadable',
      'reason', 'the paid-provider gate could not be evaluated: ' || sqlstate || ' ' || sqlerrm,
      'model', p_model);
end $function$


CREATE OR REPLACE FUNCTION public.fn_knowledge_exam_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with recent as (
    select * from knowledge_exam_results where created_at > now() - interval '30 days'
  ),
  per as (
    select agent_key,
      count(*) as examined,
      count(*) filter (where verdict='correct') as correct,
      count(*) filter (where verdict in ('wrong','partial','not_covered')) as gaps,
      count(*) filter (where filled) as filled,
      max(created_at) as last_exam
    from recent group by agent_key
  )
  select jsonb_build_object(
    'overall', jsonb_build_object(
      'question_bank', (select count(*) from knowledge_exam_questions),
      'exams_30d', (select count(*) from recent),
      'agents_examined', (select count(*) from per),
      'gaps_filled_30d', (select count(*) from recent where filled),
      'avg_score', (select round(100.0*count(*) filter (where verdict='correct')/nullif(count(*),0),1) from recent)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'agent_key', agent_key, 'examined', examined, 'correct', correct,
        'score_pct', round(100.0*correct/nullif(examined,0),1),
        'gaps', gaps, 'filled', filled, 'last_exam', last_exam
      ) order by round(100.0*correct/nullif(examined,0),1) asc nulls first) from per), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_knowledge_gaps(p_stale_days integer DEFAULT 14, p_thin_min integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select ca.slug, ca.name, ca.emoji,
      (select count(*) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as items,
      (select max(updated_at) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as last_updated,
      (select min(d.os_key) from os_knowledge_domain d
        where d.domain_key = 'cat:'||ca.slug and d.ownership = 'owns') as owner_os
    from category_agents ca where coalesce(ca.active,true)
  ),
  scored as (
    select slug, name, emoji, items, last_updated, owner_os,
      case when last_updated is null then null else floor(extract(epoch from (now()-last_updated))/86400)::int end as days_stale,
      case when items = 0 then 'missing'
           when last_updated < now() - (p_stale_days||' days')::interval then 'stale'
           when items < p_thin_min then 'thin'
           else 'ok' end as status
    from base
  )
  select jsonb_build_object(
    -- THE POPULATION IS NAMED. 'summary' and 'agents' are the supplier-category PERSONAS
    -- (category_agents, cat:<slug>); the 54 employees are under 'employees'.
    'population', 'category personas (category_agents active)',
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status='ok'),
      'stale', (select count(*) from scored where status='stale'),
      'thin', (select count(*) from scored where status='thin'),
      'missing', (select count(*) from scored where status='missing'),
      'unowned', (select count(*) from scored where owner_os is null),
      'coverage_pct', round(100.0 * (select count(*) from scored where status='ok') / nullif((select count(*) from scored),0), 1)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', emoji, 'items', items, 'owner_os', owner_os,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status
      ) order by case status when 'stale' then 0 when 'thin' then 1 when 'missing' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb),
    'employees', public.fn_employee_knowledge_freshness(30, 1)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_knowledge_provenance_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  -- OWNER. Only when the writer did not name one.
  if NEW.owner_agent is null and coalesce(NEW.agent_key,'') <> '' then
    NEW.owner_agent := case
      when NEW.agent_key like 'cat:%' then 'learning_dev_mgr'
      when NEW.agent_key = '_global'  then 'docs'
      else NEW.agent_key
    end;
  end if;
  if NEW.owner_agent is null then NEW.owner_agent := NEW.agent_key; end if;

  -- CITATION. Each branch reads a reference the writer itself put in the row; anything else is
  -- left NULL here and handled by the fallback below. A source_ref that says "unknown" is worse
  -- than one that is absent, because the check counts it as present — which is exactly why the
  -- fallback now comes after this block instead of before it.
  if NEW.source_ref is null or btrim(NEW.source_ref) = '' then
    NEW.source_ref := case
      -- assets_ingest: content opens 'From company asset "X" (Dropbox: /path)'
      when NEW.topic like 'Asset text: %'
        then 'dropbox_asset:' || coalesce(substring(NEW.content from 'Dropbox: ([^)]+)'),
                                          substring(NEW.topic   from 'Asset text: (.*)'))
      when NEW.topic = 'Company assets (auto-synced from Dropbox)'
        then 'dropbox_asset:manifest'
      -- fn_experience_promote stamps the org_memory id into the topic as [org#123]
      when NEW.topic ~ '\[org#[0-9]+\]'
        then 'org_memory:' || substring(NEW.topic from '\[org#([0-9]+)\]')
      -- trg_ingest_case_lessons: 'Closed-case lesson (RFQ-45)'
      when NEW.topic like 'Closed-case lesson (RFQ-%'
        then 'rfq_case:' || substring(NEW.topic from 'RFQ-([0-9]+)')
      when NEW.topic like 'exam:%'
        then 'knowledge_exam:' || substring(NEW.topic from 'exam:(.*)')
      else null
    end;
  end if;

  -- LAST RESORT, and only now. Nothing above could name a source, so say so honestly.
  if NEW.source_ref is null or btrim(NEW.source_ref) = '' then
    NEW.source_ref := 'unattributed: no provenance was recorded when this item was written';
  end if;

  -- CONFIDENCE, SCORED OFF THE FINAL source_ref. This ran one line after the placeholder was set,
  -- so it matched nothing and fell to 0.50 on every row that had no writer-supplied reference.
  if NEW.confidence is null then
    NEW.confidence := case
      when NEW.source_ref ~* '^(pack|corpus|import|kb_stage|ops_kb_stage|v2026)' then 0.90
      when NEW.source_ref ~* '^authored'     then 0.85
      when NEW.source_ref ~* '^web_research' then 0.70
      when NEW.source_ref ~* '^(knowledge_exam|org_memory|auto_chat|session|dropbox_asset|rfq_case)' then 0.60
      else 0.50 end;
  end if;

  if NEW.supporting_evidence is null then
    NEW.supporting_evidence := 'Basis: ' || NEW.source_ref
      || ' | layer: ' || coalesce(NEW.layer,'unspecified')
      || ' | owner: ' || coalesce(NEW.owner_agent,'unassigned')
      || ' | validation: ' || coalesce(NEW.validation_status,'unvalidated')
      || case when coalesce(NEW.content,'') ~ 'https?://' then ' | the item itself cites at least one URL'
              else ' | the item cites no external source; treat it as internal know-how, not as an authority' end;
  end if;

  return NEW;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_knowledge_staleness_tag(p_review_due date, p_validation_status text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select case
    when coalesce(p_validation_status,'') = 'unsourced'
      then '[UNSOURCED - written from an exam''s own answer, not a primary source; verify before relying on it] '
    when coalesce(p_validation_status,'') = 'stale' or (p_review_due is not null and p_review_due < current_date)
      then '[STALE - review was due '||coalesce(p_review_due::text,'(undated)')||'; verify before relying on it] '
    else '' end;
$function$


CREATE OR REPLACE FUNCTION public.fn_knowledge_text_change_clears_embedding()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if (new.title is distinct from old.title or new.body is distinct from old.body)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_kpi_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_opened int:=0; v_missed int:=0; v_nodata int:=0; v_title text; v_task bigint;
  v_remediated int:=0; v_trained int:=0; v_rem bigint; v_comp text; v_tr jsonb; v_agent text;
begin
  for r in select * from fn_kpi_scoreboard() loop
    if r.verdict='NO DATA' then v_nodata:=v_nodata+1; continue; end if;
    if r.verdict<>'MISSED' then continue; end if;
    v_missed := v_missed+1;
    v_title := 'KPI missed: '||r.metric||' ('||r.agent_key||')';
    if exists (select 1 from org_tasks where title=v_title and status<>'done') then continue; end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, objective_id)
    values (coalesce(r.department,'exec'), v_title,
      'Owner: '||r.agent_key||'. Target '||coalesce(r.target::text,'?')||' '||coalesce(r.unit,'')||
      ', actual '||coalesce(r.actual::text,'?')||' ('||coalesce(r.attainment::text,'?')||'% of target), cadence '||coalesce(r.cadence,'?')||
      '. Serves company goal: '||coalesce(r.serves_goal,'unassigned')||
      '. Diagnose the cause and either close the gap or propose a revised target with evidence.',
      'proposed','advisory', false, 'recommend',
      -- the objective this KPI serves, resolved precisely from serves_goal -> department_objective
      (select o.id from public.department_objective o
        where o.active and o.status='active' and o.dept_key = coalesce(r.department,'exec')
          and coalesce(r.serves_goal,'') <> '' and o.goal_key = r.serves_goal
        order by o.id limit 1))
    returning id into v_task;

    perform fn_outcome_open(
      p_actor           => r.agent_key,
      p_decision        => 'Close the gap on: '||r.metric,
      p_subject_type    => 'org_task',
      p_subject_id      => v_task::text,
      p_expected_kpi_id => r.kpi_id,
      p_rationale       => 'KPI missed at '||coalesce(r.attainment::text,'?')||'% of target. Opened automatically by the weekly KPI review.',
      p_direction       => case when r.unit='percent_max' then 'down' else 'up' end,
      p_measure_after   => case when r.cadence='weekly' then interval '14 days' else interval '35 days' end
    );

    v_comp := coalesce(nullif(r.serves_goal,''), r.metric);
    v_agent := coalesce(public.fn_org_agent_resolve(r.agent_key), r.agent_key);
    if exists (select 1 from org_agents o where o.agent_key = v_agent and o.active)
       and not exists (select 1 from agent_remediation ar
                    where ar.agent_key = v_agent and ar.failure_class = 'kpi_miss'
                      and coalesce(ar.detail->>'metric','') = r.metric and ar.status = 'open') then
      v_rem := fn_open_remediation(v_agent, 'kpi_miss', v_comp,
        jsonb_build_object('metric', r.metric, 'kpi_id', r.kpi_id, 'attainment', r.attainment,
                           'target', r.target, 'actual', r.actual, 'serves_goal', r.serves_goal,
                           'org_task_id', v_task, 'owner_key', r.agent_key, 'source', 'fn_kpi_review'));
      v_remediated := v_remediated + 1;
      begin
        v_tr := fn_assign_training(v_agent, null, 'practice', 3);
        v_trained := v_trained + coalesce((v_tr->>'assigned')::int, 0);
      exception when others then null;
      end;
    end if;

    v_opened := v_opened+1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('kpi_review', now(), now(), 'ok',
          jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata,
                             'remediations_opened',v_remediated,'practice_assigned',v_trained),
          'Weekly KPI review: '||v_missed||' missing target, '||v_opened||' task(s) + outcome record(s) opened, '
          ||v_remediated||' remediation(s) opened, '||v_trained||' practice case(s) assigned, '||v_nodata||' with no data.');
  return jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata,
                            'remediations_opened',v_remediated,'practice_assigned',v_trained);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kpi_scoreboard()
 RETURNS TABLE(kpi_id bigint, agent_key text, department text, kpi text, metric text, cadence text, serves_goal text, target numeric, unit text, actual numeric, attainment numeric, verdict text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v numeric; t numeric;
begin
  for r in
    select k.id, k.agent_key, a.department, k.kpi, k.metric, k.cadence,
           k.serves_goal, k.target_value, k.unit, k.measure_sql
    from employee_kpi k
    left join org_agents a on a.agent_key = k.agent_key
    where k.active
    order by a.department nulls last, k.agent_key, k.id
  loop
    v := null;
    begin
      if r.measure_sql is not null then execute r.measure_sql into v; end if;
    exception when others then v := null;
    end;

    t := null;
    begin
      t := r.target_value::numeric;
    exception when others then t := null;
    end;

    kpi_id := r.id; agent_key := r.agent_key; department := r.department;
    kpi := r.kpi; metric := r.metric; cadence := r.cadence;
    serves_goal := r.serves_goal; target := t; unit := r.unit; actual := v;

    if v is null or t is null then
      attainment := null;
    elsif t = 0 then
      -- A ZERO TARGET IS A TARGET (11 Aug 2026). "Zero defects" is the commonest shape a quality
      -- KPI takes - reveal invoices with no payment record, suppliers gone quiet, categories off
      -- the specification, notifications still unsent - and t = 0 short-circuited into
      -- attainment null, which the verdict below then reported as 'NO TARGET'. Four active,
      -- measured KPIs were being told they had no target when zero IS the target, and the four
      -- were exactly the ones about defects.
      attainment := case when v <= 0 then 100.0 else 0.0 end;
    elsif r.unit = 'percent_max' then
      attainment := round(least(100.0, 100.0 * t / nullif(v,0)), 1);
    else
      attainment := round(100.0 * v / t, 1);
    end if;

    verdict := case
      when v is null then 'NO DATA'
      when attainment is null then 'NO TARGET'
      when attainment >= 100 then 'MET'
      when attainment >= 90 then 'NEAR'
      else 'MISSED' end;

    return next;
  end loop;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_language_mismatch(p_lang text, p_text text, p_allow text[] DEFAULT '{}'::text[])
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t text := coalesce(p_text, ''); a text; w text;
begin
  foreach a in array coalesce(p_allow, '{}') loop
    if coalesce(btrim(a), '') <> '' then t := replace(t, a, ' '); end if;
  end loop;
  t := regexp_replace(t, 'https?://\S+', ' ', 'gi');
  t := regexp_replace(t, '\S+@\S+', ' ', 'g');
  t := regexp_replace(t, 'QD-[A-Za-z0-9-]+', ' ', 'g');
  t := regexp_replace(t, '\m(QuotesDone|AED|PDF|Stripe|WhatsApp|quotesdone\.com)\M', ' ', 'gi');
  -- An all-capitals code (SPC, BTU, CCTV, IP65, BS EN) is a standard or a product code, not English prose.
  t := regexp_replace(t, '\m[A-Z][A-Z0-9]{1,5}\M', ' ', 'g');
  if p_lang = 'ar' then
    if t !~ '[؀-ۿ]' then return 'no Arabic at all'; end if;
    w := substring(t from '[A-Za-z]{2,}(?:\s+[A-Za-z]{2,})*');
    if w is not null then return 'English inside Arabic: ' || left(w, 60); end if;
  else
    if t ~ '[؀-ۿ]' then return 'Arabic inside English: ' || left(substring(t from '[؀-ۿ][؀-ۿ\s]*'), 60); end if;
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_lead_reclassify_tick(p_limit integer DEFAULT 20, p_only bigint[] DEFAULT NULL::bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_gate text; v_cap int; v_today int; v_room int; v_n int := 0; l record; v_short jsonb; v_opts jsonb; v_day timestamptz;
begin
  select value into v_gate from public.app_secrets where key = 'lead_reclassify_backfill';
  if coalesce(btrim(v_gate), '') <> 'go' then
    return jsonb_build_object('ran', false, 'reason', 'gate_off', 'gate_key', 'lead_reclassify_backfill');
  end if;
  -- Nothing is filed while the model hold is on: a question filed under the hold would only wait 48 hours and
  -- land in the sales engineer's queue as a pending item, 95 a day. The backfill runs only when it can reason.
  if coalesce(public.fn_kernel_paid_provider_gate('hold-probe/not-a-model')->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return jsonb_build_object('ran', false, 'reason', 'model_hold');
  end if;
  begin select btrim(value)::int into v_cap from public.app_secrets where key = 'lead_reclassify_daily_cap';
  exception when others then v_cap := null; end;
  v_cap := greatest(0, coalesce(v_cap, 95));
  v_day := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  select count(*) into v_today from public.reasoning_held_question where surface = 'lead_trade.classify' and created_at >= v_day;
  v_room := greatest(0, least(greatest(coalesce(p_limit, 20), 0), v_cap - v_today));
  if v_room = 0 then
    return jsonb_build_object('ran', false, 'reason', 'daily_cap', 'cap', v_cap, 'filed_today', v_today);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.code, 'meaning', t.label) order by t.sort, t.code), '[]'::jsonb)
         || jsonb_build_array(jsonb_build_object('id', 'none', 'meaning', 'no trade in this list is what the company supplies or performs'))
    into v_opts from public.taxonomy_trade t where t.active;
  for l in
    select x.* from public.leads x
     where (p_only is null or x.id = any (p_only))   -- p_only: a named set (the probe's ZZ DEMO leads); null = every lead
       and not exists (select 1 from public.lead_trade_class c where c.lead_id = x.id)
       -- a question still waiting, or one that failed within the day, is not asked again; one whose answer could not be
       -- stored (fn_reason_apply_lead_trade__classify puts it back to held) is waiting again, so it is skipped here too
       and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'lead_trade:' || x.id
                         and (h.status = 'held' or (h.status = 'failed' and coalesce(h.last_attempt_at, h.created_at) > now() - interval '24 hours')))
     order by (coalesce(x.approval_status, '') = 'approved') desc, x.id   -- approved suppliers first: they are the live pools
     limit v_room
  loop
    v_short := '[]'::jsonb;
    if l.embedding_gte is not null then
      select coalesce(jsonb_agg(distinct z.trade_code), '[]'::jsonb) into v_short
        from (select s.trade_code from public.taxonomy_trade_service s
               where s.active and s.embedding_gte is not null
               order by s.embedding_gte <=> l.embedding_gte limit 8) z;
    end if;
    perform public.fn_reason_route_ask('sales_engineer', 'lead_trade.classify',
      concat_ws(E'\n',
        'Company: ' || l.company_name,
        'Licence authority: ' || nullif(btrim(coalesce(l.license_authority, '')), ''),
        'Stated categories (the supplier''s or a directory''s free text; may name the company, not its trade): ' || nullif(btrim(coalesce(l.categories, '')), ''),
        'Sub type: ' || nullif(btrim(coalesce(l.sub_type, '')), ''),
        'Description: ' || left(nullif(btrim(coalesce(l.description, '')), ''), 1500),
        'Website: ' || nullif(btrim(coalesce(l.website, '')), ''),
        case when jsonb_array_length(v_short) > 0
             then 'Nearest trades by meaning (a hint to check, never the answer): ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_short) x) end,
        'Which trade in the taxonomy does this company supply or perform? Answer none if the record does not say.'),
      v_opts, jsonb_build_object('lead_id', l.id, 'shortlist', v_short), 'lead_trade:' || l.id);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ran', true, 'filed', v_n, 'cap', v_cap, 'filed_today', v_today + v_n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_collaboration_hold_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if OLD.collaboration_hold_at is not null then
    if NEW.collaboration_hold_at is null and coalesce(current_setting('app.collaboration_hold_lift', true), '') <> 'founder' then
      raise exception 'A supplier matching hold is lifted by the founder only, in a working session, with his founder_instruction (fn_supplier_collaboration_hold_lift). No agent path may lift it (founder_instruction #160).';
    end if;
    -- Any other writer that clears matching_blocked (a document restore, an unban) leaves the hold in force.
    if NEW.collaboration_hold_at is not null and (NEW.matching_blocked is distinct from true or NEW.matching_block_reason is distinct from 'collaboration_hold') then
      NEW.matching_blocked := true; NEW.matching_block_reason := 'collaboration_hold';
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_derive_owner_email_verified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Only when an address is newly attached or changed. A later edit of an unrelated column must
  -- not re-run this, and it must never REVOKE a verification an OTP sign-in has already granted.
  if NEW.claimed_by is null then return NEW; end if;
  if TG_OP = 'UPDATE' and NEW.claimed_by is not distinct from OLD.claimed_by then return NEW; end if;
  if coalesce(NEW.owner_email_verified, false) then return NEW; end if;

  if exists (
    select 1 from email_verifications
    where email = lower(NEW.claimed_by)
      and purpose = 'login'
      and used_at is not null
  ) then
    NEW.owner_email_verified := true;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_exception_invariant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days   int := public.fn_supplier_exception_days();
  v_now    timestamptz := now();
  v_needs  boolean;
  v_isopen boolean;
begin
  v_needs  := coalesce(new.approval_status, '') = 'action_required';
  v_isopen := new.exception_opened_at is not null and new.exception_closed_at is null;

  if v_needs and not v_isopen then
    -- (a) OPEN IT HERE. supplier_api commits the status first and opens the window afterwards
    -- inside a try/catch that swallows failures; if that RPC never lands, the supplier is stranded
    -- in a state no sweep can see. Opening it in the same statement that sets the status removes
    -- the ordering problem entirely, whatever the caller does.
    new.exception_opened_at        := v_now;
    new.exception_due_at           := v_now + make_interval(days => v_days);
    new.exception_reminders        := 0;
    new.exception_last_reminder_at := null;
    new.exception_closed_at        := null;
    new.exception_outcome          := null;

  elsif v_needs and v_isopen and new.exception_due_at is null then
    -- Open but with no deadline: same invisibility, different route in.
    new.exception_due_at := v_now + make_interval(days => v_days);

  elsif (not v_needs) and v_isopen then
    -- (b)(c) CLOSE IT HERE. An approved or verified supplier must not carry an open window: it is
    -- invisible to every sweep, and it poisons the NEXT demotion with a stale due date.
    new.exception_closed_at := v_now;
    new.exception_outcome   := case
      when coalesce(new.approval_status,'') in ('approved','verified') or new.verified is true then 'resolved'
      when coalesce(new.approval_status,'') = 'rejected' then coalesce(new.exception_outcome, 'closed_rejected')
      else 'closed_status_change' end;
    if new.exception_outcome = 'resolved' then new.licence_gate_reason := null; end if;
  end if;

  -- Backstop. If the branches above ever stop covering a case, fail loudly here rather than
  -- writing a row that no queue can see. A CHECK constraint cannot express this (it depends on
  -- two column groups at once) and would also have blocked the legacy rows this trigger repairs.
  if (coalesce(new.approval_status,'') = 'action_required')
     <> (new.exception_opened_at is not null and new.exception_closed_at is null) then
    raise exception
      'leads %: exception window and approval_status disagree (status=%, open=%). An open window '
      'must mean action_required and nothing else — otherwise the supplier is in a state no sweep '
      'and no view can see.', new.id, new.approval_status,
      (new.exception_opened_at is not null and new.exception_closed_at is null)
      using errcode = 'check_violation';
  end if;

  if coalesce(new.approval_status,'') = 'action_required' and new.exception_due_at is null then
    raise exception 'leads %: action_required with no exception_due_at — both sweep loops skip it.', new.id
      using errcode = 'check_violation';
  end if;

  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_mandatory_item_landed_reverifies()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_sales_engineer_verifies_supplier(new.id, 'mandatory_item_changed');
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_mandatory_six_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_missing text[] := public.fn_supplier_mandatory_six(new);
begin
  if cardinality(v_missing) = 0 then return new; end if;
  if tg_op = 'UPDATE' and (coalesce(old.approval_status, '') = 'approved' or coalesce(old.verified, false)) then
    -- Already approved and an item is gone (or was never there: nothing re-checked approvals before).
    new.approval_status := 'action_required';
    new.verified := false;
    new.licence_gate_reason := v_missing[1];
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_verification', 'auto_done', 'medium',
            'Supplier demoted to action_required (' || array_to_string(v_missing, ', ') || ') — ' || left(coalesce(new.company_name, 'supplier #' || new.id), 120),
            'No action required. A mandatory item is missing from an approved supplier, so the approval was withdrawn and the 14-day window opened. The supplier is approved again automatically when the item is back.',
            jsonb_build_object('supplier_id', new.id, 'decision', 'demoted', 'missing', v_missing, 'source', 'trg_leads_e0_mandatory_six_gate'),
            'leads', new.id::text);
    return new;
  end if;
  raise exception 'leads %: a supplier whose mandatory fields are incomplete cannot be verified (missing: %)',
    new.id, array_to_string(v_missing, ', ') using errcode = 'check_violation';
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_sanctioned_identity_cannot_re_register()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_banned bigint;
begin
  v_banned := public.fn_sanctioned_identity(new.company_name, new.trade_license_no,
                coalesce(nullif(btrim(new.claimed_by), ''), nullif(btrim(new.email), '')), new.id);
  if v_banned is not null then
    raise exception 'SANCTIONED_PARTY_BLOCKED: this company name, trade licence number or account e-mail belongs to lead #%, which carries a confirmed sanctions ban. It cannot be registered again (founder instruction 516, 18 Sep 2026).', v_banned
      using errcode = '23514';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_leads_sanctioned_row_is_permanent()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'DELETE' then
    if public.fn_is_sanctioned_lead(old.id) then
      raise exception 'SANCTIONS_RECORD_IS_SEALED: lead #% carries a confirmed sanctions ban; deleting it would cascade away its supplier_screening_hit rows. The record is retained (founder instruction 516).', old.id
        using errcode = '42501';
    end if;
    return old;
  end if;
  -- UPDATE: the ban is permanent. Everything else about the row stays editable, so the CEO can
  -- annotate it and the screen can keep writing to it.
  if public.fn_is_sanctioned_lead(new.id)
     and (coalesce(new.banned, false) = false or coalesce(new.matching_blocked, false) = false) then
    raise exception 'SANCTIONS_BAN_IS_PERMANENT: lead #% is banned on a confirmed sanctions hit and cannot be un-banned or re-admitted to matching.', new.id
      using errcode = '42501';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_lesson_clusters(p_limit integer DEFAULT 6, p_floor real DEFAULT 0.84)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_seat text; seed record; v_ids bigint[]; v_used bigint[] := '{}'; v_out jsonb := '[]'::jsonb; v_key text; v_n int := 0;
begin
  select coalesce(array_agg(x), '{}') into v_used from public.seat_lesson_cluster c, unnest(c.case_ids) x;
  foreach v_seat in array array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing'] loop
    v_n := 0;   -- per seat: one busy seat never starves the others of their lessons
    for seed in
      select m.id, m.embedding from public.seat_case_memory m
       where m.seat = v_seat and m.outcome is not null and m.embedding is not null
         and m.updated_at > now() - interval '90 days' and m.id <> all(v_used)
       order by m.updated_at desc limit 200
    loop
      exit when v_n >= greatest(1, least(p_limit, 20));
      continue when seed.id = any(v_used);
      select array_agg(id) into v_ids from (
        select m.id from public.seat_case_memory m
         where m.seat = v_seat and m.outcome is not null and m.embedding is not null and m.id <> all(v_used)
           and 1 - (m.embedding <=> seed.embedding) >= p_floor
         order by m.embedding <=> seed.embedding limit 12) t;
      if cardinality(v_ids) >= 3 then
        v_key := v_seat || ':' || md5(array_to_string((select array_agg(x order by x) from unnest(v_ids) x), ','));
        insert into public.seat_lesson_cluster (cluster_key, seat, case_ids) values (v_key, v_seat, v_ids) on conflict do nothing;
        v_used := v_used || v_ids;
        v_n := v_n + 1;
        v_out := v_out || jsonb_build_object('seat', v_seat, 'cluster_key', v_key, 'cases',
          (select jsonb_agg(jsonb_build_object('case_id', m.id, 'case_kind', m.case_kind, 'situation', left(m.situation, 500),
                   'decision', left(m.decision, 300), 'outcome', left(m.outcome, 300), 'finalised', m.finalised,
                   'correction', m.correction) order by m.id)
             from public.seat_case_memory m where m.id = any(v_ids)));
      end if;
    end loop;
  end loop;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_lesson_clusters_to_reason(p_min_cases integer DEFAULT 5, p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('seat', c.seat, 'cluster_key', c.cluster_key, 'cases',
           (select jsonb_agg(jsonb_build_object('case_id', m.id, 'case_kind', m.case_kind, 'situation', left(m.situation, 500),
                    'decision', left(m.decision, 300), 'outcome', left(m.outcome, 300), 'finalised', m.finalised,
                    'correction', m.correction) order by m.id)
              from public.seat_case_memory m where m.id = any(c.case_ids)))), '[]'::jsonb)
    from (select * from public.seat_lesson_cluster c
           where c.candidate_id is null and cardinality(c.case_ids) >= greatest(3, coalesce(p_min_cases, 5))
             and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'lesson:' || c.cluster_key)
           order by cardinality(c.case_ids) desc, c.filed_at
           limit greatest(1, least(coalesce(p_limit, 3), 10))) c;
$function$


CREATE OR REPLACE FUNCTION public.fn_lesson_embed_write(p_id bigint, p_embedding vector)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.reasoning_knowledge_candidate set embedding_gte = p_embedding where id = p_id and embedding_gte is null;
  update public.agent_knowledge set embedding_gte = p_embedding, updated_at = now() where source_ref = 'lesson:' || p_id and embedding_gte is null;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_lesson_unembedded(p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'finding', r.finding)), '[]'::jsonb)
    from (select r.id, r.finding from public.reasoning_knowledge_candidate r
           join public.seat_lesson_cluster c on c.candidate_id = r.id
          where r.embedding_gte is null and r.status <> 'rejected' order by r.id limit greatest(1, least(p_limit, 20))) r
$function$


CREATE OR REPLACE FUNCTION public.fn_licence_ask_close_for_lead(p_lead_id bigint, p_source text, p_source_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_closed int;
begin
  if p_lead_id is null then
    return jsonb_build_object('ok', true, 'closed', 0,
      'reason', 'no lead, so no ask is answered. A document held for an unmatched sender has not arrived for anybody yet.');
  end if;

  -- ANSWERED, not sent. The distinction the original function was built around and which this
  -- preserves: an ask closes when a document ARRIVES, never when a message goes out.
  update public.licence_renewal_ask
     set answered_at = now(),
         answered_by_intake = case when p_source = 'whatsapp' then p_source_id else answered_by_intake end
   where lead_id = p_lead_id and answered_at is null;
  get diagnostics v_closed = row_count;

  return jsonb_build_object('ok', true, 'closed', v_closed, 'lead_id', p_lead_id, 'source', p_source,
    'note', 'Every open renewal ask for this supplier is answered by the document that arrived, whichever door it came through.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_licence_ask_close_on_intake(p_intake_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_i record;
begin
  select * into v_i from public.wa_document_intake where id = p_intake_id;
  if not found or v_i.lead_id is null or v_i.classified_as <> 'licence' or not v_i.attached then
    return jsonb_build_object('ok', true, 'closed', 0,
      'reason', 'Not an attached licence for a known lead, so no renewal ask is answered by it.');
  end if;
  return public.fn_licence_ask_close_for_lead(v_i.lead_id, 'whatsapp', p_intake_id);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_licence_expiry_sweep(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r          record;
  v_band     text;
  v_days     int;
  v_planned  int := 0;
  v_email    int := 0;
  v_wa       int := 0;
  v_blocked  int := 0;
  v_rows     jsonb := '[]'::jsonb;
  v_subject  text;
  v_body     text;
  v_note     bigint;
  v_twin     bigint;
  v_twin_st  text;
  v_twin_err text;
  v_dest     text;
begin
  for r in
    select l.id, l.company_name, l.email, l.phone_e164, l.license_expiry, l.license_doc_path,
           (l.license_expiry - (now() at time zone 'Asia/Dubai')::date) as days_left
      from public.leads l
     where l.license_expiry is not null
       and l.license_expiry <= (now() at time zone 'Asia/Dubai')::date + 30
       and coalesce(l.banned, false) = false
     order by l.license_expiry
     limit 500
  loop
    v_days := r.days_left;
    v_band := case
      when v_days < 0   then 'expired'
      when v_days <= 7  then 't_minus_7'
      when v_days <= 14 then 't_minus_14'
      else                   't_minus_30' end;
    v_planned := v_planned + 1;
    v_twin := null; v_twin_st := null; v_twin_err := null;
    -- Where a WhatsApp twin would go: only a number the supplier confirmed, never the raw phone.
    v_dest := public.fn_whatsapp_destination('supplier', null, r.id, r.email);

    v_subject := case when v_days < 0
      then 'Your trade licence has expired'
      else 'Your trade licence expires in ' || v_days || ' days' end;

    v_body := 'Dear ' || coalesce(r.company_name, 'Supplier') || ',' || chr(10) || chr(10)
           || case when v_days < 0
                then 'The trade licence we hold for you expired on ' || to_char(r.license_expiry, 'DD Mon YYYY')
                  || '. Until we have a valid one we cannot include you in new requests.'
                else 'The trade licence we hold for you expires on ' || to_char(r.license_expiry, 'DD Mon YYYY')
                  || ', which is ' || v_days || ' days from now.' end
           || chr(10) || chr(10)
           || 'Please send us the renewed copy. A clear photograph is fine, a PDF is better. '
           || 'You can reply to this email with it attached, or upload it in the Documents tab of your '
           || 'supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10)
           || 'Nothing else is needed and there is no charge.' || chr(10) || chr(10)
           || 'QuotesDone';

    -- EMAIL. Always attempted when we hold an address. Addressed to the supplier role so the
    -- language trigger and trg_wa_fanout both see who it is for.
    if coalesce(btrim(r.email), '') <> '' then
      if not p_dry_run then
        insert into public.licence_renewal_ask
          (lead_id, band, expiry_date, days_to_expiry, channel, sent)
        values (r.id, v_band, r.license_expiry, v_days, 'email', false)
        on conflict (lead_id, expiry_date, band, channel) do nothing;

        if found then
          insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, lead_id)
          values ('licence_renewal', 'licence_expiry', r.email, 'supplier', v_subject, v_body, 'queued', 'email', r.id)
          returning id into v_note;

          update public.licence_renewal_ask
             set sent = true, notification_id = v_note
           where lead_id = r.id and expiry_date = r.license_expiry and band = v_band and channel = 'email';

          -- The fan-out has already run (AFTER INSERT); its twin is the WhatsApp ask.
          -- Its status is whatever the BEFORE triggers made of it (queued, or captured/skipped with a reason).
          select n.id, n.status, n.last_error into v_twin, v_twin_st, v_twin_err from public.notifications n
           where n.lead_id = r.id and n.type = 'licence_renewal' and n.channel = 'whatsapp'
             and n.created_at >= now()
           order by n.id desc limit 1;
        end if;
      end if;
      v_email := v_email + 1;
    end if;

    -- WHATSAPP. The twin of the email, to the confirmed number, on the approved supplier_doc_expiry
    -- template. No confirmed number is recorded as the reason, never hidden.
    if v_twin is not null then
      if v_twin_st = 'queued' then v_wa := v_wa + 1; else v_blocked := v_blocked + 1; end if;
      insert into public.licence_renewal_ask
        (lead_id, band, expiry_date, days_to_expiry, channel, sent, notification_id, blocked_reason)
      values (r.id, v_band, r.license_expiry, v_days, 'whatsapp', v_twin_st = 'queued', v_twin,
              case when v_twin_st <> 'queued' then left(coalesce(v_twin_err, 'twin ' || v_twin_st), 500) end)
      on conflict (lead_id, expiry_date, band, channel) do nothing;
    elsif p_dry_run and v_dest is not null and coalesce(btrim(r.email), '') <> '' then
      v_wa := v_wa + 1;
    elsif coalesce(btrim(r.phone_e164), '') <> '' or v_dest is not null then
      v_blocked := v_blocked + 1;
      if not p_dry_run then
        insert into public.licence_renewal_ask
          (lead_id, band, expiry_date, days_to_expiry, channel, sent, blocked_reason)
        values (r.id, v_band, r.license_expiry, v_days, 'whatsapp', false,
                case when v_dest is null
                     then 'no confirmed WhatsApp number on file (an unverified number is never used)'
                     else 'no email was queued this run, so there was nothing to twin' end)
        on conflict (lead_id, expiry_date, band, channel) do nothing;
      end if;
    end if;

    if jsonb_array_length(v_rows) < 10 then
      v_rows := v_rows || jsonb_build_object(
        'lead_id', r.id, 'company', r.company_name, 'expiry', r.license_expiry,
        'days_left', v_days, 'band', v_band,
        'email', case when coalesce(btrim(r.email),'')<>'' then 'queued' else 'no address held' end,
        'whatsapp', case when v_dest is not null then 'queued to the confirmed number' else 'no confirmed number' end);
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'dry_run', p_dry_run,
    'licences_within_30_days', v_planned,
    'email_asks', v_email,
    'whatsapp_asks_sent', v_wa,
    'whatsapp_asks_blocked', v_blocked,
    'whatsapp_status', 'open to confirmed numbers: the email is twinned by trg_wa_fanout and sent on the approved supplier_doc_expiry template',
    'sample', v_rows,
    'note', case when p_dry_run
      then 'Dry run. Nothing was queued and nothing was written. Call with p_dry_run => false to act.'
      else 'Asks queued. Each is closed only when a replacement document actually arrives, never when a message is sent.' end
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_line_spec_reading_get(p_keys text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(reading_key, found), '{}'::jsonb) from public.line_spec_reading where reading_key = any (p_keys);
$function$


CREATE OR REPLACE FUNCTION public.fn_line_spec_reading_put(p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  insert into public.line_spec_reading (reading_key, found)
  select r->>'key', coalesce(r->'found', '{}'::jsonb) from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where r->>'key' ~ '^[0-9a-f]{64}$' and jsonb_typeof(coalesce(r->'found', '{}'::jsonb)) = 'object'
  on conflict (reading_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_llm_cache_lookup(p_key text, p_embedding vector DEFAULT NULL::vector, p_task_class text DEFAULT NULL::text, p_min_similarity numeric DEFAULT 0.95)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_sim numeric;
begin
  -- 1. exact
  select * into r from llm_cache
   where cache_key = p_key and (expires_at is null or expires_at > now()) limit 1;
  if found then
    update llm_cache set hits = hits + 1, last_hit_at = now() where cache_key = r.cache_key;
    return jsonb_build_object('hit', true, 'kind', 'exact', 'response', r.response,
                              'model', r.model_used, 'similarity', 1.0);
  end if;

  -- 2. semantic. Deliberately scoped to the same task_class: a research answer must
  -- never be served to a classification prompt just because they read alike.
  if p_embedding is not null then
    select c.*, 1 - (c.embedding_gte <=> p_embedding) as sim into r
      from llm_cache c
     where c.embedding_gte is not null
       and (c.expires_at is null or c.expires_at > now())
       and (p_task_class is null or c.task_class is not distinct from p_task_class)
     order by c.embedding_gte <=> p_embedding
     limit 1;
    if found then
      v_sim := round((r.sim)::numeric, 4);
      if v_sim >= p_min_similarity then
        update llm_cache set hits = hits + 1, last_hit_at = now() where cache_key = r.cache_key;
        return jsonb_build_object('hit', true, 'kind', 'semantic', 'response', r.response,
                                  'model', r.model_used, 'similarity', v_sim);
      end if;
    end if;
  end if;

  return jsonb_build_object('hit', false);
end $function$


CREATE OR REPLACE FUNCTION public.fn_llm_cache_store(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer, p_embedding vector DEFAULT NULL::vector, p_saved_usd numeric DEFAULT 0)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  insert into llm_cache (cache_key, fn, task_class, model_used, response, prompt_hash,
                         expires_at, embedding_gte, saved_usd)
  values (p_key, p_fn, p_task_class, p_model, p_response, p_key,
          now() + make_interval(mins => greatest(coalesce(p_ttl_minutes,60),1)), p_embedding, coalesce(p_saved_usd,0))
  on conflict (cache_key) do update set response = excluded.response, model_used = excluded.model_used,
    expires_at = excluded.expires_at, embedding_gte = coalesce(excluded.embedding_gte, llm_cache.embedding_gte);
$function$


CREATE OR REPLACE FUNCTION public.fn_llm_log(p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text, p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean, p_cache_key text, p_latency_ms integer, p_ok boolean, p_confidence numeric DEFAULT NULL::numeric, p_cached_in integer DEFAULT 0, p_cache_write integer DEFAULT 0, p_generation_id text DEFAULT NULL::text, p_cost_usd_reported numeric DEFAULT NULL::numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cr numeric; v_cw numeric;
        v_cheaper boolean := false; v_reason text; v_alt text; v_class text;
        v_plain int; v_read int; v_write int;
        v_alt_model text; v_alt_rate numeric; v_used_rate numeric;
        v_seat text; v_seat_basis text := 'unattributed';
begin
  v_class := coalesce(nullif(trim(coalesce(p_task_class,'')), ''), case
    when p_fn ~* 'agent_brain|dept_plan|exec_agents|reflect|conductor'   then 'agent_reasoning'
    when p_fn ~* 'cos_execute|secretary|chief'                            then 'chief_of_staff_decision'
    when p_fn ~* 'knowledge|kb_|canon_eval|research|exam'                 then 'knowledge_research'
    when p_fn ~* 'extract|parse|ocr'                                      then 'document_extraction'
    when p_fn ~* 'classif|categor|intent|route'                           then 'category_classification'
    when p_fn ~* 'draft|content|blog|marketing|social'                    then 'content_drafting'
    when p_fn ~* 'quote|rfq|supplier|procure'                             then 'procurement_reasoning'
    else 'general_drafting' end);

  -- WHO SPENT IT. Declaration first, standing binding second, honest silence third.
  if nullif(btrim(coalesce(p_agent,'')),'') is not null
     and exists (select 1 from public.org_agents a where a.agent_key = btrim(p_agent)) then
    v_seat := btrim(p_agent); v_seat_basis := 'declared';
  else
    select b.seat into v_seat from public.llm_seat_binding b where b.fn = p_fn;
    if v_seat is not null then v_seat_basis := 'bound'; else v_seat_basis := 'unattributed'; end if;
  end if;

  v_read  := greatest(coalesce(p_cached_in,0), 0);
  v_write := greatest(coalesce(p_cache_write,0), 0);
  v_plain := greatest(coalesce(p_prompt_tokens,0) - v_read - v_write, 0);

  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok, cache_read_aed_per_mtok, cache_write_aed_per_mtok
      into v_in, v_out, v_cr, v_cw
      from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( v_plain/1000000.0 * v_in
                     + v_read /1000000.0 * coalesce(v_cr, v_in * 0.10)
                     + v_write/1000000.0 * coalesce(v_cw, v_in * 1.25)
                     + coalesce(p_output_tokens,0)/1000000.0 * v_out, 6);
    end if;
  end if;

  select deterministic_alternative into v_alt from model_policy where task_class = v_class;
  if v_alt is not null and v_alt <> '' then
    v_cheaper := true; v_reason := 'A deterministic path exists for this task class: ' || v_alt;
  elsif not coalesce(p_cached,false) then
    select mr.model, mr.in_aed_per_mtok into v_alt_model, v_alt_rate
      from model_rate mr
     where mr.in_aed_per_mtok is not null
     order by mr.in_aed_per_mtok asc
     limit 1;
    select mr.in_aed_per_mtok into v_used_rate from model_rate mr where mr.model = p_model;
    if v_alt_model is not null and v_used_rate is not null
       and v_alt_rate * 2 <= v_used_rate then
      v_cheaper := true;
      v_reason := v_alt_model || ' costs ' || round(v_used_rate / nullif(v_alt_rate,0), 1)
               || 'x less on input than ' || p_model
               || ' (' || v_alt_rate || ' vs ' || v_used_rate || ' AED/Mtok). '
               || 'Whether it is good enough for this task class is a policy decision, not a fact - '
               || 'this flag is the question, not the answer.';
    end if;
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because,
    tier, prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
    could_be_cheaper, cheaper_reason, ok, confidence, cached_in_tokens, cache_write_tokens,
    generation_id, cost_usd_reported, seat, seat_basis)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true),
    case when p_confidence is null then null
         when p_confidence >= 0 and p_confidence <= 1   then p_confidence
         when p_confidence > 1  and p_confidence <= 100 then round(p_confidence / 100.0, 4)
         else null end,
    v_read, v_write,
    nullif(btrim(coalesce(p_generation_id,'')),''), p_cost_usd_reported, v_seat, v_seat_basis)
  -- The generation id is unique. A retried write of the SAME provider charge must not create a
  -- second row that the reconciliation would then count twice.
  on conflict (generation_id) where generation_id is not null do nothing;

  return v_cost;
end $function$


CREATE OR REPLACE FUNCTION public.fn_llm_preflight(p_model text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when p_model is null or p_model in ('none','none/deterministic')
      then jsonb_build_object('allowed', true, 'reason', 'deterministic path, no provider call')
    when not exists (select 1 from model_registry r where r.model_id = p_model and r.active)
      then jsonb_build_object('allowed', false, 'class_key', 'route_not_registered',
             'reason', 'model ' || p_model || ' is not an active row in model_registry')
    -- NO HEALTH ROW IS NOT HEALTH. Before 23 Sep 2026 this fell through to the `else` and answered
    -- allowed=true, so the hold was bypassable on anthropic/claude-fable-5.1, openai/gpt-6-astra
    -- and openai/gpt-5.6-luna — the three most expensive routes in the fleet — purely because they
    -- were added after the hold rows were written. Absence of a measurement is not a pass.
    when not exists (select 1 from llm_route_health h where h.model_id = p_model)
      then jsonb_build_object('allowed', false, 'class_key', 'route_not_measured',
             'reason', 'model ' || p_model || ' has no llm_route_health row, so no breaker state '
                       || 'exists for it. Refusing: an unmeasured route is not a healthy one. Add '
                       || 'the row (see the_catalogue_names_every_model_the_seats_run_and_the_hold'
                       || '_covers_all_of_them.sql) before routing to it.')
    when exists (select 1 from llm_route_health h
                 where h.model_id = p_model and h.open_until is not null and h.open_until > now())
      then jsonb_build_object('allowed', false, 'class_key', 'route_open',
             'reason', 'circuit open until '
                       || (select h.open_until from llm_route_health h where h.model_id = p_model)
                       || ' after ' || (select h.consecutive_failures from llm_route_health h where h.model_id = p_model)
                       || ' consecutive failures (' || coalesce((select h.opened_class from llm_route_health h where h.model_id = p_model),'?') || ')',
             'open_until', (select h.open_until from llm_route_health h where h.model_id = p_model))
    else jsonb_build_object('allowed', true, 'reason', 'registered, breaker closed')
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_llm_retry_allowed(p_class_key text, p_attempt_no integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select c.retryable and p_attempt_no <= c.max_retries
       from llm_failure_class c where c.class_key = p_class_key),
    false);   -- unknown class is NOT retryable: an unnamed failure never earns another attempt
$function$


