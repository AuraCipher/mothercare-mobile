import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/uploads/upload_diagnostics.dart';
import 'package:mobile/features/uploads/upload_task.dart';

void main() {
  test('diagnostics never carry tokens, paths, or bytes', () {
    final seen = <UploadDiagnostic>[];
    final logger = UploadLogger(sink: seen.add, enabled: true);
    logger.log(UploadDiagnostic(
      event: 'chunk',
      taskId: 'task-1',
      sessionId: 'sess-1',
      offset: 0,
      bytes: 5242880,
      chunkNumber: 1,
      errorKind: UploadErrorKind.timeout,
      message: 'hello',
    ));
    final text = seen.single.toString();
    expect(text, contains('task-1'));
    expect(text, contains('offset=0'));
    expect(text, isNot(contains('Bearer')));
    expect(text, isNot(contains('tok')));
  });

  test('redactPath keeps basenames only', () {
    expect(redactPath('/data/user/0/app/album/photo.jpg'), 'photo.jpg');
    expect(redactPath(r'C:\Users\bob\file.pdf'), 'file.pdf');
  });

  test('disabled logger drops everything', () {
    var called = false;
    final logger = UploadLogger(sink: (_) => called = true, enabled: false);
    logger.log(UploadDiagnostic(event: 'x', taskId: 't'));
    expect(called, isFalse);
  });
}
