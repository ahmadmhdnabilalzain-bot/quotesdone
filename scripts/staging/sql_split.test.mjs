// Behavioural test for the splitter. Runs standalone: node sql_split.test.mjs
import { splitStatements } from './sql_split.mjs';

let fail = 0;
const eq = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { fail++; console.log(`FAIL ${name}\n  got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`); }
  else console.log(`PASS ${name}`);
};

eq('plain', splitStatements('select 1; select 2;'), ['select 1;', 'select 2;']);

eq('semicolon inside single quotes',
  splitStatements("insert into t values ('a;b'); select 1;"),
  ["insert into t values ('a;b');", 'select 1;']);

eq('escaped quote', splitStatements("select 'it''s; fine'; select 2;"),
  ["select 'it''s; fine';", 'select 2;']);

eq('dollar-quoted function body stays whole', splitStatements(
  `create function f() returns void as $$ begin perform 1; perform 2; end; $$ language plpgsql; select 9;`),
  ['create function f() returns void as $$ begin perform 1; perform 2; end; $$ language plpgsql;', 'select 9;']);

eq('tagged dollar quote', splitStatements(
  `create function g() returns void as $fn$ begin perform 1; end; $fn$ language plpgsql; select 8;`),
  ['create function g() returns void as $fn$ begin perform 1; end; $fn$ language plpgsql;', 'select 8;']);

eq('nested different tags', splitStatements(
  `create function h() returns void as $outer$ begin execute $q$ select 1; $q$; end; $outer$ language plpgsql;`),
  ['create function h() returns void as $outer$ begin execute $q$ select 1; $q$; end; $outer$ language plpgsql;']);

eq('line comment with semicolon', splitStatements("select 1; -- a; comment\nselect 2;"),
  ['select 1;', '-- a; comment\nselect 2;']);

eq('block comment with semicolon', splitStatements("select 1; /* a; b */ select 2;"),
  ['select 1;', '/* a; b */ select 2;']);

eq('comment-only chunk is dropped', splitStatements("select 1; -- trailing only\n"), ['select 1;']);

eq('double-quoted identifier', splitStatements('select "od;d" from t; select 2;'),
  ['select "od;d" from t;', 'select 2;']);

console.log(fail === 0 ? '\nALL SPLITTER TESTS PASS' : `\n${fail} SPLITTER TEST(S) FAILED`);
process.exit(fail === 0 ? 0 : 1);
