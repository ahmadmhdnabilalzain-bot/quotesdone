-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724215953   name: phase3_catalog_backend
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- Phase 3 Epic C: catalogue management (intake questions + quote-gate specs) for non-devs.

-- List all categories with counts.
CREATE OR REPLACE FUNCTION public.fn_os_catalog_list()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', cs.category,
    'label', coalesce(cs.label, cs.category),
    'n_fields', coalesce(jsonb_array_length(cs.fields), 0),
    'spec_group', public.fn_quote_spec_group(cs.category),
    'n_specs', (select count(*) from public.category_quote_specs q where q.spec_group = public.fn_quote_spec_group(cs.category))
  ) order by cs.category), '[]'::jsonb)
  from public.category_specs cs;
$$;
REVOKE ALL ON FUNCTION public.fn_os_catalog_list() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_catalog_list() TO service_role;

-- Get one category: intake fields + the quote-gate specs of its group.
CREATE OR REPLACE FUNCTION public.fn_os_catalog_get(p_category text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select jsonb_build_object(
    'category', cs.category,
    'label', coalesce(cs.label, cs.category),
    'fields', coalesce(cs.fields, '[]'::jsonb),
    'spec_group', g.grp,
    'specs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id, 'aspect', q.aspect, 'label', q.label, 'match_regex', q.match_regex,
        'mandatory', q.mandatory, 'note', coalesce(q.note,'')) order by q.mandatory desc, q.aspect), '[]'::jsonb)
      from public.category_quote_specs q where q.spec_group = g.grp)
  )
  from public.category_specs cs, lateral (select public.fn_quote_spec_group(cs.category) as grp) g
  where cs.category = p_category;
$$;
REVOKE ALL ON FUNCTION public.fn_os_catalog_get(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_catalog_get(text) TO service_role;

-- Save intake questions (validated array).
CREATE OR REPLACE FUNCTION public.fn_os_catalog_save_fields(p_category text, p_fields jsonb, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE oldf jsonb;
BEGIN
  IF jsonb_typeof(p_fields) <> 'array' THEN RETURN jsonb_build_object('ok',false,'error','fields_must_be_a_list'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_fields) e
             WHERE jsonb_typeof(e) <> 'object' OR coalesce(e->>'question','')='' OR coalesce(e->>'key','')='') THEN
    RETURN jsonb_build_object('ok',false,'error','each_question_needs_a_key_and_question_text'); END IF;
  SELECT fields INTO oldf FROM public.category_specs WHERE category = p_category;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','category_not_found'); END IF;
  UPDATE public.category_specs SET fields = p_fields, updated_at = now() WHERE category = p_category;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'catalog_save_fields','category',p_category,
          jsonb_build_object('n_fields', jsonb_array_length(p_fields)), true);
  RETURN jsonb_build_object('ok',true,'n_fields', jsonb_array_length(p_fields));
END $$;
REVOKE ALL ON FUNCTION public.fn_os_catalog_save_fields(text,jsonb,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_catalog_save_fields(text,jsonb,text) TO service_role;

-- Add or update one quote-gate spec (regex validated by compiling it).
CREATE OR REPLACE FUNCTION public.fn_os_catalog_spec_upsert(p_id bigint, p_spec_group text, p_aspect text, p_label text, p_regex text, p_mandatory boolean, p_note text, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE newid bigint;
BEGIN
  IF coalesce(p_spec_group,'')='' OR coalesce(p_aspect,'')='' OR coalesce(p_label,'')='' OR coalesce(p_regex,'')='' THEN
    RETURN jsonb_build_object('ok',false,'error','group_aspect_label_and_pattern_required'); END IF;
  BEGIN PERFORM regexp_match('validation probe', p_regex);
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_pattern: '||SQLERRM); END;
  IF p_id IS NOT NULL AND p_id > 0 THEN
    UPDATE public.category_quote_specs SET spec_group=p_spec_group, aspect=p_aspect, label=p_label, match_regex=p_regex, mandatory=coalesce(p_mandatory,false), note=nullif(p_note,'')
      WHERE id=p_id RETURNING id INTO newid;
    IF newid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','spec_not_found'); END IF;
  ELSE
    INSERT INTO public.category_quote_specs(spec_group,aspect,label,match_regex,mandatory,note)
      VALUES (p_spec_group,p_aspect,p_label,p_regex,coalesce(p_mandatory,false),nullif(p_note,'')) RETURNING id INTO newid;
  END IF;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'catalog_spec_upsert','quote_spec',newid::text,
          jsonb_build_object('spec_group',p_spec_group,'aspect',p_aspect,'mandatory',coalesce(p_mandatory,false)), true);
  RETURN jsonb_build_object('ok',true,'id',newid);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) TO service_role;

-- Delete a quote-gate spec.
CREATE OR REPLACE FUNCTION public.fn_os_catalog_spec_delete(p_id bigint, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g text; a text;
BEGIN
  SELECT spec_group, aspect INTO g, a FROM public.category_quote_specs WHERE id=p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','spec_not_found'); END IF;
  DELETE FROM public.category_quote_specs WHERE id=p_id;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'catalog_spec_delete','quote_spec',p_id::text,jsonb_build_object('spec_group',g,'aspect',a), true);
  RETURN jsonb_build_object('ok',true);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_catalog_spec_delete(bigint,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_catalog_spec_delete(bigint,text) TO service_role;

-- Live gate tester: score a sample quote text against a category's specs.
CREATE OR REPLACE FUNCTION public.fn_os_catalog_test_gate(p_category text, p_sample text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE grp text; res jsonb;
BEGIN
  grp := public.fn_quote_spec_group(p_category);
  WITH asp AS (
    SELECT q.aspect, q.label, q.mandatory,
           (CASE WHEN coalesce(p_sample,'') = '' THEN false ELSE p_sample ~* q.match_regex END) AS matched
    FROM public.category_quote_specs q WHERE q.spec_group = grp
  )
  SELECT jsonb_build_object(
    'category', p_category, 'spec_group', grp,
    'aspects', coalesce((select jsonb_agg(jsonb_build_object('aspect',aspect,'label',label,'mandatory',mandatory,'matched',matched) order by mandatory desc, aspect) from asp),'[]'::jsonb),
    'total', (select count(*) from asp),
    'matched_count', (select count(*) from asp where matched),
    'mandatory_missing', coalesce((select jsonb_agg(label order by label) from asp where mandatory and not matched),'[]'::jsonb),
    'passes', (select coalesce(bool_and(matched),true) from asp where mandatory)
  ) INTO res;
  RETURN res;
END $$;
REVOKE ALL ON FUNCTION public.fn_os_catalog_test_gate(text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_catalog_test_gate(text,text) TO service_role;

