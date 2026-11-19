# The founder's kit for his own supplier network

Assigned: marketing, with sales_engineer for the sign-up. Written 19 Nov 2026 for founder ledger 1709: Ahmad
will message and call the UAE suppliers he knows himself, from his own number, about 20 to 100 people.
This file is the kit for that: a WhatsApp message and a call script in English and Arabic, a tracked link
for each person, and a way to see who registered.

## What is true today (production, 19 Nov 2026)

Every line in the messages below has to stay true against these figures.

| Fact | Figure |
|---|---|
| Real suppliers approved | 3 |
| Customer requests ever received | **0**. Buyers have not started sending requests. |
| Registration | Free for the first 1,000 suppliers, permanently. From the 1,001st, AED 1,000 a year. |
| Commission | None. The supplier keeps 100% of every job. The customer pays the 3% reveal fee. |
| Supplier referral links issued | 0 (`supplier_referral_code` is empty) |

Two things the messages must never say: that buyers are active or sending work, and that the supplier
will get jobs by a certain date. When a customer request arrives, update this table and the "honest"
line in each message.

## 1. Get one link per person

1. Write the list of people as `First name - Company`, one per line, for example `Khalid - Gulf Steel`.
   The label is for you only. The link carries a short code, not the name.
2. Give the list to a Claude session and ask for "founder network links for these names". The session
   runs:
   ```sql
   select public.fn_founder_network_links(array['Khalid - Gulf Steel', 'Omar - Coast Joinery']);
   ```
   It answers one English link and one Arabic link for each name. The same name always gets the same
   link, so asking twice is safe.
3. Send each person **his own** link, in the language he reads. A link forwarded to a friend still
   works, but it counts under the first person's name.

A link looks like this:
`https://quotesdone.com/ar/supplier?utm_source=founder&utm_medium=personal&utm_campaign=founder-network&utm_content=f3a9c1e07b`

**Which link to send.** For a one-to-one message or call, send the person's own link from this step.
The CEO's weekly reading (`fn_ceo_founder_network_reading`) also prints a general link,
`quotesdone.com/portal?join=1&utm_source=founder&utm_medium=whatsapp&utm_campaign=2026-11`. That one
is for a post or a group, where no single person is named. Both links carry `utm_source=founder`, so
the CEO's count includes registrations from either. Only the personal link shows the person's name in
the view in section 5.

## 2. The WhatsApp message

Send it one person at a time, not as a broadcast. Edit the first line so it sounds like you talking to
that person.

**If someone says no, or asks not to be contacted again:** stop, and tell a Claude session "remove
[name] from my network links". The session finds his code in `v_founder_network_signups` and runs
`select public.fn_founder_network_forget('<code>');`, which deletes his name and code. Then delete his
row from your sheet. Don't keep a note of him anywhere. (A link nobody registered through is also
deleted automatically 90 days after it was made.)

### English

> Hi [name], hope all is well.
>
> I've started a company called QuotesDone. It's a UAE platform where a customer posts what he needs and
> it goes only to suppliers who do that trade. You see the scope without the customer's details, and you
> send your quote from the portal.
>
> Registration is free for the first 1,000 suppliers, and there's no commission on any job you win. The
> customer pays the fee.
>
> To be straight with you: it's new, and customer requests haven't started yet. I'm signing up good
> suppliers first, so that when they do there are people I trust to price them. I'd like you to be one
> of them.
>
> It takes a few minutes. Keep your trade licence and company profile ready:
> [his link]
>
> Any question, call me on this number.

### العربية

> هلا [الاسم]، شحالك؟ إن شاء الله أمورك طيبة.
>
> أسّست شركة اسمها QuotesDone، منصة في الإمارات يرفع فيها العميل طلبه، ويوصل الطلب للموردين اللي
> يشتغلون في نفس المجال بس. تشوف المطلوب والكميات بدون بيانات العميل، وترسل عرض سعرك من البوابة.
>
> التسجيل مجاني لأول ألف مورد، وما في أي عمولة على أي شغل يترسّى عليك. العميل هو اللي يدفع الرسوم.
>
> وبصراحة وياك: المنصة جديدة، وطلبات العملاء ما بدت للحين. أسجّل الموردين الزينين أول، عشان لما تبدأ
> الطلبات يكون عندي ناس أثق فيهم يسعّرونها، وأبيك تكون منهم.
>
> التسجيل ياخذ دقايق، وجهّز الرخصة التجارية وملف الشركة:
> [رابطه]
>
> وأي سؤال، كلّمني على هالرقم.

## 3. The call script

Use it as a guide, not something to read out. Keep the call to about five minutes and send the link on
WhatsApp straight after, so he has it in writing.

### English

1. **Open.** "Hi [name], it's Ahmad. Have you got five minutes? I want to tell you about something I've
   started and ask for a favour."
2. **What it is.** "It's called QuotesDone. A customer in the UAE posts what he needs, with the
   quantities. It goes only to suppliers who do that trade. They quote from a portal, without seeing
   who the customer is until he chooses them."
3. **The honest part.** "It's new. Customer requests haven't started yet. I'm building the supplier
   side first, with people I know do good work, so that when requests come there's someone good to send
   them to."
4. **The ask.** "Would you register? It's free for the first thousand suppliers and there's no
   commission. I'll send you the link on WhatsApp now."
5. **Close.** "You'll need your trade licence and company profile. If anything in the sign-up is
   unclear, call me and I'll sort it."

**If he asks**

- *"What does it cost me?"* Nothing to register for the first 1,000 suppliers, and no commission. The
  customer pays a 3% reveal fee when he chooses a supplier. One rule: if a customer pays to reveal you,
  reply within 5 working days (we remind you after 3). If you stay silent, the customer gets back
  everything he paid, and you owe the amount refunded (the 3% reveal fee), the payment processor fee on
  it that we couldn't recover, an AED 500 administrative fee, and simple interest at 12% a year on that
  total from the due date, never compounded. If it stays unpaid, the official fees of recovering it
  too. New matches pause until it's settled. The full rule is on the supplier page and in the supplier
  terms.
- *"How much work will I get?"* "I can't promise a number. There are no requests yet. When they come,
  they go only to suppliers who confirmed that trade."
- *"Who are the customers?"* Companies and individuals anywhere in the UAE. Every trade except food and
  beverage.
- *"Do I have to pay to rank higher?"* No. Quotes are ranked on price, completeness and delivery, never
  on what a supplier pays.

### العربية

1. **البداية.** "هلا [الاسم]، معاك أحمد. فاضي خمس دقايق؟ أبي أكلمك عن شي بديته، وعندي طلب صغير منك."
2. **شو هي.** "اسمها QuotesDone. العميل في الإمارات يرفع اللي يحتاجه بالكميات، ويوصل الطلب للموردين اللي
   يشتغلون في هالمجال بس. المورد يقدّم عرض سعره من البوابة، وما يعرف مين العميل إلا لما العميل يختاره."
3. **بصراحة.** "المنصة جديدة، وطلبات العملاء ما بدت للحين. أبني جهة الموردين أول، مع ناس أعرف إن شغلهم
   زين، عشان لما تجي الطلبات يكون فيه أحد زين أوصّلها له."
4. **الطلب.** "تسجّل؟ التسجيل مجاني لأول ألف مورد، وما في عمولة. بطرّش لك الرابط على الواتساب الحين."
5. **الختام.** "بتحتاج الرخصة التجارية وملف الشركة. وإذا شي في التسجيل ما كان واضح، كلّمني وأنا أخلّصه لك."

**إذا سأل**

- *"كم يكلّفني؟"* التسجيل مجاني لأول ألف مورد، وما في عمولة. العميل يدفع رسوم كشف بنسبة 3% لما يختار
  المورد. وفي شرط واحد: إذا دفع العميل عشان يكشف بياناتك، ترد عليه خلال 5 أيام عمل، ونذكّرك بعد 3 أيام. وإذا ما رديت،
  يرجع للعميل كل اللي دفعه، ويصير عليك المبلغ اللي رجع له بالضبط (رسوم الكشف 3%)، ورسوم مزوّد الدفع عليه
  اللي ما قدرنا نستردها، ورسم إداري 500 درهم، وفائدة بسيطة 12% في السنة على هالمجموع من تاريخ الاستحقاق،
  وما تتراكم. وإذا ظل المبلغ ما انسدّ، تنضاف عليه الرسوم الرسمية لتحصيله. وتوقف الطلبات الجديدة عنك لين
  تسدّد. والشرط كامل مكتوب في صفحة الموردين وفي شروط الموردين.
- *"كم شغل بيجيني؟"* "ما أقدر أوعدك برقم. للحين ما في طلبات، ولما تبدأ توصل بس للموردين اللي أكدوا هالمجال."
- *"مين العملاء؟"* شركات وأفراد في كل الإمارات، وفي كل المجالات إلا الأغذية والمشروبات.
- *"لازم أدفع عشان أطلع فوق؟"* لا. العروض تترتب على السعر والاكتمال ومدة التوريد، مب على اللي يدفعه المورد.

## 4. What he sees when he opens the link

1. The supplier page, in the language of his link. He presses the button to open the supplier portal.
2. He verifies his email and mobile with a code each, then accepts the supplier terms.
3. He uploads a current trade licence and company profile. Each one is checked as it is saved, and he
   is told what to fix if anything is unclear.
4. He confirms the trades he actually does. That decides which requests reach him.

If he gets stuck, ask him for a screenshot of the step and pass it to a Claude session; the sales
engineer seat owns the sign-up.

## 5. See who registered

Ask a Claude session for "who registered from my network". It reads:

```sql
select contact, company_name, registered_at, licence_submitted_at, approval_status, approved_at
  from public.v_founder_network_signups
 where not is_demo
 order by registered_at desc nulls last, contact;
```

- A row with a company name means his company registered through his link.
- A row with no company means he has not registered yet. Follow up once after about three days.
- A row with no contact means someone registered with a founder tag whose code was never issued.

**Limit.** The link is remembered from the first QuotesDone link a browser opens. If he opened another
QuotesDone link earlier on the same phone, or his browser keeps nothing (some private windows), his
registration is not counted here. You will still recognise the company name in the new registrations.

## 6. The sheet to keep alongside

| Name - Company | Language | Messaged | Called | Answer | Registered (from the view) |
|---|---|---|---|---|---|
| Khalid - Gulf Steel | ar | 20 Nov | 21 Nov | will register | |

Built by: `scripts/sql/the_founder_has_a_tracked_link_for_each_supplier_he_knows.sql` (the links and the
view) and its probe `..._probe.sql`.
