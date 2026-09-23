-- FINDING A LEAD BY ITS EMAIL OR ITS HANDSET USES AN INDEX (22 Sep 2026, it_engineer, CONN-05).
--
-- leads is 22,266 rows. Two lookups run against it on hot paths and neither had an index it could use.
--
-- 1. lower(email). uq_leads_email_lower exists but it is PARTIAL:
--       unique (lower(email)) where email is not null and email <> ''
--    A partial index is only usable when the planner can PROVE the query implies the predicate.
--    `lower(email) = $1` implies email is not null (a strict operator), but nothing in it implies
--    email <> '', so the proof fails and the index is skipped. A unique constraint that cannot be read
--    is still a constraint and is kept; this adds the plain index the readers can actually use.
--
-- 2. the last nine digits of a phone. fn_whatsapp_owner — the routine that decides whose handset an
--    inbound WhatsApp message is, on every message — matches
--       right(regexp_replace(coalesce(l.phone,''), '[^0-9]', '', 'g'), 9) = <tail>
--    against BOTH l.phone and l.whatsapp_phone. That expression appears in no index, so each inbound
--    message ran regexp_replace over 22,266 rows twice. The same nine-digit form is how the estate
--    compares numbers everywhere ("a phone may confirm, never select"), so the expression is indexed
--    rather than the column.
--
-- IMMUTABILITY, checked and not assumed: right(), regexp_replace() with a constant pattern and flags,
-- and coalesce() are all immutable, so the expression is indexable as written. lower() likewise.
--
-- CREATE INDEX, NOT CREATE INDEX CONCURRENTLY: apply_sql.mjs runs each file as ONE transaction and
-- CONCURRENTLY cannot run inside one. On 22,266 rows a plain build takes well under a second and the
-- ACCESS EXCLUSIVE lock it holds is that long. (kb_chunks, at 148k rows and 8 GB, would not be — this
-- is a judgement about this table's size, not a general licence.)
--
-- AND IT WAITS FOR THE LOCK FOR AT MOST FIVE SECONDS. The reviewer's first probe of this file was
-- CANCELLED by live traffic holding `leads`, which is the whole risk of a short lock on a busy table:
-- not the build, but the QUEUE behind a lock request, since every reader arriving after it waits too.
-- With lock_timeout the apply fails fast and harmlessly instead of stalling the supplier funnel, and it
-- can simply be run again. The estate has the matching operational rule already — an apply took 75 s and
-- locked sign-in (21 Sep) — so: DO NOT RUN THIS DURING A CAMPAIGN HOUR, when enqueue_supplier_invites
-- and the portal are both on `leads`.
set local lock_timeout = '5s';

create index if not exists leads_email_lower_idx
  on public.leads (lower(email));

create index if not exists leads_phone_tail9_idx
  on public.leads (right(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), 9));

create index if not exists leads_whatsapp_phone_tail9_idx
  on public.leads (right(regexp_replace(coalesce(whatsapp_phone, ''), '[^0-9]', '', 'g'), 9));

comment on index public.leads_email_lower_idx is
  'The readable half of uq_leads_email_lower: that one is partial on email <> '''' and the planner cannot prove it. CONN-05.';
comment on index public.leads_phone_tail9_idx is
  'The last-9-digit form fn_whatsapp_owner matches on, indexed as the expression it is. CONN-05.';
comment on index public.leads_whatsapp_phone_tail9_idx is
  'The same, for the separately-registered WhatsApp handset. CONN-05.';
