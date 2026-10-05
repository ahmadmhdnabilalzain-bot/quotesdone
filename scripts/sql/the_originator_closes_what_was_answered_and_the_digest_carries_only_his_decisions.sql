-- THE ORIGINATOR CLOSES WHAT WAS ANSWERED, AND THE IT DIGEST CARRIES ONLY HIS DECISIONS.
-- Seats: ceo (originator closes, digest content) and it_engineer (SLA and growth duties). 4 October 2026.
--
-- ══ WHAT THE FOUNDER SAW ═════════════════════════════════════════════════════════════════════════
-- Daily IT digests of 17, 20, 7, 4 and 7 "faults" (30 Sep - 4 Oct). On 4 Oct: unclosed ceo.month_directive
-- handoffs to five seats, unclosed deliberation.review handoffs to the accountant, and knowledge_vector_ml
-- growing 24 MB -> 164 MB in a week. Each fault line said "the engineers are making the code or
-- configuration change" whether or not anybody was. None of it was his to decide.
--
-- ══ WHAT WAS MEASURED (production, 4 Oct 2026 19:48 UTC) ═════════════════════════════════════════
-- (a) The brief said the seats answered and the CEO never closed. Re-measured, neither class is an
--     answered-but-unclosed handoff:
--     * the 5 ceo.month_directive (#126710-126714): each seat ACCEPTED; the contract (seat_handoff_kind
--       meaning, detail.due_at = 31 Oct 20:00 UTC) is "the CEO closes it at month end, met or missed", and
--       fn_ceo_month_plan section 1 does that deterministically when November starts. The SLA duty
--       (fn_it_handoff_sla_items) ignored due_at and called them late at created_at + 1 day + 24 h.
--     * the deliberation.review to the accountant (#120992, 126472, 126963, 127332, 127700, all from ceo):
--       evidence.step.action = 'held', "20 of 20 routes are held open-circuit" - the accountant's review
--       has NOT run; it waits on the model hold (the founder's standing OpenRouter limit, reported to him
--       by the review_independence duty). replied_at is set by fn_seat_handoff_act whenever the handler
--       returns, so the duty read "held" as "answered". The same is true of all 14 deliberation.review
--       handoffs to the CEO (13 from sales_engineer, 1 from marketing).
--     Closing any of them would be fabricating an outcome. The fault was the detector: it now times a
--     handoff by its contract's due_at and never calls a held review step "unclosed". Its findings
--     (duty:handoff_sla:ceo.month_directive:*:unclosed, duty:handoff_sla:deliberation.review:*:unclosed)
--     close on the next IT tick through fn_it_duty_settle, the routine that opened them.
--     Separately, fn_originators_reverify_handoffs had a closer for only two money conversations; every
--     other originator_closes kind had NONE. Section 4 below is that closer for every kind: verify the
--     reply, close it, or send it back with the reason (ruling 1059). Measured population it would close
--     today: 0 (every pending answered handoff is waiting, held, not due, or already in sections 1-2).
-- (b) knowledge_vector_ml: 42,519 of 148,326 kb_chunks embedded; ~8,500 rows a day land between 08:00 and
--     10:00 UTC, exactly when the scheduled ml-embed-backfill workflow ran (successful runs 29 Sep - 4 Oct
--     08:35-09:26 UTC). It is the #1115 backfill, not a leak. The growth duty now skips a table in
--     public.it_expected_table_growth until that row's end date, and the finding is closed with that cause.
-- (c) The digest now emails only items whose finding matches an it_founder_decision_class row with
--     to_founder = true. Every other item is completed 'internal' and stays an OS finding. With no
--     decision there is no email (founder_alerts channel 'os' only, as before). The false sentence is gone:
--     no line claims a fix is under way, so no line needs a PR to back it.
--
-- prevented by: scripts/checks/the_originator_closes_and_the_digest_carries_only_his_decisions.test.mjs
--
--   node scripts/apply_sql.mjs scripts/sql/the_originator_closes_what_was_answered_and_the_digest_carries_only_his_decisions.sql --apply --ddl

create table if not exists public.it_expected_table_growth (
  relid text primary key,
  cause text not null,
  writer text not null,
  until date not null,
  recorded_at timestamptz not null default now()
);
alter table public.it_expected_table_growth enable row level security;
drop policy if exists it_expected_table_growth_service_role_only on public.it_expected_table_growth;
create policy it_expected_table_growth_service_role_only on public.it_expected_table_growth
  as permissive for all to public using (false) with check (false);
revoke all on public.it_expected_table_growth from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('it_expected_table_growth', true, 'measurement', 'Growth the IT seat expects of a table (cause, writer, end date), so the growth watch closes it with its cause instead of paging.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

insert into public.it_expected_table_growth (relid, cause, writer, until)
values ('knowledge_vector_ml',
        'the multilingual embedding backfill (#1115): 105,807 of 148,326 kb_chunks still to embed on 4 Oct 2026 at ~8,500 a day',
        '.github/workflows/ml-embed-backfill.yml (scripts/kb/run_ml_embed_backfill.mjs, capped by fn_ml_embed_claim)',
        date '2026-10-31')
on conflict (relid) do update set cause = excluded.cause, writer = excluded.writer, until = excluded.until;

update public.founder_mail_policy
   set reason = 'Founder rulings 642 (22 Sep 2026) and 4 Oct 2026: ONE IT email a day at 19:00 Dubai, carrying ONLY decisions '
             || 'only he can make (it_founder_decision_class.to_founder). Faults stay with the seats on the OS. No decision, no email.',
       updated_at = now()
 where kind = 'it_daily_digest';

CREATE OR REPLACE FUNCTION public.fn_it_duties_scheduled(p_r jsonb)
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
      v_items := v_items || public.fn_it_sender_rate_items(v_d, v_n, v_rate);
    end if;
    -- DMARC aggregate reports (rua) read by _shared/it_scheduled_readings.ts dmarcReports(). An
    -- 'unavailable' reading (no report arrived) raises nothing: an absence is not a clean bill.
    if coalesce(p_r->'sender'->'dmarc_reports'->>'basis', '') = 'measured'
       and coalesce((p_r->'sender'->'dmarc_reports'->>'messages')::numeric, 0) > 0
       and (p_r->'sender'->'dmarc_reports'->>'failed')::numeric / (p_r->'sender'->'dmarc_reports'->>'messages')::numeric
           > public.fn_it_threshold('sender_dmarc_fail_rate_max') then
      v_items := v_items || jsonb_build_object('item', 'dmarc_fail_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
        'title', round(100 * (p_r->'sender'->'dmarc_reports'->>'failed')::numeric / (p_r->'sender'->'dmarc_reports'->>'messages')::numeric, 2)
                 || '% of the mail receivers saw from our domain failed DMARC',
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'dmarc_reports');
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
    -- n_dead: codes that were never used and have already expired. Pumping sends codes nobody enters;
    -- a registration day sends codes people enter within minutes (registration-day surge review,
    -- 21 Sep 2026). A code still inside its 10 minutes is neither, so it is not counted as dead.
    for x in select left(regexp_replace(phone, '\D', '', 'g'), 5) prefix, count(*) n,
                    count(*) filter (where not used and expires_at < now()) n_dead
               from (select phone, created_at, used_at is not null used, expires_at from public.phone_verifications
                     union all select phone, created_at, coalesce(consumed, false), expires_at from public.customer_phone_otps) z
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
      -- INSIDE A SERVED COUNTRY, VOLUME IS NOT THE SIGNAL. The UAE has a handful of mobile prefixes
      -- (+97150, +97152, +97154, +97155, +97156, +97158), so six suppliers verifying on +97150 in one
      -- hour crossed the 5-code line and raised a 'security' finding to the CEO for the system working —
      -- on a campaign day, one per prefix every tick. Raised now only when more than v_max of the codes
      -- died unused AND they are at least half of what was sent: the shape of pumping, not of sign-ups.
      elsif x.n_dead > v_max and x.n_dead * 2 >= x.n then
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n_dead || ' of ' || x.n || ' sign-in codes in an hour to +' || x.prefix || '… were never used, inside a country we serve',
          'blast', 'security', 'affected', 1,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n, 'codes_never_used', x.n_dead,
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
    -- THE SLOW STATEMENTS OF THE LAST INTERVAL, NOT OF THE DATABASE'S WHOLE LIFE.
    -- pg_stat_statements counters are cumulative since stats_reset and never decay, so
    -- s.mean_exec_time is a lifetime average: a statement that was slow in August and has not run
    -- since keeps the same mean for ever and is re-raised on every run. The interval is measured
    -- against public.it_query_stat_snapshot, written at the end of this block.
    --   INNER join, not left. A statement with no snapshot row has no interval -- it is not a
    --   statement that ran for a long time, it is a statement nobody has measured yet. Reading a
    --   missing baseline as zero would make its whole lifetime the first interval, which is exactly
    --   the lifetime rule this block replaces, and it would come back every time
    --   pg_stat_statements is reset or an entry is evicted and re-created. The upsert below gives it
    --   a baseline in this same run, so it is judged on the next one, one interval later.
    --   The two <= clauses keep counters that went BACKWARDS from producing a negative interval:
    --   a re-created entry can pass calls and still be behind on total_exec_time, or the reverse.
    --   Neither can be true of the same statement continuing, so both must hold or there is no
    --   comparable baseline and the row waits a run.
    -- The view is keyed on (userid, dbid, toplevel, queryid), so it is summed per queryid first --
    -- one statement's cost is what it cost, whoever ran it -- and min(query) picks one of the
    -- identical texts those rows share. That text can be NULL (pg_stat_statements can lose the text
    -- file, and a role that may not read it gets null), and a null title makes fn_it_duty_settle
    -- raise, which would abort every duty after this one: hence the coalesce.
    for x in with s as (
               select ss.queryid, sum(ss.calls) calls, sum(ss.total_exec_time) total_exec_time,
                      coalesce(min(left(regexp_replace(ss.query, '\s+', ' ', 'g'), 200)),
                               '(query text unavailable)') q,
                      -- An operator's session, not the product (21 Sep 2026): the management API
                      -- stamps every statement it runs with its own route in a trailing comment.
                      bool_and(coalesce(ss.query, '') like '%/v1/projects/:ref/database/query%') operator_session,
                      -- A schema change, not the product (24 Sep 2026): the stamp above is a
                      -- TRAILING comment, so in an applied multi-statement file only the last
                      -- statement carries it. A statement whose first word after its leading
                      -- comments is a DDL verb is an apply or a CI dry run, never product traffic.
                      bool_and(regexp_replace(coalesce(ss.query, ''), '^(\s*--[^\n]*)*\s*', '')
                               ~* '^(create|alter|drop|grant|revoke|comment)\s') schema_change
                 from extensions.pg_stat_statements ss
                where ss.queryid is not null
                group by ss.queryid)
             select s.queryid, s.q,
                    (s.calls - p.calls) d_calls,
                    round(((s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0))::numeric, 1) d_mean_ms,
                    round((s.total_exec_time - p.total_exec_time)::numeric / 1000, 1) d_total_s,
                    p.taken_at since
               from s
               join public.it_query_stat_snapshot p
                 on p.queryid = s.queryid and p.calls <= s.calls and p.total_exec_time <= s.total_exec_time
              where not s.operator_session and not s.schema_change
                and (s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0)
                    > public.fn_it_threshold('slow_query_mean_ms')
                -- Either the interval carried the call volume the threshold asks for, OR the
                -- statement burned that much time whatever its volume. Without the second arm a
                -- nightly export taking 60 s once could never be raised at all: the old rule could
                -- reach 50 calls across four months, one interval cannot. min_calls * mean_ms is
                -- not a new knob -- it is the time the first arm already has to accumulate before
                -- it fires (50 x 500 ms = 25 s), stated for the case where one call does it alone.
                and (s.calls - p.calls >= public.fn_it_threshold('slow_query_min_calls')
                     or s.total_exec_time - p.total_exec_time
                        > public.fn_it_threshold('slow_query_min_calls') * public.fn_it_threshold('slow_query_mean_ms'))
              order by 5 desc limit 10 loop
      v_items := v_items || jsonb_build_object('item', 'slow:' || x.queryid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'A statement averaged ' || x.d_mean_ms || ' ms over ' || x.d_calls || ' calls since the last check ('
                 || x.d_total_s || ' s in total): ' || left(x.q, 90),
        'blast', 'internal', 'affected', 1,
        'evidence', jsonb_build_object('queryid', x.queryid, 'query', x.q, 'calls', x.d_calls, 'mean_ms', x.d_mean_ms,
                                       'interval_total_s', x.d_total_s, 'interval_started_at', x.since,
                                       'interval_minutes', round((extract(epoch from (now() - x.since)) / 60)::numeric, 1),
                                       'basis', 'measured over the interval between this run and the previous db_health run, from public.it_query_stat_snapshot'));
    end loop;
    -- The reading this run measured against the next one. Every statement is recorded, not only the
    -- slow ones, or a statement that is fast today and slow tomorrow would have no baseline.
    -- The where clause keeps the snapshot MONOTONIC: two db_health runs overlapping would otherwise
    -- let the one that READ first COMMIT last and write its older reading over the newer, and the
    -- next interval would then re-count work already measured.
    insert into public.it_query_stat_snapshot (queryid, calls, total_exec_time, taken_at)
    select ss.queryid, sum(ss.calls), sum(ss.total_exec_time), now()
      from extensions.pg_stat_statements ss
     where ss.queryid is not null
     group by ss.queryid
      on conflict (queryid) do update
         set calls = excluded.calls, total_exec_time = excluded.total_exec_time, taken_at = excluded.taken_at
       where excluded.calls >= public.it_query_stat_snapshot.calls;
    -- A queryid pg_stat_statements has evicted will never return; keeping its row would make the
    -- table grow for ever and would give a re-created entry a stale baseline.
    delete from public.it_query_stat_snapshot p
     where not exists (select 1 from extensions.pg_stat_statements ss where ss.queryid = p.queryid);
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
                and t.bytes - o.bytes > public.fn_it_threshold('table_growth_min_bytes')
                -- A registered backfill is growth the company chose, not a fault: it is skipped until its
                -- end date. Past that date the same growth is raised again, so a backfill cannot hide a leak.
                and not exists (select 1 from public.it_expected_table_growth g
                                 where g.relid = t.relid and current_date <= g.until) loop
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
    -- Published every run, so the exclusion is a number on the record and never a silent gap.
    select count(*) into v_n from (
      select ss.queryid from extensions.pg_stat_statements ss where ss.queryid is not null
       group by ss.queryid having bool_and(coalesce(ss.query, '') like '%/v1/projects/:ref/database/query%')) z;
    v_out := v_out || jsonb_build_object('db_health_operator_statements_excluded', v_n);
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


CREATE OR REPLACE FUNCTION public.fn_it_handoff_sla_items(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with h as (
    select a.id, a.agent, a.created_at, a.detail->>'type' t, a.detail ? 'replied_at' replied,
           coalesce(k.reply_within, interval '1 hour') w,
           -- The contract's own clock: a month directive is closed by the CEO at its due_at (month end),
           -- so it is late only after that, never two days after it was sent.
           coalesce((a.detail->>'due_at')::timestamptz, a.created_at) due,
           -- A review step held by the model hold has not been answered; it waits on the hold, which is
           -- the founder's standing OpenRouter limit and is reported by the review_independence duty.
           coalesce(a.evidence#>>'{step,action}', '') = 'held' held,
           f.closed_at f_closed,
           (f.issue_key is null or f.closed_at is not null
            or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz) cleared
      from public.agent_actions a
      left join public.seat_handoff_kind k
        on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
      left join public.it_engineer_finding f
        on a.detail->>'type' = 'it.finding' and f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.status in ('pending', 'failed')
       and a.detail->>'type' <> 'delivery.request'
       and (p_include_demo or (a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true'))
  ), late as (
    select h.*, case
        when not h.replied and now() > h.created_at + h.w then 'unanswered'
        when h.replied and h.t = 'it.finding' and h.cleared
             and now() > greatest(h.created_at, coalesce(h.f_closed, h.created_at)) + h.w then 'unclosed'
        -- ponytail: other originator-closed types get a flat 24 h past their window, because
        -- fn_originators_reverify_handoffs escalates them to the CEO at the window first. Per-type
        -- rules belong in seat_handoff_kind if one of them ever needs a different allowance.
        when h.replied and h.t <> 'it.finding' and not h.held and now() > h.due + h.w + interval '24 hours' then 'unclosed'
        -- 23 Sep 2026: answered, the problem is still there, and a day has gone by.
        when h.replied and h.t = 'it.finding' and not h.cleared and now() > h.created_at + interval '24 hours' then 'open_over_24h'
      end state
      from h)
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', g.t || ':' || g.agent || ':' || g.state,
           'owner_seat', case when g.state = 'unanswered' and g.agent in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'marketing')
                              then g.agent else 'ceo' end,
           'subject', 'agent_actions',
           'title', g.n || ' ' || g.t || ' handoff(s) to ' || g.agent
                    || case g.state when 'unanswered' then ' have had no reply'
                                    when 'open_over_24h' then ' were answered more than 24 hours ago and the problem is still open'
                       else ' were answered but never closed by the seat that sent them' end
                    || case when g.state = 'open_over_24h' then '' else ' past the ' || g.w || ' window' end
                    || '; the oldest is #' || g.oldest_id || ' from '
                    || to_char(g.oldest_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
           'blast', 'agent_facing', 'affected', g.n,
           'evidence', jsonb_build_object('state', g.state, 'type', g.t, 'seat', g.agent, 'reply_within', g.w::text,
                                          'handoff_ids', g.ids, 'oldest_at', g.oldest_at,
                                          'look_at', 'select id, detail, evidence from public.agent_actions where id in (<handoff_ids>)'))
           order by g.t, g.agent, g.state), '[]'::jsonb)
    from (select t, agent, state, min(w) w, count(*) n, min(id) oldest_id, min(created_at) oldest_at,
                 jsonb_agg(id order by id) ids
            from late where state is not null group by t, agent, state) g;
$function$;

CREATE OR REPLACE FUNCTION public.fn_originators_reverify_handoffs(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_questions constant text[] := array['refund.requested', 'billing.question', 'charge.disputed'];
  c_notices constant text[] := array['reveal.paid', 'payment.failed', 'payment.received', 'refund.request_checked', 'refund.paid',
    'refund.declined', 'refund.in_progress', 'nonresponse.charge_raised', 'charge.corrected', 'subscription.due', 'billing.answer',
    'charge.dispute_answer', 'nonresponse.charge_reminder', 'nonresponse.final_demand', 'subscription.dunning',
    'subscription.payment_failed', 'subscription.renewal_reminder'];
  h public.agent_actions; k public.seat_handoff_kind; rep public.support_ceo_report; v_rep jsonb; v_answer bigint;
  v_reqs bigint[]; v_outs jsonb; v_verdict text; v_waiting boolean; v_failed jsonb; v_undecided int;
  n_answered int := 0; n_q_closed_by_ceo int := 0; n_q_reported int := 0; n_q_wait int := 0;
  n_closed int := 0; n_recorded int := 0; n_reported int := 0; n_wait int := 0; v_err jsonb := '[]'::jsonb;
  f record; v_type text; v_ok boolean; n_cleared int := 0; n_generic int := 0; n_reopened int := 0;
begin
  -- 1. THE SALES ENGINEER: did the accountant answer the question it was asked?
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'from' = 'sales_engineer' and a.agent = 'accountant'
              and a.detail->>'type' = any (c_questions) and a.status in ('pending', 'failed')
            order by (a.detail ? 'escalated_report_id'), a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      select * into k from public.seat_handoff_kind where type = h.detail->>'type' and from_seat = 'sales_engineer' and to_seat = 'accountant';
      -- An answer counts whatever became of it afterwards: relaying it is the accountant's notice loop.
      v_answer := null;
      select a.id into v_answer from public.agent_actions a
       where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'from' = 'accountant'
         and a.target_id = case h.detail->>'type'
                             when 'refund.requested' then 'refund.request_checked:' || (h.detail->>'subject_id')
                             when 'billing.question' then 'billing.answer:' || h.id end
       limit 1;
      if v_answer is null and h.detail->>'type' = 'charge.disputed' then
        select a.id into v_answer from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'type' = 'charge.dispute_answer'
           and a.target_id like 'charge.dispute\_answer:%:' || h.id
         limit 1;
      end if;
      rep := null;
      if h.detail ? 'escalated_report_id' then
        select * into rep from public.support_ceo_report where id = (h.detail->>'escalated_report_id')::bigint;
      end if;
      v_verdict := case
        when v_answer is not null then 'answered by the accountant (handoff ' || v_answer || ')'
        when rep.status in ('accepted', 'completed') then 'unanswered; the CEO decided: ' || left(rep.acceptance_receipt, 400)
      end;

      if v_verdict is not null then
        perform set_config('qd.handoff_closer', 'sales_engineer', true);
        perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', 'sales_engineer', 'verified_at', now(), 'verdict', v_verdict));
        perform set_config('qd.handoff_closer', '', true);
        if v_answer is not null then n_answered := n_answered + 1; else n_q_closed_by_ceo := n_q_closed_by_ceo + 1; end if;
      elsif rep.id is null and (h.status = 'failed' or now() > h.created_at + coalesce(k.reply_within, interval '1 hour')) then
        v_rep := public.fn_support_report_to_ceo('handoff_unanswered:' || h.id, 'serious',
          'The accountant did not answer "' || (h.detail->>'type') || '" from the sales engineer (handoff ' || h.id || ')',
          jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'handoff_status', h.status,
                             'error', h.detail->>'error', 'asked_at', h.created_at, 'reply', h.evidence),
          jsonb_build_array('sales_engineer asked the accountant at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
          'Decide what fixes the accountant''s answer. The sales engineer closes the question with your decision.',
          'agent_actions#' || h.id, p_review_in => interval '4 hours', p_source_agent => 'sales_engineer');
        if not coalesce((v_rep->>'ok')::boolean, false) then
          raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
        end if;
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_q_reported := n_q_reported + 1;
      else
        n_q_wait := n_q_wait + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 2. THE ACCOUNTANT: did the money notice it asked for reach the customer or supplier?
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'from' = 'accountant' and a.agent = 'sales_engineer'
              and a.detail->>'type' = any (c_notices) and not (a.detail ? 'originator_verdict')
              and (a.status in ('done', 'failed') or (a.status = 'pending' and a.detail ? 'replied_at'))
            order by (a.detail ? 'escalated_report_id'), a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      select * into k from public.seat_handoff_kind where type = h.detail->>'type' and from_seat = 'accountant' and to_seat = 'sales_engineer';
      v_verdict := null; rep := null;
      -- Every send the notice made: the one the handler names, and on a reveal the supplier's as well.
      v_reqs := array_remove(array[(h.evidence->>'delivery_request')::bigint,
                  case when h.detail->>'type' = 'reveal.paid' then
                    (select a.id from public.agent_actions a where a.agent = 'customer_support' and a.kind = 'handoff'
                      and a.target_id = 'delivery.request:quote_accepted:' || (h.detail->>'subject_id') order by a.id desc limit 1) end], null);
      if h.detail ? 'escalated_report_id' then
        select * into rep from public.support_ceo_report where id = (h.detail->>'escalated_report_id')::bigint;
      end if;

      if h.detail ? 'superseded_by_incident' then
        v_verdict := 'superseded by refund incident ' || (h.detail->>'superseded_by_incident');
      elsif rep.id is not null then
        -- Reported already: it ends with the CEO's decision.
        -- A send recorded on the report that has since failed is decided on its own delivery_undelivered
        -- report; the notice waits for that decision too, and carries it in the verdict.
        if rep.status = 'completed'
           and not exists (select 1 from jsonb_array_elements(coalesce(rep.verified_evidence->'sends', '[]'::jsonb)) o
                            cross join lateral public.fn_delivery_request_outcome((o->>'request_id')::bigint) oc
                            where oc->>'state' = 'failed'
                              and not exists (select 1 from public.support_ceo_report s
                                               where s.idempotency_key = oc->>'report_key' and s.status = 'completed')) then
          v_verdict := 'the CEO decided: ' || left(coalesce(rep.completion_note, rep.acceptance_receipt), 400)
            || coalesce(' | ' || (select string_agg(left(coalesce(s.completion_note, s.acceptance_receipt), 300), ' | ')
                                    from jsonb_array_elements(coalesce(rep.verified_evidence->'sends', '[]'::jsonb)) o
                                    cross join lateral public.fn_delivery_request_outcome((o->>'request_id')::bigint) oc
                                    join public.support_ceo_report s on s.idempotency_key = oc->>'report_key'
                                   where oc->>'state' = 'failed'), '');
        end if;
      elsif h.status = 'failed' or cardinality(v_reqs) = 0
            or (h.detail->>'type' = 'reveal.paid'
                and (h.evidence->>'customer_reachable' = 'false' or h.evidence->>'supplier_reachable' = 'false')) then
        -- The notice never left: no address on file, or the sales engineer could not write it.
        v_rep := public.fn_support_report_to_ceo('notice_undelivered:' || h.id, 'elevated',
          'A ' || (h.detail->>'type') || ' notice the accountant asked for was not sent (handoff ' || h.id || ')',
          jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'handoff_status', h.status,
                             'reply', h.evidence, 'error', h.detail->>'error'),
          jsonb_build_array('accountant asked the sales engineer at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
          'Decide how this customer or supplier learns of it: an address to use, another channel, or record that it cannot go.',
          'agent_actions#' || h.id, p_review_in => interval '1 day', p_source_agent => 'accountant');
        if not coalesce((v_rep->>'ok')::boolean, false) then
          raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
        end if;
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_reported := n_reported + 1;
      else
        select coalesce(jsonb_agg(public.fn_delivery_request_outcome(x)), '[]'::jsonb) into v_outs from unnest(v_reqs) x;
        v_waiting := exists (select 1 from jsonb_array_elements(v_outs) o where o->>'state' in ('waiting', 'missing'));
        v_failed := (select coalesce(jsonb_agg(o), '[]'::jsonb) from jsonb_array_elements(v_outs) o where o->>'state' = 'failed');
        if v_waiting then
          if now() > h.created_at + coalesce(k.reply_within, interval '24 hours') then
            v_rep := public.fn_support_report_to_ceo('notice_unverified:' || h.id, 'elevated',
              'A ' || (h.detail->>'type') || ' notice has no delivery outcome after ' || coalesce(k.reply_within, interval '24 hours') || ' (handoff ' || h.id || ')',
              jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'sends', v_outs,
                                 'delivery_loop', (select string_agg(o->>'loop', ', ') from jsonb_array_elements(v_outs) o)),
              jsonb_build_array('accountant asked the sales engineer at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
              'Find out what became of this send. The accountant closes the notice with your decision.',
              'agent_actions#' || h.id, p_review_in => interval '1 day', p_source_agent => 'accountant');
            if not coalesce((v_rep->>'ok')::boolean, false) then
              raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
            end if;
            update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
             where id = h.id;
            n_reported := n_reported + 1;
          end if;
        elsif jsonb_array_length(v_failed) > 0 then
          -- It did not arrive: the sales engineer's delivery_undelivered report carries it to the CEO.
          -- The notice closes with the CEO's decision on that report once it is decided and completed.
          select count(*) into v_undecided from jsonb_array_elements(v_failed) o
           where not exists (select 1 from public.support_ceo_report s where s.idempotency_key = o->>'report_key' and s.status = 'completed');
          if v_undecided = 0 then
            v_verdict := 'did not arrive; the CEO decided: ' || (select string_agg(left(coalesce(s.completion_note, s.acceptance_receipt), 300), ' | ')
              from jsonb_array_elements(v_failed) o join public.support_ceo_report s on s.idempotency_key = o->>'report_key');
          end if;
        else
          -- Only a send that arrived is 'reached'; a stubbed, routed or cancelled one ended without arriving.
          v_verdict := case when exists (select 1 from jsonb_array_elements(v_outs) o where o->>'state' <> 'reached')
                            then 'ended: ' else 'reached: ' end || (select string_agg((o->>'loop') || ' (request ' || (o->>'request_id') || ')', ', ') from jsonb_array_elements(v_outs) o);
        end if;
      end if;

      if v_verdict is null then
        n_wait := n_wait + 1;
      else
        -- Only a pending row is closed; a done or failed row is already terminal and gets the verdict recorded.
        if h.status = 'pending' and k.originator_closes then
          perform set_config('qd.handoff_closer', 'accountant', true);
          perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
            'verified_by', 'accountant', 'verified_at', now(), 'verdict', v_verdict));
          perform set_config('qd.handoff_closer', '', true);
          n_closed := n_closed + 1;
        else
          n_recorded := n_recorded + 1;
        end if;
        update public.agent_actions
           set detail = detail || jsonb_build_object('originator_verdict', v_verdict, 'originator_verified_by', 'accountant', 'originator_verified_at', now())
         where id = h.id;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 4. EVERY OTHER ORIGINATOR CLOSES WHAT WAS ANSWERED (4 Oct 2026). Sections 1 and 2 cover the two
  -- money conversations; every other kind with originator_closes had no closer at all, so an answered
  -- handoff stayed open until the SLA duty raised it. The originator reads the reply its handler wrote:
  --   no 'waiting' and no error  -> the contract is met: closed, the reply is the verdict;
  --   an error or ok=false       -> sent back with the reason and handled again (ruling 1059: a rejection
  --                                 never ends the cycle); after 3 rounds the SLA duty raises it to the CEO;
  --   'waiting', a future due_at, or a step held by the model hold -> the contract is not finished; left.
  for h in select a.* from public.agent_actions a
             join public.seat_handoff_kind sk on sk.type = a.detail->>'type' and sk.from_seat = a.detail->>'from'
                                             and sk.to_seat = a.agent and sk.originator_closes
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ? 'replied_at'
              and a.detail->>'type' not in ('it.finding', 'delivery.request')
              and not (a.detail->>'type' = any (c_questions || c_notices))
              and not (coalesce(a.evidence, '{}'::jsonb) ? 'waiting')
              and coalesce(a.evidence#>>'{step,action}', '') <> 'held'
              and coalesce((a.detail->>'due_at')::timestamptz, '-infinity') <= now()
              and coalesce((a.detail->>'reopened')::int, 0) < 3
            order by a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      if coalesce(h.evidence, '{}'::jsonb) ? 'error' or h.evidence->>'ok' = 'false' then
        update public.agent_actions
           set detail = (detail - 'replied_at') || jsonb_build_object('reopened', coalesce((detail->>'reopened')::int, 0) + 1,
                 'reopen_reasons', coalesce(detail->'reopen_reasons', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                   'at', now(), 'by', h.detail->>'from', 'why', 'the reply did not meet the contract: '
                   || left(coalesce(h.evidence->>'error', h.evidence->>'reason', h.evidence::text), 300))))
         where id = h.id;
        -- Its own block: a handler that raises still counts as a round, so the 3-round limit holds.
        begin
          perform public.fn_seat_handoff_act(h.id);
        exception when others then
          v_err := v_err || jsonb_build_object('handoff', h.id, 'sent_back_error', left(sqlerrm, 300));
        end;
        n_reopened := n_reopened + 1;
      else
        perform set_config('qd.handoff_closer', h.detail->>'from', true);
        perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', h.detail->>'from', 'verified_at', now(),
          'verdict', 'answered within the contract of ' || (h.detail->>'type') || '; closed by the originator'));
        perform set_config('qd.handoff_closer', '', true);
        n_generic := n_generic + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 3. A DEFECT THE CEO RAISED CLEARS WHEN THE SAME CONVERSATION WORKS AGAIN. The finding's key names
  -- the conversation; it closes when the latest one of that kind was answered (a question), written
  -- (a notice the sales engineer could not write) or delivered (a notice with no outcome). Closing it
  -- lets the IT loop close its own handoff. What was missed while broken is not re-sent automatically:
  -- the CEO's decision on each is on its report.
  for f in select q.issue_key from public.it_engineer_finding q
            where q.closed_at is null
              and (q.issue_key like 'monitor:handoff\_unanswered:%' or q.issue_key like 'monitor:notice\_undelivered:%'
                   or q.issue_key like 'monitor:notice\_unverified:%') loop
    begin
      v_type := split_part(f.issue_key, ':', 3);
      h := null;
      if f.issue_key like 'monitor:handoff\_unanswered:%' then
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'sales_engineer'
           and a.agent = split_part(f.issue_key, ':', 4) and a.status = 'done'
         order by a.id desc limit 1;
        v_ok := h.evidence->>'verdict' like 'answered%';
      elsif f.issue_key like 'monitor:notice\_undelivered:%' then
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'accountant'
           and (a.status <> 'pending' or a.detail ? 'replied_at')
         order by a.id desc limit 1;
        v_ok := h.status <> 'failed' and (h.evidence->>'delivery_request') is not null;
      else
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'accountant'
           and a.detail ? 'originator_verdict'
         order by a.id desc limit 1;
        -- 'ended' (routed, stubbed, digested, cancelled) is an outcome too: the finding was "no outcome".
        v_ok := h.detail->>'originator_verdict' ~ '^(reached|ended): ';
      end if;
      if coalesce(v_ok, false) then
        perform public.fn_it_engineer_finding_close(f.issue_key,
          'handoff ' || h.id || ' of the same kind worked again, re-checked by fn_originators_reverify_handoffs');
        n_cleared := n_cleared + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('finding', f.issue_key, 'error', left(sqlerrm, 300));
    end;
  end loop;

  return jsonb_build_object(
    'defects_cleared', n_cleared,
    'every_originator', jsonb_build_object('closed', n_generic, 'sent_back', n_reopened),
    'sales_engineer', jsonb_build_object('answered', n_answered, 'closed_with_ceo_decision', n_q_closed_by_ceo,
                                         'reported', n_q_reported, 'waiting', n_q_wait),
    'accountant', jsonb_build_object('closed', n_closed, 'recorded', n_recorded, 'reported', n_reported, 'waiting', n_wait),
    'errors', v_err);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_customer_support_sends_the_it_digest(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_hour  constant time := time '19:00';                         -- the founder's fixed local time
  v_stub  boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_local timestamp := p_now at time zone 'Asia/Dubai';
  v_key   text := 'it_daily_digest:' || to_char(p_now at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  x record; f public.it_engineer_finding; v_why text; v_his boolean; v_items jsonb := '[]'::jsonb;
  v_event text; v_detail text; v_res jsonb; v_fan jsonb := '[]'::jsonb; v_before bigint;
  n_dec int := 0; n_flt int := 0; n_int int := 0; n_fixed int := 0; n_wait int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('fn_customer_support_sends_the_it_digest'));
  if v_local::time < c_hour then
    return jsonb_build_object('sent', false, 'reason', 'the IT digest leaves at 19:00 Dubai', 'digest_key', v_key);
  end if;
  if exists (select 1 from public.founder_alerts where dedupe_key = v_key) then
    return jsonb_build_object('sent', false, 'reason', 'today''s IT digest was already decided', 'digest_key', v_key);
  end if;

  for x in select a.id, a.detail, a.evidence from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'pending'
              and a.detail->>'type' = 'delivery.request' and a.detail->>'recipient_role' = 'founder'
              and a.detail->>'kind' = 'it_new_bug' and a.evidence->>'digest' = 'pending'
            order by a.id loop
    -- Anything that is not "a new bug nobody could fix" (today: the CEO-silence reports) is the CEO's.
    if coalesce(x.detail->>'dedupe_key', '') !~ '^it_new_bug:' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'instruction 642: kept internal; the CEO is asked every tick until it answers',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    select * into f from public.it_engineer_finding where issue_key = regexp_replace(x.detail->>'dedupe_key', '^it_new_bug:', '');
    if not found or f.closed_at is not null then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'fixed',
        'why', 'closed before the digest: ' || coalesce(f.close_note, 'no finding row'),
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_fixed := n_fixed + 1; continue;
    end if;
    -- FOUNDER RULING 1090 (30 Sep 2026): a credential only he can renew is never a digest line.
    if public.fn_it_credential_founder_required(f.issue_key, f.title, f.evidence) then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 1090: a credential only the founder can renew is recorded by the IT engineer, never sent to him',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    -- His ruling that something is NOT his wins over any pattern that would ask him.
    select c.why, c.to_founder into v_why, v_his from public.it_founder_decision_class c where f.issue_key like c.issue_key_like
     order by c.to_founder, length(c.issue_key_like) desc limit 1;
    if found and not v_his then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', v_why, 'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; v_why := null; continue;
    end if;
    -- FOUNDER RULING 4 OCT 2026: the digest carries ONLY decisions only he can make. A fault, however
    -- old, is the seats' to solve; it stays an open finding on the OS and is never emailed.
    if not found then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 4 Oct 2026: not a decision only the founder can make; the finding stays with the '
               || replace(coalesce(f.evidence->>'owner_seat', 'it_engineer'), '_', ' ') || ' on the OS',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'key', f.issue_key,
      'title', regexp_replace(left(f.title, 140), '[.\s]+$', ''), 'why', v_why);
    n_dec := n_dec + 1;
  end loop;

  if jsonb_array_length(v_items) = 0 then
    if not v_stub then
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      values ('info', 'IT daily digest: nothing needs the founder today',
              jsonb_build_object('fixed', n_fixed, 'internal', n_int, 'waiting', n_wait)::text, 'os', v_key);
    end if;
    return jsonb_build_object('sent', false, 'reason', 'nothing needs him today', 'digest_key', v_key,
                              'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'stubbed', v_stub);
  end if;

  -- One sentence per decision. No line claims work is under way: nothing here is a fault report.
  select string_agg('- DECISION: ' || (i->>'title') || '. Only you can decide this: ' || (i->>'why')
                    || '. The CEO keeps it open until you answer (reference ' || (i->>'key') || ').',
                    E'\n' order by (i->>'id')::bigint)
    into v_detail from jsonb_array_elements(v_items) i;
  v_event := 'IT today: ' || n_dec || ' decision' || case when n_dec > 1 then 's' else '' end || ' for you';
  v_detail := 'The one IT message of the day. It carries only decisions only you can make; every fault stays with '
           || 'the seats on the OS.' || E'\n\n' || v_detail;

  if v_stub then
    v_res := jsonb_build_object('stubbed', true);               -- A TEST NEVER REACHES HIM
  else
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_detail, p_level => 'normal',
                                      p_kind => 'it_daily_digest', p_dedupe_key => v_key, p_owner_agent => 'customer_support');
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
  end if;
  -- Each item told is completed with the digest's notification ids; the delivery watch takes it from there.
  for x in select (i->>'id')::bigint id from jsonb_array_elements(v_items) i loop
    perform public.fn_seat_handoff_complete(x.id, (select (a.evidence - 'waiting') from public.agent_actions a where a.id = x.id)
      || jsonb_build_object('digest', 'sent', 'digest_key', v_key, 'notify', v_res, 'notification_ids', v_fan, 'notification_id', v_fan->0)
      || case when v_stub then jsonb_build_object('stubbed', true) else '{}'::jsonb end);
  end loop;

  return jsonb_build_object('sent', true, 'digest_key', v_key, 'event', v_event, 'detail', v_detail,
                            'decisions', n_dec, 'faults', n_flt, 'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $function$
;

-- ══ (b) THE GROWTH FINDING CLOSES WITH ITS CAUSE ═════════════════════════════════════════════════
select public.fn_it_engineer_finding_close('duty:db_health:growth:knowledge_vector_ml',
  'classified 4 Oct 2026: the multilingual embedding backfill (#1115, ml-embed-backfill.yml) - 42,519 of 148,326 kb_chunks '
  || 'embedded, ~8,500 rows a day landing in the 08:00-10:00 UTC window of its scheduled runs. Registered in '
  || 'public.it_expected_table_growth until 31 Oct 2026; the growth duty raises the table again after that.');

-- ══ PROBE ════════════════════════════════════════════════════════════════════════════════════════
-- The file defines routines, so the probe runs in a sub-block that raises and rolls back ONLY itself,
-- and reports through a verdict row. Every seeded row is ZZ DEMO / demo=true. The digest runs stubbed
-- (app.qd_stub_founder_notify) on 2099 keys, so it can never reach the founder or collide with a real day;
-- whatever it does to the real pending digest items is rolled back with the sub-block.
create temp table if not exists _qd_probe (verdict text) on commit drop;
do $probe$
declare
  v_closer bigint; v_month bigint; v_held bigint; v_ctl bigint; v_items jsonb; v_r jsonb; v_d1 jsonb; v_d2 jsonb;
  v_status text; v_out text;
begin
  begin
    -- 1. answered -> closed in the next tick (an originator_closes kind with no closer of its own before)
    insert into public.agent_actions (agent, kind, status, title, detail, evidence, target_table, target_id)
    values ('it_engineer', 'handoff', 'pending', 'ZZ DEMO ceo.root_cause probe',
            jsonb_build_object('type', 'ceo.root_cause', 'from', 'ceo', 'to', 'it_engineer', 'demo', true, 'subject_table', 'zz_demo', 'subject_id', 'probe', 'replied_at', now()),
            jsonb_build_object('accepted', true), 'zz_demo', 'zz_demo:closer')
    returning id into v_closer;
    -- 2. a month directive due at month end, three days old, and a review step held by the model hold
    insert into public.agent_actions (agent, kind, status, title, detail, evidence, target_table, target_id, created_at)
    values ('accountant', 'handoff', 'pending', 'ZZ DEMO ceo.month_directive probe',
            jsonb_build_object('type', 'ceo.month_directive', 'from', 'ceo', 'to', 'accountant', 'demo', true,
                               'subject_table', 'zz_demo', 'subject_id', 'probe', 'replied_at', now() - interval '3 days', 'due_at', now() + interval '20 days'),
            jsonb_build_object('waiting', 'the CEO closes this at month end'), 'zz_demo', 'zz_demo:month', now() - interval '3 days')
    returning id into v_month;
    insert into public.agent_actions (agent, kind, status, title, detail, evidence, target_table, target_id, created_at)
    values ('accountant', 'handoff', 'pending', 'ZZ DEMO deliberation.review probe',
            jsonb_build_object('type', 'deliberation.review', 'from', 'ceo', 'to', 'accountant', 'demo', true, 'subject_table', 'zz_demo', 'subject_id', 'probe', 'replied_at', now() - interval '5 days'),
            jsonb_build_object('waiting', 'review', 'step', jsonb_build_object('action', 'held')), 'zz_demo', 'zz_demo:held', now() - interval '5 days')
    returning id into v_held;
    -- positive control: the same review NOT held, five days old, must still be raised
    insert into public.agent_actions (agent, kind, status, title, detail, evidence, target_table, target_id, created_at)
    values ('accountant', 'handoff', 'pending', 'ZZ DEMO deliberation.review control',
            jsonb_build_object('type', 'deliberation.review', 'from', 'ceo', 'to', 'accountant', 'demo', true, 'subject_table', 'zz_demo', 'subject_id', 'probe', 'replied_at', now() - interval '5 days'),
            jsonb_build_object('waiting', 'review'), 'zz_demo', 'zz_demo:ctl', now() - interval '5 days')
    returning id into v_ctl;

    v_r := public.fn_originators_reverify_handoffs(500);
    select status into v_status from public.agent_actions where id = v_closer;
    v_items := public.fn_it_handoff_sla_items(true);

    -- 3. the digest: the current real set, then a seeded decision only the founder can make
    perform set_config('app.qd_stub_founder_notify', 'on', true);
    v_d1 := public.fn_customer_support_sends_the_it_digest(timestamptz '2099-01-01 20:00:00+04');
    perform public.fn_it_engineer_finding_upsert('duty:access:zz_demo_probe', 'ZZ DEMO an account owner nobody recognises',
      'probe', 'internal', 1, jsonb_build_object('owner_seat', 'it_engineer', 'demo', true), '{}'::text[], '{}'::text[], 'it_engineer.probe');
    insert into public.agent_actions (agent, kind, status, title, detail, evidence)
    values ('customer_support', 'handoff', 'pending', 'ZZ DEMO digest decision probe',
            jsonb_build_object('type', 'delivery.request', 'from', 'it_engineer', 'recipient_role', 'founder', 'kind', 'it_new_bug',
                               'dedupe_key', 'it_new_bug:duty:access:zz_demo_probe', 'demo', true, 'subject_table', 'zz_demo', 'subject_id', 'digest'),
            jsonb_build_object('digest', 'pending'));
    v_d2 := public.fn_customer_support_sends_the_it_digest(timestamptz '2099-01-02 20:00:00+04');

    v_out := case
      when v_status is distinct from 'done' then 'PROBE FAILED: answered handoff ' || v_closer || ' was not closed (' || coalesce(v_status, 'null') || '; ' || (v_r->'every_originator')::text || ')'
      when v_items::text ~ ('\m' || v_month || '\M') then 'PROBE FAILED: a month directive before its due_at was called late'
      when v_items::text ~ ('\m' || v_held || '\M') then 'PROBE FAILED: a review step held by the model hold was called unclosed'
      when v_items::text !~ ('\m' || v_ctl || '\M') then 'PROBE FAILED: the positive control (an unheld review 5 days old) was not raised'
      when coalesce((v_d1->>'decisions')::int, 0) <> 0 or coalesce((v_d1->>'sent')::boolean, false) then 'PROBE FAILED: the current findings produced founder lines: ' || v_d1::text
      when coalesce((v_d2->>'decisions')::int, 0) <> 1 then 'PROBE FAILED: the seeded founder decision did not produce exactly 1 line: ' || v_d2::text
      when (v_d2->>'detail') ilike '%engineers are making%' then 'PROBE FAILED: the false claim is still in the digest'
      else 'PROBE OK: answered handoff closed by its originator in one tick; month directive (not due) and held review not raised, unheld control raised; '
           || 'current findings -> 0 founder lines (' || coalesce(v_d1->>'internal', '?') || ' kept internal, ' || coalesce(v_d1->>'fixed', '?') || ' already fixed); '
           || 'seeded founder decision -> ' || (v_d2->>'decisions') || ' line'
    end;
    raise exception 'QD_PROBE_ROLLBACK';
  exception when others then
    if sqlerrm <> 'QD_PROBE_ROLLBACK' then v_out := 'PROBE FAILED: ' || left(sqlerrm, 400); end if;
  end;
  insert into _qd_probe values (v_out);
end $probe$;
select verdict from _qd_probe;
