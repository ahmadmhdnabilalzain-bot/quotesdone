-- A DECISION NAMES THE RECALLED CASE IT FOLLOWED. Seat: it_engineer (shared platform, all six seats).
-- 28 Sep 2026, founder_instruction 887 (the learning-loop recall proof).
--
-- WHAT WAS MEASURED (production, 28 Sep 2026 13:10 UTC): seat_judgement held 9 judgements, all 9 with their
-- recall record and all 9 still status 'recalled' with decided_at null. recallCases (case_recall.ts) opens a
-- judgement on every recall, but only think() ever closed one (fn_judgement_decided); the deterministic
-- decision paths recalled and decided without saying so. And no path, think() included, recorded WHICH
-- recalled case the decision followed: the accountant wrote "precedent=#<id>" into an expense note's free
-- text, which no check and no metric can read. A trace that says what was remembered but not what was used
-- cannot show that the memory changed anything.
--
-- WHAT THIS CHANGES
--   1. seat_judgement.followed_case_ids bigint[]: the recalled cases the decision followed. Empty when the
--      seat decided without a precedent; null when the path did not say.
--   2. fn_judgement_decided gains p_followed bigint[] (default null, so every existing 5-argument caller
--      keeps working). A case id that is NOT in the judgement's own recall record is refused (22023): a
--      decision cannot claim to follow a case it never recalled. Re-deciding a judgement replaces its
--      decision; that is how a held judgement is answered later.
--
-- WHAT IT DOES NOT CHANGE. fn_judgement_record, the recall routines and the outcome triggers are untouched.
-- The TypeScript half (case_recall.ts decideJudgement, think(), the accountant classification and the
-- marketing plan) ships in the same PR and is deployed with the release that applies this file.
--
-- Pending: scripts/sql/pending/a_decision_names_the_recalled_case_it_followed.txt.
-- Proved by: scripts/eval/learning_loop_recall_proof.mjs (aborted transaction, ZZ DEMO subjects).

alter table public.seat_judgement add column if not exists followed_case_ids bigint[];
comment on column public.seat_judgement.followed_case_ids is
  'The recalled cases (seat_case_memory.id) this decision followed; each one must be in recall->cases. Empty = decided without a precedent; null = the path did not say.';

-- The 5-argument form is replaced, not overloaded: two forms with a defaulted argument make a named RPC
-- ambiguous. After the DROP the CREATE is a fresh one and grants EXECUTE to PUBLIC, so the revoke below is required.
drop function if exists public.fn_judgement_decided(bigint, text, text, numeric, text);
create or replace function public.fn_judgement_decided(p_id bigint, p_status text, p_decision text, p_confidence numeric, p_model text,
                                            p_followed bigint[] default null)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_recalled bigint[]; v_stray bigint[];
begin
  if p_followed is not null then
    select coalesce(array_agg((c->>'case_id')::bigint), '{}') into v_recalled
      from public.seat_judgement j, jsonb_array_elements(coalesce(j.recall->'cases', '[]'::jsonb)) c
     where j.id = p_id;
    select coalesce(array_agg(x), '{}') into v_stray from unnest(p_followed) x where not (x = any (coalesce(v_recalled, '{}')));
    if cardinality(v_stray) > 0 then
      raise exception 'judgement % did not recall case(s) %, so it cannot have followed them', p_id, v_stray using errcode = '22023';
    end if;
  end if;
  update public.seat_judgement
     set status = p_status, decision = left(p_decision, 2000), confidence = p_confidence, model = p_model, decided_at = now(),
         -- array_agg over nothing is null, and '{}' (no precedent followed) must stay distinct from null (not said)
         followed_case_ids = case when p_followed is not null
                                  then coalesce((select array_agg(distinct x order by x) from unnest(p_followed) x), '{}') end
   where id = p_id and p_status in ('answered','held');
  return found;
end $fn$;
revoke execute on function public.fn_judgement_decided(bigint, text, text, numeric, text, bigint[]) from public, anon, authenticated;
