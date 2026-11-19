-- A REAL CUSTOMER WHOSE RECORD WAS LOST IS RESTORED, AND ASKED ABOUT THE REQUEST SHE STARTED IN JULY
-- (customer_support; 19 Nov 2026; founder ruling of 19 Nov: "if she's a real customer, then reply").
-- The customer's gender is not known; every word written to the customer below is neutral. The file name keeps the
-- brief's wording.
--
-- WHAT WAS MEASURED (production, SELECT on tables and the catalogue only, 19 Nov 2026 ~12:00-13:00Z):
--   the login       auth.users 15bcba0f-0fbe-4f9c-bd31-9b4cdd77b61e, info@ekanaglobal.com, created 2026-07-09 08:13:17.529Z,
--                   e-mail confirmed 08:13:17.553Z, last (and only) sign-in 08:14:11Z; one 'email' identity; not banned or
--                   deleted. The portal links a login to its customer by e-mail, never by id (customer_api/index.ts:
--                   customers.email = the JWT's lower-cased address; no row -> 403 'No customer profile').
--   the customer    public.customers holds 0 rows on the whole estate (the founder's two demo accounts were the last two,
--                   removed 18 Nov by the_founders_two_demo_customer_accounts_go_with_everything_they_own.sql); 0 rows for
--                   this address or id. public.inquiries holds 0 rows on the whole estate. Nothing records the deletion:
--                   0 rows naming the id, the login or the address in security_audit_log, contact_merge_audit,
--                   company_event, os_audit_log, inquiry_state_audit, security_events, error_events, signup_purge (by its
--                   sha256 subject_ref), agent_actions, notifications, inbound_messages, inbound_mail_queue,
--                   customer_support_duty_message, customer_support_voice_owed, inquiry_intake, cad_read_jobs,
--                   boq_section_reading, drawing_redaction_runs, rfq_archives, email_verifications, email_suppressions.
--   what survives   the old customer id is ca038493-61aa-4a63-be8c-0f932f4c1c4c (doc_backups 4 and 10, entity 'customer',
--                   both backed up 10 Jul 2026 16:00Z; drawing paths are drawings/<customers.id>/..., per
--                   customer_api/drawing_path.test.ts). In storage:
--                     signed-terms   customers/1783584833603_TIWNKLE_SHARMA_TnC-Acceptance.pdf  146,601 B, 2026-07-09 08:13:53.654Z
--                     drawing-files  drawings/ca038493-61aa-4a63-be8c-0f932f4c1c4c/1783584950724_BOQ-DBB_1_Ajman_MEP_work.pdf
--                                    520,692 B, 2026-07-09 08:15:51.122Z (the BOQ, uploaded 2 minutes after sign-up)
--                     backups        generated/1783699325523_customer_details_ca038493_61aa_4a63_be8c_0f932f4c1c4c.pdf 99,961 B
--                   Dropbox (read 19 Nov): /QuotesDone Backup/Customers/TIWNKLE SHARMA/Signed-Terms-Acceptance.pdf and
--                   /QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/TIWNKLE SHARMA (ca038493)/Customer Details.pdf.
--                   No request row of any kind survives: what was asked for is known only from the BOQ's file name.
--   the facts       read from those two PDFs, and from nothing else:
--                     Signed terms certificate: Full name "TIWNKLE SHARMA" (the customer's own spelling, the same in the
--                     folder, the file name and the certificate, so it is kept as entered and never "corrected"); date of
--                     birth 1998-08-08; mobile 0503765045; e-mail info@ekanaglobal.com; Customer Terms & Conditions Version 3;
--                     accepted 2026-07-09 08:13:17 UTC; IP 5.30.114.229; SHA-256 66ed486d...a56a50; click-to-accept.
--                     Customer Details (10 Jul): Phone verified No; Email verified Yes; Registered 2026-07-09; Terms version
--                     v3; Terms accepted 2026-07-09; WhatsApp opt-in No.
--                   Not recorded anywhere, so left at the column default: the customers row's own created_at to the
--                   microsecond (the login's created_at is used: the registration moment, same date as "Registered"),
--                   signed_terms_url (a signed URL that expired; signed_terms_path is what every reader uses), locale ('en',
--                   the certificate's language), industry, WhatsApp, marketing consent (false).
--
-- WHAT THIS DOES
--   1. Inserts the customers row with the old id, so the BOQ under drawings/ca038493.../ is the customer's own again and
--      the portal answers this login. Nothing is inserted if any customers row already holds the address or the id.
--   2. Hands the case to customer_support through the seat's own model-written path (ruling 1339):
--      public.fn_customer_support_voice_owe, stage support.lost_request, key = the customer id. supportVoice
--      (resilience_ping, every 15 minutes; resilience_step last ok 19 Nov 11:45Z) has the model write the words
--      (_shared/duty_voice.ts aiReply, seat customer_support, e-mail) and sends them through
--      fn_customer_support_voice_send -> fn_customer_support_duty_send (fn_email_sendable, the once-per-(stage, key) record,
--      the delivery hand-off). The draft below goes out only if no call reached a model (OpenRouter down), and
--      voice_send refuses an outage body that is not this draft. NOTE: customer_support_voice_owed held 0 rows on
--      19 Nov, so this is the first message ever owed through it; its five live callers are complaint, incident,
--      IT-fault and after-reveal duties.
--      The stage is support.* on purpose: the type becomes duty_support_lost_request, a service reply about the
--      customer's own request. fn_email_type_is_marketing matches 'activation' and 'winback' in a type, which an
--      'unsubscribe' suppression would refuse; this message is not marketing.
--   3. Closes sales_engineer.activation's first-request stage for this customer with an honest marker. MEASURED: the live
--      fn_customer_support_activation_tick (every 6 hours, last run 19 Nov 11:00Z) writes to every non-demo customer
--      older than 3 days with no request, in CODE-WRITTEN words (it does not use the voice path), guarded only by a
--      customer_support_duty_message row (activation.first_request, <customer id>). Without the marker the restored row
--      would get that generic, code-written "you have not posted a request yet" mail as a second message.
--      The marker's outcome says "superseded", never "queued", and carries no handoff_id: nothing was sent at that stage.
--   4. A probe (last statement) that raises, rolling everything back, unless: exactly one customers row holds the
--      address, with the old id, e-mail verified, not demo, signed_terms_path set and fn_signup_customer_held true (the
--      every-5-minutes cron fn_unfinished_signup_purge deletes a non-demo customer missing 'mobile' — this one is — unless
--      held; the signed terms path is what holds it); exactly one message is owed, to this address only; no notification
--      and no delivery hand-off was written by this transaction (nothing goes to anyone, this customer included, until
--      the model writes); the activation marker is in place.
--
-- SIDE EFFECTS OF THE INSERT, read from the live triggers on public.customers (19 Nov):
--   trg_block_disposable_customers  passes (ekanaglobal.com is not in app_blocked_domains);
--   trg_emit_customer_registered    ONE company_event 'customer.registered' (seats receive it by digest; no subscriber
--                                   writes to the customer). It reads as a registration of today; the probe names it.
--   z70_document_landed_kicks_backup  kicks dropbox_backup, which re-files the customer's documents under
--                                   Customers/TIWNKLE SHARMA (ca038493);
--   trg_sign_customer, z40, z41     UPDATE-only triggers: they do not fire, so no "account active" notice is sent.
--   is_demo is a generated column (fn_is_demo_email / fn_is_demo_phone / a ZZ DEMO name): false for these values.
--
-- WHAT THIS DOES NOT DO: it recreates no request (none survives; the customer is asked whether the job is still open),
-- tells the customer nothing about how the record was lost (ledger 1338: no internal detail), and does not find who deleted
-- the row (nothing recorded it). It sends nothing itself.
--
-- SEAT: customer_support. Apply (only after review; a data file, no routine):
--   node scripts/apply_sql.mjs scripts/sql/a_real_customer_whose_record_was_lost_is_restored_and_asked_about_her_request.sql --apply --ddl --seat customer_support
--   then append the file as the LAST line of scripts/sql/MANIFEST.txt (Edit tool). Until applied it carries
--   scripts/sql/pending/a_real_customer_whose_record_was_lost_is_restored_and_asked_about_her_request.txt.
-- ROLLBACK, only while the message is still owed (written_at is null; once the model has written it, it is sent):
--   delete from public.customer_support_voice_owed where stage = 'support.lost_request'
--      and subject_key = 'ca038493-61aa-4a63-be8c-0f932f4c1c4c' and written_at is null;
--   delete from public.customer_support_duty_message where stage = 'activation.first_request'
--      and subject_key = 'ca038493-61aa-4a63-be8c-0f932f4c1c4c' and outcome like 'superseded:%';
--   the customers row is NOT rolled back: deleting it again would lose the customer a second time.
-- Prevented by: the probe below (it fails on a row the purge would delete, on a second owed message, or on any send in
-- this transaction). What would stop a real customer's row going unrecorded again is the IT engineer's, not this file's.

set local lock_timeout = '1500ms';

do $restore$
declare
  c_id      constant uuid := 'ca038493-61aa-4a63-be8c-0f932f4c1c4c';
  c_login   constant uuid := '15bcba0f-0fbe-4f9c-bd31-9b4cdd77b61e';
  c_email   constant text := 'info@ekanaglobal.com';
  c_terms   constant text := 'customers/1783584833603_TIWNKLE_SHARMA_TnC-Acceptance.pdf';
  c_portal  constant text := 'https://quotesdone.com/me';      -- app_secrets.public_site_url, 19 Nov
  v_login_at timestamptz; v_terms_at timestamptz; v_existing uuid; v_owed boolean;
begin
  -- a no-op when the customer already has a row (a repeat of this file, or a new sign-in that created one)
  select cu.id into v_existing from public.customers cu
   where lower(btrim(cu.email)) = c_email or cu.id = c_id order by (cu.id = c_id) desc limit 1;
  if v_existing is not null then
    perform set_config('qd.lost_customer_restore', 'noop:' || v_existing, true);
    return;
  end if;

  -- the facts this file restores must still be what was measured on 19 Nov; otherwise it refuses
  select u.created_at into v_login_at from auth.users u
   where u.id = c_login and lower(u.email) = c_email and u.email_confirmed_at is not null and u.deleted_at is null;
  if v_login_at is null then raise exception 'LOST CUSTOMER RESTORE REFUSED: the login % for % is gone or changed', c_login, c_email; end if;
  select o.created_at into v_terms_at from storage.objects o where o.bucket_id = 'signed-terms' and o.name = c_terms;
  if v_terms_at is null then raise exception 'LOST CUSTOMER RESTORE REFUSED: the signed terms % are no longer in storage', c_terms; end if;

  -- 1. the row, with only what the signed certificate and the 10 Jul Customer Details record
  insert into public.customers (id, full_name, phone, email, created_at, phone_verified, banned, date_of_birth, email_verified,
                                tos_accepted_at, tos_version, tos_ip, tos_sha256, wa_optin, signed_terms_path, signed_terms_at, locale)
  values (c_id, 'TIWNKLE SHARMA', '0503765045', c_email, v_login_at, false, false, date '1998-08-08', true,
          timestamptz '2026-07-09 08:13:17+00', 'v3', '5.30.114.229',
          '66ed486d4bd26fc366cea6d41c01bd4d12c2d4e83fb593b07820c13475a56a50', false, c_terms, v_terms_at, 'en');

  -- 3. the activation stage is answered by the message below, not by the code-written first-request mail
  insert into public.customer_support_duty_message (stage, subject_key, customer_id, to_email, outcome)
  values ('activation.first_request', c_id::text, c_id, c_email,
          'superseded: support.lost_request (19 Nov 2026, the restored customer is written to once, by the model)')
  on conflict (stage, subject_key) do nothing;

  -- 2. the one message, owed to the seat's model-written path
  v_owed := public.fn_customer_support_voice_owe(
    'support.lost_request', c_id::text, 'support.lost_request:' || c_id, 'customer', c_email, 'en',
    'Your Ajman MEP request on QuotesDone',
    -- the DRAFT: sent only on an OpenRouter outage (fn_customer_support_voice_send refuses any other code-written body)
    'Hello,' || chr(10) || chr(10)
      || 'In July you started a request with us for MEP work in Ajman and uploaded a bill of quantities. We were not able '
      || 'to complete that request, and we are sorry it went no further.' || chr(10) || chr(10)
      || 'Is the Ajman MEP job still open? If it is, you can post it from your account and attach the bill of '
      || 'quantities, so that suppliers in that trade can quote: ' || c_portal || chr(10) || chr(10)
      || 'If you have a question, reply to this e-mail and we will help.' || chr(10) || chr(10)
      || 'The QuotesDone team',
    -- the situation the model writes about
    'Write to a customer who started a request with us in July that we could not complete. Say plainly that the request '
      || 'could not be completed and apologise once. Ask whether their MEP job in Ajman is still open, and invite them back '
      || 'to their account to post it, with the bill of quantities. The customer''s gender is not known: greet with '
      || '"Hello," and use no name, no title (Mr, Mrs, Ms, Sir, Madam) and no gendered word anywhere.',
    -- customer-safe facts only (ledger 1338): no cause, no system, nothing about records
    'SIGNED UP: 9 July 2026, and accepted our terms the same day' || chr(10)
      || 'WHAT THEY SENT: a bill of quantities for MEP work in Ajman (file "BOQ-DBB_1_Ajman_MEP_work.pdf"), uploaded on 9 July 2026' || chr(10)
      || 'WHAT HAPPENED: the request could not be completed; no supplier quote came from it' || chr(10)
      || 'WHAT WE ASK: whether the Ajman MEP job is still open' || chr(10)
      || 'WHAT THEY CAN DO: sign in to their account at ' || c_portal || ' and post the request again, attaching the bill of quantities; or reply to this e-mail' || chr(10)
      || 'DO NOT: use the customer''s name (it is recorded in capitals as typed), promise a number of quotes, a date or a price',
    array[c_portal, 'Ajman']);
  if not coalesce(v_owed, false) then
    raise exception 'LOST CUSTOMER RESTORE REFUSED: the message was already owed or written (stage support.lost_request, %)', c_id;
  end if;
  perform set_config('qd.lost_customer_restore', 'restored', true);
end $restore$;

-- ── the probe: raises (and the whole file rolls back) unless every claim holds ─────────────────────────────
do $probe$
declare
  c_id    constant uuid := 'ca038493-61aa-4a63-be8c-0f932f4c1c4c';
  c_email constant text := 'info@ekanaglobal.com';
  v_mode text := coalesce(current_setting('qd.lost_customer_restore', true), '');
  cu public.customers; v_rows int; v_owed int; v_owed_tx int; v_other_tx int; v_notif_tx int; v_handoff_tx int;
  v_marker int; v_events int;
begin
  select count(*) into v_rows from public.customers where lower(btrim(email)) = c_email;
  if v_rows <> 1 then raise exception 'PROBE FAILED: % customers rows hold %, expected exactly 1', v_rows, c_email; end if;
  select * into cu from public.customers where lower(btrim(email)) = c_email;
  -- written by THIS transaction (created_at = now() is the transaction's own start time; nothing else shares it)
  select count(*) into v_owed_tx from public.customer_support_voice_owed where created_at = now();
  select count(*) into v_other_tx from public.customer_support_voice_owed where created_at = now() and lower(to_email) <> c_email;
  select count(*) into v_notif_tx from public.notifications where created_at = now();
  select count(*) into v_handoff_tx from public.agent_actions where created_at = now() and detail ? 'prepared';
  if v_notif_tx <> 0 then raise exception 'PROBE FAILED: this transaction wrote % notification(s); it must send nothing', v_notif_tx; end if;
  if v_handoff_tx <> 0 then raise exception 'PROBE FAILED: this transaction filed % delivery hand-off(s); the model writes first', v_handoff_tx; end if;
  if v_other_tx <> 0 then raise exception 'PROBE FAILED: % message(s) owed to another address', v_other_tx; end if;

  if v_mode like 'noop:%' then
    if v_owed_tx <> 0 then raise exception 'PROBE FAILED: a no-op run owed % message(s)', v_owed_tx; end if;
    perform set_config('qd.lost_customer_verdict', 'PROBE OK: no-op, customers row ' || left(cu.id::text, 8)
      || ' already holds the address; nothing written in this run (owed to it at support.lost_request: '
      || (select count(*) from public.customer_support_voice_owed where stage = 'support.lost_request' and lower(to_email) = c_email)
      || ')', true);
    return;
  end if;
  if v_mode <> 'restored' then raise exception 'PROBE FAILED: the restore block did not report (mode "%")', v_mode; end if;

  if cu.id <> c_id or not cu.email_verified or coalesce(cu.is_demo, false) or cu.banned
     or cu.signed_terms_path is null or cu.signed_terms_at < cu.tos_accepted_at or cu.full_name <> 'TIWNKLE SHARMA' then
    raise exception 'PROBE FAILED: the restored row is not the measured one: %', row_to_json(cu);
  end if;
  -- the every-5-minutes unfinished-sign-up purge must hold it (it is missing 'mobile')
  if not public.fn_signup_customer_held(cu.id) then
    raise exception 'PROBE FAILED: fn_unfinished_signup_purge would delete the restored customer within 5 minutes';
  end if;
  select count(*) into v_owed from public.customer_support_voice_owed
   where stage = 'support.lost_request' and subject_key = c_id::text and lower(to_email) = c_email and written_at is null
     and to_role = 'customer' and lang = 'en';
  if v_owed <> 1 or v_owed_tx <> 1 then
    raise exception 'PROBE FAILED: % message(s) owed to the customer, % owed by this transaction; expected 1 and 1', v_owed, v_owed_tx;
  end if;
  if exists (select 1 from public.customer_support_duty_message where stage = 'support.lost_request' and subject_key = c_id::text) then
    raise exception 'PROBE FAILED: support.lost_request is already recorded as written, so the model''s message would never be sent';
  end if;
  select count(*) into v_marker from public.customer_support_duty_message
   where stage = 'activation.first_request' and subject_key = c_id::text and outcome like 'superseded:%' and handoff_id is null;
  if v_marker <> 1 then raise exception 'PROBE FAILED: the activation stage is not closed (% marker rows)', v_marker; end if;
  select count(*) into v_events from public.company_event where occurred_at = now() and event_type = 'customer.registered'
     and entity_id = c_id::text;
  perform set_config('qd.lost_customer_verdict', 'PROBE OK: customer ' || left(c_id::text, 8) || ' restored for login 15bcba0f '
    || '(e-mail verified, held from the unfinished-sign-up purge by its signed terms); 1 message owed to ' || c_email
    || ' at support.lost_request for the model to write (0 to anyone else); 0 notifications and 0 delivery hand-offs written; '
    || 'activation.first_request closed as superseded; customer.registered events emitted: ' || v_events, true);
end $probe$;

select current_setting('qd.lost_customer_verdict', true) as verdict;
