select id, said_at::date, left(instruction,400) i from public.founder_instruction
where instruction ilike any(array['%dropbox%','%back up%','%backup%','%folder%']) order by id;
