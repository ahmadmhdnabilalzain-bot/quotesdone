select split_part(path,'/',3) top, count(*) n from public.dropbox_files where path like '/QuotesDone Backup/%' group by 1 order by 2 desc limit 20;
select path from public.dropbox_files where path ilike '%register%' or path ilike '%.xlsx' limit 10;
select split_part(path,'/',4) cat, count(*) from public.dropbox_files where path like '/QuotesDone Backup/Suppliers/%' group by 1 order by 2 desc limit 8;
select key, value from public.app_secrets where key ilike '%prune%';
