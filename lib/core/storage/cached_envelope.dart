import 'dart:convert';

class CachedEnvelope {
  const CachedEnvelope({required this.cachedAt, required this.data});

  final DateTime cachedAt;
  final Map<String, dynamic> data;

  bool isExpired(Duration ttl) => DateTime.now().difference(cachedAt) > ttl;

  static Map<String, dynamic> wrap(Map<String, dynamic> data) => {
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      };

  static CachedEnvelope? parse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(map['cachedAt'] as String? ?? '');
      final data = map['data'];
      if (cachedAt == null || data is! Map) return null;
      return CachedEnvelope(
        cachedAt: cachedAt,
        data: Map<String, dynamic>.from(data),
      );
    } catch (_) {
      return null;
    }
  }
}
