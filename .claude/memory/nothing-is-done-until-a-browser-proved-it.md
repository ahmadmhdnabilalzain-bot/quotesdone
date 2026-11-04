---
name: nothing-is-done-until-a-browser-proved-it
description: Founder rule 2 Nov 2026, ledger 1464-1465. Code or database proof is not done; a real browser on the live site is.
metadata:
  type: feedback
---
"Never consider yourself done when you test anything only through the code or production. It has to be by the browser."

**Why:** people use the browser. On 2 Nov the live customer sign-up crashed for every new customer (React #310, a hook below an early return) while every code check was green; only the browser walk caught it.

**How to apply:** prove on the live site with the workflows on main, started by hand: supplier-signup-real-email-walk.yml, customer-signup-walk.yml, site-crawl.yml, conversation-continuity.yml, wa-exchange-real.yml, supplier-document-walk.yml. State plainly what is not real (the SMS code cannot be read). Browser tools must not create accounts on the live site; the repository's Playwright workflows do it, with ZZ DEMO data and teardown.
