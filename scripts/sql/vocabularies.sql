select line from (
  select 1 as g, disposition as o,
         'DSP | ' || disposition || ' | contributes=' || contributes::text
         || ' | clarify=' || requires_clarification::text || ' | conflict=' || is_conflict::text
         || ' | ' || label_en as line
    from public.scope_disposition_kind
  union all
  select 2, lpad(sort_order::text, 3, '0'),
         'TRD | ' || trade_key || ' | ' || label_en || ' | ' || label_ar || ' | core=' || is_core::text
    from public.mep_trade
) q order by g, o;
