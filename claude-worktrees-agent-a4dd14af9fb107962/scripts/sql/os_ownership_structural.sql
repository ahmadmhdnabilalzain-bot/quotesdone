-- Two facts the blueprint states as rules and the schema left to luck.
--
-- 1. os_knowledge_domain: PRIMARY KEY (os_key, domain_key) permits the same domain to be OWNED by
--    several OSes, which is exactly what "no knowledge domain is owned by two OSes" forbids.
--    os_responsibility already enforces its half structurally (PRIMARY KEY (responsibility));
--    this makes the domain half enforced the same way instead of merely observed to hold.
--    Measured before creating: 0 domain_key with more than one ownership='owns' row (130 domains).
--
-- 2. os_department: PRIMARY KEY (os_key, dept_key) permits one department to belong to several
--    OSes. fn_agent_context cannot represent that — it resolves the employee's OS with
--    `join operating_system o on o.os_key = d.os_key where d.dept_key = v_dept limit 1` and NO
--    ORDER BY — so a second mapping would make which OS an employee is told they belong to an
--    arbitrary unordered row. Fixing it in the table fixes it for every reader at once.
--    Measured before creating: 13 rows, 13 distinct dept_key.

create unique index if not exists os_knowledge_domain_owns_uniq
  on public.os_knowledge_domain (domain_key) where ownership = 'owns';

create unique index if not exists os_department_dept_key_uniq
  on public.os_department (dept_key);
