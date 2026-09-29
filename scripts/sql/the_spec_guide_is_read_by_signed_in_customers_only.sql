-- THE SPEC GUIDE IS READ BY SIGNED-IN CUSTOMERS ONLY (29 Sep 2026; seat: sales_engineer).
--
-- #995 (customer_spec_guide.sql) granted SELECT on public.customer_spec_guide, and EXECUTE on its read
-- routine, to anon as well as authenticated. anon_cannot_execute_security_definer pins by name the tables
-- anon can read (blog_posts, category_specs): each one widens what every anon-executable SECURITY INVOKER
-- routine can return, and the gate went red on main for every PR.
--
-- Measured: the only reader is the signed-in customer's new-request form
-- (src/components/me/NewRequest.tsx -> supaClient('qd-cust-auth').rpc('fn_customer_spec_guide')), i.e. the
-- authenticated role. anon never needs it. The columns (trade, body_en, body_ar, status, updated_at) hold
-- only published how-to-specify text, but the right fix is not to widen the public surface at all:
-- anon loses the grant, the policy and the routine; authenticated keeps all three. customer_spec_guide.sql
-- is corrected the same way so a re-apply cannot put the grant back.

revoke select on public.customer_spec_guide from anon;
alter policy customer_spec_guide_public_reads_published on public.customer_spec_guide to authenticated;
revoke execute on function public.fn_customer_spec_guide(text) from public, anon;
grant execute on function public.fn_customer_spec_guide(text) to authenticated;

select case
  when has_table_privilege('anon', 'public.customer_spec_guide', 'select') then 'PROBE FAILED: anon can still read customer_spec_guide'
  when has_function_privilege('anon', 'public.fn_customer_spec_guide(text)', 'execute') then 'PROBE FAILED: anon can still run fn_customer_spec_guide'
  when not has_table_privilege('authenticated', 'public.customer_spec_guide', 'select') then 'PROBE FAILED: a signed-in customer lost the guide'
  when not has_function_privilege('authenticated', 'public.fn_customer_spec_guide(text)', 'execute') then 'PROBE FAILED: a signed-in customer lost the read routine'
  else 'PROBE OK' end as verdict;
