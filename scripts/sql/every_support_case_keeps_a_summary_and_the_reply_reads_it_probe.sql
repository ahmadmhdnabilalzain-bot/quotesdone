-- every_support_case_keeps_a_summary_and_the_reply_reads_it_probe.sql — a PURE probe: it always raises CHK<<...>>, so every
-- row it writes rolls back. Assigned: customer_support / it_engineer (ruling 1635). Its subject is a ZZ DEMO person at a
-- reserved .invalid address, so it cannot reach anyone; real cases are counted before and after.
-- Proves: a new case opens; a summary is written as version 1 and kept in the version table; a stale writer is refused;
-- "continue" makes that case the newest open one; the open-case list shows the summary; a case of another person is refused.
do $probe$
declare
  v_email text := 'zz-demo-case-probe-' || txid_current() || '@example.invalid';
  v_real bigint := (select count(*) from public.support_case);
  v_open jsonb; v_prof bigint; v_a jsonb; v_b jsonb; v_w jsonb; v_stale jsonb; v_cont jsonb; v_other jsonb;
begin
  v_open := public.fn_support_open_cases('unknown', null, v_email, null);
  v_prof := (v_open ->> 'profile')::bigint;
  if v_prof is null or jsonb_array_length(v_open -> 'cases') <> 0 then raise exception 'CHK<<PROBE FAILED: a new person should have no case: %>>', v_open; end if;
  v_a := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO my windows quote', 'en');
  v_b := public.fn_support_case_route(v_prof, 'new', null, 'whatsapp', 'ZZ DEMO a different matter: my invoice', 'en');
  v_w := public.fn_support_case_summary_write(v_a ->> 'case_ref', 0,
    '{"asked":"a quote for 14 windows","said_or_did":"asked for sizes","promised":[{"what":"send the quotes when they arrive","by":null}],"open":["sizes"]}',
    'ASKED: a quote for 14 windows', 'ZZ DEMO windows quote', 'customer_support', 'probe');
  v_stale := public.fn_support_case_summary_write(v_a ->> 'case_ref', 0,
    '{"asked":"x","said_or_did":"y","promised":[],"open":[]}', 'stale', 'stale', 'customer_support', 'probe');
  v_cont := public.fn_support_case_route(v_prof, 'continue', v_a ->> 'case_ref', 'email', 'ZZ DEMO about the windows');
  v_other := public.fn_support_case_route(v_prof + 1000000, 'continue', v_a ->> 'case_ref', 'email', 'ZZ DEMO');
  v_open := public.fn_support_open_cases('unknown', null, v_email, null);
  if not (v_w ->> 'ok')::boolean or (v_w ->> 'version')::int <> 1 then raise exception 'CHK<<PROBE FAILED: write %>>', v_w; end if;
  if (v_stale ->> 'reason') is distinct from 'stale' then raise exception 'CHK<<PROBE FAILED: a stale writer was not refused: %>>', v_stale; end if;
  if (select count(*) from public.support_case_summary_version v join public.support_case c using (case_id) where c.case_ref = v_a ->> 'case_ref') <> 1 then
    raise exception 'CHK<<PROBE FAILED: the version was not kept>>';
  end if;
  if not (v_cont ->> 'ok')::boolean or (v_other ->> 'ok')::boolean then raise exception 'CHK<<PROBE FAILED: continue % / another person %>>', v_cont, v_other; end if;
  if v_open -> 'cases' -> 0 ->> 'case_ref' <> v_a ->> 'case_ref' or v_open -> 'cases' -> 0 ->> 'summary_text' <> 'ASKED: a quote for 14 windows'
     or jsonb_array_length(v_open -> 'cases') <> 2 then
    raise exception 'CHK<<PROBE FAILED: the continued case is not first with its summary: %>>', v_open;
  end if;
  if (select count(*) from public.support_case) <> v_real + 2 then raise exception 'CHK<<PROBE FAILED: other cases changed>>'; end if;
  raise exception 'CHK<<PROBE OK: two cases for one person, summary v1 kept, stale refused, continue moves % first>>', v_a ->> 'case_ref';
end
$probe$;
