import 'cached_envelope.dart';
import 'cache_constants.dart';
import 'session_storage.dart';
import 'sqlite_kv_cache.dart';

/// Offline snapshots for portal dashboards (fees, attendance, results).
class DashboardCacheStore {
  DashboardCacheStore._();

  static final DashboardCacheStore instance = DashboardCacheStore._();

  final SqliteKvCache _kv = SqliteKvCache.instance;
  final SessionStorage _session = SessionStorage();

  Future<void> save({
    required String key,
    required String category,
    required Map<String, dynamic> data,
  }) async {
    final userId = (await _session.readSession())?.payload.id;
    if (userId == null) return;
    await _kv.put(key: key, category: category, userId: userId, data: data);
  }

  Future<CachedEnvelope?> read(String key) => _kv.get(key);

  Future<Map<String, dynamic>?> readData(
    String key, {
    Duration ttl = CacheTtls.dashboard,
  }) async {
    final envelope = await read(key);
    if (envelope == null || envelope.isExpired(ttl)) return null;
    return envelope.data;
  }
}
