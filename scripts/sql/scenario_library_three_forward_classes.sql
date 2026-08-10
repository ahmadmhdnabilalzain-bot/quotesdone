-- The Future Simulator is specified over four forward question classes. scenario_library held 12
-- scenarios covering exactly one of them (vendor cost shock, as key_supplier_leaves) — the other
-- three had never been written down, so the OS could not be asked them.
--
-- These are QUESTIONS with an expected behaviour, in the shape of the twelve already on file. They
-- carry no last_run and no last_result: none has been exercised yet and pretending otherwise would
-- be the fabrication. Each is grounded in something this company actually has — a reveal fee, two
-- paused Meta campaigns as the only paid channel, and a lead book that is Dubai-weighted.
insert into public.scenario_library (scenario_key, name, category, situation, expected_behaviour, departments, notes)
values
 ('reveal_fee_change', 'The reveal fee changes', 'commercial',
  'The price a buyer pays to reveal a supplier quote is raised or cut. Revenue per reveal moves one way and the number of buyers willing to reveal moves the other.',
  'Finance states the current fee and the reveal-to-quote conversion it is measured against, and refuses to answer on volume alone. Marketing supplies the demand side (inquiries and quote_to_reveal_pct), Procurement the supply side (quotes available to reveal). The answer names the break-even conversion at the new fee rather than a single revenue figure, and says explicitly if the platform has too few revealed quotes on file to project honestly.',
  array['finance','marketing','procurement'],
  'Added 2026-08-10. The platform has had exactly one revealed quote and it was a QA fixture, so the first honest answer here is likely to be a refusal to project. That is the correct answer, not a failure of the simulator.'),

 ('channel_failure', 'The paid acquisition channel stops producing', 'commercial',
  'Meta ads are the only paid acquisition channel and both campaigns are paused at AED 0 spend. The scenario asks what happens to inquiry volume when the channel that is supposed to supply it produces nothing — which is the state the company is in today.',
  'Marketing names the actual current contribution of the channel before projecting its loss, so a channel contributing zero cannot be reported as a risk of losing something. The answer distinguishes the paid channel from SEO and direct, quantifies inquiries_7d against target, and routes a funded-or-retired decision to the founder rather than recommending "launch and fund it" without naming the money.',
  array['marketing','exec'],
  'Added 2026-08-10. fn_marketing_ai recommended launching the campaign daily since 30 July without ever naming an amount; this scenario exists so the channel question is asked with the budget attached.'),

 ('geographic_expansion', 'Expansion to another emirate', 'strategy',
  'The company opens a second geography — Abu Dhabi — alongside its Dubai base. Suppliers, categories, trade licence rules and buyer demand all differ by emirate.',
  'Procurement reports supplier coverage per emirate from the lead book rather than in aggregate, and names the categories that would have no approved supplier in the new emirate. Legal states which UAE authority and licence activity govern the new geography and whether existing verification rules transfer. The answer refuses to project revenue for a geography with no inquiries on file, and returns the coverage gap as the finding instead.',
  array['procurement','legal','exec'],
  'Added 2026-08-10. leads carries city and emirate, so the coverage half of this question is answerable today; the demand half is not, and the scenario says so.')
on conflict (scenario_key) do nothing;
