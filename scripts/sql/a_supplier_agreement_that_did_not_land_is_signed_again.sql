-- a_supplier_agreement_that_did_not_land_is_signed_again
-- Seat: sales_engineer (supplier registration). 10 Nov 2026. Founder, 10 Nov 2026: supplier registration must work 100%.
--
-- MEASURED (docs/reports/2026-11-10-launch-verification.md, should-fix 4): the signed Supplier Agreement is produced
-- asynchronously - z21_sign_supplier_on_acceptance (qd_sign_supplier) posts once to compliance_archive 'sign' through
-- pg_net, and nothing posts again. In 1 of 13 fixtures the signed PDF had not landed after 60 s. fn_supplier_mandatory_six
-- counts the agreement only once leads.signed_terms_path is set, so a supplier whose one post was lost (pdf_native slow,
-- a worker retired, a pg_net timeout) sat 'action_required' (reg_terms) with nothing left for him to do, until he
-- happened to save his profile again.
--
-- WHAT CHANGES: fn_sales_engineer_resigns_unsigned_agreements, every minute (cron job sales_engineer_agreement_resign,
-- owned by the sales engineer in writer_seat), posts the same 'sign' request again for every supplier who accepted the agreement more than 5 minutes
-- ago and has no certificate for that acceptance. Idempotent by construction: compliance_archive 'sign' returns the
-- existing certificate when one was issued at or after the acceptance, and writes a new one only by compare-and-set,
-- so a late first render and a re-sign can never leave two. At most 3 re-signs per acceptance, 5 minutes apart; each
-- one is an agent_actions row (kind supplier_agreement_resign, auto_done) and the third failure files ONE needs_review
-- row for the sales engineer. When the certificate lands, z20_leads_mandatory_item_landed_reverifies re-runs the gate
-- in the same update, as it does for the first post. Measured before this file: 0 accepted-but-unsigned suppliers on
-- production, so the first tick posts nothing.
-- The portal says "Signing your Supplier Agreement…" meanwhile (supplier_portal supplierCard.agreement_signing,
-- Dashboard.tsx), instead of "Action required: Signed supplier terms".
--
-- Prevented by: scripts/checks/a_supplier_agreement_that_did_not_land_is_signed_again.test.mjs (the sweep exists, is
-- scheduled, is bounded and idempotent; the portal says signing) and the probe
-- a_supplier_agreement_that_did_not_land_is_signed_again_probe.sql (a ZZ DEMO supplier accepted 6 minutes ago and unsigned
-- is re-signed once, audited, not twice in the same 5 minutes; a signed one is left alone; a 4th attempt files one review).

create or replace function public.fn_sales_engineer_resigns_unsigned_agreements(p_lead_id bigint default null)
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

  for r in select l.id, l.claimed_by, l.company_name, l.accepted_terms_at
             from public.leads l
            where l.accepted_terms_at is not null and l.claimed_by is not null and not coalesce(l.banned, false)
              and (p_lead_id is null or l.id = p_lead_id)   -- one lead: the probe's own fixture, never anyone else
              and (l.signed_terms_path is null or l.signed_terms_at is null or l.signed_terms_at < l.accepted_terms_at)
              and l.accepted_terms_at < now() - interval '5 minutes'
            order by l.accepted_terms_at limit 20 loop
    select count(*), max(a.created_at) into v_prior, v_last
      from public.agent_actions a
     where a.agent = 'sales_engineer' and a.kind = 'supplier_agreement_resign' and a.target_id = r.id::text
       and (a.detail ->> 'accepted_terms_at')::timestamptz = r.accepted_terms_at and a.status = 'auto_done';
    if v_prior >= 3 then
      -- Three re-signs did not land: one row for a person, once per acceptance.
      if not exists (select 1 from public.agent_actions a
                      where a.agent = 'sales_engineer' and a.kind = 'supplier_agreement_resign' and a.target_id = r.id::text
                        and (a.detail ->> 'accepted_terms_at')::timestamptz = r.accepted_terms_at and a.status = 'needs_review') then
        insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
        values ('sales_engineer', 'supplier_agreement_resign', 'needs_review', 'medium',
                'Supplier Agreement still unsigned after 3 re-signs — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
                'The supplier accepted the Supplier Agreement and the signed certificate never landed after the first post and 3 re-signs. Read the compliance_archive agent_runs rows for this supplier (cert_render_failed / cert_record_failed) and the pdf_native logs; once the cause is fixed the next re-sign is posted by hand: select net.http_post(... ''sign'' ...) as qd_sign_supplier does.',
                jsonb_build_object('supplier_id', r.id, 'accepted_terms_at', r.accepted_terms_at, 'attempts', v_prior),
                'leads', r.id::text);
        v_escalated := v_escalated + 1;
      end if;
      continue;
    end if;
    if v_last is not null and v_last > now() - interval '5 minutes' then v_waiting := v_waiting + 1; continue; end if;

    perform net.http_post(
      'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
      jsonb_build_object('__secret', v_secret, 'action', 'sign', 'kind', 'supplier', 'email', r.claimed_by),
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_agreement_resign', 'auto_done', 'low',
            'Supplier Agreement signed again (attempt ' || (v_prior + 1) || ' of 3) — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
            'No action required. The supplier accepted the Supplier Agreement more than 5 minutes ago and no signed certificate had landed for that acceptance, so the sign request was posted again. compliance_archive returns the existing certificate if one has since landed.',
            jsonb_build_object('supplier_id', r.id, 'accepted_terms_at', r.accepted_terms_at, 'attempt', v_prior + 1),
            'leads', r.id::text);
    v_posted := v_posted + 1;
  end loop;
  return jsonb_build_object('ok', true, 'posted', v_posted, 'waiting', v_waiting, 'escalated', v_escalated);
end
$fn$;
revoke execute on function public.fn_sales_engineer_resigns_unsigned_agreements(bigint) from public, anon, authenticated;

-- Finding nothing must be cheap: the partial index is empty on a quiet day.
create index if not exists leads_accepted_unsigned_idx on public.leads (accepted_terms_at)
  where accepted_terms_at is not null and (signed_terms_path is null or signed_terms_at is null or signed_terms_at < accepted_terms_at);

-- The job: every minute, owned by the sales engineer (seat_duty refuses anything under 5 minutes; owned the way
-- reask_refused_turns is).
select cron.schedule('sales_engineer_agreement_resign', '* * * * *',
  $c$set statement_timeout = '50s'; select public.fn_sales_engineer_resigns_unsigned_agreements();$c$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('sales_engineer_agreement_resign', 'a Supplier Agreement that did not land is signed again', 'Supplier growth',
   'Every minute: a supplier who accepted the Supplier Agreement more than 5 minutes ago and has no signed certificate for that '
   || 'acceptance is signed again (at most 3 times, 5 minutes apart, each audited in agent_actions); the third failure goes to '
   || 'the sales engineer once.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'sales_engineer_agreement_resign', 'sales_engineer',
   'Every minute: fn_sales_engineer_resigns_unsigned_agreements() posts compliance_archive sign again for an acceptance with no certificate after 5 minutes.',
   'scripts/sql/a_supplier_agreement_that_did_not_land_is_signed_again.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- verdict (reads only: this file defines a routine, so it must not raise)
select case
  when has_function_privilege('anon', 'public.fn_sales_engineer_resigns_unsigned_agreements(bigint)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_sales_engineer_resigns_unsigned_agreements(bigint)', 'execute')
    then 'PROBE FAILED: the sweep is executable by anon or authenticated'
  when not exists (select 1 from cron.job where jobname = 'sales_engineer_agreement_resign' and schedule = '* * * * *' and active)
    then 'PROBE FAILED: the sweep is not scheduled'
  else 'PROBE OK' end as verdict;
