CREATE OR REPLACE FUNCTION public.fn_phase_d_injected_defect_report()
 RETURNS TABLE(defect_id text, category text, status text, observed text, blocker text)
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.defect_id,
         r.category,
         coalesce(p.verdict, r.status)                                            as status,
         case when p.probe_id is null then r.observed
              else p.observed || ' [§8 probe ' || p.probe_id
                   || coalesce(' · HTTP ' || p.http_status::text, '')
                   || ' · executed ' || to_char(p.ran_at at time zone 'utc','YYYY-MM-DD HH24:MI') || 'Z]'
         end                                                                      as observed,
         -- The nine §8 defects with no probe mapping keep their specific mechanism text, but the
         -- prefix is corrected: "SECTION 8 NOT BUILT" became false on 19 Aug 2026 when the seven
         -- probes ran. Leaving it would be a blocker that lies about why it is a blocker — the
         -- reader would conclude the capability is missing when it exists and simply does not
         -- reach this case. The replace is a no-op on the 29 non-§8 NOT_RUN rows.
         case when p.probe_id is not null then null
              else replace(r.blocker,
                     'SECTION 8 NOT BUILT — ',
                     'SECTION 8 WAS EXECUTED 2026-08-19 AND DOES NOT REACH THIS CASE — ')
         end                                                                      as blocker
    from public.fn_phase_d_run_injected_defects() r
    left join public.phase_d_section8_defect_map m on m.defect_id = r.defect_id
    left join public.phase_d_section8_probe_result p
           on p.probe_id = m.probe_id and p.verdict <> 'NOT_RUN'
$function$
