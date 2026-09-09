-- THE SPEND REPORT IS KEPT AS A RECORD, AND SAYS WHICH MAILBOX IT READ.
--
-- The founder, 9 September 2026, verbatim: "so i need the accountant to email me the whole thing
-- and keep it in his record as well".
--
-- Two things were missing for that second half to be true.
--
-- ONE: THE REPORT WAS NOT RETAINED. fn_accountant_spend_report_deliver put the PDF on the mail lane
-- and the object stayed in the bucket, but nothing recorded WHAT was reported, WHEN, or OVER WHICH
-- PERIOD. A bucket full of PDFs is not a record: you cannot ask it what the total was in September
-- without re-opening a document, and you cannot prove a figure was ever stated. So a report row is
-- written at delivery, carrying the whole figures payload, so the same report can be reproduced and
-- audited later without re-reading a mailbox that no longer holds the mail.
--
-- TWO: THE COVERAGE LINE HAD BECOME AN INSTRUMENT MEASURING THE WRONG SUBJECT. It quoted only the
-- last Resend inbound sweep -- "read 9 message(s) from Resend's inbound history" -- because that was
-- the only way expenses had ever reached the book. As of today 28 of the 37 booked entries came
-- from a different place entirely: the founder's Gmail SENT folder, which is the surviving record of
-- everything he forwarded before Resend's ~1-month inbound retention aged it out. Left alone, the
-- report would have said it looked at 9 messages while showing 37 entries, and the line that exists
-- precisely to BOUND the total would instead have contradicted it. A coverage line that understates
-- coverage is worse than none: it converts a complete total into one that reads as unexplained.
--
-- So coverage now names BOTH sources, and says plainly when one of them has never run.
--
-- Nothing here changes a single figure. The total is what it was; the report just stops
-- misdescribing where it came from, and starts keeping itself.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE RECORD. One row per DELIVERED report. The stored object path is the identity, matching the
--    idempotency the deliver routine already keys on, so a re-render is a new report and a re-send
--    of the same document is not.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.accountant_spend_report (
  id              bigserial primary key,
  company_key     text        not null default 'quotesdone',
  as_of           date        not null,
  period_start    date,
  period_end      date,
  local_timezone  text        not null default 'Asia/Dubai',
  entries         integer,
  total_aed       numeric(18,2),
  vat_stated_aed  numeric(18,2),
  usd_to_aed      numeric(18,6),
  complete        boolean,
  shortfalls      jsonb,
  figures         jsonb       not null default '{}'::jsonb,
  coverage        jsonb,
  subject         text,
  body            text,
  pdf_bucket      text,
  pdf_path        text,
  pdf_url         text,
  pdf_bytes       bigint,
  notification_id bigint,
  generated_at    timestamptz not null default now(),
  delivered_at    timestamptz,
  created_at      timestamptz not null default now()
);

comment on table public.accountant_spend_report is
  'One row per DELIVERED since-day-one spend report. The founder asked for the report to be kept, '
  'not just sent: this is that record. figures holds the entire fn_accountant_spend_report payload '
  '(total, per vendor, per month, per currency, held receipts, shortfalls) as it stood when the '
  'document was mailed, so the report can be reproduced and audited later without re-reading a '
  'mailbox whose provider no longer holds the mail. Keyed on the stored PDF object, which is the '
  'same identity fn_accountant_spend_report_deliver uses to decide it has already sent a document.';

create unique index if not exists uq_accountant_spend_report_object
  on public.accountant_spend_report (pdf_bucket, pdf_path);

create index if not exists ix_accountant_spend_report_as_of
  on public.accountant_spend_report (as_of desc);

alter table public.accountant_spend_report enable row level security;

commit;

-- ---------------------------------------------------------------------------------------------
-- 2. COVERAGE NAMES BOTH MAILBOXES. CREATE OR REPLACE preserves the ACL, so nothing is revoked or
--    re-granted here. Only the coverage paragraph changes; every figure is computed exactly as
--    before.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_spend_report_coverage()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $cov$
declare
  v_tz    text := 'Asia/Dubai';
  v_sweep record;
  v_back  record;
  v_cov   text := '';
  v_short text[] := '{}';
begin
  select r.id, r.finished_at, r.counts, r.status into v_sweep
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_sweep'
   order by r.id desc limit 1;

  select r.id, r.finished_at, r.counts, r.status into v_back
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_backfill'
   order by r.id desc limit 1;

  -- ---- SOURCE 1: Resend's inbound history, which is what the live webhook and the sweep see. ----
  if v_sweep.id is null then
    v_cov := 'RESEND INBOUND: never swept. The expenses mailbox has never been read by this seat '
          || 'through Resend, so nothing here bounds how many messages arrived that way.';
    v_short := v_short || array['the Resend inbound mailbox has never been swept'];
  else
    v_cov := 'RESEND INBOUND: the last sweep (agent_runs #' || v_sweep.id || ', '
          || to_char(v_sweep.finished_at at time zone v_tz, 'DD Mon YYYY HH24:MI') || ' Asia/Dubai) read '
          || coalesce(v_sweep.counts->>'history_messages','?') || ' message(s) from Resend''s inbound history, of which '
          || coalesce(v_sweep.counts->>'to_expense_mailbox','?') || ' were addressed to expenses@mail.quotesdone.com. It booked '
          || coalesce(v_sweep.counts->>'booked','?') || ', found ' || coalesce(v_sweep.counts->>'already_booked','?')
          || ' already booked, held ' || coalesce(v_sweep.counts->>'held','?') || ', refused '
          || coalesce(v_sweep.counts->>'refused','?') || ' and failed on ' || coalesce(v_sweep.counts->>'failed','?') || '.'
          || ' Resend''s inbound retention is roughly one month, so that history is a WINDOW on recent '
          || 'mail, never the whole of it. Nothing older than the window was misaddressed or lost by us '
          || '- the provider simply stops keeping it.';
    if coalesce((v_sweep.counts->>'pages_capped')::boolean, false) then
      v_cov := v_cov || ' PAGING WAS CAPPED, so the history itself may be incomplete.';
      v_short := v_short || array['the sweep stopped at its page cap, so older messages may never have been read'];
    end if;
    if coalesce(v_sweep.counts->>'list_error','') <> '' then
      v_cov := v_cov || ' The listing reported an error: ' || (v_sweep.counts->>'list_error') || '.';
      v_short := v_short || array['the mailbox listing errored during the last sweep'];
    end if;
  end if;

  -- ---- SOURCE 2: the founder's own SENT folder, which is what survived the retention window. ----
  if v_back.id is null then
    v_cov := v_cov || E'\n\n' || 'FORWARDED HISTORY: never read. Everything the founder forwarded '
          || 'before Resend''s retention window has NOT been examined, so the total below covers only '
          || 'recent mail and is expected to be short.';
    v_short := v_short || array['the forwarded history older than Resend''s retention window has never been read'];
  else
    v_cov := v_cov || E'\n\n' || 'FORWARDED HISTORY: on '
          || to_char(v_back.finished_at at time zone v_tz, 'DD Mon YYYY HH24:MI') || ' Asia/Dubai (agent_runs #'
          || v_back.id || ') the accountant read the founder''s own record of what he forwarded - a '
          || 'search of his sent mail for ' || coalesce(v_back.counts->>'query','the expenses address')
          || ' returning ' || coalesce(v_back.counts->>'threads_found','?') || ' thread(s) covering '
          || coalesce(v_back.counts->>'period','the whole period') || '. All '
          || coalesce(v_back.counts->>'threads_read','?') || ' were opened and read. '
          || coalesce(v_back.counts->>'amounts_read','?') || ' printed an amount that could be read directly off the receipt; '
          || coalesce(v_back.counts->>'booked','?') || ' were booked here, '
          || coalesce(v_back.counts->>'already_booked','?') || ' were already in the book under their Resend keys, and '
          || coalesce(v_back.counts->>'held','?') || ' were held.';
    if coalesce(v_back.counts->>'date_by_corroboration','0') <> '0' then
      v_cov := v_cov || ' ' || (v_back.counts->>'date_by_corroboration')
            || ' receipt(s) printed an amount but no date, and were dated by matching to the unique '
            || 'source message in the same mailbox rather than by estimate; each says so in its own note.';
    end if;
    if coalesce((v_back.counts->>'more_pages')::boolean, false) then
      v_cov := v_cov || ' THE SEARCH REPORTED MORE RESULTS THAN IT RETURNED, so the forwarded history may be incomplete.';
      v_short := v_short || array['the forwarded-history search did not reach the end of its results'];
    end if;
  end if;

  return jsonb_build_object('note', v_cov, 'shortfalls', to_jsonb(v_short),
    'sweep_run_id', v_sweep.id, 'sweep_at', v_sweep.finished_at, 'sweep_counts', v_sweep.counts,
    'backfill_run_id', v_back.id, 'backfill_at', v_back.finished_at, 'backfill_counts', v_back.counts);
end
$cov$;

revoke execute on function public.fn_accountant_spend_report_coverage() from public;
grant execute on function public.fn_accountant_spend_report_coverage() to service_role;

comment on function public.fn_accountant_spend_report_coverage() is
  'The coverage paragraph for the since-day-one spend report: how much mail was LOOKED AT, across '
  'BOTH sources that can reach expense_entries - Resend''s ~1-month inbound history, and the '
  'founder''s own sent-mail record of what he forwarded before that window. Returns the note plus '
  'the shortfalls that make the total unbounded, so the report can say it is short rather than '
  'quietly appearing complete. Split out of fn_accountant_spend_report so a new source can be added '
  'without touching the arithmetic.';
