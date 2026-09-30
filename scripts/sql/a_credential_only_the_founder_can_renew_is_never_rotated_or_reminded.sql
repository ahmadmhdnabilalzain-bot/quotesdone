-- A CREDENTIAL ONLY THE FOUNDER CAN RENEW IS NEVER ROTATED OR REMINDED (30 Sep 2026; seat: it_engineer).
--
-- FOUNDER RULING (ledger 1090, 30 Sep 2026): keep automatic rotation for every credential the company can rotate
-- by itself through a provider API. For Meta and ANY credential that would need the founder (an OAuth sign-in, a
-- console-only key): ignore it. No rotation attempt, no reminder, no email or WhatsApp to him about rotating or
-- renewing it. Real outages are still handled: the IT engineer still records every break.
--
-- MEASURED (30 Sep 2026, production): three paths could reach him, or reach someone on his behalf, about renewing
-- a credential only he can renew:
--   1. fn_it_integration_settle mails kind integration_reauth_needed ("reconnect needed") for any integration
--      finding open two beats. #1132 exempts only a permission refusal inside a company rotation's overlap.
--   2. fn_customer_support_sends_the_it_digest (19:00 Dubai) lists every it_new_bug finding open more than 24 h,
--      which includes a refused or expired founder credential.
--   3. fn_it_renewal_watch hands every it_expiry 'key:*' / 'token:*' item inside its 60/30-day stage to the
--      accountant (renewal.due) and escalates it to the CEO. The route text of 13 of them says "the founder
--      rotates it in the provider dashboard": a reminder chain that ends at him.
-- Rotation ATTEMPTS were already confined: fn_it_provider_rotation_keys defines only Twilio, so no other provider
-- is ever claimed. Internal credentials (internal_credential, cred_*) are the company's own and keep rotating.
--
-- THE CHANGE:
--   * public.it_credential_class: every third-party credential, company_api (rotated by the IT engineer through the
--     provider API) or founder_required, with the integration probes that authenticate with it and its it_expiry item.
--   * fn_it_credential_founder_required(issue_key, title, evidence): is this finding about renewing one of the
--     founder_required credentials? renewal:<item> of one; credential:<provider> of one; integration(_social):<x>
--     of one AND the failure is a credential refusal or a reconnect link. A 522 or a 5xx on the same integration is
--     an outage, not a renewal, and keeps its path.
--   * The three paths above ask it first: a founder-required credential is recorded as an IT engineer finding
--     marked founder_required_credential (visible on the OS), and nothing is mailed, digested, handed or escalated.
--     Renewal handoffs already open for one are withdrawn with that verdict.
--   * it_expiry.route for those items no longer says the founder rotates it.
-- Prevented by: scripts/checks/a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.test.mjs
--   (ZZ DEMO probe in an aborted transaction; fails if any of the three paths notices a founder-required credential,
--   if the classifier silences a non-credential outage, or if Twilio stops rotating on schedule).
--   node scripts/apply_sql.mjs scripts/sql/a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.sql --apply --ddl --seat it_engineer

create table if not exists public.it_credential_class (
  credential   text primary key,                 -- the app_secrets key name, never its value
  rotation     text not null check (rotation in ('company_api', 'founder_required')),
  integrations text[] not null default '{}',     -- integration_registry.json keys whose probe uses it
  expiry_item  text,                             -- the public.it_expiry item that dates it, if any
  why          text not null,
  recorded_at  timestamptz not null default now()
);
alter table public.it_credential_class enable row level security;
drop policy if exists it_credential_class_service_role_only on public.it_credential_class;
create policy it_credential_class_service_role_only on public.it_credential_class
  as permissive for all to public using (false) with check (false);
revoke all on public.it_credential_class from anon, authenticated;
-- The daily export carries it: credential NAMES and their class, never a value.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('it_credential_class', true, 'company', 'which third-party credential the company rotates by API and which only the founder can renew (names only; founder ruling 1090)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

insert into public.it_credential_class (credential, rotation, integrations, expiry_item, why) values
  ('twilio_api_key_secret', 'company_api', '{twilio,twilio_verify,twilio_whatsapp_sender}', 'key:twilio_api_key_secret',
   'the IT engineer creates and deletes Twilio Standard API keys with the account credentials (_shared/it_rotate_by_api.ts)'),
  ('twilio_auth_token', 'founder_required', '{}', 'key:twilio_auth_token', 'the primary auth token is changed in the Twilio console'),
  ('stripe_secret_key', 'founder_required', '{stripe,stripe_webhook}', 'key:stripe_secret_key', 'rolled in the Stripe dashboard'),
  ('stripe_secret_key_test', 'founder_required', '{stripe_test}', null, 'rolled in the Stripe dashboard'),
  ('stripe_webhook_secret', 'founder_required', '{}', 'key:stripe_webhook_secret', 'rolled in the Stripe dashboard'),
  ('resend_api_key', 'founder_required', '{resend}', 'key:resend_api_key', 'made in the Resend console'),
  ('resend_inbound_signing_secret', 'founder_required', '{}', 'key:resend_inbound_signing_secret', 'made in the Resend console'),
  ('resend_webhook_signing_secret', 'founder_required', '{}', 'key:resend_webhook_signing_secret', 'made in the Resend console'),
  ('openrouter_api_key', 'founder_required', '{openrouter}', 'key:openrouter_api_key', 'made in the OpenRouter console'),
  ('dropbox_refresh_token', 'founder_required', '{dropbox}', 'key:dropbox_refresh_token', 'an OAuth sign-in by the account holder'),
  ('dropbox_app_secret', 'founder_required', '{}', 'key:dropbox_app_secret', 'made in the Dropbox app console'),
  ('github_token', 'founder_required', '{github}', 'key:github_token', 'a personal token made in GitHub settings'),
  ('vercel_token', 'founder_required', '{vercel}', 'key:vercel_token', 'made in the Vercel dashboard'),
  ('cloudconvert_api_key', 'founder_required', '{cloudconvert}', null, 'made in the CloudConvert dashboard'),
  ('virustotal_api_key', 'founder_required', '{virustotal}', null, 'made in the VirusTotal account'),
  ('meta_access_token', 'founder_required', '{meta}', 'token:meta_marketing', 'Meta: minted in Business Settings (the ruling names Meta)'),
  ('postiz_api_key', 'founder_required', '{postiz,linkedin,tiktok_business}', null, 'the Postiz console, and each channel is an OAuth sign-in in Postiz'),
  ('youtube_oauth', 'founder_required', '{google_youtube}', null, 'an OAuth sign-in by the channel owner')
on conflict (credential) do update set rotation = excluded.rotation, integrations = excluded.integrations,
  expiry_item = excluded.expiry_item, why = excluded.why;

-- Is this finding about renewing or rotating a credential only the founder can renew?
create or replace function public.fn_it_credential_founder_required(p_issue_key text, p_title text default null, p_evidence jsonb default '{}'::jsonb)
returns boolean language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare s text := regexp_replace(coalesce(p_issue_key, ''), '^duty:', ''); v_x text;
begin
  if s ~ '^renewal:' then
    v_x := regexp_replace(regexp_replace(s, '^renewal:', ''), ':date_unknown$', '');
    return exists (select 1 from public.it_credential_class where rotation = 'founder_required' and expiry_item = v_x);
  elsif s ~ '^credential:' then
    v_x := regexp_replace(s, '^credential:', '');
    return exists (select 1 from public.it_credential_class where rotation = 'founder_required' and v_x = any (integrations));
  elsif s ~ '^integration(_social)?:' then
    v_x := split_part(regexp_replace(s, '^integration(_social)?:', ''), ':', 1);
    if not exists (select 1 from public.it_credential_class where rotation = 'founder_required' and v_x = any (integrations)) then
      return false;
    end if;
    -- Only a credential failure is a renewal. An outage on the same integration keeps its path.
    return coalesce(p_evidence->>'reconnect_link', '') <> ''
        -- What broke only: the title's "Tried:" and "Needs:" tail is registry prose and would match any row.
        or concat_ws(' ', split_part(coalesce(p_title, ''), '. Tried:', 1), p_evidence->>'what_broke')
           ~* '(HTTP 40[13]|"code":\s*(20003|70004|190)\M|\(#190\)|invalid_grant|unauthorized_client|OAuthException|refused the company''s (API )?key|invalid.{0,20}(api key|token|credential)|expired.{0,20}token|token.{0,20}expired|not connected)';
  end if;
  return false;
end $fn$;
revoke execute on function public.fn_it_credential_founder_required(text, text, jsonb) from public, anon, authenticated;

-- The route no longer tells anyone that the founder rotates it.
update public.it_expiry e
   set route = 'founder-required credential (founder ruling 1090, 30 Sep 2026): never rotated and never reminded; '
            || 'the IT engineer records its state silently. ' || c.why
  from public.it_credential_class c
 where c.expiry_item = e.item and c.rotation = 'founder_required' and e.route not like 'founder-required credential%';
update public.it_expiry e
   set route = 'rotated by the IT engineer through the provider API every credential_rotate_days (fn_it_provider_rotation_*)'
  from public.it_credential_class c
 where c.expiry_item = e.item and c.rotation = 'company_api';

create or replace function public.fn_it_integration_settle(p_duty text, p_items jsonb, p_fixed jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb; f public.it_engineer_finding;
  v_stub boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_link text; v_detail text; v_dedupe text; v_note jsonb; n_mail int := 0; n_fixed int := 0;
  v_mailed jsonb := '[]'::jsonb; c public.it_integration_external_cause; m record; v_recovered text[] := '{}';
begin
  if p_duty not in ('integration', 'integration_social') then
    raise exception 'fn_it_integration_settle: duty must be integration or integration_social, not %', p_duty;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_typeof(coalesce(p_fixed, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_it_integration_settle(duty, items[], fixed[]): items and fixed must be arrays';
  end if;
  -- EVERY PROBE LEAVES A ROW (28 Sep 2026): one per integration measured this beat, passing or failing.
  insert into public.edge_health_probe (fn_key, last_beat_at, silent_minutes, verdict, note)
  select p_duty || ':' || (e->>'item'),
         case when coalesce((e->>'recovered')::boolean, false) then now() end,
         case when coalesce((e->>'recovered')::boolean, false) then 0 end,
         case when coalesce((e->>'recovered')::boolean, false) then 'ALIVE' else 'FAILING' end,
         case when coalesce((e->>'recovered')::boolean, false) then null else left(e->>'title', 500) end
    from jsonb_array_elements(p_items) e
   where not coalesce((e->>'carried')::boolean, false) and coalesce(e->>'item', '') <> '';
  -- A carried item holds an OPEN finding; one whose finding is closed is dropped, never reopened.
  -- A RECOVERED item is a successful re-probe, not a failure: it is kept out of the settle and remembered.
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce((x->>'recovered')::boolean, false) then v_recovered := v_recovered || (x->>'item'); continue; end if;
    if coalesce((x->>'carried')::boolean, false) and not exists (select 1 from public.it_engineer_finding
         where issue_key = 'duty:' || p_duty || ':' || (x->>'item') and closed_at is null) then
      continue;
    end if;
    v_items := v_items || x;
  end loop;
  v_res := public.fn_it_duty_settle(p_duty, v_items);
  -- The closed finding of an integration that answered its probe this beat says so. The evidence is replaced
  -- whenever the finding reopens, so the mark never outlives the closure it describes.
  update public.it_engineer_finding
     set evidence = evidence || jsonb_build_object('recovered', true, 'recovered_at', now())
   where closed_at is not null
     and issue_key = any (select 'duty:' || p_duty || ':' || r from unnest(v_recovered) r);

  -- What the company fixed itself: the IT daily line, never the founder.
  for x in select e from jsonb_array_elements(coalesce(p_fixed, '[]'::jsonb)) e loop
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'integration_self_fix', 'duty', p_duty, 'fix', x),
            left('fixed ' || coalesce(x->>'integration', '?') || ' itself: ' || coalesce(x->>'what_broke', ''), 500));
    n_fixed := n_fixed + 1;
  end loop;

  -- A KNOWN EXTERNAL CAUSE: follow the ticket up, and close the cause ONLY on a genuine recovery: the finding
  -- is closed AND a successful re-probe stamped it recovered. Any other closure (a sweep, a manual close) keeps
  -- the cause open, or the founder path would re-open without the provider having fixed anything.
  for c in select * from public.it_integration_external_cause where closed_at is null loop
    continue when not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:' || p_duty || ':' || c.integration);
    if exists (select 1 from public.it_engineer_finding where issue_key = 'duty:' || p_duty || ':' || c.integration
                  and closed_at is not null and closed_at >= c.created_at
                  and coalesce((evidence->>'recovered')::boolean, false)) then
      perform public.fn_it_external_cause_close(c.integration, 'the integration answers again; ' || c.external_party || ' ticket ' || c.ticket_ref || ' can be closed');
      continue;
    end if;
    -- The provider's reply, if it reached a company inbox: the newest inbound message naming the ticket.
    select i.created_at, coalesce(i.subject, '') || E'\n' || coalesce(i.body, '') txt into m
      from public.inbound_messages i
     where i.created_at > greatest(coalesce(c.last_reply_at, c.opened_on::timestamptz), c.opened_on::timestamptz)
       -- A literal substring, case-blind: a pattern match would read % and _ in a provider's reference as wildcards.
       and (strpos(lower(coalesce(i.subject, '')), lower(c.ticket_ref)) > 0
            or strpos(lower(coalesce(i.body, '')), lower(c.ticket_ref)) > 0)
     order by i.created_at desc limit 1;
    if found then perform public.fn_it_external_cause_reply(c.integration, m.created_at, m.txt); end if;
    update public.it_integration_external_cause set last_checked_at = now() where id = c.id;
  end loop;

  -- What it could not fix: the founder, once per open finding, after two beats.
  for f in select * from public.it_engineer_finding
            where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and seen_count >= 2
              and coalesce(evidence->>'notify', 'true') <> 'false' loop
    -- FOUNDER RULING 1090 (30 Sep 2026): a credential only the founder can renew (Meta, an OAuth sign-in, a
    -- console-only key) is never his reminder. The finding stays open and the IT engineer's, marked so the OS
    -- shows why nobody was told; a failure that is not a credential refusal still takes the path below.
    if public.fn_it_credential_founder_required(f.issue_key, f.title, f.evidence) then
      update public.it_engineer_finding
         set evidence = evidence || jsonb_build_object('founder_required_credential', true, 'founder_told', false,
                                                       'why_silent', 'founder ruling 1090: recorded, never rotated or reminded')
       where issue_key = f.issue_key and closed_at is null;
      continue;
    end if;
    select * into c from public.it_integration_external_cause
     where closed_at is null and 'duty:' || p_duty || ':' || integration = f.issue_key;
    if found then
      -- WAITING ON THE PROVIDER: he is told only when they replied AND the reply asks something of him, once.
      continue when not c.reply_needs_founder or c.founder_told_at is not null;
      v_dedupe := 'integration:' || f.issue_key || ':reply:' || to_char(c.last_reply_at, 'YYYYMMDDHH24MI');
      v_detail := c.external_party || ' replied on ticket ' || c.ticket_ref || ' about ' || c.integration
        || ', and the reply asks something of you.' || E'\n\n'
        || 'What broke: ' || f.title || E'\n'
        || 'Their reply (' || to_char(c.last_reply_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai): '
        || left(coalesce(c.last_reply_excerpt, ''), 900) || E'\n'
        || 'Where the thread is: ' || coalesce(c.thread_hint, 'the ticket ' || c.ticket_ref) || E'\n\n'
        || 'The IT engineer keeps re-checking every 15 minutes and closes this the moment it answers again (reference ' || f.issue_key || ').';
      if v_stub then v_note := jsonb_build_object('stubbed', true);
      else
        v_note := public.fn_notify_founder(p_event => 'IT engineer: ' || c.external_party || ' needs something from you on ' || c.integration,
          p_detail => v_detail, p_level => 'normal', p_kind => 'integration_reauth_needed', p_dedupe_key => v_dedupe,
          p_owner_agent => 'it_engineer');
      end if;
      update public.it_integration_external_cause set founder_told_at = now() where id = c.id;
      v_mailed := v_mailed || jsonb_build_object('key', f.issue_key, 'detail', v_detail, 'notice', v_note, 'external', true);
      n_mail := n_mail + 1;
      continue;
    end if;
    -- A KEY THE COMPANY ROTATED ITSELF: a permission refusal inside the rotation's overlap is the IT engineer's
    -- (probe endpoint or key scope), never a reconnect for the founder (29 Sep 2026, notification 78020).
    continue when (f.title ~* '(HTTP 40[13]|"code":\s*(20003|70004))' or coalesce(f.evidence->>'what_broke', '') ~* '(HTTP 40[13]|"code":\s*(20003|70004))')
      and exists (select 1 from public.it_credential_rotation r
                   where r.provider = regexp_replace(f.issue_key, '^duty:[a-z_]+:', '')
                     and r.status = 'overlap' and r.overlap_until > now());
    -- ONCE PER OPEN FINDING: the key is the finding and the moment it (re)opened. The finding's evidence is
    -- rewritten on every beat, so the record of having told him is founder_alerts, which fn_notify_founder writes.
    v_dedupe := 'integration:' || f.issue_key || ':' || to_char(f.started_at, 'YYYYMMDDHH24MI');
    continue when exists (select 1 from public.founder_alerts where dedupe_key = v_dedupe);
    v_link := coalesce(f.evidence->>'reconnect_url', '');
    if f.evidence->>'reconnect_link' in ('youtube', 'linkedin') and coalesce(f.evidence->>'connect_base', '') <> '' then
      v_link := (f.evidence->>'connect_base') || public.fn_marketing_social_connect_link(f.evidence->>'reconnect_link')
                || ' (one-time link, valid 24 hours)';
    end if;
    v_detail := 'The IT engineer found an integration down that the company could not fix itself.' || E'\n\n'
      || 'Integration: ' || coalesce(f.evidence->>'integration', f.evidence->>'channel', regexp_replace(f.issue_key, '^duty:[a-z_]+:', '')) || E'\n'
      || 'What broke: ' || f.title || E'\n'
      || 'What was tried: ' || coalesce((select string_agg(t, '; ') from jsonb_array_elements_text(f.evidence->'tried') t),
                                        'nothing the company can do: only the account holder can sign in again') || E'\n'
      || 'What you need to do: ' || coalesce(f.evidence->>'action', 'sign in again at the link') || E'\n'
      || 'Link: ' || coalesce(nullif(v_link, ''), 'none recorded') || E'\n\n'
      || 'Down since ' || to_char(f.started_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai. The IT engineer re-checks every 15 minutes and closes it the moment it answers again (reference ' || f.issue_key || ').';
    if v_stub then
      v_note := jsonb_build_object('stubbed', true);
    else
      -- The mail names its seat: customer_support is the only SENDER (founder, 14 Sep 2026; CHECK
      -- notifications_sender_is_customer_support), and the row's requested_by is it_engineer from
      -- founder_mail_policy.owner_role. The subject says who is asking so he reads it as the IT engineer's.
      v_note := public.fn_notify_founder(p_event => 'IT engineer: reconnect needed: ' || left(regexp_replace(f.issue_key, '^duty:[a-z_]+:', ''), 60),
        p_detail => v_detail, p_level => 'normal', p_kind => 'integration_reauth_needed', p_dedupe_key => v_dedupe,
        p_owner_agent => 'it_engineer');
    end if;
    v_mailed := v_mailed || jsonb_build_object('key', f.issue_key, 'detail', v_detail, 'notice', v_note);
    n_mail := n_mail + 1;
  end loop;
  return v_res || jsonb_build_object('fixed', n_fixed, 'founder_mailed', n_mail, 'mailed', v_mailed, 'stubbed', v_stub);
end $fn$;
revoke execute on function public.fn_it_integration_settle(text, jsonb, jsonb) from public, anon, authenticated;

create or replace function public.fn_customer_support_sends_the_it_digest(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
    if not found then v_why := null; end if;
    if v_why is null and f.started_at > p_now - interval '24 hours' then
      n_wait := n_wait + 1; continue;                          -- still young: judged again tomorrow
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'decision', v_why is not null, 'key', f.issue_key,
      'family', case when regexp_replace(f.issue_key, ':[^:]*$', '') ~ ':' then regexp_replace(f.issue_key, ':[^:]*$', '') else f.issue_key end,
      'title', regexp_replace(left(f.title, 140), '[.\s]+$', ''), 'since', f.started_at,
      'owner', coalesce(f.evidence->>'owner_seat', 'it_engineer'), 'why', v_why);
    if v_why is not null then n_dec := n_dec + 1; else n_flt := n_flt + 1; end if;
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

  -- One sentence per decision; faults of one family raised together are one sentence with their count.
  select string_agg(line, E'\n' order by decision desc, first_id)
    into v_detail
    from (select bool_or((i->>'decision')::boolean) decision, min((i->>'id')::bigint) first_id,
                 case when bool_or((i->>'decision')::boolean) then
                   '- DECISION: ' || min(i->>'title') || '. Only you can decide this: ' || min(i->>'why')
                   || '. The CEO keeps it open until you answer (reference ' || min(i->>'key') || ').'
                 else
                   '- ' || case when count(*) > 1 then count(*) || ' problems of one kind, e.g. ' else '' end
                   || min(i->>'title') || ', open since '
                   || to_char(min((i->>'since')::timestamptz) at time zone 'Asia/Dubai', 'DD Mon') || '. Nothing inside the company fixed it; the '
                   || replace(min(i->>'owner'), '_', ' ') || ' has it, the engineers are making the code or configuration change, and the IT engineer re-checks it every 15 minutes and closes it when it is gone (reference '
                   || case when count(*) > 1 then min(i->>'family') || ':...' else min(i->>'key') end || ').'
                 end line
            from jsonb_array_elements(v_items) i
           group by case when (i->>'decision')::boolean then i->>'key' else i->>'family' end) g;
  v_event := 'IT today: ' || case when n_dec > 0 then n_dec || ' decision' || case when n_dec > 1 then 's' else '' end || ' for you' else '' end
             || case when n_dec > 0 and n_flt > 0 then ', ' else '' end
             || case when n_flt > 0 then n_flt || ' fault' || case when n_flt > 1 then 's' else '' end || ' open more than a day' else '' end;
  v_detail := 'The one IT message of the day. It carries only what needs you: decisions only you can make, and faults '
           || 'the company could not fix that have been open more than 24 hours. Everything else stays with the CEO and the seats.'
           || E'\n\n' || v_detail;

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
end $fn$;
revoke execute on function public.fn_customer_support_sends_the_it_digest(timestamptz) from public, anon, authenticated;

create or replace function public.fn_it_renewal_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; e public.it_expiry; v_window interval; v_rep jsonb; v_items jsonb := '[]'::jsonb;
  v_days int; v_stage int; n_closed int := 0; n_esc int := 0; v_key text;
begin
  select reply_within into v_window from public.seat_handoff_kind
   where type = 'renewal.due' and from_seat = 'it_engineer' and to_seat = 'accountant';
  -- The row is the accountant's build's; without it `created_at + NULL` would never escalate anything.
  v_window := coalesce(v_window, interval '3 days');

  -- 1. RE-VERIFY: a handoff closes when the date it was about has moved (the item was renewed).
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'renewal.due' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    e := null;
    select * into e from public.it_expiry where item = h.detail->>'item';
    v_key := 'renewal:' || (h.detail->>'item') || '@' || (h.detail->>'expires_on');
    -- FOUNDER RULING 1090: a reminder already out about a credential only the founder can renew is withdrawn.
    if public.fn_it_credential_founder_required('duty:renewal:' || (h.detail->>'item')) then
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', 'withdrawn: founder ruling 1090 - a credential only the founder can renew is never rotated or reminded'));
      perform set_config('qd.handoff_closer', '', true);
      begin
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'Withdrawn by founder ruling 1090: ' || (h.detail->>'item') || ' is a founder-required credential (handoff ' || h.id || ').'
         where idempotency_key = v_key and status in ('sent', 'accepted');
      exception when others then null;
      end;
      n_closed := n_closed + 1;
      continue;
    end if;
    if e.item is null or e.expires_on is distinct from (h.detail->>'expires_on')::date then
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', case when e.item is null then 'the item is no longer watched'
                        else 'renewed: expiry moved from ' || (h.detail->>'expires_on') || ' to ' || coalesce(e.expires_on::text, 'unknown') end));
      perform set_config('qd.handoff_closer', '', true);
      -- A ceo report about this date is finished by the renewal, answered or not.
      begin
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer re-verified: ' || (h.detail->>'item') || ' now expires ' || coalesce(e.expires_on::text, 'unknown') || ' (handoff ' || h.id || ').'
         where idempotency_key = v_key and status in ('sent', 'accepted');
      exception when others then null;  -- the handoff is closed either way; the report stays for the ceo
      end;
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id')
          and (h.detail->>'stage')::int = (select min(w) from unnest(e.warn_days) w)
          and now() > h.created_at + v_window then
      -- 2. ESCALATE: the last warning's window has passed and the date has not moved.
      v_rep := public.fn_support_report_to_ceo(
        v_key, 'serious',
        'Renewal not closed: ' || e.item || ' expires ' || e.expires_on || ' (' || (e.expires_on - current_date) || ' days)',
        jsonb_build_object('item', e.item, 'kind', e.kind, 'expires_on', e.expires_on, 'route', e.route, 'source', e.source,
                           'handoff_id', h.id, 'accountant_reply', h.evidence),
        jsonb_build_array(jsonb_build_object('action', 'accountant warned at ' || (h.detail->>'stage') || ' days', 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Renew it or direct who does. The IT engineer closes this only when it reads the new expiry date back.',
        p_review_in => interval '2 days', p_source_agent => 'it_engineer');
      if coalesce((v_rep->>'ok')::boolean, false) then
        update public.agent_actions
           set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_esc := n_esc + 1;
      else
        raise exception 'fn_it_renewal_watch: the ceo report for % was refused: %', e.item, v_rep->>'reason';
      end if;
    end if;
  end loop;

  -- 3. WARN: every item inside a stage gets its handoff; the ledger records what is due.
  -- A never_expires item is settled, not overdue: there is no renewal to arrange and no date to chase.
  for e in select * from public.it_expiry where kind <> 'tls' and not never_expires order by item loop
    -- FOUNDER RULING 1090: a credential only the founder can renew gets no handoff, no report, no reminder.
    -- Inside a warning stage, past its date or undated, it is one silent IT engineer finding, so the OS shows it.
    if public.fn_it_credential_founder_required('duty:renewal:' || e.item) then
      v_days := e.expires_on - current_date;
      select min(w) into v_stage from unnest(e.warn_days) w where v_days <= w;
      if e.expires_on is null or v_stage is not null then
        v_items := v_items || jsonb_build_object('item', e.item || case when e.expires_on is null then ':date_unknown' else '' end,
          'owner_seat', 'it_engineer', 'subject', e.item, 'blast', 'internal', 'affected', 0,
          'title', e.item || ' (founder-required credential) ' || case when e.expires_on is null then 'has no known date'
                   when v_days < 0 then 'passed its date ' || e.expires_on else 'is dated ' || e.expires_on || ' (' || v_days || ' days)' end
                   || ': recorded only, never rotated or reminded (founder ruling 1090)',
          'evidence', jsonb_build_object('founder_required_credential', true, 'founder_told', false, 'expires_on', e.expires_on));
      end if;
      continue;
    end if;
    if e.expires_on is null then
      v_items := v_items || jsonb_build_object('item', e.item || ':date_unknown', 'owner_seat', 'accountant', 'subject', e.item,
        'title', 'The renewal date of ' || e.item || ' is not known (' || e.source || ')',
        'blast', 'internal', 'affected', 0, 'config', true,
        'evidence', jsonb_build_object('route', e.route, 'source', e.source));
      continue;
    end if;
    v_days := e.expires_on - current_date;
    select min(w) into v_stage from unnest(e.warn_days) w where v_days <= w;
    continue when v_stage is null;
    v_items := v_items || jsonb_build_object('item', e.item, 'owner_seat', 'accountant', 'subject', e.item,
      'title', e.item || case when v_days < 0 then ' EXPIRED on ' || e.expires_on
                              else ' expires on ' || e.expires_on || ' (' || v_days || ' days): inside the ' || v_stage || '-day warning' end,
      -- quiet in the ledger while it is being renewed; an item past its date goes round the IT loop as well
      'blast', case when v_days < 0 then 'agent_facing' else 'internal' end, 'affected', case when v_days < 0 then 1 else 0 end,
      'evidence', jsonb_build_object('stage', v_stage, 'days_left', v_days, 'route', e.route, 'source', e.source));
    perform public.fn_seat_handoff('it_engineer', 'accountant', 'renewal.due', 'it_expiry',
      e.item || '@' || e.expires_on || '@' || v_stage,
      jsonb_build_object('item', e.item, 'kind', e.kind, 'expires_on', e.expires_on, 'days_left', v_days,
                         'stage', v_stage, 'route', e.route));
  end loop;
  return jsonb_build_object('renewal', public.fn_it_duty_settle('renewal', v_items), 'closed', n_closed, 'escalated', n_esc);
end $fn$;
revoke execute on function public.fn_it_renewal_watch() from public, anon, authenticated;

-- ── VERDICT (a row; this file defines routines, so it must not raise) ─────────────────────────────
select case
  when not public.fn_it_credential_founder_required('duty:renewal:token:meta_marketing:date_unknown')
    then 'PROBE FAILED: Meta is not classed founder-required'
  when not public.fn_it_credential_founder_required('duty:integration:github', 'github (x): answered HTTP 401: bad credentials', '{}'::jsonb)
    then 'PROBE FAILED: a refused founder key is not recognised'
  when public.fn_it_credential_founder_required('duty:integration:github', 'github (x): answered HTTP 503', '{}'::jsonb)
    then 'PROBE FAILED: an outage was silenced as a renewal'
  when public.fn_it_credential_founder_required('duty:integration:twilio', 'twilio (x): answered HTTP 401', '{}'::jsonb)
    then 'PROBE FAILED: the company-rotated Twilio key was classed founder-required'
  when public.fn_it_credential_founder_required('duty:renewal:key:twilio_api_key_secret')
    then 'PROBE FAILED: the Twilio API key renewal was silenced'
  when exists (select 1 from public.it_expiry where item like 'key:%' and item <> 'key:twilio_api_key_secret' and route ~* 'the founder rotates')
    then 'PROBE FAILED: a route still says the founder rotates it'
  when has_function_privilege('anon', 'public.fn_it_credential_founder_required(text, text, jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute the classifier'
  else 'PROBE OK' end as verdict;
