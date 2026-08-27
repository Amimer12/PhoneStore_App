import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'permissions_service.dart';

/// The two actors in the app. Neither has a real email/password account —
/// both are Supabase Anonymous Sign-In sessions, distinguished only by the
/// `profiles.role` row the device claims for itself right after signing in.
enum AppRole { worker, admin }

/// Owns the current session/role and every auth-related call. UI screens
/// never talk to Supabase directly for auth — they go through here.
///
/// [roleNotifier] is the single source of truth the rest of the app reacts
/// to: AuthGate rebuilds whenever it changes, so signing in, signing out, or
/// switching role from anywhere in the widget tree "just works" without any
/// manual navigation plumbing.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final SupabaseClient _c = Supabase.instance.client;

  final ValueNotifier<AppRole?> roleNotifier = ValueNotifier<AppRole?>(null);
  final ValueNotifier<bool> bootstrapping = ValueNotifier<bool>(true);

  AppRole? get currentRole => roleNotifier.value;

  /// Called once at app start. Resumes whatever session supabase_flutter
  /// already persisted locally (if any) and figures out the matching role.
  /// If there's a session but somehow no profile row (shouldn't normally
  /// happen — claim_worker/claim_admin always write one), it signs the
  /// device out so the role-choice screen shows again rather than getting
  /// stuck in limbo.
  Future<void> bootstrap() async {
    bootstrapping.value = true;
    try {
      final session = _c.auth.currentSession;
      if (session == null) {
        roleNotifier.value = null;
        return;
      }
      final role = await _fetchOwnRole();
      if (role == null) {
        await _c.auth.signOut();
        roleNotifier.value = null;
      } else {
        // Load the worker-permissions snapshot before flipping roleNotifier
        // so HomeShell never renders a first frame with stale (default)
        // permissions — matters most for a worker device that reopens the
        // app after the admin changed something.
        await PermissionsService.instance.load();
        roleNotifier.value = role;
      }
    } finally {
      bootstrapping.value = false;
    }
  }

  Future<AppRole?> _fetchOwnRole() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _c.from('profiles').select('role').eq('id', uid).maybeSingle();
    final roleStr = row?['role'] as String?;
    if (roleStr == 'admin') return AppRole.admin;
    if (roleStr == 'worker') return AppRole.worker;
    return null;
  }

  Future<void> _ensureSession() async {
    if (_c.auth.currentSession == null) {
      await _c.auth.signInAnonymously();
    }
  }

  /// "Continuer en tant qu'employé" — no secret needed, just claims the
  /// worker role for this device's (new or existing) anonymous session.
  Future<void> continueAsWorker() async {
    await _ensureSession();
    await _c.rpc('claim_worker');
    await PermissionsService.instance.load();
    roleNotifier.value = AppRole.worker;
  }

  /// "Continuer en tant qu'administrateur" — the password is checked
  /// server-side, inside the same call that grants the role (see
  /// claim_admin() in the SQL migration), so there's no window between
  /// "verified" and "granted" a client could exploit.
  ///
  /// Returns true if the password was correct (role is now admin), false
  /// otherwise (role is unchanged).
  Future<bool> loginAsAdmin(String password) async {
    await _ensureSession();
    final ok = await _c.rpc('claim_admin', params: {'p_password': password}) as bool;
    if (ok) {
      await PermissionsService.instance.load();
      roleNotifier.value = AppRole.admin;
    }
    return ok;
  }

  /// Step 1 of "mot de passe oublié" — asks the server to generate a fresh
  /// 6-digit code and WhatsApp it to the shop's fixed admin number. The
  /// app never sees that number or the code itself.
  Future<void> requestAdminPasswordReset() async {
    final res = await _c.functions.invoke('admin-request-reset');
    if (res.status != 200) {
      final message = (res.data is Map) ? res.data['error'] as String? : null;
      throw Exception(message ?? "Impossible d'envoyer le code pour le moment.");
    }
  }

  /// Step 2 — verifies the code and sets the new password in one atomic
  /// server-side call, then immediately logs the device in as admin so the
  /// person doesn't have to re-type the password they just chose.
  Future<bool> confirmAdminPasswordReset({required String code, required String newPassword}) async {
    final res = await _c.functions.invoke(
      'admin-confirm-reset',
      body: {'code': code, 'new_password': newPassword},
    );
    final success = res.status == 200 && (res.data is Map) && res.data['success'] == true;
    if (!success) return false;
    return loginAsAdmin(newPassword);
  }

  /// Signs the device out entirely and drops back to the role-choice
  /// screen. Bound to the existing logout icon in the Produits app bar.
  Future<void> signOut() async {
    await _c.auth.signOut();
    roleNotifier.value = null;
  }
}
