-- A RENEWAL REMINDER IS NOT AN INVITATION
--
-- fn_doc_expiry_scan finds every supplier document about to expire, writes the renewal request to
-- the supplier outbox, and suspends matching on the day it lapses. It held every one of those
-- requests behind app_secrets.invite_enabled -- the COLD OUTREACH campaign switch.
--
-- Those are two different things sharing one switch. Inviting a stranger to register is outreach,
-- and it is rightly rate-limited and rightly off by default. Telling a supplier who is already
-- registered that the trade licence THEY gave us expires in three weeks is service mail to an
-- address on their own record. Withholding it does not protect them; it just means the first they
-- hear of it is being suspended from matching.
--
-- The gate is deleted rather than defaulted to true, so nothing can quietly close it again.
-- Founder ruling, 7 Sep 2026: every gate that is not OpenRouter comes off.
CREATE OR REPLACE FUNCTION public.fn_doc_expiry_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_go boolean; v_status text; v_n_actions int := 0; v_n_requests int := 0; v_n_held int := 0;
  v_blocks json; v_site text; v_reply text;
begin
  -- A RENEWAL REMINDER IS NOT AN INVITATION. v_go used to read app_secrets.invite_enabled, the
  -- cold-outreach campaign switch, so a supplier already on the books could not be told their own
  -- trade licence was about to lapse until a marketing campaign was running. Two unrelated things
  -- were sharing one switch: asking a stranger to join, and telling a member their document
  -- expires. The second is service mail to someone who gave us the document in the first place,
  -- it goes to an address already on their record, and withholding it is worse for them than
  -- sending it -- matching is suspended automatically on the day the licence lapses either way.
  --
  -- Founder ruling 7 Sep 2026: every gate that is not OpenRouter comes off. This one comes off by
  -- being deleted rather than defaulted, so nothing can quietly close it again.
  v_go := true;
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
