-- THE HELD-QUESTION REPLAY MAY PRESENT ITSELF TO THE GATEWAY -- it_engineer, 7 Oct 2026.
--
-- Founder ruling 7 Oct 2026 (ledger 1175): "from now on keep open router always on". Measured on production in
-- the first 40 minutes after the lift (03:25:36 UTC): the held-question queue (reasoning_held_question, 206
-- held) did NOT drain. resilience_ping's tick 03:45 claimed 3 rows through _shared/think.ts replayHeld; every
-- model call came back HTTP 403 {"error":"forbidden"} from ai_gateway, because llm.ts presents
-- app_secrets.cred_fn_resilience_ping and that credential's scope (fn.resilience_ping) does not name
-- ai_gateway. The accountant hit the same 403 at 03:46 (fn.accountant: ['accountant','pdf_native']).
-- Each such tick spends no money (403 is before any model call) but burns one of the row's 3 tries
-- (a_held_row_is_tried_three_times...), so left alone it would fail the whole queue with no answer at all.
--
-- Both callers call the gateway by design (resilience_ping replays every seat's held question; the accountant
-- reasons). The credential is widened by exactly the one door each needs; nothing else changes.
-- Prevented by: scripts/checks/a_tripped_breaker_on_one_route_never_holds_the_whole_estate.test.mjs
-- (the "every gateway caller can present itself" test).
update public.internal_credential
   set scope = (select array_agg(distinct t order by t) from unnest(scope || array['ai_gateway']) t)
 where context in ('fn.resilience_ping', 'fn.accountant') and active and not ('ai_gateway' = any(scope));

-- THE HOMEPAGE CHAT AND WHATSAPP (coordinator, 7 Oct 2026: customer-facing; a 403 there means a customer gets no answer).
-- Measured: 26 + 7 gateway 403s in 30 days, the latest 00:47 and 00:51 today. Their main chat call presents cred_fn_ai
-- (fn.ai, scope ai_gateway) and works; the calls that 403 go through _shared/llm.ts, which presents
-- app_secrets.cred_fn_<caller> and, finding cred_fn_site_assistant / cred_fn_wa_inbound absent, falls back to the
-- withdrawn shared inbound_secret (llm_gateway_auth rows 00:47:21 and 00:51:16 say exactly that). Each gets its own
-- credential scoped to ai_gateway alone, stored the way cred_fn_wa_docs is.
do $c$
declare v_secret text; r record;
begin
  -- fn_internal_credential_issue does not exist on production (measured 7 Oct), so the row is written directly:
  -- the same shape fn_internal_auth reads (context, secret_hash via fn_internal_credential_hash, scope, active).
  for r in select * from (values ('site_assistant', 'the homepage chat'), ('wa_inbound', 'the WhatsApp agent')) t(fn, what) loop
    if not exists (select 1 from public.app_secrets where key = 'cred_fn_' || r.fn and coalesce(value, '') <> '') then
      v_secret := encode(extensions.gen_random_bytes(32), 'hex');
      insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
      values ('fn.' || r.fn, 'Outbound credential for ' || r.what || ' (' || r.fn || ') on its _shared/llm.ts path: ai_gateway only',
              public.fn_internal_credential_hash(v_secret), array['ai_gateway'], false, true);
      insert into public.app_secrets(key, value) values ('cred_fn_' || r.fn, v_secret)
        on conflict (key) do update set value = excluded.value;
    end if;
  end loop;
end $c$;

select case when (select count(*) from public.internal_credential
                   where context in ('fn.resilience_ping', 'fn.accountant') and active and 'ai_gateway' = any(scope)) = 2
            and (select count(*) from public.app_secrets where key in ('cred_fn_site_assistant','cred_fn_wa_inbound') and coalesce(value,'') <> '') = 2
            then 'PROBE OK: resilience_ping, accountant, site_assistant and wa_inbound may present themselves to ai_gateway'
            else 'PROBE FAILED: a replay caller still cannot reach ai_gateway' end as verdict;
