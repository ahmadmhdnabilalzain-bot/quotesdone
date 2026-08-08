-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710201351   name: email_retry_deadletter
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.notifications add column if not exists attempts int not null default 0;
alter table public.notifications add column if not exists last_error text;

create or replace view public.v_email_deadletter as
select id, type, to_email, to_role, subject, attempts, last_error, created_at
from public.notifications
where status = 'failed'
order by created_at desc;
revoke all on public.v_email_deadletter from anon, authenticated;
