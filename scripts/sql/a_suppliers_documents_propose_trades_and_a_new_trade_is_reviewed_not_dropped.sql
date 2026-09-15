-- A SUPPLIER'S DOCUMENTS PROPOSE TRADES, A NEW TRADE IS REVIEWED NOT DROPPED, AND EVERY TRADE HAS
-- AN ARABIC LABEL. Seat: sales_engineer. 15 Sep 2026.
--
-- Founder: "The sales engineer must actually read company profiles and catalogues" — extract the
-- trades, then CONFIRM them with the supplier. And (14 Sep): "our categories are not finalized. if a
-- supplier comes tomorrow and register for packaging services he is welcomed".
--
-- MEASURED BEFORE THIS FILE (production, 15 Sep 2026):
--   * supplier_capabilities: 15,306 rows, 15,305 extractor_version 'derived_from_directory_v1',
--     2 confirmed; source_docs = '{}' on the sampled rows; no column held what a document said.
--   * supplier_capability_confirmation: 0 rows.
--   * taxonomy_trade: 40 active codes with an English `label` only. The Arabic lived in the portal
--     (src/components/portal/supplier/serverCopy.ts TRADE_AR), so a trade added to the table had no
--     Arabic anywhere and every other reader of the table (emails, the seat) had none either.
--   * a trade the supplier typed outside the list was stored normalised (supplier_capability.ts) but
--     nobody was ever told a new trade had arrived — no row, no owner, no review.
--
-- WHAT THIS CHANGES
--   1. supplier_capabilities.proposed_trades — the codes the supplier's own documents name, written
--      by _shared/supplier_doc_trades.ts with per-file evidence in the existing source_docs column.
--      It never feeds matching: fn_match_capability reads trades + confirmed_at, which only the
--      supplier's confirm writes.
--   2. taxonomy_trade.label_ar, filled for all 40 active codes from the same wording the portal shows.
--   3. taxonomy_trade_proposal — a trade a supplier named that is not in taxonomy_trade, owned by the
--      sales_engineer seat. fn_trade_proposal_decide is the seat's one door: 'add' puts it in the
--      vocabulary under the supplier's own code (so the supplier's confirmed trade keeps matching),
--      'offer_map' offers an existing code (applied only when the supplier ticks it and confirms),
--      'reject' closes it with a note.
--
-- WHAT THIS DOES NOT CHANGE: fn_norm_trades, fn_match_capability, the directory derivation, and the
-- aliases (still English; an Arabic-only document proposes nothing and the file says so).

alter table public.supplier_capabilities
  add column if not exists proposed_trades text[] not null default '{}';
comment on column public.supplier_capabilities.proposed_trades is
  'Trade codes the supplier''s own documents name (supplier_doc_trades.ts, deterministic). A proposal only: matching reads trades + confirmed_at. Evidence per file is in source_docs.docs.';

alter table public.taxonomy_trade add column if not exists label_ar text;

update public.taxonomy_trade t set label_ar = v.ar
from (values
  ('hvac','التكييف والتهوية'), ('electrical','الأعمال الكهربائية'), ('building_materials','مواد البناء والتشييد'),
  ('engineering_consultancy','الاستشارات الهندسية والعمارة'), ('power_generators','المولدات ومعدات الطاقة'),
  ('heavy_equipment','المعدات الثقيلة والآليات'), ('labour_supply','توريد العمالة'), ('plumbing','السباكة والأدوات الصحية'),
  ('safety_equipment','معدات السلامة والوقاية الشخصية'), ('solar','الطاقة الشمسية والمتجددة'),
  ('chemicals','الكيماويات الصناعية والإنشائية'), ('plastics_pipes','البلاستيك والأنابيب والتجهيزات'),
  ('oilfield','مستلزمات حقول النفط والصناعة'), ('home_automation','أتمتة المنازل والمباني'),
  ('logistics_moving','النقل والتخزين والخدمات اللوجستية'), ('packaging','مستلزمات التغليف والطباعة'),
  ('marine','المستلزمات والأعمال البحرية'), ('fire_fighting','مكافحة الحريق وأنظمة السلامة'),
  ('it_services','خدمات تقنية المعلومات والشبكات'), ('joinery','النجارة والأعمال الخشبية'), ('glazing','الزجاج والواجهات الزجاجية'),
  ('aluminium','الألمنيوم والتكسية'), ('steel','الحديد وتشكيل المعادن'), ('flooring','الأرضيات'), ('painting','الدهانات والتشطيبات'),
  ('gypsum','الجبس والقواطع والأسقف'), ('signage','اللافتات والطباعة'), ('landscaping','تنسيق الحدائق والمسابح'),
  ('security_systems','الأنظمة الأمنية'), ('elevators','المصاعد والسلالم المتحركة'), ('doors','الأبواب والنوافذ'),
  ('waterproofing','العزل المائي والحراري'), ('upholstery','التنجيد والمفروشات'), ('wallpaper','ورق الجدران والتشطيبات الجدارية'),
  ('scaffolding','السقالات ومعدات الوصول'), ('cleaning','التنظيف وخدمات المرافق'), ('av_it','الصوت والصورة والتيار الخفيف'),
  ('interior_fitout','التشطيبات والتجهيزات الداخلية'), ('civil_works','الأعمال المدنية والإنشائية'),
  ('mep_general','الأعمال الكهروميكانيكية المتكاملة (MEP)')
) v(code, ar)
where t.code = v.code and t.label_ar is distinct from v.ar;

create table if not exists public.taxonomy_trade_proposal (
  id          bigserial primary key,
  supplier_id bigint not null references public.leads(id) on delete cascade,
  code        text not null check (btrim(code) <> ''),
  label_en    text,
  label_ar    text,
  status      text not null default 'pending'
              check (status in ('pending', 'added', 'map_offered', 'mapped', 'rejected')),
  mapped_to   text references public.taxonomy_trade(code),
  owner_seat  text not null default 'sales_engineer' check (owner_seat = 'sales_engineer'),
  note        text,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  text,
  unique (supplier_id, code),
  check (label_en is not null or label_ar is not null),
  check ((status in ('map_offered', 'mapped')) = (mapped_to is not null))
);
comment on table public.taxonomy_trade_proposal is
  'A trade a supplier named that taxonomy_trade does not hold. Owned by the sales_engineer seat; decided only through fn_trade_proposal_decide. Never silently dropped, never mapped to a neighbour without the supplier ticking it.';
create index if not exists taxonomy_trade_proposal_pending on public.taxonomy_trade_proposal (created_at) where status = 'pending';

alter table public.taxonomy_trade_proposal enable row level security;
drop policy if exists taxonomy_trade_proposal_service_role_only on public.taxonomy_trade_proposal;
create policy taxonomy_trade_proposal_service_role_only on public.taxonomy_trade_proposal
  as permissive for all to public using (false) with check (false);
revoke all on public.taxonomy_trade_proposal from anon, authenticated;
revoke all on sequence public.taxonomy_trade_proposal_id_seq from anon, authenticated;

create or replace function public.fn_trade_proposal_decide(
  p_id bigint, p_decision text, p_code text default null,
  p_label_en text default null, p_label_ar text default null, p_note text default null)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.taxonomy_trade_proposal; v_label text;
begin
  select * into r from public.taxonomy_trade_proposal where id = p_id for update;
  if r.id is null then raise exception 'fn_trade_proposal_decide: no proposal %', p_id; end if;
  if r.status not in ('pending', 'map_offered') then
    raise exception 'fn_trade_proposal_decide: proposal % is already %', p_id, r.status;
  end if;

  if p_decision = 'add' then
    -- Under the SUPPLIER'S code, never another: suppliers who confirmed this trade already hold it
    -- in supplier_capabilities.trades, and a different code would silently unmatch them.
    -- Siblings (other suppliers' PENDING proposals of the same code) are locked in id order first, so
    -- two concurrent 'add' decisions on one code queue instead of deadlocking.
    perform 1 from public.taxonomy_trade_proposal where code = r.code and status = 'pending' order by id for update;
    v_label := coalesce(nullif(btrim(p_label_en), ''), nullif(r.label_en, ''), r.label_ar);
    insert into public.taxonomy_trade (code, label, label_ar, aliases, sort, active)
    values (r.code, v_label, coalesce(nullif(btrim(p_label_ar), ''), r.label_ar),
            array_remove(array[lower(nullif(btrim(coalesce(p_label_en, r.label_en)), ''))], null), 900, true)
    on conflict (code) do nothing;
    update public.taxonomy_trade_proposal
       set status = 'added', mapped_to = null, decided_at = now(), decided_by = 'sales_engineer', note = coalesce(p_note, note)
     where id = r.id;
    -- Other suppliers' PENDING rows of the same code are now in the list too; they are marked as a
    -- consequence, with a system note naming the decision, never with this decision's note. A
    -- map_offered row is a separate decision for that supplier and is left alone.
    update public.taxonomy_trade_proposal
       set status = 'added', decided_at = now(), decided_by = 'sales_engineer',
           note = 'auto: code added to taxonomy_trade by proposal #' || r.id
     where code = r.code and status = 'pending' and id <> r.id;
  elsif p_decision = 'offer_map' then
    if not exists (select 1 from public.taxonomy_trade where code = p_code and active) then
      raise exception 'fn_trade_proposal_decide: % is not an active trade', p_code;
    end if;
    update public.taxonomy_trade_proposal
       set status = 'map_offered', mapped_to = p_code, decided_at = now(), decided_by = 'sales_engineer', note = coalesce(p_note, note)
     where id = r.id;
  elsif p_decision = 'reject' then
    update public.taxonomy_trade_proposal
       set status = 'rejected', mapped_to = null, decided_at = now(), decided_by = 'sales_engineer', note = coalesce(p_note, note)
     where id = r.id;
  else
    raise exception 'fn_trade_proposal_decide: decision must be add, offer_map or reject, not %', p_decision;
  end if;
  return (select to_jsonb(x) from public.taxonomy_trade_proposal x where x.id = r.id);
end $fn$;

revoke execute on function public.fn_trade_proposal_decide(bigint, text, text, text, text, text) from public, anon, authenticated;

-- PROBE. This file defines things, so the probe must not raise out of the file. Its writes run in an
-- inner block that always ends in an exception, which undoes them and keeps the DDL; the outer block
-- then asserts nothing was left behind. The subject is a ZZ DEMO lead at an @example.invalid address.
do $probe$
declare v_lead bigint; v_id bigint; v_msg text;
begin
  if exists (select 1 from public.taxonomy_trade where active and label_ar is null) then
    raise exception 'taxonomy_trade: an active trade has no label_ar';
  end if;
  select id into v_lead from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid' order by id limit 1;
  if v_lead is null then raise notice 'probe skipped: no ZZ DEMO lead'; return; end if;
  begin
    insert into public.taxonomy_trade_proposal (supplier_id, code, label_en)
    values (v_lead, 'zz_demo_probe_trade', 'ZZ DEMO probe trade') returning id into v_id;
    perform public.fn_trade_proposal_decide(v_id, 'add', null, null, 'تجربة', null);
    if not exists (select 1 from public.taxonomy_trade where code = 'zz_demo_probe_trade' and label_ar = 'تجربة' and active)
       or not exists (select 1 from public.taxonomy_trade_proposal where id = v_id and status = 'added') then
      raise exception 'PROBE_FAIL add did not reach taxonomy_trade';
    end if;
    raise exception 'PROBE_OK';
  exception when raise_exception then
    v_msg := sqlerrm;
    if v_msg <> 'PROBE_OK' then raise; end if;
  end;
  if exists (select 1 from public.taxonomy_trade where code = 'zz_demo_probe_trade')
     or exists (select 1 from public.taxonomy_trade_proposal where code = 'zz_demo_probe_trade') then
    raise exception 'probe left rows behind';
  end if;
  raise notice 'probe ok: a proposal added reaches taxonomy_trade with its Arabic label; nothing left behind';
end $probe$;
