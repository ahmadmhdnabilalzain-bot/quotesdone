-- PROBE: a reversal leaves every account balance where it was (28 Sep 2026).
-- Posts one ZZ DEMO journal, reverses it with fn_gl_reverse, and compares posted-only balances per
-- account (how every report reads the ledger) before the post and after the reversal: they must be
-- equal. Before the fix the reversal stayed posted and each balance moved by the opposite of the entry.
-- PURE PROBE: no DDL; it ends in raise exception, so every row it writes rolls back.
--   node scripts/qsql.mjs scripts/checks/gl_reverse_fixtures.sql      -> expect CHK<<{... "pass": true}>>
do $probe$
declare
  v_a text; v_b text; v_j bigint; v_r bigint;
  b0 jsonb; b1 jsonb; b2 jsonb; r jsonb;
  q text := 'select coalesce(jsonb_object_agg(account_code, bal), ''{}''::jsonb) from (
               select l.account_code, round(sum(l.debit - l.credit), 2) bal
                 from public.gl_journal_lines l join public.gl_journal g on g.id = l.journal_id
                where g.status = ''posted'' group by l.account_code) x';
begin
  select account_code into v_a from public.gl_journal_lines group by account_code order by account_code limit 1;
  select account_code into v_b from public.gl_journal_lines where account_code <> v_a group by account_code order by account_code limit 1;
  execute q into b0;

  v_j := public.fn_gl_entry(current_date, 'ZZ DEMO reversal probe', 'zz_demo_probe', 'zz_probe_gl_reverse',
           jsonb_build_array(jsonb_build_object('account', v_a, 'debit', 123.45, 'credit', 0, 'memo', 'ZZ DEMO'),
                             jsonb_build_object('account', v_b, 'debit', 0, 'credit', 123.45, 'memo', 'ZZ DEMO')),
           'zz_probe');
  execute q into b1;
  v_r := public.fn_gl_reverse(v_j, 'ZZ DEMO probe, rolled back');
  execute q into b2;

  r := jsonb_build_object(
    'accounts', jsonb_build_array(v_a, v_b),
    'post_moved_balances', b1 <> b0,
    'balances_after_reversal_equal_before', b2 = b0,
    'original_status', (select status from public.gl_journal where id = v_j),
    'reversal_status', (select status from public.gl_journal where id = v_r),
    'linked_both_ways', (select reverses from public.gl_journal where id = v_j) = v_r
                        and (select reverses from public.gl_journal where id = v_r) = v_j,
    'before', b0 -> v_a, 'after', b2 -> v_a);
  r := r || jsonb_build_object('pass',
         (r->>'post_moved_balances')::boolean and (r->>'balances_after_reversal_equal_before')::boolean
         and (r->>'linked_both_ways')::boolean);
  raise exception 'CHK<<%>>', r;
end $probe$;
