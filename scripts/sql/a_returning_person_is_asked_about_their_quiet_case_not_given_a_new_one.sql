-- a_returning_person_is_asked_about_their_quiet_case_not_given_a_new_one.sql
-- Seat: customer_support. Founder ruling 1635 (11 Nov 2026): "When the same customer or supplier writes again, the agent decides
-- whether it is the same matter ... or a different matter". Final audit 12 Nov 2026 (W3) and its review (note 7).
--
-- MEASURED (production, 11 Nov 2026, aged fixture case QD-S-S68HGF, an escalated refund complaint made 8 days old): on the next
-- message fn_support_touch closed it "resolved — no further contact in 7 days", a rating request was generated (notification
-- 140609, suppressed as a fixture), a new case opened, and the reply was "Hello, of course. What would you like to ask?". The
-- reply's question naming the quiet case (support_case_memory.ts readCase 'confirm') could never fire: the case was closed
-- before anything read it.
--
-- WHAT THIS CHANGES (CREATE OR REPLACE of three live routines, bodies as read from production on 12 Nov 2026):
--   support_case.prior_activity_at  new column: when the case last moved before the message that just arrived.
--   fn_support_touch                no longer closes an idle case on arrival; it keeps prior_activity_at on every inbound.
--   fn_support_open_cases           returns prior_activity_at, so the reply can see how long the case was quiet.
--   fn_support_case_route 'new'     closes the person's open cases idle past the append window, with no rating request.
-- An idle case closed only on the person's return before, and still does: either they continue it, or it closes when the step
-- after the reply routes them to a new case. No row is deleted (ruling 1634).
-- Apply: either order against the wa_inbound / case_context deploy (the TypeScript falls back to last_activity_at when the column
-- is absent); deploying the functions first is the cleaner order.
-- Probe: a_returning_person_is_asked_about_their_quiet_case_not_given_a_new_one_probe.sql (pure, rolls back).

alter table public.support_case add column if not exists prior_activity_at timestamptz;
comment on column public.support_case.prior_activity_at is
  'When the case last moved before the newest inbound message (fn_support_touch): how long it was quiet when the person wrote again. 12 Nov 2026.';

create or replace function public.fn_support_touch(p_channel text, p_direction text, p_party_kind text, p_party_id text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_text text DEFAULT NULL::text, p_rating_text text DEFAULT NULL::text, p_lang text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int);
  v_reopen_days int := greatest(1, public.fn_seat_clock_policy('support_case_reopen_days', 14)::int);
  v_gap interval := make_interval(hours => greatest(1, public.fn_seat_clock_policy('support_contact_gap_hours', 4)::int));
  v_prof bigint; v_case public.support_case; v_closed public.support_case; v_id bigint; v_ref text;
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_party_kind text := case when p_party_kind in ('customer', 'supplier') then p_party_kind else 'unknown' end;
  v_party_id text; v_rt text; m text[]; attempt int := 0;
begin
  if p_direction not in ('in', 'out') then raise exception 'fn_support_touch: direction must be in or out'; end if;
  v_prof := public.fn_support_profile_resolve(v_party_kind, p_party_id, p_email, p_phone);
  if v_prof is null then return jsonb_build_object('ok', false, 'reason', 'no identity'); end if;

  select * into v_case from public.support_case
   where customer_profile_id = v_prof and state <> 'closed' order by last_activity_at desc limit 1;

  if p_direction = 'out' then
    if v_case.case_id is null then return jsonb_build_object('ok', true, 'case', null, 'reason', 'no open case'); end if;
    update public.support_case
       set first_reply_at = coalesce(first_reply_at, now()), outbound_count = outbound_count + 1,
           state = case when state in ('open', 'waiting_service') then 'waiting_customer' else state end,
           last_activity_at = now()
     where case_id = v_case.case_id;
    return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'direction', 'out');
  end if;

  -- A rating answering the CSAT question of a recently closed case.
  v_rt := btrim(translate(coalesce(p_rating_text, p_text, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'));
  m := regexp_match(v_rt, '^([1-5])(?:\s*[,/ -]\s*([1-7]))?$');
  if m is not null then
    select * into v_closed from public.support_case c
     where c.customer_profile_id = v_prof and c.state = 'closed' and c.csat_requested_at > now() - make_interval(days => v_days)
       and not exists (select 1 from public.feedback f where f.case_id = c.case_id and f.kind = 'csat')
     order by c.csat_requested_at desc limit 1;
    if v_closed.case_id is not null then
      perform public.fn_support_feedback_record(v_closed.case_ref, m[1]::numeric, m[2]::numeric, null, p_channel);
      return jsonb_build_object('ok', true, 'case_ref', v_closed.case_ref, 'rated', m[1]::int, 'ces', m[2]::int);
    end if;
  end if;

  -- 5. A message naming a recently closed case of this person reopens it.
  if v_case.case_id is null then
    select * into v_closed from public.support_case c
     where c.customer_profile_id = v_prof and c.state = 'closed' and c.closed_at > now() - make_interval(days => v_reopen_days)
       and position(c.case_ref in upper(coalesce(p_text, ''))) > 0
     order by c.closed_at desc limit 1;
    if v_closed.case_id is not null then
      update public.support_case set state = 'open' where case_id = v_closed.case_id;
      select * into v_case from public.support_case where case_id = v_closed.case_id;
    end if;
  end if;

  -- A RETURNING PERSON IS ASKED, NOT GIVEN A NEW CASE ON ARRIVAL (12 Nov 2026, final audit W3 / review note 7). This block
  -- closed an open case idle past the append window here, before any reply could read it: the rating request went out and a
  -- new case opened in the same breath, and the reply's "is this about your request QD-...?" (support_case_memory.ts readCase)
  -- could never fire (measured 11 Nov on aged fixture case QD-S-S68HGF). The case stays open and the update below keeps the
  -- time it last moved (prior_activity_at); the step after the reply closes it, without a rating request, only when the person
  -- turns out to be on a new matter (fn_support_case_route 'new').

  if v_case.case_id is null then
    select case when p.customer_id is not null then 'customer' when p.lead_id is not null then 'supplier' else 'unknown' end,
           coalesce(p.customer_id::text, p.lead_id::text, case when v_digits <> '' then '+' || v_digits end, p.email)
      into v_party_kind, v_party_id
      from public.support_customer_profile p where p.id = v_prof;
    loop
      attempt := attempt + 1;
      begin
        v_ref := public.fn_support_case_new_ref();
        insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, verified_how,
                                         owner_role_id, customer_profile_id, channel, lang)
        values (v_ref, v_party_kind, v_party_id,
                initcap(p_channel) || ': ' || left(coalesce(nullif(btrim(p_text), ''), '(no text)'), 4000),
                'open', v_party_kind <> 'unknown',
                case when v_party_kind <> 'unknown' then 'matched on the ' || p_channel || ' identity' end,
                'customer_support', v_prof, p_channel,
                case when p_lang in ('en', 'ar') then p_lang end)
        returning * into v_case;
        exit;
      exception when unique_violation then
        if attempt >= 5 then raise; end if;
      end;
    end loop;
  end if;

  update public.support_case
     set inbound_count = inbound_count + 1,
         contact_count = contact_count + case when last_inbound_at is null or last_inbound_at < now() - v_gap then 1 else 0 end,
         first_customer_msg_at = coalesce(first_customer_msg_at, now()),
         prior_activity_at = last_activity_at,   -- the old value: how long the case was quiet before this message
         last_inbound_at = now(), last_activity_at = now(),
         last_channel = p_channel,
         channels = case when p_channel = any(channels) then channels else channels || p_channel end,
         lang = coalesce(lang, case when p_lang in ('en', 'ar') then p_lang end),
         state = case when state = 'waiting_customer' then 'open' else state end
   where case_id = v_case.case_id;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'case_id', v_case.case_id, 'direction', 'in');
end $function$;

create or replace function public.fn_support_open_cases(p_party_kind text, p_party_id text, p_email text, p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prof bigint;
begin
  v_prof := public.fn_support_profile_resolve(case when p_party_kind in ('customer', 'supplier') then p_party_kind else 'unknown' end,
                                              p_party_id, p_email, p_phone);
  if v_prof is null then return jsonb_build_object('profile', null, 'cases', '[]'::jsonb); end if;
  return jsonb_build_object('profile', v_prof, 'cases', coalesce((
    select jsonb_agg(jsonb_build_object('case_ref', x.case_ref, 'title', coalesce(x.title, left(x.subject, 160)),
                                        'summary_text', x.summary_text, 'summary_version', x.summary_version,
                                        'status', x.status_plain, 'channels', x.channels, 'last_activity_at', x.last_activity_at,
                                        'prior_activity_at', x.prior_activity_at)
                     order by x.last_activity_at desc)
      from (select * from public.support_case where customer_profile_id = v_prof and state <> 'closed'
             order by last_activity_at desc limit 5) x), '[]'::jsonb));
end $function$;

create or replace function public.fn_support_case_route(p_profile bigint, p_choice text, p_case_ref text, p_channel text, p_text text, p_lang text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.support_case; p public.support_customer_profile; v_ref text; attempt int := 0;
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int);
begin
  select * into p from public.support_customer_profile where id = p_profile;
  if p.id is null then return jsonb_build_object('ok', false, 'reason', 'no such person'); end if;
  if p_choice = 'continue' then
    select * into c from public.support_case where case_ref = p_case_ref and customer_profile_id = p_profile and state <> 'closed';
    if c.case_id is null then return jsonb_build_object('ok', false, 'reason', 'not an open case of this person'); end if;
    -- the newest open case is the one fn_support_touch attaches the message to
    -- clock_timestamp, not now(): inside one transaction now() ties with the case opened a moment before (probe, 11 Nov)
    update public.support_case set last_activity_at = clock_timestamp() where case_id = c.case_id;
    return jsonb_build_object('ok', true, 'case_ref', c.case_ref, 'opened', false);
  elsif p_choice = 'new' then
    loop
      attempt := attempt + 1;
      begin
        v_ref := public.fn_support_case_new_ref();
        insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, verified_how,
                                         owner_role_id, customer_profile_id, channel, lang)
        values (v_ref, coalesce(p.party_kind, 'unknown'), coalesce(p.customer_id::text, p.lead_id::text, p.email, p.phone_tail),
                initcap(coalesce(p_channel, 'internal')) || ': ' || left(coalesce(nullif(btrim(p_text), ''), '(no text)'), 4000),
                'open', coalesce(p.party_kind, 'unknown') <> 'unknown',
                case when coalesce(p.party_kind, 'unknown') <> 'unknown' then 'matched on the ' || coalesce(p_channel, 'internal') || ' identity' end,
                'customer_support', p_profile,
                case when p_channel in ('whatsapp', 'email', 'widget', 'portal', 'phone', 'internal', 'social') then p_channel end,
                case when p_lang in ('en', 'ar') then p_lang end);
        exit;
      exception when unique_violation then
        if attempt >= 5 then raise; end if;
      end;
    end loop;
    -- the person is on a new matter: an open case of theirs that was idle past the append window before they wrote again is
    -- closed now, as fn_support_touch used to on arrival, but WITHOUT a rating request (they are writing to us about something
    -- else this minute); the closing notice by e-mail is unchanged
    update public.support_case sc   -- not "c": that is this routine's record variable
       set state = 'closed', closed_at = now(),
           close_reason = 'resolved — no further contact in ' || v_days || ' days; they came back with a new matter (closed by customer_support)',
           -- set, so the closing trigger asks for no rating; and dated outside the rating window, so a bare "1"-"5" they send in
           -- the next days is never read as this case's rating (fn_support_touch matches csat_requested_at > now() - v_days)
           csat_requested_at = now() - make_interval(days => v_days + 1), csat_request_error = 'not asked: they came back with a new matter'
     where sc.customer_profile_id = p_profile and sc.state <> 'closed' and sc.case_ref <> v_ref
       and least(sc.last_activity_at, coalesce(sc.prior_activity_at, sc.last_activity_at)) < now() - make_interval(days => v_days);
    return jsonb_build_object('ok', true, 'case_ref', v_ref, 'opened', true);
  end if;
  return jsonb_build_object('ok', false, 'reason', 'choice is continue or new');
end $function$;

revoke execute on function public.fn_support_touch(text, text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_support_open_cases(text, text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_support_case_route(bigint, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_support_touch(text, text, text, text, text, text, text, text, text) to service_role;
grant execute on function public.fn_support_open_cases(text, text, text, text) to service_role;
grant execute on function public.fn_support_case_route(bigint, text, text, text, text, text) to service_role;
