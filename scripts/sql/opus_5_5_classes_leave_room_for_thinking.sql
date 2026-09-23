-- opus_5_5_classes_leave_room_for_thinking.sql — it_engineer, 23 Sep 2026 (prompt audit finding 3).
--
-- Claude Opus 5.5 cannot turn thinking off, and its thinking tokens count toward max_tokens. The classes
-- that route to it (primary or fallback) were capped at 2000 (ceo_judgement and identity_redaction_verify,
-- every_seat_gets_the_model_its_own_work_needs.sql), so a long think leaves the structured answer truncated,
-- which ai_gateway reports and the callers fail closed on. ai_gateway now also adds THINKING_HEADROOM on
-- every Claude attempt (_shared/request_shape.ts); this raises the policy ceiling itself so a caller that
-- asks for more than 2000 is not silently cut back to it on these classes.
--
-- Scoped by the model the row names, not by a list of class names, so a class moved onto Opus 5.5 later is
-- covered and one moved off it is untouched. greatest() never lowers a row that is already higher.
update public.model_policy
   set max_tokens = greatest(coalesce(max_tokens, 0), 4000),
       rationale  = rationale || ' | 23 Sep 2026: max_tokens raised to at least 4000 because Opus 5.5 thinking counts toward it (opus_5_5_classes_leave_room_for_thinking.sql).'
 where 'anthropic/claude-opus-5.5' in (model_primary, model_fallback)
   and coalesce(max_tokens, 0) < 4000;

select case when exists (select 1 from public.model_policy
                          where 'anthropic/claude-opus-5.5' in (model_primary, model_fallback)
                            and coalesce(max_tokens, 0) < 4000)
            then 'PROBE FAILED: an Opus 5.5 class is still below 4000 max_tokens'
            else 'PROBE OK' end as verdict;
