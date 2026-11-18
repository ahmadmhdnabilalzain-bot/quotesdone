-- THE FOUNDER IS E-MAILED EACH SUPPLIER WHO REGISTERS AND IS APPROVED.
-- Seat: sales_engineer. 18 Nov 2026. Founder ruling 1731 (ledger row 1731): "e-mail the founder immediately whenever a supplier
-- completes registration AND is verified/approved: company name, trades/services, emirate, how they came (invite/referral/direct),
-- and a link to their record."
--
-- WHAT WAS MEASURED (production, read-only, 18 Nov 2026):
--   * The founder is e-mailed through public.fn_notify_founder: a kind that founder_mail_policy allows (allowed_to_email) becomes a
--     founder_alert notification to the first address in app_secrets admin_emails (read from config, never written here), to_role
--     'founder'; a kind it does not allow is routed to a seat's task instead. Its own dedupe is 24 hours.
--   * The registration notice supplier_api sends today (kind supplier_registered, "New supplier approved by the sales engineer") is NOT
--     allowed to e-mail him (founder_mail_policy: "a new supplier is business development's to welcome"), so it became a task. It is
--     also sent at first Save only, while an approval often lands later (the certificate landing, the sales engineer's re-check).
--   * Every approval, on every path, passes one place: the AFTER trigger on leads.approval_status that tells the supplier
--     (trg_sales_engineer_tells_the_supplier_he_is_approved, WHEN new.approval_status = 'approved', the transition only).
--   * founder_alert is not in decision_policy.alert_digest_types, so an 'info' founder_alert is sent at once, not folded into the
--     brief; and 'info' sends no WhatsApp (fn_notify_founder sends one only for critical / urgent / high / danger).
--
-- WHAT THIS ADDS:
--   1. founder_mail_policy kind 'supplier_approved_founder', allowed_to_email, owner sales_engineer.
--   2. fn_founder_supplier_approved_skip(leads): why this approval is not told (null = tell): a demo or test identity
--      (fn_seat_clock_lead_is_fixture, a qd_run:/qd_demo tag), the founder's own account (fn_is_founder_own_inbox), or already told.
--   3. fn_founder_supplier_approved_compose(leads): the e-mail. Company (the licence's legal name), trades and services (the
--      supplier's capability row: confirmed trades, else proposed ones less the excluded, as the supplier's own approval notice lists
--      them), emirate, how he came (a supplier_referral -> referral; an invitation sent or clicked, or a first touch from the invite
--      campaign -> invitation; otherwise direct, with his first touch if one was recorded), licence, approval, and a link to his row in
--      the database (the project from app_secrets project_ref; there is no admin console: src/app/[locale]/admin is a sign-in page).
--   4. trg_z30_founder_hears_of_each_approved_supplier on leads (AFTER INSERT OR UPDATE OF approval_status, WHEN approved): the
--      transition only, then skip or fn_notify_founder(kind 'supplier_approved_founder', level 'info', dedupe key
--      'supplier_approved_founder:<lead id>'). A lead already told (a founder_alerts e-mail row with that key) is never told again:
--      a supplier suspended and re-approved is one e-mail, ever. Each outcome is an agent_actions row; a failure never undoes the approval.
-- MEASURED BEFORE COMMIT (18 Nov 2026, a local Postgres 16 holding production's own bodies of fn_notify_founder,
-- fn_notifications_founder_mail_policy, fn_seat_clock_lead_is_fixture, fn_is_demo_email and fn_mailbox_fold, read by SELECT): five suppliers
-- approved at once -> three e-mails, one each, to the configured address (an invited one: "invitation: we invited him on .. and he clicked
-- it on .., found in uaecsd"; a referred one: "referral: referred by <company> (lead 1)"; a direct one: "direct: ... (first came from google
-- / organic)"), type founder_alert, severity info, status queued; the ZZ DEMO one and the founder's +tag Gmail skipped by name; the first
-- suspended and re-approved: skipped, "already told"; an approved row's other column changed: nothing. The verdict below: PROBE OK.
-- Rollback: drop trigger trg_z30_founder_hears_of_each_approved_supplier on public.leads; update founder_mail_policy set
-- allowed_to_email = false where kind = 'supplier_approved_founder'.
--
-- Pending: scripts/sql/pending/the_founder_is_e_mailed_each_supplier_who_registers_and_is_approved.txt
-- Prevented by: scripts/checks/the_founder_is_e_mailed_each_supplier_who_registers_and_is_approved.test.mjs

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('supplier_approved_founder', true,
        'Founder ruling 1731 (18 Nov 2026): one e-mail, at once, when a supplier completes registration and is approved: company, '
        || 'trades and services, emirate, how he came (invitation / referral / direct) and a link to his record. Never for a demo or '
        || 'test identity, once per supplier (scripts/sql/the_founder_is_e_mailed_each_supplier_who_registers_and_is_approved.sql).',
        'sales_engineer')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role,
                                 updated_at = now();

create or replace function public.fn_founder_supplier_approved_skip(p public.leads)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when public.fn_seat_clock_lead_is_fixture(p)
      or exists (select 1 from unnest(coalesce(p.tags, '{}'::text[])) t where t like 'qd\_run:%' or t = 'qd_demo')
      then 'a demo or test identity'
    when public.fn_is_founder_own_inbox(p.claimed_by) or public.fn_is_founder_own_inbox(p.email)
      then 'the founder''s own account'
    when exists (select 1 from public.founder_alerts f
                  where f.dedupe_key = 'supplier_approved_founder:' || p.id and f.channel = 'email')
      then 'the founder was already told of this supplier'
  end
$fn$;
revoke execute on function public.fn_founder_supplier_approved_skip(public.leads) from public, anon, authenticated;

create or replace function public.fn_founder_supplier_approved_compose(p public.leads)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_name text := coalesce(nullif(btrim(p.licence_legal_name), ''), nullif(btrim(p.company_name), ''), 'supplier #' || p.id);
  v_trades text; v_services text; v_ref record; v_ft record; v_came text; v_proj text; v_link text; v_emirate text; v_body text;
begin
  select string_agg(coalesce(t.label, c), ', ' order by coalesce(t.label, c)) into v_trades
    from public.supplier_capabilities sc
    cross join lateral unnest(case when sc.confirmed_at is not null and cardinality(sc.trades) > 0 then sc.trades
                                   else array(select x from unnest(coalesce(sc.proposed_trades, '{}')) x
                                               where x <> all (coalesce(sc.excluded_trades, '{}'))) end) c
    left join public.taxonomy_trade t on t.code = c
   where sc.supplier_id = p.id;
  select string_agg(s, ', ') into v_services
    from (select s from public.supplier_capabilities sc, unnest(coalesce(sc.services, '{}')) s
           where sc.supplier_id = p.id and nullif(btrim(s), '') is not null limit 10) x;

  select r.referrer_lead_id, coalesce(nullif(btrim(rl.licence_legal_name), ''), rl.company_name) as referrer into v_ref
    from public.supplier_referral r left join public.leads rl on rl.id = r.referrer_lead_id
   where r.referred_lead_id = p.id order by r.recorded_at limit 1;
  select f.utm_source, f.utm_medium, f.utm_campaign, f.landing_path into v_ft
    from public.marketing_first_touch f where f.lead_id = p.id order by f.first_seen_at nulls last, f.id limit 1;
  v_came := case
    when v_ref.referrer_lead_id is not null
      then 'referral: referred by ' || coalesce(v_ref.referrer, 'a supplier') || ' (lead ' || v_ref.referrer_lead_id || ')'
    when p.invited_at is not null or p.invite_clicked_at is not null or nullif(btrim(p.invite_status), '') is not null
      or v_ft.utm_source = 'invite' or v_ft.utm_campaign ilike '%invite%'
      then 'invitation: we invited him' || coalesce(' on ' || to_char(p.invited_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), '')
           || coalesce(' and he clicked it on ' || to_char(p.invite_clicked_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), '')
           || coalesce(' (campaign ' || v_ft.utm_campaign || ')', '')
           || case when coalesce(p.source, '') not in ('', 'self_registered') then ', found in ' || p.source else '' end
    else 'direct: he registered on the site himself'
         || coalesce(' (first came from ' || nullif(concat_ws(' / ', v_ft.utm_source, v_ft.utm_medium, v_ft.utm_campaign), '') || ')', '')
  end;

  v_emirate := coalesce(nullif(btrim(p.emirate), ''), 'not stated')
    || coalesce(' (licence: ' || nullif(btrim(p.license_city), '') || ')', '')
    || coalesce('; serves ' || nullif(array_to_string(p.service_emirates, ', '), ''), '');
  select nullif(btrim(value), '') into v_proj from public.app_secrets where key = 'project_ref';
  v_link := case when v_proj is not null
    then 'https://supabase.com/dashboard/project/' || v_proj || '/editor/' || ('public.leads'::regclass)::oid
         || '?schema=public&filter=id%3Aeq%3A' || p.id || ' (lead ' || p.id || ')'
    else 'lead ' || p.id || ' in public.leads' end;

  v_body := v_name || ' has completed registration and is approved on QuotesDone.' || E'\n\n'
    || 'Company: ' || v_name
    || case when nullif(btrim(p.company_name), '') is not null and btrim(p.company_name) <> v_name
            then ' (registered as "' || btrim(p.company_name) || '")' else '' end || E'\n'
    || 'Trades: ' || coalesce(v_trades, 'none read from his documents yet') || E'\n'
    || 'Services: ' || coalesce(v_services, 'none listed yet') || E'\n'
    || 'Emirate: ' || v_emirate || E'\n'
    || 'How he came: ' || v_came || E'\n'
    || 'Licence: ' || coalesce(nullif(btrim(p.trade_license_no), ''), 'number not read')
      || coalesce(', ' || nullif(btrim(p.license_authority), ''), '') || coalesce(', expires ' || to_char(p.license_expiry, 'DD Mon YYYY'), '') || E'\n'
    || 'Approved: ' || to_char(coalesce(p.approved_at, now()) at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai time'
      || coalesce(' by ' || nullif(btrim(p.approval_decided_by), ''), '') || ', verification ' || coalesce(p.verification_status, 'unknown') || E'\n'
    || 'Record: ' || v_link || E'\n\n'
    || 'For your information; nothing is asked of you.';
  return jsonb_build_object('event', 'New supplier approved: ' || v_name, 'detail', v_body, 'came', split_part(v_came, ':', 1));
end $fn$;
revoke execute on function public.fn_founder_supplier_approved_compose(public.leads) from public, anon, authenticated;

create or replace function public.fn_founder_hears_of_each_approved_supplier()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_why text; m jsonb; v_r jsonb;
begin
  if tg_op = 'UPDATE' and coalesce(old.approval_status, '') = 'approved' then return null; end if;   -- the transition only
  v_why := public.fn_founder_supplier_approved_skip(new);
  if v_why is null then
    m := public.fn_founder_supplier_approved_compose(new);
    v_r := public.fn_notify_founder(p_event => m->>'event', p_detail => m->>'detail', p_level => 'info',
                                    p_kind => 'supplier_approved_founder', p_dedupe_key => 'supplier_approved_founder:' || new.id,
                                    p_owner_agent => 'sales_engineer');
  end if;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'founder_supplier_approved_notice', case when v_why is null then 'auto_done' else 'skipped' end, 'low',
          left('Founder told of the approval ' || case when v_why is null then '' else 'not sent (' || v_why || ')' end
               || ' — ' || coalesce(new.company_name, 'supplier #' || new.id), 200),
          jsonb_build_object('supplier_id', new.id, 'not_sent', v_why, 'came', m->>'came', 'notify', v_r), 'leads', new.id::text);
  return null;
exception when others then
  -- The approval stands whatever happens here; the failure is on the record for the sales engineer.
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'founder_supplier_approved_notice', 'failed', 'medium',
          left('Founder approval notice failed — ' || coalesce(new.company_name, 'supplier #' || new.id), 200),
          jsonb_build_object('supplier_id', new.id, 'error', left(sqlerrm, 500)), 'leads', new.id::text);
  return null;
end $fn$;
revoke execute on function public.fn_founder_hears_of_each_approved_supplier() from public, anon, authenticated;

drop trigger if exists trg_z30_founder_hears_of_each_approved_supplier on public.leads;
create trigger trg_z30_founder_hears_of_each_approved_supplier
  after insert or update of approval_status on public.leads
  for each row when (new.approval_status = 'approved')
  execute function public.fn_founder_hears_of_each_approved_supplier();

-- VERDICT (reads only; no row is written): the kind may e-mail him, the trigger is on, a demo copy of a real approved supplier is
-- skipped, the founder's own address is skipped, and the real one's e-mail carries every field the ruling names.
with real as (select l from public.leads l where l.id = 158318),
     demo as (select jsonb_populate_record(null::public.leads, to_jsonb(r.l) || jsonb_build_object('tags', array['qd_demo'])) d from real r),
     own  as (select jsonb_populate_record(null::public.leads, to_jsonb(r.l) || jsonb_build_object('claimed_by', 'management@quotesdone.com', 'email', null)) o from real r),
     msg  as (select public.fn_founder_supplier_approved_compose(r.l) m from real r)
select case
  when not coalesce((select allowed_to_email from public.founder_mail_policy where kind = 'supplier_approved_founder'), false)
    then 'PROBE FAILED: supplier_approved_founder may not e-mail the founder'
  when not exists (select 1 from pg_trigger where tgrelid = 'public.leads'::regclass and tgname = 'trg_z30_founder_hears_of_each_approved_supplier' and tgenabled = 'O')
    then 'PROBE FAILED: the trigger is not on'
  when not exists (select 1 from real) then 'PROBE OK (no lead 158318 to compose from): the kind and the trigger are in place'
  when public.fn_founder_supplier_approved_skip((select d from demo)) is distinct from 'a demo or test identity' then 'PROBE FAILED: a demo identity is not skipped'
  when public.fn_founder_supplier_approved_skip((select o from own)) is distinct from 'the founder''s own account' then 'PROBE FAILED: the founder''s own account is not skipped'
  when (select m->>'detail' from msg) !~ 'Company: .+\nTrades: .+\nServices: .+\nEmirate: .+\nHow he came: (referral|invitation|direct): .+\nLicence: .+\nApproved: .+\nRecord: .+'
    then 'PROBE FAILED: the e-mail lacks a field: ' || left((select m->>'detail' from msg), 300)
  when has_function_privilege('anon', 'public.fn_founder_supplier_approved_compose(public.leads)', 'execute') then 'PROBE FAILED: anon may execute the compose'
  else 'PROBE OK: the founder is e-mailed once per approved supplier, never for a demo or his own account' end as verdict;
