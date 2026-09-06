// Append the fixture-factory change to O13: the quotation_comparison stage states its publication.
import { q } from './q.mjs';
import { appendFileSync } from 'node:fs';

let src = (await q(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  and n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`))[0].prosrc;

const FIND = `    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));`;

const REPL = `    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id';
      -- O13. THE COMPARISON STATES ITS PUBLICATION. quote_comparisons.publication_state defaults to
      -- DRAFT on purpose -- a row written by a path that does not know about publication must be
      -- invisible to a customer rather than visible -- and this factory was such a path, so BR-019
      -- and GATE-018 refused every W14 and W15 drive on a comparison nobody had published. The
      -- workflows those steps model are reading a comparison that IS published, so the fixture says
      -- so. published_at is stamped by a20_quote_comparison_publication_stamp rather than supplied,
      -- because a caller should not be trusted to date a state change it is making right now.
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'publication_state', 'PUBLISHED',
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));`;

const n = src.split(FIND).length - 1;
if (n !== 1) { console.error(`ANCHOR quotation_comparison: matched ${n}`); process.exit(1); }
src = src.replace(FIND, REPL);

appendFileSync('scripts/sql/phase_d_o13_a_package_identified_two_ways_and_a_comparison_nobody_published.sql',
  `\nCREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_scenario(p_input jsonb)\n`
  + ` RETURNS jsonb\n LANGUAGE plpgsql\n SET search_path TO 'public', 'pg_temp'\nAS $function$`
  + src + '$function$;\n');
console.log('appended fixture factory to O13');
