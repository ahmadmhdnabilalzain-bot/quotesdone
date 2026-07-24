# Category-aware quote gate — FULL trade coverage (2026-07-24)

44 spec groups, 141 mandatory domain aspects. Every customer-facing trade category
(63 slugs across category_specs + category_agents) resolves to a spec group; none
unmapped. A quote is blocked from the customer until it states the mandatory domain
specs for its trade. Generic/empty quote text fails all 44 groups (verified).

Groups: security, fire, hvac, glazing, joinery, electrical, plumbing (deep, launch);
flooring, tiling, painting, gypsum, waterproofing, wallpaper, carpet, landscaping,
pools, solar, shade, roofing, insulation, steel, masonry, smarthome, avsystems,
networking, elevators, generators, interiordesign, signage, acrylic, cleaning, facade,
watertank, pestcontrol, movers, upholstery, handyman, acduct, fitout, mep, scaffolding,
demolition, shutters, general (catch-all).

Research-grounded in UAE authorities: Dubai Municipality, Dubai Civil Defence (DCD),
DEWA, SIRA, ESMA, Al Sa'fat, Shams Dubai (solar net-metering), IRATA (facade access).
Deep intake checklists authored for the 7 launch/example trades; quote gate universal.

Source of truth is the live DB; org-as-code/ mirrors category_quote_specs nightly.
