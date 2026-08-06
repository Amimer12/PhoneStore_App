import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

// Called by AuthService.confirmAdminPasswordReset({code, newPassword}).
// Delegates the actual check + password update to admin_reset_password(),
// a service-role-only Postgres function, so the verification logic and the
// write happen in one atomic transaction on the database side.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { code, new_password } = await req.json();

    if (typeof code !== 'string' || code.length !== 6 || typeof new_password !== 'string' || new_password.length < 4) {
      return new Response(JSON.stringify({ error: 'Requête invalide.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data, error } = await supabase.rpc('admin_reset_password', {
      p_code: code,
      p_new_password: new_password,
    });
    if (error) throw error;

    return new Response(JSON.stringify({ success: data === true }), {
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
