-- PROBE: EVERY SEAT STATES THE SUPPLIER AGREEMENT'S OWN CIRCUMVENTION FIGURES (16 Nov 2026, ceo).
--
-- Pure probe: no DDL; it always raises CHK<<...>>, so the one write it makes (case 2, a changed copy of the
-- agreement text) is rolled back. Run it on a LOCAL database only, after
-- every_seat_states_the_supplier_agreements_own_circumvention_figures.sql, with pages.legal_supplier_body seeded from
-- signedBody(legal.json['supplier-agreement'], '18') (byte-equal to production's row, md5 831fadd6...). Never on
-- production: a rolled-back write there holds the real row's lock (13 Nov 2026).
--
-- VERDICT: PROBE OK only if
--   1. with the published text, the company block every seat carries (fn_company_context(8000,'public')) states the
--      clause-24 sum and multiple THE TEXT prints (read here independently, from the clause-24 section alone) and the
--      24-month window, says the figures were read, and states no AED 15,000;
--   2. with a text whose clause-24 wording no longer matches, the block states NO circumvention figure and says it could
--      not be read (never a remembered figure).
-- On production's body before this file (md5 794c3178...) case 1 FAILS: the block says AED 15,000 and "did not match".
do $probe$
declare
  v_html text := (select html from public.pages where slug = 'legal_supplier_body');
  v_c24  text;
  v_aed  text; v_mult text; v_tail text;
  v_ctx  text; v_rule text; v_hdr text;
begin
  if v_html is null then
    raise exception 'CHK<<PROBE FAILED: pages.legal_supplier_body is missing - seed it from legal.json first>>';
  end if;
  -- clause 24 alone, as the agreement prints it, so a figure of another clause can never satisfy the probe
  v_c24  := regexp_replace(substring(v_html from '<h2>24\.(.*?)<h2>25\.'), '<[^>]+>', ' ', 'g');
  v_aed  := substring(v_c24 from 'AED ([0-9,]+) per incident');
  v_mult := substring(v_c24 from 'or ([a-z]+ \([0-9]+\)) times the fee');
  v_tail := substring(v_c24 from 'For ([0-9]+) months');
  if v_aed is null or v_mult is null or v_tail is null then
    raise exception 'CHK<<PROBE FAILED: clause 24 of the seeded text has no sum/multiple/window (% / % / %)>>', v_aed, v_mult, v_tail;
  end if;

  -- 1. the published text
  v_ctx  := public.fn_company_context(8000, 'public')::text;
  v_rule := substring(public.fn_company_hard_rules() from '4\. ANTI-CIRCUMVENTION:[^\n]*');
  v_hdr  := substring(public.fn_company_hard_rules() from '# THE FOUR HARD RULES[^\n]*');
  if position(('AED ' || v_aed || ' per incident OR ' || v_mult || ' times the fee') in v_ctx) = 0 then
    raise exception 'CHK<<PROBE FAILED: the company block does not state clause 24 (AED % / %): %>>', v_aed, v_mult, v_rule;
  end if;
  if position(('within ' || v_tail || ' months') in v_rule) = 0 then
    raise exception 'CHK<<PROBE FAILED: rule 4 does not state the % month window: %>>', v_tail, v_rule;
  end if;
  if v_ctx ~ 'AED 15,000 per incident' or v_hdr !~ 'read from the published Supplier Agreement' then
    raise exception 'CHK<<PROBE FAILED: the block still states AED 15,000 or says the text did not match: % | %>>', v_hdr, v_rule;
  end if;

  -- 2. a text whose clause-24 wording no longer matches (rolled back with the probe)
  update public.pages
     set html = replace(replace(v_html, 'agreed compensation of AED', 'compensation fixed at AED'),
                        'For 24 months from such introduction', 'During the protected period after such introduction')
   where slug = 'legal_supplier_body';
  v_rule := substring(public.fn_company_hard_rules() from '4\. ANTI-CIRCUMVENTION:[^\n]*');
  v_hdr  := substring(public.fn_company_hard_rules() from '# THE FOUR HARD RULES[^\n]*');
  if v_rule ~ 'AED [0-9]' or v_rule ~ 'times the fee' or v_rule ~ '[0-9]+ months' then
    raise exception 'CHK<<PROBE FAILED: an unreadable clause still states a figure: %>>', v_rule;
  end if;
  if v_rule !~ 'could not be read' or v_hdr !~ 'could NOT be read' then
    raise exception 'CHK<<PROBE FAILED: an unreadable clause is not named as unreadable: % | %>>', v_hdr, v_rule;
  end if;

  raise exception 'CHK<<PROBE OK: every seat states AED % per incident or % times the fee within % months, as clause 24 prints; an unreadable clause states no figure>>', v_aed, v_mult, v_tail;
end
$probe$;
