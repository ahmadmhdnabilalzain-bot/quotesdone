-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205400   name: p2_c1_stage_b7_regression_suite
-- SHA-256 of the applied SQL: 11d635b881c999f52b61a28625c2f90b4830f36da1e14c2963de99a9374f44a1
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (5/6) - PART 3: permanent regression tests, one root cause at a time.
--
-- These are not the holdout. The holdout measures; this suite defends. Every case here exists
-- because a specific rule was wrong, and each one asserts the RULE that fixed it - not only the
-- answer. expect_basis pins the classification_basis, so a future change that produces the right
-- disposition through the wrong reasoning still fails. A test that only checks the output would
-- let the phrase list creep back in one phrase at a time.
--
-- Every root cause carries at least one negative: the thing that must NOT happen. Positives alone
-- would be satisfied by a rule that fires on everything.

create table if not exists public.p2c1_b7_case (
  case_key            text primary key,
  root_cause          text not null check (root_cause in
                        ('excluded_vs_by_others','arabic_scope_modifier',
                         'hvac_phrase_identification','client_supplied_language')),
  polarity            text not null check (polarity in ('positive','negative')),
  text_en             text not null,
  text_ar             text,
  expect_active       text[] not null,
  expect_dispositions jsonb  not null default '{}'::jsonb,
  expect_components   jsonb  not null default '{}'::jsonb,
  expect_conflict     boolean not null default false,
  expect_basis        text,
  forbid_candidates   text[] not null default '{}',
  note                text not null
);
alter table public.p2c1_b7_case enable row level security;

comment on column public.p2c1_b7_case.expect_basis is
  'Sorted, comma-joined distinct classification_basis over every recorded disposition that is not `included`. Null means not asserted. This is what stops a correct answer reached by the wrong rule from passing.';
comment on column public.p2c1_b7_case.forbid_candidates is
  'Trades that must not even be raised as candidates. Used for the abbreviation-inside-a-longer-term guard, where the failure mode is a proposal nobody asked for rather than a wrong activation.';

insert into public.p2c1_b7_case
 (case_key, root_cause, polarity, text_en, text_ar, expect_active, expect_dispositions,
  expect_components, expect_conflict, expect_basis, forbid_candidates, note) values

-- ROOT CAUSE 1 - who, if anyone, is responsible
('r1_removal_no_party','excluded_vs_by_others','positive',
 'Fire fighting is not in our scope.',
 'مكافحة الحريق ليست ضمن نطاق عملنا.',
 '{}','{"fire":"excluded"}','{}',false,'removal_unattributed','{}',
 'Scope leaves us and nobody is named. Excluded, not by_others. This is the v1 x09 failure.'),

('r1_removal_variant_outside','excluded_vs_by_others','positive',
 'Electrical works are outside our scope.',
 'الأعمال الكهربائية خارج نطاق عملنا.',
 '{}','{"electrical":"excluded"}','{}',false,'removal_unattributed','{}',
 'A second removal phrasing, to prove the rule is not tied to one string.'),

('r1_removal_with_party','excluded_vs_by_others','positive',
 'Fire fighting is not in our scope and is handled by the civil contractor.',
 'مكافحة الحريق ليست ضمن نطاق عملنا وتتم من قبل المقاول المتخصص.',
 '{}','{"fire":"by_others"}','{}',false,'removal_attributed','{}',
 'Same removal phrase, same clause, a party now identified. by_others - and the party is recorded.'),

('r1_by_others_third_party','excluded_vs_by_others','positive',
 'HVAC by the main contractor.',
 'التكييف من قبل المقاول الرئيسي.',
 '{}','{"hvac":"by_others"}','{}',false,'fixed_marker','{}',
 'The attributive form still classifies by_others directly. Regression guard on the old path.'),

('r1_counterparty_without_supply','excluded_vs_by_others','negative',
 'ELV by the client.',
 'التيار الخفيف من قبل العميل.',
 '{}','{"elv":"by_others"}','{}',false,'fixed_marker','{}',
 'NEGATIVE: a counterparty with no supply anchor is by_others. client_supplied must not spread to every mention of the client.'),

-- ROOT CAUSE 2 - Arabic scope and package modifiers
('r2_ar_package_anchor','arabic_scope_modifier','positive',
 'MEP package is required for the tower.',
 'حزمة كهروميكانيكية مطلوبة للبرج.',
 '{electrical,hvac,plumbing}','{}','{}',false,null,'{}',
 'Container word beside an MEP anchor, same clause, in both languages. The v1 x10/x20 parity failure.'),

('r2_ar_bundle_anchor','arabic_scope_modifier','positive',
 'Bundle of MEP works for the villa.',
 'باقة أعمال كهروميكانيكية للفيلا.',
 '{electrical,hvac,plumbing}','{}','{}',false,null,'{}',
 'A second container word, with one intervening word, inside the adjacency window.'),

('r2_ar_container_alone','arabic_scope_modifier','negative',
 'Complete office package for 50 staff.',
 'حزمة مكتبية كاملة لخمسين موظف.',
 '{}','{}','{}',false,null,'{hvac,electrical,plumbing}',
 'NEGATIVE: container plus completeness, no anchor. Must activate nothing and raise nothing.'),

('r2_ar_container_furniture','arabic_scope_modifier','negative',
 'Full furniture package.',
 'طقم أثاث كامل.',
 '{}','{}','{}',false,null,'{hvac,electrical,plumbing}',
 'NEGATIVE: a different industry. The container class must not be a back door into MEP.'),

('r2_ar_container_trade_only','arabic_scope_modifier','negative',
 'Electrical package.',
 'حزمة كهرباء.',
 '{electrical}','{}','{}',false,null,'{hvac,plumbing}',
 'NEGATIVE: a container word beside ONE trade name promotes nothing. Only an MEP anchor reaches the trio.'),

('r2_ar_container_cross_sentence','arabic_scope_modifier','negative',
 'The building is complete. MEP works required.',
 'المبنى كامل. أعمال كهروميكانيكية مطلوبة.',
 '{}','{}','{}',false,null,'{}',
 'NEGATIVE: modifier and anchor in different sentences. Co-occurrence is not adjacency, in either language.'),

-- ROOT CAUSE 3 - HVAC phrases and the ambiguous abbreviation
('r3_central_ac','hvac_phrase_identification','positive',
 'Central AC units and electrical panels.',
 'مكيفات مركزية ولوحات كهربائية.',
 '{electrical,hvac}','{}','{}',false,null,'{}',
 'Multi-token unambiguous HVAC phrase. The v1 g01 parity failure: Arabic found HVAC, English did not.'),

('r3_split_ac','hvac_phrase_identification','positive',
 'Supply and install split AC for the villa.',
 'توريد وتركيب مكيفات سبليت للفيلا.',
 '{hvac}','{}','{}',false,null,'{}',
 'A second unambiguous multi-token form. Confirms; does not merely propose.'),

('r3_ac_alone_asks','hvac_phrase_identification','negative',
 'AC required for the office.',
 null,
 '{}','{}','{}',false,null,'{}',
 'NEGATIVE: a bare ambiguous abbreviation must never auto-confirm a trade. It is raised as a hint and asked about. English only - Arabic has no equally ambiguous two-letter form, and inventing one would test nothing.'),

('r3_access_control_no_force','hvac_phrase_identification','negative',
 'Access control system for the office entrance.',
 null,
 '{elv}','{}','{}',false,null,'{hvac}',
 'NEGATIVE: the abbreviation inside a longer unrelated term has no independent force. HVAC must not even be proposed. ELV is expected and correct - access control reaches it through a catalogue alias, which is exactly the longer term being read as itself.'),

('r3_hvac_token_intact','hvac_phrase_identification','negative',
 'HVAC works required.',
 'أعمال التكييف مطلوبة.',
 '{hvac}','{}','{}',false,null,'{electrical,plumbing}',
 'NEGATIVE: `ac` inside `hvac` has no independent force either, and the existing HVAC path is untouched.'),

-- ROOT CAUSE 4 - client-supplied language
('r4_supply_by_client','client_supplied_language','positive',
 'AHU supply by client.',
 'توريد AHU من قبل العميل.',
 '{hvac}','{}','{"supply":"client_supplied"}',false,'supply_attributed_counterparty','{}',
 'The v1 i04 failure: read as by_others because "by client" was in the by_others list. Supply attributed to the counterparty is client_supplied, and HVAC stays active for the work we keep.'),

('r4_client_will_supply','client_supplied_language','positive',
 'The client will supply the chillers; installation and commissioning by us.',
 'العميل سيقوم بتوريد الشيلرات؛ التركيب والتشغيل من قبلنا.',
 '{hvac}','{}','{"supply":"client_supplied"}',false,'supply_attributed_counterparty','{}',
 'The counterparty as the actor rather than the object of "by". Installation and commissioning remain with us, so the trade remains active.'),

('r4_free_issue_employer','client_supplied_language','positive',
 'Electrical panels are free issue by the employer; installation by the contractor.',
 'لوحات كهربائية توريد صاحب العمل؛ التركيب من قبل المقاول.',
 '{electrical}','{}','{"supply":"client_supplied"}',false,'supply_attributed_counterparty','{}',
 'Free issue carries no component word at all, so the supply component has to be inferred from the attribution itself.'),

('r4_supply_by_others','client_supplied_language','negative',
 'Plumbing installation only; supply by others.',
 'تركيب السباكة فقط؛ التوريد من قبل الغير.',
 '{plumbing}','{}','{"supply":"by_others"}',false,'fixed_marker','{}',
 'NEGATIVE: an unnamed third party is not the client. by_others on the supply component, never client_supplied.'),

('r4_supply_by_main_contractor','client_supplied_language','negative',
 'Chiller supply by the main contractor; installation by the contractor.',
 'توريد الشيلرات من قبل المقاول الرئيسي؛ التركيب من قبل المقاول.',
 '{hvac}','{}','{"supply":"by_others"}',false,'fixed_marker','{}',
 'NEGATIVE: a named third party in the supply position is by_others. Telling a supplier the customer is free-issuing equipment nobody is free-issuing is the expensive direction of this error.')
on conflict (case_key) do nothing;

create or replace function public.fn_p2c1_b7_regression()
returns table(case_key text, root_cause text, polarity text, lang text,
              expected_active text, actual_active text,
              expected_disp text, actual_disp text,
              expected_comp text, actual_comp text,
              expected_basis text, actual_basis text,
              forbidden_raised text, conflict_ok boolean, passed boolean)
language plpgsql security definer set search_path to 'public' as $fn$
declare c public.p2c1_b7_case%rowtype; g bigint; L text; txt text;
        act text[]; d text; cm text; bs text; ed text; ec text; isconf boolean; forb text[];
begin
  for c in select * from public.p2c1_b7_case order by root_cause, case_key loop
    foreach L in array array['en','ar'] loop
      txt := case when L='ar' then c.text_ar else c.text_en end;
      continue when txt is null;
      insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;
      perform public.fn_inquiry_interpret(g, txt, null, null, 'b7_regression');

      select coalesce(array_agg(trade_key order by trade_key),'{}') into act
        from public.inquiry_workstream where group_id = g and active;
      select coalesce(string_agg(s.trade_key||'='||s.disposition,' ' order by s.trade_key),'')
        into d from public.v_trade_scope_status s
       where s.group_id = g and s.disposition <> 'included';
      select coalesce(string_agg(distinct e.scope_component||'='||e.disposition,' '),'')
        into cm from public.v_scope_disposition_effective e
       where e.group_id = g and e.scope_component <> 'complete_trade_scope' and e.disposition <> 'included';
      select coalesce(string_agg(distinct x.classification_basis, ','), '') into bs
        from public.inquiry_scope_disposition x
       where x.group_id = g and x.disposition <> 'included';
      select exists (select 1 from public.v_trade_scope_status s where s.group_id=g and s.is_conflict) into isconf;
      select coalesce(array_agg(distinct t.trade_key order by t.trade_key),'{}') into forb
        from public.inquiry_trade_candidate t
       where t.group_id = g and t.trade_key = any(c.forbid_candidates)
         and t.status in ('proposed','confirmed');

      select coalesce(string_agg(k||'='||v,' ' order by k),'') into ed
        from jsonb_each_text(c.expect_dispositions) x(k,v);
      select coalesce(string_agg(k||'='||v,' ' order by k),'') into ec
        from jsonb_each_text(c.expect_components) x(k,v);

      case_key := c.case_key; root_cause := c.root_cause; polarity := c.polarity; lang := L;
      expected_active := array_to_string(c.expect_active,','); actual_active := array_to_string(act,',');
      expected_disp := ed; actual_disp := d; expected_comp := ec; actual_comp := cm;
      expected_basis := c.expect_basis; actual_basis := bs;
      forbidden_raised := array_to_string(forb,',');
      conflict_ok := (isconf = c.expect_conflict);
      passed := (act = c.expect_active and d = ed and cm = ec and conflict_ok
                 and cardinality(forb) = 0
                 and (c.expect_basis is null or c.expect_basis = bs));
      return next;

      perform set_config('quotesdone.p2c1_teardown','approved',true);
      delete from public.inquiry_state_audit where group_id = g;
      delete from public.inquiry_workstream_group where id = g;
      perform set_config('quotesdone.p2c1_teardown','',true);
    end loop;
  end loop;
end $fn$;

revoke all on function public.fn_p2c1_b7_regression() from public, anon, authenticated;
;