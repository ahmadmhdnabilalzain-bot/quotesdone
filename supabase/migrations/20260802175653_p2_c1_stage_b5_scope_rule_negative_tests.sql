-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802175653   name: p2_c1_stage_b5_scope_rule_negative_tests
-- SHA-256 of the applied SQL: 4d2cbe70b57c9c7fa8116612a71b3dfb43232a74846b1c24f1bff246060bb017
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.5 - permanent negative regression tests for the scope rule.
-- The positives were never the risk. The risk is a generic word quietly activating three trades.

create table if not exists public.p2c1_scope_case (
  case_key      text primary key,
  text_en       text not null,
  expect_trades text[] not null,
  polarity      text not null check (polarity in ('positive','negative')),
  note          text not null
);
alter table public.p2c1_scope_case enable row level security;

insert into public.p2c1_scope_case (case_key, text_en, expect_trades, polarity, note) values
  ('mep_package','MEP package', array['electrical','hvac','plumbing'],'positive',
   'Anchor plus modifier, adjacent. The canonical full-MEP request.'),
  ('complete_mep_works','complete MEP works', array['electrical','hvac','plumbing'],'positive',
   'Modifier before anchor, adjacent.'),
  ('complete_hvac_package','complete HVAC package', array['hvac'],'negative',
   'NEGATIVE: no MEP anchor. "complete" and "package" must not reach electrical or plumbing.'),
  ('electrical_package','electrical package', array['electrical'],'negative',
   'NEGATIVE: "package" must not promote one named trade into three.'),
  ('complete_office_package','complete office package', '{}','negative',
   'NEGATIVE: three generic words, no anchor, no trade. Must activate nothing at all.'),
  ('full_furniture_package','full furniture package', '{}','negative',
   'NEGATIVE: a different industry entirely.'),
  ('package_incl_plumb_elec','package including plumbing and electrical',
   array['electrical','plumbing'],'negative',
   'NEGATIVE: exactly the two named trades. "package" must not add HVAC.'),
  ('complete_project_fire','complete project including fire fighting', array['fire'],'negative',
   'NEGATIVE: "complete project" is not an MEP anchor, so the core trio must not be inferred.'),
  ('anchor_across_sentence','Full fit-out of offices. MEP coordination by others.', '{}','negative',
   'NEGATIVE: modifier and anchor are in different sentences. Co-occurrence is not adjacency.'),
  ('bare_anchor','MEP works.', '{}','negative',
   'NEGATIVE: a bare anchor with no full-scope modifier must ask, not assume.'),
  ('turnkey_mep','turnkey MEP for the tower', array['electrical','hvac','plumbing'],'positive',
   'Explicit full-MEP phrase.'),
  ('mep_only_hvac','Full MEP package - HVAC only please', array['hvac'],'negative',
   'NEGATIVE: an exclusivity qualifier suppresses the scope rule even with a valid anchor.')
on conflict (case_key) do nothing;

create or replace function public.fn_p2c1_scope_rule_tests()
returns table(case_key text, polarity text, expected text, actual text, passed boolean, note text)
language plpgsql security definer set search_path to 'public' as $fn$
declare c public.p2c1_scope_case%rowtype; g bigint; got text[];
begin
  for c in select * from public.p2c1_scope_case order by polarity desc, case_key loop
    insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;
    perform public.fn_trade_identify(g, c.text_en, null, null, 'scope_tests');
    select coalesce(array_agg(trade_key order by trade_key),'{}') into got
      from public.inquiry_workstream where group_id = g and active;

    case_key := c.case_key; polarity := c.polarity; note := c.note;
    expected := array_to_string(c.expect_trades, ',');
    actual   := array_to_string(got, ',');
    passed   := (got = c.expect_trades);
    return next;

    perform set_config('quotesdone.p2c1_teardown','approved',true);
    delete from public.inquiry_state_audit where group_id = g;
    delete from public.inquiry_workstream_group where id = g;
    perform set_config('quotesdone.p2c1_teardown','',true);
  end loop;
end $fn$;

revoke all on function public.fn_p2c1_scope_rule_tests() from public, anon, authenticated;
;