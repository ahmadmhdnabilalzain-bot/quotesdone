-- THE LICENCE EXPIRY SCAN ACTS (3 Sep 2026).
--
-- What the scorer found (s26-verify-documentation): the expiry scan's cron (doc_expiry_daily, job 59)
-- had never succeeded through the kernel, and what fn_doc_expiry_scan did when it ran was "detect ->
-- email the founder": a notifications row to admin_emails per expiring document, and nothing else.
-- That is the shape the founder ruled out on 2 Sep — an alert is the record of what the agent did,
-- never a hand-off asking him to do it.
--
-- Now, for every approved supplier with a trade licence, insurance, registration, ISO or manufacturer
-- authorisation expiring within 30 days or already expired, the scan:
--   1. writes the renewal request to the SUPPLIER into the outbox (notifications, to_role supplier).
--      It is 'queued' only when the recipient is a reserved .invalid fixture address or the founder's
--      go for supplier outbound is on (app_secrets.invite_enabled = 'true', the same gate the invite
--      campaign uses); otherwise it sits 'held', which send_outbox never picks up. Not a second gate:
--      the one flag that means "we may write to real suppliers" governs both.
--   2. suspends matching for an approved supplier whose licence is past its date and restores it when
--      the date is renewed — fn_reconcile_licence_blocks(0), which already existed and nothing called;
--   3. records the action on agent_actions (kind licence_expiring / licence_expired) addressed to the
--      supplier_verification seat, once per document per 20 days — the same dedupe window the
--      onboarding agent uses for the same kind — with what was done in the detail.
-- No row is written to the founder. The 20-day dedupe on the outbox means a supplier is asked at
-- most every 20 days, not daily.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_engine_doc_expiry_scan_acts.sql --apply --ddl

create or replace function public.fn_doc_expiry_scan()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  rec record; v_go boolean; v_status text; v_n_actions int := 0; v_n_requests int := 0; v_n_held int := 0;
  v_blocks json; v_site text; v_reply text;
begin
  v_go := coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true';
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  select coalesce(nullif(btrim(value), ''), 'docs@mail.quotesdone.com') into v_reply from app_secrets where key = 'email_reply_supplier_docs';

  for rec in
    select l.id, l.company_name, l.email, d.doc, d.exp, (d.exp < current_date) as expired
      from leads l
      cross join lateral (values
        ('trade licence', l.license_expiry),
        ('insurance', l.insurance_expiry),
        ('registration', l.registration_expires_at::date),
        ('ISO certification', l.iso_expiry),
        ('manufacturer authorisation', l.manufacturer_auth_expiry)) d(doc, exp)
     where coalesce(l.approval_status, '') = 'approved' and coalesce(l.banned, false) = false
       and d.exp is not null and d.exp <= current_date + 30
     order by d.exp, l.id
  loop
    -- 1. the renewal request to the supplier, into the outbox.
    if rec.email is not null and rec.email <> ''
       and not exists (select 1 from notifications n
                        where n.type = 'doc_renewal_request' and n.lead_id = rec.id
                          and n.subject like '%' || rec.doc || '%' and n.created_at > now() - interval '20 days') then
      v_status := case when v_go or rec.email ~* '@example[.]invalid$' then 'queued' else 'held' end;
      insert into notifications (type, to_email, to_role, lead_id, channel, status, subject, body, last_error)
      values ('doc_renewal_request', rec.email, 'supplier', rec.id, 'email', v_status,
              case when rec.expired then 'Action needed: your ' || rec.doc || ' on QuotesDone has expired'
                   else 'Your ' || rec.doc || ' on QuotesDone expires on ' || to_char(rec.exp, 'DD Mon YYYY') end,
              'Dear ' || coalesce(nullif(btrim(rec.company_name), ''), 'supplier') || ',' || E'\n\n'
              || case when rec.expired
                      then 'The ' || rec.doc || ' on your QuotesDone supplier profile expired on ' || to_char(rec.exp, 'DD Mon YYYY')
                           || '. Until a valid document is on file your company is not matched to new requests for quotation.'
                      else 'The ' || rec.doc || ' on your QuotesDone supplier profile expires on ' || to_char(rec.exp, 'DD Mon YYYY')
                           || '. To keep receiving requests for quotation without interruption, please upload the renewed document before that date.' end
              || E'\n\n' || 'Upload it in your supplier portal: ' || v_site || '/en/portal' || E'\n'
              || 'or reply to this email with the document attached (' || v_reply || ').' || E'\n\n'
              || 'QuotesDone Supplier Verification',
              case when v_status = 'held' then 'HELD by fn_doc_expiry_scan: supplier outbound waits for the founder''s go (app_secrets.invite_enabled).' end);
      v_n_requests := v_n_requests + 1;
      if v_status = 'held' then v_n_held := v_n_held + 1; end if;
    end if;

    -- 3. the record of it, once per document per 20 days.
    if not exists (select 1 from agent_actions a
                    where a.kind in ('licence_expiring', 'licence_expired') and a.target_table = 'leads'
                      and a.target_id = rec.id::text and a.title like '%' || rec.doc || '%'
                      and a.created_at > now() - interval '20 days') then
      insert into agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id,
                                 confidence, evidence, decided_by, decided_at, expected_impact, cost)
      values ('supplier_verification',
              case when rec.expired then 'licence_expired' else 'licence_expiring' end,
              'auto_done', case when rec.expired then 'medium' else 'low' end,
              coalesce(nullif(btrim(rec.company_name), ''), 'Supplier #' || rec.id) || ' — ' || rec.doc
              || case when rec.expired then ' EXPIRED on ' else ' expires on ' end || to_char(rec.exp, 'DD Mon YYYY'),
              case when rec.expired
                   then 'Renewal request written to the supplier outbox; matching suspended by fn_reconcile_licence_blocks until the date on file is renewed.'
                   else 'Renewal request written to the supplier outbox ' || (rec.exp - current_date) || ' day(s) ahead; matching is suspended automatically on the day it lapses.' end,
              jsonb_build_object('document', rec.doc, 'expires_on', rec.exp, 'days_left', rec.exp - current_date,
                                 'renewal_request', case when rec.email is null or rec.email = '' then 'no email on file'
                                                         when v_go or rec.email ~* '@example[.]invalid$' then 'queued' else 'held' end,
                                 'supplier_outbound_go', v_go),
              'leads', rec.id::text, 1.0,
              jsonb_build_object('basis', 'leads.' || case rec.doc when 'trade licence' then 'license_expiry' when 'insurance' then 'insurance_expiry'
                                                                    when 'registration' then 'registration_expires_at' when 'ISO certification' then 'iso_expiry'
                                                                    else 'manufacturer_auth_expiry' end || ' read by fn_doc_expiry_scan on ' || current_date),
              'doc_expiry_scan', now(),
              'An approved supplier with a lapsed document is not matched; a renewed one keeps its supply available.',
              'No spend: one outbox email; the supplier bears the renewal fee.');
      v_n_actions := v_n_actions + 1;
    end if;
  end loop;

  -- 2. the suspension and the restoration, from the dates on file.
  v_blocks := public.fn_reconcile_licence_blocks(0);

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('doc_expiry_scan', now(), now(), 'ok',
          jsonb_build_object('actions', v_n_actions, 'renewal_requests', v_n_requests, 'held', v_n_held,
                             'suspended', (v_blocks->>'suspended')::int, 'restored', (v_blocks->>'restored')::int,
                             'supplier_outbound_go', v_go),
          'Document expiry scan: ' || v_n_actions || ' action(s) recorded, ' || v_n_requests
          || ' renewal request(s) written to the outbox (' || v_n_held || ' held pending the founder''s go), '
          || (v_blocks->>'suspended') || ' supplier(s) suspended for a lapsed licence, '
          || (v_blocks->>'restored') || ' restored.');

  return jsonb_build_object('actions', v_n_actions, 'renewal_requests', v_n_requests, 'held', v_n_held,
                            'suspended', (v_blocks->>'suspended')::int, 'restored', (v_blocks->>'restored')::int,
                            'supplier_outbound_go', v_go, 'scanned_at', now());
end $function$;
