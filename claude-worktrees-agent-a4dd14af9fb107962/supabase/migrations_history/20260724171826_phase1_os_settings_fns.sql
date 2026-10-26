-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724171826   name: phase1_os_settings_fns
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- List all editable settings with current values (business keys only; secrets never appear).
CREATE OR REPLACE FUNCTION public.fn_os_settings_list()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(x order by x->>'grp', (x->>'sort')::int, x->>'label'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'key', m.key, 'grp', m.grp, 'type', m.type, 'label', m.label,
      'help', coalesce(m.help,''), 'validation', m.validation, 'dangerous', m.dangerous,
      'sort', m.sort, 'value', coalesce(s.value,'')
    ) as x
    from public.os_settings_meta m
    left join public.app_secrets s on s.key = m.key
  ) q;
$$;
REVOKE ALL ON FUNCTION public.fn_os_settings_list() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_settings_list() TO service_role;

-- Validate + write a single setting. Refuses any key not in the registry (the secret guard),
-- enforces type/range, honours the dangerous-flag confirm gate, and writes an audit row.
CREATE OR REPLACE FUNCTION public.fn_os_settings_set(p_key text, p_value text, p_actor text, p_confirm boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m public.os_settings_meta; v text := coalesce(p_value,''); n numeric; oldv text; mn numeric; mx numeric; ml int;
BEGIN
  SELECT * INTO m FROM public.os_settings_meta WHERE key = p_key;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','key_not_editable'); END IF;
  IF m.dangerous AND NOT p_confirm THEN RETURN jsonb_build_object('ok',false,'needs_confirm',true,'label',m.label); END IF;

  mn := nullif(m.validation->>'min','')::numeric;
  mx := nullif(m.validation->>'max','')::numeric;
  ml := nullif(m.validation->>'maxlen','')::int;

  IF m.type IN ('money','number','int') THEN
    BEGIN n := v::numeric; EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','must_be_a_number'); END;
    IF m.type='int' AND n <> trunc(n) THEN RETURN jsonb_build_object('ok',false,'error','must_be_a_whole_number'); END IF;
    IF mn IS NOT NULL AND n < mn THEN RETURN jsonb_build_object('ok',false,'error','below_minimum','min',mn); END IF;
    IF mx IS NOT NULL AND n > mx THEN RETURN jsonb_build_object('ok',false,'error','above_maximum','max',mx); END IF;
    v := n::text;
  ELSIF m.type='bool' THEN
    v := lower(v);
    IF v IN ('true','1','yes','on') THEN v:='true'; ELSIF v IN ('false','0','no','off','') THEN v:='false';
    ELSE RETURN jsonb_build_object('ok',false,'error','must_be_true_or_false'); END IF;
  ELSIF m.type='email' THEN
    IF v <> '' AND position('@' in v) = 0 THEN RETURN jsonb_build_object('ok',false,'error','not_an_email'); END IF;
    IF ml IS NOT NULL AND length(v) > ml THEN RETURN jsonb_build_object('ok',false,'error','too_long','maxlen',ml); END IF;
  ELSE
    IF ml IS NOT NULL AND length(v) > ml THEN RETURN jsonb_build_object('ok',false,'error','too_long','maxlen',ml); END IF;
  END IF;

  SELECT value INTO oldv FROM public.app_secrets WHERE key = p_key;
  INSERT INTO public.app_secrets(key,value) VALUES (p_key, v)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value;

  INSERT INTO public.os_audit_log(actor, action, entity, entity_id, detail, ok)
  VALUES (coalesce(p_actor,'os'), 'settings_set', 'setting', p_key,
          jsonb_build_object('old', coalesce(oldv,''), 'new', v, 'label', m.label), true);

  RETURN jsonb_build_object('ok',true,'key',p_key,'old',coalesce(oldv,''),'new',v);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_settings_set(text,text,text,boolean) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_settings_set(text,text,text,boolean) TO service_role;

-- History for one setting (from the audit log).
CREATE OR REPLACE FUNCTION public.fn_os_settings_history(p_key text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'at', at, 'actor', actor, 'action', action,
    'old', detail->>'old', 'new', detail->>'new') order by at desc), '[]'::jsonb)
  from public.os_audit_log
  where entity='setting' and entity_id=p_key and action in ('settings_set','settings_revert')
  limit 50;
$$;
REVOKE ALL ON FUNCTION public.fn_os_settings_history(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_settings_history(text) TO service_role;

-- Revert a setting to the previous value recorded in its latest change.
CREATE OR REPLACE FUNCTION public.fn_os_settings_revert(p_key text, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE prev text; oldv text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.os_settings_meta WHERE key=p_key) THEN
    RETURN jsonb_build_object('ok',false,'error','key_not_editable'); END IF;
  SELECT detail->>'old' INTO prev FROM public.os_audit_log
    WHERE entity='setting' AND entity_id=p_key AND action IN ('settings_set','settings_revert')
    ORDER BY at DESC LIMIT 1;
  IF prev IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_history_to_revert'); END IF;
  SELECT value INTO oldv FROM public.app_secrets WHERE key=p_key;
  INSERT INTO public.app_secrets(key,value) VALUES (p_key, prev)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value;
  INSERT INTO public.os_audit_log(actor, action, entity, entity_id, detail, ok)
  VALUES (coalesce(p_actor,'os'), 'settings_revert', 'setting', p_key,
          jsonb_build_object('old', coalesce(oldv,''), 'new', prev), true);
  RETURN jsonb_build_object('ok',true,'key',p_key,'old',coalesce(oldv,''),'new',prev);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_settings_revert(text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_settings_revert(text,text) TO service_role;

