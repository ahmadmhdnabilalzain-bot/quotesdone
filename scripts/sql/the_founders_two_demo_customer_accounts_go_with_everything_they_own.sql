-- THE FOUNDER'S TWO DEMO CUSTOMER ACCOUNTS GO, WITH EVERYTHING THEY OWN, AND NOTHING ELSE MOVES
-- (it_engineer; 18 Nov 2026; founder ruling 1732, which closes 1539).
--
-- The founder, 18 Nov 2026 (ledger 1732): "Go-ahead to remove the founder's two demo customer accounts (0dc8c94f,
-- ba61fa16) and their Dropbox folders (closes 1539)." On 3 Nov (1539) he had asked for them to go "so no agent is
-- confused". Until now every purge was required to KEEP them: the_last_demo_rows_are_purged_and_no_real_row_moves.sql
-- (applied 17 Nov 23:47Z) is the model this file follows: one guarded REPEATABLE READ transaction, a census pin, an exact
-- per-table delta, foreign-key pins to every real party, a SET NULL guard, storage and Dropbox queued for dropbox_backup,
-- and a PROBE OK verdict that scripts/apply_sql.mjs reads.
--
-- THE TOOL IS THE EXISTING ONE: public.fn_demo_purge_walk (production md5 f80d12bd8d611c2a251129401666f2b7, read 18 Nov),
--   the routine fn_demo_purge_run uses for every table it purges: it walks every foreign-key child first, unlinks (and
--   reports) a SET NULL reference instead of deleting it, refuses data-request evidence (QD196) and any ledger table
--   (QD197), and returns what it deleted per table ('touched'). fn_demo_purge(true) itself is NOT called: it picks rows by
--   marker across the whole estate (every run-tagged cost row, every qd_run window, the 82 frozen Dropbox paths re-queued),
--   so running it would delete rows that are not theirs; the two cannot be "marked" demo anyway (customers.is_demo is a
--   generated column: a reserved address, the fixture mobile or a ZZ DEMO name, none of which is theirs); and it cannot reach the
--   two logins at all (their auth ids are not the customer ids, see below). So the walk is called here once per table, in
--   fn_demo_purge_run's own order, on rows chosen by id, never by a pattern.
--
-- MEASURED (SELECT on tables and the catalogue only, production, 18 Nov 2026 ~16:30-17:20Z; every table of public, auth and
--   storage scanned for the two customer ids, the two login ids, the two addresses and the two mobile numbers):
--   customers       0dc8c94f-903b-440a-b263-9b659513d7d1 "ahmad alzain", outlook.com, created 14 Sep 2026, is_demo false;
--                   ba61fa16-74f6-48ce-8cba-90fff5b157f9 "Umarah Nabi", gmail.com, created 3 Oct 2026, is_demo false.
--                   They are the only two rows of public.customers.
--   their logins    auth.users 713af87b-3d51-4da9-be51-b20ba46b085a (created 9 Jun 2026) and b22ee3f5-9b27-46e5-a90f-
--                   8c29138daa55 (3 Oct): the login id is NOT the customer id, so fn_demo_purge_run's rule `u.id in (demo
--                   customers)` would miss them. Pinned here by id; the file checks that each one's e-mail equals its
--                   customer's, never matches by it. With them: auth.identities 2, auth.sessions 1, auth.refresh_tokens 1.
--   requests, quotes, payments: 0 inquiries, 0 quotes, 0 transactions on the whole estate (so no supplier's quote, no payment).
--   their rows      support_customer_profile 2 (53, 223); support_case 2 (981 open, 1207 closed; 0 child rows);
--                   customer_support_duty_message 2; inquiry_intake 3; assistant_logs 9 (their portal chats, audience
--                   customer:<id>); ai_qa_log 2 (their intake reads); notifications 12 (to_role customer, no lead, request
--                   or quote: the activation, CSAT and case-closed mails and their WhatsApp twins); agent_actions 8 (the
--                   delivery handoffs of those notifications, all done) and company_event 18 (2 customer.registered and the
--                   16 events of those handoffs); email_verifications 16 and phone_verifications 6 (customer-kind codes of
--                   the two addresses and numbers); rl_hits 8 and ai_rate_limit 1 (keys on the two addresses).
--   backups         doc_backups 23: the 20 of the two customers whose source goes too (Customer Details, signed terms, the
--                   conversation PDFs of the notifications and chats above), and 3 of the founder's earlier sign-up of
--                   13 Jul 2026 (below). 22 have their copy in the entity tree and are queued for dropbox_backup; 1 (420492)
--                   is under /_archive/superseded-tnc-2026-10-12/, which dropbox_backup may never delete: its record goes
--                   now and the verdict names its Dropbox path for a person to delete by hand.
--   storage         22 objects (17 in backups, 5 in signed-terms), queued for dropbox_backup.
--   THE EARLIER SIGN-UP (question (a) of the brief): "/QuotesDone Backup/Customers/ahmad alzain/Signed-Terms-Acceptance.pdf"
--                   (no id) is the certificate of a customer sign-up on 13 Jul 2026 08:12:22 UTC: name ahmad alzain, the
--                   same outlook.com address as 0dc8c94f (and as login 713af87b, which dates from 9 Jun), Customer Terms
--                   v3. That customer row was gone before 15 Aug (purge_01_empty_the_marketplace.sql lists the two rows then
--                   left). Its records: doc_backups 445188 (the Dropbox sweep's record of that file), 153104 and 1165411
--                   (the storage sweep's copies of the two signed-terms objects customers/1783930331743_ and
--                   customers/1783930349503_ahmad_alzain_TnC-Acceptance.pdf of 13 Jul 08:12:11 and 08:12:30). It is the
--                   founder's, so it goes with this purge, by those exact names.
--
-- LINKS TO A REAL THIRD PARTY (the brief: refuse if any exists). Measured 18 Nov:
--   * fraud_flags (customer_matches_supplier, high, OPEN since 13 Nov): customer 0dc8c94f shares its mobile number with
--     lead 158318, a real supplier the founder keeps. With it: reasoning_held_question 43950, seat_judgement 18826 and 18829
--     (accountant.fraud_flag), support_ceo_report 27404 (overdue report, completed). These are the accountant's case about
--     a real supplier, not rows the account owns: this file never deletes them and REFUSES while that flag is open; the
--     accountant closes it (the match is the founder's own two accounts) before the apply. A closed flag stays as evidence.
--   * not links, and kept: notifications 112172 (supplier_invite_seed to the outlook.com address, to_role supplier) and its
--     handoff 302078; lead 158318's own rows on the shared number (notifications 143321, 143323, 143418, 149957, its
--     supplier KYC phone_code 2, phone_verifications eae409ba, rl_hits 31950); rl_hits 247 and 3996 (keyed by a mobile
--     number); the founder's address inside company records (gl_journal memo, app_secrets, founder_instruction,
--     routine_change_log, the accountant's close pack, the expense vendor mailbox, inbound_messages 143).
--   * four backup copies filed under 0dc8c94f whose SOURCE is not the account's (doc_backups 52497 and 52501: WhatsApp #29/#30
--     of 28 Jul from the founder's own number; 53162: inbound_messages 143, a GoDaddy receipt forwarded to the company;
--     710220: notifications 112172 above). Their sources stay, so their copies stay (records, storage objects and the four
--     files in "Customers/ahmad alzain (0dc8c94f)/Correspondence/"): re-filing them is a separate decision.
--   * the sales engineer's knowledge-gap tasks raised from their chats (579854, 580660-580666) carry no id of theirs: kept.
--
-- WHAT THIS FILE DOES, in ONE transaction at REPEATABLE READ (one snapshot, so before and after are exact):
--   1. the census: the two customers and two logins by id, and every row each rule below picks, pinned to the counts above;
--      any other count (other than an all-zero census, a repeat after success) and nothing is deleted;
--   2. the refusals before anything moves: an open fraud flag on them; any request, quote or payment of theirs; a picked row
--      that names a lead, a request, a quote or a payment; a row outside the picked set that holds a SET NULL reference to
--      one of the two customers or logins;
--   3. the scope: every table picked and every foreign-key descendant of one; its row count BEFORE (query_to_xml: read-only);
--      the foreign-key pins (rows pointing at any customer, lead, inquiry, quote, transaction or login that is not one of
--      these) and an md5 of every kept row named above;
--   4. the walk, table by table; then storage and Dropbox are LISTED in signup_purge_object / signup_purge_dropbox (kind
--      demo_purge) and dropbox_backup removes them 15 minutes later (storage through the storage API; Dropbox only for a
--      file in the entity tree, signupPurgeDeleteAllowed in supabase/functions/dropbox_backup/purge.ts), deleting each
--      backup record after its copy;
--   5. the checks, any of which raises and so rolls back EVERYTHING: the walk deleted exactly the pinned rows per table and
--      nothing outside the scope; every table in scope lost exactly what the walk reports; nothing unlinked; every picked
--      row gone (the queued backup records aside, which dropbox_backup deletes); the foreign-key pins and the md5 of the kept
--      rows unchanged; fn_demo_purge_real_counts() moved by exactly -2 customers and -2 logins and nothing else; leads 19398,
--      158318, 143027 present and unchanged;
--   6. a verdict row (PROBE OK / the raise).
-- REHEARSED 18 Nov 2026 on a local Postgres 16 (the repo schema mirror supabase/schema/full_schema, production's bodies of
--   fn_demo_purge_walk and fn_demo_purge_real_counts (md5 equal to production's), 400 triggers of the mirror live, fixtures
--   shaped like the census above plus a third, real customer with a request, lead 19398's quote on it and a payment): PROBE OK
--   on the clean run (89 tables in scope, 72 foreign-key pins; the real customer's rows, quote and payment, the four kept
--   copies and lead 158318's notifications all still there) and on a repeat (all-zero census); REFUSED, the state unchanged,
--   on each known-bad control: the open fraud flag (production's state today); a supplier's quote on a request of theirs; a
--   census that moved (one more notification); a picked row naming lead 158318; a login whose address is not its customer's;
--   a kept row holding a SET NULL link to them (questions.customer_id); a child row the census never saw (customer_preference).
-- WHEN: after the accountant has closed fraud flag (customer_matches_supplier, 0dc8c94f), with a fresh census if anything
--   moved; outside campaign hours; scripts/apply_sql.mjs, no --ddl (no DDL here).
-- AFTER: dropbox_backup drains both queues (~1 hour, 25 Dropbox paths and 50 objects a run); then the founder deletes the one
--   _archive file by hand, and the empty folders "Customers/Umarah Nabi (ba61fa16)" and "Customers/ahmad alzain" go with the
--   empty-folder rule of ruling 1726. "Customers/ahmad alzain (0dc8c94f)" keeps the four copies above until they are re-filed.
-- ROLLBACK: every refusal rolls back everything, the queues included. A committed purge cannot be undone in SQL; the daily
--   export holds customers, notifications and agent_actions only. The queues can be stopped before dropbox_backup drains them
--   (15 minutes after listing) by setting done_at on this purge's signup_purge_object / signup_purge_dropbox rows.
set transaction isolation level repeatable read;
set local lock_timeout = '5s';

-- the ids, the reviewed census (18 Nov 2026 ~17:20Z) and the earlier sign-up's two storage objects, in one place
create temp table _f_pin on commit drop as
select array['0dc8c94f-903b-440a-b263-9b659513d7d1', 'ba61fa16-74f6-48ce-8cba-90fff5b157f9']::uuid[] as customers,
       array['713af87b-3d51-4da9-be51-b20ba46b085a', 'b22ee3f5-9b27-46e5-a90f-8c29138daa55']::uuid[] as logins,
       array[19398, 158318, 143027]::bigint[] as kept_leads,
       array['customers/1783930331743_ahmad_alzain_TnC-Acceptance.pdf', 'customers/1783930349503_ahmad_alzain_TnC-Acceptance.pdf']::text[] as july_terms,
       '/QuotesDone Backup/Customers/ahmad alzain/'::text as july_folder,
       '{"customers": 2, "auth.users": 2, "support_customer_profile": 2, "support_case": 2, "customer_support_duty_message": 2,
         "inquiry_intake": 3, "notifications": 12, "agent_actions": 8, "company_event": 18, "email_verifications": 16,
         "phone_verifications": 6, "rl_hits": 8, "ai_rate_limit": 1, "assistant_logs": 9, "ai_qa_log": 2,
         "doc_backups_queued": 22, "doc_backups_now": 1, "storage_objects": 22, "inquiries": 0, "quotes": 0, "transactions": 0}'::jsonb as census,
       -- the walk's own report, table by table, of the reviewed census: the picked rows and the auth rows that cascade with the logins
       '{"customers": 2, "auth.users": 2, "auth.identities": 2, "auth.sessions": 1, "auth.refresh_tokens": 1, "support_customer_profile": 2,
         "support_case": 2, "customer_support_duty_message": 2, "inquiry_intake": 3, "notifications": 12, "agent_actions": 8,
         "company_event": 18, "email_verifications": 16, "phone_verifications": 6, "rl_hits": 8, "ai_rate_limit": 1,
         "assistant_logs": 9, "ai_qa_log": 2, "doc_backups": 1}'::jsonb as touched;

-- THE TWO ACCOUNTS, by id. Both present (the census below) or both gone (a repeat); a login must carry its customer's address.
create temp table _f_c on commit drop as
select c.id, c.id::text as k, lower(btrim(c.email)) as e, c.signed_terms_path from public.customers c, _f_pin p where c.id = any(p.customers);
create temp table _f_u on commit drop as
select u.id from auth.users u, _f_pin p where u.id = any(p.logins);
-- the two mobile numbers (digits), and whether a real supplier holds the same one (0dc8c94f's: lead 158318)
create temp table _f_ph on commit drop as
select distinct x as p from public.customers cu, _f_pin pn, unnest(array[regexp_replace(coalesce(cu.phone, ''), '[^0-9]', '', 'g'),
       regexp_replace(coalesce(cu.whatsapp_phone, ''), '[^0-9]', '', 'g')]) x
 where cu.id = any(pn.customers) and x <> '';

do $who$
declare v_bad text;
begin
  if (select count(*) from _f_c) not in (0, 2) or (select count(*) from _f_u) not in (0, 2)
     or (select count(*) from _f_c) <> (select count(*) from _f_u) then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED before it started: % of the 2 customers and % of the 2 logins exist: review',
      (select count(*) from _f_c), (select count(*) from _f_u);
  end if;
  select string_agg(left(x.c::text, 8) || '/' || left(x.u::text, 8), ', ') into v_bad
    from unnest((select customers from _f_pin), (select logins from _f_pin)) x(c, u)
   where exists (select 1 from _f_c where id = x.c)
     and not exists (select 1 from auth.users u join _f_c c on c.id = x.c where u.id = x.u and lower(btrim(u.email)) = c.e);
  if v_bad is not null then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED before it started: login and customer do not carry the same address: %', v_bad;
  end if;
  if exists (select 1 from _f_c where coalesce((select is_demo from public.customers where id = _f_c.id), false)) then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED before it started: a customer is already marked demo; the 17 Nov purge rules apply, review';
  end if;
end $who$;

-- THE PICKED ROWS, rule by rule (header), read BEFORE anything moves.
create temp table _f_n on commit drop as
select n.id from public.notifications n
 where n.to_role = 'customer' and n.lead_id is null and n.inquiry_id is null and n.quote_id is null
   and (lower(btrim(n.to_email)) in (select e from _f_c) or regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g') in (select p from _f_ph))
   and exists (select 1 from _f_c);
create temp table _f_aa on commit drop as
with a1 as (
  select a.id from public.agent_actions a
   where a.kind = 'handoff' and a.target_table = 'notifications'
     and (a.target_id in (select 'delivery.request:notification:' || id from _f_n)
          or a.target_id in (select 'delivery.request:duty:activation.first_request:' || k from _f_c)))
select id from a1
union select a.id from public.agent_actions a
 where a.kind = 'handoff' and a.target_table = 'notifications' and a.target_id in (select 'delivery.request:retry:' || id from a1);
create temp table _f_al on commit drop as
select l.id from public.assistant_logs l where l.audience in (select 'customer:' || k from _f_c);
-- backups: theirs (a conversation copy only when its source goes too), every record of a storage object that goes, and the
-- 13 Jul sign-up's file
create temp table _f_obj0 on commit drop as
select 'signed-terms'::text as b, signed_terms_path as p from _f_c where signed_terms_path is not null
union select d.bucket, d.path from public.doc_backups d
 where d.entity = 'customer' and d.entity_id in (select k from _f_c) and d.bucket is not null and d.path is not null
   and (coalesce(d.dedupe_key, '') not like 'CONV:%'
        or d.dedupe_key in (select 'CONV:notifications:' || id from _f_n union all select 'CONV:assistant_logs:' || id from _f_al))
union select 'signed-terms', unnest(july_terms) from _f_pin;
create temp table _f_db on commit drop as
select d.id, d.dropbox_path,
       -- dropbox_backup's signupPurgeDeleteAllowed: a file of the entity tree, no relative or empty segment
       (d.dropbox_path ~ '^/QuotesDone Backup/(Customers|Suppliers|Storage|Company/Correspondence|Finance)/.+/[^/]+$'
        and d.dropbox_path !~ '(//|\\|/\.\.?(/|$))') as queueable
  from public.doc_backups d
 where ((d.entity = 'customer' and d.entity_id in (select k from _f_c)
         and (coalesce(d.dedupe_key, '') not like 'CONV:%'
              or d.dedupe_key in (select 'CONV:notifications:' || id from _f_n union all select 'CONV:assistant_logs:' || id from _f_al)))
        or (d.bucket, d.path) in (select b, p from _f_obj0)
        or starts_with(d.dropbox_path, (select july_folder from _f_pin)))
   -- a repeat: a record already queued by a purge waits for dropbox_backup
   and not exists (select 1 from public.signup_purge_dropbox s where s.doc_backup_id = d.id and s.done_at is null);
create temp table _f_obj on commit drop as
select o.bucket_id, o.name from storage.objects o
 where (o.bucket_id, o.name) in (select b, p from _f_obj0)
   and not exists (select 1 from public.signup_purge_object q where q.bucket = o.bucket_id and q.path = o.name and q.done_at is null);
-- the copies filed under 0dc8c94f whose source is not the account's: kept (header)
create temp table _f_misfiled on commit drop as
select d.id from public.doc_backups d where d.entity = 'customer' and d.entity_id in (select k from _f_c) and d.id not in (select id from _f_db);

-- the walk's where-clause per table, in fn_demo_purge_run's order (identity-keyed rows first, the entities last)
create temp table _f_w on commit drop as
select ord, to_regclass(rel) as rel, w from (values
  (1, 'public.company_event', '(entity_type = ''customer'' and entity_id in (select k from pg_temp._f_c)) or (entity_type = ''agent_actions'' and entity_id in (select id::text from pg_temp._f_aa))'),
  (2, 'public.agent_actions', 'id in (select id from pg_temp._f_aa)'),
  (3, 'public.doc_backups', 'id in (select id from pg_temp._f_db where not queueable)'),
  (4, 'public.notifications', 'id in (select id from pg_temp._f_n)'),
  (5, 'public.email_verifications', 'user_kind = ''customer'' and lower(btrim(email)) in (select e from pg_temp._f_c)'),
  (6, 'public.phone_verifications', 'user_kind = ''customer'' and (lower(btrim(email)) in (select e from pg_temp._f_c) or regexp_replace(coalesce(phone, ''''), ''[^0-9]'', '''', ''g'') in (select p from pg_temp._f_ph))'),
  (7, 'public.inquiry_intake', 'customer_id in (select id from pg_temp._f_c) or lower(btrim(email)) in (select e from pg_temp._f_c)'),
  (8, 'public.support_case', 'party_kind = ''customer'' and party_id::text in (select k from pg_temp._f_c)'),
  (9, 'public.support_customer_profile', 'customer_id in (select id from pg_temp._f_c)'),
  (10, 'public.customer_support_duty_message', 'customer_id in (select id from pg_temp._f_c)'),
  (11, 'public.rl_hits', 'k in (select x || e from pg_temp._f_c, unnest(array[''intake:'', ''role_guard_id:'', ''site_assistant_acct:'']) x)'),
  (12, 'public.ai_rate_limit', 'bucket in (select ''site_assistant_acct:'' || e from pg_temp._f_c)'),
  (13, 'public.assistant_logs', 'id in (select id from pg_temp._f_al)'),
  (14, 'public.ai_qa_log', 'kind = ''intake'' and lower(btrim(email)) in (select e from pg_temp._f_c)'),
  (15, 'public.customers', 'id in (select id from pg_temp._f_c)'),
  (16, 'auth.users', 'id in (select id from pg_temp._f_u)')
) v(ord, rel, w);

-- each picked row by its primary key, so after the walk every one can be shown gone: px is the key as text over alias x
-- (every table above has a single-column key but customer_support_duty_message, whose key is (stage, subject_key))
create temp table _f_pick on commit drop as
select w.ord, w.rel, (case when n.nspname = 'public' then c.relname else n.nspname || '.' || c.relname end)::text as k, pk.px,
       array(select jsonb_array_elements_text(convert_from(decode(h.h, 'hex'), 'UTF8')::jsonb)) as ids
  from _f_w w join pg_class c on c.oid = w.rel join pg_namespace n on n.oid = c.relnamespace
  cross join lateral (select '(' || string_agg('x.' || quote_ident(a.attname) || '::text', ' || ''|'' || ' order by k.i) || ')' as px
                        from pg_constraint p cross join lateral unnest(p.conkey) with ordinality k(attnum, i)
                        join pg_attribute a on a.attrelid = p.conrelid and a.attnum = k.attnum
                       where p.conrelid = w.rel and p.contype = 'p') pk
  cross join lateral (select (xpath('/row/h/text()', query_to_xml(format(
      'select encode(convert_to(coalesce(jsonb_agg(%s), ''[]''::jsonb)::text, %L), %L) as h from %s x where %s',
      pk.px, 'UTF8', 'hex', w.rel::regclass::text, w.w), false, true, '')))[1]::text as h) h
 where pk.px is not null;

do $census$
declare
  v jsonb; v_pin jsonb := (select census from _f_pin); v_zero jsonb;
begin
  if (select count(*) from _f_w) <> 16 or exists (select 1 from _f_w where rel is null) or (select count(*) from _f_pick) <> 16 then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED before it started: a table of the plan is missing or has no primary key: review';
  end if;
  v := (select jsonb_object_agg(k, cardinality(ids)) from _f_pick where k <> 'doc_backups')
    || jsonb_build_object('doc_backups_queued', (select count(*) from _f_db where queueable), 'doc_backups_now', (select count(*) from _f_db where not queueable),
         'storage_objects', (select count(*) from _f_obj),
         'inquiries', (select count(*) from public.inquiries where customer_id in (select id from _f_c)),
         'quotes', (select count(*) from public.quotes q join public.inquiries i on i.id = q.inquiry_id where i.customer_id in (select id from _f_c)),
         'transactions', (select count(*) from public.transactions t where t.customer_id in (select id from _f_c)
                            or t.inquiry_id in (select id from public.inquiries where customer_id in (select id from _f_c))));
  select jsonb_object_agg(key, 0) into v_zero from jsonb_each(v_pin);
  if v is distinct from v_pin and v is distinct from v_zero then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED before it started: the census is % and the reviewed one (18 Nov ~17:20Z) is %: re-census and review', v, v_pin;
  end if;
end $census$;

-- THE REFUSALS (a real third party) before anything moves
do $third$
declare v_bad text; r record; v_n bigint;
begin
  -- 1. the accountant's open case linking 0dc8c94f to real supplier 158318 (header): his decision first
  select string_agg(f.kind || ' ' || left(f.subject_id, 8) || ' (' || f.severity || ', opened ' || f.created_at::date || ')', '; ') into v_bad
    from public.fraud_flags f, _f_pin p
   where f.subject_type = 'customer' and f.subject_id = any(p.customers::text[]) and f.status = 'open';
  if v_bad is not null then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: an open fraud flag links the account to a real supplier: %; the accountant closes it first', v_bad;
  end if;
  -- 2. a request, a quote or a payment of theirs is a supplier's or the books' record too
  if exists (select 1 from public.inquiries where customer_id in (select id from _f_c))
     or exists (select 1 from public.transactions where customer_id in (select id from _f_c)) then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: the accounts have requests or payments (a supplier''s quote, a transaction): review';
  end if;
  -- 3. no picked row names a lead, a request, a quote, a transaction or a supplier
  for r in select p.k, p.rel, p.px, p.ids, a.attname::text as col from _f_pick p
             join pg_attribute a on a.attrelid = p.rel and a.attnum > 0 and not a.attisdropped
            where a.attname in ('lead_id', 'supplier_id', 'inquiry_id', 'quote_id', 'transaction_id', 'refund_id') loop
    v_n := (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s x where %s = any(%L::text[]) and x.%I is not null',
             r.rel::regclass::text, r.px, r.ids, r.col), false, true, '')))[1]::text::bigint;
    if v_n > 0 then v_bad := concat_ws('; ', v_bad, format('%s.%s: %s row(s)', r.k, r.col, v_n)); end if;
  end loop;
  select concat_ws('; ', v_bad, (select 'agent_actions naming a supplier: ' || string_agg(a.id::text, ', ') from public.agent_actions a
     where a.id in (select id from _f_aa) and (a.detail ? 'supplier_id' or a.detail ? 'lead_id'))) into v_bad;
  if nullif(v_bad, '') is not null then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: a row it would delete names a real third party: %', v_bad;
  end if;
end $third$;

-- THE SCOPE: every table picked and every foreign-key descendant of one, and its count before (read-only)
create temp table _f_scope on commit drop as
with recursive walk(rel, depth) as (
  select rel, 0 from _f_w
  union
  select c.conrelid::regclass, w.depth + 1 from walk w
    join pg_constraint c on c.confrelid = w.rel and c.contype = 'f' and c.conrelid <> c.confrelid
   where w.depth < 9)
select distinct w.rel::oid as rel, case when n.nspname = 'public' then c.relname else n.nspname || '.' || c.relname end as k
  from walk w join pg_class c on c.oid = w.rel join pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('r', 'p') and c.relname not in ('signup_purge', 'signup_purge_object', 'signup_purge_dropbox');
create temp table _f_before on commit drop as
select s.rel, s.k, (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s', s.rel::regclass::text), false, true, '')))[1]::text::bigint as n
  from _f_scope s;

-- THE FOREIGN-KEY PINS: rows in scope pointing at a customer, lead, inquiry, quote, transaction or login that is NOT one of these
-- two accounts (the row itself not picked). The count must not move: a real-linked row deleted, or its link nulled, refuses.
create temp table _f_fk on commit drop as
select c.conrelid::regclass as child, a.attname::text as col, c.confrelid::regclass as parent,
       format('select count(*) as n from %s x where x.%I is not null%s%s', c.conrelid::regclass, a.attname,
              case when c.confrelid = 'public.customers'::regclass then format(' and x.%I::text not in (select k from pg_temp._f_c)', a.attname)
                   when c.confrelid = 'auth.users'::regclass then format(' and x.%I::uuid not in (select id from pg_temp._f_u)', a.attname)
                   else '' end,
              coalesce((select format(' and not (%s = any(%L::text[]))', p.px, p.ids) from _f_pick p where p.rel = c.conrelid::regclass), '')) as q
  from pg_constraint c
  join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
  join pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1]
 where c.contype = 'f' and cardinality(c.conkey) = 1 and pa.attname = 'id'
   and c.confrelid in ('public.customers'::regclass, 'public.leads'::regclass, 'public.inquiries'::regclass, 'public.quotes'::regclass,
                       'public.transactions'::regclass, 'auth.users'::regclass)
   and c.conrelid in (select rel from _f_scope);
create temp table _f_fk_before on commit drop as
select child, col, parent, q, (xpath('/row/n/text()', query_to_xml(q, false, true, '')))[1]::text::bigint as n from _f_fk;

-- A SET NULL / SET DEFAULT reference to one of the two customers or logins from a row this file does not delete: that row would
-- survive, changed. None on 18 Nov (support_customer_profile's is the one such key, and both its rows are picked).
do $setnull$
declare r record; v_n bigint; v_bad text;
begin
  for r in select c.conrelid::regclass as child, a.attname::text as col, c.confrelid::regclass as parent,
                  (select p.px from _f_pick p where p.rel = c.conrelid::regclass) as px, (select p.ids from _f_pick p where p.rel = c.conrelid::regclass) as ids
             from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
            where c.contype = 'f' and cardinality(c.conkey) = 1 and c.confdeltype in ('n', 'd')
              and c.confrelid in ('public.customers'::regclass, 'auth.users'::regclass) loop
    v_n := (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s x where x.%I::text in (select %s)%s', r.child, r.col,
             case when r.parent = 'public.customers'::regclass then 'k from pg_temp._f_c' else 'id::text from pg_temp._f_u' end,
             case when r.px is null then '' else format(' and not (%s = any(%L::text[]))', r.px, r.ids) end), false, true, '')))[1]::text::bigint;
    if v_n > 0 then v_bad := concat_ws('; ', v_bad, format('%s.%s: %s row(s)', r.child, r.col, v_n)); end if;
  end loop;
  if v_bad is not null then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: rows it keeps hold a SET NULL reference to the accounts and would be changed: %', v_bad;
  end if;
end $setnull$;

-- THE KEPT ROWS, by md5: the three leads, the copies filed under 0dc8c94f whose source stays, the accountant's case about lead
-- 158318 and lead 158318's own notifications. None may change.
create temp view _f_kept as
select 'leads' as k, (select coalesce(md5(string_agg(l::text, '|' order by l.id)), '') from public.leads l where l.id in (select unnest(kept_leads) from _f_pin)) as m,
       (select count(*) from public.leads l where l.id in (select unnest(kept_leads) from _f_pin) and not coalesce(l.is_demo, false)) as n
union all select 'doc_backups kept', (select coalesce(md5(string_agg(d::text, '|' order by d.id)), '') from public.doc_backups d where d.id in (select id from _f_misfiled)),
       (select count(*) from public.doc_backups d where d.id in (select id from _f_misfiled))
union all select 'fraud case', (select coalesce(md5(string_agg(f::text, '|' order by f::text)), '') from public.fraud_flags f, _f_pin p
         where f.subject_type = 'customer' and f.subject_id = any(p.customers::text[])),
       (select count(*) from public.fraud_flags f, _f_pin p where f.subject_type = 'customer' and f.subject_id = any(p.customers::text[]))
union all select 'notifications of the kept leads', (select coalesce(md5(string_agg(n::text, '|' order by n.id)), '') from public.notifications n where n.lead_id in (select unnest(kept_leads) from _f_pin)),
       (select count(*) from public.notifications n where n.lead_id in (select unnest(kept_leads) from _f_pin));
create temp table _f_kept_before on commit drop as select * from _f_kept;
create temp table _f_real_before on commit drop as select public.fn_demo_purge_real_counts() as rc;

do $leads$
begin
  if (select n from _f_kept_before where k = 'leads') <> 3 then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED before it started: leads 19398, 158318, 143027 are not all present and real (% of 3)',
      (select n from _f_kept_before where k = 'leads');
  end if;
end $leads$;

-- THE WALK (fn_demo_purge_walk, unchanged), table by table, in fn_demo_purge_run's order
create temp table _f_out (c jsonb) on commit drop;
do $walk$
declare r record; c jsonb := '{}'::jsonb;
begin
  for r in select rel, w from _f_w order by ord loop
    c := public.fn_demo_purge_walk(r.rel, r.w, 0, c);
  end loop;
  insert into _f_out values (c);
end $walk$;

-- STORAGE AND DROPBOX, listed for dropbox_backup under one purge record (kind demo_purge, as fn_demo_purge_run lists them)
create temp table _f_purge on commit drop as
with p as (
  insert into public.signup_purge (kind, subject_ref, missing)
  select 'demo_purge', 'founder ruling 1732: the founder''s two demo customer accounts 0dc8c94f, ba61fa16', '{}'
   where exists (select 1 from _f_obj) or exists (select 1 from _f_db where queueable)
  returning id)
select id from p;
create temp table _f_listed on commit drop as
with o as (
  insert into public.signup_purge_object (purge_id, bucket, path)
  select (select id from _f_purge), bucket_id, name from _f_obj
  on conflict (bucket, path) do nothing
  returning 1)
select count(*) as n from o;
create temp table _f_dbx on commit drop as
with d as (
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select (select id from _f_purge), id, dropbox_path from _f_db where queueable
  on conflict (doc_backup_id) do nothing
  returning doc_backup_id, dropbox_file)
select * from d;
-- a listed copy keeps its record until dropbox_backup has deleted the copy (it then deletes the record: status signup_purge_pending)
update public.doc_backups d set status = 'signup_purge_pending', claimed_at = null, claimed_by = null,
       error = 'founder ruling 1732: the founder''s demo customer account purged; Dropbox copy and record to be deleted'
 where d.id in (select doc_backup_id from _f_dbx);

create temp table _f_after on commit drop as
select s.rel, s.k, (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s', s.rel::regclass::text), false, true, '')))[1]::text::bigint as n
  from _f_scope s;

do $check$
declare
  v_touched jsonb := coalesce((select c->'touched' from _f_out), '{}'::jsonb); v_bad text; r record; v_n bigint;
  v_got jsonb; v_want jsonb; v_rb jsonb := (select rc from _f_real_before); v_ra jsonb := public.fn_demo_purge_real_counts();
  v_nc int := (select count(*) from _f_c); v_nu int := (select count(*) from _f_u);
begin
  -- a. the walk deleted exactly the reviewed rows, table by table (or nothing at all, on a repeat)
  select coalesce(jsonb_object_agg(t.key, t.value::bigint), '{}'::jsonb) into v_got from jsonb_each_text(v_touched) t
   where t.key !~ ' \(unlinked ' and t.value::bigint > 0;
  v_want := case when v_nc = 0 then '{}'::jsonb else (select touched from _f_pin) end;
  if v_got is distinct from v_want then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: the walk deleted % and the reviewed census is %', v_got, v_want;
  end if;
  -- b. nothing unlinked: no surviving row had its link to these accounts nulled
  select string_agg(t.key || '=' || t.value, ', ') into v_bad from jsonb_each_text(v_touched) t where t.key ~ ' \(unlinked ' and t.value::bigint > 0;
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: a row it keeps would be changed (its link nulled): %', v_bad; end if;
  -- c. every table in scope lost exactly what the walk reports, and the walk deleted nowhere outside the scope
  select string_agg(format('%s: %s -> %s, walk says %s', b.k, b.n, a.n, coalesce(v_touched->>b.k, '0')), '; ' order by b.k) into v_bad
    from _f_before b join _f_after a on a.rel = b.rel
   where b.n - a.n <> coalesce((v_touched->>b.k)::bigint, 0);
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: a table moved by other than the accounts'' rows: %', v_bad; end if;
  select string_agg(t.key, ', ') into v_bad from jsonb_each_text(v_touched) t
   where t.key !~ ' \(unlinked ' and t.value::bigint > 0 and not exists (select 1 from _f_scope s where s.k = t.key);
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: the walk deleted in % outside the measured scope', v_bad; end if;
  -- d. every picked row is gone (the queued backup records aside: dropbox_backup deletes each after its copy)
  for r in select k, rel, px, ids from _f_pick loop
    v_n := (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s x where %s = any(%L::text[])',
             r.rel::regclass::text, r.px, r.ids), false, true, '')))[1]::text::bigint;
    if v_n > 0 then v_bad := concat_ws('; ', v_bad, format('%s: %s picked row(s) left', r.k, v_n)); end if;
  end loop;
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE INCOMPLETE: %', v_bad; end if;
  -- e. the queues hold exactly the reviewed files, each queued Dropbox copy a file of the entity tree, under these accounts' folders
  if (select n from _f_listed) <> (select count(*) from _f_obj) or (select count(*) from _f_dbx) <> (select count(*) from _f_db where queueable) then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: % of % storage objects and % of % Dropbox copies queued (another purge holds one?): review',
      (select n from _f_listed), (select count(*) from _f_obj), (select count(*) from _f_dbx), (select count(*) from _f_db where queueable);
  end if;
  select string_agg(dropbox_file, ', ') into v_bad from _f_dbx
   where not (starts_with(dropbox_file, '/QuotesDone Backup/Customers/ahmad alzain (0dc8c94f)/')
              or starts_with(dropbox_file, '/QuotesDone Backup/Customers/Umarah Nabi (ba61fa16)/')
              or starts_with(dropbox_file, (select july_folder from _f_pin))
              or dropbox_file in (select '/QuotesDone Backup/Storage/signed-terms/' || p from _f_pin, unnest(july_terms) p));
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: Dropbox copies outside the accounts'' folders queued: %', v_bad; end if;
  -- f. no row that points at any other customer, lead, inquiry, quote, transaction or login was deleted or unlinked
  select string_agg(format('%s.%s -> %s: %s -> %s', b.child, b.col, b.parent, b.n, a.n), '; ') into v_bad
    from _f_fk_before b cross join lateral (select (xpath('/row/n/text()', query_to_xml(b.q, false, true, '')))[1]::text::bigint as n) a
   where a.n <> b.n;
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: rows pointing at a real party moved: %', v_bad; end if;
  -- g. the kept rows did not change
  select string_agg(b.k, ', ') into v_bad from _f_kept_before b join _f_kept a on a.k = b.k where a.m <> b.m or a.n <> b.n;
  if v_bad is not null then raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: kept rows changed: %', v_bad; end if;
  -- h. the estate's real counts moved by exactly the two customers and the two logins
  if v_ra is distinct from (v_rb || jsonb_build_object('customers', (v_rb->>'customers')::bigint - v_nc, 'auth_users', (v_rb->>'auth_users')::bigint - v_nu)) then
    raise exception 'FOUNDER ACCOUNTS PURGE REFUSED: real counts before % after %, expected only -% customers and -% logins', v_rb, v_ra, v_nc, v_nu;
  end if;
end $check$;

drop view if exists pg_temp._f_kept;

select 'PROBE OK: the founder''s demo customer accounts ' || coalesce((select string_agg(left(k, 8), ', ' order by k) from _f_c), 'none left (a repeat)')
       || ' and their logins removed: ' || coalesce((select string_agg(t.key || ' ' || t.value, ', ' order by t.key) from jsonb_each_text((select c->'touched' from _f_out)) t
                                                   where t.key !~ ' \(unlinked ' and t.value::bigint > 0), 'nothing to delete')
       || '; every table in scope (' || (select count(*) from _f_scope)::text || ') exactly as the walk reported; unlinked none'
       || '; queued for dropbox_backup: ' || (select n from _f_listed)::text || ' storage objects, ' || (select count(*) from _f_dbx)::text || ' Dropbox copies'
       || '; delete by hand (dropbox_backup may not): ' || coalesce((select string_agg(dropbox_path, ', ') from _f_db where not queueable and dropbox_path is not null), 'none')
       || '; foreign keys to a real party pinned: ' || (select count(*) from _f_fk_before)::text
       || '; kept: ' || (select string_agg(k || ' ' || n, ', ' order by k) from _f_kept_before)
       || ' (leads 19398, 158318, 143027); real counts ' || public.fn_demo_purge_real_counts()::text
       as verdict;
