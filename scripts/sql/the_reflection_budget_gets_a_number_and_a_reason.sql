-- workflow_reflection_steps_per_day: 6 -> 24. The founder asked for the number to be decided from
-- evidence rather than chosen, so here is the evidence and the arithmetic.
--
-- WHAT A REFLECTION STEP COSTS. Measured on production:
--   11 Aug: 179 workflow steps dispatched, whole estate spent AED 38.00
--   10 Aug:   0 workflow steps dispatched, whole estate spent AED 22.58
--   -> AED 15.42 / 179 = AED 0.086 per step, which agrees with ai_cost_log's own
--      agent_reasoning class at AED 0.0968 per call (616 calls, AED 59.64, 3 days).
-- So the ceiling itself is priced: 6/day = AED 0.52/day, 24/day = AED 2.06/day (~AED 63/month)
-- against an estate currently spending ~AED 20/day. A quadrupling of reflection costs about a
-- tenth of one day's existing spend.
--
-- WHAT 6 COSTS THE COMPANY. There are 43 classified, ready, unfinished reflection steps parked
-- right now: health_report 21, knowledge_fill 19, coordinate 3. At 6/day that queue needs seven
-- days to drain BEFORE counting arrivals, and 11-12 Aug produced 211 dispatches in two days, so
-- arrivals comfortably exceed 6. A health_report raised today therefore runs next week, describing
-- a state the company has already left. That is the loss: not fewer reports, but reports about the
-- past.
--
-- WHY NOT UNCAPPED. 11 Aug dispatched 179 steps in one day, 138 of them `recommend`. 24 is 13% of
-- that: a generator that runs away cannot spend more than ~AED 2/day, and cannot bury the founder
-- under 138 recommendations.
--
-- KNOWN WEAKNESS, NAMED RATHER THAN HIDDEN. This is one FIFO ceiling over two unlike populations.
-- Over 14 days `recommend` ran 166 times against health_report 5 and forecast 5, so `recommend`
-- can consume a whole day's allowance and starve the management reports. At 24 today's mix leaves
-- room for both (~19 + ~5); if the health_report backlog keeps growing at 24/day, the fix is a
-- per-class allowance in fn_workflow_step_claim, not a bigger single number.
--
-- cos_reflection_tasks_per_day is deliberately LEFT at 6: it governs a different population, and
-- moving two ceilings at once would make the next measurement unreadable.
update public.decision_policy
   set value = '24'::jsonb,
       description = 'Non-demand (reflection) workflow steps dispatchable per UTC day. Set to 24 on '
                  || '13 Aug 2026 from measured cost of AED 0.086/step (11 Aug: 179 steps, AED 38.00 '
                  || 'estate spend; 10 Aug: 0 steps, AED 22.58) and a standing backlog of 43 ready '
                  || 'reflection steps that 6/day cannot drain. 24/day = ~AED 2.06/day. Raise only '
                  || 'with a measurement; if health_report starves behind recommend, split the '
                  || 'allowance per action_class instead of raising this.',
       updated_at = now()
 where key = 'workflow_reflection_steps_per_day';
