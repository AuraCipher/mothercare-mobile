import 'dart:io';
import 'dart:typed_data';

/// Bounded range reads for resumable upload. Never loads the whole file:
/// each call opens the file, seeks to [offset], reads at most [length]
/// bytes, and closes it — memory stays proportional to one protocol chunk.
class ChunkReader {
  const ChunkReader();

  /// File size in bytes. Throws [FileSystemException] when unreadable.
  Future<int> fileLength(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      rethrow;
    } catch (e) {
      throw FileSystemException('Cannot stat local file', file.path, OSError(e.toString()));
    }
  }

  /// Reads exactly [length] bytes at [offset].
  /// Throws [FileSystemException] when the file is missing/unreadable and
  /// [StateError] when the file shrank (fewer bytes than requested).
  Future<Uint8List> readRange(File file, int offset, int length) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
    } catch (e) {
      throw FileSystemException('Local file is no longer readable', file.path, OSError(e.toString()));
    }
    try {
      await raf.setPosition(offset);
      final out = BytesBuilder(copy: false);
      var remaining = length;
      while (remaining > 0) {
        final n = remaining > 65536 ? 65536 : remaining;
        final part = await raf.read(n);
        if (part.isEmpty) break;
        out.add(part);
        remaining -= part.length;
      }
      final bytes = out.toBytes();
      if (bytes.length != length) {
        throw StateError(
            'Local file changed during upload (wanted $length bytes at $offset, got ${bytes.length})');
      }
      return bytes;
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
  }
}
