import 'package:flutter/services.dart';

/// Thin wrapper over the app's `mcs.media_store` platform channel.
///
/// Saves a local file into the device's public collections so it is visible
/// to the system gallery / file apps:
///  * `image/*` → `Pictures/Mother Care/`
///  * `video/*` → `Movies/Mother Care/`
///  * anything else → `Download/`
///
/// Android uses MediaStore (Q+) or public dir + media scan (pre-Q); iOS
/// copies into the Photos library (images/videos) or the app's Documents
/// directory (visible in the Files app).
class MediaStore {
  MediaStore._();

  static const MethodChannel channel = MethodChannel('mcs.media_store');

  /// Saves the file at [path] under [fileName] and returns the destination
  /// (content URI on Android Q+, absolute path otherwise).
  static Future<String> save({
    required String path,
    required String mimeType,
    required String fileName,
  }) async {
    final saved = await channel.invokeMethod<String>('saveMedia', <String, dynamic>{
      'path': path,
      'mimeType': mimeType,
      'fileName': fileName,
    });
    if (saved == null || saved.isEmpty) {
      throw StateError('Media store save failed');
    }
    return saved;
  }
}
