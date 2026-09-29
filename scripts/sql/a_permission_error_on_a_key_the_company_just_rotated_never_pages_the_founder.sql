-- A PERMISSION ERROR ON A KEY THE COMPANY JUST ROTATED NEVER PAGES THE FOUNDER (29 Sep 2026; seat: it_engineer).
--
-- MEASURED: #1038's first live Twilio rotation (13:01:25 UTC) replaced a console-made Main key with an API-made
-- Standard key. The integration probe still read /Accounts/{AC}.json, which a Standard key may not read, so it
-- answered 401/70004 and, two beats later, fn_it_integration_settle mailed the founder "reconnect needed: twilio"
-- (notification 78020) telling him to issue a new key - work that was the IT engineer's (#1130 moved the probe).
-- His standing rule: agents solve what they can and never page him for it.
--
-- THE CHANGE (body otherwise identical to every_integration_probe_leaves_a_row_in_edge_health_probe.sql): a finding
-- whose failure is a permission refusal (HTTP 401/403, Twilio 20003 or 70004) is NOT mailed to the founder while
-- a rotation the company made for that provider is inside its overlap window (it_credential_rotation.status
-- 'overlap', overlap_until in the future). The finding stays open and the IT engineer's; nothing else changes.
--   node scripts/apply_sql.mjs scripts/sql/a_permission_error_on_a_key_the_company_just_rotated_never_pages_the_founder.sql --apply --ddl --seat it_engineer

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
