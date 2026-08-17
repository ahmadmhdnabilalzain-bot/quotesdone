-- K36 — a routine recorded READ_ONLY_HISTORICAL that writes is not read-only.
--
-- fn_phase_c_outbox_settle carries disposition READ_ONLY_HISTORICAL in kernel_retired_path. Called,
-- it UPDATES phase_c_event_outbox. Those two statements cannot both be true, and the second one is
-- the one the database agrees with.
--
-- The guard suite found it sideways. Two cases have been failing —
--
--   a delivery reported ok with NO downstream record is not counted as delivered
--   an out-of-order delivery cannot mark a dead-lettered event delivered twice
--
-- with `invalid input syntax for type timestamp with time zone: ""`. That is a routine that RAN and
-- got as far as writing, not one that refused. Two things were wrong at once: a latent cast bug in
-- a routine nobody calls, and a disposition that described it wrongly.
--
-- K35 removed the service_role grant, so no Edge Function can reach it. That leaves the internal
-- identity, which is what cron and the kernel's own SECURITY DEFINER routines run as — and a
-- routine that writes the domain-event outbox should not be reachable by them either, because
-- fn_kernel_outbox_deliver is the delivery worker and has been since K5.
--
-- So the body becomes what its disposition already claimed: it refuses. The historical definition
-- is not deleted — it is in git, in scripts/sql/phase_c_32_event_delivery_backbone.sql, and the
-- rows it settled are untouched. What goes is the ability to settle another one.
--
-- This is also what makes the two guard cases assert something real again. They stop measuring a
-- cast bug and start measuring the refusal, which is the actual current guard.
--
-- Rollback: scripts/sql/rollback/kernel_k36_read_only_historical_is_read_only.rollback.sql

begin;

create or replace function public.fn_phase_c_outbox_settle(
  p_outbox_id bigint, p_ok boolean, p_downstream_ref text, p_error text)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k36_settle$
begin
  raise exception
    'fn_phase_c_outbox_settle is READ_ONLY_HISTORICAL and no longer settles anything (outbox_id %)',
    p_outbox_id
    using errcode = '23514',
          detail = 'It is recorded READ_ONLY_HISTORICAL in kernel_retired_path and it was still '
                || 'updating phase_c_event_outbox, which is not read-only by any reading. It also '
                || 'carried a latent cast defect that surfaced as "invalid input syntax for type '
                || 'timestamp with time zone" whenever it was called with an empty error string.',
          hint = 'fn_kernel_outbox_deliver is the delivery worker and has been since K5. It claims '
              || 'a batch, records each attempt, and marks delivered only in its success branch. '
              || 'The rows this routine settled historically are untouched and still readable.';
end
$k36_settle$;

comment on function public.fn_phase_c_outbox_settle(bigint, boolean, text, text) is
  'RETIRED, K36. Recorded READ_ONLY_HISTORICAL and it was still writing phase_c_event_outbox. It '
  'now refuses. fn_kernel_outbox_deliver is the delivery worker. The historical definition is in '
  'scripts/sql/phase_c_32_event_delivery_backbone.sql and the rows it settled are untouched.';

revoke all on function public.fn_phase_c_outbox_settle(bigint, boolean, text, text)
  from public, anon, authenticated, service_role;

update public.kernel_retired_path
   set evidence = coalesce(evidence,'') || ' | K36 2026-08-17: it was recorded READ_ONLY_HISTORICAL '
               || 'and still UPDATED phase_c_event_outbox, with a latent cast defect that raised '
               || '"invalid input syntax for type timestamp with time zone" on an empty error '
               || 'string. The body now refuses. Found by the guard suite, which had been failing '
               || 'on that cast rather than on a refusal.'
 where path_name = 'fn_phase_c_outbox_settle';

commit;
