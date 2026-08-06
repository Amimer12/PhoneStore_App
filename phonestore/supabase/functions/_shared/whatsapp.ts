// Sends the reset code over WhatsApp via Meta's WhatsApp Cloud API
// (free tier covers a generous number of conversations/month — no Twilio
// or paid SMS gateway involved).
//
// This template takes TWO body variables, in this order:
//   {{1}} = the admin's name (fixed — set once as WHATSAPP_ADMIN_NAME)
//   {{2}} = the 6-digit code (generated fresh on every request)
//
// Required secrets (see README.md in this folder for how to set them):
//   WHATSAPP_TOKEN            permanent access token from Meta for Developers
//   WHATSAPP_PHONE_NUMBER_ID  the ID Meta assigns to YOUR sending number
//   WHATSAPP_SENDER_NUMBER    that same sending number, in E.164 (e.g. "+213551234567")
//                             — kept as its own secret purely so you always
//                             have a plain, readable number to compare
//                             against in the Meta dashboard; the API call
//                             itself addresses the number via
//                             WHATSAPP_PHONE_NUMBER_ID (Meta's API has no
//                             way to send "as" a raw phone string — every
//                             number you register with WhatsApp Business
//                             Platform gets an ID, and that ID is what the
//                             API call below actually uses).
//   WHATSAPP_TEMPLATE_NAME    name of the approved template, e.g. "whatsapp_template"
//   WHATSAPP_TEMPLATE_LANG    template language code, e.g. "fr" or "en_US"
//   WHATSAPP_ADMIN_NAME       the name to fill {{1}} with, e.g. "Karim"
//                             — a secret (not hardcoded) so you can change
//                             it later with one `supabase secrets set`
//                             command, same as the phone number below.
//   ADMIN_PHONE_NUMBER        the shop owner's WhatsApp number in E.164, e.g. "+213551234567"
//                             — the ONE thing you said you want to be able to
//                             change easily: it's a Supabase secret, so
//                             updating it is just `supabase secrets set
//                             ADMIN_PHONE_NUMBER=+213...` and it takes effect
//                             immediately, no app rebuild/resubmit needed.
export async function sendWhatsAppCode(code: string): Promise<void> {
  const token = Deno.env.get('WHATSAPP_TOKEN');
  const phoneNumberId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
  const senderNumber = Deno.env.get('WHATSAPP_SENDER_NUMBER'); // used for validation/error messages only
  const templateName = Deno.env.get('WHATSAPP_TEMPLATE_NAME') ?? 'whatsapp_template';
  const templateLang = Deno.env.get('WHATSAPP_TEMPLATE_LANG') ?? 'fr';
  const adminName = Deno.env.get('WHATSAPP_ADMIN_NAME');
  const adminPhoneNumber = Deno.env.get('ADMIN_PHONE_NUMBER');

  if (!token || !phoneNumberId || !senderNumber || !adminName || !adminPhoneNumber) {
    throw new Error(
      'WhatsApp is not configured (missing one of WHATSAPP_TOKEN / WHATSAPP_PHONE_NUMBER_ID / WHATSAPP_SENDER_NUMBER / WHATSAPP_ADMIN_NAME / ADMIN_PHONE_NUMBER secrets).',
    );
  }

  const body = {
    messaging_product: 'whatsapp',
    to: adminPhoneNumber,
    type: 'template',
    template: {
      name: templateName,
      language: { code: templateLang },
      components: [
        {
          type: 'body',
          parameters: [
            { type: 'text', text: adminName }, // {{1}}
            { type: 'text', text: code },      // {{2}}
          ],
        },
      ],
    },
  };

  const res = await fetch(`https://graph.facebook.com/v20.0/${phoneNumberId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`WhatsApp send failed (sender ${senderNumber} / to ${adminPhoneNumber}, ${res.status}): ${detail}`);
  }

  console.log(`WhatsApp reset code sent from ${senderNumber} to ${adminPhoneNumber} (name: ${adminName})`);
}
