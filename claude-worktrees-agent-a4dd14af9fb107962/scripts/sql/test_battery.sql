-- The complete existing P2-C1 test battery, in one pass, with explicit denominators.
with
a as (select count(*) n, count(*) filter (where passed) p from fn_p2c1_stage_a_selftest()),
b as (select count(*) n, count(*) filter (where passed) p from fn_p2c1_stage_b_selftest()),
br as (select count(*) n, count(*) filter (where passed) p from fn_p2c1_stage_b_regression()),
sc as (select count(*) n, count(*) filter (where passed) p from fn_p2c1_scope_rule_tests()),
lp as (select count(*) n, count(*) filter (where verdict = 'PASS') p,
              coalesce(sum(cardinality(en_false_pos)) + sum(cardinality(ar_false_pos)), 0) fp,
              coalesce(sum(cardinality(en_false_neg)) + sum(cardinality(ar_false_neg)), 0) fn
       from fn_p2c1_lang_parity_suite()),
dp as (select count(*) n, count(*) filter (where passed) p from fn_p2c1_disposition_tests()),
h as (select count(*) n,
             count(*) filter (where verdict = 'PASS') p,
             coalesce(sum(cardinality(en_false_pos)) + sum(cardinality(ar_false_pos)), 0) fp,
             coalesce(sum(cardinality(en_false_neg)) + sum(cardinality(ar_false_neg)), 0) fn,
             count(*) filter (where trade_set_agree) tsa,
             count(*) filter (where disposition_agree) da,
             count(*) filter (where component_agree) ca,
             count(*) filter (where clarify_agree) cla,
             count(*) filter (where conflict_ok) co
      from fn_p2c1_holdout_run()),
seal as (select fn_p2c1_holdout_verify_seal() j)
select 'stage A selftest        : ' || a.p || '/' || a.n || ' passed' as line from a
union all select 'stage B selftest        : ' || b.p || '/' || b.n || ' passed' from b
union all select 'stage B regression      : ' || br.p || '/' || br.n || ' passed' from br
union all select 'scope negative tests    : ' || sc.p || '/' || sc.n || ' passed' from sc
union all select 'language parity suite   : ' || lp.p || '/' || lp.n || ' passed, false pos ' || lp.fp || ', false neg ' || lp.fn from lp
union all select 'disposition tests       : ' || dp.p || '/' || dp.n || ' passed' from dp
union all select 'holdout v1 executed     : ' || h.n || '/' || h.n || ' cases executed' from h
union all select 'holdout v1 correctness  : ' || h.p || '/' || h.n || ' cases passed' from h
union all select 'holdout v1 false pos    : ' || h.fp from h
union all select 'holdout v1 false neg    : ' || h.fn from h
union all select 'holdout v1 EN/AR parity : trade-set ' || h.tsa || '/' || h.n || ', disposition ' || h.da || '/' || h.n
                 || ', component ' || h.ca || '/' || h.n || ', clarification ' || h.cla || '/' || h.n
                 || ', conflict handling ' || h.co || '/' || h.n from h
union all select 'holdout v1 failure kinds: ' || (select string_agg(v || ' x' || c::text, '; ' order by v) from (select verdict v, count(*) c from fn_p2c1_holdout_run() where verdict <> 'PASS' group by verdict) q)
union all select 'holdout seal integrity  : ' || (seal.j ->> 'ok') || '  (' || coalesce(seal.j ->> 'current_checksum', '?') || ')' from seal;
