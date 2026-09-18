import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/chunk_reader.dart';

import 'upload_test_support.dart';

void main() {
  late Directory dir;
  const reader = ChunkReader();
  const fiveMiB = 5 * 1024 * 1024;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chunk_reader_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('reads exact ranges without loading the whole file', () async {
    final file = await makeTempFile(dir, 'big.bin', patternBytes(fiveMiB * 2 + 7, 3));
    final first = await reader.readRange(file, 0, fiveMiB);
    expect(first.length, fiveMiB);
    expect(first[0], patternBytes(1, 3)[0]);
    final tail = await reader.readRange(file, fiveMiB * 2, 7);
    expect(tail.length, 7);
    expect(await reader.fileLength(file), fiveMiB * 2 + 7);
  });

  test('one-byte final remainder', () async {
    final file = await makeTempFile(dir, 'tiny.bin', patternBytes(11, 9));
    final tail = await reader.readRange(file, 10, 1);
    expect(tail.length, 1);
    expect(tail[0], patternBytes(11, 9)[10]);
  });

  test('missing file throws FileSystemException (permanent)', () async {
    final missing = File('${dir.path}/nope.bin');
    await expectLater(reader.fileLength(missing), throwsA(isA<FileSystemException>()));
    await expectLater(reader.readRange(missing, 0, 10), throwsA(isA<FileSystemException>()));
  });

  test('shrunk file throws StateError (do not send short chunks)', () async {
    final file = await makeTempFile(dir, 'shrink.bin', patternBytes(100, 1));
    await expectLater(reader.readRange(file, 90, 50), throwsStateError);
  });
}
