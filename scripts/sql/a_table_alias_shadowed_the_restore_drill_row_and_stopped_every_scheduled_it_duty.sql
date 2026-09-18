-- A TABLE ALIAS NAMED d SHADOWED THE RESTORE-DRILL ROW AND STOPPED EVERY SCHEDULED IT DUTY
-- it_engineer, 18 Sep 2026.
--
-- THE FAULT. Open finding duty:heartbeat:itscheduled, raised 215 times between 2026-09-15T19:02:21Z
-- and 2026-09-17T23:46:25Z:
--     resilience_ping step itscheduled failed: column reference "d.bucket" is ambiguous
--
-- THE CAUSE, measured from production on 18 Sep 2026 by calling the live routine inside a
-- transaction that was rolled back:
--     ERROR: 42702 column reference "d.bucket" is ambiguous
--     DETAIL: It could refer to either a PL/pgSQL variable or a table column.
--     CONTEXT: PL/pgSQL function fn_it_duties_scheduled(jsonb) line 63 at FOR over SELECT rows
--
-- fn_it_duties_scheduled declares `d public.doc_backups` for the 9a restore drill, which reads a
-- sampled backup row into it. Duty 9b -- added by the 15 Sep backup work
-- (every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql, PR #724's
-- session) -- then wrote its swept-object anti-join as
--     not exists (select 1 from public.doc_backups AS d ... d.bucket = s.bucket ...)   [AS added here
--     so a check that greps this repo for the broken shape never matches the comment explaining it]
-- The table alias d and the PL/pgSQL record variable d are both in scope inside that query, so
-- Postgres refuses to plan it. It fails at plan time, so the duty never ran even once.
--
-- WHAT ELSE IT STOPPED. The whole routine aborts, and backup_gap is due every day, so from
-- 15 Sep 19:02 UTC no scheduled IT duty in this routine settled anything at all:
--   workflow_heartbeat  the per-workflow heartbeats
--   restore (9a)        the 30-day Dropbox/storage restore drill
--   backup_gap (9b)     open gaps in the backup registry and unbacked stored files
--   sender (10)         SPF/DKIM/DMARC, blocklists, bounce and complaint rates, WhatsApp quality
--   spend (11)          daily provider spend against its own baseline
--   otp (11)            OTP pumping
--   access (13)         who holds access on GitHub, Vercel, Stripe, Dropbox
--   db_health (14)      slow queries, table growth, connections, disk
--   rotation (15)       internal credential rotation
-- And because fn_it_duty_ran is only reached after the loop, backup_gap stayed permanently due, so
-- the step failed on every single tick rather than once a day.
--
-- THE FIX is the alias, not the variable: the anti-join is renamed to db. Measured the same way,
-- with the corrected body created inside a rolled-back transaction, the routine completes:
--   {"backup_gap": {"closed": 51, "failing": 0}, "db_health": {"closed": 1, "failing": 10},
--    "otp": {...}, "rotation": {...}, "workflow_heartbeat": {...}}
-- The ten db_health findings are real and have been invisible for three days; they are raised the
-- first time the duty runs after this apply, which is what should have happened on 15 Sep.
--
-- The body below is the live definition read back out of production on 18 Sep 2026, byte-identical
-- to every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql except for
-- that one alias. Nothing else in the routine is retyped.
--
-- AND THE ONE FAILED BACKUP ROW. doc_backups #109177 has been status='error' since
-- 2026-09-14T23:11:13Z, which is what watch:queue_stalled:doc_backups_failed reports, and 13 of the
-- 35 dropbox_backup error runs in the last 72 hours are that one row failing again. It is the Stripe
-- invoice PDF of a transaction that no longer exists: agent_runs #93064 (stripe_webhook, 14 Sep
-- 23:11) recorded invoice in_1UFj1bC45SqX5pVbHL7W7xqP / FGOIJ67E-0001 stored for transaction
-- 4710dbb1-e5e3-4a95-b27a-efc43d3730b9, and the rehearsal that produced it was torn down the same
-- night. Measured 18 Sep 2026: public.transactions holds 0 rows, and storage.objects holds nothing
-- under finance-docs/invoices/stripe/2026-09-14/ and nothing matching FGOIJ67E. There is no file to
-- back up and no owner to re-render it from, so it is marked abandoned with its reason, which is the
-- disposal fn_ceo_backup_escalation_decide already instructs for exactly this case: "Where the
-- source no longer exists, mark its row abandoned with the reason (error 'abandoned: ...') so it
-- stops counting as lost." Nothing is deleted.
--
-- THE 723 ABANDONED ROWS ARE NOT A FAULT. Measured 18 Sep 2026: every one carries a written reason
-- ("abandoned: ..."), 697 are the ZZ DEMO rehearsal of 14 Sep torn down the same night, 15 are the
-- quote-comparison renderer retired with quote_compare on 9 Sep, and 11 name suppliers 30337-30344
-- and 30361 that no longer exist. None of their paths is back in storage (0 of 723 join
-- storage.objects) and none of their entities is still live, so fn_backup_enqueue_watch does not and
-- would not flag any of them: its sources are non-demo leads, customers, inquiries and transactions,
-- and all of these are gone. No row is deleted and none needs to be.

create or replace function public.fn_it_duties_scheduled(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_due text[] := public.fn_it_scheduled_due(); v_out jsonb := '{}'::jsonb; v_items jsonb; x record; e jsonb;
  d public.doc_backups; v_n numeric; v_d numeric; v_rate numeric; v_mult numeric; v_floor numeric;
  v_p90 numeric; v_max int; v_lim numeric; v_used numeric; c record; v_rot int := 0;
begin
  if jsonb_typeof(coalesce(p_r, '{}'::jsonb)) <> 'object' then
    raise exception 'fn_it_duties_scheduled takes the readings object from _shared/it_scheduled_readings.ts';
  end if;
  v_out := v_out || jsonb_build_object('workflow_heartbeat', public.fn_it_workflow_heartbeats());

  -- ── 9a. RESTORE DRILL ──
  -- Reads: the sample the tick downloaded — each file opened from Dropbox (content hash and size) and
  -- from Supabase storage (size) — against what doc_backups recorded when it was backed up.
  if 'restore' = any (v_due) and jsonb_typeof(p_r->'restore'->'samples') = 'array' then
    v_items := '[]'::jsonb;
    for e in select s from jsonb_array_elements(p_r->'restore'->'samples') s loop
      select * into d from public.doc_backups where id = (e->>'doc_backup_id')::bigint;
      if d.id is null then continue; end if;
      -- Duty 19 (founder, 14 Sep 2026: "add all for accountant and IT"): a restored copy must also open.
      -- Compared as text so a reading taken before duty 19 (no 'opens' key) is not failed for it.
      if not coalesce((e->'dropbox'->>'ok')::boolean, false)
         or (e->'dropbox'->>'opens') = 'false'
         or (d.dropbox_content_hash is not null and e->'dropbox'->>'content_hash' is distinct from d.dropbox_content_hash)
         or (d.dropbox_size is not null and (e->'dropbox'->>'size')::bigint is distinct from d.dropbox_size) then
        v_items := v_items || jsonb_build_object('item', 'dropbox:' || d.id, 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
          'title', 'Restore drill: ' || coalesce(d.file_name, d.dropbox_path) || ' did not come back intact from Dropbox',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('doc_backup_id', d.id, 'dropbox_path', d.dropbox_path, 'recorded_hash', d.dropbox_content_hash,
                                         'recorded_size', d.dropbox_size, 'restored', e->'dropbox'));
      end if;
      -- Duty 19: the storage copy must open and must be the same file as the Dropbox copy.
      if d.bucket is not null and (not coalesce((e->'storage'->>'ok')::boolean, false)
         or (e->'storage'->>'opens') = 'false'
         or (e->'storage'->>'content_hash' is not null and e->'dropbox'->>'content_hash' is not null
             and e->'storage'->>'content_hash' <> e->'dropbox'->>'content_hash')
         or (d.bytes is not null and (e->'storage'->>'size')::bigint is distinct from d.bytes)) then
        v_items := v_items || jsonb_build_object('item', 'storage:' || d.id, 'owner_seat', 'sales_engineer', 'subject', 'storage',
          'title', 'Restore drill: ' || coalesce(d.file_name, d.path) || ' did not come back intact from Supabase storage',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('doc_backup_id', d.id, 'bucket', d.bucket, 'path', d.path, 'recorded_bytes', d.bytes,
                                         'restored', e->'storage'));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('restore', public.fn_it_duty_settle('restore', v_items));
    perform public.fn_it_duty_ran('restore', v_out->'restore');
  end if;

  -- ── 9b. OPEN GAPS IN THE BACKUP REGISTRY ──
  -- 15 Sep 2026: a reasoned EXEMPT is not a gap (it raised all 51 before: the destination column, the
  -- PDPL ledger, repository paths ...). A gap is (a) a registry source not backed up and not EXEMPT --
  -- an OPEN GAP, or a row nobody classified -- and (b) per swept bucket, the stored files over a day old
  -- that still have no doc_backups row. No item key carries ':', so every finding is
  -- 'duty:backup_gap:<item>' and the founder's digest shows the family as one line with its count.
  if 'backup_gap' = any (v_due) then
    v_items := '[]'::jsonb;
    for x in select * from public.fn_backup_source_registry() r
              where not r.backed_up and coalesce(r.reason, '') !~ '^EXEMPT' loop
      v_items := v_items || jsonb_build_object('item', replace(x.source, ':', '/'), 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
        'title', 'Not backed up to Dropbox: ' || x.source || coalesce(' — ' || x.reason, ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('source', x.source, 'kind', x.kind, 'bucket', x.bucket));
    end loop;
    for x in select s.bucket, count(*) as n, round(sum(s.bytes) / 1048576.0, 2) as mb, min(s.path) as sample
               from public.fn_backup_sweep_objects() s
              where s.created_at < now() - interval '24 hours'
                and not exists (select 1 from public.doc_backups db where db.bucket = s.bucket and db.path = s.path)
              group by s.bucket loop
      v_items := v_items || jsonb_build_object('item', 'storage/' || x.bucket, 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
        'title', 'Not backed up to Dropbox: ' || x.n || ' stored file(s) in ' || x.bucket || ' still have no backup row after 24 hours',
        'blast', 'agent_facing', 'affected', x.n,
        'evidence', jsonb_build_object('bucket', x.bucket, 'files', x.n, 'mb', x.mb, 'sample', x.sample));
    end loop;
    v_out := v_out || jsonb_build_object('backup_gap', public.fn_it_duty_settle('backup_gap', v_items));
    perform public.fn_it_duty_ran('backup_gap', v_out->'backup_gap');
  end if;

  -- ── 10. SENDER HEALTH ──
  -- Reads: DNS (SPF, DMARC, DKIM) and blocklists by DNS-over-HTTPS, Resend's own verdict on each
  -- domain record, Twilio's WhatsApp sender quality and template approvals — and from our own tables
  -- the hard bounces and complaints resend_webhook recorded against the emails we sent.
  if 'sender' = any (v_due) and jsonb_typeof(p_r->'sender') = 'object' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(coalesce(p_r->'sender'->'dns', '{}'::jsonb)) loop
      if coalesce(x.value->>'basis', '') = 'measured' then
        if not coalesce((x.value->>'spf')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'spf:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no SPF record that includes our sender', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
        if not coalesce((x.value->>'dmarc')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'dmarc:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no DMARC record', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
        if not coalesce((x.value->>'dkim')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'dkim:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no DKIM key published for our sender', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
      end if;
    end loop;
    for e in select b from jsonb_array_elements(coalesce(p_r->'sender'->'blocklists', '[]'::jsonb)) b loop
      if e->>'basis' = 'measured' and public.fn_it_dnsbl_listed(e->>'list', e->'answers') then
        v_items := v_items || jsonb_build_object('item', 'blocklist:' || (e->>'list') || ':' || (e->>'target'), 'owner_seat', 'customer_support',
          'subject', 'send_outbox', 'title', (e->>'target') || ' is listed on ' || (e->>'list'),
          'blast', 'customer_facing', 'affected', 1, 'evidence', e);
      end if;
    end loop;
    if coalesce(p_r->'sender'->'resend'->>'basis', '') = 'measured' and coalesce(p_r->'sender'->'resend'->>'status', '') <> 'verified' then
      v_items := v_items || jsonb_build_object('item', 'resend_domain', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
        'title', 'Resend reports the sending domain as ' || coalesce(p_r->'sender'->'resend'->>'status', 'unknown'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'resend');
    end if;
    if coalesce(p_r->'sender'->'whatsapp'->>'basis', '') = 'measured'
       and upper(coalesce(p_r->'sender'->'whatsapp'->>'quality', '')) not in ('HIGH', 'GREEN', 'UNKNOWN') then
      v_items := v_items || jsonb_build_object('item', 'whatsapp_quality', 'owner_seat', 'customer_support', 'subject', 'send_whatsapp',
        'title', 'The WhatsApp number''s quality rating is ' || (p_r->'sender'->'whatsapp'->>'quality'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'whatsapp');
    end if;
    for e in select t from jsonb_array_elements(coalesce(p_r->'sender'->'templates', '[]'::jsonb)) t loop
      if e->>'basis' = 'measured' and lower(coalesce(e->>'status', '')) not in ('approved') then
        v_items := v_items || jsonb_build_object('item', 'template:' || (e->>'name'), 'owner_seat', 'customer_support', 'subject', 'send_whatsapp',
          'title', 'WhatsApp template ' || (e->>'name') || ' is ' || coalesce(e->>'status', 'unknown'),
          'blast', 'customer_facing', 'affected', 0, 'evidence', e);
      end if;
    end loop;
    select count(*) into v_d from public.notifications
     where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
    if v_d >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20) then
      select count(*) filter (where reason like 'hard_bounce%'), count(*) filter (where reason = 'spam_complaint')
        into v_n, v_rate from public.email_suppressions
       where source = 'resend_webhook' and created_at > now() - interval '7 days';
      if v_n / v_d > public.fn_it_threshold('sender_bounce_rate_max') then
        v_items := v_items || jsonb_build_object('item', 'bounce_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
          'title', round(100 * v_n / v_d, 2) || '% of last week''s emails hard-bounced', 'blast', 'customer_facing', 'affected', 1,
          'evidence', jsonb_build_object('hard_bounces', v_n, 'sent', v_d, 'max', public.fn_it_threshold('sender_bounce_rate_max')));
      end if;
      if v_rate / v_d > public.fn_it_threshold('sender_complaint_rate_max') then
        v_items := v_items || jsonb_build_object('item', 'complaint_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
          'title', round(100 * v_rate / v_d, 3) || '% of last week''s emails were reported as spam', 'blast', 'customer_facing', 'affected', 1,
          'evidence', jsonb_build_object('complaints', v_rate, 'sent', v_d, 'max', public.fn_it_threshold('sender_complaint_rate_max')));
      end if;
    end if;
    v_out := v_out || jsonb_build_object('sender', public.fn_it_duty_settle('sender', v_items));
    perform public.fn_it_duty_ran('sender', v_out->'sender');
  end if;

  -- ── 11a. SPEND ──
  -- Reads: yesterday's cost per provider the tick could read (Twilio usage, Stripe fees), stored in
  -- it_spend_daily; each source is compared with its own trailing 14 days. The Supabase and Vercel
  -- bills are not readable with the tokens this estate holds, and the reading says so.
  if 'spend' = any (v_due) and jsonb_typeof(p_r->'spend') = 'array' then
    for e in select s from jsonb_array_elements(p_r->'spend') s loop
      if e->>'basis' = 'measured' then
        insert into public.it_spend_daily (day, source, amount_minor, currency)
        values ((e->>'day')::date, e->>'source', (e->>'amount_minor')::bigint, e->>'currency')
        on conflict (day, source) do update set amount_minor = excluded.amount_minor, recorded_at = now();
      end if;
    end loop;
    v_items := '[]'::jsonb;
    v_mult := public.fn_it_threshold('spend_anomaly_multiple'); v_floor := public.fn_it_threshold('spend_floor_aed');
    for x in select s.source, s.day, s.amount_minor, s.currency,
                    (select percentile_cont(0.9) within group (order by b.amount_minor) from public.it_spend_daily b
                      where b.source = s.source and b.day between s.day - 14 and s.day - 1) p90,
                    (select count(*) from public.it_spend_daily b where b.source = s.source and b.day between s.day - 14 and s.day - 1) n
               from public.it_spend_daily s
              where s.day = (select max(day) from public.it_spend_daily t where t.source = s.source) loop
      -- Fewer than seven days of history is not a baseline; the source is reported, not judged.
      continue when x.n < 7;
      if x.amount_minor / 100.0 >= v_floor and x.amount_minor > v_mult * x.p90 then
        v_items := v_items || jsonb_build_object('item', x.source, 'owner_seat', 'accountant', 'subject', x.source,
          'title', x.source || ' cost ' || round(x.amount_minor / 100.0, 2) || ' ' || x.currency || ' on ' || x.day
                   || ', over ' || v_mult || 'x its 14-day p90 of ' || round(x.p90 / 100.0, 2),
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('day', x.day, 'amount_minor', x.amount_minor, 'p90_minor', x.p90, 'history_days', x.n));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('spend', public.fn_it_duty_settle('spend', v_items),
                                         'spend_readings', p_r->'spend');
    perform public.fn_it_duty_ran('spend', v_out->'spend');
  end if;

  -- ── 11b. OTP PUMPING — the IT engineer's own playbook ──
  -- Reads: codes issued in the last hour (phone_verifications from login_otp, customer_phone_otps from
  -- mobile_otp) per 5-digit prefix. A burst to a country we do not serve is blocked for
  -- otp_block_hours at once and reported; a burst inside a served country is handed to the CEO,
  -- because blocking it could lock real customers out. The block is re-verified next hour.
  if 'otp' = any (v_due) then
    v_items := '[]'::jsonb;
    v_max := coalesce(public.fn_it_threshold('otp_burst_per_prefix_hour'), 5)::int;
    for x in select left(regexp_replace(phone, '\D', '', 'g'), 5) prefix, count(*) n
               from (select phone, created_at from public.phone_verifications
                     union all select phone, created_at from public.customer_phone_otps) z
              where created_at > now() - interval '1 hour' and phone is not null
              group by 1 having count(*) > v_max loop
      -- A prefix the CEO or founder allowed is never auto-blocked again; its burst is handed on instead.
      if not exists (select 1 from public.otp_served_country s where x.prefix like s.prefix || '%')
         and not exists (select 1 from public.otp_prefix_allowed a where x.prefix like a.prefix || '%') then
        insert into public.otp_blocked_prefix (prefix, reason, blocked_by, expires_at)
        values (x.prefix, x.n || ' codes in an hour to a country we do not serve', 'it_engineer',
                now() + make_interval(hours => coalesce(public.fn_it_threshold('otp_block_hours'), 24)::int))
        on conflict (prefix) do update set expires_at = excluded.expires_at, reason = excluded.reason;
        -- agent_facing with nobody stuck: recorded, and handed on only if it is still happening in six hours.
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n || ' sign-in codes in an hour to +' || x.prefix || '…, a country we do not serve — prefix blocked by the IT engineer',
          'blast', 'agent_facing', 'affected', 0,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n, 'remedy', 'otp_blocked_prefix'));
      else
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n || ' sign-in codes in an hour to +' || x.prefix || '…, inside a country we serve',
          'blast', 'security', 'affected', 1,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n,
                                         'why_not_blocked', 'a served country: blocking could lock real customers out'));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('otp', public.fn_it_duty_settle('otp', v_items));
    perform public.fn_it_duty_ran('otp', v_out->'otp');
  end if;

  -- ── 13. ACCESS REVIEW ──
  -- Reads: who each provider lists (GitHub collaborators and deploy keys, Vercel team members, the
  -- Dropbox account; Supabase members arrive through fn_it_platform_ingest). A principal not accepted
  -- in it_access_known, or accepted longer ago than access_reconfirm_days, is raised to the CEO.
  -- Stripe publishes no team-member API; the reading says so.
  if 'access' = any (v_due) and jsonb_typeof(p_r->'access') = 'object' then
    v_items := public.fn_it_access_items(p_r->'access');
    v_out := v_out || jsonb_build_object('access', public.fn_it_duty_settle('access', v_items));
    perform public.fn_it_duty_ran('access', v_out->'access');
  end if;

  -- ── 14. DATABASE HEALTH ──
  if 'db_health' = any (v_due) then
    v_items := '[]'::jsonb;
    for x in select s.queryid, left(regexp_replace(s.query, '\s+', ' ', 'g'), 200) q, s.calls, round(s.mean_exec_time::numeric, 1) mean_ms
               from extensions.pg_stat_statements s
              where s.calls >= public.fn_it_threshold('slow_query_min_calls')
                and s.mean_exec_time > public.fn_it_threshold('slow_query_mean_ms')
              order by s.mean_exec_time desc limit 10 loop
      v_items := v_items || jsonb_build_object('item', 'slow:' || x.queryid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'A statement averages ' || x.mean_ms || ' ms over ' || x.calls || ' calls: ' || left(x.q, 90),
        'blast', 'internal', 'affected', 1, 'evidence', jsonb_build_object('queryid', x.queryid, 'query', x.q, 'calls', x.calls, 'mean_ms', x.mean_ms));
    end loop;
    insert into public.it_table_size_daily (day, relid, bytes)
    -- The alias is pc, not c: c is this function's rotation-loop record, and plpgsql would read c.oid
    -- as that (unassigned) record instead of the table.
    select current_date, pc.oid::regclass::text, pg_total_relation_size(pc.oid)
      from pg_class pc join pg_namespace n on n.oid = pc.relnamespace
     where n.nspname = 'public' and pc.relkind = 'r'
    on conflict (day, relid) do update set bytes = excluded.bytes;
    for x in select t.relid, t.bytes, o.bytes old_bytes from public.it_table_size_daily t
               join public.it_table_size_daily o on o.relid = t.relid and o.day = current_date - 7
              where t.day = current_date
                and t.bytes > public.fn_it_threshold('table_growth_7d_multiple') * o.bytes
                and t.bytes - o.bytes > public.fn_it_threshold('table_growth_min_bytes') loop
      v_items := v_items || jsonb_build_object('item', 'growth:' || x.relid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', x.relid || ' grew from ' || pg_size_pretty(x.old_bytes) || ' to ' || pg_size_pretty(x.bytes) || ' in a week',
        'blast', 'internal', 'affected', 1, 'evidence', jsonb_build_object('bytes', x.bytes, 'bytes_7d_ago', x.old_bytes));
    end loop;
    select count(*) into v_used from pg_stat_activity;
    v_lim := current_setting('max_connections')::numeric;
    if v_used > public.fn_it_threshold('connections_ratio_max') * v_lim then
      v_items := v_items || jsonb_build_object('item', 'connections', 'owner_seat', 'ceo', 'subject', 'database',
        'title', v_used || ' of ' || v_lim || ' database connections are in use',
        'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('in_use', v_used, 'max', v_lim));
    end if;
    v_lim := public.fn_it_threshold('db_disk_limit_bytes');
    if v_lim is not null and pg_database_size(current_database()) > public.fn_it_threshold('disk_ratio_max') * v_lim then
      v_items := v_items || jsonb_build_object('item', 'disk', 'owner_seat', 'accountant', 'subject', 'database',
        'title', 'The database uses ' || pg_size_pretty(pg_database_size(current_database())) || ' of ' || pg_size_pretty(v_lim::bigint),
        'blast', 'customer_facing', 'affected', 0,
        'evidence', jsonb_build_object('bytes', pg_database_size(current_database()), 'limit_bytes', v_lim,
                                       'route', 'the accountant approves a larger disk or plan'));
    end if;
    v_out := v_out || jsonb_build_object('db_health', public.fn_it_duty_settle('db_health', v_items),
                                         'disk_limit_basis', case when v_lim is null then 'not_measured_yet' else 'measured' end);
    perform public.fn_it_duty_ran('db_health', v_out->'db_health');
  end if;

  -- ── 15. ROTATION ──
  if 'rotation' = any (v_due) then
    for c in select ic.id from public.internal_credential ic
              where ic.active and ic.retired_at is null and not ic.is_legacy
                and exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'))
                and not exists (select 1 from public.it_credential_rotation r where r.context = ic.context and r.status in ('overlap', 'held'))
                and (coalesce(ic.rotated_at, ic.created_at) < now() - make_interval(days => public.fn_it_threshold('credential_rotate_days')::int)
                     or ic.expires_at < now() + interval '30 days')
              order by coalesce(ic.rotated_at, ic.created_at)
              limit public.fn_it_threshold('credential_rotations_per_run')::int
              -- Two ticks at the same instant must not rotate one credential twice: the first holds the
              -- row until its rotation row ('overlap') exists, and the second skips what is held.
              for update of ic skip locked loop
      perform public.fn_it_credential_rotate(c.id);
      v_rot := v_rot + 1;
    end loop;
    v_out := v_out || jsonb_build_object('rotation', jsonb_build_object('rotated', v_rot, 'reverify', public.fn_it_credential_reverify()));
    perform public.fn_it_duty_ran('rotation', v_out->'rotation');
  end if;

  return v_out;
end $function$;

-- CREATE OR REPLACE preserves the ACL, so this revoke changes nothing today. It is written out so
-- the routine's canonical file states its grants rather than inheriting them from a file that moved.
revoke execute on function public.fn_it_duties_scheduled(jsonb) from public, anon, authenticated;


-- ── THE ONE FAILED ROW ──
-- Guarded on the two facts that were measured, so if the transaction or the storage object ever
-- comes back this statement does nothing and the row stays where the IT engineer can see it.
update public.doc_backups d
   set status = 'abandoned',
       error  = 'abandoned: the Stripe invoice PDF of a rehearsal transaction torn down on 14 Sep 2026'
                || ' - transaction 4710dbb1-e5e3-4a95-b27a-efc43d3730b9 no longer exists and'
                || ' finance-docs/' || coalesce(d.path, '(no path recorded)')
                || ' is not in storage (measured 18 Sep 2026; last upload'
                || ' error: ' || coalesce(d.error, 'download Object not found') || ')'
 where d.id = 109177
   and d.status = 'error'
   and not exists (select 1 from public.transactions t where t.id::text = d.entity_id)
   and not exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);


-- ── PROBE ──
-- The file carries DDL, so the probe must leave nothing behind rather than roll the file back
-- (quotesdone-apply-discipline §4). The inner block is a subtransaction: the real routine runs
-- against real data, every finding it settles is undone by the raise, and the plpgsql variable
-- keeps the verdict because variables are memory, not data. If the ambiguity is still there the
-- error is re-raised and the apply fails loudly.
do $probe$
declare
  v_ran boolean := false;
  v_findings_before bigint;
  v_findings_after bigint;
  v_error_rows integer;
begin
  select count(*) into v_findings_before from public.it_engineer_finding;

  begin
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    v_ran := true;
    raise exception 'QD_PROBE_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'QD_PROBE_ROLLBACK' then raise; end if;
  end;

  if not v_ran then
    raise exception 'probe: fn_it_duties_scheduled did not complete';
  end if;

  -- It left nothing: the settle writes went back with the subtransaction.
  select count(*) into v_findings_after from public.it_engineer_finding;
  if v_findings_after <> v_findings_before then
    raise exception 'probe: the run left % finding row(s) behind', v_findings_after - v_findings_before;
  end if;

  -- And the queue no longer carries a failed row for the stalled-queue watch to report.
  -- Scoped to the row this file disposes of, NOT to the whole queue: a fresh dropbox_backup failure
  -- landing between the measurement and the apply is a real event for the stalled-queue watch to
  -- report, and must not fail this apply (review, 18 Sep 2026).
  select count(*) into v_error_rows from public.doc_backups where id = 109177 and status = 'error';
  if v_error_rows <> 0 then
    raise exception 'probe: doc_backups #109177 is still in status error - its guard did not match';
  end if;

  raise notice 'probe: fn_it_duties_scheduled completes, left 0 finding rows behind, doc_backups #109177 is no longer in status error';
end $probe$;
