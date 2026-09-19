import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/core/storage/app_database.dart';
import 'package:mobile/core/storage/sqlite_kv_cache.dart';

/// M9: kv-cache user isolation. Proves User B can never read User A's rows,
/// including the global-key overwrite case (kv PK is cache_key, so a second
/// user's put REPLACEs the row — scoped get must still refuse cross-reads).
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqliteKvCache.testMode = false;
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  test('distinct keys: cross-user reads return null', () async {
    final kv = SqliteKvCache.instance;
    await kv.put(key: 'ka', category: 'c', userId: 'userA', data: {'v': 'A'});
    await kv.put(key: 'kb', category: 'c', userId: 'userB', data: {'v': 'B'});

    expect((await kv.get('ka', userId: 'userA'))?.data['v'], 'A');
    expect((await kv.get('kb', userId: 'userB'))?.data['v'], 'B');
    expect(await kv.get('ka', userId: 'userB'), isNull);
    expect(await kv.get('kb', userId: 'userA'), isNull);
  });

  test('same global key overwritten by B: A must not see B data', () async {
    final kv = SqliteKvCache.instance;
    await kv.put(key: 'shared', category: 'c', userId: 'userA', data: {'v': 'A'});
    expect((await kv.get('shared', userId: 'userA'))?.data['v'], 'A');
    // B logs in on the same device; REPLACE overwrites the single row.
    await kv.put(key: 'shared', category: 'c', userId: 'userB', data: {'v': 'B'});
    expect((await kv.get('shared', userId: 'userA')), isNull);
    expect((await kv.get('shared', userId: 'userB'))?.data['v'], 'B');
  });

  test('deleteAllExceptUser purges prior users rows (kill-without-logout)', () async {
    final kv = SqliteKvCache.instance;
    await kv.put(key: 'pa', category: 'c', userId: 'userA', data: {'v': 'A'});
    await kv.put(key: 'pb', category: 'c', userId: 'userB', data: {'v': 'B'});
    // Simulates saveSession purge on B's login after A's kill-without-logout.
    await kv.deleteAllExceptUser('userB');
    expect(await kv.get('pa', userId: 'userA'), isNull);
    expect((await kv.get('pb', userId: 'userB'))?.data['v'], 'B');
  });
}
