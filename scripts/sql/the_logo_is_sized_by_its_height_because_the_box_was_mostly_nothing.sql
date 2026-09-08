-- THE LOGO IS SIZED BY ITS HEIGHT, BECAUSE THE BOX WAS MOSTLY NOTHING
--
-- The founder, 8 September 2026: "make the logo a bit bigger. in compare to the text in the
-- template its very small... not only email templates. everywhere from now it should [be] in the
-- same size of the text in terms of the height."
--
-- MEASURED, NOT ADJUSTED BY EYE. horizontal_OnDark_transparent.png is a 1859x460 box in which the
-- artwork occupies 1608x176 -- 38% of the height, with 153px of empty alpha above it and 131px
-- below. Sizing that box by WIDTH is why the logo looked wrong: at width 170 the box is 42px tall
-- and the visible wordmark is 16px. Body text is 15px. The logo was, to the pixel, the same height
-- as the paragraph under it, which is exactly what he was looking at.
--
-- Making the box bigger would have papered over it -- 62% of every increase goes into padding, and
-- the layout pays for space the logo does not use. So the padding is gone instead:
-- horizontal_OnDark_trimmed.png is 1612x180, 98% of its height artwork.
--
-- THE ARTWORK IS NOT ALTERED. brand.ts states the rule -- the founder's artwork is "never altered
-- here, only placed" -- and cropping empty alpha changes no pixel of the logo. The originals stay
-- in the kit untouched; these are derivatives under their own names, so which is which is obvious.
--
-- AND THE RULE IS NOW EXPRESSIBLE. With the padding gone the box height IS the artwork height, so
-- "the logo is this tall" finally means what it says, on email, on the web, in a PDF. Sizing by
-- width could never mean that: the same width gives a different visible logo for every asset,
-- depending on how much nothing it was drawn inside.

update public.app_secrets
   set value = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png'
 where key = 'email_logo_url';

insert into public.company_brand (key, "group", value, note, sort) values
 ('logo.sizing_unit', 'logo', 'HEIGHT, never width.',
  'A lockup is drawn inside a box that is mostly transparent, so a width tells you nothing about how big the logo looks. The trimmed lockups are 98% artwork, so their height is the artwork height and is the only number worth writing down.', 60),
 ('logo.lockup_trimmed_dark', 'logo', 'kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png',
  '1612x180, aspect 8.96:1. The supplied OnDark lockup with its empty alpha cropped away. No pixel of the artwork is changed; 280px of vertical padding and 247px of horizontal padding are removed so the box is the logo.', 61),
 ('logo.lockup_trimmed_light', 'logo', 'kit/05_Logo_Lockups/horizontal_OnLight_trimmed.png',
  '1612x180, aspect 8.96:1. The same crop applied to the OnLight lockup, so light and dark grounds size identically.', 62),
 ('logo.height_email', 'logo', '28px',
  'Beside 15px body text. Roughly twice the text height, which is what makes a masthead read as a masthead rather than a word in the paragraph. At 8.96:1 this is 251px wide, about 46% of the 540px content column.', 63),
 ('logo.height_ui', 'logo', '24px',
  'In an application header beside 14-16px navigation text. Same reasoning, tighter chrome.', 64),
 ('logo.height_document', 'logo', '20px',
  'On a PDF or an invoice, where the page furniture is smaller and the logo is a mark of origin rather than a masthead.', 65),
 ('logo.never_size_by_width', 'logo', 'Do not set width on a lockup and let the height follow.',
  'It is the same mistake in a different order: the width includes whatever padding the asset was drawn with, so two assets at the same width look nothing alike. Set the height, let the width follow from the aspect ratio, and never set both -- company_brand.logo.dont already forbids stretching.', 66)
on conflict (key) do update
  set value = excluded.value, "group" = excluded."group", note = excluded.note,
      sort = excluded.sort, updated_at = now();
