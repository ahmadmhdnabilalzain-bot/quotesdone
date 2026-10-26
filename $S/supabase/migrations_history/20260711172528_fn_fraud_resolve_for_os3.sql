-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711172528   name: fn_fraud_resolve_for_os3
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_fraud_resolve(p_subject_type text, p_subject_id text, p_action text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_ok boolean := true; v_msg text := '';
begin
  if p_action = 'ban' then
    begin
      if p_subject_type in ('customer','customers') then
        update customers set banned=true, banned_reason=coalesce(banned_reason,'fraud: manual ban by '||coalesce(p_by,'admin')) where id = p_subject_id::uuid;
      elsif p_subject_type in ('supplier','lead','leads') then
        update leads set banned=true, matching_blocked=true, matching_block_reason=coalesce(matching_block_reason,'fraud ban'), banned_reason=coalesce(banned_reason,'fraud: manual ban by '||coalesce(p_by,'admin')) where id = p_subject_id::bigint;
      else v_ok:=false; v_msg:='unknown subject_type';
      end if;
    exception when others then v_ok:=false; v_msg:=SQLERRM;
    end;
    update fraud_flags set status='resolved', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  elsif p_action = 'unban' then
    begin
      if p_subject_type in ('customer','customers') then update customers set banned=false, banned_reason=null where id=p_subject_id::uuid;
      elsif p_subject_type in ('supplier','lead','leads') then update leads set banned=false, matching_blocked=false where id=p_subject_id::bigint;
      end if;
    exception when others then v_ok:=false; v_msg:=SQLERRM; end;
    update fraud_flags set status='resolved', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  elsif p_action = 'dismiss' then
    update fraud_flags set status='dismissed', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  else v_ok:=false; v_msg:='unknown action';
  end if;
  return jsonb_build_object('ok', v_ok, 'action', p_action, 'subject', p_subject_type||':'||p_subject_id, 'error', nullif(v_msg,''), 'by', p_by, 'at', now());
end $$;
revoke all on function public.fn_fraud_resolve(text,text,text,text) from public, anon, authenticated;
grant execute on function public.fn_fraud_resolve(text,text,text,text) to service_role;
