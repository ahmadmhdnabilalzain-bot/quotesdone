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

select case when (select count(*) from public.internal_credential
                   where context in ('fn.resilience_ping', 'fn.accountant') and active and 'ai_gateway' = any(scope)) = 2
            then 'PROBE OK: resilience_ping and accountant may present themselves to ai_gateway'
            else 'PROBE FAILED: a replay caller still cannot reach ai_gateway' end as verdict;
