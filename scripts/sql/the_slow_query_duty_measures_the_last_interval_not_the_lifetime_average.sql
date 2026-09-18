-- THE SLOW-QUERY DUTY MEASURES THE LAST INTERVAL, NOT THE LIFETIME AVERAGE.
--
-- Assigned: it_engineer. 18 Sep 2026.
--
-- WHAT WAS WRONG. Duty 14 (db_health) read extensions.pg_stat_statements and raised a finding for
-- any statement whose mean_exec_time exceeded fn_it_threshold('slow_query_mean_ms'). mean_exec_time
-- is total_exec_time / calls SINCE THE LAST RESET, and nothing resets it. It therefore answers
-- "what is the slowest statement ever recorded on this database", never "is the database slow now".
--
-- MEASURED IN PRODUCTION, 18 Sep 2026 (read-only, and in a rolled-back block):
--   pg_stat_statements_info.stats_reset = 2026-06-06 22:39:44+00 -- a 104-day lifetime average.
--   The ten findings the duty raised (duty:db_health:slow:*) carry `calls` in their evidence, taken
--   on 14 Sep. Four days later EVERY ONE of them has the SAME calls and the SAME mean:
--     queryid                 calls 14 Sep   calls 18 Sep   delta   mean_ms (unchanged)
--     -1488991352399092984          56             56          0     65682.8
--     -3555723878668831129          72             72          0     58767.6
--      9129102144315932938         669            669          0     44981.8
--      7313371897895493266         301            301          0     35288.5
--     -2292380670795110721         154            154          0     32080.3
--      -286833182716599660         154            154          0     32050.8
--     -3494691233747084970          66             66          0     31891.9
--      8659305906400088713         150            150          0     24541.0
--      5027105858923773171         167            167          0     21315.4
--     -4784328982199561541          69             69          0     20662.8
--   Not one of the ten has run since the findings were raised. Their stats_since values run from
--   6 Aug to 9 Sep, and eight of the ten carry the management API's own marker
--   ("-- source: POST /v1/projects/:ref/database/query -- user: pat:..."): they are introspection
--   queries typed in past sessions. One of them calls fn_kernel_all_boards, which was retired with
--   the kernel boards. The findings were arithmetically correct and about nothing that is happening.
--
-- WHAT CHANGES. public.it_query_stat_snapshot records (calls, total_exec_time) per queryid at the
-- end of every db_health run. The next run raises on the mean OVER THE INTERVAL BETWEEN THE TWO
-- SNAPSHOTS -- (total_exec_time_now - total_exec_time_then) / (calls_now - calls_then) -- and a
-- statement that did not run in the interval has a zero denominator and cannot be raised at all.
--
-- THIS IS NOT A SOFTENED CHECK, AND THE ONE PLACE IT COULD HAVE BEEN IS CLOSED. Neither threshold
-- moves: still more than fn_it_threshold('slow_query_mean_ms') milliseconds a call, and still at
-- least fn_it_threshold('slow_query_min_calls') calls. The rule becomes STRICTER, because both must
-- be earned inside one interval instead of accumulated over four months.
--
-- Being stricter IS the risk, and it has a name: a statement that is rare and expensive. The
-- schedule runs db_health once a day, and a nightly export taking 60 s makes ONE call in that day,
-- not 50 -- so a call-count floor alone would make the most expensive statement on the database
-- permanently invisible, which would be a real weakening dressed as a correction. The call floor is
-- therefore one of TWO arms: a statement is also raised when the interval's total time exceeds
-- slow_query_min_calls * slow_query_mean_ms (50 x 500 ms = 25 s). That product is not a new
-- threshold; it is exactly the time the call-count arm must accumulate before it can fire, written
-- out for the case where one call spends it. A statement that burns 25 seconds of a day is raised
-- whether it did it in one call or a thousand.
--
-- Proved both ways in the probe at the foot of this file: with a snapshot taken at the same instant
-- the rule raises 0 (the old rule raises 10 on the same data), and with a snapshot rolled back by
-- one statement's own history it raises that statement again.
--
-- WHAT THE RULE STILL CANNOT SEE, said rather than left to be discovered: a statement that is slow
-- only occasionally. Both arms are means and totals; neither reads max_exec_time, so a statement
-- with a mean of 8 ms and a maximum of 7.5 s -- which is fn_doc_backups_next, measured on the same
-- day -- is invisible to this duty, as it was to the rule before it. An outlier arm is a separate
-- subject and is not smuggled in here.
--
-- The snapshot is SEEDED by this file, in the same transaction, so the first run after the apply
-- already has a baseline. Without the seed the first run would see every statement's whole lifetime
-- as its first interval and re-raise all ten -- and each one pages the founder through
-- fn_it_engineer_alert_tick before the second run could close it.
--
-- A statement with NO baseline is not raised at all -- the join is an INNER join. A missing baseline
-- is not evidence of a long interval; it means nobody has measured this statement yet. Reading it as
-- zero would make the whole lifetime the first interval, which is the rule being replaced, and it
-- would come back in full every time pg_stat_statements is reset or an entry is evicted and
-- re-created. Such a statement gets its baseline written by the same run and is judged one interval
-- later. A counter that went BACKWARDS is excluded the same way, on calls AND on total_exec_time:
-- a re-created entry can be ahead on one and behind on the other, and neither can be true of a
-- statement that simply continued.
--
-- pg_stat_statements is keyed on (userid, dbid, toplevel, queryid), NOT on queryid: the same
-- statement executed by postgres and by authenticator is two rows. The first draft of this file
-- keyed the snapshot on queryid alone and the seed failed with 21000, "ON CONFLICT DO UPDATE
-- command cannot affect row a second time" -- caught by running the file in a rolled-back
-- transaction before it was ever applied. Every read of the view below therefore sums calls and
-- total_exec_time per queryid first, which is also the right arithmetic: one statement's cost is
-- what it cost, whoever ran it.
--
--   node scripts/apply_sql.mjs scripts/sql/the_slow_query_duty_measures_the_last_interval_not_the_lifetime_average.sql --apply --ddl

-- -- 1. THE SNAPSHOT --------------------------------------------------------------------------------
create table if not exists public.it_query_stat_snapshot (
  queryid          bigint primary key,
  calls            bigint           not null,
  total_exec_time  double precision not null,
  -- read, not decoration: the duty puts the interval's start and its length into every finding's
  -- evidence, so a reader can tell whether "50 calls" was over a day or over five minutes.
  taken_at         timestamptz      not null default now()
);
comment on table public.it_query_stat_snapshot is
  'Duty 14 (db_health) reads pg_stat_statements, whose counters are cumulative since stats_reset and never decay. This is the previous run''s reading, so the duty raises on the mean over the LAST INTERVAL instead of over the database''s whole life. Written only by fn_it_duties_scheduled.';

alter table public.it_query_stat_snapshot enable row level security;
-- service_role bypasses RLS, so the seats keep full access. The policy exists so the schema SAYS
-- deliberately service-role only, rather than leaving a table with RLS on and no policy -- which is
-- indistinguishable from one where somebody meant to write a policy and forgot.
drop policy if exists it_query_stat_snapshot_service_role_only on public.it_query_stat_snapshot;
create policy it_query_stat_snapshot_service_role_only on public.it_query_stat_snapshot
  as permissive for all to public using (false) with check (false);
revoke all on public.it_query_stat_snapshot from anon, authenticated;

-- The seed: the baseline the FIRST db_health run after this apply measures its interval against.
insert into public.it_query_stat_snapshot (queryid, calls, total_exec_time, taken_at)
select s.queryid, sum(s.calls), sum(s.total_exec_time), now()
  from extensions.pg_stat_statements s
 where s.queryid is not null
 group by s.queryid
  on conflict (queryid) do update
     set calls = excluded.calls, total_exec_time = excluded.total_exec_time, taken_at = excluded.taken_at;

-- -- 2. THE DUTY ------------------------------------------------------------------------------------
-- The body is the live definition read back out of production on 18 Sep 2026 (it carries the #727
-- alias fix), with only the slow-statement block of duty 14 changed.

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
                               '(query text unavailable)') q
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
              where (s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0)
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



-- -- 3. PROBE ---------------------------------------------------------------------------------------
-- This file carries DDL, so the probe CLEANS UP AFTER ITSELF (quotesdone-apply-discipline section 4).
-- Its SUCCESS path ends in a notice. Its failure paths raise deliberately, which takes the table and
-- the routine with them: a detector that cannot see is worse than the one it replaces, because it
-- looks like a fix.
--
-- It touches no person and no business row. Its only write is to public.it_query_stat_snapshot, the
-- table this file creates, and it restores the one row it borrows to the reading the seed left. The
-- ZZ DEMO convention has no counterpart for a query-statistics row, so instead the probe NAMES what
-- it must not disturb: it writes nothing to public.it_engineer_finding, and it asserts the borrowed
-- row by its own queryid rather than by a before/after count(*) -- the IT tick runs on a schedule
-- and a concurrent insert between two counts would abort an apply that was correct.
do $probe$
declare
  v_lifetime int; v_same_instant int; v_rolled_back int;
  v_qid bigint; v_calls bigint; v_total double precision; v_mean numeric;
begin
  -- (a) what the OLD lifetime rule raises on exactly this data, written as the old block wrote it
  select count(*) into v_lifetime from (
    select s.queryid from extensions.pg_stat_statements s
     where s.calls >= public.fn_it_threshold('slow_query_min_calls')
       and s.mean_exec_time > public.fn_it_threshold('slow_query_mean_ms')
     order by s.mean_exec_time desc limit 10) z;

  -- (b) what the NEW interval rule raises against the snapshot the seed just took. No time has
  --     passed, so every delta is zero and the answer must be 0 -- on BOTH arms.
  select count(*) into v_same_instant from (
    with s as (select ss.queryid, sum(ss.calls) calls, sum(ss.total_exec_time) total_exec_time
                 from extensions.pg_stat_statements ss where ss.queryid is not null group by ss.queryid)
    select s.queryid
      from s
      join public.it_query_stat_snapshot p
        on p.queryid = s.queryid and p.calls <= s.calls and p.total_exec_time <= s.total_exec_time
     where (s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0)
           > public.fn_it_threshold('slow_query_mean_ms')
       and (s.calls - p.calls >= public.fn_it_threshold('slow_query_min_calls')
            or s.total_exec_time - p.total_exec_time
               > public.fn_it_threshold('slow_query_min_calls') * public.fn_it_threshold('slow_query_mean_ms'))
     limit 10) z;

  -- (c) THE CHECK STILL BITES. Roll ONE statement's snapshot row back to zero, which says "this
  --     statement did all of its work inside the interval", and it must be raised again.
  with s as (select ss.queryid, sum(ss.calls) calls, sum(ss.total_exec_time) total_exec_time
               from extensions.pg_stat_statements ss where ss.queryid is not null group by ss.queryid)
  select s.queryid, s.calls, s.total_exec_time, round((s.total_exec_time / s.calls)::numeric, 1)
    into v_qid, v_calls, v_total, v_mean
    from s
   where s.calls >= public.fn_it_threshold('slow_query_min_calls')
     and s.total_exec_time / s.calls > public.fn_it_threshold('slow_query_mean_ms')
   order by s.total_exec_time / s.calls desc limit 1;

  if v_qid is null then
    raise notice 'PROBE: no statement on this database is over the threshold at all, so (c) cannot be posed. lifetime_rule=% interval_rule=%', v_lifetime, v_same_instant;
  else
    update public.it_query_stat_snapshot set calls = 0, total_exec_time = 0 where queryid = v_qid;
    select count(*) into v_rolled_back from (
      with s as (select ss.queryid, sum(ss.calls) calls, sum(ss.total_exec_time) total_exec_time
                   from extensions.pg_stat_statements ss where ss.queryid is not null group by ss.queryid)
      select s.queryid
        from s
        join public.it_query_stat_snapshot p
          on p.queryid = s.queryid and p.calls <= s.calls and p.total_exec_time <= s.total_exec_time
       where s.queryid = v_qid
         and (s.total_exec_time - p.total_exec_time) / nullif(s.calls - p.calls, 0)
             > public.fn_it_threshold('slow_query_mean_ms')
         and (s.calls - p.calls >= public.fn_it_threshold('slow_query_min_calls')
              or s.total_exec_time - p.total_exec_time
                 > public.fn_it_threshold('slow_query_min_calls') * public.fn_it_threshold('slow_query_mean_ms'))) z;
    -- put the seed's reading back, so the first real run measures from now and not from zero
    update public.it_query_stat_snapshot set calls = v_calls, total_exec_time = v_total where queryid = v_qid;
    if v_rolled_back <> 1 then
      raise exception 'PROBE FAILED: a statement averaging % ms over % calls inside the interval was NOT raised. The interval rule is blind, which is worse than the lifetime rule it replaces.', v_mean, v_calls;
    end if;
    if not exists (select 1 from public.it_query_stat_snapshot p
                    where p.queryid = v_qid and p.calls = v_calls and p.total_exec_time = v_total) then
      raise exception 'PROBE FAILED: the snapshot row for queryid % was not restored to % calls.', v_qid, v_calls;
    end if;
  end if;

  if v_same_instant <> 0 then
    raise exception 'PROBE FAILED: the interval rule raised % finding(s) across a zero-length interval; a statement that did not run cannot be slow.', v_same_instant;
  end if;

  raise notice 'PROBE OK: on the same data the lifetime rule raises %, the interval rule raises % across a zero-length interval, and it raises the slowest statement again (% ms over % calls) when that work falls inside the interval. Nothing was written to it_engineer_finding and the borrowed snapshot row is restored.',
    v_lifetime, v_same_instant, v_mean, v_calls;
end $probe$;
