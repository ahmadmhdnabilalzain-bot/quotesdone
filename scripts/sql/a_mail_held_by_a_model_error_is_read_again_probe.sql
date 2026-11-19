-- PROBE of a_mail_held_by_a_model_error_is_read_again.sql. LOCAL only (Postgres 16 from the schema mirror, scripts/db/local_pg16.mjs),
-- after the file is applied there. Always raises CHK<<...>>, so every row it writes rolls back: it leaves 0 rows and nothing reaches a
-- person. Its mail is ZZ DEMO from @example.invalid. Run it twice: the second run must answer the same verdict.
-- Cases: a mail held by a 502 gateway_deadline is put back once (a second call puts back nothing); one held by an open circuit, one
-- already answered, and one held by a model that answered 'unclear' are left alone; p_fixture false touches none of them.
do $probe$
declare
  v_p text[] := '{}'; r jsonb; r2 jsonb; rr jsonb; v_tag text := md5(random()::text);
  m_gw bigint; m_hold bigint; m_done bigint; m_model bigint; x public.inbound_messages;
begin
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, owner_role, ai_category, created_at, raw)
  values ('zz-demo-gw-' || v_tag || '@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO Re: invitation', 'ZZ DEMO could you tell us more?', true, now(), 'customer_support', 'no_auto_reply', now() - interval '7 days', '{"keep":"me"}')
  returning id into m_gw;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, owner_role, ai_category, created_at)
  values ('zz-demo-hold-' || v_tag || '@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO Re: invitation', 'ZZ DEMO hold', true, now(), 'customer_support', 'no_auto_reply', now() - interval '1 day')
  returning id into m_hold;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, replied_at, owner_role, ai_category, created_at)
  values ('zz-demo-done-' || v_tag || '@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO Re: invitation', 'ZZ DEMO done', false, now(), now(), 'customer_support', 'no_auto_reply', now() - interval '1 day')
  returning id into m_done;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, owner_role, ai_category, created_at)
  values ('zz-demo-model-' || v_tag || '@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO Re: invitation', 'ZZ DEMO unclear', true, now(), 'customer_support', 'no_auto_reply', now() - interval '1 day')
  returning id into m_model;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, why, method, decided_by, decided_at) values
    (m_gw, 'unclear', 'no model answer could be read (gateway_http_502:gateway_deadline), so it is held', 'no_model', 'customer_support', now()),
    (m_hold, 'unclear', 'no model answer could be read (gateway_http_503:circuit_open:every model route is open-circuit), so it is held', 'no_model', 'customer_support', now()),
    (m_done, 'unclear', 'no model answer could be read (gateway_http_502:gateway_deadline), so it is held', 'no_model', 'customer_support', now()),
    (m_model, 'unclear', 'the sender''s intent cannot be told from the text', 'model', 'customer_support', now())
  on conflict (inbound_message_id) do update set reading = excluded.reading, why = excluded.why, method = excluded.method;

  rr := public.fn_inbound_mail_held_by_model_error_requeue(false);
  if exists (select 1 from jsonb_array_elements_text(rr->'ids') e where e::bigint in (m_gw, m_hold, m_done, m_model)) then
    v_p := v_p || ('p_fixture false touched a ZZ DEMO row: ' || rr::text); end if;

  r := public.fn_inbound_mail_held_by_model_error_requeue(true);
  if (r->>'requeued')::int <> 1 or r->'ids' <> jsonb_build_array(m_gw) then v_p := v_p || ('expected exactly the gateway-held row: ' || r::text); end if;
  select * into x from public.inbound_messages where id = m_gw;
  if x.triaged_at is not null or x.ai_category is not null or x.owner_role is not null or not x.needs_review then
    v_p := v_p || 'the gateway-held row is not back in front of email_triage'::text; end if;
  if x.raw->>'keep' <> 'me' or not (x.raw ? 'model_error_requeued_at') then v_p := v_p || ('raw lost or unmarked: ' || x.raw::text); end if;
  if x.replied_at is not null then v_p := v_p || 'the probe row shows a reply: nothing may be sent'::text; end if;
  if exists (select 1 from public.inbound_messages where id in (m_hold, m_done, m_model) and (triaged_at is null or raw ? 'model_error_requeued_at')) then
    v_p := v_p || 'a hold, an answered mail or a model reading was put back'::text; end if;
  if exists (select 1 from public.notifications where to_email like 'zz-demo-%' || v_tag || '@example.invalid') then
    v_p := v_p || 'a notification was written'::text; end if;

  r2 := public.fn_inbound_mail_held_by_model_error_requeue(true);
  if (r2->>'requeued')::int <> 0 then v_p := v_p || ('not idempotent: ' || r2::text); end if;

  raise exception 'CHK<<%>>', case when cardinality(v_p) = 0 then 'PROBE OK: ' || r::text || ' then ' || r2::text else 'PROBE FAILED: ' || array_to_string(v_p, '; ') end;
end $probe$;
