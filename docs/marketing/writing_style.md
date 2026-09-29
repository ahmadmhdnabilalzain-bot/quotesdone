# How the marketing seat writes

Founder, instruction 722 (22 Sep 2026): the marketing seat is also business development. It writes articles
about QuotesDone and prepares two or three LinkedIn messages a day, and "no one should feel he is an agent;
replies extremely professional."

**Blog articles changed on 29 Sep 2026 (founder 1058, 1059).** A blog article is a trending MARKET topic tied to
the business (UAE construction, fit-out, MEP and the procurement trades: what people search for, seasonal and
regulatory news, the trades buyers ask for), never about QuotesDone and never naming a supplier. It cites its market
sources, and the grounding rule below applies to them. The CEO seat reviews every article against six criteria and
approves, asks for a revision or replaces the topic; the founder never approves one and is told only when one goes
live. At most one a week. The pipe: `scripts/sql/a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql`.

The rules below are enforced by code, not by this page:
`supabase/functions/_shared/marketing_style.ts` (the lint and the grounding check),
`supabase/functions/_shared/marketing_style_tells.json` (the phrase lists) and their tests. This page explains
them so a writer (the founder, Claude, or a future model behind the seat) can pass them the first time.

## Voice

- **Senior, courteous, concise.** Write as a founder writing to a peer in Gulf business: plain sentences,
  no hype, no pressure. One idea per sentence. A LinkedIn message is five short lines, not a pitch deck.
- **Formal Gulf Arabic, written, not translated.** The formal plural (كم) throughout; the brand stays
  `QuotesDone` in Latin letters. The register and the translation artefacts to avoid are in
  `scripts/checks/every_arabic_message_is_written_not_translated.test.mjs`.
- **Soft invitations.** Offer to show how it works; never push for a call, never set a deadline, never
  follow up more than once without a reply.
- **Say only what is true of the company.** Everything a message or an article claims must be in the
  company's own knowledge: the website FAQ (`src/content/marketing.json` faq), the service pages, the legal
  pages and `src/content/company.json`. No clients, statistics, savings or prices that are not there.

## What is refused (the lint)

| group | examples | why |
|---|---|---|
| cliche | "I hope this message finds you well", "I came across your profile", "touch base", "quick call" | the openers every automated message uses |
| ai_tell | "delve", "seamless", "cutting-edge", "in today's fast-paced", "unlock the power", "moreover," | words models overuse; a reader notices |
| unsupported_claim | "trusted by", "thousands of", "industry-leading", "save up to" | social proof the company cannot show |
| adjective_triplet | "fast, simple and transparent" | a list of three stock adjectives reads as generated copy |
| emoji, exclamation | any emoji; more than one "!" | not the register of a founder writing to a procurement head |
| em_dash_run | more than one "—" in a message or post | a machine rhythm in short texts (articles may use dashes as the blog does) |

The Arabic lists carry the same groups (for example "أتمنى أن تكون بخير", "نقلة نوعية", "بواسطة").

## What is refused (grounding)

An article may state **no number its cited sources do not contain**: a price, a percentage, a count, a year,
a licence number. The ingest reads each cited source from the repository and compares every digit run in the
article, English and Arabic (Arabic-Indic digits are read as the same numbers). A figure without a source is
refused at ingest; it is never "corrected later".

## LinkedIn: drafted by the seat, sent by the founder

LinkedIn's User Agreement (section 8.2) forbids bots, automated messaging and scraping, and its API gives an
ordinary application no member messaging and no connection list. A restriction would fall on the founder's
personal account. What was found on GitHub on 22 Sep 2026 and why none is used:

| tool (stars, licence) | what it does | verdict |
|---|---|---|
| stickerdaniel/linkedin-mcp-server (3.6k, Apache-2.0), eliasbiondo/linkedin-mcp-server (189, MIT) | MCP servers that read profiles and search people through a logged-in browser session | scraping a member session: breaks 8.2, risks the founder's account |
| gtm-api/linkedin-mcp (90, MIT), Linked-API/linkedin-skills (69, MIT) | hosted services that connect and message on your behalf | automated messaging through a third party holding the session |
| linvo-io/linvo-scraper (628, MIT), FujiwaraChoki/linkedin-bot (106, MIT), joeygoesgrey/Linkedln-Automation-Framework (25, MIT) | Selenium/GeckoDriver bots that post, connect and message | bots: breaks 8.2 |
| moaljumaa/linki (144), DigiHold/LinkedGrow (32, AGPL-3.0), alexey-pelykh/lhremote (14, AGPL-3.0) | self-hosted outreach sequencers, LinkedHelper remote control | automated sequences on a member account; AGPL adds licence obligations |
| FarzamHejaziK/claude-linkedin-assistant (220, MIT) | Claude workspace that sends first messages through a browser | the same automation, driven by a model |
| linkedin-developers/linkedin-api-python-client (269, official) | official client for LinkedIn's REST APIs | compliant, but the APIs it reaches do not include member messaging; company-page posting is already covered by Postiz (#834) |

**No compliant automated send route exists for member-to-member messages.** The only sanctioned automated
channels are company-page posts (Community Management API, reached through Postiz) and paid Sponsored
Messaging (Message Ads, bought through Campaign Manager, not a personal message). So the seat drafts, the
founder sends from his own account, and one tap records what happened.

## The daily routine

1. People are researched from **public sources only** (company websites, public directories, press). Each has
   the URLs they were found on. LinkedIn is never scraped; a person whose only source is LinkedIn is refused.
2. Each Dubai morning the seat drafts messages for the next two or three people: a message for a connection
   and a connection note (at most 300 characters) for someone not yet connected. The only personal line is a
   cited sentence about the person's **company**.
3. The founder receives the list by email (only while `marketing_golive` is true), sends each by hand, and taps
   its link: sent, replied (paste the reply: the seat drafts the follow-up), converted, or not interested
   (never contacted again).
