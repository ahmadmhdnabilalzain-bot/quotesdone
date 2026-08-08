-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802170028   name: p2_c1_stage_a_fix_supersede_ordering
-- SHA-256 of the applied SQL: f2b7d0ec034a7083de5cef70e7abe332b623c31759abc2af6b7644a07c4c5805
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Found by Stage A test 1, which is exactly the test that was supposed to find it.
--
-- The partial unique index says: at most ONE live answer per (group, field). Superseding inserted
-- the replacement first and marked the old row superseded second, so for one statement both rows
-- were live and the index refused it. The invariant was right; the write order was wrong.
--
-- Fix: allocate the new id first, point the old row at it, then insert. That requires the
-- self-referencing foreign key to be deferred to end of transaction - which is correct anyway,
-- because "superseded_by must reference a real answer" is a statement about the committed state,
-- not about the middle of a two-statement handover.

alter table public.inquiry_answer drop constraint if exists inquiry_answer_superseded_by_fkey;
alter table public.inquiry_answer
  add constraint inquiry_answer_superseded_by_fkey
  foreign key (superseded_by) references public.inquiry_answer(id)
  deferrable initially deferred;

create or replace function public.fn_inquiry_answer_supersede(
  p_live_id bigint, p_group_id bigint, p_field_id text, p_value text, p_unit text,
  p_scope text, p_precedence public.answer_precedence, p_source_kind text, p_actor text)
returns bigint language plpgsql security definer set search_path to 'public' as $fn$
declare v_new_id bigint;
begin
  v_new_id := nextval(pg_get_serial_sequence('public.inquiry_answer','id'));
  update public.inquiry_answer set superseded_by = v_new_id where id = p_live_id;
  insert into public.inquiry_answer (id, group_id, field_id, value, unit, scope, precedence,
                                     source_kind, confirmed_at, confirmed_by)
  values (v_new_id, p_group_id, p_field_id, p_value, p_unit, p_scope, p_precedence, p_source_kind,
          case when p_precedence = 'customer_confirmed' then now() end,
          case when p_precedence = 'customer_confirmed' then p_actor end);
  insert into public.inquiry_answer_scope (answer_id, workstream_id)
    select v_new_id, workstream_id from public.inquiry_answer_scope where answer_id = p_live_id
    on conflict do nothing;
  return v_new_id;
end $fn$;

revoke all on function public.fn_inquiry_answer_supersede(bigint, bigint, text, text, text, text, public.answer_precedence, text, text) from public, anon, authenticated;
;