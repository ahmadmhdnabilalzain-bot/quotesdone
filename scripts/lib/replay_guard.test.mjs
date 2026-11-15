// THE REPLAY GUARD, ROUND 3 (it_engineer, 15 Nov 2026): the shapes the second independent review of 13 Nov measured passing it on a
// local Postgres 16 (SP guard_review2: attack/, tt/, lift.mjs), each now refused before anything is sent, and the 15 files it must
// let through still let through. Offline: a cut-down catalogue stands in for production's pg_class; nothing is sent anywhere.
//   node --test scripts/lib/replay_guard.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { applyLockTimeout, catalogueFrom, dynamicSql, lex, limitLifters, planReplay, stallsLiveUsers, statedLocks, tightenLimits } from './replay_guard.mjs';

const CATALOGUE = catalogueFrom({ relations: ['public.quotes', 'public.leads', 'public.app_secrets', 'public.inquiry_gate', 'public.zz_domtab',
  'public.quotes_pkey>public.quotes', 'storage.objects', 'auth.users'].join(',') });
const plan = (t) => planReplay(t, { label: 'f.sql', catalogue: CATALOGUE });

// ---- item 2: what lifted a limit ------------------------------------------------------------------------------------------
const LIFTS = {
  'quoted lock_timeout': 'set local "lock_timeout" = 0;',
  'DO EXECUTE lock_timeout': "do $$ begin execute 'set local lock_timeout = 0'; end $$;",
  "E'' set_config lock_timeout": "select set_config(E'lock_timeout', '0', true);",
  'quoted transaction_timeout': 'set local "transaction_timeout" = 0;',
  'DO EXECUTE transaction_timeout': "do $$ begin execute 'set local transaction_timeout = 0'; end $$;",
  "E'' set_config transaction_timeout": "select set_config(E'transaction_timeout', '0', true);",
  'concatenated set_config name': "select set_config('transaction' || '_timeout', '0', true);",
  'U& quoted name': 'set local U&"lock\\005ftimeout" = 0;',
  "U& set_config name": "select set_config(U&'transaction\\005ftimeout', '0', true);",
  'statement_timeout in a DO block': "do $$ begin set local statement_timeout = 0; end $$;",
  'statement_timeout by set_config': "select set_config('statement_timeout', '0', true);",
  'lock_timeout by set_config': "select set_config('lock_timeout', '0', true);",
  'variable set_config name': "do $$ declare n text := 'lock_timeout'; begin perform set_config(n, '0', true); end $$;",
  'transaction_timeout in a routine body': "create function public.zz_t() returns void language sql as $f$ select set_config('transaction_timeout', '0', true) $f$;",
  'transaction_timeout in a comment': '-- transaction_timeout\nselect 1;',
  'RESET in a DO block': 'do $$ begin reset lock_timeout; end $$;',
};

test('review 2, item 2: every shape that lifted lock_timeout or transaction_timeout is refused by tightenLimits, the apply\'s and the replay\'s', () => {
  for (const [name, t] of Object.entries(LIFTS)) {
    assert.ok(limitLifters(t).length, `not seen: ${name}`);
    assert.throws(() => tightenLimits(t, 'f.sql'), /SAFE REPLAY REFUSED: f\.sql .*the guard owns those limits/, name);
    assert.throws(() => tightenLimits(t, 'f.sql', { cap: '1500ms' }), /REFUSED/, `apply: ${name}`);
    assert.throws(() => plan(t), /REFUSED/, `replay: ${name}`);
  }
});

test('review 2, item 2: a SET built at run time by an EXECUTE is refused as dynamic SQL, by the replay and by the apply', () => {
  const t = "do $$ begin execute 'set local transaction' || '_timeout = 0'; end $$;";
  assert.ok(dynamicSql(t).length, 'apply_sql refuses what dynamicSql lists');
  assert.throws(() => plan(t), /runs dynamic SQL/);
  assert.throws(() => planReplay(t, { label: 'f.sql', catalogue: CATALOGUE, acceptStall: true }), /runs dynamic SQL/);
});

test('review 2, item 2: the top-level SET lock_timeout is still lowered, and what does not touch a limit still passes', () => {
  assert.equal(tightenLimits("set local lock_timeout = 0;"), "set local lock_timeout = '1s';");
  assert.equal(tightenLimits("set lock_timeout to '15s';", 'a', { cap: '1500ms' }), "set local lock_timeout = '1500ms';");
  for (const t of ["select set_config('app.zz', '1', true);", "select set_config('search_path', 'public', true);", 'set local statement_timeout = 0;',
    "create function public.f() returns void language plpgsql as $f$ begin perform set_config('lock_timeout', v, true); end $f$;",
    "create function public.g() returns int language sql set lock_timeout to '2s' as $f$ select 1 $f$;",
    "comment on table public.quotes is $c$ set lock_timeout = 0 $c$;", "do $$ begin raise notice 'ok'; end $$;"]) {
    assert.deepEqual(limitLifters(t), [], t);
    tightenLimits(t);
  }
});

// ---- item 3: the 16 lock-taking shapes the early refusal missed --------------------------------------------------------------
const MISSES = {
  a01_unicode_ident: 'alter table U&"quotes" add column zz int;',
  a01b_unicode_escape: 'alter table U&"q\\0075otes" add column zz int;',
  a02_search_path: 'set local search_path = storage, public;\nalter table objects add column zz int;',
  a02b_search_path_set_config: "select set_config('search_path', 'storage, public', true);\nalter table objects add column zz int;",
  a03_execute_concat: "do $$ begin execute 'alter ' || 'table public.quotes add column zz int'; end $$;",
  a04_execute_variable: "do $$ declare s text := 'alter table public.quotes add column zz int'; begin execute s; end $$;",
  a06_drop_function_cascade: 'drop function public.fn_quote_supplier_is_immutable() cascade;',
  a07_drop_type_cascade: 'drop type public.gate_state cascade;',
  a08_alter_domain: 'alter domain public.zz_dom add constraint zz_pos check (value > 0);',
  a09_catalog_qualified: 'alter table postgres.public.quotes add column zz int;',
  a10_cluster_verbose: 'cluster verbose public.quotes using quotes_pkey;',
  a10b_cluster_options: 'cluster (verbose) public.quotes;',
  a10c_cluster_all: 'cluster;',
  a22_quoted_guc_then_lock: "set local \"lock_timeout\" = 0;\ndo $$ begin execute 'lock ' || 'table public.quotes'; end $$;",
  a25_create_index_dynamic: "do $$ declare t text := 'quotes'; begin execute 'create index zz_i on public.' || t || ' (id)'; end $$;",
  format_execute: "do $$ begin execute format('alter table %I add column x int', 'quotes'); end $$;",
};

test('review 2, item 3: each of the missed lock-taking shapes is refused on production before anything is sent', () => {
  for (const [name, t] of Object.entries(MISSES)) assert.throws(() => plan(t), /SAFE REPLAY REFUSED/, name);
  // ... for the reason it is, where the reason is a lock the text names
  const table = (t) => stallsLiveUsers(t, CATALOGUE).map((l) => l.table);
  assert.deepEqual(table(MISSES.a01_unicode_ident), ['quotes']);
  assert.deepEqual(table(MISSES.a01b_unicode_escape), ['quotes']);
  assert.deepEqual(table(MISSES.a02_search_path), ['storage.objects'], 'the name is read through the path the file set');
  assert.deepEqual(table(MISSES.a02b_search_path_set_config), ['storage.objects']);
  assert.deepEqual(table(MISSES.a09_catalog_qualified), ['quotes']);
  assert.deepEqual(table(MISSES.a10_cluster_verbose), ['quotes']);
  assert.deepEqual(table(MISSES.a10b_cluster_options), ['quotes']);
  for (const k of ['a06_drop_function_cascade', 'a07_drop_type_cascade', 'a08_alter_domain', 'a10c_cluster_all']) assert.deepEqual(table(MISSES[k]), ['?'], k);
  assert.match(stallsLiveUsers(MISSES.a08_alter_domain, CATALOGUE)[0].kind, /ALTER DOMAIN/);
  assert.equal(stallsLiveUsers(MISSES.a08_alter_domain, CATALOGUE)[0].mode, 'SHARE');
  // dynamic SQL is refused as dynamic SQL, whether or not the operator accepts a stall
  for (const k of ['a03_execute_concat', 'a04_execute_variable', 'a25_create_index_dynamic']) {
    assert.ok(dynamicSql(MISSES[k]).length, k);
    assert.throws(() => planReplay(MISSES[k], { label: 'f.sql', catalogue: CATALOGUE, acceptStall: true }), /runs dynamic SQL/, k);
  }
});

test('dynamic SQL: a literal EXECUTE is read, not refused; GRANT EXECUTE and EXECUTE FUNCTION are not EXECUTEs; a routine body is not run', () => {
  assert.deepEqual(dynamicSql("do $$ begin execute 'select 1'; execute 'select $1' using 2; execute $q$select 1$q$ into v; end $$;"), []);
  assert.deepEqual(dynamicSql('grant execute on function public.f() to anon; create trigger t after insert on public.zz for each row execute function f();'), []);
  assert.deepEqual(dynamicSql("create function public.f(s text) returns void language plpgsql as $f$ begin execute s; end $f$;"), []);
  assert.deepEqual(dynamicSql("do $$ begin revoke execute on function public.f() from public; end $$;"), []);
  // a literal EXECUTE that takes a lock is still refused for its lock
  assert.throws(() => plan("do $$ begin execute 'alter table public.quotes add column x int'; end $$;"), /takes a lock that stops live requests/);
});

test('the lexer decodes U& names and strings, with UESCAPE, and keeps E-strings marked', () => {
  assert.deepEqual(lex('U&"d\\0061t\\+000061"').map((t) => [t.t, t.v, !!t.u]), [['qid', 'data', true]]);
  assert.deepEqual(lex("U&'d!0061t!+000061' UESCAPE '!'").map((t) => [t.t, t.v]), [['str', 'data']]);
  assert.equal(lex("E'a\\'b'")[0].e, true);
  assert.equal(statedLocks('alter table U&"quotes" add column z int')[0].name, 'quotes');
});

// ---- what must still pass: the review's 15 files (SP guard_review2/pass), verbatim ------------------------------------------------
const MUST_PASS = {
  p01_new_table: 'create table public.zz_t (id int primary key, q text);',
  p02_new_function: 'create function public.zz_fn() returns int language sql as $$ select 1 $$;',
  p03_replace_existing_function: "CREATE OR REPLACE FUNCTION public.fn_accountant_duties_due()\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public', 'pg_temp'\nAS $function$\n  select not exists (select 1 from public.agent_runs where agent = 'accountant')\n$function$;",
  p04_insert: "insert into public.app_secrets(key, value) values ('zz_review_key', 'x');",
  p05_update_where: "update public.quotes set status = status where id = '00000000-0000-0000-0000-000000000000';",
  p06_delete_where: 'delete from public.leads where id = -1;',
  p07_policy_new_table: 'create table public.zz_t2 (id int);\nalter table public.zz_t2 enable row level security;\ncreate policy zz_p on public.zz_t2 for select using (true);',
  p08_index_new_table: 'create table public.zz_t3 (id int);\ncreate index zz_t3_i on public.zz_t3 (id);',
  p09_trigger_new_table: 'create table public.zz_t4 (id int);\ncreate function public.zz_tf() returns trigger language plpgsql as $$ begin return new; end $$;\ncreate trigger zz_tr before insert on public.zz_t4 for each row execute function public.zz_tf();',
  p10_new_view: 'create view public.zz_v as select 1 as one;',
  p11_comment_existing: "comment on table public.quotes is 'quotations';",
  p12_ddl_in_uncalled_function: 'create or replace function public.zz_ddl() returns void language plpgsql as $$ begin alter table public.quotes add column x int; end $$;',
  p13_alter_new_table: 'create table public.zz_t5 (id int);\nalter table public.zz_t5 add column b int, add constraint zz_t5_pk primary key (id);',
  p14_grants_new_function: 'create function public.zz_fn2() returns int language sql as $$ select 2 $$;\nrevoke execute on function public.zz_fn2() from public;\ngrant execute on function public.zz_fn2() to authenticated;',
  p15_tighter_lock_timeout: "set local lock_timeout = '500ms';\nselect set_config('app.zz', '1', true);\ninsert into public.app_secrets(key, value) values ('zz_review_key2', 'y');",
};

test('the 15 files the review measured as harmless still pass, unchanged but for nothing', () => {
  for (const [name, t] of Object.entries(MUST_PASS)) {
    const p = plan(t);
    assert.deepEqual(p.stalls, [], name);
    assert.equal(p.text, t, `${name}: the text is sent as written`);
  }
});

test('review 2, item 4: --lock-timeout below 1 ms is refused, and a fraction is rounded up', () => {
  for (const v of ['0.4', '0.999', '0', '0.5ms']) assert.throws(() => applyLockTimeout([`--lock-timeout=${v}`]), /refused/, v);
  assert.equal(applyLockTimeout(['--lock-timeout=1.01']), '2ms');
  assert.equal(applyLockTimeout(['--lock-timeout=1500']), '1500ms');
});
