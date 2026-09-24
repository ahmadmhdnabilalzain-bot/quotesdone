-- THE FOUNDER SEES TOMORROW'S SUPPLIER INVITATIONS AT SIX (24 Sep 2026; seat: customer_support).
--
-- Founder, 24 Sep 2026 (memory marketing-month-approval-flow): "a daily email, preferably from customer_support,
-- with a PDF listing which suppliers will be contacted the next day. It is fully coded with no LLM."
--
-- WHAT IT DOES. Every Dubai day at 18:00 (app_secrets.supplier_campaign_list_local_time, default 18:00) the
-- customer_support seat emails the founder ONE PDF: the suppliers the campaign will invite on the next sending day
-- -- company name, emirate, language, email (masked: first two characters of the mailbox and the full domain, so
-- the PDF can be forwarded without handing out a mailing list) -- and today's counts: invitations sent, bounced,
-- unsubscribed, suppliers registered.
--
-- THE LIST IS THE SENDER'S OWN SELECTION. enqueue_supplier_invites takes least(invite_daily_cap, eligible pool)
-- and calls public.fn_supplier_invite_candidates(n); fn_supplier_campaign_next_list calls the SAME function with
-- the SAME n, in the same order. Two things can still differ, and the PDF says both out loud: fn_invite_ramp may
-- move the cap at the start of the sending day (the list is then a prefix, or the batch is), and a lead that
-- registers, bounces or unsubscribes overnight drops out of the candidates.
-- The next sending day uses the sender's own holds: the UAE weekend and a public_holiday row in company_calendar
-- (enqueue_supplier_invites reads that table, so this does too).
-- When the campaign is switched off (supplier_outreach_golive or invite_enabled not 'true'), the email says so
-- plainly and the PDF shows the list that WOULD be sent.
--
-- HOW IT RUNS. resilience_ping step supportCampaignList (every 15 min): fn_customer_support_campaign_list_tick
-- returns the PDF blocks once the local time has passed; resilience_ping renders them on the company template
-- (pdf_native) and hands the file to fn_customer_support_campaign_list_attach, which mails it through
-- founder_mail_policy kind supplier_campaign_daily_list (owner customer_support) to the first address of
-- app_secrets.admin_emails -- management@quotesdone.com, measured 24 Sep 2026. A failed render is retained and
-- retried on the next beat; the email never goes without its PDF. No model is called anywhere.
--
-- Proved by the_founder_sees_tomorrows_supplier_invitations_at_six_probe.sql (aborted transaction, ZZ DEMO lead,
-- no email leaves); prevented by: scripts/checks/the_daily_supplier_list_is_the_senders_selection.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six.sql --apply --ddl

begin;

-- ── 1. WHAT THE SENDER WILL DO ON A DAY ────────────────────────────────────────────────────────────
-- The sender's day holds, as enqueue_supplier_invites applies them: a company_calendar public holiday, the weekend.
create or replace function public.fn_supplier_invites_hold_reason(p_day date)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(
    (select 'public holiday: ' || c.event_name from public.company_calendar c
      where c.kind = 'public_holiday' and p_day between c.starts_on and coalesce(c.ends_on, c.starts_on)
      order by c.starts_on limit 1),
    case when extract(isodow from p_day) in (6, 7) then 'the UAE weekend' end)
$fn$;
revoke execute on function public.fn_supplier_invites_hold_reason(date) from public, anon, authenticated;

create or replace function public.fn_mask_email(p text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when position('@' in coalesce(p, '')) > 1
              then left(split_part(lower(btrim(p)), '@', 1), 2) || '***@' || split_part(lower(btrim(p)), '@', 2)
              else '***' end
$fn$;
revoke execute on function public.fn_mask_email(text) from public, anon, authenticated;

-- The next sending day after p_after, and exactly who the sender would invite on it.
create or replace function public.fn_supplier_campaign_next_list(p_after date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_after date := coalesce(p_after, (now() at time zone 'Asia/Dubai')::date);
  v_day date := v_after + 1; v_skipped jsonb := '[]'::jsonb; v_why text; i int := 0;
  v_cap int; v_pool int; v_n int; v_switch boolean; v_held text; v_rows jsonb;
begin
  loop
    v_why := public.fn_supplier_invites_hold_reason(v_day);
    exit when v_why is null;
    v_skipped := v_skipped || jsonb_build_object('day', v_day, 'why', v_why);
    v_day := v_day + 1; i := i + 1;
    if i > 20 then raise exception 'no supplier sending day within 20 days of %', v_after; end if;
  end loop;
  v_switch := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
              and public.fn_supplier_outreach_golive();
  v_held := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                 when not v_switch then 'invite_enabled is false' end;
  -- the sender's own numbers (enqueue_supplier_invites): cap, eligible pool, planned = least of the two
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  select count(*) into v_pool from public.leads l where public.fn_supplier_invite_eligible(l);
  v_n := greatest(least(v_cap, v_pool), 0);
  select coalesce(jsonb_agg(jsonb_build_object('n', c.rn, 'lead_id', c.lead_id,
            'company', coalesce(nullif(btrim(c.company_name), ''), '(no company name)'),
            'emirate', coalesce(nullif(btrim(l.emirate), ''), '-'), 'language', c.lang,
            'email', public.fn_mask_email(c.to_email)) order by c.rn), '[]'::jsonb)
    into v_rows
    from (select x.*, row_number() over () rn from public.fn_supplier_invite_candidates(v_n) x) c
    join public.leads l on l.id = c.lead_id;
  return jsonb_build_object('send_day', v_day, 'skipped', v_skipped, 'switch_on', v_switch, 'held_because', v_held,
                            'cap', v_cap, 'pool', v_pool, 'planned', v_n, 'rows', v_rows);
end $fn$;
revoke execute on function public.fn_supplier_campaign_next_list(date) from public, anon, authenticated;

-- Today's campaign counts (one Dubai day).
create or replace function public.fn_supplier_campaign_day_counts(p_day date default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with d as (select coalesce(p_day, (now() at time zone 'Asia/Dubai')::date) as d_day)
  select jsonb_build_object('day', d.d_day,
    'sent', (select count(*) from public.notifications n where n.type = 'supplier_invite' and n.status = 'sent'
               and not public.fn_is_demo_email(n.to_email) and (n.sent_at at time zone 'Asia/Dubai')::date = d.d_day),
    'bounced', (select count(*) from public.email_suppressions s where s.reason ilike '%bounce%'
                  and (s.created_at at time zone 'Asia/Dubai')::date = d.d_day),
    'unsubscribed', (select count(*) from public.email_suppressions s where s.reason ilike 'unsub%'
                       and (s.created_at at time zone 'Asia/Dubai')::date = d.d_day),
    'registered', (select count(*) from public.leads l where coalesce(l.is_demo, false) = false
                     and (l.registration_submitted_at at time zone 'Asia/Dubai')::date = d.d_day))
  from d
$fn$;
revoke execute on function public.fn_supplier_campaign_day_counts(date) from public, anon, authenticated;

-- ── 2. ONE ROW PER DAY: WHAT WAS SHOWN, AND WHETHER IT WAS DELIVERED ───────────────────────────────
create table if not exists public.supplier_campaign_daily_list (
  id               bigint generated always as identity primary key,
  list_day         date not null unique,             -- the Dubai day the email is sent ON (the list is for the next sending day)
  send_day         date not null,
  switch_on        boolean not null,
  held_because     text,
  planned          int not null,
  rows             jsonb not null,
  counts           jsonb not null,
  subject          text not null,
  body             text not null,
  pdf_blocks       jsonb not null,
  pdf_path         text,
  pdf_error        text,
  attempts         int not null default 0,
  notification_id  bigint,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on table public.supplier_campaign_daily_list is
  'The founder''s 18:00 Dubai email (customer_support): the suppliers the campaign will invite on the next sending day, from the sender''s own fn_supplier_invite_candidates, with the day''s sent / bounced / unsubscribed / registered counts. One row per day; notification_id set when mailed.';
alter table public.supplier_campaign_daily_list enable row level security;
drop policy if exists supplier_campaign_daily_list_service_role_only on public.supplier_campaign_daily_list;
create policy supplier_campaign_daily_list_service_role_only on public.supplier_campaign_daily_list as permissive for all to public using (false) with check (false);
revoke all on public.supplier_campaign_daily_list from anon, authenticated;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at) values
  ('supplier_campaign_daily_list', true, 'Founder, 24 Sep 2026: every day at 18:00 Dubai, customer_support emails him a PDF of exactly which suppliers the campaign invites the next sending day, with the day''s counts.', 'customer_support', now())
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
       owner_role = excluded.owner_role, updated_at = now();

-- ── 3. THE TICK (18:00 Dubai) AND THE ATTACH ──────────────────────────────────────────────────────
create or replace function public.fn_customer_support_campaign_list_tick(p_now timestamptz default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := coalesce(p_now, now()) at time zone 'Asia/Dubai'; v_at time; r public.supplier_campaign_daily_list;
  v_l jsonb; v_c jsonb; v_subj text; v_body text; v_blocks jsonb; v_state text; v_send text;
begin
  begin
    select coalesce(nullif(btrim(value), ''), '18:00')::time into v_at from public.app_secrets where key = 'supplier_campaign_list_local_time';
  exception when others then v_at := time '18:00'; end;
  v_at := coalesce(v_at, time '18:00');
  if v_local::time < v_at then return jsonb_build_object('due', false, 'reason', 'before ' || to_char(v_at, 'HH24:MI') || ' Dubai'); end if;

  select * into r from public.supplier_campaign_daily_list where list_day = v_local::date;
  if r.notification_id is not null then return jsonb_build_object('due', false, 'reason', 'already sent today', 'id', r.id); end if;
  if r.id is not null and r.attempts >= 8 then return jsonb_build_object('due', false, 'ok', false, 'reason', 'render failed 8 times today', 'error', r.pdf_error); end if;

  if r.id is null then
    v_l := public.fn_supplier_campaign_next_list(v_local::date);
    v_c := public.fn_supplier_campaign_day_counts(v_local::date);
    v_send := to_char((v_l->>'send_day')::date, 'FMDay DD FMMonth YYYY');
    v_state := case when (v_l->>'switch_on')::boolean
                    then 'The campaign is ON: these ' || (v_l->>'planned') || ' supplier(s) will be invited on ' || v_send || ', spread across the working day.'
                    else 'The campaign is SWITCHED OFF (' || (v_l->>'held_because') || '): NOTHING will be sent on ' || v_send
                         || '. This is the list that WOULD be sent if it were on.' end;
    v_subj := 'Supplier campaign: ' || case when (v_l->>'switch_on')::boolean then '' else 'OFF — would invite ' end
              || (v_l->>'planned') || ' supplier(s) on ' || to_char((v_l->>'send_day')::date, 'Dy DD Mon');
    v_body := v_state || E'\n\n'
      || 'Today (' || to_char(v_local::date, 'Dy DD Mon') || '): ' || (v_c->>'sent') || ' invitation(s) sent, ' || (v_c->>'bounced') || ' bounced, '
      || (v_c->>'unsubscribed') || ' unsubscribed, ' || (v_c->>'registered') || ' supplier(s) registered.' || E'\n\n'
      || 'The attached PDF lists each supplier: company, emirate, language and email (masked). It is produced by code from the same '
      || 'selection the sender uses (cap ' || (v_l->>'cap') || ', eligible pool ' || (v_l->>'pool') || '). The morning warm-up may move the cap, '
      || 'and a supplier who registers, bounces or unsubscribes overnight drops out.'
      || coalesce(E'\n\nNo sending on: ' || (select string_agg(to_char((s->>'day')::date, 'Dy DD Mon') || ' (' || (s->>'why') || ')', ', ')
                                               from jsonb_array_elements(v_l->'skipped') s), '');
    v_blocks := jsonb_build_array(
        jsonb_build_object('t', 'h2', 'text', 'Suppliers to be invited on ' || v_send),
        jsonb_build_object('t', 'p', 'text', v_state),
        jsonb_build_object('t', 'p', 'text', 'Today (' || to_char(v_local::date, 'Dy DD Mon YYYY') || '): sent ' || (v_c->>'sent') || ', bounced ' || (v_c->>'bounced')
                                              || ', unsubscribed ' || (v_c->>'unsubscribed') || ', registered ' || (v_c->>'registered') || '.'),
        jsonb_build_object('t', 'note', 'text', 'Selection: fn_supplier_invite_candidates(' || (v_l->>'planned') || '), the sender''s own; cap ' || (v_l->>'cap')
                                              || ', eligible pool ' || (v_l->>'pool') || '. Emails are masked. Prepared by customer_support, by code.'),
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
end $fn$;
revoke execute on function public.fn_customer_support_campaign_list_tick(timestamptz) from public, anon, authenticated;

-- The render's result: a path -> the email goes (once); an error -> retained for the next beat.
create or replace function public.fn_customer_support_campaign_list_attach(
  p_id bigint, p_bucket text default null, p_path text default null, p_url text default null,
  p_bytes int default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_customer_support_campaign_list_attach(bigint, text, text, text, int, text) from public, anon, authenticated;

-- ── 4. THE BEAT ───────────────────────────────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('supportCampaignList', interval '15 min', 3000, 'plan', 0,
   'customer_support: at 18:00 Dubai, the PDF of the suppliers the campaign invites on the next sending day (fn_customer_support_campaign_list_tick -> pdf_native -> fn_customer_support_campaign_list_attach)',
   'customer_support')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
       note = excluded.note, owner_seat = excluded.owner_seat;

-- ── THE DAILY TABLE EXPORT: + supplier_campaign_daily_list (and the marketing tables of one_approve_..., applied before this file) (body of every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql) ──
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
grant execute on function public.fn_table_export_list() to service_role;

commit;
