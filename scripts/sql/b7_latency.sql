-- End-to-end latency of fn_inquiry_interpret over the full 54-case corpus in both languages.
-- Measured in the database, per call, with the fixture teardown excluded from the timer.
create or replace function pg_temp.b7_latency()
returns table(line text) language plpgsql as $fn$
declare c record; g bigint; t0 timestamptz; t1 timestamptz; L text; txt text;
        ms numeric[] := '{}'; v numeric; n int;
begin
  for c in select case_key, text_en, text_ar from public.p2c1_holdout_case order by case_key loop
    foreach L in array array['en','ar'] loop
      txt := case when L='ar' then c.text_ar else c.text_en end;
      insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;
      t0 := clock_timestamp();
      perform public.fn_inquiry_interpret(g, txt, null, null, 'latency_probe');
      t1 := clock_timestamp();
      ms := ms || round((extract(epoch from (t1 - t0)) * 1000)::numeric, 2);
      perform set_config('quotesdone.p2c1_teardown','approved',true);
      delete from public.inquiry_state_audit where group_id = g;
      delete from public.inquiry_workstream_group where id = g;
      perform set_config('quotesdone.p2c1_teardown','',true);
    end loop;
  end loop;
  n := cardinality(ms);
  line := 'interpretations timed  : ' || n::text || '  (54 cases x 2 languages)'; return next;
  select round(avg(x),1) into v from unnest(ms) x;
  line := 'mean ms                : ' || v::text; return next;
  select round(percentile_cont(0.5) within group (order by x)::numeric,1) into v from unnest(ms) x;
  line := 'p50 ms                 : ' || v::text; return next;
  select round(percentile_cont(0.95) within group (order by x)::numeric,1) into v from unnest(ms) x;
  line := 'p95 ms                 : ' || v::text; return next;
  select round(max(x),1) into v from unnest(ms) x;
  line := 'max ms                 : ' || v::text; return next;
  select round(sum(x),0) into v from unnest(ms) x;
  line := 'total ms for the corpus: ' || v::text; return next;
end $fn$;
select * from pg_temp.b7_latency();
