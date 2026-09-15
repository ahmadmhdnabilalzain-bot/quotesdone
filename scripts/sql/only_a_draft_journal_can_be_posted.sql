-- ONLY A DRAFT JOURNAL CAN BE POSTED.
--
-- Assigned: accountant.
--
-- WHAT WAS MEASURED (15 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * gl_journal.status is CHECKed to exactly 'draft', 'posted', 'void' (constraint on the table).
--     Live rows: 63 posted, 4 void, 0 draft.
--   * public.fn_gl_post(bigint) returned early only for 'posted' and otherwise went on to post, so a
--     'void' journal (a reversed one) fell through to the balance checks and the UPDATE to 'posted'.
--     trg_gl_journal_immutable refuses that UPDATE today ("Void journal % is terminal"), so no void
--     journal has ever been re-posted; the routine itself simply did not say so.
--   * Callers: fn_gl_entry, which posts the journal it inserted a moment earlier (always a draft).
--     No other routine body calls it (fn_gl_journal_immutable only names it in a comment; fn_gl_reverse
--     does not call it), no edge function, page or check calls it, and no cron job names it.
--
-- WHAT THIS CHANGES: fn_gl_post refuses unless the journal is a draft. A posted journal is no longer
-- an idempotent no-op either: re-posting is not a meaningful request, and its only caller never makes
-- it. The body is otherwise the one live since 20260708100550_erp_gl_post_message_fix.sql, which had
-- no file under scripts/sql; this file becomes its canonical definition.
-- WHAT THIS DOES NOT CHANGE: trg_gl_journal_immutable stays exactly as it is; the trigger remains the
-- guard of last resort and this is the first one. Void still happens only through fn_gl_reverse.
--
--   node scripts/apply_sql.mjs scripts/sql/only_a_draft_journal_can_be_posted.sql --apply --ddl

create or replace function public.fn_gl_post(p_journal bigint)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare d numeric(18,2); c numeric(18,2); n int; st text;
begin
  select status into st from public.gl_journal where id=p_journal;
  if st is null then raise exception 'journal % not found', p_journal; end if;
  if st is distinct from 'draft' then
    raise exception 'journal % is %; only a draft can be posted (a posted journal is corrected with fn_gl_reverse, and a void one is terminal)', p_journal, st;
  end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from public.gl_journal_lines where journal_id=p_journal;
  if n < 2 then raise exception 'journal % needs at least 2 lines', p_journal; end if;
  if d <> c then raise exception 'journal % out of balance: debits % <> credits %', p_journal, to_char(d,'FM999999990.00'), to_char(c,'FM999999990.00'); end if;
  if d = 0 then raise exception 'journal % has zero amount', p_journal; end if;
  update public.gl_journal
     set status='posted', posted_at=now(),
         entry_no = coalesce(entry_no, 'JE-'||lpad(p_journal::text,6,'0'))
   where id=p_journal;
  return p_journal;
end $function$;

-- CREATE OR REPLACE keeps the live ACL (postgres, service_role). Stated anyway, by exact signature.
revoke execute on function public.fn_gl_post(bigint) from public, anon, authenticated;

-- PROBE. DDL lives in this file, so nothing here may raise on success. It writes nothing: it calls
-- the routine on one existing void and one existing posted journal inside sub-blocks, and the
-- refusal comes before any UPDATE. It then asserts both rows are byte-for-byte what they were.
do $$
declare v_void bigint; v_posted bigint; b_void jsonb; b_posted jsonb; m_void text; m_posted text;
begin
  select id, to_jsonb(j) into v_void, b_void from public.gl_journal j where status = 'void' order by id limit 1;
  select id, to_jsonb(j) into v_posted, b_posted from public.gl_journal j where status = 'posted' order by id limit 1;
  if v_void is not null then
    begin perform public.fn_gl_post(v_void); m_void := 'NOT REFUSED';
    exception when others then m_void := sqlerrm; end;
    if m_void not like '%only a draft can be posted%' then raise exception 'fn_gl_post did not refuse void journal %: %', v_void, m_void; end if;
    if (select to_jsonb(j) from public.gl_journal j where id = v_void) is distinct from b_void then raise exception 'probe changed journal %', v_void; end if;
  end if;
  if v_posted is not null then
    begin perform public.fn_gl_post(v_posted); m_posted := 'NOT REFUSED';
    exception when others then m_posted := sqlerrm; end;
    if m_posted not like '%only a draft can be posted%' then raise exception 'fn_gl_post did not refuse posted journal %: %', v_posted, m_posted; end if;
    if (select to_jsonb(j) from public.gl_journal j where id = v_posted) is distinct from b_posted then raise exception 'probe changed journal %', v_posted; end if;
  end if;
  raise notice 'only_a_draft_journal_can_be_posted: void % refused, posted % refused, both unchanged', v_void, v_posted;
end $$;
