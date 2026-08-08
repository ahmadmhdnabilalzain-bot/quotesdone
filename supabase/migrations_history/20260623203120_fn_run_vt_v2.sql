-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623203120   name: fn_run_vt_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function fn_run_vt() returns void language plpgsql security definer as $$
declare v_secret text; v_files jsonb;
begin
  select value into v_secret from app_secrets where key='inbound_secret';
  select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'path', o.name, 'size', coalesce((o.metadata->>'size')::bigint,0))), '[]'::jsonb)
    into v_files
  from (
    select bucket_id, name, metadata, created_at
    from storage.objects
    where bucket_id in ('quote-files','drawing-files','supplier-docs','receipt-files')
      and right(name,1) <> '/'
      and name not in (select path from vt_results where path is not null)
    order by created_at desc
    limit 4
  ) o;
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/vt_scan',
    body := jsonb_build_object('__secret', v_secret, 'files', v_files),
    headers := '{"Content-Type":"application/json"}'::jsonb
  );
end;$$;

