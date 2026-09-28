-- A REVERSAL NETS TO ZERO IN EVERY REPORT, NOT ONLY IN THE RAW LINES.
--
-- Measured before: fn_gl_reverse marked the original 'void' and left its reversal 'posted'. Every
-- ledger reader (trial balance, P&L, bank balance, the accountant duties) counts status = 'posted'
-- only, so after a reversal the book carried the reversal alone: the opposite of the entry it was
-- meant to cancel. It happened on journals 98, 131, 140 and 690, restated by PR #1014.
--
-- The fix voids BOTH sides. Keeping the original posted was the other option; it was rejected
-- because the checks in force rely on the original ending void: fn_gl_journal_immutable's
-- "void is terminal" branch, only_a_draft_journal_can_be_posted's probe (it picks a void journal),
-- test_money_never_reaches_the_books (690 void), and the supplier_dues readers that treat a void
-- journal as settled. The reversal goes void through the same trigger exit (status void + reverses
-- set, nothing else changed), with reverses pointing back at the original.
--
-- Only the routine changes. No existing journal is touched: the four past pairs are already
-- corrected by #1014, and voiding their reversals now would undo that restatement.
--
-- prevented by: scripts/checks/gl_reverse_fixtures.sql

create or replace function public.fn_gl_reverse(p_journal_id bigint, p_reason text)
returns bigint
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_orig  public.gl_journal%rowtype;
  v_lines jsonb;
  v_new   bigint;
  v_dr    numeric;
  v_cr    numeric;
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'a reversal needs a reason: reversing a posted entry is a decision and the ledger must carry why';
  end if;

  select * into v_orig from public.gl_journal where id = p_journal_id;
  if not found then
    raise exception 'no journal %', p_journal_id;
  end if;
  if v_orig.status <> 'posted' then
    raise exception 'journal % has status %, not posted; only a posted entry can be reversed', p_journal_id, v_orig.status;
  end if;
  if exists (select 1 from public.gl_journal where reverses = p_journal_id) then
    raise exception 'journal % has already been reversed; reversing it twice would double the correction', p_journal_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
             'account', l.account_code,
             'debit',   l.credit,
             'credit',  l.debit,
             'memo',    'Reversal of journal ' || p_journal_id || coalesce(': ' || l.memo, '')
           ) order by l.line_no), '[]'::jsonb)
    into v_lines
    from public.gl_journal_lines l
   where l.journal_id = p_journal_id;

  if jsonb_array_length(v_lines) = 0 then
    raise exception 'journal % has no lines, so there is nothing to reverse', p_journal_id;
  end if;

  v_new := public.fn_gl_entry(
    (now() at time zone 'Asia/Dubai')::date,
    'REVERSAL of journal ' || p_journal_id || ' (' || coalesce(v_orig.memo, '') || ') — ' || p_reason,
    'reversal', p_journal_id::text, v_lines, 'fn_gl_reverse');

  -- BOTH SIDES GO VOID, each pointing at the other, through the one exit the immutability trigger
  -- allows. Reports count posted journals only; voiding just the original left the reversal
  -- counted on its own and overstated the ledger.
  update public.gl_journal set status = 'void', reverses = v_new        where id = p_journal_id;
  update public.gl_journal set status = 'void', reverses = p_journal_id where id = v_new;

  if exists (select 1 from public.gl_journal where id in (p_journal_id, v_new) and status <> 'void') then
    raise exception 'journal % or its reversal % is still posted; the pair would not net to zero in the reports', p_journal_id, v_new;
  end if;

  select sum(l.debit), sum(l.credit) into v_dr, v_cr
    from public.gl_journal_lines l
   where l.journal_id in (p_journal_id, v_new);
  if round(coalesce(v_dr, 0), 2) <> round(coalesce(v_cr, 0), 2) then
    raise exception 'the reversal did not net to zero: DR % CR % across journals % and %',
      v_dr, v_cr, p_journal_id, v_new;
  end if;

  return v_new;
end;
$function$;

comment on function public.fn_gl_reverse(bigint, text) is
  'Reverses one posted journal: writes a new journal carrying the opposite of every line, then marks '
  'BOTH the original and the reversal void, each pointing at the other, so every posted-only report '
  'nets to zero. Requires a reason. Refuses a journal that is not posted or already reversed, and '
  'refuses to stand if the pair does not net to zero. 28 Sep 2026: before, only the original went '
  'void and the posted reversal overstated the ledger (journals 98, 131, 140, 690; restated by #1014).';
