-- THE ACCOUNTANT SAYS WHETHER THE EXPENSES MAILBOX IS QUIET OR THE INTAKE IS SILENT.
--
-- Assigned: accountant. Ledger 983 (24 Sep 2026): Accountant gap 1 in GAPS.md -- "the books are 9 days stale.
-- Either no receipts came in, or intake is silent. The accountant must say which." KPI in the approved job
-- description: books current within 24 hours; every receipt booked.
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only):
--   * expense_entries: 52 rows from receipts, the newest created 15 Sep 22:12 UTC; 2 founder_reported rows,
--     the newest 24 Sep 01:56.
--   * inbound_messages to expenses@mail.quotesdone.com since 14 Sep: THREE -- 14 Sep (a statement, held),
--     15 Sep (Resend, booked) and 23 Sep 23:37 (an Anthropic receipt, HELD: the PDF has no text layer).
--   So the answer on 24 Sep was: the mailbox was quiet from 15 to 23 Sep, and the one receipt that came in on
--   23 Sep is held, not booked. Neither case was said anywhere; a person had to read the tables to know.
--
-- WHAT THIS BUILDS
--   accountant_mailbox_check  one row per check: what the Resend inbound list showed for the expenses mailbox
--       (the accountant runtime lists it; address EQUALITY, never a word test), how many of those messages the
--       intake never recorded, how many recorded receipts are still held after 24 hours, and the verdict.
--   fn_accountant_mailbox_check_record(messages, list_error)  called by the accountant runtime's hourly
--       'duties' action. Verdict, in this order:
--         unreadable     the list could not be read (said, never read as "empty")
--         intake_silent  a message reached the mailbox and nothing recorded it           -> accountant finding
--         held_waiting   a receipt was recorded but is still held after 24 hours         -> accountant finding
--         mailbox_quiet  nothing arrived in the last 72 hours; the books are current with what came in
--         current        everything that arrived is booked or recorded
--       Findings settle through fn_accountant_duty_settle('mailbox', ...), so they close themselves when the
--       check no longer finds them.
--
-- A message counts as TAKEN IN when any intake path left its Resend id: inbound_messages.provider_email_id
-- (the live webhook), expense_entries.source_msg_id 'resend:<id>' (a booking), or the historical sweep's
-- inbound record, which carries 'Resend inbound id <id>' in its body.
--
-- prevented by: supabase/functions/_shared/expense_mailbox.test.ts (the mailbox filter) and
-- scripts/checks/accountant_duties_are_wired.test.mjs (the record routine is in the mirror and called).

create table if not exists public.accountant_mailbox_check (
  id bigint generated always as identity primary key,
  checked_at timestamptz not null default now(),
  listed int not null,
  not_taken_in int not null,
  held_over_24h int not null,
  last_received_at timestamptz,
  verdict text not null check (verdict in ('unreadable', 'intake_silent', 'held_waiting', 'mailbox_quiet', 'current')),
  detail jsonb not null default '{}'::jsonb
);
comment on table public.accountant_mailbox_check is
  'The accountant''s hourly answer to "is the expenses mailbox quiet, or is the intake silent?". Written by fn_accountant_mailbox_check_record.';
alter table public.accountant_mailbox_check enable row level security;
drop policy if exists accountant_mailbox_check_service_role_only on public.accountant_mailbox_check;
create policy accountant_mailbox_check_service_role_only on public.accountant_mailbox_check
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_mailbox_check from anon, authenticated;

create or replace function public.fn_accountant_mailbox_check_record(p_messages jsonb, p_list_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_missing jsonb; v_not int; v_held jsonb; v_held_n int; v_last timestamptz; v_listed int; v_verdict text;
  v_items jsonb := '[]'::jsonb; v_settle jsonb;
begin
  if p_list_error is null and jsonb_typeof(p_messages) is distinct from 'array' then
    raise exception 'fn_accountant_mailbox_check_record: messages must be an array of {id, created_at}';
  end if;
  v_listed := case when p_list_error is null then jsonb_array_length(p_messages) else 0 end;

  select coalesce(jsonb_agg(jsonb_build_object('id', m->>'id', 'received_at', m->>'created_at', 'from', m->>'from')), '[]'::jsonb), count(*)
    into v_missing, v_not
    from jsonb_array_elements(case when p_list_error is null then p_messages else '[]'::jsonb end) m
   where coalesce(m->>'id', '') <> ''
     and not exists (select 1 from public.inbound_messages i where i.provider_email_id = m->>'id')
     and not exists (select 1 from public.expense_entries e where e.source_msg_id = 'resend:' || (m->>'id'))
     and not exists (select 1 from public.inbound_messages i
                      where lower(i.to_email) like 'expenses@%'
                        and position(('Resend inbound id ' || (m->>'id')) in coalesce(i.body, '')) > 0);

  select coalesce(jsonb_agg(jsonb_build_object('inbound_id', i.id, 'received_at', i.created_at, 'subject', left(i.subject, 120)) order by i.id), '[]'::jsonb), count(*)
    into v_held, v_held_n
    from public.inbound_messages i
   where lower(i.to_email) like 'expenses@%' and i.needs_review and i.created_at < now() - interval '24 hours';

  select greatest(
           (select max(created_at) from public.inbound_messages where lower(to_email) like 'expenses@%'),
           (select max((m->>'created_at')::timestamptz) from jsonb_array_elements(case when p_list_error is null then p_messages else '[]'::jsonb end) m))
    into v_last;

  v_verdict := case when p_list_error is not null then 'unreadable'
                    when v_not > 0 then 'intake_silent'
                    when v_held_n > 0 then 'held_waiting'
                    when v_last is null or v_last < now() - interval '72 hours' then 'mailbox_quiet'
                    else 'current' end;

  if p_list_error is not null then
    v_items := v_items || jsonb_build_object('item', 'unreadable', 'owner_seat', 'accountant', 'subject', 'resend inbound',
      'title', 'The expenses mailbox could not be listed, so nobody can say whether receipts arrived',
      'evidence', jsonb_build_object('error', left(p_list_error, 300)));
  end if;
  if v_not > 0 then
    v_items := v_items || jsonb_build_object('item', 'intake_silent', 'owner_seat', 'accountant', 'subject', 'inbound_messages',
      'title', v_not || ' message(s) reached the expenses mailbox and no intake recorded them',
      'affected', v_not, 'evidence', jsonb_build_object('messages', v_missing,
        'act', 'run the accountant expense_sweep for each email_id; if it cannot book one, it holds it and says why'));
  end if;
  if v_held_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'held_waiting', 'owner_seat', 'accountant', 'subject', 'inbound_messages',
      'title', v_held_n || ' receipt(s) in the expenses mailbox are held, not booked, for more than 24 hours',
      'affected', v_held_n, 'evidence', jsonb_build_object('held', v_held));
  end if;
  v_settle := public.fn_accountant_duty_settle('mailbox', v_items);

  insert into public.accountant_mailbox_check (listed, not_taken_in, held_over_24h, last_received_at, verdict, detail)
  values (v_listed, v_not, v_held_n, v_last, v_verdict,
          jsonb_build_object('not_taken_in', v_missing, 'held', v_held, 'list_error', p_list_error));

  return jsonb_build_object('verdict', v_verdict, 'listed', v_listed, 'not_taken_in', v_not, 'held_over_24h', v_held_n,
    'last_received_at', v_last, 'findings', v_settle,
    'says', case v_verdict
      when 'unreadable' then 'the mailbox could not be listed: nothing is known about what arrived'
      when 'intake_silent' then 'receipts reached the mailbox and the intake did not record them'
      when 'held_waiting' then 'every message was taken in, and ' || v_held_n || ' receipt(s) are still held'
      when 'mailbox_quiet' then 'the mailbox is quiet: nothing has arrived since ' || coalesce(to_char(v_last at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai', 'it was opened')
      else 'every receipt that arrived is recorded' end);
end $fn$;
revoke execute on function public.fn_accountant_mailbox_check_record(jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_accountant_mailbox_check_record(jsonb, text) to service_role;

-- PROBE (verdict row). The routine WRITES (a check row and findings), so it is not called here; the file
-- creates only definitions. The runtime's first hourly duties run is the first check.
select case when to_regclass('public.accountant_mailbox_check') is null then 'PROBE FAILED: table missing'
            when to_regprocedure('public.fn_accountant_mailbox_check_record(jsonb,text)') is null then 'PROBE FAILED: routine missing'
            else 'PROBE OK' end as verdict;
