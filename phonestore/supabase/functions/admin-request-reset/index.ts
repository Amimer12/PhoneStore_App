import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { sendWhatsAppCode } from '../_shared/whatsapp.ts';

// Called by AuthService.requestAdminPasswordReset() — no request body needed.
// Generates a 6-digit code, stores only its bcrypt hash (via the
// admin_create_reset_code RPC, service-role only), and sends the plain code
// to the shop's fixed WhatsApp number. The code itself never leaves this
// function — not returned to the client, not logged.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Simple cooldown: don't let someone spam-trigger WhatsApp sends. Only
    // block if a code was created in the last 60s AND hasn't expired yet —
    // admin_create_reset_code() itself immediately overwrites/expires the
    // previous one otherwise.
    const { data: existing } = await supabase
      .from('admin_reset_codes')
      .select('created_at')
      .eq('id', 1)
      .maybeSingle();

    if (existing?.created_at) {
      const secondsSince = (Date.now() - new Date(existing.created_at).getTime()) / 1000;
      if (secondsSince < 60) {
        return new Response(
          JSON.stringify({ error: `Veuillez patienter ${Math.ceil(60 - secondsSince)}s avant de redemander un code.` }),
          { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    const code = Array.from({ length: 6 }, () => Math.floor(Math.random() * 10)).join('');

    const { error: rpcError } = await supabase.rpc('admin_create_reset_code', { p_code: code });
    if (rpcError) throw rpcError;

    await sendWhatsAppCode(code);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `${e instanceof Error ? e.message : e}` }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
