select split_part(path,'/',3) top, split_part(path,'/',4) l2, count(*) from public.dropbox_files
where path ilike '/QuotesDone Backup/Customers/%' and path not ilike '%/Customers/%/%/%' group by 1,2 order by 3 desc limit 15;
select count(*) filter (where path ilike '%customer_register%') reg from public.dropbox_files;
