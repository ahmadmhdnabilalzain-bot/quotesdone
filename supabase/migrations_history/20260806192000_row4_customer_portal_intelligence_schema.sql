-- ROW #4 (customer portal) — intelligence backend, SCHEMA half.
-- Spec §5 (project intelligence), §8 (RFQ reference), §15 (negotiation policy).
-- Applied identically to staging and production by scripts/apply_sql.mjs --promote --ddl.
--
-- NOTHING HERE WRITES BUSINESS DATA. Production holds zero customers, zero inquiries, zero quotes
-- and zero projects; every figure added below is COMPUTED from those (empty) relations, so each
-- one reads null or [] today and starts reading a real number the moment a real row exists. The one
-- row this work seeds is a negotiation POLICY — founder configuration, not customer history — and
-- it is seeded by row4_negotiation_policy_seed.sql, not here.

-- ═══ §8 — a human reference number on every RFQ ══════════════════════════════════════════════════
-- The primary key is a uuid; the spec's command centre shows "RFQ #88291". A uuid is not a number a
-- customer can read out on the phone, so inquiries gains a short integer reference.
--
-- DETERMINISTIC BACKFILL, NOT A HASH. A truncated md5 of the uuid would be deterministic and would
-- also collide: 90,000 five-digit slots collide at ~50% by 350 rows (birthday bound), and a UNIQUE
-- index would then reject a legitimate RFQ at intake. The backfill is therefore ordered — oldest
-- inquiry gets the lowest number — which is deterministic for any given table state AND collision-
-- free by construction, and new rows continue the same run from a sequence.
--
-- The sequence starts at 88291 because that is the number the spec itself prints. It is a start
-- value, not a fabricated row: production has zero inquiries, so the FIRST REAL RFQ anyone files
-- will be #88291 and every one after it counts up honestly from there.
create sequence if not exists public.inquiries_rfq_no_seq as integer start with 88291;

alter table public.inquiries add column if not exists rfq_no integer;

-- Backfill in creation order. No-op on both projects today (0 inquiries) and correct if it is not.
with ordered as (
  select id, row_number() over (order by created_at, id) rn
    from public.inquiries where rfq_no is null
)
update public.inquiries i set rfq_no = 88290 + o.rn from ordered o where o.id = i.id;

select setval('public.inquiries_rfq_no_seq',
              greatest(88291, coalesce((select max(rfq_no) from public.inquiries), 0) + 1), false);

alter table public.inquiries alter column rfq_no set default nextval('public.inquiries_rfq_no_seq');
alter table public.inquiries alter column rfq_no set not null;
alter sequence public.inquiries_rfq_no_seq owned by public.inquiries.rfq_no;

create unique index if not exists inquiries_rfq_no_key on public.inquiries (rfq_no);

-- ═══ §15 — a negotiation policy that can exist before there is a supplier to attach it to ════════
-- supplier_negotiation_policy was keyed by supplier_id (primary key, FK to leads), so the ONLY
-- expressible policy was a per-supplier one — 20,464 rows, or nothing. Writing 20,464 policy rows
-- to make a table non-empty is exactly the fabrication this project forbids, so the table gains a
-- `scope` key instead: 'default' is the house policy, 'supplier:<id>' overrides it for one supplier.
-- supplier_id becomes nullable and keeps its FK, so a per-supplier override is still a real FK row.
alter table public.supplier_negotiation_policy add column if not exists scope text;
update public.supplier_negotiation_policy set scope = 'supplier:' || supplier_id where scope is null;
alter table public.supplier_negotiation_policy drop constraint if exists supplier_negotiation_policy_pkey;
alter table public.supplier_negotiation_policy alter column supplier_id drop not null;
alter table public.supplier_negotiation_policy alter column scope set not null;
alter table public.supplier_negotiation_policy add constraint supplier_negotiation_policy_pkey primary key (scope);
create unique index if not exists supplier_negotiation_policy_supplier_key
  on public.supplier_negotiation_policy (supplier_id) where supplier_id is not null;

-- ═══ §5 — the three project figures the spec names and project_summary did not carry ═════════════
-- CREATE OR REPLACE keeps the eleven existing columns in place and in order (project_api reads the
-- view with select *, so a reordering would silently change its payload) and appends three.
--   trade_breakdown  — the material/trade rollup. Categories ARE the trade axis in this schema.
--   supplier_count   — suppliers engaged ON THIS PROJECT, from inquiry_matches. project_api's
--                      dashboard.suppliers_engaged counts the customer's whole transaction history,
--                      which is a different number and answers a different question.
--   timeline_pct     — elapsed time toward the project's target open date. NULL when no target date
--                      is set: a project with no deadline has no timeline completion, and rendering
--                      0% for it would be a figure the data does not support.
create or replace view public.project_summary as
select p.id as project_id,
       p.customer_id,
       p.name,
       p.status,
       p.target_open_date,
       p.budget_total,
       p.created_at,
       count(i.id) as rfq_count,
       count(i.id) filter (where i.status <> all (array['completed'::text, 'cancelled'::text])) as rfq_open,
       count(i.id) filter (where i.hired_supplier_id is not null) as rfq_awarded,
       round(coalesce(sum(i.expected_value), (0)::numeric), 0) as pipeline_value,
       (select coalesce(jsonb_agg(b order by b ->> 'category'), '[]'::jsonb)
          from (select jsonb_build_object(
                         'category', coalesce(i2.category, 'uncategorised'),
                         'rfqs', count(*),
                         'open', count(*) filter (where i2.status <> all (array['completed'::text, 'cancelled'::text])),
                         'awarded', count(*) filter (where i2.hired_supplier_id is not null),
                         'value_aed', round(coalesce(sum(i2.expected_value), (0)::numeric), 0)
                       ) b
                  from public.inquiries i2
                 where i2.project_id = p.id
                 group by coalesce(i2.category, 'uncategorised')) s
       ) as trade_breakdown,
       (select count(distinct m.supplier_id)
          from public.inquiry_matches m
          join public.inquiries i3 on i3.id = m.inquiry_id
         where i3.project_id = p.id) as supplier_count,
       case
         when p.target_open_date is null then null::numeric
         when p.target_open_date <= p.created_at::date then 100::numeric
         else round(least(100::numeric, greatest(0::numeric,
                100::numeric * (current_date - p.created_at::date)::numeric
                             / nullif((p.target_open_date - p.created_at::date), 0)::numeric)), 0)
       end as timeline_pct
  from public.projects p
  left join public.inquiries i on i.project_id = p.id
 group by p.id, p.customer_id, p.name, p.status, p.target_open_date, p.budget_total, p.created_at;
