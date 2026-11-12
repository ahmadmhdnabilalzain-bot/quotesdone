// my_data_pdf — "Download my data" on both portals: the person's own data copy as a PDF in the QuotesDone template.
// The door and who may pass it: ./door.ts. The document: ./document.ts. The drawing: ../pdf_native/render.ts.
import { siteCors } from '../_shared/site_origins.ts';
import { observe } from '../_shared/observe.ts';
import { handle } from './door.ts';

Deno.serve(siteCors(observe('my_data_pdf', handle)));
