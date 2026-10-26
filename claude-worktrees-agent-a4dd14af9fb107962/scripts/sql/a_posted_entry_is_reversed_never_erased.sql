-- A POSTED ENTRY IS REVERSED, NEVER ERASED.
--
-- The founder, 9 September 2026: "replicate no". The Gmail-inbox sweep had already booked two
-- Replicate invoices ($20.00 on 31 Aug, $20.00 on 4 Sep) and posted them to the ledger, because from
-- a receipt alone Replicate is indistinguishable from the AI vendors that ARE QuotesDone's. His
-- ruling makes them another company's cost, so they must come out of this book.
--
-- THE GAP THAT STOPPED THAT BEING POSSIBLE. gl_journal is immutable by trigger, correctly:
--
--     raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
--
-- and the trigger carves out exactly one exemption, for "the controlled void marking done by
-- fn_gl_reverse". Measured: **fn_gl_reverse does not exist.** Nothing in pg_proc matches. So the
-- guard directed every caller to a routine that was never built, and this ledger had NO WAY AT ALL
-- to correct a mis-booking -- the one thing a set of books must always be able to do. A guard whose
-- named remedy does not exist is a wall, not a control.
--
-- WHY REVERSAL RATHER THAN DELETION. The entry was really posted; pretending otherwise loses the
-- fact that the company once believed this cost was its own, which is exactly what an audit needs to
-- see. So the original stays, marked void and pointing at the entry that undid it, and a new journal
-- carries the opposite of every line. The pair nets to zero and both halves are readable forever.
--
-- The expense_entries ROW is deleted, though, because the spend report and every figure the founder
-- reads are computed from that table: a Replicate row left there would keep the total wrong, and the
-- reason it is gone lives in expense_vendor_billing_mailbox with his ruling attached, plus in the
-- reversal memo. The ledger keeps the history; the book keeps the truth.

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
  -- A REASON IS NOT OPTIONAL. Undoing a posted entry is a decision, and a ledger that records the
  -- reversal without the reason records that something was changed and hides why.
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

  -- Every line, with debit and credit exchanged. Built from the stored lines rather than recomputed,
  -- so a reversal cannot disagree with what was actually posted.
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

  -- The exemption the immutability trigger allows: posted -> void, with reverses set.
  update public.gl_journal
     set status = 'void', reverses = v_new
   where id = p_journal_id;

  -- THE PAIR MUST NET TO ZERO. If it does not, the correction is itself a defect and must not stand.
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

revoke execute on function public.fn_gl_reverse(bigint, text) from public;
grant execute on function public.fn_gl_reverse(bigint, text) to service_role;

comment on function public.fn_gl_reverse(bigint, text) is
  'Reverses one posted journal: writes a new journal carrying the opposite of every line, then marks '
  'the original void and pointing at it. Requires a reason -- a reversal is a decision and the ledger '
  'must carry why. Refuses a journal that is not posted, or one already reversed, and refuses to '
  'stand if the pair does not net to zero. Built 9 Sep 2026: trg_gl_journal_immutable had told every '
  'caller for months to "reverse it instead" and carved out an exemption for a routine of this name '
  'that HAD NEVER BEEN CREATED, so this ledger had no way to correct a mis-booking at all.';

-- ---------------------------------------------------------------------------------------------
-- THE CORRECTION THIS WAS BUILT FOR: Replicate is not QuotesDone's.
-- ---------------------------------------------------------------------------------------------
do $do$
declare
  v_j record;
  v_new bigint;
  v_reversed int := 0;
  v_entries_before int;
  v_entries_after int;
  v_dr numeric; v_cr numeric;
  v_still int;
begin
  select count(*) into v_entries_before from public.expense_entries where vendor = 'Replicate';
  -- POSITIVE CONTROL. If Replicate is not in the book, this block would "succeed" while reversing
  -- nothing, and the assertions below would pass on an empty set.
  if v_entries_before = 0 then
    raise notice 'Replicate is not in expense_entries — nothing to reverse (already corrected, or never booked)';
  else
    for v_j in
      select g.id, g.memo from public.gl_journal g
       where g.source = 'expense'
         and g.status = 'posted'
         and g.source_ref in (select id::text from public.expense_entries where vendor = 'Replicate')
    loop
      v_new := public.fn_gl_reverse(v_j.id,
        'Not a QuotesDone cost. Founder''s ruling 9 Sep 2026, in his own words: "replicate no". '
        || 'Booked in good faith by the Gmail-inbox sweep, which cannot tell one AI vendor from '
        || 'another from a receipt alone.');
      v_reversed := v_reversed + 1;
    end loop;

    delete from public.expense_entries where vendor = 'Replicate';

    select count(*) into v_entries_after from public.expense_entries where vendor = 'Replicate';
    if v_entries_after <> 0 then
      raise exception '% Replicate entry/entries survived the deletion', v_entries_after;
    end if;
    if v_reversed <> v_entries_before then
      raise exception 'reversed % journal(s) for % booked entry/entries — they must match', v_reversed, v_entries_before;
    end if;
  end if;

  -- THE LEDGER MUST STILL BALANCE, counting every journal including the voided ones and their
  -- reversals. A correction that unbalances the books is worse than the error it corrects.
  select sum(debit), sum(credit) into v_dr, v_cr from public.gl_journal_lines;
  if round(coalesce(v_dr,0),2) <> round(coalesce(v_cr,0),2) then
    raise exception 'the ledger no longer balances after the correction: DR % CR %', v_dr, v_cr;
  end if;

  -- And nothing ruled out of scope may remain booked.
  select count(*) into v_still
    from public.expense_entries e
    join public.expense_vendor_billing_mailbox m on m.vendor = e.vendor
   where m.in_ledger_scope = false;
  if v_still > 0 then
    raise exception '% booked entry/entries still belong to a vendor ruled out of scope', v_still;
  end if;

  raise notice 'reversed % journal(s), removed % Replicate entry/entries, ledger balances at DR % = CR %',
    v_reversed, v_entries_before, v_dr, v_cr;
end
$do$;
