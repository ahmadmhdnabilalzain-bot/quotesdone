-- THE REFLECTION CEILING WAS PRICED AT HALF WHAT A STEP ACTUALLY COSTS.
--
-- decision_policy.workflow_reflection_steps_per_day = 24, and its own description records the
-- working: "Set to 24 on 13 Aug 2026 from measured cost of AED 0.086/step (11 Aug: 179 steps,
-- AED 38.00 estate spend; 10 Aug: 0 steps, AED 22.58)".
--
-- That arithmetic divides an ESTATE-WIDE daily total by a step count. AED 38.00 on 11 Aug is
-- everything the company spent on AI that day — agent_brain, action_worker, exec_agents, kb_deepen
-- and the rest — not what the 179 workflow steps cost. It is the same defect this codebase has
-- named before in other places: a number measuring something other than what its name says.
--
-- MEASURED DIRECTLY, from ai_cost_log rows whose fn IS workflow_dispatch, over the four days
-- 11-14 Aug:
--
--     24.3 calls/day, AED 3.54/day, AED 0.146 per step, AED 106/month at this rate
--
-- AED 0.146, not AED 0.086 — 70% higher. At 24 steps a day the ceiling authorises about AED 106 a
-- month, which against a measured trailing-4-day estate run rate of AED 29.7/day (~AED 890/month)
-- is 12% of everything the company spends, on reflection, while the marketplace has taken 0
-- inquiries, 0 quotes and 0 trades.
--
-- LOWERED TO 8. That is AED 1.17/day, ~AED 35/month, and it keeps a real reflection cadence: eight
-- non-demand steps a day is still 240 a month.
--
-- WHAT THIS DOES NOT TOUCH, AND THE DESIGN IS ALREADY RIGHT ABOUT IT. The ceiling counts NON-DEMAND
-- steps only. fn_workflow_step_sweep exempts demand-linked work entirely — its own refusal message
-- says so: "the daily reflection ceiling is spent and no revenue-path step is waiting". A real RFQ,
-- quote or customer registration is never throttled by this number, today or after this change.
-- When trading starts, revenue steps flow regardless and this row should be revisited from measured
-- use rather than defended.
--
-- REVERSIBLE WITHOUT A DEPLOY, which is why it is a policy row. One UPDATE restores 24.
--
-- The 82 workflow_step_run rows sitting at status='ready' are NOT stalled by this and are not
-- evidence against it: 29 of them carry action_class = NULL, which no executor can ever match, and
-- fn_workflow_step_sweep already raises "Classify the workflow steps no executor can run" for that.
-- The rest are queued behind the ceiling by design.

update decision_policy
   set value = '8'::jsonb,
       description = 'Non-demand (reflection) workflow steps dispatchable per UTC day. Lowered '
                     '24 -> 8 on 14 Aug 2026. The previous figure was derived from AED 0.086/step, '
                     'which divided ESTATE-WIDE daily spend by a step count; measured directly from '
                     'ai_cost_log rows where fn=''workflow_dispatch'' over 11-14 Aug the true cost '
                     'is AED 0.146/step (24.3 calls/day, AED 3.54/day, ~AED 106/month — 12% of the '
                     'AED 890/month trailing run rate) while the marketplace has taken 0 inquiries, '
                     '0 quotes and 0 trades. 8/day is ~AED 35/month and still 240 reflection steps '
                     'a month. Demand-linked steps are exempt from this ceiling and are never '
                     'throttled by it. Revisit from measured use once trading starts.',
       updated_at = now()
 where key = 'workflow_reflection_steps_per_day';
