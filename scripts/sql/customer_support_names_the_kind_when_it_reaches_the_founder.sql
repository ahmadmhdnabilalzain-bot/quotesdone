-- CUSTOMER SUPPORT NAMES THE KIND WHEN IT REACHES THE FOUNDER.
--
-- Assigned: customer_support. Carried out for the ceo.
--
-- fn_customer_support_acts_on_handoff (payments_are_the_accountant_and_the_seats_close_every_refund_together.sql)
-- called fn_notify_founder with positional arguments, so the check "every fn_notify_founder call names
-- p_kind" (founder_mail_policy routing) could not see the kind. Same body, named arguments. The combined
-- file carries the identical body; this file is applied on its own because that file also drops three
-- retired routines and apply_sql.mjs reads a drop of an absent routine as a missing callee.
--
--   node scripts/apply_sql.mjs scripts/sql/customer_support_names_the_kind_when_it_reaches_the_founder.sql --apply

create or replace function public.fn_customer_support_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; v_ar boolean; v_subject text; v_body text; v_nid bigint; v_fan jsonb; v_cc text[]; v_res jsonb;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail;
  if d->>'type' <> 'delivery.request' then raise exception 'customer_support has no handler for %', d->>'type'; end if;

  if d->>'recipient_role' = 'founder' then
    -- A TEST NEVER REACHES HIM. The fixture ladder sets app.qd_stub_founder_notify; the probe also
    -- aborts its transaction, so even the queued rows are never committed.
    if coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on' then
      return jsonb_build_object('channel', 'founder', 'stubbed', true, 'event', d->>'event');
    end if;
    v_res := public.fn_notify_founder(p_event => d->>'event', p_detail => d->>'detail', p_level => coalesce(d->>'level', 'high'),
                                      p_kind => d->>'kind', p_dedupe_key => d->>'dedupe_key', p_owner_agent => 'customer_support');
    return jsonb_build_object('channel', 'founder', 'notify', v_res);
  end if;

  if a.detail->>'from' <> 'sales_engineer' then
    raise exception 'only the sales engineer addresses customers and suppliers; % may address the founder only', a.detail->>'from';
  end if;
  if coalesce(d->>'to_email', '') !~ '@' then
    return jsonb_build_object('delivered', false, 'reason', 'no email address on file for the ' || coalesce(d->>'recipient_role', 'recipient'));
  end if;

  v_ar := d->>'locale' = 'ar' and d->>'body_ar' is not null;
  v_subject := case when v_ar then coalesce(d->>'subject_ar', d->>'subject_en') else d->>'subject_en' end;
  v_body    := case when v_ar then d->>'body_ar' else d->>'body_en' end;
  select coalesce(array_agg(x), '{}') into v_cc from jsonb_array_elements_text(coalesce(d->'cc', '[]'::jsonb)) x;

  -- requested_by names the seat that asked (customer_support_is_the_only_sender_on_email_and_whatsapp.sql);
  -- sender stays customer_support by that file's default and check.
  insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
  values (d->>'msg_type', d->>'msg_type', d->>'to_email', v_cc, d->>'recipient_role',
          (d->>'supplier_id')::bigint, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, 'email', v_subject, v_body, 'queued',
          a.detail->>'from')
  returning id into v_nid;
  select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
   where n.channel = 'whatsapp' and n.type = d->>'msg_type' and n.id > v_nid
     and n.to_email = d->>'to_email' and n.created_at >= now() - interval '1 minute';

  return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                            'language', case when v_ar then 'ar' else 'en' end,
                            'watch_until', d->'watch_until', 'watching', (d->>'watch_until') is not null);
end $fn$;
revoke execute on function public.fn_customer_support_acts_on_handoff(bigint) from public, anon, authenticated;
