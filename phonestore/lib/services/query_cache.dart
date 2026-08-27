import 'dart:async';

/// A tiny generic cache used to keep the "chunked" product/achats screens
/// from re-issuing the same Supabase query twice.
///
/// Two things happen here that a plain `Map<String, T>` wouldn't give you:
///  1. Results are kept until explicitly invalidated, so re-opening a
///     category you already paged through, or scrolling back up, doesn't
///     re-hit the network.
///  2. While a fetch for a given key is in flight, a second caller asking
///     for the same key gets the SAME Future instead of firing a second,
///     redundant request — this is what actually guarantees "no duplicate
///     queries" when, say, a fast double-tap or two widgets rebuild at once
///     and both ask for the same page.
///
/// Deliberately not a package: the app's read patterns are simple enough
/// (a handful of named caches, invalidated on writes) that a dependency
/// would be overkill.
class QueryCache<T> {
  final Map<String, T> _values = {};
  final Map<String, Future<T>> _inFlight = {};

  /// Returns the cached value for [key] if present; otherwise calls
  /// [fetch] (once, even under concurrent callers) and caches the result.
  Future<T> getOrFetch(String key, Future<T> Function() fetch) {
    final cached = _values[key];
    if (cached != null) return Future.value(cached);

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final future = fetch().then((value) {
      _values[key] = value;
      _inFlight.remove(key);
      return value;
    }, onError: (e, st) {
      _inFlight.remove(key);
      throw e;
    });
    _inFlight[key] = future;
    return future;
  }

  /// True if [key] already has a resolved value sitting in the cache (not
  /// counting an in-flight fetch) — used when a caller wants to batch
  /// together several still-uncached keys into one network request before
  /// populating them individually (see getAchatsForDates).
  bool isCached(String key) => _values.containsKey(key);

  /// Drops one cached entry (e.g. a single page) without touching the rest.
  void invalidate(String key) {
    _values.remove(key);
    _inFlight.remove(key);
  }

  /// Drops every cached entry whose key starts with [prefix] — used when a
  /// write could affect many pages at once (e.g. any product write should
  /// drop every cached products page, since we don't know which page the
  /// changed row lives on).
  void invalidateWhere(bool Function(String key) test) {
    _values.removeWhere((k, _) => test(k));
    _inFlight.removeWhere((k, _) => test(k));
  }

  void clear() {
    _values.clear();
    _inFlight.clear();
  }
}
