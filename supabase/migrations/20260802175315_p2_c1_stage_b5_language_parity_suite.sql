-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802175315   name: p2_c1_stage_b5_language_parity_suite
-- SHA-256 of the applied SQL: 605297a6ef5e66d8aa8a3d95b83434df614a51631d425487e7149210eb966298
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.5 (4/5) - the paired English/Arabic identification suite, and the scope negatives.

create table if not exists public.p2c1_lang_case (
  case_key      text primary key,
  category      text not null,
  text_en       text,
  text_ar       text,
  doc_en        text,
  doc_ar        text,
  expect_trades text[] not null default '{}',
  expect_status text not null default 'confirmed'
                  check (expect_status in ('confirmed','proposed','none')),
  expect_clarify boolean not null default false,
  note          text
);
alter table public.p2c1_lang_case enable row level security;

comment on table public.p2c1_lang_case is
  'Paired cases. The same meaning in English and Arabic must produce the same trade set, the same confirmed/proposed split and the same clarification decision. Expectations are written from the meaning of the sentence, not from what the code currently does.';

insert into public.p2c1_lang_case
  (case_key, category, text_en, text_ar, expect_trades, expect_status, expect_clarify, note) values
  ('trade_hvac','single_trade','We need HVAC works for the villa.','نحتاج أعمال التكييف للفيلا.',
   array['hvac'],'confirmed',false,'Each of the five supported trades, named plainly.'),
  ('trade_electrical','single_trade','Electrical works for the tower.','أعمال الكهرباء للبرج.',
   array['electrical'],'confirmed',false,null),
  ('trade_plumbing','single_trade','Plumbing works for the building.','أعمال السباكة للمبنى.',
   array['plumbing'],'confirmed',false,null),
  ('trade_fire','single_trade','Fire fighting system required.','مطلوب نظام مكافحة الحريق.',
   array['fire'],'confirmed',false,null),
  ('trade_elv','single_trade','CCTV and security systems required.','مطلوب كاميرات مراقبة وأنظمة أمنية.',
   array['elv'],'confirmed',false,null),
  ('full_mep','full_mep','MEP package for a new building.','أعمال كهروميكانيكية كاملة لمبنى جديد.',
   array['electrical','hvac','plumbing'],'confirmed',false,'Full core MEP, both languages.'),
  ('two_elec_plumb','two_trade','Electrical and plumbing works.','أعمال الكهرباء والسباكة.',
   array['electrical','plumbing'],'confirmed',false,null),
  ('two_hvac_fire','two_trade','HVAC and fire fighting.','التكييف ومكافحة الحريق.',
   array['fire','hvac'],'confirmed',false,null),
  ('ambiguous_umbrella','ambiguous','MEP works.','أعمال كهروميكانيكية.',
   '{}','none',true,'Umbrella anchor, no full-scope modifier, no trade named.'),
  ('ambiguous_generic','ambiguous','We need a contractor for the project.','نحتاج مقاول للمشروع.',
   '{}','none',true,'No trade evidence at all.'),
  ('variant_plain_alef','spelling_variant','Electrical works.','اعمال الكهرباء.',
   array['electrical'],'confirmed',false,'Plain alef instead of hamza-alef.'),
  ('variant_ta_marbuta','spelling_variant','Electrical works for the project.','أعمال كهربائيه للمشروع.',
   array['electrical'],'confirmed',false,'Ta marbuta typed as ha - extremely common.'),
  ('gulf_ac_units','gulf_vocabulary','Central air conditioning units.','مكيفات مركزية.',
   array['hvac'],'confirmed',false,'Gulf usage: مكيفات rather than تكييف.'),
  ('gulf_drainage','gulf_vocabulary','Drainage and sanitary works.','أعمال الصرف الصحي والأدوات الصحية.',
   array['plumbing'],'confirmed',false,'Gulf usage for plumbing/drainage.'),
  ('mixed_mep_latin','mixed_language','Supply of MEP package for the tower.','توريد MEP package للبرج.',
   array['electrical','hvac','plumbing'],'confirmed',false,'Latin technical term inside Arabic text.'),
  ('mixed_elv_latin','mixed_language','ELV works including CCTV.','أعمال ELV تشمل CCTV.',
   array['elv'],'confirmed',false,null),
  ('generic_office','generic_word','Complete office package for 50 staff.','باقة مكتبية كاملة لخمسين موظف.',
   '{}','none',true,'"complete"/"package"/"كاملة" with no MEP anchor must activate nothing.'),
  ('generic_furniture','generic_word','Full furniture package.','طقم أثاث كامل.',
   '{}','none',true,'Same, for furniture.')
on conflict (case_key) do nothing;

insert into public.p2c1_lang_case
  (case_key, category, text_en, text_ar, doc_en, doc_ar, expect_trades, expect_status, expect_clarify, note) values
  ('doc_only_elv','document_only', null, null,
   'CCTV cameras and access control doors on the riser diagram.',
   'كاميرات مراقبة وأبواب تحكم بالدخول على مخطط الرايزر.',
   array['elv'],'proposed',true,
   'Approved document only. Must PROPOSE in both languages and activate nothing.')
on conflict (case_key) do nothing;

-- Runs one case in one language and returns what happened.
create or replace function public.fn_p2c1_run_lang_case(p_case_key text, p_lang text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare c public.p2c1_lang_case%rowtype; g bigint; r jsonb; v_txt text; v_doc text;
        v_conf text[]; v_prop text[]; v_active text[]; v_clar boolean;
begin
  select * into c from public.p2c1_lang_case where case_key = p_case_key;
  if not found then return jsonb_build_object('ok', false, 'error','unknown_case'); end if;

  v_txt := case when p_lang = 'ar' then c.text_ar else c.text_en end;
  v_doc := case when p_lang = 'ar' then c.doc_ar else c.doc_en end;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;
  r := public.fn_trade_identify(g, v_txt, null,
        case when v_doc is null then null else
          jsonb_build_array(jsonb_build_object('document_id','DOC-'||p_case_key,
                                               'approved', true, 'text', v_doc)) end,
        'lang_suite');

  select coalesce(array_agg(trade_key order by trade_key),'{}') into v_conf
    from public.inquiry_trade_candidate where group_id = g and status = 'confirmed';
  select coalesce(array_agg(trade_key order by trade_key),'{}') into v_prop
    from public.inquiry_trade_candidate where group_id = g and status = 'proposed';
  select coalesce(array_agg(trade_key order by trade_key),'{}') into v_active
    from public.inquiry_workstream where group_id = g and active;
  select exists (select 1 from public.inquiry_trade_clarification
                  where group_id = g and answered_at is null) into v_clar;

  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_state_audit where group_id = g;
  delete from public.inquiry_workstream_group where id = g;
  perform set_config('quotesdone.p2c1_teardown','',true);

  return jsonb_build_object('ok', true, 'lang', p_lang, 'text', v_txt,
                            'confirmed', to_jsonb(v_conf), 'proposed', to_jsonb(v_prop),
                            'activated', to_jsonb(v_active), 'clarify', v_clar);
end $fn$;

create or replace function public.fn_p2c1_lang_parity_suite()
returns table(
  case_key text, category text,
  en_trades text, ar_trades text,
  trade_set_agree boolean, status_agree boolean, clarify_agree boolean,
  en_false_pos text[], en_false_neg text[], ar_false_pos text[], ar_false_neg text[],
  verdict text)
language plpgsql security definer set search_path to 'public' as $fn$
declare c public.p2c1_lang_case%rowtype; en jsonb; ar jsonb;
        en_set text[]; ar_set text[]; en_stat text; ar_stat text;
begin
  for c in select * from public.p2c1_lang_case order by category, case_key loop
    en := public.fn_p2c1_run_lang_case(c.case_key, 'en');
    ar := public.fn_p2c1_run_lang_case(c.case_key, 'ar');

    -- the trade set under test is confirmed+proposed: what the system identified at all
    select array(select jsonb_array_elements_text(en->'confirmed')
                 union select jsonb_array_elements_text(en->'proposed') order by 1) into en_set;
    select array(select jsonb_array_elements_text(ar->'confirmed')
                 union select jsonb_array_elements_text(ar->'proposed') order by 1) into ar_set;

    en_stat := case when jsonb_array_length(en->'confirmed') > 0 then 'confirmed'
                    when jsonb_array_length(en->'proposed')  > 0 then 'proposed' else 'none' end;
    ar_stat := case when jsonb_array_length(ar->'confirmed') > 0 then 'confirmed'
                    when jsonb_array_length(ar->'proposed')  > 0 then 'proposed' else 'none' end;

    case_key := c.case_key; category := c.category;
    en_trades := array_to_string(en_set,','); ar_trades := array_to_string(ar_set,',');
    trade_set_agree := (en_set = ar_set);
    status_agree    := (en_stat = ar_stat);
    clarify_agree   := ((en->>'clarify')::boolean = (ar->>'clarify')::boolean);

    en_false_pos := array(select unnest(en_set) except select unnest(c.expect_trades) order by 1);
    en_false_neg := array(select unnest(c.expect_trades) except select unnest(en_set) order by 1);
    ar_false_pos := array(select unnest(ar_set) except select unnest(c.expect_trades) order by 1);
    ar_false_neg := array(select unnest(ar_set) except select unnest(ar_set) order by 1);
    ar_false_neg := array(select unnest(c.expect_trades) except select unnest(ar_set) order by 1);

    verdict := case
      when trade_set_agree and status_agree and clarify_agree
           and cardinality(en_false_pos)=0 and cardinality(en_false_neg)=0
           and cardinality(ar_false_pos)=0 and cardinality(ar_false_neg)=0
        then 'PASS'
      when not trade_set_agree then 'PARITY_MISMATCH'
      when cardinality(en_false_pos)+cardinality(ar_false_pos) > 0 then 'FALSE_POSITIVE'
      when cardinality(en_false_neg)+cardinality(ar_false_neg) > 0 then 'FALSE_NEGATIVE'
      else 'STATUS_OR_CLARIFY_MISMATCH' end;
    return next;
  end loop;
end $fn$;

revoke all on function public.fn_p2c1_run_lang_case(text, text) from public, anon, authenticated;
revoke all on function public.fn_p2c1_lang_parity_suite() from public, anon, authenticated;
;