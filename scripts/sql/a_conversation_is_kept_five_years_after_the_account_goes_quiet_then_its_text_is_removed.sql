-- A CONVERSATION IS KEPT WHILE THE ACCOUNT IS ACTIVE AND FIVE YEARS AFTER IT GOES QUIET, THEN ITS TEXT
-- IS REMOVED. BUSINESS RECORDS ARE NEVER TOUCHED.
--
-- Assigned: it_engineer. 6 Oct 2026. Founder rulings:
--   ledger 1126: conversations are kept while the account is active + 5 YEARS after closure, IF lawful;
--   ledger 1127: BOQs, drawings, photos, inquiry details, quotes, comparison reports, reveal/payment
--                records are NEVER purged by this job; it covers conversation text and conversation PDFs.
--
-- THE LEGAL BASIS, READ FROM THE PRIMARY SOURCE (6 Oct 2026):
--   Cabinet Decision No. 74 of 2023 (Executive Regulation of Federal Decree-Law No. 28 of 2022 on Tax
--   Procedures), Article 3(1), as published by the FTA (tax.gov.ae): "All accounting records,
--   commercial books and information shall be retained ... (b) A period of (5) five years from the end
--   of the calendar year in which the concerned document was created in respect of all Persons other
--   than Taxable Persons." QuotesDone is not VAT-registered, so (b) applies. Article 3(2) adds 4 years
--   while a dispute with the FTA or a tax audit is open.
--   FDL 45/2021 (PDPL) Art. 5 requires data be kept no longer than necessary; a statutory retention duty
--   is that necessity. The Commercial Transactions Law (FDL 50/2022) books article could NOT be read
--   (uaelegislation.gov.ae returns 403); it is not relied on here.
--   So a message is eligible only when BOTH hold:
--     (a) its party's last activity is more than 5 years ago (an active account is never eligible), and
--     (b) 5 years have passed since the end of the calendar year the message was created in.
--
-- WHAT IS REMOVED: the text of a message - subject/body/html (email and outbox), inbound/reply
-- (WhatsApp), body (portal chat), message/reply (website assistant) - replaced by a fixed marker. The row
-- itself stays (its time, parties and delivery record are the business record of THAT a message was
-- sent). The message's archived PDF (conversation_archive) is queued in conversation_retention_pdf for
-- deletion from storage and Dropbox.
-- WHAT IS NEVER TOUCHED: rfq_clarification (it records spec decisions - an inquiry record under 1127),
-- inquiries, BOQs, drawings, photos and any attachment file (portal chat attachment_path is kept), quotes,
-- comparison reports, transactions, reveal invoices, refunds, disputes, dues.
-- LEGAL HOLD: a party with any open dispute (post_reveal_dispute undecided, stripe_dispute not closed),
-- open refund (refunds or refund_case not decided, or decided and not settled), unanswered complaint, or
-- unpaid supplier_dues is held entirely: none of its messages is eligible, whatever their age.
--
-- WHAT THIS DOES NOT DO (said so it is not lost):
--   * It does not delete the queued PDFs. The storage + Dropbox deleter for conversation_retention_pdf is
--     not built here; the backup-prune deleter's allow-list deliberately refuses conversations/. Nothing
--     can be queued before 2031 (the oldest message is from 2026), so the deleter is owed before then.
--   * It does not redact copies of message text held in derived tables (support_notification, the
--     customer-support duty tables, social_message). Those are listed for the same follow-up.
--
-- MEASURED BEFORE WRITING (6 Oct 2026, production, read-only): every legal-hold table is empty except
-- supplier_dues (1 row, 'reversed'); the oldest conversation is 2026, so the plan today is 0 rows.

create table if not exists public.conversation_retention_log (
  source_table text not null,
  source_id    text not null,
  party_kind   text,
  party_id     text,
  occurred_at  timestamptz,
  last_activity timestamptz,
  removed_at   timestamptz not null default now(),
  primary key (source_table, source_id));
comment on table public.conversation_retention_log is
  'Every message whose text was removed under the 5-year retention rule (ledger 1126/1127): what, whose, when. Never pruned. a_conversation_is_kept_five_years_after_the_account_goes_quiet_then_its_text_is_removed.sql';
alter table public.conversation_retention_log enable row level security;
revoke all on public.conversation_retention_log from anon, authenticated;
create policy conversation_retention_log_service_only on public.conversation_retention_log
  for all to service_role using (true) with check (true);

create table if not exists public.conversation_retention_pdf (
  source_table text not null,
  source_id    text not null,
  pdf_bucket   text,
  pdf_path     text,
  queued_at    timestamptz not null default now(),
  deleted_at   timestamptz,
  primary key (source_table, source_id));
comment on table public.conversation_retention_pdf is
  'Conversation PDFs owed deletion from storage and Dropbox after their text was removed under the retention rule. The deleter is not built yet (see the owning file).';
alter table public.conversation_retention_pdf enable row level security;
revoke all on public.conversation_retention_pdf from anon, authenticated;
create policy conversation_retention_pdf_service_only on public.conversation_retention_pdf
  for all to service_role using (true) with check (true);

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('conversation_retention_log', true, 'company', 'which message texts were removed under the 5-year retention rule, and when: the evidence the rule ran', 'it_engineer'),
  ('conversation_retention_pdf', true, 'company', 'conversation PDFs owed deletion after their text was removed under the retention rule', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── THE SWITCH (release review, 6 Oct 2026): the job removes text only when app_secrets.conversation_retention_mode
-- = 'remove'. No row - which is the state this file leaves - means DRY RUN: every message it WOULD remove is written to
-- conversation_retention_plan_log with the day it was decided, and nothing is changed. Same pattern as
-- fn_backup_prune_mode (the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql). Switching it on is a separate,
-- recorded production act.
create table if not exists public.conversation_retention_plan_log (
  decided_for   date not null,
  source_table  text not null,
  source_id     text not null,
  party_kind    text,
  party_id      text,
  occurred_at   timestamptz,
  last_activity timestamptz,
  decided_at    timestamptz not null default now(),
  primary key (decided_for, source_table, source_id));
comment on table public.conversation_retention_plan_log is
  'Dry-run decisions of the conversation retention job: what it would remove, per day. Written only while conversation_retention_mode is not remove.';
alter table public.conversation_retention_plan_log enable row level security;
revoke all on public.conversation_retention_plan_log from anon, authenticated;
create policy conversation_retention_plan_log_service_only on public.conversation_retention_plan_log
  for all to service_role using (true) with check (true);
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('conversation_retention_plan_log', true, 'company', 'what the conversation retention job would remove each day while it runs dry', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_conversation_retention_mode()
returns text
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select 'remove' from public.app_secrets s where s.key = 'conversation_retention_mode' and s.value = 'remove'), 'dry_run');
$fn$;
revoke execute on function public.fn_conversation_retention_mode() from public, anon, authenticated;

-- ── A party under legal hold. Conservative: any row not clearly finished holds. ─────────────────────
create or replace function public.fn_conversation_party_on_hold(p_kind text, p_id text)
returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_kind = 'customer' then
         exists (select 1 from public.post_reveal_dispute d where d.customer_id::text = p_id and d.decided_at is null)
      or exists (select 1 from public.refunds r where r.customer_id::text = p_id
                  and (r.decided_at is null or (r.settled_at is null and coalesce(r.status, '') !~* 'reject|declin|cancel|denied')))
      or exists (select 1 from public.transactions t join public.stripe_dispute s on s.transaction_id = t.id
                  where t.customer_id::text = p_id and s.closed_at is null)
      or exists (select 1 from public.transactions t join public.refund_case rc on rc.transaction_id = t.id
                  where t.customer_id::text = p_id and rc.settled_at is null
                    and (rc.decided_at is null or coalesce(rc.decision, '') !~* 'reject|declin|denied'))
      or exists (select 1 from public.customers c join public.complaint_tickets ct on lower(ct.email) = lower(c.email)
                  where c.id::text = p_id and ct.final_response_at is null)
    when p_kind = 'supplier' then
         exists (select 1 from public.supplier_dues sd where sd.supplier_id::text = p_id and sd.paid_at is null
                  and coalesce(sd.status, '') !~* '^(paid|reversed|waived|cancelled|canceled|written_off)$')
      or exists (select 1 from public.post_reveal_dispute d where d.supplier_id::text = p_id and d.decided_at is null)
      or exists (select 1 from public.refunds r where r.supplier_lead_id::text = p_id
                  and (r.decided_at is null or (r.settled_at is null and coalesce(r.status, '') !~* 'reject|declin|cancel|denied')))
      or exists (select 1 from public.transactions t join public.stripe_dispute s on s.transaction_id = t.id
                  where t.supplier_id::text = p_id and s.closed_at is null)
      or exists (select 1 from public.leads l join public.complaint_tickets ct on lower(ct.email) = lower(l.email)
                  where l.id::text = p_id and ct.final_response_at is null)
    else false end;
$fn$;
revoke execute on function public.fn_conversation_party_on_hold(text, text) from public, anon, authenticated;

-- ── A party's last activity: messages, inquiries, transactions and sign-ins, by direct lookups. ─────
create or replace function public.fn_conversation_party_last_activity(p_kind text, p_id text)
returns timestamptz
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_kind = 'customer' then (
      select greatest(
        (select max(greatest(i.created_at, i.stage_changed_at, i.completed_at)) from public.inquiries i where i.customer_id::text = p_id),
        (select max(m.created_at) from public.messages m where m.customer_id::text = p_id),
        (select max(u.last_sign_in_at) from public.customers c join auth.users u on lower(u.email) = lower(c.email) where c.id::text = p_id),
        (select max(coalesce(n.sent_at, n.created_at)) from public.customers c join public.notifications n on lower(n.to_email) = lower(c.email) where c.id::text = p_id),
        (select max(im.created_at) from public.customers c join public.inbound_messages im on lower(im.from_email) = lower(c.email) where c.id::text = p_id),
        (select c.created_at from public.customers c where c.id::text = p_id)))
    when p_kind = 'supplier' then (
      select greatest(
        (select max(m.created_at) from public.messages m where m.supplier_id::text = p_id),
        (select max(coalesce(n.sent_at, n.created_at)) from public.notifications n where n.lead_id::text = p_id),
        (select max(im.created_at) from public.inbound_messages im where im.lead_id::text = p_id),
        (select max(u.last_sign_in_at) from public.leads l join auth.users u on u.id::text = l.claimed_by or lower(u.email) = lower(l.email) where l.id::text = p_id)))
    end;
$fn$;
revoke execute on function public.fn_conversation_party_last_activity(text, text) from public, anon, authenticated;

-- ── The plan: which messages are eligible at p_now. Pure read. ────────────────────────────────────
create or replace function public.fn_conversation_retention_plan(p_now timestamptz default now(), p_limit int default 500)
returns table(source_table text, source_id text, party_kind text, party_id text, occurred_at timestamptz, last_activity timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with c as (
    select v.source_table, v.source_id, v.party_kind, v.party_id, v.occurred_at
      from public.v_conversation_message v
     where v.source_table in ('inbound_messages', 'notifications', 'wa_messages', 'messages', 'assistant_logs')
       and v.occurred_at < p_now - interval '5 years'
       and date_trunc('year', v.occurred_at) + interval '6 years' <= p_now      -- end of creation year + 5 years
       and not exists (select 1 from public.conversation_retention_log l
                        where l.source_table = v.source_table and l.source_id = v.source_id)),
  p as (
    select distinct c.party_kind, c.party_id from c where c.party_id is not null),
  pa as (
    select p.party_kind, p.party_id,
           public.fn_conversation_party_last_activity(p.party_kind, p.party_id) as last_activity,
           public.fn_conversation_party_on_hold(p.party_kind, p.party_id) as on_hold
      from p)
  select c.source_table, c.source_id, c.party_kind, c.party_id, c.occurred_at,
         coalesce(pa.last_activity, c.occurred_at)
    from c left join pa on pa.party_kind = c.party_kind and pa.party_id = c.party_id
   where not coalesce(pa.on_hold, false)
     and greatest(coalesce(pa.last_activity, c.occurred_at), c.occurred_at) < p_now - interval '5 years'
   order by c.occurred_at
   limit greatest(p_limit, 0);
$fn$;
revoke execute on function public.fn_conversation_retention_plan(timestamptz, int) from public, anon, authenticated;

-- ── The purge: remove the text of the planned messages, log them, queue their PDFs. Idempotent. ────
create or replace function public.fn_conversation_retention_purge(p_limit int default 500)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  k constant text := '[removed under the QuotesDone retention policy]';
  r record; n int := 0;
  v_mode constant text := public.fn_conversation_retention_mode();
begin
  for r in select * from public.fn_conversation_retention_plan(now(), p_limit) loop
    if v_mode <> 'remove' then
      insert into public.conversation_retention_plan_log (decided_for, source_table, source_id, party_kind, party_id, occurred_at, last_activity)
      values (current_date, r.source_table, r.source_id, r.party_kind, r.party_id, r.occurred_at, r.last_activity)
      on conflict do nothing;
      n := n + 1;
      continue;                                                                   -- DRY RUN: nothing is changed
    end if;
    if r.source_table = 'inbound_messages' then
      update public.inbound_messages set subject = k, body = k, html = null where id::text = r.source_id;
    elsif r.source_table = 'notifications' then
      update public.notifications set subject = k, body = k, html = null where id::text = r.source_id;
    elsif r.source_table = 'wa_messages' then
      update public.wa_messages set inbound = k, reply = case when reply is null then null else k end where id::text = r.source_id;
    elsif r.source_table = 'messages' then
      update public.messages set body = k where id::text = r.source_id;          -- attachment_path is kept
    elsif r.source_table = 'assistant_logs' then
      update public.assistant_logs set message = k, reply = k where id::text = r.source_id;
    else
      continue;                                                                   -- never anything else
    end if;
    insert into public.conversation_retention_log (source_table, source_id, party_kind, party_id, occurred_at, last_activity)
    values (r.source_table, r.source_id, r.party_kind, r.party_id, r.occurred_at, r.last_activity)
    on conflict do nothing;
    insert into public.conversation_retention_pdf (source_table, source_id, pdf_bucket, pdf_path)
    select a.source_table, a.source_id, a.pdf_bucket, a.pdf_path from public.conversation_archive a
     where a.source_table = r.source_table and a.source_id = r.source_id
    on conflict do nothing;
    n := n + 1;
  end loop;
  return jsonb_build_object('mode', v_mode, case when v_mode = 'remove' then 'removed' else 'would_remove' end, n, 'ran_at', now(),
                            'pdfs_owed', (select count(*) from public.conversation_retention_pdf where deleted_at is null));
end $fn$;
revoke execute on function public.fn_conversation_retention_purge(int) from public, anon, authenticated;

-- ── Daily, 03:20 Dubai (23:20 UTC). ─────────────────────
select cron.schedule('conversation_retention_daily', '20 23 * * *',
  $CRON$select public.fn_conversation_retention_purge(500);$CRON$);

-- PROBE: read-only. Today nothing may be eligible (the oldest message is 2026), and no message of a
-- held or recently active party may appear even far in the future. Returns ONE verdict row.
with now_plan as (select count(*) n from public.fn_conversation_retention_plan(now(), 100000)),
     future as (select * from public.fn_conversation_retention_plan(timestamptz '2045-01-01', 2000)),
     bad as (
       select count(*) n from future f
        where f.party_id is not null
          and (public.fn_conversation_party_on_hold(f.party_kind, f.party_id)
               or public.fn_conversation_party_last_activity(f.party_kind, f.party_id) >= timestamptz '2040-01-01'
               or f.source_table not in ('inbound_messages', 'notifications', 'wa_messages', 'messages', 'assistant_logs')))
select case when (select n from now_plan) <> 0 then 'PROBE FAILED: ' || (select n from now_plan) || ' messages eligible today'
            when (select n from bad) <> 0 then 'PROBE FAILED: a held, active or non-conversation row was planned'
            when public.fn_conversation_retention_mode() <> 'dry_run' then 'PROBE FAILED: the job is armed; this file must leave it dry'
            when (select count(*) from cron.job where jobname = 'conversation_retention_daily') <> 1 then 'PROBE FAILED: the cron is missing'
            else 'PROBE OK: 0 eligible today; ' || (select count(*) from future) || ' would be eligible on 2045-01-01, none held or active'
       end as verdict;
