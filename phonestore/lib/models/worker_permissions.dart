/// Which of the 5 permission sections the admin can configure for the
/// worker role, and which action within a section.
///
/// There's no per-worker-account granularity in this app (workers don't
/// have individual logins — see AuthService), so this is a single, shop-wide
/// "what can a worker do" switchboard that the admin edits from the new
/// Permissions tab.
enum PermSection { catalog, product, ventes, depense, analyse }

enum PermAction { view, add, modify, delete }

/// Snapshot of the single `worker_permissions` row.
///
/// `productView` and `ventesView` are intentionally NOT settable — the
/// business rule is that a worker must always be able to see products and
/// sales, no matter what the admin configures. They're kept here as
/// constant `true` getters (rather than removed) so the rest of the app can
/// use the same uniform `WorkerPermissions.can(section, action)` check
/// everywhere instead of special-casing those two screens.
class WorkerPermissions {
  final bool catalogView;
  final bool catalogAdd;
  final bool catalogModify;
  final bool catalogDelete;

  final bool productAdd;
  final bool productModify;
  final bool productDelete;

  final bool ventesAdd;
  final bool ventesModify;
  final bool ventesDelete;

  final bool depenseView;
  final bool depenseAdd;
  final bool depenseModify;
  final bool depenseDelete;

  final bool analyseView;

  const WorkerPermissions({
    this.catalogView = false,
    this.catalogAdd = false,
    this.catalogModify = false,
    this.catalogDelete = false,
    this.productAdd = false,
    this.productModify = false,
    this.productDelete = false,
    this.ventesAdd = true,
    this.ventesModify = true,
    this.ventesDelete = true,
    this.depenseView = true,
    this.depenseAdd = true,
    this.depenseModify = true,
    this.depenseDelete = true,
    this.analyseView = false,
  });

  /// Locked "on" — always true for a worker, regardless of DB content.
  bool get productView => true;

  /// Locked "on" — always true for a worker, regardless of DB content.
  bool get ventesView => true;

  /// Matches the behaviour the app had before permissions existed:
  /// - Produits: read-only for workers (no add/modify/delete), but always
  ///   visible.
  /// - Ventes: full read/write for workers (that's how the old, ungated
  ///   achats screen behaved), always visible.
  /// - Dépenses: full read/write for workers (the old depenses screen had
  ///   no gating at all).
  /// - Catalogue: no access at all for workers (only the admin ever saw the
  ///   catalog-management icon).
  /// - Analyse: hidden for workers (the old bottom nav only added the tab
  ///   for admins).
  static const defaults = WorkerPermissions();

  factory WorkerPermissions.fromMap(Map<String, dynamic> map) => WorkerPermissions(
        catalogView: map['catalog_view'] as bool? ?? false,
        catalogAdd: map['catalog_add'] as bool? ?? false,
        catalogModify: map['catalog_modify'] as bool? ?? false,
        catalogDelete: map['catalog_delete'] as bool? ?? false,
        productAdd: map['product_add'] as bool? ?? false,
        productModify: map['product_modify'] as bool? ?? false,
        productDelete: map['product_delete'] as bool? ?? false,
        ventesAdd: map['ventes_add'] as bool? ?? true,
        ventesModify: map['ventes_modify'] as bool? ?? true,
        ventesDelete: map['ventes_delete'] as bool? ?? true,
        depenseView: map['depense_view'] as bool? ?? true,
        depenseAdd: map['depense_add'] as bool? ?? true,
        depenseModify: map['depense_modify'] as bool? ?? true,
        depenseDelete: map['depense_delete'] as bool? ?? true,
        analyseView: map['analyse_view'] as bool? ?? false,
      );

  /// Only the columns the admin can actually change — `product_view` and
  /// `ventes_view` don't exist as writable knobs (see class doc), so they're
  /// never sent back to the server.
  Map<String, dynamic> toMap() => {
        'catalog_view': catalogView,
        'catalog_add': catalogAdd,
        'catalog_modify': catalogModify,
        'catalog_delete': catalogDelete,
        'product_add': productAdd,
        'product_modify': productModify,
        'product_delete': productDelete,
        'ventes_add': ventesAdd,
        'ventes_modify': ventesModify,
        'ventes_delete': ventesDelete,
        'depense_view': depenseView,
        'depense_add': depenseAdd,
        'depense_modify': depenseModify,
        'depense_delete': depenseDelete,
        'analyse_view': analyseView,
      };

  WorkerPermissions copyWith({
    bool? catalogView,
    bool? catalogAdd,
    bool? catalogModify,
    bool? catalogDelete,
    bool? productAdd,
    bool? productModify,
    bool? productDelete,
    bool? ventesAdd,
    bool? ventesModify,
    bool? ventesDelete,
    bool? depenseView,
    bool? depenseAdd,
    bool? depenseModify,
    bool? depenseDelete,
    bool? analyseView,
  }) {
    return WorkerPermissions(
      catalogView: catalogView ?? this.catalogView,
      catalogAdd: catalogAdd ?? this.catalogAdd,
      catalogModify: catalogModify ?? this.catalogModify,
      catalogDelete: catalogDelete ?? this.catalogDelete,
      productAdd: productAdd ?? this.productAdd,
      productModify: productModify ?? this.productModify,
      productDelete: productDelete ?? this.productDelete,
      ventesAdd: ventesAdd ?? this.ventesAdd,
      ventesModify: ventesModify ?? this.ventesModify,
      ventesDelete: ventesDelete ?? this.ventesDelete,
      depenseView: depenseView ?? this.depenseView,
      depenseAdd: depenseAdd ?? this.depenseAdd,
      depenseModify: depenseModify ?? this.depenseModify,
      depenseDelete: depenseDelete ?? this.depenseDelete,
      analyseView: analyseView ?? this.analyseView,
    );
  }

  /// Uniform lookup used by [PermissionsService] — e.g.
  /// `perms.can(PermSection.depense, PermAction.delete)`.
  /// [PermAction.view] on [PermSection.product]/[PermSection.ventes] always
  /// returns true (see class doc); [PermSection.analyse] only understands
  /// [PermAction.view] and returns false for anything else.
  bool can(PermSection section, PermAction action) {
    switch (section) {
      case PermSection.catalog:
        switch (action) {
          case PermAction.view:
            return catalogView;
          case PermAction.add:
            return catalogAdd;
          case PermAction.modify:
            return catalogModify;
          case PermAction.delete:
            return catalogDelete;
        }
      case PermSection.product:
        switch (action) {
          case PermAction.view:
            return productView;
          case PermAction.add:
            return productAdd;
          case PermAction.modify:
            return productModify;
          case PermAction.delete:
            return productDelete;
        }
      case PermSection.ventes:
        switch (action) {
          case PermAction.view:
            return ventesView;
          case PermAction.add:
            return ventesAdd;
          case PermAction.modify:
            return ventesModify;
          case PermAction.delete:
            return ventesDelete;
        }
      case PermSection.depense:
        switch (action) {
          case PermAction.view:
            return depenseView;
          case PermAction.add:
            return depenseAdd;
          case PermAction.modify:
            return depenseModify;
          case PermAction.delete:
            return depenseDelete;
        }
      case PermSection.analyse:
        return action == PermAction.view && analyseView;
    }
  }
}
