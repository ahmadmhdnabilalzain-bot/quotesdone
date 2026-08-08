-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802181851   name: p2_c1_stage_b6_dispatch_integration_and_tests
-- SHA-256 of the applied SQL: fb60097f411ed91a010b6172837f4eb30b781094a96434385b224f9126f490bc
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- P2-C1 STAGE B.6 (4/n) - dispatch report shows scope, and the eleven required examples become
-- permanent tests.

create or replace function public.fn_group_dispatch_report(p_group_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_gd public.v_group_dispatch%rowtype; v_blockers jsonb := '[]'::jsonb; r record;
        v_active jsonb; v_out jsonb; v_opt jsonb; v_conf jsonb; v_comp jsonb; v_n_active int;
begin
  select * into v_gd from public.v_group_dispatch where group_id = p_group_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_group'); end if;

  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'disposition', disposition)
                            order by trade_key), '[]'::jsonb), count(*)
    into v_active, v_n_active
    from public.v_trade_scope_status
   where group_id = p_group_id and coalesce(contributes,false) and coalesce(workstream_active,false);

  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'disposition', disposition,
                                               'reason', reason) order by trade_key), '[]'::jsonb)
    into v_out from public.v_trade_scope_status
   where group_id = p_group_id and disposition in ('excluded','by_others','client_supplied');

  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'disposition', disposition,
                                               'reason', reason) order by trade_key), '[]'::jsonb)
    into v_opt from public.v_trade_scope_status
   where group_id = p_group_id and disposition in ('optional','future_phase','proposed','unknown');

  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'clauses', clause_indexes,
                                               'reason', reason) order by trade_key), '[]'::jsonb)
    into v_conf from public.v_trade_scope_status
   where group_id = p_group_id and coalesce(is_conflict,false);

  select coalesce(jsonb_agg(jsonb_build_object('trade', trade_key, 'component', scope_component,
                                               'disposition', disposition) order by trade_key, scope_component), '[]'::jsonb)
    into v_comp from public.v_scope_disposition_effective
   where group_id = p_group_id and scope_component <> 'complete_trade_scope'
     and disposition <> 'included';

  if v_n_active = 0 then
    if jsonb_array_length(v_conf) > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','scope_confirmation_required','severity','blocking',
        'conflicts', v_conf,
        'detail','Contradictory scope statements of equal specificity. The customer must say which applies.',
        'remedy','Answer the open clarification.'));
    else
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','no_active_trade','severity','blocking',
        'excluded_or_by_others', v_out, 'optional_or_future', v_opt,
        'detail','Every detected trade is excluded, by others, optional, future-phase or unconfirmed. There is nothing in scope to dispatch.',
        'remedy','Confirm at least one trade as included, or answer the open clarification.'));
    end if;
  elsif jsonb_array_length(v_conf) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','scope_confirmation_required','severity','blocking', 'conflicts', v_conf,
      'detail','Some trades are active but an unresolved scope conflict remains.'));
  end if;

  if cardinality(v_gd.shared_missing_mandatory) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','shared_mandatory_missing','severity','blocking',
      'fields', to_jsonb(v_gd.shared_missing_mandatory),
      'detail','Shared project fields required by an active workstream are unanswered.'));
  end if;

  if not v_gd.no_unresolved_shared_conflict then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_shared_conflict','severity','blocking',
      'fields', (select coalesce(jsonb_agg(c.field_id), '[]'::jsonb)
                   from public.inquiry_answer_conflict c
                   join public.field_definition fd on fd.field_id = c.field_id
                  where c.group_id = p_group_id and c.resolved_at is null and fd.scope = 'shared'),
      'detail','A shared field has sources that disagree. Every workstream is affected.'));
  end if;

  for r in select * from public.v_workstream_dispatch
            where group_id = p_group_id and active and not dispatch_eligible loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_not_eligible','severity','blocking','trade_key', r.trade_key,
      'missing_mandatory', to_jsonb(r.missing_mandatory),
      'unresolved_conflicts', to_jsonb(r.blocked_by), 'gate_states', r.gate_states,
      'detail','This trade is not dispatch-eligible, so the group is not.'));
  end loop;

  for r in select gr.gate_key,
                  coalesce((select g.state::text from public.inquiry_gate g
                             where g.group_id = p_group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key), 'not_evaluated') as state
             from public.inquiry_gate_required gr where gr.level = 'group' loop
    if r.state not in ('passed','not_applicable') then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','group_gate_not_satisfied','severity','blocking',
        'gate_key', r.gate_key, 'state', r.state,
        'detail', case when r.state = 'not_evaluated'
                       then 'This gate has never been evaluated. Absent reads as failed.'
                       else 'Gate state is ' || r.state || '.' end));
    end if;
  end loop;

  if jsonb_array_length(v_comp) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','component_scope_restriction','severity','informational',
      'restrictions', v_comp,
      'detail','Parts of an active trade are out of scope. The trade still dispatches; the RFQ must carry the restriction.'));
  end if;

  for r in select trade_key, evidence_score, score_basis, evidence_source
             from public.inquiry_trade_candidate
            where group_id = p_group_id and status = 'proposed' loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_awaiting_confirmation','severity','informational','trade_key', r.trade_key,
      'evidence_source', r.evidence_source, 'evidence_score', r.evidence_score,
      'score_basis', r.score_basis,
      'detail','Proposed but not confirmed. It contributes nothing to dispatch until a person confirms it.'));
  end loop;

  if exists (select 1 from public.inquiry_trade_clarification
              where group_id = p_group_id and answered_at is null) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_clarification','severity','blocking',
      'question', (select question_en from public.inquiry_trade_clarification
                    where group_id = p_group_id and answered_at is null limit 1),
      'detail','The customer has been asked to settle the scope.'));
  end if;

  return jsonb_build_object(
    'ok', true, 'group_id', p_group_id,
    'overall_dispatch_eligible', (v_gd.overall_dispatch_eligible and v_n_active > 0
                                  and jsonb_array_length(v_conf) = 0),
    'active_included_trades', v_active,
    'excluded_or_by_others_trades', v_out,
    'optional_or_future_trades', v_opt,
    'unresolved_scope_conflicts', v_conf,
    'component_scope_restrictions', v_comp,
    'active_workstreams', v_gd.active_workstreams,
    'shared_complete', v_gd.shared_complete,
    'group_gate_states', v_gd.gate_states,
    'blocking_trades', to_jsonb(v_gd.blocking_trades),
    'blockers', v_blockers, 'blocker_count', jsonb_array_length(v_blockers));
end $fn$;

-- The eleven required examples, as permanent tests.
create table if not exists public.p2c1_disposition_case (
  case_key text primary key, text_en text not null, text_ar text,
  expect_active text[] not null, expect_dispositions jsonb not null default '{}'::jsonb,
  expect_components jsonb not null default '{}'::jsonb, expect_conflict boolean not null default false,
  note text
);
alter table public.p2c1_disposition_case enable row level security;

insert into public.p2c1_disposition_case
 (case_key, text_en, text_ar, expect_active, expect_dispositions, expect_components, expect_conflict, note) values
('d01','Complete fit-out; MEP by others.','تشطيب كامل؛ الأعمال الكهروميكانيكية من قبل الغير.','{}','{"hvac":"by_others","electrical":"by_others","plumbing":"by_others"}','{}',false,'No core MEP workstream may activate.'),
('d02','Complete MEP package; coordination by others.','حزمة كهروميكانيكية كاملة؛ التنسيق من قبل الغير.','{electrical,hvac,plumbing}','{}','{"coordination":"by_others"}',false,'Component exclusion must not kill the trade.'),
('d03','HVAC by others; electrical and plumbing included.','التكييف من قبل الغير؛ الكهرباء والسباكة مشمولة.','{electrical,plumbing}','{"hvac":"by_others"}','{}',false,null),
('d04','MEP excluded except plumbing.','الأعمال الكهروميكانيكية مستثناة عدا السباكة.','{plumbing}','{"hvac":"excluded","electrical":"excluded"}','{}',false,'Carve-out.'),
('d05','Fire alarm not required; CCTV required.','إنذار الحريق غير مطلوب؛ كاميرات المراقبة مطلوبة.','{elv}','{"fire":"excluded"}','{}',false,null),
('d06','ELV optional.','التيار الخفيف اختياري.','{}','{"elv":"optional"}','{}',false,null),
('d07','HVAC is planned for a future phase.','التكييف مخطط لمرحلة لاحقة.','{}','{"hvac":"future_phase"}','{}',false,null),
('d08','AHUs supplied by client; installation by contractor.','وحدات مناولة الهواء توريد العميل؛ التركيب من قبل المقاول.','{hvac}','{}','{"supply":"client_supplied"}',false,'Component split within an active trade.'),
('d09','Existing fire alarm to remain with modifications.','إنذار الحريق الحالي يبقى مع تعديلات.','{fire}','{"fire":"existing_only"}','{}',false,null),
('d10','MEP by main contractor. Electrical included in this package.','الأعمال الكهروميكانيكية من قبل المقاول الرئيسي. الكهرباء مشمولة في هذه الحزمة.','{electrical}','{"hvac":"by_others","plumbing":"by_others"}','{}',false,null),
('d11','HVAC included. HVAC excluded.','التكييف مشمول. التكييف مستثنى.','{}','{"hvac":"conflicted"}','{}',true,'Equal specificity contradiction. Never resolved by the last sentence.')
on conflict (case_key) do nothing;

create or replace function public.fn_p2c1_disposition_tests()
returns table(case_key text, lang text, expected_active text, actual_active text,
              expected_disp text, actual_disp text, expected_comp text, actual_comp text,
              conflict_ok boolean, passed boolean)
language plpgsql security definer set search_path to 'public' as $fn$
declare c public.p2c1_disposition_case%rowtype; g bigint; L text; txt text;
        act text[]; d text; cm text; ed text; ec text; isconf boolean;
begin
  for c in select * from public.p2c1_disposition_case order by case_key loop
    foreach L in array array['en','ar'] loop
      txt := case when L='ar' then c.text_ar else c.text_en end;
      continue when txt is null;
      insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;
      perform public.fn_inquiry_interpret(g, txt, null, null, 'disposition_tests');

      select coalesce(array_agg(trade_key order by trade_key),'{}') into act
        from public.inquiry_workstream where group_id = g and active;
      select coalesce(string_agg(s.trade_key||'='||s.disposition,' ' order by s.trade_key),'')
        into d from public.v_trade_scope_status s
       where s.group_id = g and s.disposition <> 'included';
      select coalesce(string_agg(distinct e.scope_component||'='||e.disposition,' '),'')
        into cm from public.v_scope_disposition_effective e
       where e.group_id = g and e.scope_component <> 'complete_trade_scope' and e.disposition <> 'included';
      select exists (select 1 from public.v_trade_scope_status s where s.group_id=g and s.is_conflict) into isconf;

      select coalesce(string_agg(k||'='||v,' ' order by k),'') into ed
        from jsonb_each_text(c.expect_dispositions) x(k,v);
      select coalesce(string_agg(k||'='||v,' ' order by k),'') into ec
        from jsonb_each_text(c.expect_components) x(k,v);

      case_key := c.case_key; lang := L;
      expected_active := array_to_string(c.expect_active,','); actual_active := array_to_string(act,',');
      expected_disp := ed; actual_disp := d; expected_comp := ec; actual_comp := cm;
      conflict_ok := (isconf = c.expect_conflict);
      passed := (act = c.expect_active and d = ed and cm = ec and conflict_ok);
      return next;

      perform set_config('quotesdone.p2c1_teardown','approved',true);
      delete from public.inquiry_state_audit where group_id = g;
      delete from public.inquiry_workstream_group where id = g;
      perform set_config('quotesdone.p2c1_teardown','',true);
    end loop;
  end loop;
end $fn$;

revoke all on function public.fn_p2c1_disposition_tests() from public, anon, authenticated;
revoke all on function public.fn_group_dispatch_report(bigint) from public, anon, authenticated;
;