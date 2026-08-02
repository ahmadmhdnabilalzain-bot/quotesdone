-- Holdout v1 failing cases, with their source text, for root-cause work.
with r as (select * from public.fn_p2c1_holdout_run())
select r.case_key || ' | ' || r.category || ' | ' || r.verdict
       || E'\n    EN: ' || c.text_en
       || E'\n    AR: ' || c.text_ar
       || E'\n    expect_active=' || array_to_string(c.expect_active,',')
       || ' en_active=[' || coalesce(r.en_active,'') || '] ar_active=[' || coalesce(r.ar_active,'') || ']'
       || E'\n    expect_disp=' || c.expect_dispositions::text
       || ' expect_comp=' || c.expect_components::text
       || E'\n    fn_en=' || array_to_string(r.en_false_neg,',') || ' fn_ar=' || array_to_string(r.ar_false_neg,',')
       || ' clarify_agree=' || r.clarify_agree::text as line
  from r join public.p2c1_holdout_case c on c.case_key = r.case_key
 where r.verdict <> 'PASS'
 order by r.case_key;
