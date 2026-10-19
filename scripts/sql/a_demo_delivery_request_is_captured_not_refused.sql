-- customer_support: a delivery request about a demo row is written and CAPTURED, never refused.
--
-- Measured 19 Oct 2026 (platform-on simulation, run tag 63c1, supplier_api submit_quote): ruling 1199
-- makes fn_seat_handoff return NULL for demo work, so this door returned notification_id = null with no
-- error. _shared/deliver.ts reads that as "not queued", line_specs/workflow.ts notify() throws, and an
-- incomplete quote from a ZZ DEMO supplier answered HTTP 500 instead of being HELD. No hold row, no
-- notice: the hold path could not be proven in the sandbox at all.
--
-- Fix: when no handoff is filed (demo), the notification row is inserted directly. The demo capture
-- row is written with status suppressed EXPLICITLY (fn_seat_work_is_demo is wider than the capture
-- trigger: a demo-by-payload row can carry a real recipient), so nothing reaches anyone, and the caller
-- gets a real notification_id. Real (non-demo) rows take the unchanged handoff path.
create or replace function public.fn_customer_support_takes_delivery(p_rows jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r jsonb; v_seat text; v_id bigint; v_nid bigint; h public.agent_actions; v_out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'fn_customer_support_takes_delivery takes an array of notification rows';
  end if;
  for r in select x from jsonb_array_elements(p_rows) x loop
    if coalesce(btrim(r->>'type'), '') = '' then raise exception 'a delivery request must name its type'; end if;
    v_seat := coalesce(nullif(btrim(r->>'requested_by'), ''), public.fn_channel_requester(r->>'type', r->>'kind'));
    if v_seat = 'platform' then
      raise exception 'a sign-in code (%) is sent by the platform OTP service, never queued through support', r->>'type';
    end if;
    v_id := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications',
      coalesce(nullif(btrim(r->>'dedupe_key'), ''),
               (r->>'type') || ':' || coalesce(r->>'to_email', r->>'to_phone', r->>'to_role', 'nobody') || ':' || gen_random_uuid()::text),
      jsonb_build_object('prepared', r - 'dedupe_key' - 'requested_by' - 'status' - 'sender',
                         'msg_type', r->>'type', 'recipient_role', r->>'to_role', 'to_email', r->>'to_email',
                         'supplier_id', r->'lead_id', 'inquiry_id', r->'inquiry_id', 'quote_id', r->'quote_id'));
    if v_id is null then
      -- demo work (ruling 1199): no handoff; the row is written and the demo capture suppresses it
      insert into public.notifications (type, channel, to_email, to_phone, to_role, lead_id, inquiry_id, quote_id,
                                        subject, body, html, kind, lang, attachments, cc_emails, reply_to, requested_by, status, last_error)
      select n.type, coalesce(n.channel, 'email'), n.to_email, n.to_phone, n.to_role, n.lead_id, n.inquiry_id, n.quote_id,
             n.subject, n.body, n.html, n.kind, n.lang, n.attachments, coalesce(n.cc_emails, '{}'), n.reply_to, v_seat,
             'suppressed', 'demo work (ruling 1199): written for the record, never sent'
        from jsonb_populate_record(null::public.notifications, r) n
      returning id into v_nid;
      v_out := v_out || jsonb_build_array(jsonb_build_object('handoff_id', null, 'seat', v_seat, 'status', 'demo_captured',
        'notification_id', v_nid, 'error', null));
      continue;
    end if;
    select * into h from public.agent_actions where id = v_id;
    v_out := v_out || jsonb_build_array(jsonb_build_object('handoff_id', v_id, 'seat', v_seat, 'status', h.status,
      'notification_id', h.evidence->'notification_id', 'error', h.detail->>'error'));
  end loop;
  return v_out;
end $function$;
