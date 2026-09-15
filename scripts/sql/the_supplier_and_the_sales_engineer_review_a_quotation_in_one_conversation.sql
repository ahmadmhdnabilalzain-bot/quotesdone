-- the_supplier_and_the_sales_engineer_review_a_quotation_in_one_conversation.sql
-- Assigned: sales_engineer — the supplier portal's quotation review (founder, 14 Sep 2026: "its always
-- the sales agent. no other agent is involved in customer or supplier portal").
--
-- THE FOUNDER, 15 Sep 2026 (verbatim in public.founder_instruction, section 0): the Quotations
-- submitted tab opens a chat with the sales engineer; the supplier attaches the quotation; the engineer
-- reviews it immediately against our rules and replies "Quotation approved for submission" or lists the
-- adjustments and clarifications line by line; the supplier answers in free text or with a revised
-- file; finally the engineer asks whether they will upload a new version or have it generated, and once
-- done the quotation is submitted to the inquiry and the conversation ends. And: "later this will be a
-- mobile app as well. the structure need to be built in already" — so the conversation's state lives
-- in these tables and in supplier_api, never in a browser.
--
-- MEASURED BEFORE (production, 15 Sep 2026, read-only):
--   * public.quote_reviews (13 columns) and public.quote_review_messages (6 columns) already exist, from
--     the 1 Jul 2026 review subsystem (supabase/migrations_history/20260701131409_quote_review_subsystem.sql).
--     Both hold 0 rows, no routine writes either, and both have RLS ON with NO policy.
--   * quote_review_messages is already a REGISTERED CONVERSATION STORE: v_conversation_message reads it,
--     so its rows are archived to PDF and Dropbox and are never purged
--     (every_conversation_is_kept_backed_up_twice_and_readable_by_the_sales_engineer.sql). This change
--     therefore EXTENDS those two tables rather than writing a second conversation store beside them.
--   * v_conversation_message's quote_review_messages branch was written for the old roles: a SUPPLIER's
--     message was classed 'out' (only role 'customer' was 'in'), no party was resolved, and is_demo was
--     always false — so a ZZ DEMO fixture's messages would have been archived into the real backups.
--   * quote_reviews had no foreign key to inquiries or leads, and nothing tracked a point the engineer
--     raised until it was answered.
--
-- WHAT THIS CHANGES:
--   1. quote_reviews gains the conversation's state (status, the supplier's choice, the working quotation,
--      the last review, the submitted quote ids, the owner's address for its own-row policy), with CHECKs
--      naming every state and choice, and foreign keys to inquiries and leads (no cascade: a conversation
--      is never deleted by deleting its parent).
--   2. quote_review_messages gains kind, the Arabic text of the engineer's message, and the points a
--      review raised; role is 'supplier' or 'sales_engineer' — the seat is the author of every engineer
--      message.
--   3. public.quote_review_request — every point the engineer raises, open until answered (founder:
--      "nothing is one-way").
--   4. RLS: a signed-in supplier reads only their own reviews, messages and requests; nobody but the
--      service role writes. anon reads nothing.
--   5. v_conversation_message: copied VERBATIM from its MANIFEST-last definition (every_conversation_is_
--      kept_backed_up_twice_and_readable_by_the_sales_engineer.sql) with ONE branch changed — the
--      quote_review_messages branch now reads the supplier's message as 'in', resolves the party through
--      fn_conversation_party, and marks a demo supplier's messages demo. This file is now the canonical one.
--
-- WHAT IT DOES NOT CHANGE: no quote row is written here or by the conversation itself — submission goes
-- through supplier_api submit_quote, so the hold gate, the accept rule and everything downstream are
-- untouched. quote_committed_items (the 1 Jul subsystem's third table, 0 rows) is left as it is.

-- ── 0. HIS WORDS FIRST ─────────────────────────────────────────────────────────────────────────
insert into public.founder_instruction (said_at, instruction, subject, status, note)
select '2026-09-15 12:00+04', v.i, 'supplier portal: inquiries received and the quotation review', 'open', v.n
from (values
  ('this is the most important part in the whole supplier portal, so make sure its built perfectly',
   'Inquiries received (job number, the inquiry as prepared, redacted BOQ and drawings downloadable) and Quotations submitted (a chat with the sales engineer who reviews the attached quotation at once by rule, approves or lists line-by-line adjustments, answers the supplier, asks upload-or-generate, then submits through submit_quote and closes the thread). supplier_api quote_review_flow.ts; this file.'),
  ('later this will be a mobile app as well. the structure need to be built in already',
   'API-first: every step is a supplier_api action with typed request and response shapes (docs/api/supplier_portal_quotations.md); the conversation state and the review rules live on the server; uploads are base64 in JSON, callable from a native app.')
) v(i, n)
where not exists (select 1 from public.founder_instruction f where f.instruction = v.i);

-- ── 1. THE REVIEW: ONE PER (INQUIRY, SUPPLIER), AND ITS STATE ──────────────────────────────────
alter table public.quote_reviews
  add column if not exists owner_email text,
  add column if not exists choice text,
  add column if not exists working jsonb,
  add column if not exists last_review jsonb,
  add column if not exists reviewing_since timestamptz,
  add column if not exists submitted_quote_ids uuid[],
  add column if not exists owner_seat text not null default 'sales_engineer';
alter table public.quote_reviews drop constraint if exists quote_reviews_status_known;
alter table public.quote_reviews add constraint quote_reviews_status_known
  check (status in ('open', 'reviewing', 'changes_requested', 'awaiting_choice', 'awaiting_upload', 'ready_to_submit', 'submitted', 'closed'));
alter table public.quote_reviews drop constraint if exists quote_reviews_choice_known;
alter table public.quote_reviews add constraint quote_reviews_choice_known check (choice is null or choice in ('generate', 'reupload'));
alter table public.quote_reviews drop constraint if exists quote_reviews_owner_seat;
alter table public.quote_reviews add constraint quote_reviews_owner_seat check (owner_seat = 'sales_engineer');
alter table public.quote_reviews drop constraint if exists quote_reviews_submitted_has_quotes;
alter table public.quote_reviews add constraint quote_reviews_submitted_has_quotes
  check (status <> 'submitted' or (completed_at is not null and coalesce(array_length(submitted_quote_ids, 1), 0) > 0));
alter table public.quote_reviews drop constraint if exists quote_reviews_inquiry_id_fkey;
alter table public.quote_reviews add constraint quote_reviews_inquiry_id_fkey foreign key (inquiry_id) references public.inquiries(id) not valid;
alter table public.quote_reviews validate constraint quote_reviews_inquiry_id_fkey;
alter table public.quote_reviews drop constraint if exists quote_reviews_supplier_id_fkey;
alter table public.quote_reviews add constraint quote_reviews_supplier_id_fkey foreign key (supplier_id) references public.leads(id) not valid;
alter table public.quote_reviews validate constraint quote_reviews_supplier_id_fkey;
comment on table public.quote_reviews is 'The quotation conversation between one supplier and the sales_engineer seat on one inquiry (founder, 15 Sep 2026). State machine in supabase/functions/supplier_api/quote_review_flow.ts. Written only by the service role; the supplier reads their own row.';
comment on column public.quote_reviews.status is 'open | reviewing | changes_requested | awaiting_choice | awaiting_upload | ready_to_submit | submitted | closed (quote_review_flow.ts).';
comment on column public.quote_reviews.working is 'The quotation under review: what the last file said plus every detail the supplier confirmed in the chat (quote_review.ts Working).';
comment on column public.quote_reviews.last_review is 'The last review the sales engineer ran: approved, the points raised, the price excluding VAT.';
comment on column public.quote_reviews.owner_email is 'The claimed_by address of the company that owns this review, refreshed on every action; the supplier''s own-row policy reads it.';
comment on column public.quote_reviews.submitted_quote_ids is 'The quote rows submit_quote created when the conversation submitted (one per option).';

-- ── 2. THE MESSAGES: THE REGISTERED CONVERSATION STORE ─────────────────────────────────────────
alter table public.quote_review_messages
  add column if not exists kind text not null default 'text',
  add column if not exists body_ar text,
  add column if not exists issues jsonb;
alter table public.quote_review_messages drop constraint if exists quote_review_messages_role_known;
alter table public.quote_review_messages add constraint quote_review_messages_role_known check (role in ('supplier', 'sales_engineer'));
alter table public.quote_review_messages drop constraint if exists quote_review_messages_kind_known;
alter table public.quote_review_messages add constraint quote_review_messages_kind_known
  check (kind in ('text', 'file', 'review', 'choice_prompt', 'choice', 'submitted', 'notice'));
comment on table public.quote_review_messages is 'One message of a quotation conversation. role sales_engineer = written by that seat (body English, body_ar Arabic); role supplier = the supplier''s own words in body. A registered conversation store: kept permanently, archived by conversation_archive.';

-- ── 3. EVERY POINT RAISED, OPEN UNTIL ANSWERED ─────────────────────────────────────────────────
create table if not exists public.quote_review_request (
  id bigint generated always as identity primary key,
  review_id uuid not null references public.quote_reviews(id),
  key text not null,
  code text not null,
  kind text not null check (kind in ('adjustment', 'clarification', 'choice')),
  line_no integer,
  boq_line integer,
  attr text,
  label_en text not null,
  label_ar text not null,
  state text not null default 'open' check (state in ('open', 'answered', 'superseded')),
  asked_message_id uuid references public.quote_review_messages(id),
  answered_message_id uuid references public.quote_review_messages(id),
  opened_at timestamptz not null default now(),
  answered_at timestamptz,
  check ((state = 'open') = (answered_at is null))
);
comment on table public.quote_review_request is 'A point the sales engineer raised in a quotation conversation — an adjustment, a clarification or the upload-or-generate choice — tracked until the supplier answers it (founder: "nothing is one-way").';
create unique index if not exists quote_review_request_one_open on public.quote_review_request (review_id, key) where state = 'open';
create index if not exists quote_review_request_by_review on public.quote_review_request (review_id, state);
create index if not exists quote_review_messages_by_review_kind on public.quote_review_messages (review_id, kind);

-- ── 4. WHO READS WHAT ──────────────────────────────────────────────────────────────────────────
-- The supplier reads their own conversation directly as well as through supplier_api, so a mobile app
-- can subscribe to it. The address is the one the portal signs in with (leads.claimed_by); a policy
-- cannot read leads itself (its RLS admits only owner/admin), so the review carries it.
alter table public.quote_review_request enable row level security;
revoke all on public.quote_reviews, public.quote_review_messages, public.quote_review_request from anon, authenticated;
grant select on public.quote_reviews, public.quote_review_messages, public.quote_review_request to authenticated;

drop policy if exists quote_reviews_supplier_reads_own on public.quote_reviews;
create policy quote_reviews_supplier_reads_own on public.quote_reviews as permissive for select to authenticated
  using (owner_email is not null and owner_email = lower(coalesce(auth.jwt() ->> 'email', '')));
drop policy if exists quote_review_messages_supplier_reads_own on public.quote_review_messages;
create policy quote_review_messages_supplier_reads_own on public.quote_review_messages as permissive for select to authenticated
  using (exists (select 1 from public.quote_reviews r where r.id = quote_review_messages.review_id
                   and r.owner_email is not null and r.owner_email = lower(coalesce(auth.jwt() ->> 'email', ''))));
drop policy if exists quote_review_request_supplier_reads_own on public.quote_review_request;
create policy quote_review_request_supplier_reads_own on public.quote_review_request as permissive for select to authenticated
  using (exists (select 1 from public.quote_reviews r where r.id = quote_review_request.review_id
                   and r.owner_email is not null and r.owner_email = lower(coalesce(auth.jwt() ->> 'email', ''))));

-- ── 5. THE CONVERSATION RECORD READS THE SUPPLIER'S SIDE THE RIGHT WAY ROUND ───────────────────
-- Copied VERBATIM from every_conversation_is_kept_backed_up_twice_and_readable_by_the_sales_engineer.sql;
-- only the last branch (quote_review_messages) differs.
create or replace view public.v_conversation_message as
select 'inbound_messages'::text as source_table, m.id::text as source_id, 'email'::text as channel, 'in'::text as direction,
       m.created_at as occurred_at, m.from_email as from_addr, m.to_email as to_addr, null::text as cc,
       m.subject, m.body, m.html, jsonb_build_object('count', coalesce(m.attachments_count, 0)) as attachments,
       p.party_kind, p.party_id, p.inquiry_id,
       (coalesce(m.from_email, '') ~* 'example\.invalid' or p.demo) as is_demo
  from public.inbound_messages m
  cross join lateral public.fn_conversation_party(m.lead_id, null, null, m.from_email, null) p
union all
select 'notifications', n.id::text, coalesce(n.channel, 'email'), 'out',
       coalesce(n.sent_at, n.created_at), coalesce(n.sender, 'QuotesDone'), coalesce(n.to_email, n.to_phone),
       array_to_string(n.cc_emails, ', '), n.subject, n.body, n.html, coalesce(n.attachments, '[]'::jsonb),
       p.party_kind, p.party_id, coalesce(p.inquiry_id, n.inquiry_id::text),
       (coalesce(n.to_email, '') ~* 'example\.invalid' or coalesce(n.subject, '') ~* 'ZZ DEMO' or p.demo)
  from public.notifications n
  cross join lateral public.fn_conversation_party(n.lead_id, null, n.inquiry_id, n.to_email, n.to_phone) p
 where n.status = 'sent' and coalesce(n.channel, 'email') in ('email', 'whatsapp')
union all
select 'wa_messages', w.id::text, 'whatsapp', 'in', w.created_at, w.wa_from, w.wa_to, null,
       'WhatsApp' || coalesce(' from ' || nullif(w.profile_name, ''), ''),
       'Received:' || E'\n' || coalesce(w.inbound, '')
         || case when coalesce(w.reply, '') <> '' then E'\n\n' || 'Replied' || case when w.sent then '' else ' (not delivered)' end || ':' || E'\n' || w.reply else '' end,
       null, '[]'::jsonb, p.party_kind, p.party_id, p.inquiry_id, p.demo
  from public.wa_messages w
  cross join lateral public.fn_conversation_party(null, null, null, null, w.wa_from) p
union all
select 'messages', pm.id::text, 'chat', case when pm.sender in ('customer', 'supplier') then 'in' else 'out' end,
       pm.created_at, pm.sender, null, null, 'Portal chat - ' || coalesce(pm.sender, ''),
       pm.body || coalesce(E'\n\n' || 'Attachment: ' || pm.attachment_path, ''), null,
       case when pm.attachment_path is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('path', pm.attachment_path)) end,
       p.party_kind, p.party_id, coalesce(p.inquiry_id, pm.inquiry_id::text), p.demo
  from public.messages pm
  cross join lateral public.fn_conversation_party(pm.supplier_id, pm.customer_id, pm.inquiry_id, null, null) p
union all
select 'rfq_clarification', r.id::text, 'chat', 'in', r.asked_at, 'supplier ' || coalesce(r.supplier_id::text, ''), null, null,
       'Clarification - ' || coalesce(r.kind, ''),
       'Question:' || E'\n' || coalesce(r.question, '') || case when r.answer is not null then E'\n\n' || 'Answer:' || E'\n' || r.answer else '' end,
       null, '[]'::jsonb, p.party_kind, p.party_id, coalesce(p.inquiry_id, r.inquiry_id::text), p.demo
  from public.rfq_clarification r
  cross join lateral public.fn_conversation_party(r.supplier_id, null, r.inquiry_id, null, null) p
union all
select 'assistant_logs', a.id::text, 'chat', 'in', a.created_at,
       case when a.audience ~ '^customer:' then 'portal customer' else 'website visitor' end, coalesce(a.seat, 'customer_support'), null,
       case when a.seat = 'sales_engineer' then 'Portal - sales engineer' else 'Website assistant' end || coalesce(' - ' || a.path, ''),
       'Asked:' || E'\n' || coalesce(a.message, '') || E'\n\n' || 'Answered:' || E'\n' || coalesce(a.reply, ''),
       null, '[]'::jsonb, p.party_kind, p.party_id, p.inquiry_id, p.demo
  from public.assistant_logs a
  cross join lateral public.fn_conversation_party(null,
       case when a.audience ~ '^customer:[0-9a-f-]{36}$' then substring(a.audience from 10)::uuid end, null, null, null) p
union all
select 'contact_messages', cm.id::text, 'form', 'in', cm.created_at, coalesce(cm.email, cm.phone), null, null,
       'Contact form' || coalesce(' - ' || cm.name, ''), cm.message, null, '[]'::jsonb,
       p.party_kind, p.party_id, p.inquiry_id, (coalesce(cm.email, '') ~* 'example\.invalid' or p.demo)
  from public.contact_messages cm
  cross join lateral public.fn_conversation_party(null, null, null, cm.email, cm.phone) p
union all
select 'complaint_tickets', ct.id::text, 'form', 'in', ct.created_at, ct.email, null, null,
       'Complaint ' || coalesce(ct.ticket_no, ''),
       coalesce(ct.message, '') || case when ct.final_response is not null then E'\n\n' || 'Final response:' || E'\n' || ct.final_response else '' end,
       null, '[]'::jsonb, p.party_kind, p.party_id, p.inquiry_id, (coalesce(ct.email, '') ~* 'example\.invalid' or p.demo)
  from public.complaint_tickets ct
  cross join lateral public.fn_conversation_party(null, null, null, ct.email, null) p
union all
-- 15 Sep 2026: the supplier's side of a quotation conversation is 'in', the sales engineer's 'out';
-- the party is the supplier on the review, and a demo supplier's conversation is demo (never archived).
select 'quote_review_messages', q.id::text, 'chat', case when q.role = 'supplier' then 'in' else 'out' end, q.created_at,
       case when q.role = 'supplier' then 'supplier ' || coalesce(qr.supplier_id::text, '') else coalesce(q.role, '') end, null, null,
       'Quotation review - job ' || upper(left(coalesce(qr.inquiry_id::text, ''), 8)) || ' - ' || coalesce(q.role, ''),
       coalesce(q.body, '') || case when coalesce(q.body_ar, '') <> '' then E'\n\n' || q.body_ar else '' end,
       null, coalesce(q.attachments, '[]'::jsonb),
       p.party_kind, p.party_id, coalesce(p.inquiry_id, qr.inquiry_id::text), p.demo
  from public.quote_review_messages q
  join public.quote_reviews qr on qr.id = q.review_id
  cross join lateral public.fn_conversation_party(qr.supplier_id, null, qr.inquiry_id, null, null) p;
revoke all on public.v_conversation_message from public, anon, authenticated;

-- ── 6. PROBE ───────────────────────────────────────────────────────────────────────────────────
-- This file defines things, so the probe ends in a notice. Its writes are made inside a sub-block that
-- always raises and is caught: the savepoint rolls them back, the DDL above stays. It uses a ZZ DEMO
-- supplier and a demo customer's inquiry only, and skips (saying so) when none exists; it never touches
-- a real company, and nothing it writes can notify anyone (no trigger on these tables sends anything).
do $$
declare
  v_lead bigint; v_inq uuid; v_rev uuid; v_msg uuid; v_dir text; v_demo boolean;
  v_before bigint; v_after bigint; v_bad boolean := false;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public'
        and ((table_name = 'quote_reviews' and column_name in ('owner_email', 'choice', 'working', 'last_review', 'reviewing_since', 'submitted_quote_ids', 'owner_seat'))
          or (table_name = 'quote_review_messages' and column_name in ('kind', 'body_ar', 'issues')))) <> 10 then
    raise exception 'CHK<<the conversation columns are not all there>>';
  end if;
  if exists (select 1 from pg_class where oid in ('public.quote_reviews'::regclass, 'public.quote_review_messages'::regclass, 'public.quote_review_request'::regclass) and not relrowsecurity)
     or (select count(*) from pg_policies where schemaname = 'public' and tablename in ('quote_reviews', 'quote_review_messages', 'quote_review_request')) < 3 then
    raise exception 'CHK<<a conversation table without RLS and its policy>>';
  end if;
  if has_table_privilege('anon', 'public.quote_review_messages', 'select') or has_table_privilege('authenticated', 'public.quote_review_messages', 'insert') then
    raise exception 'CHK<<anon can read, or a signed-in user can write, the conversation>>';
  end if;

  select l.id into v_lead from public.leads l where l.company_name ~* '^ZZ DEMO' and coalesce(l.email, '') ~* 'example\.invalid$' order by l.id desc limit 1;
  select i.id into v_inq from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.email ~* 'example\.invalid$' and c.full_name ~* '^ZZ DEMO' order by i.created_at desc limit 1;
  if v_lead is null or v_inq is null then
    raise notice 'CHK<<structure verified; the write probe was skipped: no ZZ DEMO supplier and demo inquiry to probe with>>';
    return;
  end if;
  select count(*) into v_before from public.quote_reviews;
  begin
    insert into public.quote_reviews (inquiry_id, supplier_id, owner_email, status) values (v_inq, v_lead, 'probe@example.invalid', 'open') returning id into v_rev;
    insert into public.quote_review_messages (review_id, role, kind, body) values (v_rev, 'supplier', 'file', 'ZZ DEMO probe') returning id into v_msg;
    insert into public.quote_review_request (review_id, key, code, kind, label_en, label_ar, asked_message_id) values (v_rev, 'validity|||validity', 'validity', 'adjustment', 'probe', 'probe', v_msg);
    select direction, is_demo into v_dir, v_demo from public.v_conversation_message where source_table = 'quote_review_messages' and source_id = v_msg::text;
    if v_dir is distinct from 'in' or v_demo is not true then v_bad := true; end if;
    begin
      update public.quote_reviews set status = 'complete' where id = v_rev;
      v_bad := true;   -- the old free-text status must be refused
    exception when check_violation then null;
    end;
    raise exception 'probe_rollback';
  exception when others then
    if sqlerrm <> 'probe_rollback' then raise exception 'CHK<<probe failed: %>>', sqlerrm; end if;
  end;
  select count(*) into v_after from public.quote_reviews;
  if v_bad then raise exception 'CHK<<a supplier message read as "%" (demo %), or an unknown status was accepted>>', v_dir, v_demo; end if;
  if v_after <> v_before then raise exception 'CHK<<the probe left % review row(s) behind>>', v_after - v_before; end if;
  raise notice 'CHK<<quotation conversation ready: supplier messages read in, demo kept out of the archive, unknown status refused, probe left nothing>>';
end $$;
