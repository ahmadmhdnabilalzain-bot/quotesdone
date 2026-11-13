-- a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one
-- Seat: it_engineer (the finding); customer_support (a customer's signed-terms certificate and its re-sign). 13 Nov 2026.
-- Founder (7 Sep and 13 Nov 2026): nothing may leave a person stuck with nothing on screen, and a seat with a step must know.
--
-- MEASURED on production, 13 Nov 2026 (read-only):
--   * Suppliers already have this: fn_sales_engineer_resigns_unsigned_agreements (a_supplier_agreement_that_did_not_land_is_
--     signed_again.sql, every minute) posts compliance_archive 'sign' again for an acceptance with no certificate after 5
--     minutes, 3 times, then asks the sales engineer. It certified the 07:46 failure (lead 159271, ZZ DEMO) at 07:51.
--   * Customers had NOTHING: kyc posts 'sign' once, in the background, and a lost or failed render or record was never asked
--     again. In run f0219e92 (08:47, ZZ DEMO) no certificate was stored, because kyc's acceptance write itself had been
--     cancelled (fixed in kyc: _shared/recorded_write.ts; the person is now told and presses again).
--   * Nobody checked that a person using the platform HAS an acceptance on record. Counted 13 Nov 09:00 UTC: customers with a
--     request and no acceptance: 0 real, 1 demo; suppliers submitted or approved without an acceptance: 0; acceptances
--     without a certificate: customers 0, suppliers 0 real (1 demo in flight, inside its 5 minutes).
--   The cause of the 13 Nov failures was rehearsals holding table locks on production (scripts/lib/replay_guard.mjs), but
--   any lock (an apply, a long migration) can do the same, so the recovery must not depend on the cause.
--
-- WHAT CHANGES:
--   1. fn_customer_support_resigns_unsigned_terms(): every minute, a customer who accepted the terms more than 5 minutes ago
--      and has no certificate for THAT acceptance is signed again (compliance_archive 'sign', kind customer; it returns the
--      existing certificate if one has since landed and writes a new one only by compare-and-set). At most 3 times, 5
--      minutes apart, each an agent_actions row (customer_support, customer_terms_resign, auto_done); after the third, ONE
--      needs_review row for customer_support. The supplier sweep is the model; it is not changed.
--   2. fn_it_engineer_finds_people_working_without_an_acceptance(): every hour, counts (a) customers with a request and no
--      acceptance on record, (b) suppliers who submitted their registration or are approved with no acceptance, (c)
--      acceptances with no certificate after 30 minutes (both kinds: the sweeps have had their three tries). Real and demo
--      apart; a real count above 0 raises one it_engineer finding per state (fn_it_engineer_finding_upsert), with ids only.
--   No index is added: customers holds 5 rows, and an index on a hot table is a lock this file does not need.
--
-- WHAT IT DOES NOT CHANGE: the supplier sweep, the portal copy ("Signing your Supplier Agreement…"), compliance_archive's
-- refusal to certify an acceptance that is not on record (12 Aug 2026), or who may accept.
--
-- Prevented by: scripts/checks/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.test.mjs
-- (offline: both routines exist, are scheduled, bounded, revoked, and keyed on the acceptance) and the probe
-- a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one_probe.sql.

create or replace function public.fn_customer_support_resigns_unsigned_terms(p_customer_id uuid default null)
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_secret text; v_ref text; v_prior int; v_last timestamptz; v_posted int := 0; v_waiting int := 0; v_escalated int := 0;
begin
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  begin v_ref := public.qd_project_ref(); exception when others then v_ref := null; end;
  if v_ref is null or coalesce(v_secret, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'no project ref or internal credential: nothing can be posted');
  end if;

  for r in select c.id, c.email, c.tos_accepted_at
             from public.customers c
            where c.tos_accepted_at is not null and coalesce(btrim(c.email), '') <> '' and not coalesce(c.banned, false)
              and (p_customer_id is null or c.id = p_customer_id)   -- one customer: the probe's own fixture, never anyone else
              and (c.signed_terms_path is null or c.signed_terms_at is null or c.signed_terms_at < c.tos_accepted_at)
              and c.tos_accepted_at < now() - interval '5 minutes'
            order by c.tos_accepted_at limit 20 loop
    select count(*), max(a.created_at) into v_prior, v_last
      from public.agent_actions a
     where a.agent = 'customer_support' and a.kind = 'customer_terms_resign' and a.target_id = r.id::text
       and (a.detail ->> 'tos_accepted_at')::timestamptz = r.tos_accepted_at and a.status = 'auto_done';
    if v_prior >= 3 then
      if not exists (select 1 from public.agent_actions a
                      where a.agent = 'customer_support' and a.kind = 'customer_terms_resign' and a.target_id = r.id::text
                        and (a.detail ->> 'tos_accepted_at')::timestamptz = r.tos_accepted_at and a.status = 'needs_review') then
        insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
        values ('customer_support', 'customer_terms_resign', 'needs_review', 'medium',
                'Customer terms certificate still missing after 3 re-signs — customer ' || left(r.id::text, 8),
                'The customer accepted the terms and the signed certificate never landed after the first post and 3 re-signs. Read the compliance_archive agent_runs rows (cert_render_failed / cert_record_failed) and the it_engineer finding certificate_not_recorded:customer; once the cause is fixed, select public.fn_customer_support_resigns_unsigned_terms(''<id>''::uuid) posts it again.',
                jsonb_build_object('customer_id', r.id, 'tos_accepted_at', r.tos_accepted_at, 'attempts', v_prior),
                'customers', r.id::text);
        v_escalated := v_escalated + 1;
      end if;
      continue;
    end if;
    if v_last is not null and v_last > now() - interval '5 minutes' then v_waiting := v_waiting + 1; continue; end if;

    perform net.http_post(
      'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
      jsonb_build_object('__secret', v_secret, 'action', 'sign', 'kind', 'customer', 'id', r.id),
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('customer_support', 'customer_terms_resign', 'auto_done', 'low',
            'Customer terms certificate signed again (attempt ' || (v_prior + 1) || ' of 3) — customer ' || left(r.id::text, 8),
            'No action required. The customer accepted the terms more than 5 minutes ago and no signed certificate had landed for that acceptance, so the sign request was posted again. compliance_archive returns the existing certificate if one has since landed.',
            jsonb_build_object('customer_id', r.id, 'tos_accepted_at', r.tos_accepted_at, 'attempt', v_prior + 1),
            'customers', r.id::text);
    v_posted := v_posted + 1;
  end loop;
  return jsonb_build_object('ok', true, 'posted', v_posted, 'waiting', v_waiting, 'escalated', v_escalated);
end
$fn$;
revoke execute on function public.fn_customer_support_resigns_unsigned_terms(uuid) from public, anon, authenticated;

create or replace function public.fn_it_engineer_finds_people_working_without_an_acceptance()
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; k text; v_real int; v_ids jsonb;
begin
  with s as (
    select 'customer_active_without_acceptance' st, coalesce(c.is_demo, false) demo, c.id::text id
      from public.customers c where c.tos_accepted_at is null and not coalesce(c.banned, false)
       and exists (select 1 from public.inquiries i where i.customer_id = c.id)
    union all
    select 'supplier_active_without_acceptance', coalesce(l.is_demo, false), l.id::text
      from public.leads l where l.claimed_by is not null and l.accepted_terms_at is null and not coalesce(l.banned, false)
       and (l.registration_submitted_at is not null or l.approval_status = 'approved')
    union all
    select 'customer_acceptance_without_certificate', coalesce(c.is_demo, false), c.id::text
      from public.customers c where c.tos_accepted_at < now() - interval '30 minutes'
       and (c.signed_terms_path is null or c.signed_terms_at is null or c.signed_terms_at < c.tos_accepted_at)
    union all
    select 'supplier_acceptance_without_certificate', coalesce(l.is_demo, false), l.id::text
      from public.leads l where l.accepted_terms_at < now() - interval '30 minutes' and l.claimed_by is not null
       and (l.signed_terms_path is null or l.signed_terms_at is null or l.signed_terms_at < l.accepted_terms_at))
  select coalesce(jsonb_object_agg(st, jsonb_build_object('real', real_n, 'demo', demo_n, 'real_ids', real_ids)), '{}'::jsonb) into v
    from (select st, count(*) filter (where not demo) real_n, count(*) filter (where demo) demo_n,
                 coalesce(jsonb_agg(id order by id) filter (where not demo), '[]'::jsonb) real_ids
            from s group by st) g;

  for k in select jsonb_object_keys(v) loop
    v_real := (v -> k ->> 'real')::int; v_ids := v -> k -> 'real_ids';
    if v_real > 0 then
      perform public.fn_it_engineer_finding_upsert(
        'acceptance_gap:' || k,
        case k when 'customer_active_without_acceptance' then 'A customer with a request has no acceptance of the terms on record'
               when 'supplier_active_without_acceptance' then 'A supplier who submitted or is approved has no acceptance of the agreement on record'
               when 'customer_acceptance_without_certificate' then 'A customer''s acceptance has had no signed certificate for 30 minutes'
               else 'A supplier''s acceptance has had no signed certificate for 30 minutes' end,
        'public.' || case when k like 'customer%' then 'customers' else 'leads' end, 'customer_facing', v_real,
        jsonb_build_object('state', k, 'real', v_real, 'ids', v_ids, 'counted_at', now(),
          'what_to_do', case when k like '%without_acceptance' then 'Read kyc and supplier_api agent_runs for this person''s accept_terms (terms_not_recorded). The person is asked to accept again; never write an acceptance on their behalf.'
                             else 'The minute sweep has had its three tries: read compliance_archive agent_runs and the certificate_not_recorded finding, fix the cause, then post the sign again.' end),
        '{}'::text[], '{}'::text[], 'it_engineer');
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'states', v);
end
$fn$;
revoke execute on function public.fn_it_engineer_finds_people_working_without_an_acceptance() from public, anon, authenticated;

-- The jobs: the customer re-sign every minute as the supplier one does; the count every hour at :23.
select cron.schedule('customer_support_terms_resign', '* * * * *',
  $c$set statement_timeout = '50s'; select public.fn_customer_support_resigns_unsigned_terms();$c$);
select cron.schedule('it_engineer_acceptance_gap', '23 * * * *',
  $c$set statement_timeout = '50s'; select public.fn_it_engineer_finds_people_working_without_an_acceptance();$c$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('customer_support_terms_resign', 'a customer''s terms certificate that did not land is signed again', 'Customer experience',
   'Every minute: a customer who accepted the terms more than 5 minutes ago and has no signed certificate for that acceptance is '
   || 'signed again (at most 3 times, 5 minutes apart, each audited in agent_actions); the third failure goes to customer_support once.'),
  ('it_engineer_acceptance_gap', 'nobody works on the platform without an acceptance on record', 'IT',
   'Every hour: counts customers with a request and no acceptance, suppliers submitted or approved with no acceptance, and '
   || 'acceptances with no certificate after 30 minutes; a real one raises an it_engineer finding.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'customer_support_terms_resign', 'customer_support',
   'Every minute: fn_customer_support_resigns_unsigned_terms() posts compliance_archive sign again for a customer acceptance with no certificate after 5 minutes.',
   'scripts/sql/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.sql'),
  ('cron_job', 'it_engineer_acceptance_gap', 'it_engineer',
   'Every hour: fn_it_engineer_finds_people_working_without_an_acceptance() raises a finding for a real person active without an acceptance or a certificate.',
   'scripts/sql/a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- verdict (reads only: this file defines routines, so it must not raise)
select case
  when has_function_privilege('anon', 'public.fn_customer_support_resigns_unsigned_terms(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_customer_support_resigns_unsigned_terms(uuid)', 'execute')
    or has_function_privilege('anon', 'public.fn_it_engineer_finds_people_working_without_an_acceptance()', 'execute')
    or has_function_privilege('authenticated', 'public.fn_it_engineer_finds_people_working_without_an_acceptance()', 'execute')
    then 'PROBE FAILED: a sweep is executable by anon or authenticated'
  when (select count(*) from cron.job where jobname in ('customer_support_terms_resign', 'it_engineer_acceptance_gap') and active) <> 2
    then 'PROBE FAILED: a sweep is not scheduled'
  else 'PROBE OK' end as verdict;
