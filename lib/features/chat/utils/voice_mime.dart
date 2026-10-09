import 'dart:io';
import 'dart:typed_data';

/// Declared MIME type for a recorded voice upload.
///
/// The backend validates the declared type against magic-byte sniffing
/// (file-type@21 on ISO-BMFF `ftyp` brands) when the upload completes:
/// `M4A` → `audio/x-m4a`, `M4B`/`F4A`/`F4B` → `audio/mp4`, `3g*` →
/// `video/3gpp` (which then falls back to the `.m4a` extension mapping and
/// lands on `audio/x-m4a`), and every other brand — including Android's
/// `mp42` — → `video/mp4`. A declared top-level type that differs from the
/// sniffed one rejects the file, so the declaration is derived by reading
/// the brand from the file itself. That keeps the contract true on every
/// platform (iOS `M4A ` vs Android `mp42`) without touching the backend's
/// validation rules. `audio/mp4` and `audio/x-m4a` are both allowed tops
/// for purpose-scoped uploads, so either audio branch passes validation.
Future<String> voiceDeclaredMimeType(File file) async {
  Uint8List bytes = Uint8List(0);
  try {
    final raf = await file.open();
    try {
      bytes = await raf.read(16);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return 'audio/x-m4a'; // Unreadable header: mirror the server's ext fallback.
  }
  // ISO-BMFF: [size(4)]'ftyp'brand(4) — matches file-type's ftyp detection.
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 /* f */ &&
      bytes[5] == 0x74 /* t */ &&
      bytes[6] == 0x79 /* y */ &&
      bytes[7] == 0x70 /* p */) {
    final brand = String.fromCharCodes(bytes, 8, 12).trim();
    switch (brand) {
      case 'M4A':
        return 'audio/x-m4a';
      case 'M4B':
      case 'F4A':
      case 'F4B':
        return 'audio/mp4';
      default:
        if (brand.startsWith('3g')) {
          // Sniffs as video/3gpp (not allowed) → server falls back to the
          // .m4a extension mapping → audio/x-m4a; declare that top.
          return 'audio/x-m4a';
        }
        return 'video/mp4'; // file-type's default for unknown brands (mp42…)
    }
  }
  // No ftyp box: not ISO-BMFF. Recorder output always is, so this is a
  // defensive default aligned with the server's extension fallback.
  return 'audio/x-m4a';
}
