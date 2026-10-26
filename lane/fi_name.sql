insert into public.founder_instruction (instruction, said_at)
values ('7 Oct: "auto fill the name from the attachment instead of rejection" - when a supplier''s trade licence name differs from the registered company name, the company name is taken from the licence (read with confidence), the old name kept in history, the supplier told; no hold or rejection for a name mismatch alone.', now())
returning id;
