select jsonb_pretty(jsonb_agg(x order by x->>'case_key')) as j
from (
  select jsonb_build_object(
    'case_key', c.case_key,
    'bucket', c.bucket,
    'adversarial', c.adversarial,
    'gulf', c.gulf_phrasing,
    'mixed', c.mixed_language,
    'morph', c.morphology_variant,
    'text_en', c.text_en,
    'text_ar', c.text_ar,
    'rationale', c.rationale,
    'spec_refs', to_jsonb(c.spec_refs),
    'expect', c.expect,
    'verdict', v.verdict,
    'parity', v.parity,
    'failure_class', v.failure_class,
    'langs', (
      select jsonb_object_agg(s.lang, jsonb_build_object(
        'detected', s.detected_actual,
        'active', s.active_actual,
        'trade_dispositions', s.td_actual,
        'component_rows', s.comp_actual,
        'clarification_required', s.clar_actual,
        'clarification_reason', s.reason_actual,
        'dispatch_blockers', s.blockers_actual,
        'match', jsonb_build_object('det',s.m_detected,'act',s.m_active,'td',s.m_td,
                  'comp',s.m_comp,'clar',s.m_clar,'rsn',s.m_reason,'blk',s.m_blockers),
        'candidates', s.candidates,
        'status_reasons', (select jsonb_agg(jsonb_build_object('trade',t->>'trade','reason',t->>'reason'))
                           from jsonb_array_elements(s.trade_status) t),
        'component_reasons', (select jsonb_agg(jsonb_build_object('trade',r->>'trade','component',r->>'component',
                                'disposition',r->>'disposition','reason',r->>'reason'))
                              from jsonb_array_elements(s.component_rows) r)
      ))
      from holdout_v2.v_scored s where s.run_id=1 and s.case_key=c.case_key)
  ) as x
  from holdout_v2.case_v2 c
  join holdout_v2.result_case_verdict v on v.case_key=c.case_key and v.result_id=1
  where v.verdict='FAIL'
) q;
