-- THE DROPBOX BACKUP IS CONFIRMED, NOT ASSUMED.
--
-- Assigned: it_engineer (verification: the post-upload check, the weekly re-check, the 48-hour
-- coverage watch, the abandoned-row investigation), with sales_engineer (filing: the tree, the
-- uploads, the refile). Carried out for the ceo, 14 Sep 2026.
--
-- The founder, 14 Sep 2026, relayed by the coordinating session, on who checks the backup:
--   "i think the IT agent need to check such details yea?"
-- The sales engineer files; the IT engineer verifies; the sales engineer never marks its own work
-- verified; persistent failure goes to the CEO.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   doc_backups      183 done, 26 abandoned (all created 11-15 Jul), 0 pending, 0 error.
--   'done' meant     files/upload returned 200. Nothing ever read the file back; no row carried a
--                    hash or the size Dropbox holds. A backup that was never confirmed was counted
--                    as one.
--   fn_backup_watch  NOTHING CALLS IT. The brief said fn_it_detect reads it; fn_it_detect mentions it
--                    only in comments (its D8 detector reads pg_stat_archiver), no routine's source
--                    calls it, and no edge function does -- the last caller was pg_cron, removed
--                    7 Sep. The only invocation in the repository is a probe script. It also only
--                    ever asked "did a RUN fail or go stale", never "is every document in Dropbox".
--   handoffs         agent_actions kind='handoff' through fn_seat_handoff is the estate's one
--                    seat-to-seat mechanism; it_engineer had no conversation in it.
--   reporting        it_engineer had NO org_reporting_edge, so fn_support_report_to_ceo refused
--                    every report it could have filed ("No active reporting parent").
--
-- THE 26 ABANDONED ROWS, EACH ONE READ (source checked in storage.objects / leads / inquiries):
--   15  gen_kind='comparison' (ids 5965-5975, 6047, 6297, 6298, 6390). The quote-comparison renderer
--       was retired with quote_compare on 9 Sep (dropbox_backup v5 header); and all 15 inquiries
--       they describe no longer exist (0 of 15 in public.inquiries). Nothing to render, nowhere to
--       render it from.
--    8  gen_kind='supplier_details' for leads 30337-30344 ("QA SkyLine Ceilings" ... "QA ShieldPest
--       Control" -- QA fixtures). None of the 8 leads exists; renderGenerated fails supplier_missing.
--    3  source='storage', lead 30361 (Emirates Prestige Flooring LLC, seed_profile.pdf and two
--       seed_catalog PDFs). None of the 3 objects is in storage.objects and the lead no longer exists.
--   REQUEUED: 0. Every one gets its reason written into `error` as 'abandoned: ...' so the coverage
--   watch below can tell a documented abandonment from a lost document. The statement decides from
--   the source at apply time, so a source that reappears is requeued rather than annotated.
--
-- WHAT CHANGES:
--   1. doc_backups gains dropbox_content_hash, dropbox_size, verified_at (written only by the
--      it_engineer's post-upload check in dropbox_backup v6, after files/get_metadata agrees on
--      size and hash) and requeued_at (so a refiled row's age counts from the refile).
--   2. Weekly reconciliation: fn_dropbox_reconcile_due (once per Asia/Dubai ISO week),
--      fn_dropbox_reconcile_sample, fn_dropbox_reconcile_apply. A file missing or changed in
--      Dropbox is an it_engineer finding and a 'backup.refile' handoff to the sales engineer, who
--      requeues it. The handoff stays open until the it_engineer sees the row verified again
--      (fn_it_backup_refile_close) -- the filer never closes its own refile.
--   3. Coverage, not freshness: fn_backup_coverage, read by fn_backup_watch. It fails when a row is
--      not done 48h after it was queued (documented abandonments excepted), when a source the
--      enqueue would pick up has no row and the enqueue has not succeeded for 48h, when a refile
--      handoff is open past 48h or failed, and -- once it exists -- when the conversation
--      retention function reports a breach older than 48h. A failure is an it_engineer finding
--      and a 'serious' report to the CEO.
--   4. fn_dropbox_backup_summary / fn_dropbox_backup_daily_report: one line a day from the
--      it_engineer to the CEO (support_ceo_report): queued / uploaded / verified / failed, last 24h
--      and totals.
--   5. fn_it_backup_tick: the one call resilience_ping makes for all of the above.
--
-- NOT DONE, AND WHY: the new SQL routines are NOT registered in public.function_owner. That table
-- is keyed by deployed edge-function slug and every_deployed_function_has_an_owner.mjs fails on a
-- row with no deployed function ("a record outliving its subject"). They are attributed instead by
-- what they write: agent_actions agent='it_engineer', agent_runs agent='it_engineer' (which
-- fn_run_seat maps to the it_engineer seat), and support_ceo_report source_agent='it_engineer'.
--
--   node scripts/apply_sql.mjs scripts/sql/the_dropbox_backup_is_confirmed_not_assumed.sql --apply --ddl

-- ── 1. THE COLUMNS THAT MAKE "DONE" MEAN SOMETHING ─────────────────────────────────────────────
alter table public.doc_backups add column if not exists dropbox_content_hash text;
alter table public.doc_backups add column if not exists dropbox_size bigint;
alter table public.doc_backups add column if not exists verified_at timestamptz;
alter table public.doc_backups add column if not exists requeued_at timestamptz;
comment on column public.doc_backups.verified_at is
  'When the it_engineer''s check confirmed this file in Dropbox: files/get_metadata returned the same size and the same content_hash as the bytes sent (dropbox_backup v6), or the weekly reconciliation matched it. NULL on a done row means uploaded but never confirmed.';
comment on column public.doc_backups.dropbox_content_hash is
  'Dropbox content_hash of the file as confirmed (SHA-256 of the concatenated SHA-256 digests of each 4 MiB block).';
comment on column public.doc_backups.requeued_at is
  'When a refile or a reset put this row back in the queue; the 48-hour coverage clock counts from here instead of created_at.';

-- ── 2. THE IT ENGINEER REPORTS TO THE CEO ─────────────────────────────────────────────────────
insert into public.org_reporting_edge (child_role_id, parent_role_id, established_at, established_by, reason)
select 'it_engineer', 'ceo', now(), 'founder',
       'Founder ruling 14 Sep 2026 ("i think the IT agent need to check such details yea?"): the IT engineer verifies the Dropbox backup and sends the daily backup line, and any persistent failure, to the CEO. Without this edge fn_support_report_to_ceo refused every it_engineer report.'
 where exists (select 1 from public.org_role where role_id = 'it_engineer' and status = 'active')
on conflict (child_role_id) do nothing;

-- ── 3. THE 26 ABANDONED ROWS ──────────────────────────────────────────────────────────────────
with s as (
  select d.id,
         case when d.source = 'storage' then exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path)
              when d.gen_kind = 'supplier_details' then exists (select 1 from public.leads l where l.id::text = d.gen_ref)
              when d.gen_kind = 'customer_details' then exists (select 1 from public.customers c where c.id::text = d.gen_ref)
              when d.gen_kind = 'inquiry_summary'  then exists (select 1 from public.inquiries i where i.id::text = d.gen_ref)
              else false end as src_ok,
         case when d.source = 'storage'
                then 'abandoned: source object ' || coalesce(d.bucket, '?') || '/' || coalesce(d.path, '?')
                     || ' is not in storage and ' || d.entity || ' ' || d.entity_id
                     || case when d.entity = 'supplier' and not exists (select 1 from public.leads l where l.id::text = d.entity_id)
                             then ' no longer exists' else ' still exists but no longer holds it' end
              when d.gen_kind = 'comparison'
                then 'abandoned: the quote-comparison renderer was retired with quote_compare on 9 Sep 2026'
                     || case when not exists (select 1 from public.inquiries i where i.id::text = d.gen_ref)
                             then ' and inquiry ' || left(d.gen_ref, 8) || ' no longer exists' else '' end
              else 'abandoned: ' || coalesce(d.gen_kind, 'generated') || ' source ' || coalesce(d.gen_ref, '?') || ' no longer exists, nothing to render'
         end || ' (measured 14 Sep 2026; last upload error: ' || coalesce(d.error, 'none') || ')' as reason
    from public.doc_backups d
   where d.status = 'abandoned' and coalesce(d.error, '') not like 'abandoned:%'
)
update public.doc_backups d
   set status      = case when s.src_ok then 'pending' else 'abandoned' end,
       attempts    = case when s.src_ok then 0 else d.attempts end,
       error       = case when s.src_ok then null else left(s.reason, 300) end,
       requeued_at = case when s.src_ok then now() else d.requeued_at end
  from s where s.id = d.id;

-- ── 4. THE CONVERSATION: backup.refile, it_engineer -> sales_engineer ──────────────────────────
-- Mirrored in supabase/functions/_shared/payment_handoffs.ts; payments_are_the_accountant.test.mjs
-- fails if they differ. The first 22 rows are the list as it stood, unchanged.
create or replace function public.fn_seat_handoff_types()
returns table(type text, from_seat text, to_seat text, meaning text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  values
    ('reveal.paid',              'accountant',       'sales_engineer',   'A reveal charge settled at Stripe: tell the customer the contact is released and the supplier that they were revealed.'),
    ('payment.failed',           'accountant',       'sales_engineer',   'A reveal checkout expired or failed: tell the customer nothing was charged and how to try again.'),
    ('payment.received',         'accountant',       'sales_engineer',   'A supplier paid an outstanding charge or the registration fee: confirm it to them.'),
    ('refund.request_checked',   'accountant',       'sales_engineer',   'The books checked a refund request: acknowledge it to the customer.'),
    ('refund.paid',              'accountant',       'sales_engineer',   'A refund settled: tell the customer what came back and when the bank shows it.'),
    ('refund.declined',          'accountant',       'sales_engineer',   'A refund was declined: tell the customer why.'),
    ('refund.in_progress',       'accountant',       'sales_engineer',   'A refund is approved but not settled after a retry: tell the customer it is in progress.'),
    ('nonresponse.charge_raised','accountant',       'sales_engineer',   'The non-response charge was raised: tell the supplier the figures.'),
    ('charge.corrected',         'accountant',       'sales_engineer',   'A charge already sent was wrong: send a correction to whoever got the original.'),
    ('subscription.due',         'accountant',       'sales_engineer',   'The yearly registration fee fell due: tell the supplier.'),
    ('billing.answer',           'accountant',       'sales_engineer',   'The books answered a billing question: relay it.'),
    ('charge.dispute_answer',    'accountant',       'sales_engineer',   'The books checked a disputed charge: relay the result to the supplier.'),
    ('refund.requested',         'sales_engineer',   'accountant',       'A customer asked for a refund in the portal: check the money behind it.'),
    ('billing.question',         'sales_engineer',   'accountant',       'A customer or supplier asked about a charge, an invoice or a refund: read the books.'),
    ('charge.disputed',          'sales_engineer',   'accountant',       'A supplier disputed a charge: recompute it from the refund record.'),
    ('refund.remediate',         'ceo',              'accountant',       'The CEO refused approval on a money check the accountant owns: fix it and report back.'),
    ('refund.remediate',         'ceo',              'sales_engineer',   'The CEO refused approval on a ladder check the sales engineer owns: fix it and report back.'),
    ('incident.fix',             'ceo',              'accountant',       'Post-payment re-verification found a mismatch: apply the fix the playbook names.'),
    ('delivery.request',         'sales_engineer',   'customer_support', 'Deliver these words to a customer or supplier through the outbox, and watch for the reply when asked.'),
    ('delivery.request',         'ceo',              'customer_support', 'Deliver this summary to the founder on his command channel.'),
    ('delivery.request',         'accountant',       'customer_support', 'Deliver this money exception to the founder on his command channel.'),
    ('delivery.result',          'customer_support', 'sales_engineer',   'What came back: proof the supplier responded, or confirmation that nothing did.'),
    ('backup.refile',            'it_engineer',      'sales_engineer',   'The IT engineer found a backed-up document missing, changed or unconfirmed in Dropbox: file it again. The IT engineer closes it once the new copy is verified.')
$fn$;

-- The sales engineer's half of a refile: put the document back in its own queue. It does NOT close
-- the handoff; it waits for the it_engineer to see the new copy verified.
create or replace function public.fn_sales_engineer_refiles_backup(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_row bigint; n int;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_row := (a.detail->>'doc_backup_id')::bigint;
  update public.doc_backups
     set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
         error = left('refile: ' || coalesce(a.detail->>'reason', 'requested') || ' (it_engineer handoff ' || p_id || ')', 300)
   where id = v_row and status <> 'abandoned';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'backup.refile: doc_backups row % does not exist or is abandoned', v_row; end if;
  return jsonb_build_object('waiting', 'it_engineer re-verification', 'doc_backup_id', v_row, 'requeued_at', now());
end $fn$;
revoke execute on function public.fn_sales_engineer_refiles_backup(bigint) from public, anon, authenticated;

-- The sales engineer's handler, verbatim from production (14 Sep 2026) with one branch added
-- before the final raise: 'backup.refile'.
create or replace function public.fn_sales_engineer_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
as $fn$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';
  select refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3); v_min := coalesce(v_min, 7); v_max := coalesce(v_max, 14);

  select null::uuid as id, null::text as email, null::text as full_name into v_cust;
  select null::bigint as id, null::text as company_name, null::text as email into v_sup;
  if (d->>'customer_id') is not null then
    select id, email, full_name into v_cust from public.customers where id = (d->>'customer_id')::uuid;
  end if;
  if (d->>'supplier_id') is not null then
    select id, company_name, coalesce(claimed_by, email) as email into v_sup from public.leads where id = (d->>'supplier_id')::bigint;
  end if;
  if (d->>'inquiry_id') is not null then
    select summary into v_inq from public.inquiries where id = (d->>'inquiry_id')::uuid;
  end if;
  v_revealed := coalesce(to_char((d->>'revealed_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date');
  v_rid := left(coalesce(d->>'transaction_id', d->>'subject_id', ''), 8);

  if t = 'reveal.paid' then
    -- The words trg_reveal_receipt used to write itself, unchanged, now composed by the seat whose
    -- voice the portal is and carried by the seat that owns the pipe.
    if v_cust.email is not null then
      v_req := public.fn_sales_engineer_writes('reveal_receipt', 'customer', v_cust.email, null, v_cust.id,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Reveal confirmed — ' || coalesce(v_sup.company_name, 'supplier'),
        'You have unlocked ' || coalesce(v_sup.company_name, 'the supplier') || '''s contact details'
          || coalesce(' for: ' || left(v_inq, 80), '')
          || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'تم تأكيد الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لك الآن، ويمكنك مراسلته مباشرة من التطبيق. '
          || 'نتابع هذا الكشف منذ لحظة الدفع: إن لم يردّ المورّد خلال ' || v_chase::text || ' أيام عمل نتواصل معه نيابةً عنك مع نسخة لك، '
          || 'وإن لم يردّ حتى يوم العمل ' || v_window::text || ' يقرّر رئيسنا التنفيذي في الحالة، وإن لم يردّ المورّد إطلاقًا نردّ إليك كامل ما دفعته.',
        '{}', 'reveal_receipt:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    if coalesce(v_sup.email, '') like '%@%' then
      perform public.fn_sales_engineer_writes('quote_accepted', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'A customer revealed your quote on QuotesDone',
        'A customer paid to reveal your contact for: ' || coalesce(v_inq, '')
          || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
          || ' working days of the reveal. If you have not responded after ' || v_chase::text
          || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
          || ' our chief executive decides the case, the customer is refunded, and the amount refunded plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
        'كشف عميل عن عرضك على QuotesDone',
        'دفع عميل للكشف عن بيانات التواصل معك بخصوص: ' || coalesce(v_inq, '') || '. يُرجى الرد سريعًا — بموجب اتفاقية المورّد يجب الرد خلال '
          || v_window::text || ' أيام عمل من الكشف، وإلا يُردّ للعميل ما دفعه ويُسترد المبلغ من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا.',
        '{}', 'quote_accepted:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req);

  elsif t = 'payment.failed' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('reveal_payment_incomplete', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your reveal payment did not complete',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your payment to unlock the supplier''s contact details did not go through, and nothing was charged to your card.' || E'\n\n'
        || 'You can try again at any time: open the request in your QuotesDone portal and choose Reveal on the quote you picked. If the card was declined, your bank can tell you why, and a different card also works.',
      'لم تكتمل عملية الدفع للكشف',
      'لم تنجح عملية الدفع للكشف عن بيانات المورّد، ولم يُخصم أي مبلغ من بطاقتك. يمكنك المحاولة مجددًا في أي وقت من بوابتك في QuotesDone.',
      '{}', 'payment_failed:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'payment.received' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes(coalesce(d->>'msg_type', 'dues_paid'), 'supplier', v_sup.email, v_sup.id, null, null, null,
      case when d->>'kind' = 'supplier_registration' then 'Registration confirmed - thank you' else 'Payment received - thank you' end,
      case when d->>'kind' = 'supplier_registration'
           then 'We have received your registration payment of AED ' || (d->>'amount_aed') || '. Your QuotesDone supplier account is registered for the next 12 months.'
           else 'We have received your payment of AED ' || (d->>'amount_aed') || ' settling ' || coalesce(d->>'items', '1') || ' outstanding charge(s). Your account is now up to date.' end,
      'تم استلام دفعتك', 'استلمنا دفعتك بقيمة ' || (d->>'amount_aed') || ' درهم. شكرًا لك.',
      '{}', 'payment_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.request_checked' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_amt := case when (d->>'money_ok')::boolean then ' — AED ' || (d->>'amount_aed') else '' end;
    v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'We have your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have received your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || '.' || E'\n\n'
        || 'What happens next: we check whether the supplier ever replied to you, our chief executive decides on that record, and if the refund is due you get back everything you paid'
        || v_amt || ', the reveal fee and the card processing part together, to the card you paid with. Banks usually take ' || v_min || '–' || v_max || ' working days to show it.' || E'\n\n'
        || 'If you have an email thread with the supplier, keep it: it is the proof we rely on.',
      'استلمنا طلب الاسترداد',
      'استلمنا طلب استرداد مبلغ الكشف. نتحقق أولًا من ردّ المورّد، ثم يقرّر رئيسنا التنفيذي، وإن كان الاسترداد مستحقًا يعود إليك كامل ما دفعته إلى البطاقة نفسها خلال '
        || v_min || '–' || v_max || ' يوم عمل بحسب البنك.',
      '{}', 'refund_request_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'money_ok', d->'money_ok');

  elsif t = 'refund.paid' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        || 'You are welcome to post the request again; we will introduce you to another supplier.',
      'تم إصدار استرداد بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لك استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، وهو كامل ما دفعته، إلى وسيلة الدفع الأصلية لأن المورّد لم يردّ خلال '
        || v_window::text || ' أيام عمل. قد يستغرق ظهوره في كشف حسابك ' || v_min || '–' || v_max || ' يوم عمل.',
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed');

  elsif t = 'refund.declined' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_declined', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'About your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We looked at your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || ' and it was not approved.' || E'\n\n'
        || 'The reason: ' || coalesce(nullif(btrim(d->>'note'), ''), 'the record shows the supplier did respond.') || E'\n\n'
        || 'If you think we have missed something, reply to this email with what you have — an email thread with the supplier, dates, anything — and we will look again.',
      'بخصوص طلب الاسترداد',
      'راجعنا طلب الاسترداد ولم تتم الموافقة عليه. السبب: ' || coalesce(nullif(btrim(d->>'note'), ''), 'السجل يُظهر أن المورّد قد ردّ.')
        || ' إن كان لديك ما يثبت خلاف ذلك فردّ على هذه الرسالة وسنراجع الطلب مجددًا.',
      '{}', 'refund_declined:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.in_progress' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_in_progress', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your refund is being processed',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your refund of AED ' || coalesce(d->>'amount_aed', '') || ' has been approved and is being processed with the payment provider. It has not reached your card yet; we will write again the moment it has.',
      'استردادك قيد المعالجة',
      'تمت الموافقة على استردادك وهو قيد المعالجة لدى مزوّد الدفع، ولم يصل إلى بطاقتك بعد. سنراسلك فور وصوله.',
      '{}', 'refund_in_progress:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t in ('nonresponse.charge_raised', 'charge.corrected') then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := '  Amount refunded to the customer: AED ' || (d->>'refunded_aed') || E'\n'
            || '  Administration fee: AED ' || (d->>'admin_fee_aed') || E'\n'
            || '  Interest: ' || round((d->>'interest_apr')::numeric * 100, 2) || '% a year, simple, on AED '
            || round((d->>'refunded_aed')::numeric + (d->>'admin_fee_aed')::numeric, 2) || ' from ' || (d->>'due_date') || ' until paid' || E'\n'
            || '  Due by: ' || (d->>'due_date');
    if t = 'nonresponse.charge_raised' then
      v_req := public.fn_sales_engineer_writes('nonresponse_charge', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Charge under the Supplier Agreement — reveal #' || left(coalesce(d->>'transaction_id', ''), 8),
        'Hello ' || coalesce(v_sup.company_name, '') || E',\n\n'
          || 'A customer paid to reveal your contact details and did not hear from you within ' || v_window::text
          || ' working days, despite the reminders we sent. Under the Supplier Agreement the customer has been refunded in full, and that refund is recovered from your account:' || E'\n\n'
          || v_lines || E'\n\n'
          || 'Matching is paused until this is settled. You can pay it from the Billing section of your supplier portal. If you believe it is wrong, use "Dispute this charge" there or reply to this email and we will check the figures against the payment record.',
        'رسوم بموجب اتفاقية المورّد',
        'دفع عميل للكشف عن بيانات التواصل معك ولم يتلقَّ ردًّا خلال ' || v_window::text || ' أيام عمل رغم التذكيرات. بموجب اتفاقية المورّد رُدّ للعميل كامل ما دفعه ويُسترد من حسابك: المبلغ المسترد '
          || (d->>'refunded_aed') || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، وفائدة بسيطة ' || round((d->>'interest_apr')::numeric * 100, 2)
          || '% سنويًا من ' || (d->>'due_date') || ' حتى السداد. يمكنك السداد أو الاعتراض من قسم الفواتير في بوابتك.',
        '{}', 'nonresponse_charge:' || (d->>'subject_id'));
    else
      -- THE CORRECTION MUST REACH WHOEVER GOT THE ORIGINAL: its To and every Cc, not today's address book.
      select * into v_orig from public.notifications where id = (d->>'original_notification_id')::bigint;
      v_req := public.fn_sales_engineer_writes('nonresponse_charge_correction', 'supplier',
        coalesce(v_orig.to_email, v_sup.email), v_sup.id, null, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Correction: ' || coalesce(v_orig.subject, 'your charge under the Supplier Agreement'),
        'This replaces our message of ' || coalesce(to_char(v_orig.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'earlier')
          || ' about this charge, which carried the wrong figures. Please disregard it. The correct figures are:' || E'\n\n' || v_lines,
        'تصحيح: رسوم بموجب اتفاقية المورّد',
        'هذه الرسالة تحلّ محلّ رسالتنا السابقة التي تضمنت أرقامًا غير صحيحة. الأرقام الصحيحة: المبلغ المسترد ' || (d->>'refunded_aed')
          || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، مستحقة في ' || (d->>'due_date') || '.',
        coalesce(v_orig.cc_emails, '{}'), 'charge_corrected:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'subscription.due' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('subscription_due', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your QuotesDone annual subscription is due',
      'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour QuotesDone annual supplier subscription of '
        || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
      'اشتراكك السنوي في QuotesDone مستحق',
      'اشتراكك السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم مستحق الآن. يمكنك السداد بأمان من بوابة المورّد.',
      '{}', 'subscription_due:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'billing.answer' then
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'facts') x);
    if d->>'party' = 'supplier' then
      if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  Nothing is recorded against your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    else
      if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'customer', v_cust.email, null, v_cust.id, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  No payment is recorded on your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req, 'facts', d->'facts');

  elsif t = 'charge.dispute_answer' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'lines') x);
    v_req := public.fn_sales_engineer_writes('charge_dispute_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your query about charge #' || coalesce(d->>'due_id', ''),
      case when (d->>'figures_match')::boolean
           then E'We checked the charge against the payment record and the figures stand:\n\n'
           else E'We checked the charge against the payment record and the figures do not match it. It is on hold while our chief executive reviews it; you do not need to pay it until we write again.\n\n' end
        || coalesce(v_lines, ''),
      null, null, '{}', 'charge_dispute_answer:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'figures_match', d->'figures_match');

  elsif t = 'refund.remediate' then
    return public.fn_sales_engineer_remediates(p_id);

  elsif t = 'delivery.result' then
    return public.fn_sales_engineer_attaches_delivery_result(p_id);

  elsif t = 'backup.refile' then
    return public.fn_sales_engineer_refiles_backup(p_id);
  end if;
  raise exception 'sales_engineer has no handler for %', t;
end $fn$;

-- ── 5. THE WEEKLY RECONCILIATION ──────────────────────────────────────────────────────────────
create or replace function public.fn_dropbox_reconcile_due()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with w as (select to_char(now() at time zone 'Asia/Dubai', 'IYYY-"W"IW') as week)
  select jsonb_build_object(
    'due', not exists (select 1 from public.agent_runs r, w
                        where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_reconcile'
                          and r.status in ('ok', 'warn')
                          and to_char(r.started_at at time zone 'Asia/Dubai', 'IYYY-"W"IW') = w.week)
       and not exists (select 1 from public.agent_runs r
                        where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_reconcile'
                          and r.status = 'error' and r.started_at > now() - interval '6 hours'),
    'week', (select week from w));
$fn$;
revoke execute on function public.fn_dropbox_reconcile_due() from public, anon, authenticated;
comment on function public.fn_dropbox_reconcile_due() is
  'it_engineer: once per Asia/Dubai ISO week, the Dropbox reconciliation is due; a failed attempt waits 6 hours before the next. Read by fn_it_backup_tick.';

-- ponytail: uniform random over every done row, so rows filed before v6 are confirmed over the
-- weeks (20 a week against 183 today). Bias toward unverified rows if that proves too slow.
create or replace function public.fn_dropbox_reconcile_sample(p_n integer default 20)
returns table(id bigint, dropbox_path text, bucket text, path text, bytes bigint, dropbox_content_hash text)
language sql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
  select d.id, d.dropbox_path, d.bucket, d.path, d.bytes, d.dropbox_content_hash
    from public.doc_backups d
   where d.status = 'done' and d.dropbox_path is not null
   order by random()
   limit greatest(1, least(coalesce(p_n, 20), 200));
$fn$;
revoke execute on function public.fn_dropbox_reconcile_sample(integer) from public, anon, authenticated;

-- p_results: [{id, outcome: ok|changed|missing|unverifiable|error, hash, size, basis, note}].
create or replace function public.fn_dropbox_reconcile_apply(p_results jsonb, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r jsonb; v_id bigint; v_out text; v_week text := to_char(now() at time zone 'Asia/Dubai', 'IYYY-"W"IW');
  c jsonb := jsonb_build_object('job', 'dropbox_reconcile', 'week', v_week);
  n_ok int := 0; n_missing int := 0; n_changed int := 0; n_unver int := 0; n_err int := 0;
  v_handoffs jsonb := '[]'::jsonb; v_h bigint; v_status text; v_note text;
begin
  if p_error is not null then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'error', c || jsonb_build_object('stage', 'fatal'),
            left('The weekly Dropbox reconciliation did not run: ' || p_error || '. No file was re-checked this attempt; it is retried after 6 hours.', 500), now(), now());
    return jsonb_build_object('ok', false, 'error', p_error);
  end if;

  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    v_id := (r->>'id')::bigint; v_out := r->>'outcome';
    if v_out = 'ok' then
      update public.doc_backups set dropbox_content_hash = r->>'hash', dropbox_size = (r->>'size')::bigint, verified_at = now()
       where id = v_id and status = 'done';
      n_ok := n_ok + 1;
    elsif v_out in ('missing', 'changed') then
      if v_out = 'missing' then n_missing := n_missing + 1; else n_changed := n_changed + 1; end if;
      -- The finding, on the row: no longer confirmed. The status stays the filer's to change.
      update public.doc_backups
         set verified_at = null,
             error = case when v_out = 'missing' then 'reconcile: missing in Dropbox'
                          else 'reconcile: content in Dropbox differs from what was confirmed' end
       where id = v_id;
      v_h := public.fn_seat_handoff('it_engineer', 'sales_engineer', 'backup.refile', 'doc_backups', v_id::text || '@' || v_week,
               jsonb_build_object('doc_backup_id', v_id, 'reason', 'reconcile ' || v_out, 'dropbox_hash_seen', r->>'hash', 'basis', r->>'basis'));
      v_handoffs := v_handoffs || to_jsonb(v_h);
    elsif v_out = 'unverifiable' then n_unver := n_unver + 1;
    else n_err := n_err + 1;
    end if;
  end loop;

  c := c || jsonb_build_object('checked', jsonb_array_length(coalesce(p_results, '[]'::jsonb)), 'ok', n_ok,
         'missing', n_missing, 'changed', n_changed, 'unverifiable', n_unver, 'errors', n_err, 'handoffs', v_handoffs);
  v_status := case when n_missing + n_changed + n_err > 0 then 'warn' else 'ok' end;
  v_note := 'Weekly Dropbox reconciliation ' || v_week || ': ' || (c->>'checked') || ' checked, ' || n_ok || ' confirmed, '
         || n_missing || ' missing, ' || n_changed || ' changed, ' || n_unver || ' unverifiable (no recorded hash and no source), '
         || n_err || ' could not be read.'
         || case when n_missing + n_changed > 0 then ' Each missing or changed file was handed to the sales engineer to refile.' else '' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, c, left(v_note, 500), now(), now());
  return c || jsonb_build_object('status', v_status, 'note', v_note);
end $fn$;
revoke execute on function public.fn_dropbox_reconcile_apply(jsonb, text) from public, anon, authenticated;

-- The it_engineer closes a refile only when it sees the new copy verified after the handoff.
create or replace function public.fn_it_backup_refile_close()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; n int := 0;
begin
  for h in
    select a.id, d.id as doc_id, d.verified_at, d.dropbox_content_hash
      from public.agent_actions a
      join public.doc_backups d on d.id = (a.detail->>'doc_backup_id')::bigint
     where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'type' = 'backup.refile'
       and a.status = 'pending' and d.status = 'done' and d.verified_at > a.created_at
  loop
    perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'it_engineer',
      'doc_backup_id', h.doc_id, 'verified_at', h.verified_at, 'dropbox_content_hash', h.dropbox_content_hash));
    update public.agent_actions set decided_by = 'it_engineer' where id = h.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('closed', n);
end $fn$;
revoke execute on function public.fn_it_backup_refile_close() from public, anon, authenticated;

-- ── 6. COVERAGE, NOT FRESHNESS ────────────────────────────────────────────────────────────────
create or replace function public.fn_backup_coverage()
returns jsonb language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_not_done int; v_ids jsonb; v_abandoned int; v_unqueued int; v_unq_err text; v_last_ok timestamptz;
  v_conv jsonb; v_conv_fn text := 'public.fn_conversation_retention' || '_breaches(interval)';
  v_refile int; v_fail text[] := '{}';
begin
  -- (a) queued and still not done 48h after it was queued. Documented abandonments are excepted.
  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]'::jsonb) into v_not_done, v_ids
    from (select d.id, row_number() over (order by d.id) rn from public.doc_backups d
           where d.status <> 'done'
             and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%')
             and coalesce(d.requeued_at, d.created_at) < now() - interval '48 hours') x;
  select count(*) into v_abandoned from public.doc_backups where status = 'abandoned' and coalesce(error, '') like 'abandoned:%';
  if v_not_done > 0 then v_fail := array_append(v_fail, 'not_done_after_48h'); end if;

  -- (b) sources the enqueue would pick up that have no row. Measured by running the enqueue itself
  -- and rolling it back, so this can never disagree with what fn_enqueue_doc_backups does.
  begin
    v_unqueued := public.fn_enqueue_doc_backups();
    raise exception using errcode = 'QDRBK', message = 'roll back the coverage measurement';
  exception
    when sqlstate 'QDRBK' then null;
    when read_only_sql_transaction then v_unq_err := 'not measurable in a read-only transaction';
    when others then v_unq_err := left(sqlerrm, 200);
  end;
  select max(started_at) into v_last_ok from public.agent_runs where agent = 'dropbox_backup' and status = 'ok';
  if (v_unqueued > 0 and coalesce(v_last_ok, '-infinity') < now() - interval '48 hours')
     or (v_unq_err is not null and v_unq_err <> 'not measurable in a read-only transaction') then
    v_fail := array_append(v_fail, 'sources_without_a_row');
  end if;

  -- (c) the conversation archive, once its retention function exists.
  if to_regprocedure(v_conv_fn) is not null then
    begin
      execute 'select ' || replace(v_conv_fn, '(interval)', '($1)') into v_conv using interval '48 hours';
    exception when others then v_conv := jsonb_build_object('error', left(sqlerrm, 200));
    end;
    if coalesce((v_conv->>'total')::int, 0) > 0 or v_conv ? 'error' then v_fail := array_append(v_fail, 'conversation_retention'); end if;
  end if;

  -- (d) refiles the sales engineer has not got verified within 48h, or that failed outright.
  select count(*) into v_refile from public.agent_actions
   where kind = 'handoff' and agent = 'sales_engineer' and detail->>'type' = 'backup.refile'
     and (status = 'failed' or (status = 'pending' and created_at < now() - interval '48 hours'));
  if v_refile > 0 then v_fail := array_append(v_fail, 'refile_not_verified_in_48h'); end if;

  return jsonb_build_object(
    'ok', cardinality(v_fail) = 0, 'failing', to_jsonb(v_fail),
    'not_done_after_48h', v_not_done, 'not_done_ids', v_ids, 'abandoned_documented', v_abandoned,
    'sources_without_a_row', v_unqueued, 'sources_error', v_unq_err, 'last_ok_backup', v_last_ok,
    'conversation_retention', coalesce(v_conv, jsonb_build_object('checked', false, 'reason', 'function not installed')),
    'refiles_open_past_48h', v_refile, 'measured_at', now());
end $fn$;
revoke execute on function public.fn_backup_coverage() from public, anon, authenticated;

-- Canonical until now: the_backup_watcher_was_watching_a_name_nothing_writes.sql. Its body is kept
-- verbatim except: search_path gains pg_temp; the freshness alert is addressed to it_engineer (was
-- 'security', which the addressee trigger rewrote to 'brief'); and coverage is read and returned.
-- The return shape is the old one plus a 'coverage' key; 'ok' is now false when coverage fails.
create or replace function public.fn_backup_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_last timestamptz; v_status text; v_stale boolean; v_open int; v_subject_rows int;
  v_cov jsonb; v_cov_ok boolean; v_cov_open int := 0; v_date text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  -- The subject is the backup that this database can actually SEE. Managed physical backups are
  -- not in here and this function makes no claim about them.
  c_agents constant text[] := array['dropbox_backup','fn:dropbox_backup'];
begin
  -- POSITIVE CONTROL FIRST. A name that matches no rows is a fact about the query. Refuse to conclude.
  select count(*) into v_subject_rows from agent_runs where agent = any(c_agents);
  if v_subject_rows = 0 then
    return jsonb_build_object(
      'ok', false,
      'reason', 'subject_not_found',
      'watched', c_agents,
      'detail', 'No run of any watched backup agent has ever been recorded, so this watcher cannot '
             || 'tell a stopped backup from a renamed one. It alerts nobody rather than reporting '
             || 'catastrophe from an empty lookup. Check the agent name before the backup.');
  end if;

  select started_at, status into v_last, v_status
    from agent_runs where agent = any(c_agents) order by started_at desc limit 1;

  -- COVERAGE (14 Sep 2026). A run that succeeded says nothing about whether every document is in
  -- Dropbox. A coverage failure is by construction 48 hours old, so it is both the it_engineer's
  -- finding and a report to the CEO; deduped to one of each per 20 hours / per Dubai day.
  v_cov := public.fn_backup_coverage();
  v_cov_ok := coalesce((v_cov->>'ok')::boolean, false);
  if not v_cov_ok then
    select count(*) into v_cov_open from agent_actions
     where kind = 'backup_coverage' and agent = 'it_engineer' and coalesce(status,'') in ('pending','needs_review')
       and created_at > now() - interval '20 hours';
    if v_cov_open = 0 then
      insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
      values('it_engineer','backup_coverage','pending','medium',
        'Dropbox backup coverage failing: ' || (v_cov->>'failing'),
        'Something that should be in Dropbox has not reached it within 48 hours: '
        || (v_cov->>'not_done_after_48h') || ' queued row(s) not done, '
        || coalesce(v_cov->>'sources_without_a_row','unknown') || ' source(s) with no row, '
        || (v_cov->>'refiles_open_past_48h') || ' refile(s) not verified. Rows: ' || (v_cov->>'not_done_ids') || '.',
        'doc_backups', v_cov);
      perform public.fn_support_report_to_ceo(
        'dropbox_backup_escalation:' || v_date, 'serious',
        'Dropbox backup coverage has been failing for over 48 hours (' || (v_cov->>'failing') || ')',
        v_cov,
        coalesce((select jsonb_agg(jsonb_build_object('handoff_id', id, 'status', status, 'doc_backup_id', detail->>'doc_backup_id'))
                    from agent_actions where kind = 'handoff' and detail->>'type' = 'backup.refile' and status <> 'done'), '[]'::jsonb),
        'Decide whether the missing documents need the founder''s Dropbox checked by hand or the filing corrected. The IT engineer has raised it and handed each missing file to the sales engineer to refile; this is past 48 hours, which is why it reaches you.',
        p_review_in => interval '1 day', p_source_agent => 'it_engineer');
    end if;
  end if;

  v_stale := (v_last < now() - interval '26 hours') or (coalesce(v_status,'') = 'error');
  if not v_stale then
    return jsonb_build_object('ok', v_cov_ok, 'last', v_last, 'status', v_status, 'watched', c_agents,
                              'coverage', v_cov, 'coverage_alerted', not v_cov_ok and v_cov_open = 0);
  end if;

  -- Twenty hours is strictly shorter than the daily cadence, so a daily check always re-alerts on a
  -- continuing outage while a ten-minute caller still cannot spam (13 Aug 2026).
  select count(*) into v_open from agent_actions
   where kind = 'backup_alert' and coalesce(status,'') in ('pending','needs_review')
     and created_at > now() - interval '20 hours';

  if v_open = 0 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values('it_engineer','backup_alert','pending','high',
      'Document backup to Dropbox has failed or is overdue',
      'The Dropbox document mirror has not completed successfully in the last 26 hours (last: '
      || coalesce(v_last::text,'never') || ', status: ' || coalesce(v_status,'unknown')
      || '). Check the dropbox_backup function and its logs. This concerns stored DOCUMENTS only — '
      || 'the managed Postgres backups are outside this database and are not covered by this check.',
      'agent_runs', jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    insert into security_events(kind, severity, source, subject, detail)
    values('backup_overdue','high','backup','dropbox document mirror',
      jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    -- An outage that lasts must get louder, not repeat itself: past 48 hours this also pages the
    -- founder (the one founder-mail kind this watcher is allowed) and states the age in hours.
    if v_last < now() - interval '48 hours' then
      perform public.fn_notify_founder(
        'Document backup failing after retry: no successful Dropbox mirror for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours',
        'The Dropbox document mirror has now been failing for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours (last run: '
        || v_last::text || ', status: ' || coalesce(v_status,'unknown')
        || '). This covers stored DOCUMENTS — supplier files, quotes, drawings. The managed Postgres '
        || 'backups are a separate system outside this database and this alert says nothing about '
        || 'them either way. Verify the dropbox_backup function.',
        'critical', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_failed_after_retry');
    end if;
  end if;

  return jsonb_build_object('alerted', true, 'last', v_last, 'status', v_status,
                            'existing_open', v_open, 'watched', c_agents, 'coverage', v_cov);
end
$function$;
revoke execute on function public.fn_backup_watch() from public, anon, authenticated;

-- ── 7. THE DAILY LINE TO THE CEO ──────────────────────────────────────────────────────────────
create or replace function public.fn_dropbox_backup_summary()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with f as (
    select
      count(*) filter (where created_at > now() - interval '24 hours')                         as queued_24h,
      count(*) filter (where backed_up_at > now() - interval '24 hours')                       as uploaded_24h,
      count(*) filter (where verified_at > now() - interval '24 hours')                        as verified_24h,
      count(*) filter (where status in ('pending','error') and coalesce(attempts,0) < 5)        as waiting,
      count(*) filter (where status = 'done')                                                  as uploaded_total,
      count(*) filter (where status = 'done' and verified_at is not null)                      as verified_total,
      count(*) filter (where status in ('error','skipped_large'))                              as failing_now,
      count(*) filter (where status = 'abandoned')                                             as abandoned,
      count(*)                                                                                 as total
    from public.doc_backups),
  r as (select coalesce(sum((counts->>'failed')::int), 0) as failed_24h from public.agent_runs
         where agent = 'dropbox_backup' and started_at > now() - interval '24 hours' and counts ? 'failed')
  select to_jsonb(f) || to_jsonb(r) || jsonb_build_object('line',
    'Dropbox backup, last 24h: ' || f.queued_24h || ' queued, ' || f.uploaded_24h || ' uploaded, '
    || f.verified_24h || ' verified, ' || r.failed_24h || ' failed. Totals: ' || f.uploaded_total || ' uploaded ('
    || f.verified_total || ' verified in Dropbox), ' || f.waiting || ' waiting, ' || f.failing_now || ' failing, '
    || f.abandoned || ' abandoned with a recorded reason, of ' || f.total || '.',
    'measured_at', now())
  from f, r;
$fn$;
revoke execute on function public.fn_dropbox_backup_summary() from public, anon, authenticated;

-- Filed once per Asia/Dubai day, at the first tick from 19:00 local (the CEO's digest is 20:00).
create or replace function public.fn_dropbox_backup_daily_report()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; s jsonb;
begin
  if v_local::time < time '19:00' then
    return jsonb_build_object('filed', false, 'reason', 'before 19:00 Asia/Dubai');
  end if;
  if exists (select 1 from public.support_ceo_report
              where idempotency_key = 'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD')) then
    return jsonb_build_object('filed', false, 'reason', 'already filed today');
  end if;
  s := public.fn_dropbox_backup_summary();
  return public.fn_support_report_to_ceo(
    'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD'),
    case when (s->>'failing_now')::int > 0 or (s->>'failed_24h')::int > 0 then 'elevated' else 'routine' end,
    'Dropbox backup ' || to_char(v_local, 'DD Mon') || ': ' || (s->>'line'),
    s, '[]'::jsonb,
    'Note the day''s backup position. NOTHING IS REQUESTED: this is the IT engineer''s daily line on the Dropbox backup. A failure past 48 hours reaches you separately, as a serious report.',
    p_review_in => interval '1 day', p_source_agent => 'it_engineer') || jsonb_build_object('filed', true);
end $fn$;
revoke execute on function public.fn_dropbox_backup_daily_report() from public, anon, authenticated;

-- ── 8. THE ONE CALL resilience_ping MAKES ─────────────────────────────────────────────────────
-- Each part is caught on its own so one failing cannot silence the others.
create or replace function public.fn_it_backup_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb;
begin
  begin o := o || jsonb_build_object('refiles', public.fn_it_backup_refile_close());
  exception when others then o := o || jsonb_build_object('refiles', jsonb_build_object('error', left(sqlerrm, 200))); end;
  begin o := o || jsonb_build_object('watch', public.fn_backup_watch());
  exception when others then o := o || jsonb_build_object('watch', jsonb_build_object('error', left(sqlerrm, 200))); end;
  begin o := o || jsonb_build_object('daily', public.fn_dropbox_backup_daily_report());
  exception when others then o := o || jsonb_build_object('daily', jsonb_build_object('error', left(sqlerrm, 200))); end;
  return o || jsonb_build_object('reconcile', public.fn_dropbox_reconcile_due());
end $fn$;
revoke execute on function public.fn_it_backup_tick() from public, anon, authenticated;

-- ── 9. PROBE: measured, never raised, never a real row ────────────────────────────────────────
-- The refile loop is exercised on a ZZ DEMO row inside a block that rolls itself back, so nothing
-- it writes (the row, the handoff, the event, the run) survives the probe.
do $probe$
declare cov jsonb; summ jsonb; due jsonb; v_fx bigint; v_ap jsonb; v_h bigint; v_st text; v_aw text; v_cl jsonb; v_hs text; v_ab int;
begin
  cov  := public.fn_backup_coverage();
  summ := public.fn_dropbox_backup_summary();
  due  := public.fn_dropbox_reconcile_due();
  select count(*) into v_ab from public.doc_backups where status = 'abandoned' and error like 'abandoned:%';
  raise notice 'coverage: %', cov::text;
  raise notice 'summary: %', summ->>'line';
  raise notice 'reconcile due: %; abandoned with a recorded reason: %', due::text, v_ab;
  begin
    insert into public.doc_backups (entity, entity_id, doc_type, dropbox_path, status, source, dedupe_key, bytes, backed_up_at)
    values ('zz_demo', 'ZZ DEMO', 'probe', '/QuotesDone Backup/_selftest/ZZ DEMO probe.txt', 'done', 'storage',
            'ZZDEMO:probe:' || txid_current(), 1, now())
    returning id into v_fx;
    v_ap := public.fn_dropbox_reconcile_apply(jsonb_build_array(jsonb_build_object('id', v_fx, 'outcome', 'missing')));
    v_h := (v_ap->'handoffs'->>0)::bigint;
    select d.status, a.detail->>'awaiting' into v_st, v_aw
      from public.doc_backups d, public.agent_actions a where d.id = v_fx and a.id = v_h;
    update public.doc_backups set status = 'done', verified_at = clock_timestamp() where id = v_fx;
    v_cl := public.fn_it_backup_refile_close();
    select status || '/' || coalesce(decided_by, '') into v_hs from public.agent_actions where id = v_h;
    raise exception using errcode = 'QDRBK', message = 'probe rollback';
  exception
    when sqlstate 'QDRBK' then
      raise notice 'refile loop on ZZ DEMO (rolled back): reconcile -> handoff % ; row after sales engineer = % (awaiting %) ; after verify, close = % , handoff = %',
        v_h, v_st, v_aw, v_cl::text, v_hs;
    when others then
      raise notice 'REFILE LOOP PROBE FAILED (rolled back, nothing kept): %', sqlerrm;
  end;
end $probe$;
