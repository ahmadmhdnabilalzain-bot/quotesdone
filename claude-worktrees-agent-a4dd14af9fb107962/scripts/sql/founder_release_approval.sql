-- founder_release_approval — the last OS_PORTALS gate, and the only one that is a human act.
--
-- "Founder approves release report" had no table behind it, so it could only ever be reported as
-- needs_founder. He approved on 2026-08-10 in the working session and supplied a handwritten
-- signature image in chat.
--
-- WHAT THIS ROW IS AND IS NOT, stated plainly because an approval record that overstates itself is
-- worse than none. It is a dated, attributed record that the founder approved this release in the
-- session, with the scorecard as it stood at that moment. It is NOT a cryptographic signature, NOT
-- a signed document, and the image itself is not stored here — the chat transcript is where that
-- lives. Anyone auditing this should read `evidence` before treating it as more than it is.
--
-- It EXPIRES. An approval of f756bcb is not an approval of whatever ships in September, so the
-- gate below requires an approval inside 30 days, the same reasoning as the 90-day expiry on the
-- rollback drill.
create table if not exists public.founder_release_approval (
  id           bigserial primary key,
  approved_at  timestamptz not null default now(),
  approved_by  text        not null,
  release_ref  text        not null,
  scope        text        not null,
  evidence     text        not null,
  scorecard    jsonb
);
alter table public.founder_release_approval enable row level security;
revoke all on public.founder_release_approval from anon, authenticated;

insert into public.founder_release_approval (approved_by, release_ref, scope, evidence, scorecard)
select
  coalesce(split_part((select value from app_secrets where key='admin_emails'), ',', 1), 'founder'),
  'f756bcb',
  'Row #3 part 9: the six v2026.07.31 knowledge packs deployed and in use, the HTTP action invoker, the employee inbox drain, mobile sign-in and the WhatsApp command channel.',
  'Approved by the founder in the working session on 2026-08-10, in direct answer to a report naming this as the one remaining item; a handwritten signature image was supplied in chat. This is a dated attributed record, NOT a cryptographic signature and NOT a signed document, and the image is not stored in this row.',
  jsonb_build_object(
    'packs_ingested_pct', 100,
    'artefacts_in_use', '37 of 37',
    'os_portals_gates_met', (select count(*) from public.fn_os_portals_gates() where verdict='met'),
    'row3', '121/152',
    'approved_at_utc', now() at time zone 'utc')
where not exists (
  select 1 from public.founder_release_approval where release_ref = 'f756bcb');
