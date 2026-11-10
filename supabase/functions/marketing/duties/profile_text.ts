// The daily profile text push (split out of duties.ts, 9 Nov 2026; a pure move).
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { pushFacebook, pushWhatsapp, pushYoutube, VARIANTS } from '../profile_text.ts';
import { accessToken } from '../../_shared/marketing_social_oauth.ts';
import { metaPageToken } from '../../_shared/marketing_social_store.ts';
import { isolated, Skip } from './shared.ts';
import type { Duty } from './types.ts';

export const profileText: Duty = {
  name: 'profile_text',
  owner_seat: 'marketing',
  async run({ admin, sec, now }) {
    if (now.getUTCHours() !== 3 || now.getUTCMinutes() >= 30) return { due: false };
    if ((await sec('profile_text_push')) === 'off') return { due: true, held: 'app_secrets.profile_text_push is off' };
    const since = new Date(now.getTime() - 10 * 60_000).toISOString();
    const master = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const save = async (k: string, v: string) => { const { error } = await admin.from('app_secrets').upsert({ key: k, value: v }, { onConflict: 'key' }); if (error) throw new Error(error.message); };
    const { out, skipped, errors } = await isolated({
      async whatsapp() {
        const [ks, kk, from] = await Promise.all([sec('twilio_api_key_sid'), sec('twilio_api_key_secret'), sec('twilio_wa_from')]);
        if (!ks || !kk || !from) throw new Skip('no Twilio key or twilio_wa_from');
        return await pushWhatsapp(timedFetch, 'Basic ' + btoa(`${ks}:${kk}`), from, since);
      },
      async facebook() {
        const { data } = await admin.from('marketing_meta_page').select('page_id').limit(1).maybeSingle();
        if (!data?.page_id) throw new Skip('no Facebook page cached yet (marketing_meta_page)');
        const t = await metaPageToken(admin, timedFetch, 'facebook', data.page_id);
        if (!t) throw new Skip('no page token');
        return await pushFacebook(timedFetch, data.page_id, t);
      },
      async youtube() {
        const t = await accessToken(timedFetch, 'youtube', master, sec, save);
        if (!t) throw new Skip('youtube not connected');
        return await pushYoutube(timedFetch, t.access_token);
      },
    });
    if (errors.length) throw new Error(errors.join(' | ') + ' (' + JSON.stringify({ out, skipped }).slice(0, 300) + ')');
    return { due: true, ...out, skipped, manual: VARIANTS.filter((v) => v.api === 'manual').map((v) => v.platform + '.' + v.field) };
  },
};
