import 'dart:convert';

/// Builds a JWT the mobile app can decode (signature is not verified client-side).
String buildFakeJwt({
  required String id,
  required String role,
  required String name,
  List<String> branchIds = const ['branch-demo-1'],
}) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final exp = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'id': id,
        'role': role,
        'name': name,
        'branchIds': branchIds,
        'exp': exp,
      }),
    ),
  );
  final sig = base64Url.encode(utf8.encode('e2e-test-signature'));
  return '$header.$payload.$sig';
}

String jsonResponse(Map<String, dynamic> body) => jsonEncode(body);
