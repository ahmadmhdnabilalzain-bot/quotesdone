-- CUSTOMER CHAT AND THE REVIEWER MOVE ONCE THEIR EVALS PASS (part 2 of 3: the T2 chat classes and the internal reviewer).
-- Seat: it_engineer (cost). 10 Nov 2026. Founder rulings 1571 ("pick the right model per task yourself"; it supersedes the
-- chat shortlist of 1217 for simple tasks and lets the session overrule 1219 on measured quality and cost), 1219 ("sonnet",
-- 13 Oct: 8.80 against Luna Pro's 8.20, measured on the old ~140k-token prompts), 1218, 1241.
-- Design: docs/reports/2026-11-10-design-model-routing.md section 5a, steps 4, 5 and 8.
--
-- GATED. This file is applied ONLY after both evals pass, never at merge (scripts/sql/pending/ carries the note):
--   eval A  scripts/eval/model_routing/eval_a.ts  (40 T2/status cases, Luna Pro against a Sonnet control, judge Sonnet)
--   eval C  scripts/eval/model_routing/eval_c.ts  (60 reviewer drafts, 30 seeded defects; Qwen must flag >= 28 with <= 3 false)
-- Their results and cost lines: docs/reports/2026-11-10-model-routing-evals.md.
-- It needs part 1 (simple_tasks_leave_sonnet_and_every_reply_runs_on_the_model_its_task_needs.sql: Qwen registered).
--
-- MEASURED (production, 30 days to 10 Nov 2026, ai_cost_log): conversation_reply 3,361 calls USD 76.71, customer_portal_assistant
-- 1,831 USD 36.59, visitor_chat 614 USD 15.14 (all Sonnet 5.5 first); knowledge_validation 1,341 USD 31.64 (Sonnet). Re-priced on
-- Luna Pro / Qwen 3.8 Flash at the same tokens: USD 8.55 and USD 2.26 (design section 4a).
--
-- WHAT THIS FILE DOES:
--   1. conversation_reply, customer_portal_assistant, visitor_chat: openai/gpt-6-luna-pro first, anthropic/claude-sonnet-5.5
--      behind (today's pair, swapped). The WhatsApp conversation chain (model_fallback_chain) follows the same pair.
--   2. knowledge_validation and sales_engineer__knowledge_validation: qwen/qwen3.8-flash first, Sonnet 5.5 behind. Their authors
--      write on Luna Pro (OpenAI), so the reviewer is Qwen (another family) and an Anthropic author's review goes to the pool
--      outside its family (fn_ai_route_review_for). ceo__knowledge_validation stays on Sonnet.
--   3. founder_instruction 1219 records that 1571 superseded it for the T2 chat classes, on eval A's evidence.
-- Code needs no change at apply: ai_reply.ts and brief_answer.ts follow the route (routePrimary, the gateway's ladder).
--
-- Prevented by: scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql (section 4: the 'chat' route is Luna Pro >
-- Sonnet, 'review' Qwen > Sonnet; scripts/checks/every_model_class_is_on_the_founders_matrix.test.mjs replays this file while
-- its pending note exists) and the verdict row at the end of this file.
--   after evals A and C pass: node scripts/apply_sql.mjs scripts/sql/customer_chat_and_the_reviewer_move_once_their_evals_pass.sql --apply --ddl --seat it_engineer

update public.model_policy
   set model_primary = 'openai/gpt-6-luna-pro', model_fallback = 'anthropic/claude-sonnet-5.5',
       rationale = coalesce(rationale || ' | ', '') || '10 Nov 2026, ruling 1571 on eval A (docs/reports/2026-11-10-model-routing-evals.md): Luna Pro first (USD 0.10/0.50), Sonnet 5.5 the second rung. Supersedes 1219 for this class.'
 where task_class in ('conversation_reply', 'customer_portal_assistant', 'visitor_chat')
   and (model_primary, model_fallback) = ('anthropic/claude-sonnet-5.5', 'openai/gpt-6-luna-pro');

update public.model_policy
   set model_primary = 'qwen/qwen3.8-flash', model_fallback = 'anthropic/claude-sonnet-5.5',
       rationale = coalesce(rationale || ' | ', '') || '10 Nov 2026, ruling 1571 on eval C (docs/reports/2026-11-10-model-routing-evals.md): the reviewer of OpenAI authors is Qwen 3.8 Flash (USD 0.15/0.47), another family; Sonnet 5.5 behind it.'
 where task_class in ('knowledge_validation', 'sales_engineer__knowledge_validation')
   and (model_primary, model_fallback) = ('anthropic/claude-sonnet-5.5', 'openai/gpt-6-luna-pro');

update public.model_fallback_chain
   set model = case rung when 1 then 'openai/gpt-6-luna-pro' else 'anthropic/claude-sonnet-5.5' end,
       rationale = case rung when 1 then '10 Nov 2026, ruling 1571 on eval A: a conversation reply runs on Luna Pro first. Carries language only; facts come from the fact pack.'
                             else '10 Nov 2026, ruling 1571 on eval A: Sonnet 5.5 is the second rung. Same fact pack and the same boundaries: a fallback is not a relaxation.' end
 where purpose = 'whatsapp_conversation' and rung in (1, 2) and active
   and (select string_agg(model, '>' order by rung) from public.model_fallback_chain where purpose = 'whatsapp_conversation' and active)
       = 'anthropic/claude-sonnet-5.5>openai/gpt-6-luna-pro>deterministic';

update public.founder_instruction
   set note = coalesce(note || ' | ', '') || '10 Nov 2026: superseded for the T2 chat classes (conversation_reply, customer_portal_assistant, visitor_chat) by 1571, on eval A (docs/reports/2026-11-10-model-routing-evals.md): Luna Pro first, Sonnet 5.5 the second rung. Sonnet stays where an eval has not moved a class.',
       updated_at = now()
 where id = 1219 and coalesce(note, '') not like '%superseded for the T2 chat classes%';

with bad as (
  select c || ' runs ' || coalesce(p.model_primary, '-') || '>' || coalesce(p.model_fallback, '-') w
    from (values ('conversation_reply', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'),
                 ('customer_portal_assistant', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'),
                 ('visitor_chat', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'),
                 ('knowledge_validation', 'qwen/qwen3.8-flash', 'anthropic/claude-sonnet-5.5'),
                 ('sales_engineer__knowledge_validation', 'qwen/qwen3.8-flash', 'anthropic/claude-sonnet-5.5'),
                 ('ceo__knowledge_validation', 'anthropic/claude-sonnet-5.5', 'openai/gpt-6-luna-pro')) v(c, pm, fm)
    left join public.model_policy p on p.task_class = v.c
   where (p.model_primary, p.model_fallback) is distinct from (v.pm, v.fm)
  union all select 'the WhatsApp chain is ' || coalesce((select string_agg(model, '>' order by rung) from public.model_fallback_chain
                    where purpose = 'whatsapp_conversation' and active), 'empty')
   where (select string_agg(model, '>' order by rung) from public.model_fallback_chain where purpose = 'whatsapp_conversation' and active)
         is distinct from 'openai/gpt-6-luna-pro>anthropic/claude-sonnet-5.5>deterministic'
  -- the reviewer is never its author's family: over a Luna Pro author Qwen, over a Sonnet or Opus author never Anthropic
  union all select 'knowledge_validation over ' || a || ' routes ' || coalesce(r->>'model', '-') || '>' || coalesce(r->>'fallback', '-')
    from (values ('openai/gpt-6-luna-pro', 'openai'), ('anthropic/claude-sonnet-5.5', 'anthropic'), ('anthropic/claude-opus-5.5', 'anthropic')) v(a, fam)
    cross join lateral (select public.fn_ai_route_review_for('knowledge_validation', v.a, 'sales_engineer', null, null, null) r) x
   where r->>'model' is null or split_part(r->>'model', '/', 1) = v.fam or split_part(coalesce(r->>'fallback', 'x/'), '/', 1) = v.fam
  union all select 'founder_instruction 1219 does not record the supersession'
   where not exists (select 1 from public.founder_instruction where id = 1219 and note like '%superseded for the T2 chat classes%'))
select case when count(*) = 0 then 'PROBE OK: chat on Luna Pro > Sonnet, reviewer Qwen > Sonnet, chain follows, 1219 noted'
            else 'PROBE FAILED: ' || string_agg(w, '; ') end as verdict
  from bad;
