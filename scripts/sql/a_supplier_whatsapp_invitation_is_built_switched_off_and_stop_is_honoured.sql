-- A SUPPLIER WHATSAPP INVITATION IS BUILT SWITCHED OFF, AND "STOP" IS HONOURED (marketing, 19 Oct 2026).
--
-- Founder ruling 1184 (12 Oct): supplier acquisition must use every SAFE channel beyond email -- WhatsApp,
-- LinkedIn, others -- "nothing that risks bans". Ruling 1185: bulk SMS is too expensive, not now. Measured
-- 19 Oct: 176 of the 213 active trades hold fewer than 10 complete leads (email + phone) and every one of the
-- 213 holds 0 verified suppliers; 2,761 real leads carry a UAE mobile (+9715), the numbers a business runs
-- WhatsApp on.
--
-- What this builds (the channel; nothing sends until the founder's go):
--   * app_secrets.wa_supplier_invite_golive = 'false'. While it is not 'true' fn_wa_supplier_invite_queue only
--     COUNTS who would be invited and writes nothing.
--   * fn_wa_supplier_invite_queue(p_limit): queues at most p_limit (cap 20) a Dubai day, and only on a weekday
--     between 10:00 and 17:00 Dubai (founder: no posting weekends; TDRA marketing-hours rule), one invitation
--     per lead for life, as notifications rows of type 'supplier_invite_wa' (the email invitation owns 'supplier_invite') that send_whatsapp drains through the
--     Meta-approved MARKETING template 'supplier_invite' (wa_template_setup). Never to a lead that opted out of
--     WhatsApp, whose email is suppressed, that bounced, that is banned, closed, demo, or already a supplier.
--   * fn_wa_supplier_invite_opt_out(p_from): an inbound STOP from a number sets every lead on it to
--     whatsapp_opt='none' and cancels any invitation still queued to it (wa_inbound calls it). UAE PDPL /
--     TDRA: an objection is honoured at once and for good.
-- send_whatsapp never fails a 'supplier_invite_wa' over to SMS (ruling 1185).

insert into public.app_secrets (key, value) values ('wa_supplier_invite_golive', 'false') on conflict (key) do nothing;

create or replace function public.fn_wa_supplier_invite_queue(p_limit int default 20, p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_live boolean := coalesce((select value from public.app_secrets where key = 'wa_supplier_invite_golive'), '') = 'true';
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_today int; v_room int; v_eligible int; v_queued int := 0;
begin
  select count(*) into v_today from public.notifications
   where type = 'supplier_invite_wa' and channel = 'whatsapp' and (created_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date;  -- the cap counts real rows, whatever p_at says
  v_room := greatest(0, least(coalesce(p_limit, 20), 20) - v_today);

  create temp table if not exists _wa_inv(lead_id bigint, phone text, trade text, token text) on commit drop;
  truncate _wa_inv;
  insert into _wa_inv
  select l.id, l.phone_e164, coalesce(l.invite_trades[1], l.sector), l.claim_token::text
    from public.leads l
   where l.claim_token is not null and l.phone_e164 ~ '^\+9715[0-9]{8}$'
     and not coalesce(l.is_demo, false) and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
     and not coalesce(l.claimed, false) and l.approval_status is null
     and coalesce(l.whatsapp_opt, '') <> 'none'
     and coalesce(l.invite_status, '') <> 'bounced'
     and (l.email is null or not exists (select 1 from public.email_suppressions s where lower(s.email) = lower(l.email)))
     and not exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.lead_id = l.id)
     and not exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.to_phone = l.phone_e164)
   order by l.id;
  select count(*) into v_eligible from _wa_inv;

  if v_live and v_room > 0 and extract(isodow from v_local) between 1 and 5 and extract(hour from v_local) between 10 and 16 then
    with pick as (select distinct on (phone) * from _wa_inv order by phone, lead_id limit v_room)
    insert into public.notifications (type, channel, sender, to_phone, lead_id, subject, body, status, lang, dedupe_key)
    select 'supplier_invite_wa', 'whatsapp', 'customer_support', p.phone, p.lead_id,
           coalesce(t.label, replace(p.trade, '_', ' ')),
           'Invitation to receive customer requests on QuotesDone for ' || coalesce(t.label, replace(p.trade, '_', ' ')) || ': https://quotesdone.com/en/portal?t=' || p.token,
           'queued', 'en', 'supplier_invite_wa:' || p.lead_id
      from pick p left join lateral (select x->>'label' label from jsonb_array_elements(
             public.fn_every_category_has_ten_suppliers(false)->'short') x where x->>'trade' = p.trade limit 1) t on true;
    get diagnostics v_queued = row_count;
  end if;

  return jsonb_build_object('live', v_live, 'eligible', v_eligible, 'sent_today', v_today, 'room_today', v_room,
                            'queued', v_queued, 'dubai_time', v_local);
end $fn$;
revoke execute on function public.fn_wa_supplier_invite_queue(int, timestamptz) from public, anon, authenticated;
grant execute on function public.fn_wa_supplier_invite_queue(int, timestamptz) to service_role;

create or replace function public.fn_wa_supplier_invite_opt_out(p_from text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '\D', '', 'g'); v_leads int; v_cancelled int;
begin
  if length(v_phone) < 9 then return jsonb_build_object('ok', false, 'reason', 'no number'); end if;
  update public.leads set whatsapp_opt = 'none' where phone_e164 = v_phone or whatsapp_phone = v_phone;
  get diagnostics v_leads = row_count;
  update public.notifications set status = 'cancelled', last_error = 'the recipient replied STOP; WhatsApp opt-out honoured'
   where type = 'supplier_invite_wa' and to_phone = v_phone and status in ('queued', 'sending');
  get diagnostics v_cancelled = row_count;
  return jsonb_build_object('ok', true, 'leads_opted_out', v_leads, 'invitations_cancelled', v_cancelled);
end $fn$;
revoke execute on function public.fn_wa_supplier_invite_opt_out(text) from public, anon, authenticated;
grant execute on function public.fn_wa_supplier_invite_opt_out(text) to service_role;
