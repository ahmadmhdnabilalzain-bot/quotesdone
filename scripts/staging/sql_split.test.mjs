// Behavioural test for the splitter. Runs standalone: node sql_split.test.mjs
import { splitStatements, repairDumpSectionBreaks } from './sql_split.mjs';

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

// The shape fn_schema_export() actually emits: 0 of 590 function definitions are terminated with
// a semicolon. Every test above ends its function with ';', which is why the suite passed while
// the real dump collapsed into a single 1.1 MB statement.
eq('unterminated function body ends at the next CREATE', splitStatements(
  `CREATE OR REPLACE FUNCTION public.a() RETURNS int LANGUAGE sql AS $function$ select 1 $function$\n\n\n` +
  `CREATE OR REPLACE FUNCTION public.b() RETURNS int LANGUAGE sql AS $function$ select 2 $function$\n`),
  ['CREATE OR REPLACE FUNCTION public.a() RETURNS int LANGUAGE sql AS $function$ select 1 $function$',
   'CREATE OR REPLACE FUNCTION public.b() RETURNS int LANGUAGE sql AS $function$ select 2 $function$']);

eq('trailing clause after body is not a boundary', splitStatements(
  `create function f() returns void as $$ begin perform 1; end; $$ language plpgsql; select 9;`),
  ['create function f() returns void as $$ begin perform 1; end; $$ language plpgsql;', 'select 9;']);

// A literal backslash-n after a section header leaves the next statement inside the comment.
// This cost action_class_gate: it could not be created from the baseline at any point.
eq('literal \\n in a section header is repaired', splitStatements(
  repairDumpSectionBreaks('-- ===== TABLES (403) =====\\nCREATE TABLE public.a (x int);')),
  ['-- ===== TABLES (403) =====\nCREATE TABLE public.a (x int);']);

eq('a real newline section header is untouched', splitStatements(
  repairDumpSectionBreaks('-- ===== TABLES =====\nCREATE TABLE public.b (x int);')),
  ['-- ===== TABLES =====\nCREATE TABLE public.b (x int);']);

eq('backslash-n inside a string literal survives', repairDumpSectionBreaks(
  "select 'line1\\nline2';"), "select 'line1\\nline2';");

eq('line comment with semicolon', splitStatements("select 1; -- a; comment\nselect 2;"),
  ['select 1;', '-- a; comment\nselect 2;']);

eq('block comment with semicolon', splitStatements("select 1; /* a; b */ select 2;"),
  ['select 1;', '/* a; b */ select 2;']);

eq('comment-only chunk is dropped', splitStatements("select 1; -- trailing only\n"), ['select 1;']);

eq('double-quoted identifier', splitStatements('select "od;d" from t; select 2;'),
  ['select "od;d" from t;', 'select 2;']);

console.log(fail === 0 ? '\nALL SPLITTER TESTS PASS' : `\n${fail} SPLITTER TEST(S) FAILED`);
process.exit(fail === 0 ? 0 : 1);
