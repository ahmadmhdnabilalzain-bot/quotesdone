-- RENEWALS WARN THE ACCOUNTANT AT SIXTY AND THIRTY DAYS, AND GO TO THE CEO IF NOTHING CLOSES THEM.
--
-- Assigned: it_engineer (the watch, the warning, the re-check, the close, the escalation); the accountant
-- answers and arranges each renewal; the ceo decides when it is not closed.
--
-- Founder, 14 Sep 2026, approving IT duty 20 ("add all for accountant and IT"): watch the TDRA NOL
-- NOL-26-100000665 (expires 2027-09-14), the DET trade licence 1633275 (expires 2027-06-24), the domains
-- and the Meta/WhatsApp tokens; warn the accountant 60 and 30 days ahead; escalate to the ceo if not
-- closed; store the dates as data, not code. No model call anywhere.
--
-- WHAT WAS THERE. public.it_expiry (the_it_engineer_runs_its_duties_every_hour.sql) already held the two
-- licences as data, the domains and certificates from RDAP and crt.sh, and warned at 30 days through the
-- ordinary IT loop - whose reply window is four hours and whose escalation emails the founder as a new
-- bug. That is right for a certificate Vercel failed to renew and wrong for a licence 60 days out.
-- Measured 14 Sep 2026: domain:quotesdone.com expires 2027-06-08 (RDAP); domain:quotesdone.ae has no
-- date (RDAP gave none); both certificates have no date yet.
--
-- WHAT THIS CHANGES:
--   * it_expiry gains warn_days (data: {60,30} for licences, domains and tokens) and the kind 'token'.
--     Certificates stay with fn_it_duties at 30 days to the ceo: they renew themselves, so a date inside
--     30 days is a fault, not a renewal to arrange (that file is edited to take only kind 'tls').
--   * The conversation 'renewal.due' (it_engineer -> accountant) belongs to the accountant's build, PR #659
--     (the_accountant_budgets_every_renewal_the_it_engineer_sees_coming.sql), which registers it in
--     seat_handoff_kind: the accountant answers at once with the budget line (fn_accountant_budgets_renewal)
--     and waits, and only the IT engineer closes it, once its own reading shows the new expiry date. This
--     file only STARTS it, with the payload that contract names ({item}) plus the date and the stage, so
--     neither build redefines the other's half. Until #659 is applied, fn_seat_handoff records the handoff
--     as failed and raises 'unregistered handoff kind' round the IT loop - loud, not silent.
--   * fn_it_renewal_watch, every 15 minutes: opens one handoff per item and stage (60, then 30), with the
--     date in the subject so a renewed item that later falls due again is a new conversation; closes a
--     handoff when the date it was about has moved; and when the LAST stage (30 days) is past its reply
--     window and still open, files a serious report to the ceo. A ceo report left unanswered past its
--     review time already reaches the founder through fn_it_ceo_silence_watch.
--   * fn_it_renewal_recorded: how the accountant, the ceo or the founder records a new expiry date, with
--     what proves it. Domains and certificates also update themselves from RDAP and crt.sh.
--
-- THE TOKENS. WhatsApp runs through Twilio (app_secrets.twilio_wa_from); a Twilio API key has no expiry
-- date, and whether it still works is already the credential duty's (providers.twilio in
-- _shared/it_duty_readings.ts). The Meta marketing token does expire, and its expiry is read from Meta's
-- debug_token when app_secrets.meta_access_token exists. On 14 Sep 2026 it does not (the ad-spend
-- autopilot is built and waits for it), so its row has no date and says so.
-- An item with no date is a quiet ledger finding for the accountant: never a guessed date.

alter table public.it_expiry add column if not exists warn_days int[] not null default '{60,30}';
alter table public.it_expiry drop constraint if exists it_expiry_warn_days_ck;
alter table public.it_expiry add constraint it_expiry_warn_days_ck check (cardinality(warn_days) > 0 and 0 < all (warn_days));
alter table public.it_expiry drop constraint if exists it_expiry_kind_check;
alter table public.it_expiry add constraint it_expiry_kind_check check (kind in ('licence', 'domain', 'tls', 'token'));
update public.it_expiry set warn_days = '{30}' where kind = 'tls' and warn_days <> '{30}';

insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source, warn_days) values
  ('token:meta_marketing', 'token', null, 'accountant',
   'the founder mints a new long-lived token in Meta Business Settings and stores it as app_secrets.meta_access_token; the accountant tracks the date',
   'graph.facebook.com debug_token, read when app_secrets.meta_access_token exists (it did not on 14 Sep 2026)', '{60,30}')
on conflict (item) do update set kind = excluded.kind, owner_seat = excluded.owner_seat, route = excluded.route,
  source = excluded.source, warn_days = excluded.warn_days;

-- (No seat_handoff_kind row and no accountant handler here: both are the accountant's, PR #659.)

create or replace function public.fn_it_renewal_recorded(p_item text, p_expires_on date, p_by text, p_evidence text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare e public.it_expiry;
begin
  if p_by is null or p_by not in ('accountant', 'ceo', 'founder') then
    raise exception 'a renewal is recorded by the accountant, the ceo or the founder, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_evidence), '') = '' then
    raise exception 'say what proves the renewal (the certificate number, the receipt, the registrar page)';
  end if;
  select * into e from public.it_expiry where item = p_item;
  if not found then raise exception 'no renewal item % in public.it_expiry', p_item; end if;
  if p_expires_on is null or p_expires_on <= coalesce(e.expires_on, current_date) then
    raise exception 'the new expiry (%) must be later than the one on record (%)', p_expires_on, coalesce(e.expires_on::text, 'today');
  end if;
  update public.it_expiry
     set expires_on = p_expires_on, checked_at = now(),
         source = left('renewed, recorded by ' || p_by || ' on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ': ' || p_evidence, 500)
   where item = p_item;
  return jsonb_build_object('item', p_item, 'was', e.expires_on, 'now', p_expires_on, 'by', p_by,
                            'watch', public.fn_it_renewal_watch());
end $fn$;
revoke execute on function public.fn_it_renewal_recorded(text, date, text, text) from public, anon, authenticated;

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
  for e in select * from public.it_expiry where kind <> 'tls' order by item loop
    if e.expires_on is null then
      v_items := v_items || jsonb_build_object('item', e.item || ':date_unknown', 'owner_seat', 'accountant', 'subject', e.item,
        'title', 'The renewal date of ' || e.item || ' is not known (' || e.source || ')',
        'blast', 'internal', 'affected', 0, 'evidence', jsonb_build_object('route', e.route, 'source', e.source));
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
