-- WHATSAPP ANSWERS EVERY HELLO WITH A WELCOME AND A MENU, AND A REFUSED HELLO IS NEVER SILENT AGAIN.
--
-- Assigned: customer_support (owns WhatsApp and every send). 22 Sep 2026. Founder_instruction 759:
-- "I texted our WhatsApp number from my WhatsApp, said hi, got no response. Even without the LLM there
-- should be automatic replies: a professional welcome message and options (general inquiry/information,
-- existing inquiry, new inquiry, report a problem) for customers and suppliers, not simple text."
--
-- MEASURED 22 Sep 2026 (production, read-only):
--   - wa_messages holds exactly two inbound messages that ever reached the webhook since the signature
--     check went live (id 45, 10 Sep "Test"; id 245, 22 Sep 12:19Z "Hi"), both the founder's, both
--     meta.signature_valid=false "signature mismatch", no_autoreply_reason "failed X-Twilio-Signature".
--   - function_edge_logs: Twilio POSTed to https://<ref>.supabase.co/functions/v1/wa_inbound (403).
--     agent_runs fn:wa_inbound counts.path = '/wa_inbound' for the same run: inside the runtime the
--     /functions/v1 prefix is stripped, and wa_inbound signed-URL rebuild used that path. Root cause,
--     fixed in supabase/functions/wa_inbound/signature.ts. app_secrets.twilio_auth_token authenticates
--     against the account (GET of the 22 Sep message with it returned 200), so the key was right.
--   - Nothing noticed for twelve days: a refused webhook raised a throttled founder_alerts row and an
--     agent_runs error, and no IT finding.
--
-- WHAT THIS CHANGES
--   1. founder_mail_policy 'whatsapp_human_request': a person who picks "Talk to a person" from the menu
--      reaches the founder at once (email; WhatsApp where fn_notify_founder routes it), deduped per
--      number per day by the caller. Owner customer_support.
--   2. fn_wa_menu_context(phone): who is writing, by the CONFIRMED number only (fn_identify_contact and
--      fn_whatsapp_owner — a phone may confirm, never select), their name, supplier approval, and a
--      customer's own open requests (rfq_no, status, date; at most five). Nothing for anyone else.
--   3. fn_wa_problem_report(phone, text, lang): "Report a problem" -> a support_case row with a
--      reference QD-S-XXXXXX, owner customer_support, identity_verified only for a confirmed number.
--      The case already appears on the contact's timeline (fn_contact_timeline reads support_case).
--   4. The IT watch: an AFTER INSERT trigger on wa_messages. A row refused at the door
--      (meta.signature_valid=false) upserts it_engineer_finding 'wa_inbound:signature_refused',
--      customer_facing, affected = distinct senders refused in 24h. The next inbound that passes
--      verification closes it. Event-driven on purpose: it needs no scheduler to notice, so the first
--      refused hello is a finding, not the twelfth day.
--
-- WHAT THIS DOES NOT CHANGE
--   - wa_daily_cap / wa_per_recipient_24h: measured in send_whatsapp, they govern the notifications
--     outbox (business-initiated notices). Menu replies go through wa_inbound's sendWa inside the
--     session the person opened, never the outbox, so the caps cannot block a conversation. Unchanged.
--   - the Content SIDs of the interactive menu are written by scripts/whatsapp/create_menu_content.mjs
--     into app_secrets.wa_menu_content_sids after deploy; until then the menu goes as numbered text.
--   - fn_it_detect / fn_it_duties: untouched; the watch is its own trigger.
--
--   node scripts/apply_sql.mjs scripts/sql/whatsapp_answers_every_hello_with_a_welcome_and_a_menu.sql --apply --ddl
--   then: scripts/sql/whatsapp_answers_every_hello_with_a_welcome_and_a_menu_probe.sql (verdict row)

-- ── 1. THE FOUNDER HEARS WHEN SOMEONE ASKS FOR A PERSON ─────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('whatsapp_human_request', true,
        'founder_instruction 759 (22 Sep 2026): a person who chooses "Talk to a person" on the WhatsApp menu is told a member of the team will contact them, so the founder is told at once. One per number per day.',
        'customer_support')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
                                 owner_role = excluded.owner_role, updated_at = now();

-- ── 2. WHO IS WRITING, AND THEIR OWN OPEN REQUESTS ──────────────────────────────────────────────
create or replace function public.fn_wa_menu_context(p_phone text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id json; v_aud text; v_cust uuid; v_reqs jsonb := '[]'::jsonb;
begin
  v_id  := public.fn_identify_contact(p_phone);
  v_aud := coalesce(v_id ->> 'audience', 'unknown');
  if v_aud = 'customer' then
    select o.customer_id into v_cust from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'customer';
    if v_cust is not null then
      select coalesce(jsonb_agg(jsonb_build_object('rfq_no', i.rfq_no, 'status', i.status, 'created_at', i.created_at)
                                order by i.created_at desc), '[]'::jsonb)
        into v_reqs
        from (select rfq_no, status, created_at from public.inquiries
               where customer_id = v_cust and completed_at is null
                 and coalesce(status, '') not in ('closed', 'cancelled', 'completed', 'lost')
               order by created_at desc limit 5) i;
    end if;
  end if;
  return jsonb_build_object('audience', v_aud, 'name', v_id ->> 'name',
                            'approved', coalesce((v_id ->> 'approved')::boolean, false), 'requests', v_reqs);
end $fn$;
revoke execute on function public.fn_wa_menu_context(text) from public, anon, authenticated;

-- ── 3. "REPORT A PROBLEM" BECOMES A CASE WITH A REFERENCE ──────────────────────────────────────
create or replace function public.fn_wa_problem_report(p_phone text, p_text text, p_lang text default 'en')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 32 symbols, no 0/O/1/I (as fn_complaint_open)
  v_kind text; v_cust uuid; v_lead bigint; v_ref text; v_id bigint; v_bytes bytea; i int; attempt int := 0;
begin
  if coalesce(btrim(p_text), '') = '' then raise exception 'fn_wa_problem_report: empty report'; end if;
  select o.party_kind, o.customer_id, o.lead_id into v_kind, v_cust, v_lead from public.fn_whatsapp_owner(p_phone) o;
  loop
    attempt := attempt + 1;
    v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_ref := 'QD-S-';
    for i in 0..5 loop v_ref := v_ref || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, verified_how, owner_role_id)
      values (v_ref, coalesce(v_kind, 'unknown'),
              coalesce(v_cust::text, v_lead::text, regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g')),
              'WhatsApp problem report (' || coalesce(nullif(p_lang, ''), 'en') || '): ' || left(btrim(p_text), 4000),
              'open', v_kind is not null, case when v_kind is not null then 'confirmed WhatsApp number' end, 'customer_support')
      returning case_id into v_id;
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;
  return jsonb_build_object('case_ref', v_ref, 'case_id', v_id, 'party_kind', coalesce(v_kind, 'unknown'));
end $fn$;
revoke execute on function public.fn_wa_problem_report(text, text, text) from public, anon, authenticated;

-- ── 4. A REFUSED HELLO IS A FINDING THE MOMENT IT HAPPENS ──────────────────────────────────────
create or replace function public.fn_wa_signature_watch()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n_rows int; n_senders int; v_last timestamptz;
begin
  if coalesce(new.meta ->> 'signature_valid', '') = 'false' then
    select count(*), count(distinct wa_from), max(created_at) into n_rows, n_senders, v_last
      from public.wa_messages
     where created_at > now() - interval '24 hours' and meta ->> 'signature_valid' = 'false';
    perform public.fn_it_engineer_finding_upsert(
      'wa_inbound:signature_refused',
      'Inbound WhatsApps are being refused at the door: ' || n_rows || ' failed X-Twilio-Signature in 24 hours, so nobody who wrote got an answer',
      'supabase/functions/wa_inbound (verifyTwilioSignature, signature.ts) and app_secrets.twilio_auth_token',
      'customer_facing', n_senders,
      jsonb_build_object('refused_24h', n_rows, 'senders_24h', n_senders, 'last_refused_at', v_last,
                         'last_reason', new.meta ->> 'signature_reason', 'urls_tried', new.meta -> 'signature_urls_tried',
                         'owner_seat', 'customer_support'),
      '{}'::text[],
      array['whether the refused request was a forgery or a genuine Twilio webhook signed over a URL or token we did not try'],
      'it_engineer.wa_signature_watch');
  elsif coalesce(new.meta ->> 'signature_valid', '') = 'true' or coalesce(new.meta ->> 'provenance_verified', '') = 'true' then
    if exists (select 1 from public.it_engineer_finding where issue_key = 'wa_inbound:signature_refused' and closed_at is null) then
      perform public.fn_it_engineer_finding_close('wa_inbound:signature_refused',
        'an inbound WhatsApp passed verification at ' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z (wa_messages ' || new.id || ')');
    end if;
  end if;
  return null;
exception when others then
  -- The watch must never cost the message row it is watching.
  raise warning 'fn_wa_signature_watch: %', sqlerrm;
  return null;
end $fn$;
revoke execute on function public.fn_wa_signature_watch() from public, anon, authenticated;

drop trigger if exists trg_wa_signature_watch on public.wa_messages;
create trigger trg_wa_signature_watch after insert on public.wa_messages
  for each row execute function public.fn_wa_signature_watch();
