import 'package:flutter/foundation.dart';
import '../models/worker_permissions.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// Owns the single, shop-wide `worker_permissions` row and every
/// "can the current user do X" check the UI needs.
///
/// The admin is never restricted by these flags — every `canX` getter below
/// short-circuits to `true` for [AppRole.admin]. Only a worker session is
/// actually gated by the loaded [WorkerPermissions].
///
/// [notifier] is loaded once at bootstrap (see AuthGate) and re-loaded
/// whenever the admin saves changes on the Permissions screen, so any
/// screen using [ValueListenableBuilder] on it (or just reading the
/// `canX` getters synchronously) reflects the latest configuration without
/// needing its own fetch.
class PermissionsService {
  PermissionsService._();
  static final PermissionsService instance = PermissionsService._();

  final ValueNotifier<WorkerPermissions> notifier =
      ValueNotifier<WorkerPermissions>(WorkerPermissions.defaults);

  bool get _isAdmin => AuthService.instance.currentRole == AppRole.admin;

  WorkerPermissions get current => notifier.value;

  /// Called once at app bootstrap (after the role is known) and again
  /// whenever the app wants a fresh read (e.g. pulling the Permissions
  /// screen open). Safe to call for both roles — admins load it too, purely
  /// so the Permissions screen has something to display and edit.
  Future<void> load() async {
    notifier.value = await SupabaseService.instance.getWorkerPermissions();
  }

  Future<void> save(WorkerPermissions permissions) async {
    await SupabaseService.instance.updateWorkerPermissions(permissions);
    notifier.value = permissions;
  }

  // ---------------- CATALOG ----------------
  bool get canViewCatalog => _isAdmin || current.catalogView;
  bool get canAddCatalog => _isAdmin || current.catalogAdd;
  bool get canModifyCatalog => _isAdmin || current.catalogModify;
  bool get canDeleteCatalog => _isAdmin || current.catalogDelete;

  // ---------------- PRODUCTS ----------------
  // canViewProduct is intentionally always true — see WorkerPermissions doc.
  bool get canViewProduct => true;
  bool get canAddProduct => _isAdmin || current.productAdd;
  bool get canModifyProduct => _isAdmin || current.productModify;
  bool get canDeleteProduct => _isAdmin || current.productDelete;

  // ---------------- VENTES (achats) ----------------
  // canViewVentes is intentionally always true — see WorkerPermissions doc.
  bool get canViewVentes => true;
  bool get canAddVentes => _isAdmin || current.ventesAdd;
  bool get canModifyVentes => _isAdmin || current.ventesModify;
  bool get canDeleteVentes => _isAdmin || current.ventesDelete;

  // ---------------- DEPENSES ----------------
  bool get canViewDepense => _isAdmin || current.depenseView;
  bool get canAddDepense => _isAdmin || current.depenseAdd;
  bool get canModifyDepense => _isAdmin || current.depenseModify;
  bool get canDeleteDepense => _isAdmin || current.depenseDelete;

  // ---------------- ANALYSE ----------------
  bool get canViewAnalyse => _isAdmin || current.analyseView;
}
