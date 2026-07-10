import 'dart:async';
import 'dart:io';

Stream<List<int>> fileUploadStream(File file, void Function(double progress) onProgress) async* {
  final total = await file.length();
  var sent = 0;
  await for (final chunk in file.openRead()) {
    sent += chunk.length;
    if (total > 0) onProgress(sent / total);
    yield chunk;
  }
}
