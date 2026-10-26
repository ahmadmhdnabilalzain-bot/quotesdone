-- THE CEO SEAT GETS A RUNTIME, AND A CREDENTIAL OF ITS OWN.
--
-- Founder, 8 September 2026: "for the new CEO we will build proper tables and edge functions and
-- everything. we dont rely on the old structure."
--
-- Until this landed the CEO seat had tools and no runtime. fn_ceo_request_decision,
-- fn_ceo_decide_refund, fn_ceo_standing, fn_ceo_context and the rest existed in the database with
-- nothing able to call them, and public.function_owner recorded ZERO edge functions owned by 'ceo'.
--
-- IT IS ALSO A PRECONDITION FOR THE DELETION, which is why it comes first. os_api is the sole caller
-- of every founder-command routine and the only surface that can submit an instruction today. The
-- founder has ruled the OS irrelevant and it is going. Deleting it before this existed would have
-- left him with no command channel at all — his WhatsApp fallback already POSTs to an `agent_brain`
-- that is not deployed and can only 404.
--
-- THE CREDENTIAL IS SCOPED, not the shared one. `fn_internal_auth` still accepts the legacy shared
-- secret (scope '*') so nothing breaks during migration, but a channel that carries the founder's
-- instructions should be attributable on its own: if this credential is ever used, the log says
-- ceo_agent and not "something with the shared secret". The secret VALUE is not in this file and is
-- not in the repository — only its hash is stored, and the value is minted by the operator.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_seat_gets_a_runtime_and_a_credential.sql --apply --ddl

begin;

-- OWNERSHIP FIRST, so every_deployed_function_has_an_owner cannot go red between the deploy and the
-- record. The registry is what tells the next sweep this function is not an orphan — and a sweep
-- reading an incomplete registry is exactly how the eight portal functions were deleted.
insert into public.function_owner (function_slug, owner, note) values
  ('ceo_agent', 'ceo',
   'The CEO seat''s runtime: the founder submits an instruction (action=command), the seat reads what '
   || 'it is carrying (action=inbox), closes its own work with evidence (action=task) and records an '
   || 'approval (action=decide). Replaces os_api''s secretary_chat and founder_command actions, which '
   || 'belong to the OS dashboard the founder has ruled irrelevant. Makes no model call: every route '
   || 'in llm_route_health is held, and an instruction must route the same way twice.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

commit;
