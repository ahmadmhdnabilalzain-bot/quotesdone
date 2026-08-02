-- P2-C1 STAGE B (1/6) - BRAND POLICY, one canonical field with a real value domain.
-- Applied as migration p2_c1_stage_b_brand_acceptance_policy.
--
-- Founder decision, 2 Aug: the Stage A split of brand_policy into five trade fields was driven by
-- one word of corpus wording ("brand AND approved-equal" vs "brand OR approved-equal"). That word
-- is not noise - it is the difference between "this brand" and "this brand or an equal" - but the
-- answer is not to duplicate the field five times. It is to make the DISTINCTION a value, not a
-- field, and let a trade override the project default when it genuinely differs.

create table if not exists public.brand_acceptance_policy_value (
  policy_value                   text primary key,
  label_en                       text not null,
  label_ar                       text,
  requires_brand_list            boolean not null default false,
  requires_customer_confirmation boolean not null default false,
  permits_equivalent             boolean not null default false,
  sort_order                     integer not null default 0,
  note                           text
);
alter table public.brand_acceptance_policy_value enable row level security;

insert into public.brand_acceptance_policy_value
  (policy_value, label_en, label_ar, requires_brand_list, requires_customer_confirmation, permits_equivalent, sort_order, note) values
  ('named_brand_only','Named brand only','العلامة المحددة فقط', false, false, false, 1,
   'The named brand is the only acceptable supply. This is the "brand AND approved-equal policy" corpus wording read strictly: the brand is named and no equivalent is invited.'),
  ('named_brand_or_approved_equal','Named brand or approved equal','العلامة المحددة أو ما يعادلها المعتمد', false, false, true, 2,
   'A named brand with an equivalent permitted subject to approval. This is the "brand OR approved-equal policy" wording. Keeping this apart from named_brand_only is the whole point of the enum.'),
  ('approved_brand_list','Approved brand list','قائمة العلامات المعتمدة', true, false, true, 3,
   'Any brand on a supplied list is acceptable. Requires the list; without it the field is not answered.'),
  ('no_brand_restriction','No brand restriction','بدون قيود على العلامة', false, false, true, 4,
   'Any compliant product is acceptable.'),
  ('customer_confirmation_required','Customer confirmation required','يتطلب تأكيد العميل', false, true, false, 5,
   'The policy is not yet known and the customer must state it. Never satisfies a mandatory field on its own - it is the explicit "we do not know yet" value, which is safer than an inferred guess.')
on conflict (policy_value) do nothing;

-- Preserve the original corpus wording, per subcategory, with its route. Nothing is merged away.
create table if not exists public.field_question_variant (
  id               bigserial primary key,
  field_id         text not null references public.field_definition(field_id) on delete cascade,
  subcategory_slug text not null,
  catalog_num      integer,
  source_field_key text not null,
  question_en      text,
  question_ar      text,
  answer_type      text,
  unique (field_id, subcategory_slug, source_field_key)
);
alter table public.field_question_variant enable row level security;

comment on table public.field_question_variant is
  'The exact wording each subcategory used, kept so a canonical field never loses the question it came from. "brand and approved-equal policy" and "brand or approved-equal policy" both live here verbatim; the difference between them is carried by the value domain, not by an ambiguous free-text merge.';

alter table public.field_definition add column if not exists allowed_values text[];
alter table public.field_definition add column if not exists supersedes_field_ids text[];

insert into public.field_definition
  (field_id, scope, trade_key, label_en, label_ar, answer_type, allowed_values,
   evidence_rule, regulatory_interpretation, review_status, review_note)
values ('shared.brand_acceptance_policy','shared', null,
        'Brand acceptance policy for the project',
        'سياسة قبول العلامات التجارية للمشروع',
        'single_select',
        array['named_brand_only','named_brand_or_approved_equal','approved_brand_list','no_brand_restriction','customer_confirmation_required'],
        'One project-level default. A trade may override it; it may not silently diverge from it.',
        'approved_brand_list and named_brand_or_approved_equal both imply an approval step with the consultant or authority before substitution.',
        'approved',
        'Founder decision 2 Aug 2026: replaces the five trade-split *.brand_policy identities. The and/or distinction is now a value (named_brand_only vs named_brand_or_approved_equal), not a field split.')
on conflict (field_id) do nothing;

insert into public.field_definition
  (field_id, scope, trade_key, label_en, label_ar, answer_type, allowed_values,
   evidence_rule, review_status, review_note)
select t.trade_key || '.brand_acceptance_policy_override', 'trade_specific', t.trade_key,
       'Brand acceptance policy override (' || t.label_en || ')',
       'تجاوز سياسة قبول العلامات (' || coalesce(t.label_ar, t.label_en) || ')',
       'single_select',
       array['named_brand_only','named_brand_or_approved_equal','approved_brand_list','no_brand_restriction','customer_confirmation_required'],
       'Optional. Present only when this trade genuinely differs from the project default. Absent means inherit.',
       'approved',
       'Founder decision 2 Aug 2026: the override is optional and explicit. Absence is inheritance, not a missing answer, so it is never mandatory.'
  from public.mep_trade t
on conflict (field_id) do nothing;

insert into public.field_question_variant
  (field_id, subcategory_slug, catalog_num, source_field_key, question_en, question_ar, answer_type)
select distinct on (fs.subcategory_slug, q.field_key)
       'shared.brand_acceptance_policy', fs.subcategory_slug, m.catalog_num, q.field_key,
       q.question_en, q.question_ar, q.answer_type
  from public.field_definition_source fs
  join kb_stage.questions q
    on q.subcategory_slug = fs.subcategory_slug and q.field_key = fs.source_field_key
  join public.kb_operational_route_map m on m.subcategory_slug = fs.subcategory_slug
 where fs.source_field_key = 'brand_policy' and m.catalog_num in (9,10,11,12,13,14)
 order by fs.subcategory_slug, q.field_key, m.catalog_num
on conflict (field_id, subcategory_slug, source_field_key) do nothing;

update public.field_definition_source
   set field_id = 'shared.brand_acceptance_policy'
 where source_field_key = 'brand_policy';

-- Retire the superseded split identities. Guarded: refuses if any answer ever referenced them.
do $mig$
declare n integer;
begin
  select count(*) into n from public.inquiry_answer where field_id like '%.brand_policy';
  if n > 0 then
    raise exception 'refusing to retire %.brand_policy: % answers reference it', n, n;
  end if;
  delete from public.inquiry_workstream_requirement where field_id like '%.brand_policy';
  delete from public.field_definition where field_id like '%.brand_policy' and scope = 'trade_specific';
end $mig$;

update public.field_definition
   set supersedes_field_ids = array['hvac.brand_policy','electrical.brand_policy','plumbing.brand_policy','fire.brand_policy','elv.brand_policy']
 where field_id = 'shared.brand_acceptance_policy';

create or replace view public.v_workstream_brand_policy as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       sh.value as shared_default,
       ov.value as trade_override,
       coalesce(ov.value, sh.value) as effective_policy,
       case when ov.value is not null then 'trade_override'
            when sh.value is not null then 'shared_default'
            else 'unset' end as effective_source,
       d.permits_equivalent, d.requires_brand_list, d.requires_customer_confirmation
  from public.inquiry_workstream w
  left join public.inquiry_answer sh
    on sh.group_id = w.group_id and sh.field_id = 'shared.brand_acceptance_policy'
   and sh.superseded_by is null
  left join public.inquiry_answer ov
    on ov.group_id = w.group_id
   and ov.field_id = w.trade_key || '.brand_acceptance_policy_override'
   and ov.superseded_by is null
   and exists (select 1 from public.inquiry_answer_scope s
                where s.answer_id = ov.id and s.workstream_id = w.id)
  left join public.brand_acceptance_policy_value d
    on d.policy_value = coalesce(ov.value, sh.value);

comment on view public.v_workstream_brand_policy is
  'Effective brand policy per workstream: trade override, else shared default, else unset. Inheritance is derived from the absence of an override row - there is no copied-down default that can go stale.';
