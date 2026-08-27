-- Down: remove the ISTQB CTFL test-design knowledge loaded for the QA roles.
begin;
delete from public.ops_knowledge where record_id like 'EXPERTISE:istqb-ctfl-v4:%';
commit;
