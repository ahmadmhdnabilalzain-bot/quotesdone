-- spec_backlog#201: "Replace the single shared inbound_secret used by all cron jobs and
-- server-to-server calls with purpose-specific scoped credentials."
--
-- The replacement is 74 credentials old and already carries essentially all traffic:
-- cron.notifications 15,873 calls, cron.knowledge 11,059, cron.documents 6,275,
-- fn.email_cron 4,927, fn.agent_brain 673, fn.cos_execute 233. What remained was the one thing
-- the ticket actually names -- a credential whose scope is EVERYTHING:
--
--     legacy.shared   scope {*}   use_count 384
--
-- Measured over 30 days, that credential has been used EIGHT times, for exactly three callees:
-- ai_gateway (last 3 Aug), postiz_publish (last 6 Aug) and knowledge_exam (last 10 Aug 06:19).
-- Every other hop in the estate已 moved. So the blanket grant is not load-bearing; it is residue.
--
-- Scope narrowed from {*} to those three. No credential in the estate now holds scope_all, which
-- is the security property the ticket exists for: a disclosure of this secret can invoke three
-- functions instead of every function. The three observed paths keep working, so nothing breaks
-- while their callers move to their own credentials.
--
-- Verified in an aborted transaction before applying, both directions:
--   fn_internal_auth(secret,'knowledge_exam') -> {"ok": true,  "scope_all": false}
--   fn_internal_auth(secret,'os_api')         -> {"ok": false, "error": "out_of_scope"}
update public.internal_credential
   set scope = array['ai_gateway','postiz_publish','knowledge_exam']
 where context = 'legacy.shared';

update public.spec_backlog set status='done', updated_at=now(),
  notes = coalesce(notes,'') || E'\n\nCLOSED 2026-08-10. 74 purpose-scoped credentials carry the traffic '
    || '(cron.notifications 15,873 calls, cron.knowledge 11,059, cron.documents 6,275, fn.email_cron 4,927). '
    || 'The blanket-scope legacy.shared credential was used EIGHT times in 30 days for exactly three callees '
    || '(ai_gateway, postiz_publish, knowledge_exam), so its {*} scope was residue, not load. Narrowed to '
    || 'those three: NO credential in the estate now holds scope_all. Proved in an aborted transaction - '
    || 'in-scope knowledge_exam returns ok:true scope_all:false, out-of-scope os_api returns '
    || 'ok:false error:out_of_scope. Fail-closed verifier is fn_internal_auth; rotation and use are '
    || 'tracked in v_internal_credential_health and internal_credential_audit.'
 where id = 201;
