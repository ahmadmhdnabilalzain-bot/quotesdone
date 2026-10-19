-- sales_engineer, founder_instruction 1028 (backlog 1019, T1): a customer re-issues a past request in one click.
-- The copy is a NEW inquiry (same posting door, same spec check and matching) and carries a link to the request it
-- copies. customer_api writes repeat_of only from the server-side intake it built itself (never from the body).
-- on delete set null: removing the original never removes or blocks the copy.
alter table public.inquiries add column if not exists repeat_of uuid references public.inquiries(id) on delete set null;
create index if not exists inquiries_repeat_of_idx on public.inquiries (repeat_of) where repeat_of is not null;
comment on column public.inquiries.repeat_of is 'The earlier request of the same customer this one was posted again from (customer_api repeat_inquiry, founder_instruction 1028).';

select case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'inquiries' and column_name = 'repeat_of')
            then 'PROBE OK' else 'PROBE FAILED: inquiries.repeat_of missing' end as verdict;
