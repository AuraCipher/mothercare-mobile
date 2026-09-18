import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/app_database.dart';
import 'package:mobile/features/uploads/upload_task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'upload_test_support.dart';

void main() {
  group('upload_tasks table', () {
    test('CRUD + idempotency dedupe + recoverable listing', () async {
      final store = await TestDb.openStore();
      final task = makeTask(taskId: 't1', localPath: '/tmp/a.bin', expectedSize: 10);
      await store.saveTask(task);
      expect((await store.getTask('user-1', 't1'))?.serverBytes, 0);

      await store.saveTask(task.copyWith(
        sessionId: 's1',
        serverBytes: 5,
        state: UploadTaskState.uploading,
      ));
      final reloaded = (await store.getTask('user-1', 't1'))!;
      expect(reloaded.sessionId, 's1');
      expect(reloaded.serverBytes, 5);

      // Same key → same logical upload (enqueue dedupe path).
      expect((await store.getTaskByKey('user-1', 'idem-key-1'))?.taskId, 't1');
      // Different user, same key → isolated.
      expect(await store.getTaskByKey('user-2', 'idem-key-1'), isNull);

      expect((await store.listRecoverable('user-1')).map((t) => t.taskId), ['t1']);
      await store.saveTask(reloaded.copyWith(state: UploadTaskState.completed, fileRecordId: 'f1'));
      expect(await store.listRecoverable('user-1'), isEmpty);

      await store.deleteTask('user-1', 't1');
      expect(await store.getTask('user-1', 't1'), isNull);
    });

    test('clearUser wipes upload tasks', () async {
      final store = await TestDb.openStore();
      await store.saveTask(makeTask(taskId: 't9', localPath: '/tmp/a.bin', expectedSize: 3));
      await AppDatabase.instance.clearUser('user-1');
      expect(await store.getTask('user-1', 't9'), isNull);
    });
  });

  group('schema migration v1 -> v2', () {
    test('upgradeSchema creates upload_tasks and preserves existing rows', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
                'CREATE TABLE kv_cache (cache_key TEXT PRIMARY KEY, category TEXT NOT NULL, user_id TEXT NOT NULL, payload TEXT NOT NULL, cached_at INTEGER NOT NULL)');
          },
        ),
      );
      addTearDown(db.close);
      await db.insert('kv_cache', {
        'cache_key': 'k',
        'category': 'c',
        'user_id': 'u',
        'payload': '{}',
        'cached_at': 1,
      });

      // Same step AppDatabase._open runs when oldVersion < 2.
      await AppDatabase.upgradeSchema(db, 1);

      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='upload_tasks'");
      expect(tables, hasLength(1));
      final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='upload_tasks'");
      expect(indexes.map((r) => r['name']),
          containsAll(['idx_upload_tasks_idem', 'idx_upload_tasks_state']));
      expect(await db.query('kv_cache'), hasLength(1));

      // Fresh v2 install also carries the table.
      final fresh = await databaseFactoryFfi.openDatabase(
        '${inMemoryDatabasePath}_fresh',
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: (db, version) => AppDatabase.createSchema(db),
        ),
      );
      addTearDown(fresh.close);
      final freshTables = await fresh.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='upload_tasks'");
      expect(freshTables, hasLength(1));
    });
  });
}
