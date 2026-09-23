-- THE AUTHOR CLOSES THE REVIEW HANDOFF, AND SAYS WHICH KIND IT CLOSES (23 Sep 2026; seat: marketing).
-- #876 registered ('deliberation.review', marketing, ceo) as an originator-closed kind. Its closer already exists:
-- fn_seat_deliberation_close (a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql, #877) sets qd.handoff_closer
-- to the author seat and completes the handoff. every_report_and_handoff_comes_back found the kind orphaned because the
-- closer never names it. The completion evidence now records the kind it closes. Copied from #877 with that one key
-- added; CREATE OR REPLACE keeps the ACL and the revoke is restated.
--   node scripts/apply_sql.mjs scripts/sql/the_author_closes_the_review_handoff_and_names_its_kind.sql --apply --ddl --seat marketing

begin;

create or replace function public.fn_seat_deliberation_close(p_id bigint, p_closed_by text, p_outcome text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; c public.seat_deliberation_turn;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if p_closed_by is distinct from d.author_seat then
    raise exception 'only the originating seat % closes deliberation %', d.author_seat, p_id;
  end if;
  if d.status not in ('reviewed', 'no_independent_reviewer') or coalesce(btrim(p_outcome), '') = '' then
    raise exception 'deliberation % closes after the review (or its escalation), with an outcome', p_id;
  end if;
  select * into c from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'compare' and t.status = 'recorded' order by t.round desc limit 1;
  update public.seat_deliberation set status = 'closed', outcome = p_outcome, closed_at = now() where id = p_id;
  if d.handoff_id is not null then
    -- trg_handoff_only_originator_closes: the author seat names itself, only for this transaction.
    perform set_config('qd.handoff_closer', d.author_seat, true);
    perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', p_id,
      'final_verdict', c.verdict, 'reviewer_model', c.model, 'reviewer_provider', c.provider,
      'ended', d.status, 'outcome', p_outcome, 'closed_by', p_closed_by));
  end if;
  return jsonb_build_object('ok', true, 'deliberation_id', p_id, 'final_verdict', c.verdict, 'ended', d.status);
end $fn$;
revoke execute on function public.fn_seat_deliberation_close(bigint, text, text) from public, anon, authenticated;

commit;
