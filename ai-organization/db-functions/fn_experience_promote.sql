CREATE OR REPLACE FUNCTION public.fn_experience_promote()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_promoted int:=0; v_rejected int:=0; v_agent text;
begin
  for r in select m.* from org_memory m
           where m.active and m.kind='lesson'
             and m.created_at < now() - interval '7 days'
             and not exists (select 1 from agent_knowledge k
                             where k.layer='experience' and k.topic like '%[org#'||m.id||']')
  loop
    if exists (select 1 from policy_rules p where p.active and r.content ~* p.forbid_regex) then
      v_rejected := v_rejected + 1;
      insert into founder_alerts(level,event,detail,channel)
        values ('warn','experience_promotion_blocked',
                'org_memory lesson #'||r.id||' contradicts policy_rules and was NOT promoted: '||left(r.content,300),'system');
    else
      select coalesce(d.brain_agent,'_global') into v_agent from org_departments d where d.dept_key=r.scope;
      insert into agent_knowledge(agent_key, topic, content, priority, layer)
        values (coalesce(v_agent,'_global'),
                'Experience: '||left(regexp_replace(r.content,'^\[[a-z]+\]\s*',''),60)||' [org#'||r.id||']',
                r.content, 5, 'experience');
      v_promoted := v_promoted + 1;
    end if;
  end loop;
  return jsonb_build_object('promoted', v_promoted, 'lint_rejected', v_rejected);
end $function$
