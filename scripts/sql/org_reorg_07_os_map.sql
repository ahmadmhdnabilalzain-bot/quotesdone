-- REORGANISING THE AGENT COMPANY — the OS map, corrected deliberately rather than by collapse.
--
-- Collapsing 25 department rows into 10 left os_department holding whichever predecessor's OS
-- survived the de-duplication: Marketplace & Supplier Network pointed at the Knowledge OS and
-- People & Company Operations at the Leadership OS. fn_owning_os and fn_org_task_cross_os_guard
-- both read this map, so an arbitrary survivor is an arbitrary owner and an arbitrary refusal.
--
-- The ten Operating Systems and the ten departments are NOT isomorphic and this file does not
-- pretend they are: each department is mapped to the OS owned by its own head where one exists,
-- and otherwise to the OS that owns its work. Knowledge OS and Evolution OS keep no department of
-- their own; both still resolve through fn_owning_os's owner_agent arm.

begin;

delete from public.os_department o
 where exists (select 1 from public.org_departments d where d.dept_key = o.dept_key and d.active);

insert into public.os_department (os_key, dept_key) values
 ('leadership','exec'),               -- owner ceo, head of Executive & Strategy
 ('commercial','growth'),             -- owner sales_director, now Chief Revenue Officer
 ('marketplace','marketplace'),       -- owner procurement, now Marketplace Director
 ('marketplace','customer_experience'),-- the customer side of the same operating system
 ('technology','product_eng'),        -- owner cto
 ('intelligence','data_intel'),       -- owner intel_director, now Data & Intelligence Director
 ('finance','finance'),               -- owner cfo
 ('legal_gov','legal'),               -- owner legal, now General Counsel
 ('operations','people_ops'),         -- owner ops_director, now Chief Operating Officer
 ('operations','assurance')           -- platform operations and reliability
on conflict do nothing;

commit;
