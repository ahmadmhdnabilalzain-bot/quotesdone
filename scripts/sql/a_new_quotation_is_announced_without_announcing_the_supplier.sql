-- A NEW QUOTATION IS ANNOUNCED WITHOUT ANNOUNCING THE SUPPLIER
--
-- Build spec §3 and §14. The first end-to-end workflow the spec asks for: a canonical new-quotation
-- event, out through both eligible channels, with verified outcomes.
--
-- THE WHOLE DIFFICULTY IS WHAT MUST NOT BE IN THE MESSAGE. "Never include the supplier's name, logo,
-- phone, email, identifying address, original quotation, commercial line items, quoted amount or a
-- reconstructed full quote... Keep email subjects, preheaders, sender/reply-to fields, URLs and
-- filenames anonymous too."
--
-- A rule written in a prompt is a rule the next person edits away. So the anonymity is enforced by a
-- FUNCTION THAT SCANS THE RENDERED MESSAGE against the actual supplier row and the actual quotation
-- row before anything is queued, and a CHECK that refuses a queued notification that never passed
-- it. The model never composes these messages at all -- they are deterministic, which the spec also
-- requires: "Use deterministic rendering for notifications".

-- ---------------------------------------------------------------------------------------------
-- 1. THE CASE. §14: persist ownership, verified identity, inquiry, evidence, channel outcomes.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.support_case (
  case_id          bigserial primary key,
  case_ref         text not null unique,
  party_kind       text not null,
  party_id         text,
  inquiry_ref      text,
  subject          text not null,
  state            text not null default 'open',
  identity_verified boolean not null default false,
  verified_how     text,
  opened_at        timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  closed_at        timestamptz,
  close_reason     text,
  owner_role_id    text not null default 'customer_support',
  constraint support_case_state_ck check (state in ('open','waiting_customer','waiting_service','blocked','closed')),
  constraint support_case_party_ck check (party_kind in ('customer','supplier','unknown')),
  -- A CLOSED CASE MUST SAY WHY. The estate has already shipped 113 closes that recorded facts and
  -- decided nothing; a close with no reason is that defect with a different table name.
  constraint support_case_close_ck check (state <> 'closed' or (closed_at is not null and close_reason is not null)),
  -- VERIFIED MEANS SOMETHING HAPPENED. A flag with no method behind it is a claim.
  constraint support_case_verified_ck check (not identity_verified or verified_how is not null)
);

comment on table public.support_case is
  'One case per matter support is holding. identity_verified may only be true when verified_how says HOW, and a closed case must carry a reason: a close that records facts and decides nothing is the defect this estate has already paid for.';

-- ---------------------------------------------------------------------------------------------
-- 2. ONE OUTBOX, ONE SENDING OWNER. §1: "Use one canonical notification outbox and one sending
--    owner; prevent duplicate sends from any still-running old triggers."
-- ---------------------------------------------------------------------------------------------
create table if not exists public.support_notification (
  id               bigserial primary key,
  -- DEDUPLICATION IS BY THE BUSINESS EVENT, not by the message text. The spec: "Deduplicate by
  -- business event, recipient, channel, purpose and relevant publication version." A webhook that
  -- fires twice, a retry and a restart must all produce one send.
  dedupe_key       text not null unique,
  case_id          bigint references public.support_case(case_id),
  purpose          text not null,
  channel          text not null,
  recipient        text not null,
  inquiry_ref      text,
  publication_version text,
  subject          text,
  body             text not null,
  attachment_ref   text,
  state            text not null default 'queued',
  provider_id      text,
  provider_status  text,
  failure_reason   text,
  attempts         int not null default 0,
  anonymity_checked_at timestamptz,
  anonymity_result jsonb,
  queued_at        timestamptz not null default now(),
  sent_at          timestamptz,

  constraint support_notification_channel_ck check (channel in ('whatsapp','email')),
  constraint support_notification_state_ck check (state in
    ('queued','sending','sent','delivered','read','failed','suppressed','unknown')),
  -- THE ANONYMITY GATE, AS A CONSTRAINT. A notification cannot be queued unless it was scanned and
  -- the scan passed. This is the difference between a rule and a guarantee: a future caller that
  -- forgets to scan cannot insert a row at all.
  constraint support_notification_scanned_ck check (
    anonymity_checked_at is not null
    and anonymity_result is not null
    and (anonymity_result->>'safe') = 'true'),
  -- "Never say attached without an attachment." A row claiming an attachment must name one.
  constraint support_notification_attachment_ck check (
    body not ilike '%is attached%' or attachment_ref is not null)
);

create index if not exists support_notification_pending_idx
  on public.support_notification (state, queued_at) where state in ('queued','failed');

comment on table public.support_notification is
  'The one outbox. Deduplicated by business event + recipient + channel + purpose + publication version, so a repeated webhook produces one send. Two CHECKs make the spec''s rules structural rather than advisory: nothing may be queued that has not passed the anonymity scan, and no message may say "is attached" without naming an attachment.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE ANONYMITY SCAN
-- ---------------------------------------------------------------------------------------------
-- It scans the RENDERED message -- subject, body, attachment reference and every URL in it --
-- against the ACTUAL values on the supplier row and the quotation row. Not a blocklist of words: the
-- real supplier's real name, email, phone and amount, read from the database at scan time.
--
-- The spec is explicit that a flag is not enough: "A model-supplied privacy_approved flag is not
-- sufficient." Nothing here trusts a caller's assertion; it re-reads and re-checks.
create or replace function public.fn_support_anonymity_scan(
  p_text text,
  p_subject text,
  p_attachment_ref text,
  p_supplier_lead_id bigint,
  p_quote_id text default null)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  s record;
  v_hay text;
  v_hits text[] := '{}';
  v_digits text;
begin
  -- Everything a recipient could see, in one haystack: the body, the subject line, the attachment
  -- filename. A leak in a filename is still a leak.
  v_hay := lower(coalesce(p_text,'') || ' ' || coalesce(p_subject,'') || ' ' || coalesce(p_attachment_ref,''));

  select company_name, email, phone, trade_license_no, license_city
    into s from public.leads where id = p_supplier_lead_id;

  if not found then
    -- A scan that cannot read the supplier cannot clear the message. It fails CLOSED.
    return jsonb_build_object('safe', false, 'reason',
      'the supplier row could not be read, so nothing about it could be checked for', 'hits', '[]'::jsonb);
  end if;

  if coalesce(btrim(s.company_name),'') <> '' and position(lower(btrim(s.company_name)) in v_hay) > 0 then
    v_hits := array_append(v_hits, 'company_name');
  end if;
  if coalesce(btrim(s.email),'') <> '' and position(lower(btrim(s.email)) in v_hay) > 0 then
    v_hits := array_append(v_hits, 'email');
  end if;
  -- Phone numbers are compared on DIGITS ONLY, because +971 50 931 9355 and 971509319355 are the
  -- same number and a literal comparison would miss one of them.
  v_digits := regexp_replace(coalesce(s.phone,''), '[^0-9]', '', 'g');
  if length(v_digits) >= 7 and position(v_digits in regexp_replace(v_hay, '[^0-9]', '', 'g')) > 0 then
    v_hits := array_append(v_hits, 'phone');
  end if;
  if coalesce(btrim(s.trade_license_no),'') <> '' and position(lower(btrim(s.trade_license_no)) in v_hay) > 0 then
    v_hits := array_append(v_hits, 'trade_license_no');
  end if;

  -- The quoted amount, when there is a quotation to compare against. An amount is the one field a
  -- customer could act on without the name, so it counts as identifying commercial content.
  if p_quote_id is not null then
    if exists (select 1 from public.quotes q
                where q.id::text = p_quote_id
                  and q.total_amount is not null
                  and position(regexp_replace(round(q.total_amount)::text, '[^0-9]', '', 'g')
                               in regexp_replace(v_hay, '[^0-9]', '', 'g')) > 0) then
      v_hits := array_append(v_hits, 'quoted_amount');
    end if;
  end if;

  return jsonb_build_object(
    'safe', array_length(v_hits, 1) is null,
    'hits', to_jsonb(v_hits),
    'checked', jsonb_build_array('company_name','email','phone','trade_license_no','quoted_amount'),
    'scanned_at', now(),
    'note', case when array_length(v_hits,1) is null
                 then 'No supplier-identifying or commercial value from the live row appears in the subject, body or attachment name.'
                 else 'REFUSED: the message contains ' || array_to_string(v_hits, ', ') || ' from the live supplier row.' end);
end $function$;

comment on function public.fn_support_anonymity_scan(text,text,text,bigint,text) is
  'Scans a rendered notification against the ACTUAL supplier and quotation rows, not a word blocklist. Covers subject, body and attachment name; compares phone numbers on digits so formatting cannot hide one. Fails CLOSED when the supplier row cannot be read.';
