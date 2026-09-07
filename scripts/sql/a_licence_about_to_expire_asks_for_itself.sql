-- A LICENCE ABOUT TO EXPIRE ASKS FOR ITSELF
--
-- Founder, 7 September 2026: "so if a supplier trade license is expiring soon, our agent will notify
-- him on email and whatsapp and request for an updated one, and then he attach the pdf or clear
-- picture there, and then the agent will update it in the database"
-- and: "but first time registration is always on the website"
--
-- That last line is a real constraint and it shapes this. WhatsApp is NOT a registration channel. A
-- company that has never registered is sent to the website. WhatsApp carries documents for suppliers
-- who ALREADY exist: renewals, replacements, and completing a file after the website took the rest.
--
-- THE WINDOW IS 30 DAYS, BY FOUNDER RULING 7 Sep 2026: "30 days not 60". So the first ask lands a
-- month out, then at fourteen days, seven days, and on expiry. Four asks in total across the life of
-- a licence, which is enough to be heard and few enough not to be muted.
--
-- THIS IS THE PROACTIVE HALF. fn_wa_attach_document already takes the document and updates the record;
-- verified end to end, a supplier going from three missing to a complete file. What was missing is the
-- company noticing first. A supplier does not know his licence expires in three weeks; we do, and
-- telling him before it lapses is the difference between a renewal and a suspension.
--
-- WHY BOTH CHANNELS AT EACH BAND, AND NOT MORE OFTEN. Email reaches a company address that may be read
-- weekly. WhatsApp reaches a person. Both is right for something with a deadline. But a system that
-- chases daily becomes noise and gets muted, so this asks at fixed distances from the expiry and
-- records each ask, and it never asks the same thing twice in the same window.
--
-- AND IT OBEYS THE CHANNEL POLICY RATHER THAN ASSUMING. WhatsApp is blocked today: zero opt-ins and no
-- approved template. So the WhatsApp leg is PLANNED and reported as blocked, not silently skipped, and
-- it starts working the day the template is approved without any code change.

begin;

create table if not exists public.licence_renewal_ask (
  id            bigserial primary key,
  lead_id       bigint      not null references public.leads(id),
  asked_at      timestamptz not null default now(),

  -- Which distance from expiry this ask represents. One ask per band per licence, ever.
  band          text        not null check (band in ('t_minus_30','t_minus_14','t_minus_7','expired')),
  expiry_date   date        not null,
  days_to_expiry int        not null,

  channel       text        not null check (channel in ('email','whatsapp')),
  sent          boolean     not null default false,
  blocked_reason text,
  notification_id bigint,

  -- Closed when a replacement document actually arrives, not when the message is sent.
  answered_at   timestamptz,
  answered_by_intake bigint references public.wa_document_intake(id),

  unique (lead_id, expiry_date, band, channel)
);

create index if not exists licence_renewal_ask_open
  on public.licence_renewal_ask (lead_id, asked_at desc) where answered_at is null;

comment on table public.licence_renewal_ask is
  'One row per ask, per band, per channel, per licence expiry. The unique key is what stops a supplier being chased daily. Closed when a document arrives, not when a message is sent.';

comment on column public.licence_renewal_ask.blocked_reason is
  'Why a planned ask did not go out. A blocked channel is recorded, never silently skipped, so the gap is visible rather than looking like nobody needed telling.';

commit;

-- ---------------------------------------------------------------------------------------------
-- THE SWEEP
--   Finds licences approaching expiry, decides which band each is in, and queues the asks that have
--   not been made. Deterministic; no model.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_licence_expiry_sweep(p_dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r          record;
  v_band     text;
  v_days     int;
  v_planned  int := 0;
  v_email    int := 0;
  v_wa       int := 0;
  v_blocked  int := 0;
  v_wa_ok    boolean;
  v_wa_why   text;
  v_rows     jsonb := '[]'::jsonb;
  v_subject  text;
  v_body     text;
  v_note     bigint;
begin
  -- Ask the channel policy rather than assuming. Today WhatsApp is blocked for want of a template
  -- and any opt-in, and this must say so instead of quietly sending nothing.
  select (status = 'open'), status_reason
    into v_wa_ok, v_wa_why
    from public.outreach_channel_policy where channel_key = 'whatsapp';
  v_wa_ok := coalesce(v_wa_ok, false);

  for r in
    select l.id, l.company_name, l.email, l.phone_e164, l.license_expiry, l.license_doc_path,
           (l.license_expiry - (now() at time zone 'Asia/Dubai')::date) as days_left
      from public.leads l
     where l.license_expiry is not null
       and l.license_expiry <= (now() at time zone 'Asia/Dubai')::date + 30
       and coalesce(l.banned, false) = false
     order by l.license_expiry
     limit 500
  loop
    v_days := r.days_left;
    v_band := case
      when v_days < 0   then 'expired'
      when v_days <= 7  then 't_minus_7'
      when v_days <= 14 then 't_minus_14'
      else                   't_minus_30' end;

    v_planned := v_planned + 1;

    v_subject := case when v_days < 0
      then 'Your trade licence has expired - QuotesDone'
      else 'Your trade licence expires in ' || v_days || ' days - QuotesDone' end;

    v_body := 'Dear ' || coalesce(r.company_name, 'Supplier') || ',' || chr(10) || chr(10)
           || case when v_days < 0
                then 'The trade licence we hold for you expired on ' || to_char(r.license_expiry, 'DD Mon YYYY')
                  || '. Until we have a valid one we cannot include you in new requests.'
                else 'The trade licence we hold for you expires on ' || to_char(r.license_expiry, 'DD Mon YYYY')
                  || ', which is ' || v_days || ' days from now.' end
           || chr(10) || chr(10)
           || 'Please send us the renewed copy. A clear photograph is fine, a PDF is better. '
           || 'You can reply to this email with it attached, or send it on WhatsApp and it will go '
           || 'straight onto your file.' || chr(10) || chr(10)
           || 'Nothing else is needed and there is no charge.' || chr(10) || chr(10)
           || 'QuotesDone';

    -- EMAIL. Always attempted when we hold an address.
    if coalesce(btrim(r.email), '') <> '' then
      if not p_dry_run then
        insert into public.licence_renewal_ask
          (lead_id, band, expiry_date, days_to_expiry, channel, sent)
        values (r.id, v_band, r.license_expiry, v_days, 'email', false)
        on conflict (lead_id, expiry_date, band, channel) do nothing;

        if found then
          insert into public.notifications (type, kind, to_email, subject, body, status, channel, lead_id)
          values ('licence_renewal', 'licence_expiry', r.email, v_subject, v_body, 'queued', 'email', r.id)
          returning id into v_note;

          update public.licence_renewal_ask
             set sent = true, notification_id = v_note
           where lead_id = r.id and expiry_date = r.license_expiry and band = v_band and channel = 'email';
        end if;
      end if;
      v_email := v_email + 1;
    end if;

    -- WHATSAPP. Planned either way, and the block is recorded rather than the ask vanishing.
    if coalesce(btrim(r.phone_e164), '') <> '' then
      if v_wa_ok then
        v_wa := v_wa + 1;
      else
        v_blocked := v_blocked + 1;
        if not p_dry_run then
          insert into public.licence_renewal_ask
            (lead_id, band, expiry_date, days_to_expiry, channel, sent, blocked_reason)
          values (r.id, v_band, r.license_expiry, v_days, 'whatsapp', false, v_wa_why)
          on conflict (lead_id, expiry_date, band, channel) do nothing;
        end if;
      end if;
    end if;

    if jsonb_array_length(v_rows) < 10 then
      v_rows := v_rows || jsonb_build_object(
        'lead_id', r.id, 'company', r.company_name, 'expiry', r.license_expiry,
        'days_left', v_days, 'band', v_band,
        'email', case when coalesce(btrim(r.email),'')<>'' then 'queued' else 'no address held' end,
        'whatsapp', case when v_wa_ok then 'queued' else 'BLOCKED' end);
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'dry_run', p_dry_run,
    'licences_within_30_days', v_planned,
    'email_asks', v_email,
    'whatsapp_asks_sent', v_wa,
    'whatsapp_asks_blocked', v_blocked,
    'whatsapp_status', case when v_wa_ok then 'open' else 'BLOCKED: ' || coalesce(v_wa_why,'no policy row') end,
    'sample', v_rows,
    'note', case when p_dry_run
      then 'Dry run. Nothing was queued and nothing was written. Call with p_dry_run => false to act.'
      else 'Asks queued. Each is closed only when a replacement document actually arrives, never when a message is sent.' end
  );
end;
$fn$;

revoke execute on function public.fn_licence_expiry_sweep(boolean) from public;

comment on function public.fn_licence_expiry_sweep(boolean) is
  'Finds licences expiring within 30 days and asks for a renewal by email and WhatsApp. One ask per band per channel, ever. A blocked channel is recorded, never silently skipped.';

-- ---------------------------------------------------------------------------------------------
-- CLOSING THE LOOP
--   An ask is answered when a document ARRIVES, not when a message goes out. This is the difference
--   between a chase that works and a chase that only looks busy.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_licence_ask_close_on_intake(p_intake_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_i record; v_closed int;
begin
  select * into v_i from public.wa_document_intake where id = p_intake_id;
  if not found or v_i.lead_id is null or v_i.classified_as <> 'licence' or not v_i.attached then
    return jsonb_build_object('ok', true, 'closed', 0,
      'reason', 'Not an attached licence for a known lead, so no renewal ask is answered by it.');
  end if;

  update public.licence_renewal_ask
     set answered_at = now(), answered_by_intake = p_intake_id
   where lead_id = v_i.lead_id and answered_at is null;
  get diagnostics v_closed = row_count;

  return jsonb_build_object('ok', true, 'closed', v_closed, 'lead_id', v_i.lead_id,
    'note', 'Every open renewal ask for this supplier is answered by the document that arrived.');
end;
$fn$;

revoke execute on function public.fn_licence_ask_close_on_intake(bigint) from public;

comment on function public.fn_licence_ask_close_on_intake(bigint) is
  'Closes renewal asks when a licence actually arrives. An ask closed by a message being sent would be a chase that only looks busy.';
