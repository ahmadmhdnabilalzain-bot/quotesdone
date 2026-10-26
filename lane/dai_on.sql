insert into public.app_secrets (key, value) values ('document_expiry_ai', 'on')
on conflict (key) do update set value = 'on';
select key, value from public.app_secrets where key = 'document_expiry_ai';
