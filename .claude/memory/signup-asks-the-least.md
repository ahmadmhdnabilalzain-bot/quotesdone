---
name: signup-asks-the-least
description: "Founder ruling 1672 of 12 Nov 2026: supplier sign-up asks the least. No 'pick your category', no typed company name: both are read from the trade licence and the company profile. Order: verify e-mail, verify WhatsApp or phone, accept the terms (copy kept with the IP address), then documents. A trading name is optional; legally the trade licence matters most."
metadata:
  type: feedback
  modified: 2026-11-12
---

**The founder, verbatim (12 Nov 2026, after registering a company of his own from his iPhone):**
*"there was something like pick your category. Let's not add that option because honestly, there are loads of options.
So it's going to be really, really hard to for someone to find out his field. So let these things be extracted
automatically from the company profile and the trade license. … The same applies for the name. So I want like the least
amount of work. Like I don't want it to be annoying as a sign-up process. So directly, the guy verifies his emails,
verify his WhatsApp or phone, then directly accepts the terms and conditions. We get the copy of that with the IP
address. … even the company name, he doesn't have to fill it. Like once he attaches trade license, the company name is
there. Now, whether his trademark name is different, we can keep that as an optional thing … It's not a must because
eventually legally we care about the trade license the most."*

**How to apply (the session's reading of his ruling, labelled as its own; only the quote above is his).**
- Before adding any field to registration, ask whether a document he already gives us, or a proof he already passed,
  carries the answer. If it does, read it (the model reads, [[the-llm-understands-code-only-checks]]) and show it back.
- The company is named by its licence (`licence_legal_name`), not by typing. `leads.company_name` is empty until then:
  every consumer of the name must cope with empty, and nobody is approved without a name.
- The session's own addition, not his ruling, reported to him the same evening and not objected to by the time this was
  written: one typed thing, the full name of the person accepting the agreement, because his
  own certificate showed only a first name.
- The signed agreement is a PDF in our template ([[every-document-is-a-pdf-in-our-template]]) with the acceptance time,
  IP address, version and text hash taken on the server, and a copy on Dropbox.
- Open, his to decide: the Dropbox supplier folder is "uncategorized" because the folder category matches catalogue
  slugs and nothing maps the trades we read to them.
