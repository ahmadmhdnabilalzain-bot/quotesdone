-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623202029   name: fn_security_scan
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function fn_security_scan() returns void language plpgsql security definer as $$
declare
  v_run bigint; v_scanned int := 0; v_susp int := 0; v_high int := 0; v_viol int; v_banned int; v_owner text;
  r record; v_path text; v_sev text; v_why text; v_size bigint; v_mime text;
begin
  insert into agent_runs(agent, started_at) values ('security', now()) returning id into v_run;
  for r in
    select bucket_id, name, coalesce((metadata->>'size')::bigint,0) as size, coalesce(metadata->>'mimetype','') as mime
    from storage.objects
    where bucket_id in ('quote-files','drawing-files','supplier-docs','receipt-files')
    order by created_at desc limit 400
  loop
    v_path := r.name; if v_path is null or v_path = '' or right(v_path,1) = '/' then continue; end if;
    v_scanned := v_scanned + 1; v_size := r.size; v_mime := r.mime; v_sev := null; v_why := null;
    if v_path ~* '\.[a-z0-9]{2,5}\.(exe|js|scr|bat|html?|svg|hta)$' then v_sev := 'high'; v_why := 'double extension';
    elsif v_path ~* '\.(exe|bat|cmd|com|scr|msi|ps1|vbs|js|jar|sh|apk|dll|hta|wsf|docm|xlsm|pptm|iso|img)$' then v_sev := 'high'; v_why := 'dangerous file type';
    elsif v_path ~* '\.(html?|svg)$' then v_sev := 'high'; v_why := 'active-content file';
    elsif v_size > 30*1024*1024 then v_sev := 'medium'; v_why := 'oversized';
    end if;
    if v_sev is not null then
      v_susp := v_susp + 1;
      insert into security_events(kind,severity,source,subject,detail) values ('suspicious_upload',v_sev,r.bucket_id,left(v_path,200),jsonb_build_object('mime',v_mime,'size',v_size,'why',v_why));
      if v_sev = 'high' then
        v_high := v_high + 1;
        insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
        values ('security','security_alert','pending','high','Suspicious upload ('||v_why||'): '||left(v_path,80),'inspect/remove the file in storage; do NOT open it directly','security_events',jsonb_build_object('bucket',r.bucket_id,'path',v_path,'why',v_why,'size',v_size));
      end if;
    end if;
  end loop;
  select count(*) into v_viol from chat_violations where created_at >= now()-interval '7 days';
  select (select count(*) from leads where banned=true)+(select count(*) from customers where banned=true) into v_banned;
  if v_viol > 0 then insert into security_events(kind,severity,source,subject,detail) values ('contact_disclosure','medium','chat',v_viol||' contact-sharing attempt(s) in 7d',jsonb_build_object('count',v_viol)); end if;
  if v_susp > 0 then
    select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
    insert into notifications(type,to_email,to_role,channel,subject,body) values ('security_alert',coalesce(v_owner,'management@quotesdone.com'),'admin','email','QuotesDone security: '||v_susp||' suspicious file(s) flagged','The Security agent flagged '||v_susp||' uploaded file(s) ('||v_high||' high-severity). Open the Security agent in admin. Do not open flagged files directly.');
  end if;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('scanned',v_scanned,'suspicious',v_susp,'high',v_high,'violations7d',v_viol,'banned',v_banned) where id=v_run;
end;$$;

select cron.unschedule('agent_security_6h');
select cron.schedule('agent_security_6h', '45 */6 * * *', $$ select fn_security_scan() $$);

