-- THE COMPANY RECOVERS NO INPUT VAT, SO 1150 IS MOVED INTO COST.
--
-- Assigned: accountant. 13 Nov 2026 (founder_instruction 1687: "VAT is not for us"; memory trade-licence-and-vat-status-
-- are-closed: QuotesDone is not VAT-registered, no TRN, registration only above AED 375k of taxable supplies).
--
-- ══ MEASURED ON PRODUCTION, 13 Nov 2026 (read only) ═══════════════════════════════════════════════════
--   Account 1150 "VAT Recoverable (Input)" holds AED 284.41 posted (the workflow audit's AED 288.31 also counted void journal
--   98 and its restatement, 1.95 each) of VAT stated on 27 expense receipts (GoDaddy, Google,
--   Anthropic, OpenAI, Tasjeel.ae, GlockApps), posted by public.fn_expense_post_to_gl, which split each receipt into
--   net -> the expense account and VAT -> 1150. A business that is not registered for VAT cannot reclaim input VAT from
--   the FTA, so that asset does not exist: the VAT is part of what each service cost. Expenses are understated and
--   assets overstated by the same amount.
--
-- ══ WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════
--   1. A CORRECTING ENTRY PER SOURCE JOURNAL, never an edit (posted journals are immutable): for every posted journal
--      whose 1150 lines do not net to zero, a journal source 'vat_input_reclass', source_ref the original journal's id,
--      dated today: Dr the expense account that journal debited / Cr 1150 for the VAT (the reverse for a journal that
--      credited 1150, the reversal of JE-000098). Idempotent: a journal already reclassed is skipped. After it, 1150 is 0.
--      Rehearsed 13 Nov 2026 (rolled back): 27 reclass journals, AED 284.41 moved, 1150 = 0.00, every journal balanced.
--   2. GOING FORWARD: fn_expense_post_to_gl books the whole receipt to the expense account; the VAT stays in the memo.
--   3. 1150 is marked inactive with the reason, so nothing posts to it unnoticed.
--
-- NOT CHANGED: the expenses themselves, their dates, the periods they sit in (the reclass is dated in the open period;
-- the closed months stay as filed), any report that reads balances (they now read 1150 = 0 and the cost in full).
-- The founder confirms the treatment (the hand-back of 13 Nov 2026 names it).
--
-- Pending: scripts/sql/pending/the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.txt.
--
-- THE APPLY MUST NOT FREEZE THE SITE (coordinator's review 3, item 2): it takes row locks on gl_journal (215 rows, 13 Nov)
-- and replaces one routine; lock_timeout makes it FAIL after 1.5 seconds rather than queue behind a long query. The release
-- runbook (docs/runbooks/a_paid_reveal_release_13_nov_2026.md) says when and how to re-run it.
set local lock_timeout = '1500ms';

do $reclass$
declare r record; v_acct text; v_n int := 0;
begin
  for r in
    select j.id, j.entry_no, j.memo, sum(l.debit - l.credit) as vat
      from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
     where l.account_code = '1150' and j.status = 'posted'
       and not exists (select 1 from public.gl_journal x where x.source = 'vat_input_reclass' and x.source_ref = j.id::text)
     group by j.id, j.entry_no, j.memo
    having sum(l.debit - l.credit) <> 0
     order by j.id
  loop
    -- the cost account the receipt was booked to: the journal's own largest expense line, else General & Administrative
    select l.account_code into v_acct
      from public.gl_journal_lines l join public.gl_accounts a on a.code = l.account_code
     where l.journal_id = r.id and a.type = 'expense'
     order by greatest(l.debit, l.credit) desc limit 1;
    v_acct := coalesce(v_acct, '6300');
    perform public.fn_gl_entry((now() at time zone 'Asia/Dubai')::date,
      'Input VAT is not recoverable (QuotesDone is not VAT-registered): VAT from ' || coalesce(r.entry_no, r.id::text)
        || ' moved from 1150 into the cost it was part of',
      'vat_input_reclass', r.id::text,
      case when r.vat > 0
        then jsonb_build_array(jsonb_build_object('account', v_acct, 'debit', r.vat, 'memo', 'non-recoverable input VAT, ' || coalesce(r.entry_no, '')),
                               jsonb_build_object('account', '1150', 'credit', r.vat))
        else jsonb_build_array(jsonb_build_object('account', '1150', 'debit', -r.vat),
                               jsonb_build_object('account', v_acct, 'credit', -r.vat, 'memo', 'non-recoverable input VAT reversed, ' || coalesce(r.entry_no, '')))
      end, 'accountant');
    v_n := v_n + 1;
  end loop;
  raise notice 'vat_input_reclass journals posted: %', v_n;
end $reclass$;

update public.gl_accounts
   set is_active = false,
       description = 'Not used: QuotesDone is not VAT-registered, so input VAT is not recoverable and is part of the cost (13 Nov 2026, the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql).'
 where code = '1150';

CREATE OR REPLACE FUNCTION public.fn_expense_post_to_gl(p_entry_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e record; fx numeric; acct text; amt_aed numeric(18,2); vat_aed numeric(18,2);
        net_aed numeric(18,2); jid bigint; lines jsonb;
begin
  select id, vendor, category, amount, upper(coalesce(currency,'AED')) as cur, vat_amount,
         coalesce(charged_on, created_at::date) as d, note
    into e
    from public.expense_entries where id = p_entry_id;
  if not found or coalesce(e.amount,0) <= 0 then return null; end if;
  -- a ZZ DEMO expense is a rehearsal's, never the company's (same marker as fn_gl_sync_business)
  if (coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo' then return null; end if;

  -- already posted (by this routine or by fn_gl_sync_business): return it, never post twice
  select g.id into jid from public.gl_journal g
   where g.source='expense' and g.source_ref = e.id::text limit 1;
  if jid is not null then return jid; end if;

  select num_value into fx from public.gl_settings where key='usd_to_aed';
  fx := coalesce(fx, 3.6725);

  -- Same refusal as fn_gl_sync_business: a currency with no rate is NOT booked at 1:1. An
  -- understated ledger that says so beats a wrong one that does not.
  if e.cur not in ('AED','USD') then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn','gl_unconvertible_currency',
              'Expense #'||e.id||' from '||coalesce(e.vendor,'?')||' is in '||e.cur||
              ', which has no rate in gl_settings, so it was NOT posted to the ledger.','system');
    exception when others then null; end;
    return null;
  end if;

  amt_aed := round(e.amount * case when e.cur='USD' then fx else 1 end, 2);
  vat_aed := round(coalesce(e.vat_amount,0) * case when e.cur='USD' then fx else 1 end, 2);
  if vat_aed <= 0 or vat_aed >= amt_aed then vat_aed := 0; end if;
  -- 13 Nov 2026 (accountant): QuotesDone is not VAT-registered (no TRN; registration only above AED 375k of supplies), so
  -- input VAT is NOT recoverable: it is part of the cost. The whole amount goes to the expense account; the VAT stated on
  -- the receipt is kept in the memo only. 1150 VAT Recoverable is no longer posted.
  net_aed := amt_aed;

  acct := coalesce((select m.account_code from public.gl_expense_map m where m.category = e.category), '6300');

  lines := jsonb_build_array(jsonb_build_object('account', acct, 'debit', net_aed,
             'memo', coalesce(e.vendor,'')||' '||coalesce(e.category,'G&A')));
  lines := lines || jsonb_build_array(jsonb_build_object('account','1000','credit',amt_aed));

  return public.fn_gl_entry(e.d,
    'Expense: '||coalesce(e.vendor,'?')||' - '||coalesce(e.category,'G&A')
      ||case when e.cur='USD' then ' ('||e.amount||' USD @ '||fx||')' else '' end
      ||case when vat_aed > 0 then ' incl VAT '||vat_aed||' AED (not recoverable: not VAT-registered)' else '' end,
    'expense', e.id::text, lines, 'expenses_inbox');
end
$function$;
revoke execute on function public.fn_expense_post_to_gl(bigint) from public, anon, authenticated;
