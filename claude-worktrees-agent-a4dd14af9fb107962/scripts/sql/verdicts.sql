select 'holdout verdict: ' || verdict || ' x' || count(*)::text as line
  from fn_p2c1_holdout_run() group by verdict
union all
select 'lang verdict: ' || verdict || ' x' || count(*)::text from fn_p2c1_lang_parity_suite() group by verdict
union all
select 'seal json: ' || fn_p2c1_holdout_verify_seal()::text;
