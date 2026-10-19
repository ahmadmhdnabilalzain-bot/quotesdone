-- sales_engineer, founder_instruction 1028 (backlog 1019, T1): a customer re-issues a past request in one click.
-- The copy is a NEW inquiry (same posting door, same spec check and matching) and carries a link to the request it
-- copies. customer_api writes repeat_of only from the server-side intake it built itself (never from the body).
-- on delete set null: removing the original never removes or blocks the copy.
alter table public.inquiries add column if not exists repeat_of uuid references public.inquiries(id) on delete set null;
create index if not exists inquiries_repeat_of_idx on public.inquiries (repeat_of) where repeat_of is not null;
comment on column public.inquiries.repeat_of is 'The earlier request of the same customer this one was posted again from (customer_api repeat_inquiry, founder_instruction 1028).';

-- Idempotent repeat (release review of #1180): one open ('ready') repeat draft per customer per original request, so
-- two concurrent clicks cannot both insert. customer_api answers the unique violation with 409 already_repeated and
-- retires a stale ready draft (> 3 min, never posted) as 'expired' before inserting.
create unique index if not exists inquiry_intake_one_open_repeat on public.inquiry_intake (customer_id, (brief->>'repeat_of'))
  where status = 'ready' and brief ? 'repeat_of';

select case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'inquiries' and column_name = 'repeat_of')
            and exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'inquiry_intake_one_open_repeat')
            then 'PROBE OK' else 'PROBE FAILED: inquiries.repeat_of or inquiry_intake_one_open_repeat missing' end as verdict;
