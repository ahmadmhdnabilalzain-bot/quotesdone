-- THE NIGHTLY REFLECTION CATCHES UP THE NIGHTS IT MISSED (3 Sep 2026).
--
-- The Row #3 scorer asks whether the nine questions were answered on each of the last seven nights
-- (consciousness-nightly-self-questions). Measured before this change: 0 of 63 (night, question)
-- pairs — the last reflection row is dated 15 Aug, the stand-down switched company_reflect_nightly
-- off on the 16th, and it was only put back on the clock on 2-3 Sep. The routine itself never
-- waited on a model: it is nine SQL reads. The brief's diagnosis ("almost certainly waits on the
-- held model") was wrong; the job was off.
--
-- What was actually missing is a mechanism: a nightly job that can only ever write TONIGHT leaves a
-- permanent hole for every night it was down. This fn_company_reflect reflects on every night of
-- the last seven that has no row, then on tonight, through fn_company_reflect_night — which reads
-- each night's facts from that night's own window and labels, in the answer text, the present-state
-- readings it cannot reconstruct for a past night. Past nights are only ever FILLED, never
-- overwritten; tonight is always recomputed because the 21:30 UTC tick is what closes the day.
--
-- One agent_runs row per tick, as before, now saying how many nights it covered.

create or replace function public.fn_company_reflect()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_night date; v_r jsonb; v_last jsonb; n_nights int := 0; n_late int := 0;
  n_concern int := 0; n_act int := 0;
begin
  for v_night in
    select d::date from generate_series(current_date - 7, current_date, interval '1 day') d
     where d::date = current_date
        or not exists (select 1 from company_reflection r where r.reflected_on = d::date)
     order by 1
  loop
    v_r := public.fn_company_reflect_night(v_night);
    n_nights := n_nights + 1;
    if coalesce((v_r->>'late')::boolean, false) then n_late := n_late + 1; end if;
    n_concern := n_concern + coalesce((v_r->>'concerns')::int, 0);
    n_act     := n_act     + coalesce((v_r->>'actions')::int, 0);
    v_last := v_r;
  end loop;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_reflect',now(),now(),'ok',
    jsonb_build_object('nights',n_nights,'late',n_late,'concerns',n_concern,'actions',n_act),
    'Nightly self-reflection: '||n_nights||' night(s) reflected ('||n_late||' caught up late), '
      ||n_concern||' concern(s), '||n_act||' action(s) opened. Nobody asked for this.');

  return jsonb_build_object('nights',n_nights,'late',n_late,'concerns',n_concern,'actions',n_act,
                            'answers',v_last->'answers');
end $function$;
