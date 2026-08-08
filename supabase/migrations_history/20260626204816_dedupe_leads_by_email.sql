-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626204816   name: dedupe_leads_by_email
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

with ranked as (
  select id,
    row_number() over (partition by lower(email)
      order by (verified is true) desc,
               (coalesce(approval_status,'')='approved') desc,
               (embedding is not null) desc,
               (coalesce(phone,'')<>'') desc,
               coalesce(array_length(tags,1),0) desc,
               (coalesce(capability_summary,'')<>'') desc,
               id asc) rn
  from leads
  where email is not null and email <> ''
    and lower(email) in (select lower(email) from leads where email is not null and email<>'' group by 1 having count(*)>1)
)
delete from leads where id in (select id from ranked where rn > 1);

-- add a unique index to prevent future email duplicates (case-insensitive), allowing multiple no-email rows
create unique index if not exists uq_leads_email_lower on public.leads (lower(email)) where email is not null and email <> '';
