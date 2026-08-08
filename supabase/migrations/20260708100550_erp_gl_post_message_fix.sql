-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708100550   name: erp_gl_post_message_fix
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_gl_post(p_journal bigint)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare d numeric(18,2); c numeric(18,2); n int; st text;
begin
  select status into st from public.gl_journal where id=p_journal;
  if st is null then raise exception 'journal % not found', p_journal; end if;
  if st='posted' then return p_journal; end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from public.gl_journal_lines where journal_id=p_journal;
  if n < 2 then raise exception 'journal % needs at least 2 lines', p_journal; end if;
  if d <> c then raise exception 'journal % out of balance: debits % <> credits %', p_journal, to_char(d,'FM999999990.00'), to_char(c,'FM999999990.00'); end if;
  if d = 0 then raise exception 'journal % has zero amount', p_journal; end if;
  update public.gl_journal
     set status='posted', posted_at=now(),
         entry_no = coalesce(entry_no, 'JE-'||lpad(p_journal::text,6,'0'))
   where id=p_journal;
  return p_journal;
end $$;
