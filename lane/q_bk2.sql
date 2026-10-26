select id, said_at::date, left(instruction,600) i from public.founder_instruction
where instruction ilike any(array['%organiz%','%organis%','%sub folder%','%subfolder%','%company name%','%inquiry number%','%per customer%']) order by id limit 30;
