-- spec_backlog#205 named FIVE routes with no mapped authority (38, 39, 41, 61, 62). The table says
-- FORTY-ONE, and all 86 routes are 'requires_review', so fn_kb_route_activation_blocked blocks every
-- route rather than the five. Sizing Phase 2 from this ticket would have under-scoped the work by
-- roughly eight times.
--
-- The five in the original note are not wrong, they are the ones somebody happened to check. That is
-- the failure worth naming: a ticket written from a sample reads exactly like a ticket written from a
-- census.
--
-- The note now points at the QUERY rather than restating a count, because a count written into a note
-- is stale the moment the corpus is ingested against and nobody re-reads the note to find out.
update public.spec_backlog
   set notes = 'Blocks activation via fn_kb_route_activation_blocked. '
     || 'DO NOT SIZE THIS FROM THIS TICKET - measure it, every time: '
     || 'select regulatory_coverage_status, count(*), count(*) filter (where named_authorities_in_corpus=0) '
     || 'from public.v_kb_route_regulatory_status group by 1; '
     || 'At 4 Aug 2026 that returned requires_review 86 routes, 41 of them with ZERO named authorities - '
     || 'catalog numbers 17 18 19 20 21 22 23 26 27 28 29 31 32 33 34 35 36 38 39 40 41 42 43 44 45 46 '
     || '48 49 50 51 53 54 55 57 58 59 60 61 62 63 67. The previous text of this ticket named only five '
     || '(38, 39, 41, 61, 62); those were the ones someone had checked, not the ones that exist. '
     || 'Authorities already identified for the original five: Ministry of Economy and Tourism / ADGM / '
     || 'DIFC (38); Federal Tax Authority (39); Dubai Legal Affairs Department / ADJD (41); MOHAP, DHA, '
     || 'DoH Abu Dhabi (61, 62). The remaining 36 have no authority identified yet. '
     || 'Note that ALL 86 routes are requires_review, so every route is blocked, not only the 41.'
 where id = 205;

-- #201 is the shared-secret separation. Its code half closed on 4 Aug; the ticket stays OPEN because
-- the secret itself is still live and still withdrawable only on the invariant, not on a date.
update public.spec_backlog
   set notes = notes
     || E'\n\nPROGRESS 4 Aug 2026 (code complete, ticket deliberately still open). '
     || 'All 32 _shared/llm.ts callers now present a per-caller credential scoped to ai_gateway - that '
     || 'module was the shared secret''s largest consumer and was in neither the D3 nor the D5 hop '
     || 'inventory, because both were built by reading each function''s own fetch() calls and this hop '
     || 'lives in a shared import. qa_suite and social_stage moved off the x-internal-key / '
     || 'postiz_publish_key header, which was a second shared secret nobody had counted. '
     || 'wa_templates_watch had no internal gate at all and has been gated and unscheduled. '
     || 'REMAINING: re-issue the two Resend URLs (founder, five minutes), and withdraw inbound_secret '
     || 'ONLY when v_internal_secret_migration_progress.safe_to_withdraw_shared_secret has been true '
     || 'for a full 7-day window. Never on a calendar date: the 7-day clock resets on every use, and '
     || 'before 4 Aug every model call the platform made reset it.'
 where id = 201 and notes not like '%PROGRESS 4 Aug 2026%';;
