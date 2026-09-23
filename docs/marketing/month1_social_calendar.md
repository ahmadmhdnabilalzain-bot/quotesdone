# Month 1 social calendar: supplier recruitment (12 videos)

Owner: `marketing` seat. Founder instruction 865 (23 Sep 2026). The data the seat ingests is
`month1_social_calendar.json` in this folder: 60 posts (12 videos x 5 platforms), one record per post
with the storage path and sha256 of the video, the Dubai and UTC times, the English and Arabic captions,
hashtags, alt text, the tracked registration link and the reason for the slot. This page explains the
decisions. Nothing is scheduled in Postiz until the founder approves.

## What each video says (watched frame by frame, 23 Sep 2026)

All 12 files are 1080x1920 (9:16), 60 fps. 01-06 run 24 s, 07-12 run 28 s. On-screen text below, in order.

| # | Video | On-screen text | End card | Audience |
|---|---|---|---|---|
| 01 | Stop Chasing Suppliers | Stop chasing suppliers. Start choosing. / Describe it. Just once. (SPC flooring for a villa brief) / Compare quotes. Not guesswork. / Reveal one. Keep control. Post and compare for free. | "Your next project. Starts here." **Post your job free**, quotesdone.com | Customers |
| 02 | Big Plans | Big plans. Start with an idea. / Big ideas need the right connections (fit-out, electrical & MEP, landscaping, flooring). / One place. More possibilities. Connect your requirement with UAE suppliers. / From possibilities to your choice. | "Big plans. Start here." Discover QuotesDone, quotesdone.com | Customers (soft) |
| 03 | On Your Terms | Your project. Not your identity. / Share the brief. Keep your privacy. Your details are removed before suppliers see it. / Let suppliers focus on the job. / Every quote. Your decision. | "Sourcing, on your terms." Get to know QuotesDone, quotesdone.com | Customers (soft) |
| 04 | Behind the Check | A name is easy. A check matters. / Start with the licence: number, issuing authority, expiry. / Current documents. Expired licences stay out of matching. / Checked before you're connected. Not a quality guarantee. (business name, mobile, email, trade licence, company profile, signed terms) | "Confidence starts with the checks." Meet QuotesDone. Licence checks do not certify workmanship. | Both |
| 05 | Complete Before Compare | A quote should be complete. / Missing a detail? Back for completion. Incomplete quotations are held. / The supplier fills in what's missing. / Complete first. Compare next. Price, lead time, warranty, validity. | "Less back-and-forth. More clarity." Discover QuotesDone | Both |
| 06 | Stay in the Loop | Your project moves. So do you. / Updates come to you. On WhatsApp and email. / Less checking. More doing. / Stay in the loop. Keep your momentum. | "Your day. Still yours." Explore QuotesDone | Customers (soft) |
| 07 | The First 1000 | The first 1,000. A lasting advantage. / Not a trial. Free. Forever. The first 1,000 pay no membership subscription (AED 0 year one, year two, every year). / Your capabilities. Relevant inquiries. / First 1,000: AED 0. After that: membership, from registration 1,001. Same merit-based ranking. Early entry, not paid preference. | "Register early. Keep the advantage." Register your business, quotesdone.com/supplier. Supplier verification and agreement apply. | Suppliers |
| 08 | Beyond Your Contacts | A friend's contact is a starting point ("Who did you use?"). / Look beyond who you already know. / Not just a name. A quote you can assess (scope, price, timing, terms). / Compare options. Choose what fits. | "More perspective. Your choice." **Start your request**. Post and compare free. Reveal fees apply. | Customers |
| 09 | Your Business Belongs Here | Your business. Your opportunity. / Across UAE sectors. Beyond the usual trades. / Show what you do. Meet requests that fit. / More chances to be considered. Request volume and sales are not guaranteed. | "FIRST 1,000 SUPPLIERS. Join early. Subscription-free forever." Register your business, quotesdone.com/supplier. Food & beverage excluded. | Suppliers |
| 10 | You Dont Need to Be the Expert | Know what you need. Not every technical term. / Describe the outcome. We ask the questions. / Materials. Scope. The details that matter. / Understand the options. Not just the numbers. | "Less guesswork. More clarity." **Start with your requirement**. Post and compare free. Reveal fees apply. | Customers |
| 11 | Compete on Value | Your expertise. Not a paid position. / No featured suppliers. No paid ranking. / Technical fit. Scope. Delivery. Value. / Compete on your offer. Let the customer choose. | "Bring your expertise. Join the first 1,000." A permanent subscription waiver, not a ranking boost. Register your business, quotesdone.com/supplier. | Suppliers |
| 12 | Procurement with Perspective | Your supplier list can go further. / One inquiry. Relevant new options. / Align the scope. Top three in one report; every other quotation available. / The lowest number is not the whole story. | "More options. A clearer decision." **Submit your company request**. Post and compare free. Reveal fees apply. | Customers |

### What is wrong for month 1

No video states a false number, a supplier count or the old "20,400+ vetted suppliers". Video 07 matches
the Supplier Agreement (first 1,000 free permanently; subscription from the 1,001st); it does not print
the AED 1,000 figure, so the captions add it. But:

- **01, 08, 10 and 12 end on a customer call to action** ("Post your job free", "Start your request",
  "Start with your requirement", "Submit your company request"). Month 1 is supplier registration only.
  These four are in the calendar as **held**: each needs a 4-second supplier end card (Register your
  business, quotesdone.com/supplier) before it posts. If the re-edit is not in storage 48 hours before
  its slot, the slot re-runs a named supplier video instead (01 -> 07, 08 -> 04, 10 -> 09, 12 -> 11).
- **02, 03 and 06 speak to customers** with a soft end card. Nothing in them is false, so they run, and
  the caption turns them to the supplier: what the customer sees is why the work reaches you.
- 09's headline "Subscription-free forever" is qualified only by a small "FIRST 1,000 SUPPLIERS" label.
  Every caption states the 1,000 limit in words.
- The end cards print quotesdone.com; UAE visitors are served on quotesdone.ae. The caption links use
  `https://quotesdone.com/supplier` with UTM tags so the path on screen and the path in the link agree.

## Platforms (measured, not assumed)

`public.marketing_connection_check`, measured 22 Sep 2026 20:00 UTC: Postiz answers 200 and holds five
channels, all enabled, none needing a refresh: **instagram-standalone, facebook, linkedin-page, x,
youtube**. All five take 9:16 natively (Reels, Facebook Reels, LinkedIn vertical video, X video,
YouTube Shorts), so every video goes to every channel unchanged.

- TikTok: left out on the founder's ruling. Snapchat and Threads: not connected in Postiz, so not planned.
- **YouTube gap:** Postiz has YouTube, but `supabase/functions/_shared/marketing_channels.ts` publishes
  only `facebook, instagram, linkedin, x`. The 12 YouTube rows cannot go through the seat until
  `youtube` is added there (with a title setting, which Shorts require).
- **Media:** the masters are in the private bucket `marketing-media`. Postiz must receive each file
  through its upload endpoint (the seat already uploads images before posting); the private bucket is
  not to be made public. The sha256 in each record lets the upload be checked against the master.

## Order: the story a supplier walks through

| Week | Theme | Mon | Wed | Thu |
|---|---|---|---|---|
| 1 (28 Sep - 1 Oct) | Awareness: there is a place for you | 09 Your Business Belongs Here | 02 Big Plans | 11 Compete on Value |
| 2 (5 - 8 Oct) | Trust: how it treats you | 04 Behind the Check | 03 On Your Terms | 05 Complete Before Compare |
| 3 (12 - 15 Oct) | The offer | 07 The First 1000 | 12 Procurement with Perspective (held) | 06 Stay in the Loop |
| 4 (19 - 22 Oct) | Action: requests are coming | 08 Beyond Your Contacts (held) | 10 You Dont Need to Be the Expert (held) | 01 Stop Chasing Suppliers (held; falls back to 07) |

Why this order: a supplier first has to see that his trade belongs (09), that the work arrives from real
projects (02) and that he cannot be outbid by money (11). Before handing over a licence he needs to know
what is checked and why (04), that he is judged on the work (03) and how his quotation is treated (05).
Only then does the offer land (07), at the midpoint, when the audience knows what they are joining.
Weeks 3 and 4 show the buyer side, why requests will come, and the last slot closes on the offer again
if 01 is not re-edited.

## Timing: when, and the gap between posts

- **Days: Monday, Wednesday, Thursday.** 3 a week x 4 weeks = 12 videos, one video a day. Each video has
  24 to 96 hours alone before the next. No Friday (half day for government since 2022, prayer at midday);
  no Saturday or Sunday (the UAE business weekend since January 2022).
- **Same video on all five channels the same day, staggered** so each lands in its own peak:

| Platform | Dubai | UTC | Evidence |
|---|---|---|---|
| LinkedIn | 11:30 | 07:30 | Strong: Sprout Social's cross-brand data puts LinkedIn's peak Tue-Thu from late morning into the afternoon, local time. UAE agency guides agree (10:00-16:00). |
| Facebook | 13:00 | 09:00 | Strong: Sprout Social, midweek late morning and mid-afternoon. UAE guides cite a 12:00-14:00 lunch peak (convention). |
| X | 14:30 | 10:30 | Strong: Sprout Social, 12:00-18:00 Tue-Thu. |
| YouTube Shorts | 17:30 | 13:30 | Weak, convention: after-work commute. The Shorts feed serves a video for days, so the hour matters least. |
| Instagram | 19:30 | 15:30 | Medium: UAE-specific guides (agency data, not published datasets) put the weekday peak at 19:00-22:00 Dubai time. Sprout's global data favours afternoons; the evening is chosen for owners of small trading and contracting firms who browse after work. |

Strong evidence means a published dataset (Sprout Social, tens of thousands of accounts, local time).
The UAE guides are agency write-ups without published method and count as convention. Dubai has no
daylight saving, so the UTC times hold all month. After week 2 the seat should compare reach by hour in
Postiz analytics and move any platform whose window underperforms.

## Captions

- **English and Arabic** on Instagram, Facebook, LinkedIn and YouTube: UAE supplier owners and managers
  read in both, and Arabic-first owners of trading and contracting firms are a large part of the audience.
  **X is English only**: a bilingual body does not fit 280 characters.
- Arabic is formal Gulf Arabic, written not translated, in the plural of respect, with the brand in Latin
  letters, matching the supplier page (`supplierLanding` in `messages/ar.json`).
- Instagram has no clickable caption link: the caption says "link in bio" and names quotesdone.com/supplier;
  the bio link must carry the Instagram UTM. LinkedIn, Facebook, X and YouTube carry the tracked link.
- Hashtags: Instagram 5, LinkedIn 3, Facebook 2, X 1, YouTube 3 (with #Shorts). Few and specific.
- Every claim is from the Supplier Agreement or the supplier page: first 1,000 free permanently; AED 1,000
  a year from the 1,001st; no commission (the customer pays the 3% reveal fee); invited only for licensed
  activity; customer identity hidden until chosen; every quotation shown and the top three compared on
  price, completeness and delivery; all trades except food and beverage. No counts, no statistics.

Sources: [Sprout Social, best times to post on LinkedIn](https://sproutsocial.com/insights/best-times-to-post-on-linkedin/),
[Instagram](https://sproutsocial.com/insights/best-times-to-post-on-instagram/),
[all platforms](https://sproutsocial.com/insights/best-times-to-post-on-social-media/);
[Prism, best time to post in the UAE](https://www.prism-me.com/blog/best-time-to-post-on-social-media-2021);
[Meltwater, Instagram in the UAE](https://www.meltwater.com/en/blog/important-instagram-posting-insights);
[Khaleej Times, the new UAE weekend](https://www.khaleejtimes.com/uae/new-uae-weekend-today-is-the-last-working-sunday-for-many);
[Al Jazeera, 4.5-day week](https://www.aljazeera.com/economy/2021/12/7/uae-announces-changes-to-workweek-for-employees-of-govt-sector).
