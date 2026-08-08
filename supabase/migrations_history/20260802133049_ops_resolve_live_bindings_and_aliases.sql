-- LIVE-DATA BINDING RESOLUTION.
-- 262 of the 268 candidates resolve to a real object by exact name. The remaining 6 are not missing
-- capability - they are the corpus using generic industry names for objects this platform calls
-- something else. Left as 'missing' they would read as six holes in the operating model; resolved
-- by hand with the reason recorded, they are what they actually are: naming drift.
--
-- The mapping and why:
--   suppliers / companies          -> leads. QuotesDone has never had a suppliers table; supplier
--                                     records live in leads with claimed_by / approval_status. Any
--                                     new "suppliers" table would be a second source of truth.
--   supplier_health_snapshots      -> supplier_health (+ supplier_kpi_snapshots for the time series).
--   refunds                        -> refund_requests is absent too; refunds are currently modelled
--                                     as stripe_transactions rows plus a decision_record. This one
--                                     is a REAL gap in the data model, not just a naming difference,
--                                     and is left flagged rather than aliased away.
--   audit_logs                     -> os_audit_log and security_audit_log (two of them, by design).
--   kyc                            -> not a table at all; kyc is an edge function. The persisted
--                                     state lives on customers/leads verification columns.
create table if not exists ops_kb_stage.binding_aliases (
  object_name text primary key,
  resolved_to text[] not null,
  resolution text not null,
  note text not null
);

insert into ops_kb_stage.binding_aliases (object_name, resolved_to, resolution, note) values
 ('suppliers', array['leads'], 'alias',
  'Supplier records live in public.leads (claimed_by, approval_status, verified). There is no suppliers table and creating one would split the source of truth.'),
 ('companies', array['leads'], 'alias',
  'Same object as suppliers; the corpus uses "companies" for the supplier business entity.'),
 ('supplier_health_snapshots', array['supplier_health','supplier_kpi_snapshots'], 'alias',
  'Current health is supplier_health; the historical series is supplier_kpi_snapshots.'),
 ('audit_logs', array['os_audit_log','security_audit_log'], 'alias',
  'Two audit streams by design: operational actions and security events. A single audit_logs table would merge two different retention and access policies.'),
 ('kyc', array[]::text[], 'not_a_table',
  'kyc is an edge function, not stored state. Verification outcomes live on customers.email_verified / phone_verified and leads verification columns.'),
 ('refunds', array[]::text[], 'real_gap',
  'GENUINE GAP, not naming drift. Refunds are currently implied by stripe_transactions plus a decision_record; there is no refund ledger with status, reason, approver and reconciliation. Payments & Revenue cannot report refund rate without one.')
on conflict (object_name) do update set resolved_to=excluded.resolved_to, resolution=excluded.resolution, note=excluded.note;

update ops_kb_stage.live_bindings b
set mapping_status = case when a.resolution = 'alias' then 'mapped' else 'rejected' end,
    raw = b.raw || jsonb_build_object('resolved_to', a.resolved_to, 'resolution', a.resolution, 'resolution_note', a.note)
from ops_kb_stage.binding_aliases a
where lower(btrim(b.object_name)) = a.object_name;

alter table ops_kb_stage.binding_aliases enable row level security;
revoke all on ops_kb_stage.binding_aliases from anon, authenticated;
grant all on ops_kb_stage.binding_aliases to service_role;
