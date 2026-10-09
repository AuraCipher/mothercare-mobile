import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile/core/media/media_store.dart';
import 'package:mobile/features/chat/data/chat_media_download.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

final Uint8List jpegBytes = _bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00]);
final Uint8List pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);
final Uint8List gifBytes = _bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
final Uint8List webpBytes = _bytes([
  0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00,
  0x57, 0x45, 0x42, 0x50, 0x56, 0x38, 0x20, 0x20,
]);
final Uint8List m4aBytes = _bytes([
  0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
  0x4D, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
]);
final Uint8List mp4Bytes = _bytes([
  0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
  0x6D, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00,
]);
final Uint8List pdfBytes = _bytes(utf8.encode('%PDF-1.7\n%EOF'));
final Uint8List mp3Bytes = _bytes([0xFF, 0xFB, 0x90, 0x00]);

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('mcs_media_save');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  tearDownAll(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  group('parseContentDispositionFileName', () {
    test('parses RFC 5987 filename*', () {
      expect(
        parseContentDispositionFileName("inline; filename*=UTF-8''IMG_0123.jpg"),
        'IMG_0123.jpg',
      );
    });

    test('decodes percent-encoded RFC 5987 filename', () {
      expect(
        parseContentDispositionFileName(
          "attachment; filename*=UTF-8''My%20Photo%20%281%29.png",
        ),
        'My Photo (1).png',
      );
    });

    test('parses quoted plain filename', () {
      expect(
        parseContentDispositionFileName('inline; filename="report.pdf"'),
        'report.pdf',
      );
    });

    test('parses unquoted plain filename', () {
      expect(
        parseContentDispositionFileName('inline; filename=voice.m4a'),
        'voice.m4a',
      );
    });

    test('returns null for missing or empty header', () {
      expect(parseContentDispositionFileName(null), isNull);
      expect(parseContentDispositionFileName(''), isNull);
      expect(parseContentDispositionFileName('inline'), isNull);
    });
  });

  group('sniffMime', () {
    test('jpeg / png / gif / webp', () {
      expect(sniffMime(jpegBytes), 'image/jpeg');
      expect(sniffMime(pngBytes), 'image/png');
      expect(sniffMime(gifBytes), 'image/gif');
      expect(sniffMime(webpBytes), 'image/webp');
    });

    test('ftyp brands: m4a vs mp4', () {
      expect(sniffMime(m4aBytes), 'audio/mp4');
      expect(sniffMime(mp4Bytes), 'video/mp4');
    });

    test('pdf / zip / mp3 / empty', () {
      expect(sniffMime(pdfBytes), 'application/pdf');
      expect(sniffMime(_bytes([0x50, 0x4B, 0x03, 0x04, 0x00])), 'application/zip');
      expect(sniffMime(mp3Bytes), 'audio/mpeg');
      expect(sniffMime(Uint8List(0)), isNull);
    });
  });

  group('extensionForMime', () {
    test('canonical extensions (jpeg maps to jpg, never jpeg)', () {
      expect(extensionForMime('image/jpeg'), 'jpg');
      expect(extensionForMime('image/png'), 'png');
      expect(extensionForMime('image/webp'), 'webp');
      expect(extensionForMime('audio/mp4'), 'm4a');
      expect(extensionForMime('application/pdf'), 'pdf');
      expect(extensionForMime('image/svg+xml'), 'svg');
      expect(extensionForMime(''), isNull);
      expect(extensionForMime('application/octet-stream'), 'bin');
    });
  });

  group('mediaStoreMimeFor', () {
    test('prefers the extension of the visible file name', () {
      expect(mediaStoreMimeFor(fileName: 'IMG_1.jpg'), 'image/jpeg');
      expect(mediaStoreMimeFor(fileName: 'IMG_1.webp'), 'image/webp');
      expect(mediaStoreMimeFor(fileName: 'clip.mp4'), 'video/mp4');
    });

    test('falls back to magic bytes, then declared mime', () {
      expect(mediaStoreMimeFor(fileName: 'photo', bytes: jpegBytes), 'image/jpeg');
      expect(
        mediaStoreMimeFor(fileName: 'photo', declaredMime: 'image/png'),
        'image/png',
      );
      expect(mediaStoreMimeFor(fileName: 'photo'), 'application/octet-stream');
    });
  });

  group('resolveDownloadFileName', () {
    test('Content-Disposition original name beats everything (webp bytes, jpg name)', () {
      expect(
        resolveDownloadFileName(
          contentDisposition: "inline; filename*=UTF-8''Holiday%20photo.jpg",
          bytes: webpBytes,
        ),
        'Holiday photo.jpg',
      );
    });

    test('synthesizes extension from sniffed bytes when no header', () {
      expect(
        resolveDownloadFileName(contentDisposition: null, bytes: jpegBytes),
        'photo.jpg',
      );
      expect(
        resolveDownloadFileName(contentDisposition: null, bytes: webpBytes),
        'photo.webp',
      );
      expect(
        resolveDownloadFileName(contentDisposition: null, bytes: m4aBytes),
        'voice.m4a',
      );
    });
  });

  group('saveChatMediaUrls', () {
    late List<MethodCall> channelCalls;

    setUp(() {
      channelCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MediaStore.channel, (call) async {
        channelCalls.add(call);
        return 'content://media/external/images/media/1';
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MediaStore.channel, null);
      });
    });

    test('image goes through media store with original name; pdf stays private', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/img')) {
          return http.Response.bytes(
            webpBytes,
            200,
            headers: {
              'content-type': 'image/webp',
              'content-disposition': "inline; filename*=UTF-8''original_photo.jpg",
            },
          );
        }
        return http.Response.bytes(
          pdfBytes,
          200,
          headers: {
            'content-type': 'application/pdf',
            'content-disposition': 'inline; filename="minutes.pdf"',
          },
        );
      });

      final report = await saveChatMediaUrls(
        urls: [
          'http://127.0.0.1:9/img',
          'http://127.0.0.1:9/doc',
        ],
        authToken: 'token',
        client: client,
      );

      expect(report.allSaved, isTrue);
      expect(report.savedCount, 2);

      // Image: registered through the channel with the real uploaded name
      // and the extension of that name (jpg, not the transcoded webp).
      expect(channelCalls, hasLength(1));
      final call = channelCalls.single;
      expect(call.method, 'saveMedia');
      expect(call.arguments['fileName'], 'original_photo.jpg');
      expect(call.arguments['mimeType'], 'image/jpeg');

      // Document: app-private chat_downloads copy, no channel call.
      final private = report.saved.firstWhere((f) => !f.isPublic);
      expect(private.fileName, 'minutes.pdf');
      expect(File(private.path).existsSync(), isTrue);
    });

    test('temp files are cleaned up after the media store save', () async {
      final client = MockClient((_) async {
        return http.Response.bytes(
          pngBytes,
          200,
          headers: {
            'content-type': 'image/png',
            'content-disposition': 'inline; filename="pic.png"',
          },
        );
      });

      final report = await saveChatMediaUrls(
        urls: ['http://127.0.0.1:9/pic'],
        authToken: 'token',
        client: client,
      );

      expect(report.allSaved, isTrue);
      expect(channelCalls, hasLength(1));
      final sourcePath = callArgumentsPath(channelCalls.single);
      expect(File(sourcePath).existsSync(), isFalse,
          reason: 'temp download should be removed after save');
    });
  });
}

String callArgumentsPath(MethodCall call) => (call.arguments as Map)['path'] as String;
